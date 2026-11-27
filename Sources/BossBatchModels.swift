import Foundation

enum BossBatchState: String, Codable {
    case queued = "等待处理", reading = "读取 JD", generating = "AI 定制中"
    case opening = "核对聊天", sending = "发送中", sent = "页面已确认发送"
    case uncertain = "发送结果待核对", failed = "未完成", skipped = "已跳过", stopped = "已停止"
    var label: String { self == .generating ? "准备招呼" : rawValue }
    var blocksResend: Bool { self == .sending || self == .sent || self == .uncertain }
}

struct BossBatchItem: Codable, Identifiable {
    var id = UUID().uuidString
    var card: BossCard
    var state: BossBatchState = .queued
    var detail = ""
    var job: Job?
    var greeting = ""
    var updatedAt = Date()
}

struct BossBatchBook: Codable {
    var items: [BossBatchItem] = []
    var currentIDs: [String] = []
    static func companyKey(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased().components(separatedBy: .whitespacesAndNewlines).joined()
    }
    var current: [BossBatchItem] { let ids = Set(currentIDs); return items.filter { ids.contains($0.id) } }
    func persist() throws {
        let directory = LocalAIStorage.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("boss-batch-v1.json")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw AIError.message("无法创建批量投递记录文件。")
            }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

@MainActor 
enum BossBatchPolicy {
    static func prepare(_ cards: [BossCard], book: BossBatchBook, jobs: [Job], applications: [String: ApplicationRecord], onePerCompany: Bool, skipContactedCompany: Bool) -> [BossBatchItem] {
        var seen = Set<String>()
        return cards.map { card in
            var item = BossBatchItem(card: card)
            let company = BossBatchBook.companyKey(card.company), url = BossSite.canonical(card.url)
            if company.isEmpty || url == nil {
                item.state = .skipped; item.detail = "公司或岗位原链接缺失。"
            } else if !seen.insert(onePerCompany ? company : (url ?? card.url)).inserted {
                item.state = .skipped; item.detail = onePerCompany ? "同一家公司只处理列表中最靠前的岗位。" : "已跳过列表中的重复岗位。"
            } else if book.items.contains(where: { $0.state.blocksResend && ((skipContactedCompany && BossBatchBook.companyKey($0.card.company) == company) || BossSite.canonical($0.card.url) == url) }) {
                item.state = .skipped; item.detail = "该岗位已有发送或待核对记录，或符合已选的公司跳过规则。"
            } else if jobs.contains(where: { (skipContactedCompany ? BossBatchBook.companyKey($0.company) == company : BossSite.canonical($0.sourceURL ?? "") == url) && applications[$0.id]?.shouldOpenExistingChat == true }) {
                item.state = .skipped; item.detail = "已有该岗位的沟通记录，或符合公司跳过规则。"
            }
            return item
        }
    }
}
