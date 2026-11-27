import CoreFoundation
import Foundation

/// Byte-preserving MIME traversal. Attachments (including .txt/.eml files) never
/// enter the AI notification body; multipart/alternative prefers plain text.
enum CareerMailMIME {
  struct Part {
    var headers: [String: String]
    var body: Data
  }
  static func latin(_ data: Data) -> String {
    String(String.UnicodeScalarView(data.map { UnicodeScalar(UInt32($0))! }))
  }
  static func bytes(_ text: String) -> Data {
    Data(text.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
  }
  static func split(_ data: Data) -> Part {
    let text = latin(data).replacingOccurrences(of: "\r\n", with: "\n")
    let split = text.range(of: "\n\n")
    let head = split.map { String(text[..<$0.lowerBound]) } ?? text
    let body = split.map { bytes(String(text[$0.upperBound...])) } ?? Data()
    var headers: [String: String] = [:]
    var key = ""
    for line in head.components(separatedBy: "\n") {
      if line.hasPrefix(" ") || line.hasPrefix("\t") {
        headers[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
      } else if let colon = line.firstIndex(of: ":") {
        key = String(line[..<colon]).lowercased()
        headers[key] = String(line[line.index(after: colon)...]).trimmingCharacters(
          in: .whitespaces)
      }
    }
    return Part(headers: headers, body: body)
  }
  static func parameter(_ key: String, in value: String) -> String? {
    let pattern =
      "(?i)(?:^|;)\\s*" + NSRegularExpression.escapedPattern(for: key)
      + #"\s*=\s*(?:"([^"]*)"|([^;\s]+))"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
    else { return nil }
    for index in [1, 2] {
      if let range = Range(match.range(at: index), in: value) { return String(value[range]) }
    }
    return nil
  }
  static func decode(_ data: Data, charset: String?) -> String {
    let name = (charset ?? "utf-8").lowercased()
    let aliases = ["gbk": "gb18030", "gb2312": "gb18030", "cp936": "gb18030", "utf8": "utf-8"]
    let encoding = CFStringConvertIANACharSetNameToEncoding((aliases[name] ?? name) as CFString)
    if encoding != kCFStringEncodingInvalidId,
      let text = String(
        data: data,
        encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding)))
    {
      return text
    }
    return String(data: data, encoding: .utf8) ?? "[无法解码此正文字符集，请查看原邮件]"
  }
  static func quotedPrintable(_ data: Data) -> Data {
    let input = Array(data)
    let hex: Set<UInt8> = Set(Array("0123456789abcdefABCDEF".utf8))
    var out: [UInt8] = []
    var i = 0
    while i < input.count {
      if input[i] == 61 {
        if i + 1 < input.count, input[i + 1] == 10 {
          i += 2
          continue
        }
        if i + 2 < input.count, input[i + 1] == 13, input[i + 2] == 10 {
          i += 3
          continue
        }
        if i + 2 < input.count, hex.contains(input[i + 1]), hex.contains(input[i + 2]),
          let n = UInt8(String(bytes: input[(i + 1)...(i + 2)], encoding: .ascii)!, radix: 16)
        {
          out.append(n)
          i += 3
          continue
        }
      }
      out.append(input[i])
      i += 1
    }
    return Data(out)
  }
  static func header(_ raw: String) -> String {
    let value = String(data: bytes(raw), encoding: .utf8) ?? raw
    guard let regex = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#) else {
      return value
    }
    var result = value
    for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed()
    {
      guard let full = Range(match.range, in: result),
        let charset = Range(match.range(at: 1), in: value),
        let kind = Range(match.range(at: 2), in: value),
        let payload = Range(match.range(at: 3), in: value)
      else { continue }
      let data =
        value[kind].lowercased() == "b"
        ? Data(base64Encoded: String(value[payload]))
        : quotedPrintable(Data(value[payload].replacingOccurrences(of: "_", with: " ").utf8))
      if let data {
        result.replaceSubrange(full, with: decode(data, charset: String(value[charset])))
      }
    }
    return result
  }
  static func body(_ part: Part, depth: Int = 0) -> String {
    guard depth < 24 else { return "[邮件嵌套层级过深，请查看原文]" }
    let type = part.headers["content-type"] ?? "text/plain"
    let disposition = part.headers["content-disposition"] ?? ""
    guard !disposition.lowercased().hasPrefix("attachment"),
      parameter("filename", in: disposition) == nil, parameter("filename*", in: disposition) == nil,
      parameter("name", in: type) == nil
    else { return "" }
    if type.lowercased().hasPrefix("multipart/"), let boundary = parameter("boundary", in: type) {
      let marker = "--" + boundary
      var chunks: [String] = []
      var current: [String] = []
      var inside = false
      for line in latin(part.body).components(separatedBy: "\n") {
        let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r \t"))
        if clean == marker || clean == marker + "--" {
          if inside {
            chunks.append(current.joined(separator: "\n"))
            current = []
          }
          inside = clean != marker + "--"
          if !inside { break }
        } else if inside {
          current.append(line)
        }
      }
      let children = chunks.map { split(bytes($0)) }.filter {
        !(($0.headers["content-disposition"] ?? "").lowercased().hasPrefix("attachment"))
      }
      if type.lowercased().hasPrefix("multipart/alternative") {
        if let plain = children.first(where: {
          ($0.headers["content-type"] ?? "text/plain").lowercased().hasPrefix("text/plain")
        }), !body(plain, depth: depth + 1).isEmpty {
          return body(plain, depth: depth + 1)
        }
        return children.reversed().map { body($0, depth: depth + 1) }.first(where: { !$0.isEmpty })
          ?? ""
      }
      return children.map { body($0, depth: depth + 1) }.filter { !$0.isEmpty }.joined(
        separator: "\n")
    }
    guard type.lowercased().hasPrefix("text/plain") || type.lowercased().hasPrefix("text/html")
    else { return "" }
    let transfer = (part.headers["content-transfer-encoding"] ?? "").lowercased()
    let data =
      transfer == "base64"
      ? Data(base64Encoded: part.body, options: .ignoreUnknownCharacters) ?? Data()
      : transfer == "quoted-printable" ? quotedPrintable(part.body) : part.body
    let text = decode(data, charset: parameter("charset", in: type))
    guard type.lowercased().hasPrefix("text/html") else { return text }
    return text.replacingOccurrences(
      of: #"(?is)<(script|style)[^>]*>.*?</\1>"#, with: "", options: .regularExpression
    ).replacingOccurrences(
      of: #"(?i)<br\s*/?>|</p>|</div>|</li>"#, with: "\n", options: .regularExpression
    ).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&quot;", with: "\"")
  }
}
