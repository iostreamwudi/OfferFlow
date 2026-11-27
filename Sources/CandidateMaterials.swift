import Foundation
import CryptoKit

struct CandidateResumeVersion: Codable, Identifiable {
    var id: String
    var date = Date()
    var material: ResumeMaterial
}
enum CandidateMaterials {
    static var versions: [CandidateResumeVersion] { LocalAIStorage.read("resume-versions-v1.json", as: [CandidateResumeVersion].self) ?? [] }
    static func save(_ material: ResumeMaterial) throws {
        let id = fingerprint(material.text)
        let path = LocalAIStorage.directory.appendingPathComponent("resume-versions-v1.json")
        var versions = FileManager.default.fileExists(atPath: path.path) ? try JSONDecoder().decode([CandidateResumeVersion].self, from: Data(contentsOf: path)) : []
        if let previous = LocalAIStorage.read("resume.json", as: ResumeMaterial.self), !versions.contains(where: { $0.id == fingerprint(previous.text) }) {
            versions.insert(.init(id: fingerprint(previous.text), material: previous), at: 0)
        }
        if !versions.contains(where: { $0.id == id }) { versions.insert(.init(id: id, material: material), at: 0) }
        try LocalAIStorage.save(versions, name: "resume-versions-v1.json")
        try LocalAIStorage.save(material, name: "resume.json")
        NotificationCenter.default.post(name: .flowMaterialsChanged, object: nil)
    }
    static func fingerprint(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).prefix(5).map { String(format: "%02x", $0) }.joined() }
    static func effective(profile supplied: ApplicationProfile? = nil) -> ResumeMaterial? {
        let profile = supplied ?? LocalAIStorage.read("application-profile-v1.json", as: ApplicationProfile.self)
        let original = LocalAIStorage.read("resume.json", as: ResumeMaterial.self)
        return resolve(profile: profile, original: original)
    }
    static func resolve(profile: ApplicationProfile?, original: ResumeMaterial?) -> ResumeMaterial? {
        // Use a single coherent set of professional facts. Never append an older,
        // contradictory résumé to a newer confirmed structured record.
        let allowed: Set<String> = ["education", "work", "project", "campus", "award", "competition", "language", "computer", "certificate", "paper", "patent", "evaluation", "portfolio", "intention"]
        let facts = profile?.facts.filter { allowed.contains($0.section) } ?? []
        let hasExperience = facts.contains { ["education", "work", "project"].contains($0.section) }
        if hasExperience, let profile {
            let name = profile.values["basic.name"] ?? original?.name ?? ""
            let text = (["姓名：" + name] + facts.map { "\(ApplicationProfileCatalog.section($0.section)?.title ?? $0.section) \($0.entryIndex + 1) · \($0.label)：\($0.value)" }).joined(separator: "\n")
            return ResumeMaterial(filename: "最新个人资料", name: name, text: text)
        }
        return original
    }
    static func label(profile: ApplicationProfile? = nil) -> String {
        guard let value = effective(profile: profile) else { return "尚未添加简历" }
        return value.filename + " · " + fingerprint(value.text)
    }
}
