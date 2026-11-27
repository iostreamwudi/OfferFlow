import Foundation
import SwiftUI
import CryptoKit

struct InterviewTarget: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var company = ""
    var role = "AI 产品经理"
    var jd = ""
    var jobID: String?
    var label: String { [company, role].filter { !$0.isEmpty }.joined(separator: " · ") }
}
struct InterviewSegment: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var text: String
    var imageFile: String? = nil
}
enum InterviewAnswerMode: String, Codable, CaseIterable {
    case direct, project
    var label: String { self == .direct ? "直接回答原题" : "结合我的经历" }
}
struct InterviewQuestion: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var original: String
    var segmentID: String
    var intent: String
    var reasoning: String
    var category: String
    var answerMode: InterviewAnswerMode?
    var modeReason: String?
    var modeManuallySet: Bool?
    var interviewRound: String?
}
struct InterviewPractice: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var questionID: String
    var target: InterviewTarget
    var projectID: String
    var projectName: String
    var question: String
    var outline: [String]
    var followups: [String]
    var missing: [String]
    var evidence: [String]
    var answer = ""
    var model: String
    var created = Date()
    var sourceFingerprint: String
    var projectFingerprint: String? = nil
}
struct InterviewNote: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var author = ""
    var dateRaw = ""
    var sourceURL = ""
    var segments: [InterviewSegment] = []
    var completeness = "仅链接，待读取"
    var aiNotice = false
    var category = "待分析"
    var questions: [InterviewQuestion] = []
    var practices: [InterviewPractice] = []
    var extractedFingerprint = ""
    var model = ""
    var collected = Date()
    var sourceCompany: String?
    var sourceRole: String?
    var sourceRound: String?
    var preparationTargetIDs: Set<String>?
    var memo = ""
    var questionSummary: String {
        if !questions.isEmpty { return "\(questions.count) 道题" }
        if segments.allSatisfy({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return "待补充原文" }
        return extractionIsCurrent ? "未发现明确原题" : "原文已保存 · 待提取"
    }
    func relevance(to target: InterviewTarget) -> String? {
        if preparationTargetIDs?.contains(target.id) == true { return "已关联" }
        if InterviewSearch(company: target.company, role: target.role).matches(self) { return "岗位匹配" }
        let company = sourceCompany.flatMap { $0.isEmpty ? nil : $0 } ?? title
        if !target.company.isEmpty, FlowCompanyRole.companyMatches(company, query: target.company) { return "同公司参考" }
        return nil
    }
    mutating func applyExtraction(_ incoming: [InterviewQuestion], category: String, model: String) {
        var previous = questions
        questions = incoming.map { question in
            var result = question
            if let index = previous.firstIndex(where: { $0.original == question.original && $0.segmentID == question.segmentID }) {
                let old = previous.remove(at: index)
                result.id = old.id
                result.interviewRound = old.interviewRound
                if old.modeManuallySet == true {
                    result.answerMode = old.answerMode; result.modeReason = old.modeReason; result.modeManuallySet = true
                }
            }
            return result
        }
        // A new model pass can omit questions that still have verbatim source evidence.
        questions += previous.filter { old in
            !old.original.isEmpty && segments.contains { $0.id == old.segmentID && $0.text.contains(old.original) }
        }
        self.category = category
        self.model = model
        extractedFingerprint = fingerprint
    }
    var fingerprint: String { InterviewRules.hash(segments.map { $0.id + ":" + $0.text }.joined(separator: "\n")) }
    var extractionIsCurrent: Bool { extractedFingerprint == fingerprint && !extractedFingerprint.isEmpty }
}
struct InterviewSearch: Equatable {
    var company = ""
    var role = ""
    var keyword = ""

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
            .components(separatedBy: .whitespacesAndNewlines).joined()
    }
    var isEmpty: Bool { [company, role, keyword].allSatisfy { clean($0).isEmpty } }
    var webQuery: String {
        ([company, role, keyword].map(clean).filter { !$0.isEmpty } + ["面经"]).joined(separator: " ")
    }
    func matches(_ note: InterviewNote, target: InterviewTarget? = nil) -> Bool {
        if isEmpty { return true }
        let source = [note.title] + note.segments.map(\.text) + note.questions.map(\.original)
        func includes(_ values: [String], _ term: String) -> Bool {
            let term = normalized(term)
            return term.isEmpty || values.contains { normalized($0).contains(term) }
        }
        guard includes(source + [note.author], keyword) else { return false }
        if let target, note.preparationTargetIDs?.contains(target.id) == true,
           normalized(company) == normalized(target.company), normalized(role) == normalized(target.role) {
            return true
        }
        let companyValues = note.sourceCompany.map { clean($0).isEmpty ? source : [$0] } ?? source
        let roleValues = note.sourceRole.map { clean($0).isEmpty ? source : [$0] } ?? source
        return companyValues.contains { FlowCompanyRole.companyMatches($0, query: company) } && (clean(role).isEmpty || roleValues.contains { FlowCompanyRole.role($0).contains(FlowCompanyRole.role(role)) })
    }
    func revealing(_ note: InterviewNote, target: InterviewTarget) -> Self {
        if matches(note, target: target) { return self }
        var withoutKeyword = self
        withoutKeyword.keyword = ""
        return withoutKeyword.matches(note, target: target) ? withoutKeyword : Self()
    }
}
struct InterviewLibrary: Codable {
    var version = 1
    var targets = [InterviewTarget()]
    var targetID = ""
    var notes: [InterviewNote] = []
}
enum InterviewSource: String, CaseIterable, Identifiable {
    case xiaohongshu, nowcoder
    var id: String { rawValue }
    var name: String { self == .nowcoder ? "牛客网" : "小红书" }
    var reader: String { self == .nowcoder ? "NowcoderReader" : "XiaohongshuReader" }
    static func detect(_ raw: String) -> Self? {
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme ?? ""),
              url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return nil }
        if host == "nowcoder.com" || host.hasSuffix(".nowcoder.com") { return .nowcoder }
        if host == "xiaohongshu.com" || host.hasSuffix(".xiaohongshu.com") { return .xiaohongshu }
        return nil
    }
    func searchURL(_ keyword: String) -> URL {
        var url = URLComponents(string: self == .nowcoder ? "https://www.nowcoder.com/search/all" : "https://www.xiaohongshu.com/search_result")!
        url.queryItems = self == .nowcoder
            ? [.init(name: "query", value: keyword), .init(name: "type", value: "all"), .init(name: "subType", value: "818")]
            : [.init(name: "keyword", value: keyword), .init(name: "source", value: "web_explore_feed")]
        return url.url!
    }
}
enum InterviewRules {
    static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func sourceID(_ raw: String) -> String? {
        guard let source = InterviewSource.detect(raw), let url = URL(string: raw) else { return nil }
        let parts = url.path.split(separator: "/")
        if source == .nowcoder {
            if parts.count == 2, parts[0] == "discuss", !parts[1].isEmpty, parts[1].allSatisfy({ $0.isASCII && $0.isNumber }) { return "discuss:" + parts[1] }
            if parts.count == 4, parts[0] == "feed", parts[1] == "main", parts[2] == "detail", parts[3].count == 32, parts[3].allSatisfy({ $0.isASCII && $0.isHexDigit }) { return "feed:" + parts[3] }
            return nil
        }
        guard parts.count >= 2, ["explore", "search_result"].contains(String(parts[0])), parts[1].count == 24,
              parts[1].allSatisfy({ $0.isHexDigit }) else { return nil }
        return String(parts[1])
    }
    static func canonical(_ raw: String) -> String {
        if let id = sourceID(raw) {
            if InterviewSource.detect(raw) == .nowcoder {
                let parts = id.split(separator: ":")
                return "https://www.nowcoder.com/" + (parts[0] == "discuss" ? "discuss/" : "feed/main/detail/") + parts[1]
            }
            return "https://www.xiaohongshu.com/explore/\(id)"
        }
        guard var components = URLComponents(string: raw), components.scheme == "https", components.host != nil,
              components.user == nil, components.password == nil else { return "" }
        components.query = nil; components.fragment = nil
        return components.string ?? ""
    }
    static func noteID(_ raw: String) -> String? {
        guard let source = InterviewSource.detect(raw), let id = sourceID(raw) else { return nil }
        return source.rawValue + ":" + id
    }
    static func merged(_ incoming: InterviewNote, existing: InterviewNote) -> InterviewNote {
        var value = existing
        if !incoming.title.isEmpty { value.title = incoming.title }
        if !incoming.author.isEmpty { value.author = incoming.author }
        if !incoming.dateRaw.isEmpty { value.dateRaw = incoming.dateRaw }
        if !incoming.sourceURL.isEmpty { value.sourceURL = incoming.sourceURL }
        // Failed reads and card-only refreshes never erase successfully captured text.
        if !incoming.segments.isEmpty {
            let receivedIDs = Set(incoming.segments.map(\.id))
            value.segments = incoming.segments + existing.segments.filter { !receivedIDs.contains($0.id) }
            value.completeness = incoming.completeness
            value.aiNotice = incoming.aiNotice
        }
        if value.sourceCompany?.isEmpty != false { value.sourceCompany = incoming.sourceCompany }
        if value.sourceRole?.isEmpty != false { value.sourceRole = incoming.sourceRole }
        if let targets = incoming.preparationTargetIDs {
            value.preparationTargetIDs = (value.preparationTargetIDs ?? []).union(targets)
        }
        value.collected = Date()
        return value
    }
}
@MainActor final class InterviewStore: ObservableObject {
    @Published private(set) var library = InterviewLibrary()
    @Published var error: String?
    private let directory: URL
    private var failedLoad = false
    init(directory: URL = LocalAIStorage.directory) {
        self.directory = directory
        let file = directory.appendingPathComponent("interviews-v1.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                library = try JSONDecoder().decode(InterviewLibrary.self, from: Data(contentsOf: file))
                guard library.version == 1 else { throw AIError.message("面经数据版本不兼容") }
            } catch { failedLoad = true; self.error = "面经库读取失败，原文件保留，暂停写入：\(error.localizedDescription)" }
        }
    }
    var target: InterviewTarget { library.targets.first { $0.id == library.targetID } ?? library.targets.first ?? InterviewTarget() }
    func transaction(_ mutate: (inout InterviewLibrary) -> Void) {
        guard !failedLoad else { return }
        var next = library; mutate(&next)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(next)
            try data.write(to: directory.appendingPathComponent("interviews-v1.json"), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent("interviews-v1.json").path)
            library = next; error = nil
        } catch { self.error = "面经保存失败：\(error.localizedDescription)" }
    }
    func prepareForApplication(jobID: String?, company: String, role: String, jd: String?) {
        let byID = jobID.flatMap { id in library.targets.first { $0.jobID == id } }
        var target = byID ?? library.targets.first { ($0.jobID == nil || jobID == nil) &&
            FlowCompanyRole.company($0.company) == FlowCompanyRole.company(company) &&
            FlowCompanyRole.role($0.role) == FlowCompanyRole.role(role) } ?? InterviewTarget()
        target.company = company
        target.role = role
        if let jobID { target.jobID = jobID }
        if let jd { target.jd = jd }
        saveTarget(target)
    }
    func saveTarget(_ target: InterviewTarget) {
        if library.targetID == target.id, self.target == target { return }
        transaction { lib in
            if let i = lib.targets.firstIndex(where: { $0.id == target.id }) { lib.targets[i] = target }
            else { lib.targets.append(target) }
            lib.targetID = target.id
        }
    }
    func upsert(_ note: InterviewNote) {
        transaction { lib in
            if let i = lib.notes.firstIndex(where: { $0.id == note.id }) { lib.notes[i] = InterviewRules.merged(note, existing: lib.notes[i]) }
            else { lib.notes.insert(note, at: 0) }
        }
    }
    func update(_ id: String, _ mutate: (inout InterviewNote) -> Void) {
        transaction { lib in if let i = lib.notes.firstIndex(where: { $0.id == id }) { mutate(&lib.notes[i]) } }
    }
}
