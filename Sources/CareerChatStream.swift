import Foundation

enum CareerChatStream {
    static func text(_ request: URLRequest, update: @MainActor (String) -> Void) async throws -> String {
        let (bytes, response) = try await ArkClient.session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.message("模型请求失败，请检查网络、模型配置和额度。")
        }
        var json = ""
        var answer = CareerAnswerDeltas()
        var nextUpdate = ContinuousClock.now
        if http.mimeType == "application/json" {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  result["status"] as? String == "completed" else { throw AIError.message("模型未完成回答。") }
            return output(result)
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let event = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
            switch event["type"] as? String {
            case "response.output_text.delta":
                let delta = event["delta"] as? String ?? ""
                json += delta
                answer.consume(delta)
                if ContinuousClock.now >= nextUpdate, let addition = answer.takeText() {
                    await update(addition)
                    nextUpdate = ContinuousClock.now.advanced(by: .milliseconds(160))
                }
            case "response.completed":
                let result = event["response"] as? [String: Any] ?? [:]
                let final = output(result)
                return final.isEmpty ? json : final
            case "error", "response.failed", "response.incomplete":
                throw AIError.message("本次回答未完成，请稍后重试。")
            default: continue
            }
        }
        throw AIError.message("回答连接已中断，请稍后重试。")
    }

    private static func output(_ response: [String: Any]) -> String {
        (response["output"] as? [[String: Any]] ?? [])
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .filter { $0["type"] as? String == "output_text" }
            .compactMap { $0["text"] as? String }.joined()
    }
}

// Frame just the top-level answer string. Decode each batch with Foundation so
// escapes and surrogate pairs can span network events without corrupting text.
struct CareerAnswerDeltas {
    private enum StringKind { case key, other, answer }
    private var depth = 0
    private var expectingKey = false
    private var answerValue = false
    private var string: StringKind?
    private var key: [UInt8] = []
    private var escaped = false
    private var finished = false
    private var pending = Data()

    mutating func consume(_ delta: String) {
        guard !finished else { return }
        for byte in delta.utf8 {
            if let kind = string {
                if !escaped && byte == 34 {
                    string = nil
                    if kind == .answer { finished = true; return }
                    answerValue = kind == .key && key.elementsEqual("answer".utf8)
                    expectingKey = false
                } else {
                    if kind == .key && key.count <= 6 { key.append(byte) }
                    if kind == .answer { pending.append(byte) }
                    escaped = !escaped && byte == 92
                }
                continue
            }
            switch byte {
            case 34:
                string = depth == 1 && expectingKey ? .key : answerValue ? .answer : .other
                key.removeAll(keepingCapacity: true)
                escaped = false
            case 123, 91:
                depth += 1
                expectingKey = depth == 1 && byte == 123
                answerValue = false
            case 125, 93:
                depth -= 1
                answerValue = false
            case 44:
                expectingKey = depth == 1
                answerValue = false
            default: break
            }
        }
    }

    mutating func takeText() -> String? {
        guard !pending.isEmpty else { return nil }
        var quoted = Data([34])
        quoted.append(pending)
        quoted.append(34)
        // If the batch ends inside an escape, retain it until the next delta.
        guard let text = try? JSONDecoder().decode(String.self, from: quoted) else { return nil }
        pending.removeAll(keepingCapacity: true)
        return text
    }
}
