import Foundation
import CryptoKit

/// A recruitment announcement may describe several roles. It is not a full JD.
struct LiveJobListing: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let company: String
    let title: String
    let city: String
    let industry: String
    let nature: String
    let cohort: String
    let education: String
    let deadline: String
    let sourceUpdated: String
    let batch: String
    let applyRaw: String
    let announcementRaw: String
    let notes: String
    let majorRequirements: String
    let exam: String
    let sourceURL: String
    let rawFields: [String]

    // IDs are local fingerprints, never invented Feishu record identifiers.
    var sourceRecordId: String? { nil }
    var applyURL: URL? { Self.safeHTTPURL(applyRaw) }
    var announcementURL: URL? { Self.safeHTTPURL(announcementRaw) }
    var applicationEmails: [String] {
        guard let pattern = try? NSRegularExpression(pattern: #"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}"#) else { return [] }
        var seen = Set<String>()
        return pattern.matches(in: applyRaw, range: NSRange(applyRaw.startIndex..., in: applyRaw)).compactMap { match in Range(match.range, in: applyRaw).map { String(applyRaw[$0]) } }.filter { seen.insert($0.lowercased()).inserted }
    }
    var applicationURLs: [URL] {
        var seen = Set<URL>()
        return applyRaw.components(separatedBy: .newlines).compactMap(Self.safeHTTPURL)
            .filter { seen.insert($0).inserted }
    }

    static func safeHTTPURL(_ raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              value.rangeOfCharacter(from: .controlCharacters) == nil,
              let components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return url
    }

    init(fields: [String], sourceURL: String = LiveJobParser.sourceURL) {
        precondition(fields.count == LiveJobParser.expectedHeaders.count)
        func clean(_ index: Int) -> String { fields[index].trimmingCharacters(in: .whitespacesAndNewlines) }
        company = clean(1); title = clean(4); city = clean(5); industry = clean(3); nature = clean(2)
        cohort = clean(7); education = clean(8); deadline = clean(6); sourceUpdated = clean(0)
        batch = clean(9); applyRaw = fields[12]; announcementRaw = fields[11]
        notes = fields[13]; majorRequirements = fields[14]; exam = clean(15)
        self.sourceURL = sourceURL; rawFields = fields
        // Update date, deadline, notes and requirements can change without
        // losing a local favorite. The recruiting role/cohort/URL is the key.
        // This is a conservative local match, not a claim of source identity.
        let key = [sourceURL, company, title, city, cohort, batch, clean(12)]
        let encoded = try! JSONEncoder().encode(key)
        id = "feishu-local-" + SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
    }
}

struct LiveJobSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version = Self.currentVersion
    var sourceURL = LiveJobParser.sourceURL
    var fetchedAt: Date
    var sourceRecordCount: Int
    var skippedRecordCount: Int
    var duplicateRecordCount: Int
    var exactDuplicateRecordCount: Int
    var listings: [LiveJobListing]
    // The exact, already validated source copy, not a substitute for checking
    // the independently observed schema and count on each refresh. Older
    // caches decode this as nil and receive a fingerprint after one full sync.
    var sourceFingerprint: String? = nil

    var latestSourceUpdated: String? {
        listings.map(\.sourceUpdated).filter { !$0.isEmpty }
            .max { (LiveJobParser.dateRank($0) ?? 0) < (LiveJobParser.dateRank($1) ?? 0) }
    }

    func validate() throws {
        guard version == Self.currentVersion else { throw LiveJobDataError.unsupportedCache }
        if let sourceFingerprint {
            guard sourceFingerprint.utf8.count == 64,
                  sourceFingerprint.utf8.allSatisfy({
                      (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
                  }) else { throw LiveJobDataError.invalidSnapshot }
        }
        guard sourceURL == LiveJobParser.sourceURL, fetchedAt.timeIntervalSince1970.isFinite,
              sourceRecordCount > 0, skippedRecordCount >= 0, duplicateRecordCount >= 0,
              exactDuplicateRecordCount >= 0, exactDuplicateRecordCount <= duplicateRecordCount,
              !listings.isEmpty,
              sourceRecordCount >= listings.count,
              skippedRecordCount <= sourceRecordCount - listings.count,
              duplicateRecordCount == sourceRecordCount - listings.count - skippedRecordCount,
              Set(listings.map(\.id)).count == listings.count else {
            throw LiveJobDataError.invalidSnapshot
        }
        for listing in listings {
            guard listing.rawFields.count == LiveJobParser.expectedHeaders.count,
                  !listing.company.isEmpty, !listing.title.isEmpty,
                  listing.sourceURL == sourceURL,
                  LiveJobListing(fields: listing.rawFields, sourceURL: sourceURL) == listing else {
                throw LiveJobDataError.invalidSnapshot
            }
        }
    }
}

