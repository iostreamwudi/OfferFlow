import Foundation
import CryptoKit

/// Data-only adapters. They can name fields/sections and rank already-observed
/// safe actions, but cannot add JavaScript, URLs, values or submission actions.
struct ApplicationSiteRule: Codable {
    var id: String
    var version: Int
    var hosts: [String]
    var pathPrefixes: [String]
    var fieldRows: [String]
    var activeSections: [String]
    var fieldAliases: [String: String]
    var sectionAliases: [String: String]
    var actionOrder: [String]

    func matches(_ url: URL) -> Bool {
        guard ["https", "http"].contains(url.scheme), hosts.contains(url.host?.lowercased() ?? "") else { return false }
        return pathPrefixes.contains { prefix in
            prefix == "/" || url.path == prefix || url.path.hasPrefix(prefix.hasSuffix("/") ? prefix : prefix + "/")
        }
    }
    var javascript: [String: Any] {
        ["id": id, "version": version, "fieldRows": fieldRows, "activeSections": activeSections,
         "fieldAliases": fieldAliases, "sectionAliases": sectionAliases]
    }
}

struct ApplicationSiteRulePack: Codable {
    var schemaVersion: Int
    var version: Int
    var sites: [ApplicationSiteRule]

    static let safeActions: Set<String> = ["edit", "expand", "scroll", "save", "save-next", "next", "tab"]
    static let sections: Set<String> = ["basic", "intention", "education", "highSchool", "work", "project", "campus", "award", "language", "computer", "certificate", "family", "emergency", "paper", "patent", "evaluation", "portfolio", "competition"]
    func validate() throws {
        guard schemaVersion == 1, version > 0, !sites.isEmpty, sites.count <= 100,
              Set(sites.map(\.id)).count == sites.count else { throw RuleError.invalid }
        for site in sites {
            guard !site.id.isEmpty, site.version > 0, !site.hosts.isEmpty, !site.pathPrefixes.isEmpty,
                  site.hosts.allSatisfy({ !$0.isEmpty && $0.range(of: #"^[a-z0-9.-]+$"#, options: .regularExpression) != nil }),
                  site.pathPrefixes.allSatisfy({ $0.hasPrefix("/") && !$0.contains("?") && !$0.contains("#") }),
                  site.fieldRows.count <= 20, site.activeSections.count <= 20,
                  (site.fieldRows + site.activeSections).allSatisfy({ !$0.isEmpty && $0.count < 300 }),
                  site.fieldAliases.count <= 200, site.sectionAliases.count <= 100,
                  site.fieldAliases.allSatisfy({ !$0.key.isEmpty && !$0.value.isEmpty && $0.key.count < 100 && $0.value.count < 100 }),
                  site.sectionAliases.allSatisfy({ !$0.key.isEmpty && Self.sections.contains($0.value) }),
                  Set(site.actionOrder) == Self.safeActions, site.actionOrder.count == Self.safeActions.count else { throw RuleError.invalid }
        }
    }
    enum RuleError: LocalizedError {
        case invalid, older, unavailable
        var errorDescription: String? {
            switch self {
            case .invalid: return "规则文件格式无效，原有适配继续生效。"
            case .older: return "请选择版本更新的规则文件；恢复旧版请使用回滚。"
            case .unavailable: return "没有可回滚的规则版本。"
            }
        }
    }
}

final class ApplicationSiteRuleStore {
    private let directory: URL?
    private let bundled: ApplicationSiteRulePack?
    private(set) var pack: ApplicationSiteRulePack?
    private var current: URL? { directory?.appendingPathComponent("current.json") }
    private var previous: URL? { directory?.appendingPathComponent("previous.json") }
    init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("CareerAI-Demo/site-rules"), bundledURL: URL? = Bundle.main.url(forResource: "ApplicationSiteRules", withExtension: "json")) {
        self.directory = directory
        bundled = bundledURL.flatMap { try? Self.read($0) }
        pack = current.flatMap { try? Self.read($0) } ?? bundled
    }
    private static func read(_ url: URL) throws -> ApplicationSiteRulePack {
        let data = try Data(contentsOf: url)
        guard data.count <= 512_000 else { throw ApplicationSiteRulePack.RuleError.invalid }
        let pack = try JSONDecoder().decode(ApplicationSiteRulePack.self, from: data)
        try pack.validate(); return pack
    }
    func rule(for url: URL) -> ApplicationSiteRule? { pack?.sites.first { $0.matches(url) } }
    var revision: String { "rules-\(pack?.version ?? 0)" }
    var canRollback: Bool { previous.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    func install(_ url: URL) throws {
        let next = try Self.read(url)
        guard next.version > (pack?.version ?? 0) else { throw ApplicationSiteRulePack.RuleError.older }
        guard let directory, let current, let previous else { throw ApplicationSiteRulePack.RuleError.unavailable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let pack { try JSONEncoder().encode(pack).write(to: previous, options: .atomic) }
        try JSONEncoder().encode(next).write(to: current, options: .atomic)
        pack = next
    }
    func rollback() throws {
        guard let previous, let current else { throw ApplicationSiteRulePack.RuleError.unavailable }
        let old = try Self.read(previous)
        try JSONEncoder().encode(old).write(to: current, options: .atomic)
        pack = old
        try? FileManager.default.removeItem(at: previous)
    }
}

/// A location bookmark, never a claim that inputs were saved. No field values,
/// credentials, complete URLs, unsatisfied fields or executable actions persist.
final class ApplicationJourneyRecoveryStore {
    struct Bookmark: Codable {
        var section: String
        var pendingSave: Bool
        var updatedAt: Date
    }
    private let file: URL?
    private var bookmarks: [String: Bookmark]
    init(file: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("CareerAI-Demo/application-recovery-v1.json")) {
        self.file = file
        bookmarks = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: Bookmark].self, from: $0) } ?? [:]
    }
    static func key(url: String, facts: [ApplicationAutofillFact], revision: String) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let profile = (try? encoder.encode(facts.sorted { $0.id < $1.id })) ?? Data()
        return SHA256.hash(data: Data((url + "\n" + revision + "\n").utf8) + profile).map { String(format: "%02x", $0) }.joined()
    }
    func bookmark(for key: String) -> Bookmark? {
        guard let value = bookmarks[key], Date().timeIntervalSince(value.updatedAt) < 30 * 86400 else { return nil }
        return value
    }
    func record(key: String, section: String, pendingSave: Bool) {
        guard !section.isEmpty, section.count < 100 else { return }
        bookmarks[key] = Bookmark(section: section, pendingSave: pendingSave, updatedAt: Date())
        persist()
    }
    func clear(_ keys: Set<String>) { for key in keys { bookmarks.removeValue(forKey: key) }; persist() }
    private func persist() {
        bookmarks = bookmarks.filter { Date().timeIntervalSince($0.value.updatedAt) < 30 * 86400 }
        if bookmarks.count > 100 { bookmarks = Dictionary(uniqueKeysWithValues: bookmarks.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(100).map { ($0.key, $0.value) }) }
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(bookmarks).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { /* A full/unwritable disk must not block filling. */ }
    }
}
