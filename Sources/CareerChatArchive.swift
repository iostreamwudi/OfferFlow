import Foundation
import SQLite3

struct CareerChatAttachment: Codable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var text = ""
    var imagePath: String? = nil
    var mime = ""
}
struct CareerChatMessage: Codable, Identifiable {
    var id = UUID().uuidString
    var role: String
    var text: String
    var date = Date()
    var sources: [String] = []
    var actions: [String] = []
    var attachments: [CareerChatAttachment] = []
    var interrupted: Bool? = nil
    var intents: [FlowIntent]? = nil
}
struct CareerChat: Codable, Identifiable {
    var id = UUID().uuidString
    var title = "新对话"
    var jobID: String? = nil
    var messages: [CareerChatMessage] = []
    var updatedAt = Date()
}

struct CareerChatHeader: Identifiable {
    var id = UUID().uuidString
    var title = "新对话"
    var jobID: String?
    var count = 0
    var updatedAt = Date()
}

actor CareerChatArchive {
    private let directory: URL
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(directory: URL) { self.directory = directory }
    deinit { sqlite3_close(db) }

    private enum Parameter {
        case text(String), integer(Int), number(Double), data(Data), null
    }
    private func failure() -> NSError {
        NSError(domain: "OfferFlow.ChatArchive", code: Int(sqlite3_errcode(db)), userInfo: [
            NSLocalizedDescriptionKey: "对话记录读写失败：" + String(cString: sqlite3_errmsg(db))
        ])
    }
    private func query(_ sql: String, _ params: [Parameter] = [], row: (OpaquePointer) throws -> Void = { _ in }) throws {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &pointer, nil) == SQLITE_OK, let stmt = pointer else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        for (index, value) in params.enumerated() {
            let i = Int32(index + 1)
            let code: Int32
            switch value {
            case .text(let s): code = sqlite3_bind_text(stmt, i, s, -1, transient)
            case .integer(let n): code = sqlite3_bind_int64(stmt, i, Int64(n))
            case .number(let n): code = sqlite3_bind_double(stmt, i, n)
            case .data(let d): code = d.withUnsafeBytes { sqlite3_bind_blob(stmt, i, $0.baseAddress, Int32($0.count), transient) }
            case .null: code = sqlite3_bind_null(stmt, i)
            }
            guard code == SQLITE_OK else { throw failure() }
        }
        var code = sqlite3_step(stmt)
        while code == SQLITE_ROW { try row(stmt); code = sqlite3_step(stmt) }
        guard code == SQLITE_DONE else { throw failure() }
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try query("BEGIN IMMEDIATE")
        do { let result = try body(); try query("COMMIT"); return result }
        catch { try? query("ROLLBACK"); throw error }
    }
    func open() throws -> [CareerChatHeader] {
        if db == nil {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("assistant-chats.sqlite3")
            guard sqlite3_open(file.path, &db) == SQLITE_OK else { throw failure() }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            sqlite3_busy_timeout(db, 3000)
            try query("PRAGMA foreign_keys=ON")
            try query("PRAGMA journal_mode=WAL")
        }
        let legacy = directory.appendingPathComponent("assistant-chats-v1.json")
        var migrated = false
        try transaction {
            var version = 0
            try query("PRAGMA user_version") { version = Int(sqlite3_column_int($0, 0)) }
            if version == 1 { return }
            guard version == 0 else { throw AIError.message("对话数据版本较新，请更新 OfferFlow。") }
            try query("CREATE TABLE chats (id TEXT PRIMARY KEY, title TEXT NOT NULL, job TEXT, updated REAL NOT NULL, count INTEGER NOT NULL)")
            try query("CREATE TABLE messages (chat TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE, pos INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(chat,pos)) WITHOUT ROWID")
            try query("CREATE TABLE images (chat TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE, path TEXT NOT NULL, PRIMARY KEY(chat,path)) WITHOUT ROWID")
            try query("CREATE INDEX image_path ON images(path)")
            if FileManager.default.fileExists(atPath: legacy.path) {
                let old = try JSONDecoder().decode([CareerChat].self, from: Data(contentsOf: legacy, options: .mappedIfSafe))
                migrated = true
                for chat in old {
                    let header = CareerChatHeader(id: chat.id, title: chat.title, jobID: chat.jobID, count: chat.messages.count, updatedAt: chat.updatedAt)
                    try insert(header)
                    for (pos, message) in chat.messages.enumerated() { try insert(message, chat: chat.id, pos: pos) }
                }
            }
            try query("PRAGMA user_version=1")
        }
        // Until COMMIT succeeds the original is the authoritative copy.
        if migrated { try FileManager.default.removeItem(at: legacy) }
        var headers: [CareerChatHeader] = []
        try query("SELECT id,title,job,count,updated FROM chats ORDER BY updated DESC") { stmt in
            headers.append(CareerChatHeader(id: String(cString: sqlite3_column_text(stmt,0)), title: String(cString: sqlite3_column_text(stmt,1)), jobID: sqlite3_column_text(stmt,2).map { String(cString: $0) }, count: Int(sqlite3_column_int64(stmt,3)), updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt,4))))
        }
        return headers
    }

    private func insert(_ header: CareerChatHeader) throws {
        try query("INSERT INTO chats VALUES(?,?,?,?,?)", [.text(header.id),.text(header.title),header.jobID.map(Parameter.text) ?? .null,.number(header.updatedAt.timeIntervalSince1970),.integer(header.count)])
    }
    private func insert(_ message: CareerChatMessage, chat: String, pos: Int) throws {
        try query("INSERT INTO messages VALUES(?,?,?)", [.text(chat),.integer(pos),.data(try JSONEncoder().encode(message))])
        for path in message.attachments.compactMap(\.imagePath) {
            try query("INSERT OR IGNORE INTO images VALUES(?,?)", [.text(chat),.text(path)])
        }
    }
    func append(_ message: CareerChatMessage, header: CareerChatHeader) throws -> CareerChatHeader {
        var next = header
        next.updatedAt = Date()
        next.count += 1
        try transaction {
            if header.count == 0 {
                try query("INSERT INTO chats VALUES(?,?,?,?,0) ON CONFLICT(id) DO NOTHING", [.text(header.id),.text(header.title),header.jobID.map(Parameter.text) ?? .null,.number(next.updatedAt.timeIntervalSince1970)])
            }
            try query("UPDATE chats SET title=?,job=?,updated=?,count=? WHERE id=? AND count=?", [.text(next.title),next.jobID.map(Parameter.text) ?? .null,.number(next.updatedAt.timeIntervalSince1970),.integer(next.count),.text(header.id),.integer(header.count)])
            guard sqlite3_changes(db) == 1 else { throw AIError.message("对话已变更，请重新打开后再试。") }
            try insert(message, chat: header.id, pos: header.count)
        }
        return next
    }
    func page(_ id: String, before end: Int, limit: Int = 24) throws -> [CareerChatMessage] {
        var messages: [CareerChatMessage] = []
        try query("SELECT payload FROM messages WHERE chat=? AND pos>=? AND pos<? ORDER BY pos", [.text(id),.integer(max(0,end-limit)),.integer(end)]) { stmt in
            let data = Data(bytes: sqlite3_column_blob(stmt,0), count: Int(sqlite3_column_bytes(stmt,0)))
            messages.append(try JSONDecoder().decode(CareerChatMessage.self, from: data))
        }
        return messages
    }
    func delete(_ id: String, drafts: [String]) throws -> Set<String> {
        try transaction {
            var paths = Set(drafts)
            try query("SELECT path FROM images WHERE chat=?", [.text(id)]) { paths.insert(String(cString: sqlite3_column_text($0,0))) }
            try query("DELETE FROM chats WHERE id=?", [.text(id)])
            var unused = paths
            for path in paths {
                try query("SELECT 1 FROM images WHERE path=? LIMIT 1", [.text(path)]) { _ in unused.remove(path) }
            }
            return unused
        }
    }
}