enum LiveJobDataError: LocalizedError {
    case schemaChanged, invalidCount, incompleteCopy, ambiguousCells, unexpectedDate
    case noRecruitmentRows, unsupportedCache, invalidSnapshot

    var errorDescription: String? {
        switch self {
        case .schemaChanged: return "岗位数据字段发生变化，本次未更新，已保留原有岗位。"
        case .invalidCount: return "读取数量与数据源不一致，本次未更新，已保留原有岗位。"
        case .incompleteCopy: return "岗位数据尚未完整读取，请稍后重试。"
        case .ambiguousCells: return "无法确认招聘数据结构，本次未更新，已保留原有岗位。"
        case .unexpectedDate: return "招聘字段内容与预期不符，本次未更新，已保留原有岗位。"
        case .noRecruitmentRows: return "本次没有读到有效的招聘信息，已保留原有岗位。"
        case .unsupportedCache: return "本机岗位缓存版本暂不支持，请重新更新岗位库。"
        case .invalidSnapshot: return "岗位数据校验失败，未替换已有缓存。"
        }
    }
}

enum LiveJobParser {
    static let sourceURL = "https://my.feishu.cn/base/ZBpybxIDfayhQssBHnYc9ZjEn7c?table=tblCNHUxBdaYvYvx&view=vewIPUzblP"
    static let expectedHeaders = [
        "更新时间", "公司名称", "企业性质", "行业分类", "招聘岗位", "工作地点",
        "截止时间", "届次", "学历要求", "批次", "公告来源", "公告链接", "投递方式",
        "备注", "专业要求", "是否笔试", "字段 1", "字段 2", "专业要求 (1)",
        "是否笔试 (1)", "字段 1 (1)", "字段 2 (1)", "父记录"
    ]

