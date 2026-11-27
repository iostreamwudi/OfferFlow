import Foundation
import SwiftUI

struct Job: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var company: String
    var city: String
    var salary: String
    var experience: String
    var tags: [String]
    var jd: String
    var source: String = "示例岗位"
    var colorIndex: Int = 0
    var created: Date = Date()
    var sourceURL: String? = nil
    var fetchedAt: Date? = nil
    var isWebApplication: Bool { source == "企业网申" }
    var initial: String { String(company.prefix(1)) }
    var color: Color { [Color.teal, .indigo, .orange, .blue, .pink, .purple][abs(colorIndex % 6)] }
}

struct Profile: Codable {
    var name = "体验用户"
    var target = "AI 产品经理"
    var experience = "参与监管报送指标与 FAQ 智能匹配项目，使用大模型与 RAG 完成知识检索、需求分析和效果评估；有产品设计和数据分析经验。"
}

struct MatchReport {
    let matched: [String]
    let missing: [String]
    let requirements: [String]
    var score: Int? { requirements.isEmpty ? nil : Int(Double(matched.count) / Double(requirements.count) * 100) }
}

enum Analysis {
    static let vocabulary = ["大模型", "RAG", "Agent", "产品设计", "需求分析", "数据分析", "效果评估", "项目管理", "Python", "SQL", "用户研究", "B端", "商业化", "推荐系统", "交互设计"]
    static func contains(_ text: String, _ word: String) -> Bool { text.localizedCaseInsensitiveContains(word) }
    static func report(_ job: Job, _ profile: Profile) -> MatchReport {
        let requirements = vocabulary.filter { contains(job.jd, $0) }
        let matched = requirements.filter { contains(profile.experience, $0) }
        return MatchReport(matched: matched, missing: requirements.filter { !matched.contains($0) }, requirements: requirements)
    }
    static func evidence(_ profile: Profile, keyword: String) -> String {
        let parts = profile.experience.components(separatedBy: CharacterSet(charactersIn: "。；\n"))
        return parts.first { contains($0, keyword) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    static func greeting(_ job: Job, _ profile: Profile) -> String {
        let report = report(job, profile)
        let evidence = profile.experience.trimmingCharacters(in: .whitespacesAndNewlines)
        let intro = profile.name.isEmpty ? "" : "我是\(profile.name)，"
        if report.matched.isEmpty {
            return "您好！\(intro)对贵公司的\(job.title)岗位很感兴趣，希望进一步了解岗位职责与团队需求。方便交流一下吗？"
        }
        return "您好！\(intro)关注到贵公司的\(job.title)岗位。我的经历与岗位中的\(report.matched.prefix(3).joined(separator: "、"))要求有关：\(evidence)\(evidence.hasSuffix("。") ? "" : "。")希望有机会进一步交流！"
    }
}


enum ApplicationStage: String, Codable, CaseIterable, Identifiable {
    case planned = "待沟通", drafted = "草稿已生成", filled = "草稿已填入", sent = "已发送", replied = "已回复"
    case referred = "已内推", submitted = "已投简历", screen = "简历筛选中", reviewed = "简历已查看", shortlisted = "简历筛选通过", screenRejected = "简历筛选未通过"
    case assessmentInvited = "测评已邀请", assessment = "测评进行中", assessmentWait = "测评待结果", assessmentPass = "测评通过", assessmentFail = "测评未通过", testInvited = "笔试已邀请", testActive = "笔试进行中", testWait = "笔试待结果", testPass = "笔试通过", testFail = "笔试未通过"
    case interview = "面试中", awaitInvite = "待约面", reschedule = "面试待改期", pool = "候选池等待中"
    case oneBooked = "一面已约", oneActive = "一面进行中", oneWait = "一面待反馈", onePass = "一面通过", oneFail = "一面未通过"
    case twoBooked = "二面已约", twoActive = "二面进行中", twoWait = "二面待反馈", twoPass = "二面通过", twoFail = "二面未通过"
    case threeBooked = "三面已约", threeActive = "三面进行中", threeWait = "三面待反馈", threePass = "三面通过", threeFail = "三面未通过"
    case fourBooked = "四面已约", fourActive = "四面进行中", fourWait = "四面待反馈", fourPass = "四面通过", fourFail = "四面未通过"
    case fiveBooked = "五面已约", fiveActive = "五面进行中", fiveWait = "五面待反馈", fivePass = "五面通过", fiveFail = "五面未通过"
    case extraBooked = "加面已约", extraActive = "加面进行中", extraWait = "加面待反馈", extraPass = "加面通过", extraFail = "加面未通过"
    case hrBooked = "HR 面已约", hrActive = "HR 面进行中", hrWait = "HR 面待反馈", hrPass = "HR 面通过", hrFail = "HR 面未通过"
    case finalBooked = "终面已约", finalActive = "终面进行中", finalWait = "终面待反馈", finalPass = "终面通过", finalFail = "终面未通过"
    case salaryTalk = "薪资沟通中", approval = "Offer 审批中", verbal = "已获口头 Offer", offer = "已获 Offer", accepted = "已接受 Offer", background = "背调中", backgroundPass = "背调通过", medical = "入职体检中", onboard = "待入职", joined = "已入职"
    case offerDeclined = "已拒绝 Offer", offerCancelled = "Offer 已撤回", backgroundFail = "背调未通过", approvalFail = "Offer 审批未通过", withdrawn = "本人撤回申请", frozen = "岗位取消或冻结", closed = "已结束"
    var id: String { rawValue }
    var label: String { self == .sent ? "已发送招呼" : rawValue }
    // Only the first three stages can be advanced automatically by draft restoration.
    var order: Int {
        switch self {
        case .planned: return 0
        case .drafted: return 1
        case .filled: return 2
        case .sent: return 3
        default: return 4
        }
    }
    static let groups: [(name: String, stages: [ApplicationStage])] = [
        ("准备与沟通", [.planned, .drafted, .filled, .sent, .replied]),
        ("投递与筛选", [.referred, .submitted, .screen, .reviewed, .shortlisted, .screenRejected]),
        ("测评与笔试", [.assessmentInvited, .assessment, .assessmentWait, .assessmentPass, .assessmentFail, .testInvited, .testActive, .testWait, .testPass, .testFail]),
        ("面试安排", [.interview, .awaitInvite, .reschedule, .pool]),
        ("一面", [.oneBooked, .oneActive, .oneWait, .onePass, .oneFail]),
        ("二面", [.twoBooked, .twoActive, .twoWait, .twoPass, .twoFail]),
        ("三面", [.threeBooked, .threeActive, .threeWait, .threePass, .threeFail]),
        ("四面", [.fourBooked, .fourActive, .fourWait, .fourPass, .fourFail]),
        ("五面", [.fiveBooked, .fiveActive, .fiveWait, .fivePass, .fiveFail]),
        ("加面", [.extraBooked, .extraActive, .extraWait, .extraPass, .extraFail]),
        ("HR 面", [.hrBooked, .hrActive, .hrWait, .hrPass, .hrFail]),
        ("终面", [.finalBooked, .finalActive, .finalWait, .finalPass, .finalFail]),
        ("Offer 与入职", [.salaryTalk, .approval, .verbal, .offer, .accepted, .background, .backgroundPass, .medical, .onboard, .joined]),
        ("流程结束", [.offerDeclined, .offerCancelled, .backgroundFail, .approvalFail, .withdrawn, .frozen, .closed]),
    ]
    var group: String { Self.groups.first { $0.stages.contains(self) }!.name }
    var isTerminal: Bool {
        switch self {
        case .screenRejected, .assessmentFail, .testFail, .oneFail, .twoFail, .threeFail,
             .fourFail, .fiveFail, .extraFail, .hrFail, .finalFail, .joined, .offerDeclined,
             .offerCancelled, .backgroundFail, .approvalFail, .withdrawn, .frozen, .closed: return true
        default: return false
        }
    }
}

struct ApplicationEvent: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    let stage: ApplicationStage
    let date: Date
    let note: String
}

struct ApplicationImportRow {
    var company: String
    var title: String
    var stage: ApplicationStage
    var notes: String
    var followUpAt: Date?
    var updatedAt: Date?
    var sourceURL: String?
    var city: String
}
struct ApplicationRecord: Codable, Equatable, Identifiable {
    var jobID: String
    var stage: ApplicationStage = .planned
    var generatedAt: Date?
    var filledAt: Date?
    var sentAt: Date?
    var confirmedAt: Date?
    var notes = ""
    var followUpAt: Date?
    var updatedAt = Date()
    var id: String { jobID }
    var formState: String? = nil
    var resumeVersion: String? = nil
    var history: [ApplicationEvent]?
    var isOpen: Bool { !stage.isTerminal }
    var timeline: [ApplicationEvent] {
        if let history { return history }
        var events: [ApplicationEvent] = []
        func add(_ stage: ApplicationStage, _ date: Date?, note: String = "") {
            if let date { events.append(.init(id: "old-" + stage.rawValue, stage: stage, date: date, note: note)) }
        }
        add(.drafted, generatedAt); add(.filled, filledAt); add(.sent, sentAt)
        if !events.contains(where: { $0.stage == stage }) {
            add(stage, confirmedAt, note: notes)
        }
        return events.sorted { $0.date < $1.date }
    }
    mutating func log(_ next: ApplicationStage, at date: Date, note: String) {
        history = timeline + [ApplicationEvent(stage: next, date: date, note: note)]
    }
    var shouldOpenExistingChat: Bool { sentAt != nil || stage.order >= ApplicationStage.sent.order }
}

@MainActor final class Store: ObservableObject {
    @Published var jobs: [Job] = [] {
        didSet { matchReports.removeAll(keepingCapacity: true) }
    }
    @Published var profile = Profile() {
        didSet { if oldValue.experience != profile.experience { matchReports.removeAll(keepingCapacity: true) } }
    }
    private var matchReports: [String: (jd: String, report: MatchReport)] = [:]

