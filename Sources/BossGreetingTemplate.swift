import SwiftUI
import CryptoKit

struct BossGreetingTemplate: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = "通用模板"
    var body = "您好，关注到贵公司的{{岗位}}岗位，希望进一步了解岗位职责与团队需求，方便交流一下吗？"
}
struct BossGreetingConfiguration: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable { case ai = "AI 定制生成", template = "手动模板" }
    var version = 1
    var mode = Mode.ai
    var templates = [BossGreetingTemplate()]
    var selectedID = ""
    var candidateName = ""
    var selected: BossGreetingTemplate? { templates.first { $0.id == selectedID } ?? templates.first }
    var label: String { mode == .ai ? mode.rawValue : "模板 · " + (selected?.name ?? "未选择") }
    var aiRegionCount: Int { ((try? BossTemplateParser.parse(selected?.body ?? "")) ?? []).reduce(0) { count, part in if case .generation = part { return count + 1 }; return count } }
    func requiresAI() throws -> Bool { if mode == .ai { return true }; _ = try BossTemplateParser.parse(selected?.body ?? ""); return aiRegionCount > 0 }
    static let variables = ["姓名", "公司", "岗位", "城市", "薪资", "经验要求"]
    static let filename = "boss-greeting-templates-v1.json"
    static func load() throws -> Self {
        let url = LocalAIStorage.directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.version == 1 else { throw AIError.message("打招呼模板版本暂不支持，请先检查模板设置。") }
        return value
    }
    func save() throws {
        if mode == .template { guard let selected else { throw AIError.message("请先新建并选择一个模板。") }; try Self.validate(selected.body) }
        guard templates.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw AIError.message("模板名称不能为空。") }
        try FileManager.default.createDirectory(at: LocalAIStorage.directory, withIntermediateDirectories: true)
        let url = LocalAIStorage.directory.appendingPathComponent(Self.filename)
        try JSONEncoder().encode(self).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func validate(_ body: String) throws { _ = try BossTemplateParser.parse(body) }
    func prepare(job: Job, name: String) throws -> BossPreparedGreeting {
        guard let selected else { throw AIError.message("请先配置打招呼模板。") }
        let configuredName = candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = ["姓名": configuredName.isEmpty ? name : configuredName, "公司": job.company, "岗位": job.title, "城市": job.city, "薪资": job.salary, "经验要求": job.experience]
        return try BossTemplateParser.prepare(selected.body, values: values)
    }
    func render(job: Job, name: String) throws -> String { try prepare(job: job, name: name).preview }

    func signature(job: Job, name: String) throws -> String {
        if mode == .ai { return "ai" }
        return "template-layout-v2:" + SHA256.hash(data: Data(((selected?.id ?? "") + "\n" + (try render(job: job, name: name))).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
struct BossGreetingContext {
    let configuration: BossGreetingConfiguration
    let resume: ResumeMaterial?
    let settings: ArkSettings
    let key: String
    let name: String
    init(configuration override: BossGreetingConfiguration? = nil, validateAI: Bool = true) throws {
        configuration = try override ?? BossGreetingConfiguration.load()
        resume = CandidateMaterials.effective()
        settings = LocalAIStorage.read("ark-settings.json", as: ArkSettings.self) ?? ArkSettings()
        let profile = LocalAIStorage.read("application-profile-v1.json", as: ApplicationProfile.self)
        name = profile?.values["basic.name"] ?? resume?.name ?? ""
        if try configuration.requiresAI(), validateAI {
            guard let resume, !resume.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.message("请先在个人资料中导入简历或补充经历。") }
            key = try LocalAIStorage.key()
        } else if configuration.mode == .template {
            guard let selected = configuration.selected else { throw AIError.message("请先配置打招呼模板。") }
            try BossGreetingConfiguration.validate(selected.body)
            key = ""
        } else { key = "" }
    }
    func signature(job: Job) throws -> String {
        let base = try configuration.signature(job: job, name: name)
        guard configuration.mode == .template, configuration.aiRegionCount > 0 else { return base }
        // Invalidate mixed drafts when instructions, fact sources, JD or model change.
        let components = ["mixed-v1", base, job.title, job.company, job.jd, resume.map { ArkClient.outboundResume($0.text) } ?? "", settings.model]
        return "mixed:" + SHA256.hash(data: try JSONEncoder().encode(components)).map { String(format: "%02x", $0) }.joined()
    }
    func generate(job: Job) async throws -> AIResponse {
        var response: AIResponse
        if configuration.mode == .template {
            let prepared = try configuration.prepare(job: job, name: name)
            if prepared.regions.isEmpty {
                response = .init(result: .init(greeting: try prepared.assemble([:]), evidence: []), model: "手动模板 · " + (configuration.selected?.name ?? ""), inputTokens: 0, outputTokens: 0)
            } else {
                guard let resume else { throw AIError.message("请先导入真实简历，再生成模板中的 AI 部分。") }
                response = try await BossMixedGreetingAI.generate(prepared: prepared, job: job, resume: resume, settings: settings, key: key.isEmpty ? try LocalAIStorage.key() : key)
            }
        } else {
            guard let resume else { throw AIError.message("请先导入简历。") }
            response = try await ArkClient.generate(job: job, resume: resume, settings: settings, key: key.isEmpty ? try LocalAIStorage.key() : key)
        }
        response.greetingConfiguration = try signature(job: job)
        return response
    }

}

struct BossGreetingTemplateSheet: View {
    var previewJob: Job?
    var onSave: (BossGreetingConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var config = BossGreetingConfiguration()
    @State private var selectedID = ""
    @State private var error = ""
    @State private var loadFailed = false
    @State private var profileName = ""
    @State private var generatedPreview: String?
    @State private var previewBusy = false
    @State private var previewTask: Task<Void, Never>?
    private var index: Int? { config.templates.firstIndex { $0.id == selectedID } }
    private var job: Job { previewJob ?? Job(title: "AI 产品经理", company: "示例公司", city: "上海", salary: "20–30K", experience: "1–3年", tags: [], jd: "") }
    private var preview: String {
        var copy = config; copy.selectedID = selectedID
        do { return try copy.render(job: job, name: profileName) } catch { return "模板提示：" + error.localizedDescription }
    }
    var body: some View {
        FlowSurface {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("打招呼模板").font(.system(size: 22, weight: .semibold))
                    Text("当前使用：" + config.label).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.browserIcon).accessibilityLabel("关闭打招呼模板")
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        FlowSelect(title: "选择模板", selection: $selectedID, options: config.templates.map { ($0.id, $0.name) })
                        Button("新建", systemImage: "plus") { var value = BossGreetingTemplate(); value.name = "新模板"; config.templates.append(value); selectedID = value.id }
                        Button("复制", systemImage: "square.on.square") { if let i = index { var value = config.templates[i]; value.id = UUID().uuidString; value.name += " 副本"; config.templates.append(value); selectedID = value.id } }.disabled(index == nil)
                        Button { config.templates.removeAll { $0.id == selectedID }; selectedID = config.templates.first?.id ?? "" } label: { Image(systemName: "trash") }.disabled(index == nil).accessibilityLabel("删除模板")
                    }
                    if let i = index {
                        HStack(alignment: .top, spacing: 22) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("模板名称").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                                TextField("模板名称", text: $config.templates[i].name).accessibilityLabel("模板名称")
                                Text("招呼内容").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.top, 4)
                                TextEditor(text: $config.templates[i].body).frame(height: 205).flowEditorSurface().accessibilityLabel("打招呼模板内容")
                                HStack(spacing: 4) {
                                    ForEach(BossGreetingConfiguration.variables, id: \.self) { value in
                                        Button(value) { config.templates[i].body += "{{\(value)}}" }.help("插入 {{\(value)}}")
                                    }
                                }.buttonStyle(.browserToolbar)
                                Button("添加 AI 生成片段", systemImage: "sparkles") { config.templates[i].body += "{根据当前岗位 JD 和我的真实简历，用两句话说明最匹配的项目经历}" }
                                Text("{要求} 由 AI 生成 · {{岗位}} 替换资料\n其他文字和换行原样保留。")
                                    .font(.system(size: 12)).lineSpacing(4).foregroundStyle(.secondary)
                                DisclosureGroup("自定义称呼姓名") {
                                    TextField("留空使用个人资料姓名", text: $config.candidateName).padding(.top, 8)
                                }.font(.system(size: 12)).padding(.top, 3)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 14) {
                                HStack { Text("效果预览").font(.system(size: 14, weight: .semibold)); Spacer(); if previewBusy { ProgressView().controlSize(.small) } }
                                Text(previewJob == nil ? "示例岗位 · AI 产品经理" : job.company + " · " + job.title).font(.system(size: 12)).foregroundStyle(.secondary)
                                Text(generatedPreview ?? preview).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                Divider()
                                Text(generatedPreview.map { "\($0.count) 字 · 仅预览，未发送" } ?? (currentAIRegionCount > 0 ? "\(currentAIRegionCount) 个 AI 片段待生成。读取岗位 JD 后可预览完整招呼。" : "仅替换资料变量，无需 AI 生成。"))
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                                if previewBusy { Button("停止预览") { previewTask?.cancel() } }
                                else if currentAIRegionCount > 0 { Button("生成 AI 片段预览") { generatePreview() }.disabled(previewJob?.jd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false) }
                            }.padding(18).frame(width: 270, alignment: .leading).background(Color(white: 0.965), in: RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        Text("新建一个模板，写下你希望保留的招呼内容。").foregroundStyle(.secondary).padding(.vertical, 40)
                    }
                    if !error.isEmpty { Text(error).font(.callout).foregroundStyle(.orange) }
                }.padding(24)
            }
            Divider()
            HStack {
                Button("使用 AI 全文生成") { saveAndActivate(.ai) }.disabled(loadFailed || previewBusy).buttonStyle(.browserToolbar)
                Spacer()
                Button("取消") { dismiss() }
                Button("保存并使用") { saveAndActivate(.template) }.buttonStyle(.flowPrimary).disabled(loadFailed || index == nil || previewBusy)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }.frame(width: 860, height: 690)
        .onChange(of: config) { _, _ in generatedPreview = nil; previewTask?.cancel() }
        .onChange(of: selectedID) { _, _ in generatedPreview = nil; previewTask?.cancel() }
        .onDisappear { previewTask?.cancel() }
        .onAppear { profileName = LocalAIStorage.read("application-profile-v1.json", as: ApplicationProfile.self)?.values["basic.name"] ?? LocalAIStorage.read("resume.json", as: ResumeMaterial.self)?.name ?? ""; do { config = try BossGreetingConfiguration.load(); selectedID = config.selected?.id ?? "" } catch { self.error = "模板设置读取失败，原文件已保留：" + error.localizedDescription; loadFailed = true } }
    
        }
    }
    private func saveAndActivate(_ mode: BossGreetingConfiguration.Mode) {
        // Commit the chosen mode together with the edited template; failed validation
        // must not change the active setting or close the editor.
        var next = config
        next.selectedID = selectedID
        next.mode = mode
        do { try next.save(); onSave(next); dismiss() }
        catch { self.error = error.localizedDescription }
    }
    private var currentAIRegionCount: Int { var selected = config; selected.selectedID = selectedID; return selected.aiRegionCount }
    private func generatePreview() {
        guard let job = previewJob, !job.jd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var snapshot = config; snapshot.selectedID = selectedID; snapshot.mode = .template
        previewBusy = true; error = ""; generatedPreview = nil
        previewTask = Task { @MainActor in
            defer { previewBusy = false }
            do {
                let response = try await BossGreetingContext(configuration: snapshot).generate(job: job)
                try Task.checkCancellation()
                generatedPreview = response.result.greeting
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

}
