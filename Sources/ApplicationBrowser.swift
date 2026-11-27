import SwiftUI
import WebKit
import AppKit

@MainActor final class ApplicationBrowserSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var address = ""
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isFilling = false
    @Published private(set) var status = "请先登录并进入网申表单，再点击一键填写。"
    @Published private(set) var outcomes: [ApplicationFieldOutcome] = []
    @Published private(set) var error: String?
    @Published private(set) var preparedFieldCount = 0
    @Published private(set) var isPreparing = false
    @Published private(set) var adapterTitle = "通用适配"
    @Published private(set) var resumableSection: String?
    private let siteRuleStore: ApplicationSiteRuleStore
    private let recoveryStore: ApplicationJourneyRecoveryStore
    private var preparationTask: Task<Void, Never>?
    private var preparationID = UUID()
    private var preparationFacts: [ApplicationAutofillFact] = []
    private var preparationURL = ""
    private var factsProvider: (@MainActor (String) -> [ApplicationAutofillFact])?
    private struct PreparedField {
        var assignment: ApplicationFieldAssignment?
        var resolved: Bool
    }
    // Session memory only. Never write candidate answers or unanswered fields to disk.
    private var preparedFields: [String: PreparedField] = [:]
    private(set) var preparationModelCalls = 0
    private(set) var preparationSeconds = 0.0
    let viewport = ApplicationViewport()
    let webView: WKWebView
    private var task: Task<Void, Never>?
    private var navigationID = UUID()
    private var fillID = UUID()
    private let scriptWorld = WKContentWorld.world(name: "CareerAI.ApplicationAutofill")
    private var script: String?
    private var incompleteDetails: Set<String> = []
    private var intentionalNavigation = false
    private let decisionProvider: @MainActor (ApplicationJourneyAgent.Observation) async throws -> ApplicationJourneyAgent.Decision?
    private let semanticProvider: @MainActor ([ApplicationFormField], [ApplicationAutofillFact]) async throws -> [ApplicationFieldAssignment]
    struct Performance {
        var preparedAssignments = 0
        var scriptCalls = 0
        var mappingModelCalls = 0
        var decisionModelCalls = 0
        var cachedMappings = 0
        var repeatedMappingSkips = 0
        var transitionSeconds = 0.0
        var elapsedSeconds = 0.0
    }
    private(set) var performance = Performance()
    private let mappingCache: ApplicationFieldMappingCache
    private var pendingUpload: (url: URL, page: URL)?

    init(url: URL, scriptURL: URL? = nil, decisionProvider: (@MainActor (ApplicationJourneyAgent.Observation) async throws -> ApplicationJourneyAgent.Decision?)? = nil, semanticProvider: (@MainActor ([ApplicationFormField], [ApplicationAutofillFact]) async throws -> [ApplicationFieldAssignment])? = nil, mappingCache: ApplicationFieldMappingCache? = nil, siteRuleStore: ApplicationSiteRuleStore? = nil, recoveryStore: ApplicationJourneyRecoveryStore? = nil) {
        self.siteRuleStore = siteRuleStore ?? ApplicationSiteRuleStore()
        self.recoveryStore = recoveryStore ?? ApplicationJourneyRecoveryStore(file: scriptURL == nil ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("CareerAI-Demo/application-recovery-v1.json") : nil)
        self.mappingCache = mappingCache ?? ApplicationFieldMappingCache()
        self.semanticProvider = semanticProvider ?? { fields, facts in try await ApplicationAutofillPlanner.semanticPlan(fields: fields, facts: facts) }
        self.decisionProvider = decisionProvider ?? ApplicationJourneyAgent.choose
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Remote application pages receive no native script-message handlers.
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        if let scriptURL { script = try? String(contentsOf: scriptURL, encoding: .utf8) }
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setAccessibilityLabel("网申网站")
        viewport.start(webView)
        open(url)
    }
    static func validURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil && url.user == nil && url.password == nil
    }
    func open(_ url: URL) {
        guard Self.validURL(url) else { error = "仅支持有效的 HTTP 或 HTTPS 网申链接。"; return }
        cancelFill(); error = nil; address = url.absoluteString
        webView.load(URLRequest(url: url, timeoutInterval: 45))
    }
    func openAddress() {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text.contains("://") ? text : "https://" + text) else { error = "请输入完整网址。"; return }
        open(url)
    }
    func back() { cancelFill(); webView.goBack() }
    func forward() { cancelFill(); webView.goForward() }
    func reload() { cancelFill(); webView.reload() }
    func cancelFill() {
        if isFilling { status = "已停止，已填内容保留。再次点击一键填写可继续。" }
        intentionalNavigation = false; pendingUpload = nil; fillID = UUID(); task?.cancel(); task = nil; isFilling = false
        webView.callAsyncJavaScript("globalThis.__careerApplicationState = null;", in: nil, in: scriptWorld, completionHandler: nil)
    }
    func close() { stopPreparation(clear: true); factsProvider = nil; cancelFill(); viewport.stop(); webView.stopLoading() }

    func enablePreparation(facts: @escaping @MainActor (String) -> [ApplicationAutofillFact]) {
        factsProvider = facts
        viewport.start(webView)
        refreshAdapterState()
        restartPreparation()
    }
    func refreshPreparation() { stopPreparation(clear: true); refreshAdapterState(); restartPreparation() }
    private func recoveryKey(_ facts: [ApplicationAutofillFact]) -> String {
        ApplicationJourneyRecoveryStore.key(url: webView.url?.absoluteString ?? address, facts: facts, revision: siteRuleStore.revision)
    }
    private func refreshAdapterState() {
        guard let url = webView.url else { resumableSection = nil; return }
        if let rule = siteRuleStore.rule(for: url) {
            let name = rule.id == "moka" ? "Moka" : rule.id.hasPrefix("zhaopin") ? "智联" : rule.id
            adapterTitle = "\(name) 适配 · v\(rule.version)"
        } else { adapterTitle = "通用适配" }
        resumableSection = factsProvider.flatMap { recoveryStore.bookmark(for: recoveryKey($0(url.absoluteString)))?.section }
    }
    var canRollbackRules: Bool { siteRuleStore.canRollback }
    func importSiteRules() {
        guard !isFilling else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "选择 OfferFlow 站点适配规则 JSON 文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try siteRuleStore.install(url); refreshPreparation(); error = nil; status = "站点适配规则已更新。" }
        catch { self.error = error.localizedDescription }
    }
    func rollbackSiteRules() {
        guard !isFilling else { return }
        do { try siteRuleStore.rollback(); refreshPreparation(); error = nil; status = "已恢复上一版站点适配规则。" }
        catch { self.error = error.localizedDescription }
    }
    func resetRecovery() {
        guard !isFilling, let provider = factsProvider else { return }
        recoveryStore.clear([recoveryKey(provider(webView.url?.absoluteString ?? address))])
        resumableSection = nil; status = "已清除当前页面的恢复位置，下一次将从当前页面重新检查填写。"
    }
    private func stopPreparation(clear: Bool = false) {
        preparationID = UUID(); preparationTask?.cancel(); preparationTask = nil; isPreparing = false
        if clear { preparedFields.removeAll(); preparationFacts = []; preparationURL = ""; preparedFieldCount = 0 }
    }
    private func preparationKey(_ field: ApplicationFormField, url: String, facts: [ApplicationAutofillFact]) -> String {
        // Reuse individual unchanged fields even when another experience is added.
        // Identity prevents transferring a plan to a replacement control or different record.
        (field.identity ?? field.id) + "|" + mappingCache.key(field: field, fields: [field], facts: facts, source: url)
    }
    private func restartPreparation() {
        guard !isFilling, !isLoading, factsProvider != nil, preparationTask == nil else { return }
        let generation = preparationID
        preparationTask = Task { [weak self] in
            var lastRevision = -1, lastURL = ""
            var lastFacts: [ApplicationAutofillFact] = []
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(1500))
                    guard let self, !self.isFilling, !self.isLoading, self.preparationID == generation,
                          let url = self.webView.url?.absoluteString, let provider = self.factsProvider else { return }
                    let facts = provider(url)
                    let activity = try await self.javascript("activity")
                    try Task.checkCancellation()
                    let revision = activity["revision"] as? Int ?? 0
                    guard activity["ready"] as? Bool == true, activity["busy"] as? Bool != true else { continue }
                    if revision == lastRevision && url == lastURL && facts == lastFacts { continue }
                    lastRevision = revision; lastURL = url; lastFacts = facts
                    try await self.prepare(using: facts)
                } catch is CancellationError { return }
                catch { /* Login/loading/unavailable model must not block browsing or filling. */ }
            }
        }
    }
    /// Observe and plan only: no clicks, expansion, uploads, typing or saving.
    func prepare(using facts: [ApplicationAutofillFact]) async throws {
        guard !isFilling, !isLoading, !facts.isEmpty else { return }
        let generation = preparationID, started = Date(), ticket = navigationID
        isPreparing = true
        defer { if generation == preparationID { isPreparing = false; preparationSeconds = Date().timeIntervalSince(started) } }
        let scan = try await scan()
        try Task.checkCancellation(); try checkCurrent(ticket, url: scan.url)
        guard !isFilling, generation == preparationID, !scan.needsLogin else { return }
        if preparationURL != scan.url || preparationFacts != facts {
            preparedFields.removeAll(); preparedFieldCount = 0; preparationURL = scan.url; preparationFacts = facts
        }
        let keys = Dictionary(uniqueKeysWithValues: scan.fields.map { ($0.id, preparationKey($0, url: scan.url, facts: facts)) })
        let validKeys = Set(keys.values)
        preparedFields = preparedFields.filter { validKeys.contains($0.key) }
        let pending = scan.fields.filter { preparedFields[keys[$0.id]!] == nil }
        var planned = ApplicationAutofillPlanner.plan(fields: pending, facts: facts)
        var resolved = Set(planned.map(\.fieldID))
        var unknown: [ApplicationFormField] = []
        for field in pending where !resolved.contains(field.id) {
            let key = mappingCache.key(field: field, fields: scan.fields, facts: facts, source: scan.url)
            if let cached = mappingCache.assignment(key: key, field: field, facts: facts) {
                planned.append(cached); resolved.insert(field.id)
            } else if !field.section.isEmpty && ApplicationAutofillPlanner.unmatchedOutcome(field: field, facts: facts).status == "unmatched" {
                unknown.append(field)
            } else { resolved.insert(field.id) }
        }
        func publish(_ values: [ApplicationFieldAssignment], resolved ids: Set<String>) {
            for id in ids { preparedFields[keys[id]!] = PreparedField(assignment: values.first { $0.fieldID == id }, resolved: true) }
            preparedFieldCount = preparedFields.values.filter { $0.assignment != nil }.count
        }
        planned = try await ApplicationValueAdapter.prepare(planned, fields: pending)
        try Task.checkCancellation(); try checkCurrent(ticket, url: scan.url)
        guard !isFilling, generation == preparationID else { return }
        publish(planned, resolved: resolved)
        // Batch unfamiliar captions; do not ask the model once per input.
        for start in stride(from: 0, to: unknown.count, by: 60) {
            try Task.checkCancellation()
            let batch = Array(unknown[start..<min(start + 60, unknown.count)])
            preparationModelCalls += 1
            var semantic = try await semanticProvider(batch, facts)
            try Task.checkCancellation()
            semantic = try await ApplicationValueAdapter.prepare(semantic, fields: batch)
            try Task.checkCancellation(); try checkCurrent(ticket, url: scan.url)
            guard !isFilling, generation == preparationID else { return }
            publish(semantic, resolved: Set(batch.map(\.id)))
        }
    }
    private func javascript(_ action: String, arguments: [String: Any] = [:]) async throws -> [String: Any] {
        performance.scriptCalls += 1
        if script == nil || ProcessInfo.processInfo.arguments.contains("--journey-diagnostics"), let url = Bundle.main.url(forResource: "ApplicationAutofill", withExtension: "js") {
            script = try String(contentsOf: url, encoding: .utf8)
        }
        guard let script else { throw AIError.message("网申填写组件缺失，请重新安装当前版本。") }
        let rule = webView.url.flatMap { siteRuleStore.rule(for: $0) }
        var args: [String: Any] = ["action": action, "token": "", "assignments": [], "desiredSections": [:], "identities": [:], "siteRules": rule?.javascript ?? [:]]
        arguments.forEach { args[$0.key] = $0.value }
        if ProcessInfo.processInfo.arguments.contains("--autofill-diagnostics") {
            let step = (arguments["desiredSections"] as? [String: Any])?["step"] as? String ?? ""
            try? Data("\(action) \(step)".utf8).write(to: URL(fileURLWithPath: "/tmp/careerai-profile-review/current-action.txt"))
        }
        let result: Any = try await withCheckedThrowingContinuation { continuation in
            let pending = ScriptResult(continuation)
            pending.timeout = Task {
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                pending.finish(.failure(AIError.message("网页识别超时，请检查页面是否已经加载完成。")))
            }
            webView.callAsyncJavaScript(script, arguments: args, in: nil, in: scriptWorld) { result in pending.finish(result) }
        }
        return result as? [String: Any] ?? [:]
    }
    @MainActor private final class ScriptResult {
        var continuation: CheckedContinuation<Any, Error>?
        var timeout: Task<Void, Never>?
        init(_ continuation: CheckedContinuation<Any, Error>) { self.continuation = continuation }
        func finish(_ result: Result<Any, Error>) {
            guard let continuation else { return }; self.continuation = nil
            timeout?.cancel(); timeout = nil; continuation.resume(with: result)
        }
    }
    private func scan() async throws -> ApplicationFormScan {
        let result = try await javascript("scan")
        return try JSONDecoder().decode(ApplicationFormScan.self, from: JSONSerialization.data(withJSONObject: result))
    }
    func inspect() {
        guard !isFilling, !isLoading else { return }
        let ticket = navigationID; let operation = UUID(); fillID = operation
        isFilling = true; error = nil; status = "正在识别当前页，不会改动网页内容…"
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.navigationID == ticket && self.fillID == operation { self.isFilling = false; self.task = nil } }
            do {
                let scan = try await self.scan(); try Task.checkCancellation(); try self.checkCurrent(ticket, url: scan.url)
                self.outcomes = scan.fields.map { .init(id: $0.id, label: $0.label, status: $0.hasValue ? "preserved" : "identified") }
                    + scan.manualFields.enumerated().map { ApplicationAutofillPlanner.manualOutcome(label: $0.element, id: "manual-\($0.offset)") }
                self.status = "识别到 \(scan.fields.count) 个表单字段、\(scan.manualFields.count) 个手动处理项，未填写任何内容。"
                if scan.inaccessibleFrames > 0 { self.status += " 另有独立嵌入表单尚未读取。" }
            } catch { if self.fillID == operation { self.error = error.localizedDescription } }
        }
    }
    func fill(using facts: [ApplicationAutofillFact], attachments: [ApplicationProfileAttachment] = [], resumeFilename: String = "") {
        guard !isFilling else { return }
        guard !facts.isEmpty else { error = "请先打开网申档案，导入简历并补全资料。"; return }
        guard let url = webView.url, Self.validURL(url), !isLoading else { error = "请等待网申页面加载完成。"; return }
        stopPreparation()
        performance = Performance(); mappingCache.beginRun()
        error = nil; outcomes = []; incompleteDetails = []; isFilling = true; status = "正在识别当前页面的表单…"
        let operation = UUID(); fillID = operation
        task = Task { [weak self] in
            guard let self else { return }
            let runStart = Date()
            defer { if self.fillID == operation { self.performance.elapsedSeconds = Date().timeIntervalSince(runStart); self.isFilling = false; self.task = nil } }
            do {
                try await self.runJourney(using: facts, attachments: attachments, resumeFilename: resumeFilename, operation: operation)
            } catch is CancellationError {
                if self.fillID == operation { self.status = "填写已停止，已填内容保留，请检查当前页面。" }
            } catch {
                if self.fillID == operation { self.webView.callAsyncJavaScript("globalThis.__careerApplicationState = null;", in: nil, in: self.scriptWorld, completionHandler: nil)
                    self.error = error.localizedDescription; self.status = "请检查当前页面和网申档案后重试。" }
            }
        }
    }
    private func fillCurrentPage(using facts: [ApplicationAutofillFact], attachments: [ApplicationProfileAttachment], resumeFilename: String, ticket: UUID, preferImmediate: Bool = false) async throws -> [ApplicationFieldOutcome] {
                var scan = try await self.scan()
                try self.checkCurrent(ticket, url: scan.url)
                guard !scan.fields.isEmpty || !(scan.uploads ?? []).isEmpty else { return [] }
                let desired = Dictionary(grouping: facts, by: \.section).mapValues { $0.map(\.entryIndex).max().map { $0 + 1 } ?? 0 }
                // Add only explicitly named, non-submit experience controls. Each
                // step is followed by a new DOM scan, and the loop is bounded.
                for _ in 0..<20 {
                    try Task.checkCancellation(); try self.checkCurrent(ticket, url: scan.url)
                    let expansion = try await self.javascript("expand", arguments: ["desiredSections": desired])
                    guard (expansion["added"] as? Int ?? 0) > 0 else { break }
                    if let click = expansion["click"] as? [String: Any] { try await self.nativeClick(click) }
                    try await Task.sleep(for: .milliseconds(220)); scan = try await self.scan()
                }
                try self.checkCurrent(ticket, url: scan.url)
                if ProcessInfo.processInfo.arguments.contains("--autofill-diagnostics") {
                    try? JSONEncoder().encode(scan.fields).write(to: URL(fileURLWithPath: "/tmp/careerai-profile-review/scan.json"), options: .atomic)
                }
                var prepared: [ApplicationFieldAssignment] = []
                var resolvedPrepared: Set<String> = []
                if preparationURL == scan.url && preparationFacts == facts {
                    for field in scan.fields {
                        guard let saved = preparedFields[preparationKey(field, url: scan.url, facts: facts)] else { continue }
                        if saved.resolved { resolvedPrepared.insert(field.id) }
                        if var assignment = saved.assignment {
                            assignment.fieldID = field.id; prepared.append(assignment)
                        }
                    }
                }
                performance.preparedAssignments += prepared.count
                var assignments = prepared + ApplicationAutofillPlanner.plan(fields: scan.fields.filter { !resolvedPrepared.contains($0.id) }, facts: facts)
                let ruleIDs = Set(assignments.map(\.fieldID))
                let unmatched = scan.fields.filter {
                    !$0.section.isEmpty && !ruleIDs.contains($0.id) && !resolvedPrepared.contains($0.id)
                        && ApplicationAutofillPlanner.unmatchedOutcome(field: $0, facts: facts).status == "unmatched"
                }
                var mappingKeys: [String: String] = [:]
                var cachedIDs: Set<String> = []
                var unknown: [ApplicationFormField] = []
                for field in unmatched {
                    let key = mappingCache.key(field: field, fields: scan.fields, facts: facts, source: scan.url)
                    mappingKeys[field.id] = key
                    if let cached = mappingCache.assignment(key: key, field: field, facts: facts) {
                        assignments.append(cached); cachedIDs.insert(field.id); performance.cachedMappings += 1
                    } else { unknown.append(field) }
                }
                if !unknown.isEmpty && (!preferImmediate || assignments.isEmpty) {
                    unknown = unknown.filter { field in
                        let should = mappingCache.shouldResolve(mappingKeys[field.id]!)
                        if !should { performance.repeatedMappingSkips += 1 }
                        return should
                    }
                    self.status = "正在填写…"
                    // Only field labels/IDs are sent to the configured model.
                    // Actual candidate values stay local until filling this site.
                    for start in stride(from: 0, to: unknown.count, by: 60) {
                        try Task.checkCancellation()
                        do {
                            let batch = Array(unknown[start..<min(start + 60, unknown.count)])
                            performance.mappingModelCalls += 1
                            assignments += try await semanticProvider(batch, facts)
                        } catch is CancellationError { throw CancellationError() }
                        catch { break }
                    }
                }
                try Task.checkCancellation(); try self.checkCurrent(ticket, url: scan.url)
                self.status = "正在填写…"
                let preparedIDs = Set(prepared.map(\.fieldID))
                assignments = prepared + (try await ApplicationValueAdapter.prepare(assignments.filter { !preparedIDs.contains($0.fieldID) }, fields: scan.fields))
                try Task.checkCancellation(); try self.checkCurrent(ticket, url: scan.url)
                self.status = "正在填写…"
                let values = try JSONSerialization.jsonObject(with: JSONEncoder().encode(assignments))
                var result = try await self.javascript(ProcessInfo.processInfo.arguments.contains("--autofill-diagnostics") ? "fillDiagnostics" : "fill", arguments: ["token": scan.token, "assignments": values, "identities": ApplicationAutofillPlanner.identities(facts: facts)])
                try Task.checkCancellation(); try self.checkCurrent(ticket, url: scan.url)
                guard result["error"] == nil else { throw AIError.message("网申页面已变化，请重新点击一键填写。") }
                if var rows = result["results"] as? [[String: Any]] {
                    for index in rows.indices where ["option-missing", "unverified", "widget-pending"].contains(rows[index]["status"] as? String ?? "") {
                        try Task.checkCancellation(); try self.checkCurrent(ticket, url: scan.url)
                        guard let assignment = assignments.first(where: { $0.fieldID == rows[index]["id"] as? String }), let field = scan.fields.first(where: { $0.id == assignment.fieldID }) else { continue }
                        do {
                            if try await self.repair(assignment, field: field, token: scan.token) { rows[index]["status"] = "filled" }
                            else if self.incompleteDetails.contains(assignment.fieldID) { rows[index]["status"] = "missing-detail" }
                            else if rows[index]["status"] as? String == "widget-pending" { rows[index]["status"] = "unsupported" }
                        } catch is CancellationError { throw CancellationError() }
                        catch { rows[index]["status"] = "unverified" }
                    }
                    // Audit all successful fields after dependent controls have re-rendered.
                    let successful = Set(rows.filter { $0["status"] as? String == "filled" }.compactMap { $0["id"] as? String })
                    let auditValues = try JSONSerialization.jsonObject(with: JSONEncoder().encode(assignments.filter { successful.contains($0.fieldID) }))
                    let audit = try await self.javascript("audit", arguments: ["token": scan.token, "assignments": auditValues])
                    for item in audit["results"] as? [[String: Any]] ?? [] {
                        if let index = rows.firstIndex(where: { $0["id"] as? String == item["id"] as? String }) { rows[index]["status"] = item["status"] }
                    }
                    result["results"] = rows
                }
                let uploaded = try await self.fillAttachments(scan.uploads ?? [], attachments: attachments, resumeFilename: resumeFilename, token: scan.token, ticket: ticket, page: scan.url)
                result["uploadResults"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(uploaded))
                if ProcessInfo.processInfo.arguments.contains("--autofill-diagnostics") {
                    try? JSONSerialization.data(withJSONObject: result).write(to: URL(fileURLWithPath: "/tmp/careerai-profile-review/result.json"), options: .atomic)
                }
                let received = try JSONDecoder().decode([ApplicationFieldOutcome].self, from: JSONSerialization.data(withJSONObject: result["results"] ?? []))
                // Learn only after execution AND the independent value audit succeeded.
                let verified = received.filter { $0.status == "filled" }.compactMap { outcome -> (String, String)? in
                    guard let key = mappingKeys[outcome.id], let assignment = assignments.first(where: { $0.fieldID == outcome.id }) else { return nil }
                    return (key, assignment.factID)
                }
                mappingCache.verified(verified)
                mappingCache.invalidate(received.filter { cachedIDs.contains($0.id) && $0.status != "filled" && $0.status != "preserved" }.compactMap { mappingKeys[$0.id] })
                let pageOutcomes = (received + uploaded).filter { ["filled", "preserved"].contains($0.status) }
                let all = pageOutcomes.map { row -> ApplicationFieldOutcome in
                    var row = row
                    if let field = scan.fields.first(where: { $0.id == row.id }) {
                        row.id = field.identity.map { "field-dom|" + $0 } ?? "field|\(field.section)|\(field.entryIndex)|\(field.label)"
                    } else if let upload = scan.uploads?.first(where: { $0.id == row.id }), let identity = upload.identity {
                        row.id = "field-dom|" + identity
                    } else { row.id = "other|" + (row.label ?? row.id) }
                    return row
                }
                return all
    }
    private func journeySnapshot() async throws -> ApplicationJourneySnapshot {
        let raw = try await javascript("journey")
        if ProcessInfo.processInfo.arguments.contains("--journey-diagnostics") {
            try? JSONSerialization.data(withJSONObject: raw).write(to: URL(fileURLWithPath: "/tmp/careerai-agent/journey-snapshot.json"), options: .atomic)
            if let layout = try? await javascript("layoutDiagnostics") { try? JSONSerialization.data(withJSONObject: layout).write(to: URL(fileURLWithPath: "/tmp/careerai-agent/layout.json"), options: .atomic) }
        }
        return try JSONDecoder().decode(ApplicationJourneySnapshot.self, from: JSONSerialization.data(withJSONObject: raw))
    }
    /// Lightweight DOM activity polling; a changed, stable form can continue
    /// immediately, while unchanged/async saves retain a conservative fallback.
    private func waitForTransition(from before: ApplicationJourneySnapshot) async throws {
        let start = Date()
        defer { performance.transitionSeconds += Date().timeIntervalSince(start) }
        var revision = -1
        var quietSince = Date()
        var lastExaminedRevision = -2
        for _ in 0..<100 {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
            guard !isLoading else { quietSince = Date(); continue }
            guard let activity = try? await javascript("activity"), activity["ready"] as? Bool == true else { quietSince = Date(); continue }
            let currentRevision = activity["revision"] as? Int ?? 0
            if currentRevision != revision { revision = currentRevision; quietSince = Date() }
            let elapsed = Date().timeIntervalSince(start)
            // Unrelated clocks/animations must not keep the form waiting forever.
            guard activity["busy"] as? Bool != true,
                  Date().timeIntervalSince(quietSince) >= 0.2 || elapsed >= 1.5 else { continue }
            if revision != lastExaminedRevision {
                lastExaminedRevision = revision
                if let current = try? await journeySnapshot(), current.fingerprint != before.fingerprint || current.validation != before.validation || current.progress != before.progress { return }
            }
            if elapsed >= 1.5 { return }
        }
        throw AIError.message("网站仍在加载或处理保存，已保留填写内容；请待处理完成后继续。")
    }
    private func runJourney(using facts: [ApplicationAutofillFact], attachments: [ApplicationProfileAttachment], resumeFilename: String, operation: UUID) async throws {
        var attempted: Set<String> = []
        var pagePasses: [String: Int] = [:]
        var accumulated: [String: ApplicationFieldOutcome] = [:]
        var order: [String] = []
        var scopeKeys: [String: Set<String>] = [:]
        var started = false
        var sawProfileArea = false
        var history: [ApplicationJourneyAgent.Event] = []
        var modelUnavailable = false
        var limitReached = true
        // Restore a location, never stale action IDs or a claim that values saved.
        let initialKey = recoveryKey(facts)
        var bookmark = recoveryStore.bookmark(for: initialKey)
        var touchedKeys: Set<String> = [initialKey]
        var latestSection = bookmark?.section ?? ""
        var pendingSave = bookmark?.pendingSave ?? false
        var resumeAttempted = false
        defer { refreshAdapterState() }
        // A no-progress guard, not a cap on how many fields or companies exist.
        for _ in 0..<100 {
            try Task.checkCancellation()
            guard fillID == operation else { throw CancellationError() }
            let before = try await journeySnapshot()
            var page = before
            let key = recoveryKey(facts)
            touchedKeys.insert(key)
            // Do not switch away from a live edit/modal: it may contain unsaved
            // text from the interrupted run. First process the current state.
            if !resumeAttempted {
                resumeAttempted = true
                if let saved = bookmark, before.resumeSection != saved.section,
                   !before.hasFields, before.modalContext == nil, !before.needsLogin {
                    let targets = before.actions.filter { $0.kind == "tab" && $0.label == saved.section }
                    if targets.count == 1 {
                        status = "正在恢复\(saved.section)…"
                        intentionalNavigation = true
                        do {
                            let activated = try await javascript("journeyAction", arguments: ["desiredSections": ["id": targets[0].id, "fingerprint": before.fingerprint, "kind": "tab", "step": "execute"]])
                            if activated["activated"] as? Bool == true { try await waitForTransition(from: before) }
                            intentionalNavigation = false
                            bookmark = nil
                            continue
                        } catch { intentionalNavigation = false; throw error }
                    }
                }
                bookmark = nil
            }
            if let section = before.recoverySection { latestSection = section }
            recoveryStore.record(key: key, section: latestSection, pendingSave: pendingSave)
            sawProfileArea = sawProfileArea || !before.actions.isEmpty || !(before.headings ?? []).isEmpty
            let passes = pagePasses[before.fingerprint, default: 0]
            if before.hasFields && passes < 4 {
                started = true
                pagePasses[before.fingerprint] = passes + 1
                let rows = try await fillCurrentPage(using: facts, attachments: attachments, resumeFilename: resumeFilename, ticket: navigationID, preferImmediate: passes == 0)
                for var row in rows {
                    let key = row.id.hasPrefix("field-dom|") ? row.id : before.scope + "|" + row.id
                    scopeKeys[before.scope, default: []].insert(key)
                    if accumulated[key] == nil { order.append(key) }
                    // A second scan sees our own confirmed value as existing.
                    if row.status == "preserved", let previous = accumulated[key], previous.status == "filled" { row = previous }
                    row.id = key; accumulated[key] = row
                }
                outcomes = order.compactMap { accumulated[$0] }
                let afterFill = try await journeySnapshot()
                page = afterFill
                // New conditional fields, or a framework replacement, get another pass.
                if afterFill.fingerprint != before.fingerprint || passes == 0 { continue }
            }
            if ProcessInfo.processInfo.arguments.contains("--journey-diagnostics") { print("journey actions", page.actions.map { $0.kind + ":" + $0.label }, "attempted", attempted.count) }
            let available = ApplicationJourneyPolicy.available(in: page, attempted: attempted, started: started)
            var choice = ApplicationJourneyPolicy.next(in: page, attempted: attempted, started: started, actionOrder: webView.url.flatMap { siteRuleStore.rule(for: $0)?.actionOrder })
            if !modelUnavailable && available.contains(where: { $0.kind == "semantic" && !Set($0.allowedKinds ?? []).isSubset(of: ["tab", "expand"]) }) {
                status = "正在填写…"
                let localRows = outcomes.filter { scopeKeys[page.scope]?.contains($0.id) == true }
                let observation = ApplicationJourneyAgent.Observation(
                    headings: page.headings ?? [], activeSections: page.activeSections ?? [],
                    knownPending: localRows.filter { ["unverified", "option-missing", "changed", "unsupported", "upload-unverified"].contains($0.status) }.count,
                    missingOrUncertain: localRows.filter { ["missing-profile", "missing-detail", "invalid-profile", "unmatched", "missing-attachment"].contains($0.status) }.count,
                    validationCount: page.validation.count,
                    actions: available.map { .init(id: $0.id, label: $0.label, kind: $0.kind, context: $0.context ?? "", allowedKinds: $0.allowedKinds ?? [$0.kind]) },
                    recentActions: Array(history.suffix(8)), modalContext: page.modalContext)
                do {
                    performance.decisionModelCalls += 1
                    let decision = try await decisionProvider(observation)
                    if let planned = ApplicationJourneyAgent.resolve(decision, candidates: available) { choice = planned }
                } catch is CancellationError { throw CancellationError() }
                catch { modelUnavailable = true }
                try Task.checkCancellation()
                guard fillID == operation else { throw CancellationError() }
            }
            guard let action = choice else {
                limitReached = false; break
            }
            // Key the observed candidate rather than its model-resolved kind.
            let observedAction = available.first { $0.id == action.id } ?? action
            attempted.insert(ApplicationJourneyPolicy.key(observedAction, in: page))
            let actionTitle = action.kind == "edit" ? "编辑\(action.context ?? "当前资料")" : action.kind == "tab" ? "进入\(action.label)" : action.label
            status = "正在\(actionTitle)…"
            pendingSave = ["save", "save-next"].contains(action.kind)
            recoveryStore.record(key: key, section: latestSection, pendingSave: pendingSave)
            intentionalNavigation = true
            do {
                _ = try await javascript("activity")
                let activation = try await javascript("journeyAction", arguments: ["desiredSections": ["id": action.id, "fingerprint": page.fingerprint, "kind": action.kind, "step": "execute"]])
                guard activation["activated"] as? Bool == true else { intentionalNavigation = false; continue }
                try await waitForTransition(from: page)
                intentionalNavigation = false
            } catch { intentionalNavigation = false; throw error }
            if isLoading { throw AIError.message("网站仍在加载，已保留填写结果；加载完成后可继续一键填写。") }
            let observed = try await journeySnapshot()
            // Only an observed transition out of the editing state can clear a
            // pending save. On restart the current DOM is inspected again.
            if pendingSave && observed.modalContext == nil && observed.validation.isEmpty &&
                (observed.scope != page.scope || (!observed.hasFields && observed.fingerprint != page.fingerprint)) { pendingSave = false }
            if let section = observed.recoverySection { latestSection = section }
            recoveryStore.record(key: recoveryKey(facts), section: latestSection, pendingSave: pendingSave)
            let effect = observed.scope != page.scope ? "new-section-or-page" : observed.fingerprint != page.fingerprint ? "new-fields" : observed.progress != page.progress ? "field-progress" : !observed.validation.isEmpty ? "validation-blocked" : "no-observed-change"
            history.append(.init(action: action.label, kind: action.kind, effect: action.kind == "scroll" && effect == "no-observed-change" ? "scrolled-no-new-fields" : effect))
            // Even if Next was rejected, the next iteration explores another tab.
        }
        let filled = outcomes.filter { $0.status == "filled" }.count
        status = "已填写 \(filled) 项。"
        if !started { status = sawProfileArea ? "暂时无法打开填写区域，请检查当前页面。" : "请登录并打开网申表单。" }
        else if limitReached { status += " 网站尚有后续内容，可继续填写。" }
        status += " 请核对后自行提交。"
        // Exhausting available actions is not proof of submission, but it ends
        // this traversal. Only interrupted/limited runs need a resume position.
        if !limitReached && started && !pendingSave { recoveryStore.clear(touchedKeys) }
        if ProcessInfo.processInfo.arguments.contains("--autofill-diagnostics") {
            // Outcome metadata only: no profile values, credentials or resume contents.
            try? JSONEncoder().encode(outcomes).write(to: URL(fileURLWithPath: "/tmp/careerai-profile-review/journey-outcomes.json"), options: .atomic)
        }
    }
    private func fillAttachments(_ fields: [ApplicationUploadField], attachments: [ApplicationProfileAttachment], resumeFilename: String, token: String, ticket: UUID, page: String) async throws -> [ApplicationFieldOutcome] {
        var result: [ApplicationFieldOutcome] = []
        for field in fields where field.label.range(of: #"简历|(?i:resume|curriculum.?vitae|\bcv\b)"#, options: .regularExpression) != nil && field.label.range(of: "身份证|照片|成绩单|学位证|学历证|证书|作品集|快速|导入|解析", options: .regularExpression) == nil {
            try Task.checkCancellation(); try checkCurrent(ticket, url: page)
            if field.hasValue { result.append(.init(id: field.id, label: field.label, status: "preserved")); continue }
            let candidates = attachments.filter { !["个人照片", "证件照"].contains($0.kind) && ($0.kind == "简历" || (!resumeFilename.isEmpty && $0.name == resumeFilename)) }.filter { FileManager.default.isReadableFile(atPath: $0.path) }
            let preferred = candidates.filter { $0.name == resumeFilename }
            let available = preferred.count == 1 ? preferred : candidates
            guard available.count == 1, let attachment = available.first else { result.append(.init(id: field.id, label: field.label, status: available.isEmpty ? "missing-attachment" : "resume-ambiguous")); continue }
            let url = URL(fileURLWithPath: attachment.path)
            let values: [[String: Any]] = [["fieldID": field.id, "value": attachment.name]]
            do {
                status = "正在上传简历：\(field.label)…"
                let prepared = try await javascript("upload", arguments: ["token": token, "assignments": values, "desiredSections": ["step": "prepare"]])
                if ProcessInfo.processInfo.arguments.contains("--autofill-diagnostics") {
                    try? JSONSerialization.data(withJSONObject: prepared).write(to: URL(fileURLWithPath: "/tmp/careerai-profile-review/upload-prepare.json"), options: .atomic)
                }
                if prepared["preserved"] as? Bool == true { result.append(.init(id: field.id, label: field.label, status: "preserved")); continue }
                guard let pageURL = webView.url, prepared["canTrigger"] as? Bool == true else { result.append(.init(id: field.id, label: field.label, status: "upload-unverified")); continue }
                pendingUpload = (url, pageURL)
                // A site handler may replace the upload node while the chooser resolves.
                // Always inspect the receipt afterward; an execution error alone is not success.
                _ = try? await javascript("upload", arguments: ["token": token, "assignments": values, "desiredSections": ["step": "trigger"]])
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(300))
                if pendingUpload != nil, let click = prepared["click"] as? [String: Any] { try await nativeClick(click) }
                var complete = false
                for _ in 0..<30 {
                    try Task.checkCancellation(); try checkCurrent(ticket, url: page)
                    let verification = try await javascript("upload", arguments: ["token": token, "assignments": values, "desiredSections": ["step": "verify"]])
                    if ProcessInfo.processInfo.arguments.contains("--autofill-diagnostics") {
                        try? JSONSerialization.data(withJSONObject: verification).write(to: URL(fileURLWithPath: "/tmp/careerai-profile-review/upload-verification.json"), options: .atomic)
                    }
                    if verification["complete"] as? Bool == true { complete = true; break }
                    if verification["failed"] as? Bool == true { break }
                    try await Task.sleep(for: .milliseconds(300))
                }
                pendingUpload = nil
                result.append(.init(id: field.id, label: field.label, status: complete ? "filled" : "upload-unverified"))
            } catch is CancellationError { pendingUpload = nil; throw CancellationError() }
            catch { pendingUpload = nil; result.append(.init(id: field.id, label: field.label, status: "upload-unverified")) }
        }
        return result
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        if let queued = pendingUpload {
            pendingUpload = nil
            guard isFilling, webView.url == queued.page, frame.isMainFrame, frame.securityOrigin.host == queued.page.host,
                  FileManager.default.isReadableFile(atPath: queued.url.path) else { completionHandler(nil); return }
            completionHandler([queued.url]); return
        }
        guard let window = webView.window else { completionHandler(nil); return }
        let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.allowsMultipleSelection = parameters.allowsMultipleSelection
        picker.beginSheetModal(for: window) { response in completionHandler(response == .OK ? picker.urls : nil) }
    }
    private func nativeClick(_ coordinates: [String: Any]) async throws {
        guard let cssX = coordinates["x"] as? Double, let cssY = coordinates["y"] as? Double else { throw AIError.message("网页控件坐标无效。") }
        let x = cssX * webView.pageZoom, y = cssY * webView.pageZoom
        guard
              let window = webView.window, x >= 0, y >= 0, x < webView.bounds.width, y < webView.bounds.height else { throw AIError.message("网页控件不在可点击范围内，已保留当前填写结果。") }
        if !NSApp.isActive || !window.isKeyWindow { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
        try await Task.sleep(for: .milliseconds(120))
        let local = NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y)
        let point = webView.convert(local, to: nil)

        // Route to this web view directly; window-level dispatch may consume the
        // first event as focus activation instead of delivering it to the page.
        for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0) { if kind == .leftMouseDown { webView.mouseDown(with: event) } else { webView.mouseUp(with: event) } }
        }
        try await Task.sleep(for: .milliseconds(250))
    }
    private func repair(_ assignment: ApplicationFieldAssignment, field: ApplicationFormField, token: String) async throws -> Bool {
        let data = try JSONSerialization.jsonObject(with: JSONEncoder().encode([assignment]))
        func step(_ name: String) async throws -> [String: Any] {
            try await javascript("repair", arguments: ["token": token, "assignments": data, "desiredSections": ["step": name, "perform": true]])
        }
        if field.type == "date-widget" {
            let opening = try await step("open")
            if opening["missingDetail"] as? Bool == true { incompleteDetails.insert(assignment.fieldID); return false }
            if let click = opening["click"] as? [String: Any], opening["invoked"] as? Bool != true { try await nativeClick(click) }
            for _ in 0..<40 {
                try Task.checkCancellation()
                let choice = try await step("calendar")
                if choice["done"] as? Bool == true { _ = try await step("dismiss"); return true }
                if choice["missingDetail"] as? Bool == true { incompleteDetails.insert(assignment.fieldID); break }
                guard choice["invoked"] as? Bool == true else { break }
                try await Task.sleep(for: .milliseconds(180))
            }
            _ = try await step("dismiss")
            return try await step("verify")["done"] as? Bool == true
        }
        if ["aria-radio", "aria-checkbox", "select-multiple"].contains(field.type) { return try await step("verify")["done"] as? Bool == true }
        if !["select-one", "select", "combobox", "radio", "checkbox"].contains(field.type) {
            return try await step("text")["done"] as? Bool == true
        }
        if !field.type.hasPrefix("select") {
            let opening = try await step("open")
            if let click = opening["click"] as? [String: Any], opening["invoked"] as? Bool != true { try await nativeClick(click) }
        }
        var selected = field.type != "combobox"
        if field.type == "combobox" {
            for _ in 0..<12 {
                let choice = try await step("choose")
                if ProcessInfo.processInfo.arguments.contains("--autofill-diagnostics"), let options = choice["options"] {
                    try? JSONSerialization.data(withJSONObject: ["label": field.label, "options": options, "menus": choice["debugMenus"] ?? []]).write(to: URL(fileURLWithPath: "/tmp/careerai-profile-review/options-\(field.id).json"), options: .atomic)
                }
                if choice["done"] as? Bool == true { selected = true; break }
                guard let click = choice["click"] as? [String: Any] else { try await Task.sleep(for: .milliseconds(300)); continue }
                if choice["invoked"] as? Bool != true { try await nativeClick(click) }
                else { try await Task.sleep(for: .milliseconds(180)) }
                selected = true
                if choice["continue"] as? Bool != true { break }
            }
        }
        let verification = try await step("verify")
        var verified = verification["done"] as? Bool == true
        if !verified, field.component == nil, verification["missingDetail"] as? Bool != true {
            do {
                let menu = try await step("options")
                let options = try JSONDecoder().decode([ApplicationOptionMatcher.Option].self, from: JSONSerialization.data(withJSONObject: menu["options"] ?? []))
                if let id = try await ApplicationOptionMatcher.match(label: field.label, value: assignment.value, options: options), let signature = menu["signature"] as? String {
                    let selection = try await javascript("repair", arguments: ["token": token, "assignments": data, "desiredSections": ["step": "selectOption", "optionID": id, "signature": signature, "perform": true]])
                    if let click = selection["click"] as? [String: Any], selection["invoked"] as? Bool != true { try await nativeClick(click) }
                    verified = try await step("verify")["done"] as? Bool == true
                    selected = verified
                }
            } catch is CancellationError { throw CancellationError() }
            catch { /* An uncertain option remains pending; later fields still run. */ }
        }
        if verification["missingDetail"] as? Bool == true { incompleteDetails.insert(assignment.fieldID) }
        _ = try await step("dismiss")
        if !(selected && verified), ["学校名称", "专业"].contains(field.label) {
            let custom = try await step("custom")
            if let click = custom["click"] as? [String: Any] {
                if custom["invoked"] as? Bool != true { try await nativeClick(click) }
                else { try await Task.sleep(for: .milliseconds(180)) }
                return try await step("customText")["done"] as? Bool == true
            }
        }
        return selected && verified
    }
    private func checkCurrent(_ ticket: UUID, url: String) throws {
        guard ticket == navigationID, webView.url?.absoluteString == url else { throw AIError.message("页面已跳转，已停止填写，请在新页面重新识别。") }
    }
    private func updateNavigation() {
        address = webView.url?.absoluteString ?? address; canGoBack = webView.canGoBack; canGoForward = webView.canGoForward
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        stopPreparation(clear: true)
        navigationID = UUID(); isLoading = true; updateNavigation()
        if intentionalNavigation && isFilling { return }
        cancelFill(); error = nil; outcomes = []
        status = "请先登录并进入网申表单，再点击一键填写。"
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false; updateNavigation()
        refreshAdapterState()
        restartPreparation()
        if ProcessInfo.processInfo.arguments.contains("--journey-diagnostics") {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1000))
                for _ in 0..<20 {
                    guard let self else { return }
                    _ = try? await self.journeySnapshot()
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) { isLoading = false; if (error as NSError).code != NSURLErrorCancelled { self.error = "网页加载失败：\(error.localizedDescription)" }; updateNavigation() }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { cancelFill(); isLoading = false; error = "网页进程已停止，请刷新后继续。" }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, Self.validURL(url) else { decisionHandler(.cancel); return }
        if intentionalNavigation, let current = webView.url, url.host != current.host {
            intentionalNavigation = false; cancelFill(); status = "网站跳转到新的服务，请确认登录状态后继续填写。"
            decisionHandler(.allow); return
        }
        if navigationAction.targetFrame == nil {
            if intentionalNavigation { webView.load(URLRequest(url: url)) } else { open(url) }
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, Self.validURL(url) { if intentionalNavigation { webView.load(URLRequest(url: url)) } else { open(url) } }; return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert(); alert.messageText = webView.url?.host ?? "网站提示"; alert.informativeText = String(message.prefix(2000)); alert.addButton(withTitle: "好")
        if let window = webView.window { alert.beginSheetModal(for: window) { _ in completionHandler() } } else { completionHandler() }
    }
}

