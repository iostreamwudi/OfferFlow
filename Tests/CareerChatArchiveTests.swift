import Foundation

@main struct CareerChatArchiveTests {
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("assistant-chats-v1.json")
        let db = CareerChatArchive(directory: folder)
        try Data("invalid".utf8).write(to: file)
        do { _ = try await db.open(); fatalError("Corrupt history was accepted") }
        catch { precondition(FileManager.default.fileExists(atPath: file.path)) }

        let sample = String(repeating: "上海产品岗位面试准备，结合项目写一段回答。", count: 35)
        let image = CareerChatAttachment(name: "截图", imagePath: "/tmp/shared-test-image")
        var old = (0..<100).map { n in
            CareerChat(title: "测试对话" + String(n), messages: (0..<50).map { i in
                CareerChatMessage(role: i % 2 == 0 ? "user" : "assistant", text: sample)
            })
        }
        old[0].messages[0].attachments = [image]
        old[1].messages[0].attachments = [image]
        old[1].jobID = "test-job"
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(old).write(to: file)
        var headers = try await db.open()
        precondition(headers.count == old.count && !FileManager.default.fileExists(atPath: file.path))
        // All message fields and ordering survive migration, not just titles and counts.
        for chat in old {
            let rows = try await db.page(chat.id, before: chat.messages.count, limit: chat.messages.count)
            let actual = try encoder.encode(rows), expected = try encoder.encode(chat.messages)
            precondition(actual == expected)
        }
        var target = headers.first { $0.id == old[1].id }!
        precondition(target.jobID == "test-job")
        let page = try await db.page(target.id, before: target.count)
        precondition(page.map(\.id) == old[1].messages.suffix(24).map(\.id))
        var baseline: [Double] = [], incremental: [Double] = []
        let legacyBenchmark = folder.appendingPathComponent("original-save")
        for _ in 0..<9 {
            let message = CareerChatMessage(role: "user", text: "明天面试怎么准备")
            old[1].messages.append(message)
            var start = DispatchTime.now().uptimeNanoseconds
            try JSONEncoder().encode(old).write(to: legacyBenchmark)
            baseline.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            start = DispatchTime.now().uptimeNanoseconds
            target = try await db.append(message, header: target)
            incremental.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        }
        print(String(format: "5,000 historical messages, median of 9 saves: full JSON %.2f ms, SQLite append %.2f ms", baseline.sorted()[4], incremental.sorted()[4]))
        let large = CareerChatMessage(role: "assistant", text: String(repeating: "长回答。", count: 20_000))
        target = try await db.append(large, header: target)
        headers = try await CareerChatArchive(directory: folder).open()
        precondition(headers.first { $0.id == target.id }?.count == 60)
        let tail = try await db.page(target.id, before: target.count, limit: 1)
        precondition(tail.first?.text == large.text)
        let retained = try await db.delete(old[0].id, drafts: [])
        precondition(retained.isEmpty)
        let removed = try await db.delete(target.id, drafts: [])
        precondition(removed == Set([image.imagePath!]))
        do { _ = try await db.append(large, header: target); fatalError("Deleted conversation resurrected") }
        catch {}
        let remaining = try await db.open()
        precondition(remaining.count == 98)
        print("PASS migration rollback, full history fidelity, indexed pagination, restart, long answer, shared attachment deletion")
    }
}
