import SwiftUI

@MainActor final class CareerChatStore: ObservableObject {
    @Published private(set) var chats: [CareerChatHeader] = []
    @Published var error: String?
    @Published var selected = "" {
        didSet {
            guard selected != oldValue else { return }
            sessions[oldValue]?.unloadMessages()
            updateSidebar()
        }
    }
    @Published private(set) var replying: Set<String> = []
    @Published private(set) var sidebarJSON = "{}"
    private var sidebarLimit = 40
    private var sessions: [String: CareerChatSession] = [:]
    private var deleting: Set<String> = []
    private let archive: CareerChatArchive
    private var ready = false

    init(directory: URL = LocalAIStorage.directory) {
        archive = CareerChatArchive(directory: directory)
        Task {
            do {
                chats = try await archive.open()
                ready = true
                startNew()
            } catch { self.error = "无法打开对话记录：" + error.localizedDescription }
        }
    }
    func session(for id: String) -> CareerChatSession {
        if let existing = sessions[id] { return existing }
        let header = chats.first { $0.id == id }
        let value = CareerChatSession(id: id, jobID: header?.jobID ?? "")
        value.loaded = header?.count == 0
        sessions[id] = value
        return value
    }
    func startNew() {
        guard ready else { return }
        if let empty = chats.first(where: { $0.count == 0 && !replying.contains($0.id) && !deleting.contains($0.id) }) { selected = empty.id; return }
        let value = CareerChatHeader()
        chats.insert(value, at: 0)
        selected = value.id
    }
    func setReplying(_ active: Bool, in id: String) {
        guard replying.contains(id) != active else { return }
        if active { replying.insert(id) } else { replying.remove(id) }
        updateSidebar()
    }
    func showMoreChats() {
        sidebarLimit += 40
        updateSidebar()
    }
    private func updateSidebar() {
        let visible = Array(chats.lazy.filter { $0.count > 0 }.prefix(sidebarLimit + 1))
        let rows = visible.prefix(sidebarLimit).map { ["id": $0.id, "title": $0.title] }
        let payload: [String: Any] = ["chats": rows, "selected": selected, "replying": replying.sorted(), "hasMore": visible.count > sidebarLimit]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .sortedKeys) {
            let json = String(decoding: data, as: UTF8.self)
            if sidebarJSON != json { sidebarJSON = json }
        }
    }
    func loadRecent(_ session: CareerChatSession) async {
        do {
            while selected == session.id && !session.loaded && !Task.isCancelled,
                  let header = chats.first(where: { $0.id == session.id }) {
                let page = try await archive.page(header.id, before: header.count)
                guard selected == header.id, !session.loaded, !Task.isCancelled else { return }
                guard chats.first(where: { $0.id == header.id })?.count == header.count else { continue }
                session.messages = page
                session.loaded = true
            }
        } catch { session.message = error.localizedDescription }
    }
    func loadEarlier(_ session: CareerChatSession) async -> Bool {
        guard let header = chats.first(where: { $0.id == session.id }), selected == session.id,
              session.loaded, let anchor = session.messages.first?.id else { return false }
        let before = header.count - session.messages.count
        guard before > 0 else { return false }
        do {
            let page = try await archive.page(header.id, before: before)
            guard selected == header.id, session.messages.first?.id == anchor, !page.isEmpty else { return false }
            session.messages.insert(contentsOf: page, at: 0)
            return true
        } catch { session.message = error.localizedDescription; return false }
    }
    func append(_ message: CareerChatMessage, to id: String, jobID: String?) async throws {
        guard !deleting.contains(id), var header = chats.first(where: { $0.id == id }) else { throw CancellationError() }
        if message.role == "user" {
            if header.count == 0 { header.title = String(message.text.prefix(36)) }
            header.jobID = jobID
        }
        let next = try await archive.append(message, header: header)
        guard let index = chats.firstIndex(where: { $0.id == id }) else { throw CancellationError() }
        if let session = sessions[id], session.loaded {
            if session.messages.count >= 24 && message.role == "user" {
                session.messages = Array(session.messages.suffix(23))
            }
            session.messages.append(message)
        }
        var changed = chats
        changed.remove(at: index)
        changed.insert(next, at: 0)
        chats = changed
        updateSidebar()
    }
    func delete(_ id: String) async throws {
        guard deleting.insert(id).inserted else { return }
        defer { deleting.remove(id) }
        let session = sessions[id]
        let paths = try await archive.delete(id, drafts: session?.attachments.compactMap(\.imagePath) ?? [])
        session?.operation?.cancel()
        replying.remove(id)
        sessions.removeValue(forKey: id)
        chats.removeAll { $0.id == id }
        if selected == id {
            if let next = chats.first(where: { $0.count > 0 }) { selected = next.id }
            else { startNew() }
        }
        updateSidebar()
        let kept = Set(sessions.values.flatMap(\.attachments).compactMap(\.imagePath))
        let folder = LocalAIStorage.directory.appendingPathComponent("chat-attachments").standardizedFileURL
        for path in paths.subtracting(kept) {
            let file = URL(fileURLWithPath: path).standardizedFileURL
            guard file.deletingLastPathComponent().path == folder.path,
                  UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil,
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