    func matchReport(for job: Job) -> MatchReport {
        if let cached = matchReports[job.id], cached.jd == job.jd { return cached.report }
        let report = Analysis.report(job, profile)
        matchReports[job.id] = (job.jd, report)
        return report
    }
    @Published var saved: Set<String> = []
    @Published var pipeline: Set<String> = []
    @Published var applications: [String: ApplicationRecord] = [:]
    @Published var selected: String?
    @Published var preferredDetailTab = "岗位详情"
    @Published var bossImportRevision = 0
    @Published var notice = ""
    private let file: URL
    struct Snapshot: Codable { var jobs: [Job]; var profile: Profile; var saved: Set<String>; var pipeline: Set<String>; var applications: [String: ApplicationRecord]? = nil }
    init(storageDirectory: URL? = nil) {
        let folder = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CareerAI-Demo")
        file = folder.appendingPathComponent("workspace.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try Data(contentsOf: file)
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
                jobs = snapshot.jobs; profile = snapshot.profile; saved = snapshot.saved; pipeline = snapshot.pipeline
                applications = snapshot.applications ?? [:]
                for id in pipeline where applications[id] == nil && jobs.contains(where: { $0.id == id }) { applications[id] = ApplicationRecord(jobID: id) }
            } else { jobs = Self.samples }
        } catch { jobs = Self.samples; notice = "本地数据读取失败，已载入示例；保存前请检查磁盘权限。" }
        selected = jobs.first?.id
    }
    func persist() {
        do { try write(jobs: jobs, records: applications, pipeline: pipeline) }
        catch { notice = "保存失败：\(error.localizedDescription)" }
    }
    func toggleSaved(_ id: String) { if saved.contains(id) { saved.remove(id) } else { saved.insert(id) }; persist() }
    func togglePipeline(_ id: String) {
        var ids = pipeline, records = applications
        if ids.contains(id) {
            ids.remove(id)
            if records[id]?.stage == .planned && (records[id]?.history ?? []).isEmpty { records.removeValue(forKey: id) }
        } else { ids.insert(id); if records[id] == nil { records[id] = ApplicationRecord(jobID: id) } }
        do { try write(jobs: jobs, records: records, pipeline: ids); pipeline = ids; applications = records; notice = "" }
        catch { notice = "保存失败：\(error.localizedDescription)" }
    }
    private func write(jobs: [Job], records: [String: ApplicationRecord], pipeline: Set<String>) throws {
        try JSONEncoder().encode(Snapshot(jobs: jobs, profile: profile, saved: saved, pipeline: pipeline, applications: records)).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    @discardableResult func renameApplication(_ id: String, company: String, role: String) -> Bool {
        let company = company.trimmingCharacters(in: .whitespacesAndNewlines), role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !company.isEmpty, !role.isEmpty, let index = jobs.firstIndex(where: { $0.id == id }) else { notice = "公司与岗位不能为空。"; return false }
        var next = jobs; next[index].company = company; next[index].title = role
        guard !next.contains(where: { $0.id != id && $0.company == company && $0.title == role && $0.sourceURL == next[index].sourceURL }) else { notice = "已存在这个公司与岗位的记录，请使用已有记录。"; return false }
        do { try write(jobs: next, records: applications, pipeline: pipeline); jobs = next; notice = ""; return true }
        catch { notice = "修改未保存：" + error.localizedDescription; return false }
    }
    private func existingIndex(for job: Job, canonicalURL: String) -> Int? {
        if let index = jobs.firstIndex(where: { BossSite.canonical($0.sourceURL ?? "") == canonicalURL }) {
            return index
        }
        let manual = jobs.indices.filter { index in
            let candidate = jobs[index]
            return candidate.source == "手动登记" && candidate.sourceURL == nil &&
                candidate.company.localizedCaseInsensitiveCompare(job.company) == .orderedSame &&
                candidate.title.localizedCaseInsensitiveCompare(job.title) == .orderedSame
        }
        return manual.count == 1 ? manual.first : nil
    }
    private func upserting(_ job: Job) -> (jobs: [Job], job: Job)? {
        guard let raw = job.sourceURL, let url = BossSite.canonical(raw), !job.title.isEmpty, !job.company.isEmpty else { return nil }
        var incoming = job, updated = jobs
        incoming.sourceURL = url
        if let index = existingIndex(for: job, canonicalURL: url) {
            let existing = updated[index]
            incoming.id = existing.id; incoming.created = existing.created
            if incoming.jd.isEmpty || (existing.fetchedAt != nil && (incoming.fetchedAt ?? .distantPast) <= existing.fetchedAt!) { incoming = existing }
            updated[index] = incoming
        } else { updated.insert(incoming, at: 0) }
        return (updated, incoming)
    }
    func application(for job: Job) -> ApplicationRecord? {
        let canonical = job.sourceURL.flatMap(BossSite.canonical)
        let stored = jobs.first { $0.id == job.id || (canonical != nil && BossSite.canonical($0.sourceURL ?? "") == canonical) }
        return stored.flatMap { applications[$0.id] }
    }
    @discardableResult func recordActivity(job: Job, stage: ApplicationStage, at date: Date? = Date()) -> Bool {
        guard stage == .drafted || stage == .filled, let update = upserting(job) else { return false }
        var record = applications[update.job.id] ?? ApplicationRecord(jobID: update.job.id)
        let original = record
        if record.history == nil { record.history = applications[record.id]?.timeline ?? [] }
        if stage == .drafted && record.generatedAt == nil { record.generatedAt = date }
        if stage == .filled && record.filledAt == nil { record.filledAt = date }
        if record.stage.order < stage.order {
            if let date { record.log(stage, at: date, note: "") }
            record.stage = stage
        }
        if record != original { record.updatedAt = max(record.updatedAt, date ?? record.updatedAt) }
        if applications[record.id] == record && update.jobs == jobs { return true }
        var records = applications; records[record.id] = record
        var ids = pipeline; ids.insert(record.id)
        do {
            try write(jobs: update.jobs, records: records, pipeline: ids)
            jobs = update.jobs; applications = records; pipeline = ids; notice = ""; return true
        } catch { notice = "沟通记录保存失败：\(error.localizedDescription)"; return false }
    }
    @discardableResult func updateApplication(_ id: String, stage: ApplicationStage?, notes: String, followUpAt: Date?, at date: Date = Date()) -> Bool {
        guard jobs.contains(where: { $0.id == id }) else { notice = "找不到对应岗位，未保存记录。"; return false }
        var record = applications[id] ?? ApplicationRecord(jobID: id)
        if let stage {
            if record.stage != stage { record.log(stage, at: date, note: notes); record.confirmedAt = date }
            record.stage = stage
            if stage == .sent && record.sentAt == nil { record.sentAt = date }
        }
        record.notes = notes; record.followUpAt = followUpAt; record.updatedAt = date
        var records = applications; records[id] = record
        var ids = pipeline; ids.insert(id)
        do {
            try write(jobs: jobs, records: records, pipeline: ids)
            applications = records; pipeline = ids; notice = ""; return true
        } catch { notice = "沟通记录保存失败：\(error.localizedDescription)"; return false }
    }
    @discardableResult func confirmSent(_ job: Job) -> Bool {
        guard let record = application(for: job) else { notice = "请先生成或保存该岗位的沟通记录。"; return false }
        return updateApplication(record.id, stage: record.stage.order > ApplicationStage.sent.order ? record.stage : .sent, notes: record.notes, followUpAt: record.followUpAt)
    }
    @discardableResult func importApplications(_ rows: [ApplicationImportRow], overwriteExisting: Bool) -> Bool {
        var nextJobs = jobs, records = applications, ids = pipeline
        var imported = 0, skipped = 0
        for row in rows {
            let company = row.company.trimmingCharacters(in: .whitespacesAndNewlines), title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !company.isEmpty, !title.isEmpty else { notice = "导入包含空公司或岗位，未保存任何记录。"; return false }
            let matches = nextJobs.filter { $0.company.localizedCaseInsensitiveCompare(company) == .orderedSame && $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
            let existing = matches.first(where: { records[$0.id] != nil }) ?? matches.first
            if let existing, records[existing.id] != nil, !overwriteExisting { skipped += 1; continue }
            var job = existing ?? Job(title: title, company: company, city: row.city, salary: "", experience: "", tags: [], jd: "", source: "表格导入")
            if !row.city.isEmpty { job.city = row.city }
            if let link = row.sourceURL { job.sourceURL = link }
            if let index = nextJobs.firstIndex(where: { $0.id == job.id }) { nextJobs[index] = job } else { nextJobs.append(job) }
            var record = records[job.id] ?? ApplicationRecord(jobID: job.id)
            let date = row.updatedAt ?? records[job.id]?.updatedAt ?? Date()
            if records[job.id] == nil || record.stage != row.stage { record.log(row.stage, at: date, note: "表格导入"); record.confirmedAt = date }
            record.stage = row.stage; record.notes = row.notes
            if let follow = row.followUpAt { record.followUpAt = follow }
            record.updatedAt = date
            if row.stage == .sent && record.sentAt == nil { record.sentAt = date }
            records[job.id] = record; ids.insert(job.id); imported += 1
        }
        do {
            try write(jobs: nextJobs, records: records, pipeline: ids)
            jobs = nextJobs; applications = records; pipeline = ids
            notice = "已导入或更新 \(imported) 条，跳过已有记录 \(skipped) 条。"; return true
        } catch { notice = "导入失败，原记录未变：\(error.localizedDescription)"; return false }
    }
    func registerApplication(company: String, title: String, stage: ApplicationStage) -> String? {
        let company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !company.isEmpty, !title.isEmpty else { return nil }
        let matches = jobs.filter { $0.company.localizedCaseInsensitiveCompare(company) == .orderedSame &&
            $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
        // An existing application is opened as-is, preserving its current progress.
        if let existing = matches.first(where: { applications[$0.id] != nil }) { return existing.id }
        var nextJobs = jobs
        let job = matches.first ?? Job(title: title, company: company, city: "", salary: "", experience: "", tags: [], jd: "", source: "手动登记")
        if matches.isEmpty { nextJobs.insert(job, at: 0) }
        let now = Date()
        var record = ApplicationRecord(jobID: job.id)
        record.stage = stage; record.confirmedAt = now; record.updatedAt = now
        record.history = [.init(stage: stage, date: now, note: "手动登记")]
        if stage == .sent { record.sentAt = now }
        var records = applications; records[job.id] = record
        let ids = pipeline.union([job.id])
        do {
            try write(jobs: nextJobs, records: records, pipeline: ids)
            jobs = nextJobs; applications = records; pipeline = ids; notice = ""
            return job.id
        } catch { notice = "登记失败：\(error.localizedDescription)"; return nil }
    }
    func applyResume(name: String, text: String) {
        profile.name = name.isEmpty ? "我的档案" : name
        profile.experience = text
        persist()
    }
    func add(_ job: Job) { jobs.insert(job, at: 0); selected = job.id; persist() }
    @discardableResult func importBoss(_ job: Job) -> Bool {
        guard let raw = job.sourceURL, let canonical = BossSite.canonical(raw),
              !job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !job.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !job.jd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notice = "请补全岗位名称、公司和 JD，并保留有效的 BOSS 原链接。"; return false
        }
        var incoming = job
        incoming.sourceURL = canonical
        var updated = jobs
        if let index = existingIndex(for: job, canonicalURL: canonical) {
            incoming.id = jobs[index].id
            incoming.created = jobs[index].created
            updated[index] = incoming
        } else { updated.insert(incoming, at: 0) }
        do {
            try write(jobs: updated, records: applications, pipeline: pipeline)
        } catch { notice = "保存失败：\(error.localizedDescription)"; return false }
        notice = ""
        preferredDetailTab = "匹配分析"
        jobs = updated
        selected = incoming.id
        bossImportRevision += 1
        return true
    }
    static let samples: [Job] = [
        Job(title: "AI 产品经理", company: "星澜科技", city: "上海", salary: "20–35K · 14薪", experience: "1–3年 · 本科", tags: ["大模型", "RAG", "产品设计"], jd: "岗位职责\n1. 负责面向企业的大模型应用产品设计，完成需求分析、原型设计与交付。\n2. 结合 RAG 知识检索能力，解决业务场景中的信息匹配问题。\n3. 建立效果评估体系，分析用户反馈并持续迭代产品。\n\n任职要求\n1. 具备清晰的产品思维，能独立开展需求分析。\n2. 理解大模型与 RAG 的基本原理，有相关实践经验。\n3. 有数据分析经验，能够基于事实推动产品优化。\n4. 良好的沟通表达和跨团队协作能力。", colorIndex: 0),
        Job(title: "Agent 产品工程师", company: "知序智能", city: "北京", salary: "25–40K · 16薪", experience: "1–3年 · 本科", tags: ["Agent", "Python", "大模型"], jd: "岗位职责\n负责 Agent 工作流设计及大模型应用落地，结合 Python 实现工具调用与任务执行。\n建立效果评估体系，跟踪任务完成率。\n\n任职要求\n熟悉 Agent 技术架构，具备 Python 开发经验。\n理解大模型及 RAG，能与产品设计团队协作。", colorIndex: 1),
        Job(title: "B端产品经理", company: "云川数字", city: "上海", salary: "18–28K · 13薪", experience: "1–3年 · 本科", tags: ["B端", "需求分析", "项目管理"], jd: "岗位职责\n负责 B端 产品设计与需求分析，推动企业业务流程数字化。\n开展用户研究，协调研发交付，负责项目管理。\n\n任职要求\n有企业软件产品经验，具备数据分析能力，熟悉 SQL。", colorIndex: 2),
        Job(title: "大模型应用产品经理", company: "原点实验室", city: "杭州", salary: "22–38K · 14薪", experience: "3–5年 · 本科", tags: ["大模型", "用户研究", "商业化"], jd: "岗位职责\n负责大模型应用的需求分析、产品设计和商业化探索。\n通过用户研究理解业务问题，推动从验证到上线。\n\n任职要求\n熟悉 Agent 与 RAG 应用，有效果评估和数据分析经验。", colorIndex: 3),
        Job(title: "数据产品经理", company: "数见科技", city: "深圳", salary: "18–30K · 14薪", experience: "1–3年 · 本科", tags: ["数据分析", "SQL", "产品设计"], jd: "岗位职责\n负责数据分析平台的产品设计与需求分析，设计业务指标体系。\n\n任职要求\n熟练使用 SQL 和 Python，具备数据分析及项目管理经验。", colorIndex: 4),
        Job(title: "AI 交互设计师", company: "灵感工场", city: "上海", salary: "18–32K · 13薪", experience: "1–3年 · 本科", tags: ["交互设计", "用户研究", "大模型"], jd: "岗位职责\n负责大模型对话产品的交互设计，开展用户研究并制作可交互原型。\n\n任职要求\n具备产品设计能力，熟悉 Agent 交互模式，能利用数据分析改进体验。", colorIndex: 5)
    ]
}
