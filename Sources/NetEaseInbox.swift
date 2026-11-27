import Foundation
import Network

/// NetEase accepts LOGIN before checking the client ID when opening the folder.
/// EXAMINE and BODY.PEEK keep message flags unchanged during import.
final class NetEaseInbox {
  static func supports(_ host: String) -> Bool {
    ["imap.163.com", "imap.126.com"].contains(host.lowercased())
  }

  private let connection: NWConnection
  private let queue = DispatchQueue(label: "OfferFlow.IMAP")
  private var buffer = Data()
  private var sequence = 0
  private var timeout: DispatchWorkItem?
  private static let delimiter = Data([13, 10])

  init(account: CareerMailAccount) throws {
    try CareerMailTransport.validate(account)
    connection = NWConnection(host: NWEndpoint.Host(account.imapHost),
      port: NWEndpoint.Port(rawValue: UInt16(account.imapPort))!, using: .tls)
    connection.start(queue: queue)
  }

  func close() {
    timeout?.cancel()
    connection.cancel()
  }

  private func resetTimeout() {
    timeout?.cancel()
    let task = DispatchWorkItem { [connection] in connection.cancel() }
    timeout = task
    queue.asyncAfter(deadline: .now() + 90, execute: task)
  }

  private static func quoted(_ value: String) throws -> String {
    guard !value.utf8.contains(where: { $0 == 0 || $0 == 10 || $0 == 13 }) else {
      throw AIError.message("邮箱地址、授权码或文件夹名称中含有无效字符。")
    }
    return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }

  private func receive() async throws {
    let chunk: Data = try await withCheckedThrowingContinuation { continuation in
      connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, error in
        if let data, !data.isEmpty { continuation.resume(returning: data) }
        else { continuation.resume(throwing: error.map { $0 as Error } ?? AIError.message("邮箱连接已断开，请重试同步。")) }
      }
    }
    buffer.append(chunk)
  }

  private func line() async throws -> String {
    while true {
      if let end = buffer.range(of: Self.delimiter) {
        let text = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
        buffer.removeSubrange(..<end.upperBound)
        return text
      }
      guard buffer.count < 1_000_000 else { throw AIError.message("邮箱响应格式异常。") }
      try await receive()
    }
  }

  private func command(_ text: String, failure: String, fetch: Bool = false, onLine: (String) -> Void = { _ in }) async throws -> Data? {
    resetTimeout()
    sequence += 1
    let tag = "A\(sequence)"
    let request = Data("\(tag) \(text)\r\n".utf8)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.send(content: request, completion: .contentProcessed { error in
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
      })
    }
    var payload: Data?
    while true {
      let reply = try await line()
      if reply.hasPrefix(tag + " ") {
        let status = reply.split(separator: " ", maxSplits: 2).dropFirst().first
        guard status?.uppercased() == "OK" else { throw AIError.message(failure) }
        return payload
      }
      if reply.uppercased().hasPrefix("* BYE") { throw AIError.message("服务器已结束邮箱连接，请重试同步。") }
      onLine(reply)
      if reply.hasSuffix("}"), let brace = reply.lastIndex(of: "{"),
         let size = Int(reply[reply.index(after: brace)..<reply.index(before: reply.endIndex)]) {
        guard (0...20_000_000).contains(size) else { throw AIError.message("邮件超过 20 MB，本次不导入。") }
        while buffer.count < size { try await receive() }
        if fetch && reply.uppercased().contains("BODY[]") {
          payload = Data(buffer.prefix(size))
        }
        buffer.removeFirst(size)
      }
    }
  }

  func open(_ account: CareerMailAccount, secret: String) async throws {
    resetTimeout()
    let greeting = try await line()
    guard greeting.uppercased().hasPrefix("* OK") else { throw AIError.message("网易暂时无法建立邮箱连接。") }
    _ = try await command("LOGIN \(Self.quoted(account.address)) \(Self.quoted(secret))",
      failure: "网易未接受登录，请核对邮箱地址和客户端授权码。")
    _ = try await command(#"ID ("name" "OfferFlow")"#, failure: "网易未接受客户端标识，请稍后重试。")
    _ = try await command("EXAMINE \(Self.quoted(account.folder))", failure: "登录成功，但网易未允许读取所选文件夹，请核对文件夹名称和邮箱安全提示。")
  }

  func search(since: String) async throws -> String {
    var result: String?
    _ = try await command("UID SEARCH SINCE " + since, failure: "网易未能搜索收件箱，请重试。") { line in
      if line == "* SEARCH" || line.hasPrefix("* SEARCH ") { result = line }
    }
    guard let result else { throw AIError.message("网易未返回可识别的搜索结果。") }
    return result
  }

  func message(uid: String) async throws -> Data {
    guard UInt32(uid) != nil, let body = try await command("UID FETCH \(uid) (BODY.PEEK[])",
      failure: "网易未能读取这封邮件，请刷新后重试。", fetch: true)
    else { throw AIError.message("未收到所选邮件的正文，请重新同步。") }
    return body
  }
}