    /// Preserve every source byte, including embedded and trailing newlines.
    /// A matching digest lets a refresh reuse previously validated listings.
    static func fingerprint(text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The caller must independently observe these headers and the page count.
    /// Plain-text copy alone cannot establish schema or prove completeness.
    static func parse(_ text: String, expectedRecordCount: Int, headers: [String],
                      fetchedAt: Date = Date()) throws -> LiveJobSnapshot {
        guard headers == expectedHeaders else { throw LiveJobDataError.schemaChanged }
        guard expectedRecordCount > 0 else { throw LiveJobDataError.noRecruitmentRows }
        guard !text.isEmpty else { throw LiveJobDataError.incompleteCopy }
        guard !text.unicodeScalars.contains(where: { [0, 0xB, 0xC, 0x2028, 0x2029].contains($0.value) }) else {
            throw LiveJobDataError.ambiguousCells
        }
        // Fixed-width copy format: tabs separate the observed 23 columns;
        // only an LF after the 22nd tab is a record delimiter. CRs inside cells
        // are preserved verbatim. Do not normalize or trim the input first.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var rows: [[String]] = [], pending = "", tabs = 0
        rows.reserveCapacity(expectedRecordCount)
        for (index, line) in lines.enumerated() {
            if line.isEmpty && index == lines.count - 1 { continue }
            pending += line
            tabs += line.utf8.filter { $0 == 9 }.count
            guard tabs <= expectedHeaders.count - 1 else { throw LiveJobDataError.ambiguousCells }
            if tabs == expectedHeaders.count - 1 {
                let fields = pending.components(separatedBy: "\t")
                guard !fields[0].contains("\n"), !fields[0].contains("\r"),
                      !fields[22].contains("\n"), !fields[22].contains("\r") else {
                    throw LiveJobDataError.ambiguousCells
                }
                rows.append(fields)
                pending = ""; tabs = 0
            } else if index < lines.count - 1 {
                pending += "\n"
            }
        }
        guard pending.isEmpty, tabs == 0 else { throw LiveJobDataError.incompleteCopy }
        guard rows.count == expectedRecordCount else { throw LiveJobDataError.invalidCount }
        let roundTrip = rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
        guard text == roundTrip || text == roundTrip + "\n" else { throw LiveJobDataError.ambiguousCells }

        var skipped = 0, exactDuplicates = 0, duplicates = 0
        var seenRows = Set<[String]>(), positions: [String: Int] = [:], listings: [LiveJobListing] = []
        for fields in rows {
            let listing = LiveJobListing(fields: fields)
            guard !listing.company.isEmpty, !listing.title.isEmpty else { skipped += 1; continue }
            if !listing.sourceUpdated.isEmpty, dateRank(listing.sourceUpdated) == nil {
                throw LiveJobDataError.unexpectedDate
            }
            if !seenRows.insert(fields).inserted { exactDuplicates += 1 }
            if let index = positions[listing.id] {
                duplicates += 1
                if (dateRank(listing.sourceUpdated) ?? 0) > (dateRank(listings[index].sourceUpdated) ?? 0) {
                    listings[index] = listing
                }
            } else {
                positions[listing.id] = listings.count
                listings.append(listing)
            }
        }
        guard !listings.isEmpty else { throw LiveJobDataError.noRecruitmentRows }
        let snapshot = LiveJobSnapshot(fetchedAt: fetchedAt, sourceRecordCount: rows.count,
            skippedRecordCount: skipped, duplicateRecordCount: duplicates,
            exactDuplicateRecordCount: exactDuplicates, listings: listings,
            sourceFingerprint: fingerprint(text: text))
        try snapshot.validate()
        return snapshot
    }

    static func dateRank(_ raw: String) -> Int? {
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return year * 10_000 + month * 100 + day
    }
}

/// Snapshot and local favorites are separate files: replacing remote data never
/// deletes a saved ID. Writes validate first and atomically replace the old file.
struct LiveJobCache: Sendable {
    let directory: URL
    var snapshotURL: URL { directory.appendingPathComponent("live-jobs-v1.json") }
    var favoritesURL: URL { directory.appendingPathComponent("live-job-favorites-v1.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask)[0].appendingPathComponent("CareerAI-Demo", isDirectory: true)
    }

    func load() throws -> LiveJobSnapshot? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        let snapshot = try JSONDecoder().decode(LiveJobSnapshot.self, from: Data(contentsOf: snapshotURL))
        try snapshot.validate()
        return snapshot
    }

    func save(_ snapshot: LiveJobSnapshot) throws {
        try snapshot.validate()
        try write(JSONEncoder().encode(snapshot), to: snapshotURL)
    }

    private struct FavoriteSnapshot: Codable { var version = 1; var ids: Set<String> }

    func loadFavorites() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: favoritesURL.path) else { return [] }
        let snapshot = try JSONDecoder().decode(FavoriteSnapshot.self, from: Data(contentsOf: favoritesURL))
        guard snapshot.version == 1 else { throw LiveJobDataError.unsupportedCache }
        return snapshot.ids
    }

    func saveFavorites(_ ids: Set<String>) throws {
        try write(JSONEncoder().encode(FavoriteSnapshot(ids: ids)), to: favoritesURL)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
    }
}

// A view projection only: never mutate the synchronized source snapshot.
extension LiveJobListing {
    static func roleListings(from projects: [LiveJobListing]) -> [LiveJobListing] {
        var seen = Set<String>()
        return projects.flatMap(\.separatedRoles).filter { seen.insert($0.id).inserted }
    }
    var separatedRoles: [LiveJobListing] {
        var depth = 0, token = "", titles: [String] = []
        func commit() { let value = token.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { titles.append(value) }; token = "" }
        for char in title {
            if "（([【".contains(char) { depth += 1 }
            if "）)]】".contains(char) { depth = max(0, depth - 1) }
            if depth == 0 && "、；;\n".contains(char) { commit() } else { token.append(char) }
        }
        commit()
        var seen = Set<String>(); titles = titles.filter { seen.insert($0).inserted }
        guard titles.count > 1 else { return [self] }
        return titles.map { role in
            var fields = rawFields
            fields[4] = role
            fields[13] = "来源公告岗位：" + title + (notes.isEmpty ? "" : "\n" + notes)
            return LiveJobListing(fields: fields, sourceURL: sourceURL)
        }
    }
}
