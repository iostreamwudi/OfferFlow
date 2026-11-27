import CryptoKit
import Foundation
import Security

struct CareerMailAccount: Codable, Identifiable, Hashable {
  var id = UUID().uuidString
  var address = ""
  var imapHost = ""
  var imapPort = 993
  var smtpHost = ""
  var smtpPort = 465
  var folder = "INBOX"
  var syncDays: Int? = nil
  var syncPageSize: Int? = nil
  var autoSyncMinutes: Int? = nil
  var autoAnalyze: Bool? = nil
  var lookbackDays: Int { max(1, min(syncDays ?? 30, 3650)) }
  var pageSize: Int { max(10, min(syncPageSize ?? 50, 500)) }
}
enum CareerMailSecrets {
  static func save(_ value: String, id: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "CareerAI.Mail",
      kSecAttrAccount as String: id,
    ]
    let data = Data(value.utf8)
    let update = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if update == errSecItemNotFound {
      var insert = query
      insert[kSecValueData as String] = data
      guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
        throw AIError.message("无法保存邮箱授权码到钥匙串。")
      }
    } else if update != errSecSuccess {
      throw AIError.message("钥匙串更新失败。")
    }
  }
  static func read(_ id: String) throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "CareerAI.Mail",
      kSecAttrAccount as String: id, kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { throw AIError.message("请先配置邮箱授权码。") }
    guard status == errSecSuccess else {
      throw AIError.message("无法读取本机钥匙串中的邮箱授权码（\(status)）。请解锁登录钥匙串，并在系统提示中允许 OfferFlow 访问。")
    }
    guard let data = item as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty
    else { throw AIError.message("请先配置邮箱授权码。") }
    return value
  }
  static func remove(_ id: String) {
    SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "CareerAI.Mail",
        kSecAttrAccount as String: id,
      ] as CFDictionary)
  }
}
struct CareerMailMessage: Codable, Identifiable, Equatable {
  var id: String
  var accountID: String
  var uid: String
  var subject: String
  var from: String
  var date: String
  var body: String
  var raw: String
  var rawEncoding: String? = nil
}
enum CareerMailTransport {
  static func validate(_ account: CareerMailAccount) throws {
    let hostPattern = #"^[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$"#
    guard account.address.range(of: #"^[^\s@:]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#, options: .regularExpression) != nil,
      [account.imapHost, account.smtpHost].allSatisfy({
        $0.range(of: hostPattern, options: .regularExpression) != nil
      }), (1...65535).contains(account.imapPort), (1...65535).contains(account.smtpPort),
      !account.folder.isEmpty
    else { throw AIError.message("请填写有效邮箱、IMAP/SMTP 主机和端口。") }
  }
  private static func quoted(_ s: String) -> String {
    "\""
      + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
      + "\""
  }
  static func request(
    account: CareerMailAccount, url: String, command: String? = nil, message: Data? = nil,
    recipient: String? = nil, secretOverride: String? = nil
  ) async throws -> Data {
    try validate(account)
    let secret = try secretOverride ?? CareerMailSecrets.read(account.id)
    var config = "user = \(quoted(account.address+":"+secret))\nssl-reqd\nsilent\nshow-error\nconnect-timeout = 20\nmax-time = 90\nurl = \(quoted(url))\n"
    if let command { config += "request = \(quoted(command))\n" }
    if let recipient {
      config += "mail-from = \(quoted(account.address))\nmail-rcpt = \(quoted(recipient))\n"
    }
    let initialConfig = config
    return try await Task.detached(priority: .userInitiated) {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "career-mail-" + UUID().uuidString)
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      defer { try? FileManager.default.removeItem(at: directory) }
      var config = initialConfig
      if let message {
        let file = directory.appendingPathComponent("message.eml")
        try message.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        config += "upload-file = \(quoted(file.path))\n"
      }
      let out = directory.appendingPathComponent("out")
      let err = directory.appendingPathComponent("err")
      FileManager.default.createFile(
        atPath: out.path, contents: nil, attributes: [.posixPermissions: 0o600])
      FileManager.default.createFile(
        atPath: err.path, contents: nil, attributes: [.posixPermissions: 0o600])
      let output = try FileHandle(forWritingTo: out)
      let errors = try FileHandle(forWritingTo: err)
      defer {
        try? output.close()
        try? errors.close()
      }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
      process.arguments = ["-q", "--config", "-"]
      let input = Pipe()
      process.standardInput = input
      process.standardOutput = output
      process.standardError = errors
      try process.run()
      input.fileHandleForWriting.write(Data(config.utf8))
      try input.fileHandleForWriting.close()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw AIError.message(CareerMailProvider.failureMessage(process.terminationStatus))
      }
      let result = try Data(contentsOf: out)
      guard result.count < 20_000_000 else { throw AIError.message("邮件超过 20 MB，本次不导入。") }
      return result
    }.value
  }
  static func searchUIDs(_ account: CareerMailAccount, secretOverride: String? = nil) async throws -> [String] {
    let folder =
      account.folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "INBOX"
    let url = "imaps://\(account.imapHost):\(account.imapPort)/\(folder)"
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "dd-MMM-yyyy"
    let since = formatter.string(
      from: Date().addingTimeInterval(-Double(account.lookbackDays) * 86400))
    let result: String
    if NetEaseInbox.supports(account.imapHost) {
      let secret = try secretOverride ?? CareerMailSecrets.read(account.id)
      let inbox = try NetEaseInbox(account: account)
      defer { inbox.close() }
      try await inbox.open(account, secret: secret)
      result = try await inbox.search(since: since)
    } else {
      result = String(decoding: try await request(account: account, url: url,
        command: "UID SEARCH SINCE \(since)", secretOverride: secretOverride), as: UTF8.self)
    }
    guard
      let line = result.components(separatedBy: .newlines).first(where: { $0.hasPrefix("* SEARCH") }
      )
    else { throw AIError.message("邮箱未返回可识别的搜索结果，本机邮件保持不变。") }
    return line.split(separator: " ").dropFirst(2).compactMap { Int($0) }.sorted(by: >).map(
      String.init)
  }
  static func fetchPage(
    _ account: CareerMailAccount, uids: [String], secretOverride: String? = nil, shouldStop: @MainActor () -> Bool = { false }
  ) async throws -> [CareerMailMessage] {
    let folder =
      account.folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "INBOX"
    let url = "imaps://\(account.imapHost):\(account.imapPort)/\(folder)"
    let secret = try secretOverride ?? CareerMailSecrets.read(account.id)
    var messages: [CareerMailMessage] = []
    if NetEaseInbox.supports(account.imapHost), !uids.isEmpty {
      let inbox = try NetEaseInbox(account: account)
      defer { inbox.close() }
      try await inbox.open(account, secret: secret)
      for uid in uids {
        try Task.checkCancellation()
        if await shouldStop() { throw CancellationError() }
        let data = try await inbox.message(uid: uid)
        messages.append(parse(data, accountID: account.id, uid: uid))
      }
      return messages
    }
    for uid in uids {
      try Task.checkCancellation()
      if await shouldStop() { throw CancellationError() }
      let response = try await request(
        account: account, url: url, command: "UID FETCH \(uid) BODY.PEEK[]", secretOverride: secret)
      let prefix = String(decoding: response.prefix(4096), as: UTF8.self)
      var data = response
      if let regex = try? NSRegularExpression(pattern: #"\{(\d+)\}\r?\n"#),
        let match = regex.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)),
        let countRange = Range(match.range(at: 1), in: prefix),
        let fullRange = Range(match.range, in: prefix), let count = Int(prefix[countRange])
      {
        let offset = prefix[..<fullRange.upperBound].utf8.count
        guard count <= 20_000_000, response.count >= offset + count else {
          throw AIError.message("邮件服务器返回了不完整的正文。")
        }
        data = response.subdata(in: offset..<(offset + count))
      }
      messages.append(parse(data, accountID: account.id, uid: String(uid)))
    }
    return messages
  }
  static func parse(_ data: Data, accountID: String, uid: String) -> CareerMailMessage {
    let part = CareerMailMIME.split(data)
    let headers = part.headers
    let id = SHA256.hash(
      data: Data(
        (accountID + "|" + (headers["message-id"] ?? uid) + "|" + (headers["date"] ?? "")).utf8)
    ).map { String(format: "%02x", $0) }.joined()
    return .init(
      id: id, accountID: accountID, uid: uid,
      subject: CareerMailMIME.header(headers["subject"] ?? "无主题"),
      from: CareerMailMIME.header(headers["from"] ?? ""), date: headers["date"] ?? "",
      body: CareerMailMIME.body(part), raw: CareerMailMIME.latin(data), rawEncoding: "latin1")
  }
  static func send(
    account: CareerMailAccount, to: String, subject: String, body: String, attachment: URL?
  ) async throws {
    guard to.range(of: #"^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$"#, options: .regularExpression) != nil,
      !subject.contains(where: { $0.isNewline })
    else { throw AIError.message("请填写一个有效收件人和单行主题。") }
    let boundary = "CareerAI-" + UUID().uuidString
    func b64(_ data: Data) -> String {
      let value = data.base64EncodedString()
      return stride(from: 0, to: value.count, by: 76).map { start in
        let a = value.index(value.startIndex, offsetBy: start)
        let b = value.index(a, offsetBy: min(76, value.count - start))
        return String(value[a..<b])
      }.joined(separator: "\r\n")
    }
    var text =
      "From: \(account.address)\r\nTo: \(to)\r\nSubject: =?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?=\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n\r\n--\(boundary)\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n\(b64(Data(body.utf8)))\r\n"
    if let attachment {
      let data = try Data(contentsOf: attachment)
      guard data.count <= 20_000_000 else { throw AIError.message("附件超过 20 MB。") }
      let filename =
        attachment.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        ?? "resume.pdf"
      text +=
        "--\(boundary)\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename*=UTF-8''\(filename)\r\nContent-Transfer-Encoding: base64\r\n\r\n\(b64(data))\r\n"
    }
    text += "--\(boundary)--\r\n"
    let scheme = account.smtpPort == 465 ? "smtps" : "smtp"
    _ = try await request(
      account: account, url: "\(scheme)://\(account.smtpHost):\(account.smtpPort)",
      message: Data(text.utf8), recipient: to)
  }
}
