import Foundation
import WebKit

@MainActor extension BossSession {
    func attach(_ store: Store) {
        self.store = store
        for cached in greetingBook.entries.values {
            store.recordActivity(job: cached.job, stage: .drafted, at: cached.generatedAt)
            if cached.filled { store.recordActivity(job: cached.job, stage: .filled, at: cached.filledAt) }
        }
        syncBatchSentRecords()
    }
    func confirmSent() {
        guard let job = communicationJob, let store else { return }
        if store.confirmSent(job) { communicationStatus = "已登记「\(job.company) · \(job.title)」为已发送（由你确认）。可在求职管理中记录回复和跟进。"; isError = false }
        else { say(store.notice, error: true) }
    }
    func openTrackedConversation(_ job: Job) {
        guard let raw = job.sourceURL, let canonical = BossSite.canonical(raw), let url = URL(string: canonical) else { say("该岗位没有可用的 BOSS 原链接。", error: true); return }
        navigatePreservingGreeting {
            let card = BossCard(title: job.title, company: job.company, city: job.city, salary: job.salary, experience: job.experience, tags: job.tags, url: canonical)
            self.selectedCard = card; self.activateGreeting(for: card); self.communicationJob = job
            self.communicating = true; self.isError = false
            self.communicationStatus = "正在打开「\(job.company) · \(job.title)」聊天，不生成或填入草稿…"
            let ticket = self.communicationTicket
            self.communicationTask = Task { [weak self] in
                guard let self else { return }
                defer { if self.communicationTicket == ticket { self.communicating = false } }
                do {
                    self.load(url)
                    let current = try await self.waitForJob(canonical)
                    try Task.checkCancellation()
                    guard current.company == job.company, current.title == job.title else { throw AIError.message("岗位信息已变化，请重新核对详情后打开聊天。") }
                    guard try await self.chatAction("open", job: job, text: "") == "opening" else { throw AIError.message("没有找到沟通入口，请在 BOSS 当前岗位手动打开聊天。") }
                    for _ in 0..<40 {
                        try Task.checkCancellation()
                        let status = try await self.chatAction("capture", job: job, text: "")
                        try Task.checkCancellation()
                        if status == "captured" { self.communicationStatus = "已打开并核对「\(job.company) · \(job.title)」聊天。未改动输入框；后续消息由你操作。"; return }
                        try await Task.sleep(nanoseconds: 400_000_000)
                    }
                    throw AIError.message("聊天尚未核对完成，请在 BOSS 页面确认岗位和联系人。未改动输入框。")
                } catch { if self.communicationTicket == ticket { self.isError = true; self.communicationStatus = error.localizedDescription } }
            }
        }
    }
    func navigatePreservingGreeting(_ action: @escaping @MainActor () -> Void) {
        guard !batchRunning else { return }
        selectionTask?.cancel(); selectionTicket = UUID()
        let ticket = selectionTicket
        cancelCommunication()
        selectionTask = Task { [weak self] in
            guard let self else { return }
            await self.preserveCurrentGreeting()
            guard !Task.isCancelled, self.selectionTicket == ticket else { return }
            action()
        }
    }
    var displayGreeting: String {
        if let url = communicationJob?.sourceURL, let text = greetingBook.draft(for: url)?.editorText { return text }
        return generatedGreeting?.result.greeting ?? ""
    }
    func persistGreetingBook() {
        do { try LocalAIStorage.save(greetingBook, name: "job-greeting-drafts.json") }
        catch { say("草稿仍在本次会话中，但保存到本机失败。请暂勿退出软件，检查本机存储后重试。", error: true) }
    }
    func cacheGreeting(job: Job, response: AIResponse, text: String? = nil, filled: Bool = false) {
        greetingBook.save(job: job, response: response, editorText: text, filled: filled)
        persistGreetingBook()
        if let store, let cached = job.sourceURL.flatMap({ greetingBook.draft(for: $0) }) {
            let generated = store.recordActivity(job: job, stage: .drafted, at: cached.generatedAt)
            let recorded = !filled || store.recordActivity(job: job, stage: .filled, at: cached.filledAt)
            if !generated || !recorded { say("草稿已保留，但求职管理记录未保存，请检查本机存储后重试。", error: true) }
        }
    }
    func preserveCurrentGreeting() async {
        guard let job = communicationJob, let response = generatedGreeting else { return }
        cacheGreeting(job: job, response: response)
        if let result = try? await chatResult("capture", job: job, text: response.result.greeting),
           result["status"] as? String == "captured", let text = result["text"] as? String {
            cacheGreeting(job: job, response: response, text: text)
        }
    }
    func activateGreeting(for card: BossCard) {
        overwriteRequested = false
        if let cached = greetingBook.draft(for: card.url) {
            communicationJob = cached.job
            generatedGreeting = cached.response
        } else { communicationJob = nil; generatedGreeting = nil }
    }
    func selectJob(_ card: BossCard, startChat: Bool, savedJobs: [Job]) {
        guard !batchRunning else { return }
        guard let raw = BossSite.canonical(card.url), let url = URL(string: raw) else { return }
        selectionTask?.cancel(); selectionTicket = UUID()
        let ticket = selectionTicket
        cancelCommunication()
        selectionTask = Task { [weak self] in
            guard let self else { return }
            await self.preserveCurrentGreeting()
            guard !Task.isCancelled, self.selectionTicket == ticket else { return }
            self.selectedCard = card
            self.activateGreeting(for: card)
            if startChat { self.runCommunication(card, savedJobs: savedJobs) }
            else {
                self.load(url)
                self.say(self.generatedGreeting == nil ? "正在查看「\(card.title)」。点击其他卡片可继续浏览，立即沟通会生成打招呼语。" : "已恢复「\(card.title)」的本地草稿；可查看详情或继续沟通，无需重新生成。")
            }
        }
    }
    func cancelCommunication() {
        communicationTask?.cancel()
        communicationTicket = UUID()
        communicationTask = nil
        communicating = false
        if !communicationStatus.isEmpty { communicationStatus = "" }
    }
    func communicate(_ card: BossCard, savedJobs: [Job]) {
        if let job = store?.jobs.first(where: { $0.sourceURL == BossSite.canonical(card.url) }),
           let record = store?.application(for: job), record.shouldOpenExistingChat {
            openTrackedConversation(job)
        } else { selectJob(card, startChat: true, savedJobs: savedJobs) }
    }
    func runCommunication(_ card: BossCard, savedJobs: [Job]) {
        guard !communicating else { return }
        cancelCommunication()
        generatedGreeting = nil; communicationJob = nil
        communicating = true; isError = false
        communicationStatus = "正在读取「\(card.title)」的岗位详情…"
        let ticket = communicationTicket
        communicationTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.communicationTicket == ticket { self.communicating = false } }
            do {
                try Task.checkCancellation()
                guard let rawURL = BossSite.canonical(card.url), let url = URL(string: rawURL) else { throw AIError.message("岗位原链接无效。") }
                let cached = self.greetingBook.draft(for: rawURL)
                let job: Job
                if self.isTargetChat(rawURL), let saved = cached?.job ?? savedJobs.first(where: { $0.sourceURL == rawURL }), !saved.jd.isEmpty {
                    job = saved
                } else {
                    self.selectedCard = card
                    // Read the live DOM again for freshness, but do not reload the same detail page.
                    if BossSite.canonical(self.webView.url?.absoluteString ?? "") != rawURL { self.load(url) }
                    job = try await self.waitForJob(rawURL)
                }
                try Task.checkCancellation()
                self.communicationJob = job
                self.draft = job
                let context = try BossGreetingContext(validateAI: false)
                let configurationID = try context.signature(job: job)
                var response: AIResponse
                if let cached, (cached.greetingConfiguration ?? "ai") == configurationID {
                    response = cached.response
                    if let text = cached.editorText, !text.isEmpty { response.result.greeting = text }
                    self.communicationStatus = "已恢复本岗位草稿，正在继续沟通，不重复调用模型…"
                } else {
                    self.communicationStatus = context.configuration.mode == .template ? (context.configuration.aiRegionCount > 0 ? "正在生成模板中指定的 AI 部分，固定文字保持不变…" : "正在按手动模板准备打招呼语…") : "豆包正在根据简历与当前 JD 生成打招呼语…"
                    response = try await context.generate(job: job)
                }
                try Task.checkCancellation()
                self.generatedGreeting = response
                self.cacheGreeting(job: job, response: response)
                if !self.isTargetChat(rawURL) {
                    guard BossSite.canonical(self.webView.url?.absoluteString ?? "") == rawURL else { throw AIError.message("打招呼语已生成，但页面已切换。请重新打开目标岗位后填入，草稿已保留。") }
                    self.communicationStatus = "打招呼语已生成，正在打开该岗位的 BOSS 聊天界面…"
                    let opened = try await self.chatAction("open", job: job, text: response.result.greeting)
                    guard opened == "opening" else { throw AIError.message("未找到当前岗位的沟通入口，请在 BOSS 页面手动打开目标聊天，再点左侧本岗位的「继续沟通」。草稿已保留，不会重复生成。") }
                }
                var targetSeen = false
                for _ in 0..<40 {
                    try Task.checkCancellation()
                    if self.isTargetChat(rawURL) { targetSeen = true }
                    let status = try await self.chatAction("fill", job: job, text: response.result.greeting)
                    try Task.checkCancellation()
                    if status == "filled" {
                        self.cacheGreeting(job: job, response: response, text: response.result.greeting, filled: true)
                        self.communicationStatus = "已为「\(job.company) · \(job.title)」填入草稿。可直接点其他岗位继续浏览，草稿会保留；发送由你操作。"; return
                    }
                    if status == "occupied" { self.overwriteRequested = true; self.communicationStatus = "打招呼语已生成，当前输入框已有草稿，请选择是否替换。"; return }
                    if status == "wrong_conversation" && targetSeen { throw AIError.message("当前聊天对应其他岗位，已停止填入。草稿已保留。") }
                    try await Task.sleep(nanoseconds: 400_000_000)
                }
                throw AIError.message("尚未能核对聊天对象或找到输入框。请确认页面已打开目标聊天，再点左侧本岗位的「继续沟通」。草稿已保留，不会重复生成。")
            } catch is CancellationError {
                if self.communicationTicket == ticket { self.communicationStatus = "已取消；没有发送消息。" }
            } catch {
                if self.communicationTicket == ticket { self.isError = true; self.communicationStatus = error.localizedDescription }
            }
        }
    }
    func isTargetChat(_ rawURL: String) -> Bool {
        guard let current = webView.url, current.path == "/web/geek/chat", let expected = URL(string: rawURL) else { return false }
        let id = expected.deletingPathExtension().lastPathComponent
        return URLComponents(url: current, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "jobId" }?.value == id
    }
    func waitForJob(_ rawURL: String) async throws -> Job {
        guard let file = Bundle.main.url(forResource: "BossExtractor", withExtension: "js") else { throw AIError.message("缺少岗位读取组件。") }
        let script = try String(contentsOf: file, encoding: .utf8)
        var entered = false
        for _ in 0..<40 {
            try Task.checkCancellation()
            if BossSite.canonical(webView.url?.absoluteString ?? "") == rawURL {
                entered = true
                if let raw = try? await webView.evaluateJavaScript(script) as? String, let data = raw.data(using: .utf8), let result = try? JSONDecoder().decode(BossReadResult.self, from: data) {
                    if result.gated { throw BossDraftError.verification }
                    if result.detail?.complete == true { return try BossDraftBuilder.make(result, cards: cards, fallbackCity: city) }
                    if result.detail != nil && result.detail?.jd.isEmpty == false { throw BossDraftError.incomplete }
                }
            } else if entered { throw AIError.message("页面已切换，已停止生成。请重新选择目标岗位。") }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        throw AIError.message("岗位详情尚未就绪。请确认登录和完整 JD 显示后，再点击立即沟通。")
    }
    func chatAction(_ operation: String, job: Job, text: String, overwrite: Bool = false) async throws -> String {
        let result = try await chatResult(operation, job: job, text: text, overwrite: overwrite)
        return result["status"] as? String ?? "unrecognized"
    }
    func chatResult(_ operation: String, job: Job, text: String, overwrite: Bool = false) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard let raw = job.sourceURL, let file = Bundle.main.url(forResource: "BossChat", withExtension: "js") else { throw AIError.message("缺少聊天连接组件。") }
        let script = try String(contentsOf: file, encoding: .utf8)
        let args: [String: Any] = ["operation": operation, "jobURL": raw, "company": job.company, "title": job.title, "text": text, "overwrite": overwrite]
        let json = String(data: try JSONSerialization.data(withJSONObject: args), encoding: .utf8)!
        let result = try await webView.evaluateJavaScript("(\(script))(\(json))") as? [String: Any]
        return result ?? [:]
    }
    func fillGenerated(overwrite: Bool) {
        guard !communicating, let job = communicationJob, let response = generatedGreeting else { return }
        if store?.application(for: job)?.shouldOpenExistingChat == true { say("本岗位已登记过沟通进展，请直接在 BOSS 继续聊天，不再重复填入打招呼语。", error: true); return }
        let text = displayGreeting
        guard !text.isEmpty else { say("本岗位草稿为空，请先检查草稿内容。", error: true); return }
        communicating = true
        let ticket = communicationTicket
        communicationTask = Task {
            defer { if communicationTicket == ticket { communicating = false } }
            do {
                let status = try await chatAction("fill", job: job, text: text, overwrite: overwrite)
                try Task.checkCancellation()
                if status == "filled" { cacheGreeting(job: job, response: response, text: text, filled: true); isError = false; communicationStatus = "草稿已填入本岗位聊天框。可点击其他岗位继续浏览，草稿已保留。" }
                else if status == "occupied" { overwriteRequested = true }
                else { throw AIError.message("未能核对目标聊天或找到可填写的输入框（\(status)），草稿已保留。请打开对应岗位的聊天。") }
            } catch { if communicationTicket == ticket { isError = true; communicationStatus = error.localizedDescription } }
        }
    }
}