struct ApplicationBrowserView: View {
    @EnvironmentObject private var store: Store
    @State private var recordedID: String?
    @State private var showRecording = false
    @State private var showBrowserOptions = false
    @FocusState private var addressFocused: Bool
    private var recordingContext: FlowIntent?
    private var onRecordCreated: ((String) -> Void)?
    let title: String
    @ObservedObject var profileStore: ApplicationProfileStore
    @StateObject private var session: ApplicationBrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var showProfile = false
    @State private var profileSection = "basic"
    var resumeOverride: URL?
    var onFillState: ((Bool, Bool, String?) -> Void)?
    init(url: URL, title: String, profileStore: ApplicationProfileStore, resumeOverride: URL? = nil, retainedSession: ApplicationBrowserSession? = nil, recordingContext: FlowIntent? = nil, onRecordCreated: ((String) -> Void)? = nil, onFillState: ((Bool, Bool, String?) -> Void)? = nil) {
        self.title = title; self.profileStore = profileStore
        self.resumeOverride = resumeOverride; self.onFillState = onFillState
        self.recordingContext = recordingContext; self.onRecordCreated = onRecordCreated
        _recordedID = State(initialValue: recordingContext?.jobID)
        _session = StateObject(wrappedValue: retainedSession ?? ApplicationBrowserSession(url: url))
    }
    private func fillNow() {
        let attachments: [ApplicationProfileAttachment]
        let filename: String
        if let resumeOverride {
            filename = resumeOverride.lastPathComponent
            attachments = [.init(name: filename, path: resumeOverride.path, kind: "简历")]
        } else if let id = profileStore.profile.defaultResumeAttachmentID, let attachment = profileStore.profile.attachments.first(where: { $0.id == id && $0.kind == "简历" }) {
            filename = attachment.name; attachments = [attachment]
        } else { filename = profileStore.profile.resumeFilename; attachments = profileStore.profile.attachments }
        session.fill(using: profileStore.profile.facts(forSourceURL: session.webView.url?.absoluteString ?? ""), attachments: attachments, resumeFilename: filename)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("返回岗位库", systemImage: "chevron.left") { session.close(); dismiss() }
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer()
                Button { showBrowserOptions.toggle() } label: {
                    Image(systemName: "ellipsis").frame(width: 18)
                }.buttonStyle(.browserIcon).accessibilityLabel("浏览器选项").help("浏览器选项").disabled(session.isFilling)
                    .popover(isPresented: $showBrowserOptions, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("网页适配").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 11).padding(.top, 6)
                            Text(session.adapterTitle).font(.system(size: 13)).padding(.horizontal, 11).padding(.bottom, 7)
                            Divider().padding(.horizontal, 6)
                            Button { showBrowserOptions = false; session.importSiteRules() } label: {
                                Label("导入适配规则…", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Button { showBrowserOptions = false; session.rollbackSiteRules() } label: {
                                Label("回滚上一版规则", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity, alignment: .leading)
                            }.disabled(!session.canRollbackRules)
                            if session.resumableSection != nil {
                                Button { showBrowserOptions = false; session.resetRecovery() } label: {
                                    Label("清除恢复位置", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }.buttonStyle(.browserToolbar).padding(8).frame(width: 250).background(.white)
                    }
                Button("网申档案", systemImage: "person.text.rectangle") { profileSection = "basic"; showProfile = true }
                if recordingContext != nil {
                    Button(recordedID == nil ? "记录投递" : "查看记录", systemImage: "tray.and.arrow.down") {
                        if let id = recordedID { dismiss(); FlowIntent(route: "applications", jobID: id).post() }
                        else { showRecording = true }
                    }.disabled(session.isFilling)
                        .help("是否记录由你决定，填写不会自动新增或更新投递记录。")
                }
                Button { fillNow() } label: { Label(session.isFilling ? "正在填写…" : session.resumableSection == nil ? "一键填写" : "继续填写", systemImage: "sparkles") }
                    .buttonStyle(.flowPrimary).disabled(session.isFilling || session.isLoading)
                if session.isFilling { Button("停止") { session.cancelFill() } }
            }.buttonStyle(.browserToolbar).padding(.horizontal, 18).padding(.vertical, 10).background(.white)
            if let id = recordedID, let job = store.jobs.first(where: { $0.id == id }) {
                HStack {
                    Text(job.company + " · " + job.title).font(.caption).lineLimit(1)
                    Text(store.applications[id]?.formState ?? "已加入管理 · 尚未确认投递").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("查看进展") { dismiss(); FlowIntent(route: "applications", jobID: id).post() }
                    Button("我已完成投递") {
                        if let record = store.applications[id], store.updateApplication(id, stage: record.stage.order <= 3 ? .submitted : nil, notes: record.notes, followUpAt: record.followUpAt) {
                            store.recordFormProgress(id, state: "用户已确认提交", resumeVersion: CandidateMaterials.label(profile: profileStore.profile))
                        }
                    }.disabled(session.isFilling || store.applications[id]?.formState == "用户已确认提交")
                }.buttonStyle(.browserToolbar).padding(.horizontal, 20).padding(.bottom, 10)
            }
            Divider()
            HStack(spacing: 12) {
                Button { session.back() } label: { Image(systemName: "chevron.left") }.disabled(!session.canGoBack).help("后退")
                Button { session.forward() } label: { Image(systemName: "chevron.right") }.disabled(!session.canGoForward).help("前进")
                Button { session.reload() } label: { Image(systemName: "arrow.clockwise") }.help("刷新网申页面")
                HStack(spacing: 9) {
                    Image(systemName: "globe").font(.system(size: 13)).foregroundStyle(.secondary)
                    TextField("网申网址", text: $session.address).textFieldStyle(.plain).font(.system(size: 13))
                        .focused($addressFocused).onSubmit { session.openAddress(); addressFocused = false }.accessibilityLabel("网申网址")
                }.padding(.horizontal, 12).frame(height: 36)
                    .background(Color(white: 0.965), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(addressFocused ? 0.24 : 0.04)))
                ApplicationViewportTools(viewport: session.viewport).disabled(session.isFilling)
                if session.isLoading { ProgressView().controlSize(.small) }
            }.buttonStyle(.browserIcon).padding(.horizontal, 18).padding(.vertical, 8).background(.white)
            if let error = session.error { Text(error).font(.system(size: 12)).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 8) }
            ApplicationWebsite(session: session)
            ApplicationHorizontalScroll(viewport: session.viewport)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if !session.isFilling, let section = session.resumableSection { Text("上次停在\(section)，继续时会重新检查网页内容。").font(.system(size: 12)).foregroundStyle(.secondary) }
                Text(!session.isFilling && session.isPreparing ? "正在后台准备填写内容…" : (!session.isFilling && session.preparedFieldCount > 0 && session.outcomes.isEmpty ? "已准备好 \(session.preparedFieldCount) 项，点击一键填写即可。" : session.status)).font(.system(size: 12)).foregroundStyle(.secondary)
                Text("按档案逐页填写；仅自动上传简历。缺少的信息留空并继续其他项，验证码与最终提交由你操作。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 12).background(Color(white: 0.985))
        }.frame(minWidth: 1000, idealWidth: 1280, minHeight: 680, idealHeight: 820)
            .onAppear { session.enablePreparation { url in profileStore.profile.facts(forSourceURL: url) } }
            .onChange(of: profileStore.profile) { _, _ in session.refreshPreparation() }
            .sheet(isPresented: $showRecording) {
                if let context = recordingContext {
                    ApplicationLaunchSheet(request: context) { company, role, raw in
                        guard let id = store.trackApplication(company: company, role: role, url: raw) else { return false }
                        recordedID = id; onRecordCreated?(id); return true
                    }
                }
            }
            .onChange(of: session.isFilling) { _, filling in
                onFillState?(filling, !filling && session.status.hasPrefix("已填写") && session.error == nil, session.error) }
            .onDisappear { session.close() }
            .sheet(isPresented: $showProfile) {
                VStack(spacing: 0) {
                    HStack { Text("网申档案").font(.headline); Spacer(); Button("返回网申") { _ = profileStore.save(); showProfile = false } }.padding(16)
                    Divider(); ApplicationProfileView(store: profileStore, initialSection: profileSection)
                }.frame(minWidth: 950, minHeight: 680)
            }
    }
}
private struct ApplicationWebsite: NSViewRepresentable {
    @ObservedObject var session: ApplicationBrowserSession
    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
