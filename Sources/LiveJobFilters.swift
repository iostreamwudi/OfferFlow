import Foundation

struct LiveJobFieldRule: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var field = 1
    var operation: Operation = .contains
    var value = ""
    enum Operation: String, CaseIterable, Codable, Sendable {
        case contains = "包含", excludes = "不包含", equals = "等于", notEquals = "不等于", empty = "为空", notEmpty = "不为空"
        var needsValue: Bool { self != .empty && self != .notEmpty }
    }
    var isActive: Bool { !operation.needsValue || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct LiveJobFilterState: Hashable, Codable, Sendable {
    var query = ""
    var company = ""
    var role = ""
    var major = ""
    // Source column indexes; OR within one field, AND between fields.
    var selected: [Int: Set<String>] = [:]
    var onlyFavorites = false
    var channel: Channel = .all
    var sort: Sort = .source
    enum Channel: String, CaseIterable, Codable, Sendable { case all = "全部投递方式", web = "可打开网申", adapted = "已配置 AI 站点适配", email = "支持邮件投递" }
    enum Sort: String, CaseIterable, Codable, Sendable { case source = "默认排序", newest = "更新时间从新到旧", oldest = "更新时间从旧到新", deadline = "截止时间从近到远", company = "公司名称" }
    var updatedFrom = ""
    var updatedTo = ""
    var deadlineFrom = ""
    var deadlineTo = ""
    var deadline: Deadline = .all
    var rules: [LiveJobFieldRule] = []
    var matchAnyRule = false
    enum Deadline: String, CaseIterable, Codable, Sendable {
        case all = "全部截止状态", open = "未截止（有日期）", expired = "已截止（有日期）", undated = "未给出具体日期"
    }
    var activeCount: Int {
        [query, company, role, major].filter { !$0.isEmpty }.count + selected.values.filter { !$0.isEmpty }.count +
        (onlyFavorites ? 1 : 0) + (channel == .all ? 0 : 1) + (deadline == .all ? 0 : 1) +
        ((!updatedFrom.isEmpty || !updatedTo.isEmpty) ? 1 : 0) +
        ((!deadlineFrom.isEmpty || !deadlineTo.isEmpty) ? 1 : 0) + rules.filter(\.isActive).count
    }
    var dateError: String? {
        for value in [updatedFrom, updatedTo, deadlineFrom, deadlineTo] where !value.isEmpty {
            if LiveJobSearchIndex.dayRank(value) == nil { return "日期请填写 YYYY-MM-DD，例如 2026-11-17。" }
        }
        for pair in [(updatedFrom, updatedTo), (deadlineFrom, deadlineTo)] {
            if let first = LiveJobSearchIndex.dayRank(pair.0), let last = LiveJobSearchIndex.dayRank(pair.1), first > last {
                return "起始日期不能晚于结束日期。"
            }
        }
        return nil
    }
}

/// One immutable index per source revision. Never rebuild for status updates or
/// each keystroke. Full text and all 23 original fields remain searchable.
struct LiveJobSearchIndex: Sendable {
    static let facetFields = [5, 2, 3, 7, 8, 9, 15, 10]
    let jobs: [LiveJobListing]
    let options: [Int: [String]]
    private let rows: [Row]
    private struct Row: Sendable {
        let search: String
        let company: String
        let role: String
        let major: String
        let facets: [[String]]
        let updated: Int?
        let deadline: Int?
        let web: Bool
        let email: Bool
        let adapted: Bool
    }
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
    // Normalize display separators once per row; keep technical symbols such as C++/C#.
    static func normalizedRole(_ value: String) -> String {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_／/·（）()[]【】"))
        return normalized(value.precomposedStringWithCompatibilityMapping)
            .components(separatedBy: separators).joined()
    }
    static func roleKeywords(_ value: String) -> [String] {
        value.precomposedStringWithCompatibilityMapping
            .components(separatedBy: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，、;；")))
            .map(normalizedRole).filter { !$0.isEmpty }
    }
    static func tokens(_ value: String, field: Int) -> [String] {
        // A slash is meaningful in industry names (IT/互联网/游戏), and should
        // not turn one source category into several unrelated categories.
        let delimiters = field == 8 ? ",，、;；\n/" : ",，、;；\n"
        return value.components(separatedBy: CharacterSet(charactersIn: delimiters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "-" && $0 != "/" }
    }
    static func dayRank(_ value: String) -> Int? {
        LiveJobParser.dateRank(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "/"))
    }
    static func todayRank(now: Date = Date()) -> Int {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        return (parts.year ?? 0) * 10000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }
    init?(jobs: [LiveJobListing], adaptedURLs: Set<String> = []) {
        self.jobs = jobs
        var rows: [Row] = []
        var choices: [Int: Set<String>] = [:]
        rows.reserveCapacity(jobs.count)
        for (position, job) in jobs.enumerated() {
            if position.isMultiple(of: 64), Task.isCancelled { return nil }
            var facets: [[String]] = []
            for field in Self.facetFields {
                let values = Self.tokens(job.rawFields[field], field: field)
                facets.append(values)
                choices[field, default: []].formUnion(values)
            }
            rows.append(Row(search: Self.normalized([job.company, job.title, job.city, job.industry, job.majorRequirements].joined(separator: " ")),
                            company: Self.normalized(job.company), role: Self.normalizedRole(job.title),
                            major: Self.normalized(job.majorRequirements), facets: facets,
                            updated: Self.dayRank(job.sourceUpdated), deadline: Self.dayRank(job.deadline), web: !job.applicationURLs.isEmpty, email: !job.applicationEmails.isEmpty, adapted: job.applicationURLs.contains { adaptedURLs.contains($0.absoluteString) }))
        }
        self.rows = rows
        options = choices.mapValues { $0.sorted() }
    }
    func filter(_ filters: LiveJobFilterState, favorites: Set<String>, today: Int = Self.todayRank()) -> (jobs: [LiveJobListing], positions: [String: Int])? {
        guard filters.dateError == nil else { return ([], [:]) }
        let words = Self.normalized(filters.query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let company = Self.normalized(filters.company), major = Self.normalized(filters.major)
        let roleWords = Self.roleKeywords(filters.role)
        let searchWords = words.map { ($0, Self.normalizedRole($0)) }
        let facets = Self.facetFields.enumerated().compactMap { position, field -> (Int, Set<String>)? in
            guard let selected = filters.selected[field], !selected.isEmpty else { return nil }
            return (position, selected)
        }
        let updatedFrom = Self.dayRank(filters.updatedFrom), updatedTo = Self.dayRank(filters.updatedTo)
        let deadlineFrom = Self.dayRank(filters.deadlineFrom), deadlineTo = Self.dayRank(filters.deadlineTo)
        let rules = filters.rules.filter(\.isActive).map { ($0.field, $0.operation, Self.normalized($0.value)) }
        func within(_ value: Int?, _ from: Int?, _ to: Int?) -> Bool {
            guard from != nil || to != nil else { return true }
            guard let value else { return false }
            return (from == nil || value >= from!) && (to == nil || value <= to!)
        }
        var result: [LiveJobListing] = [], positions: [String: Int] = [:]
        result.reserveCapacity(jobs.count)
        for (position, job) in jobs.enumerated() {
            if position.isMultiple(of: 64), Task.isCancelled { return nil }
            let row = rows[position]
            guard !filters.onlyFavorites || favorites.contains(job.id),
                  company.isEmpty || row.company.contains(company), roleWords.allSatisfy({ row.role.contains($0) }),
                  major.isEmpty || row.major.contains(major), searchWords.allSatisfy({ row.search.contains($0.0) || (!$0.1.isEmpty && row.role.contains($0.1)) }),
                  facets.allSatisfy({ item in row.facets[item.0].contains(where: { item.1.contains($0) }) }),
                  within(row.updated, updatedFrom, updatedTo), within(row.deadline, deadlineFrom, deadlineTo) else { continue }
            switch filters.channel {
            case .all: break
            case .web: guard row.web else { continue }
            case .email: guard row.email else { continue }
            case .adapted: guard row.adapted else { continue }
            }
            switch filters.deadline {
            case .all: break
            case .open: guard let date = row.deadline, date >= today else { continue }
            case .expired: guard let date = row.deadline, date < today else { continue }
            case .undated: guard row.deadline == nil else { continue }
            }
            if !rules.isEmpty {
                func matches(_ item: (Int, LiveJobFieldRule.Operation, String)) -> Bool {
                    guard job.rawFields.indices.contains(item.0) else { return false }
                    let original = Self.normalized(job.rawFields[item.0])
                    switch item.1 {
                    case .contains: return original.contains(item.2)
                    case .excludes: return !original.contains(item.2)
                    case .equals: return original == item.2
                    case .notEquals: return original != item.2
                    case .empty: return original.isEmpty
                    case .notEmpty: return !original.isEmpty
                    }
                }
                if filters.matchAnyRule ? !rules.contains(where: matches) : !rules.allSatisfy(matches) { continue }
            }
            positions[job.id] = result.count; result.append(job)
        }
        if filters.sort != .source {
            let sourcePositions = Dictionary(jobs.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
            result.sort { a, b in
                guard let ai = sourcePositions[a.id], let bi = sourcePositions[b.id] else { return a.id < b.id }
                let left = rows[ai], right = rows[bi]
                switch filters.sort {
                case .source: return ai < bi
                case .company: return a.company == b.company ? ai < bi : a.company.localizedStandardCompare(b.company) == .orderedAscending
                case .newest: return left.updated == right.updated ? ai < bi : (left.updated ?? 0) > (right.updated ?? 0)
                case .oldest: return left.updated == right.updated ? ai < bi : (left.updated ?? Int.max) < (right.updated ?? Int.max)
                case .deadline: return left.deadline == right.deadline ? ai < bi : (left.deadline ?? Int.max) < (right.deadline ?? Int.max)
                }
            }
            positions = Dictionary(result.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        }
        return (result, positions)
    }
}
