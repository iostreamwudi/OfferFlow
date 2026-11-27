import Foundation

@main struct CareerChatStreamTests {
    static func main() throws {
        let raw = #"{"intents":[{"answer":"nested"}],"sources":["answer"],"answer":"中文\n\t\"引号\"\\\uD83D\uDE00","actions":["hidden"]}"#
        let expected = "中文\n\t\"引号\"\\😀"
        var parser = CareerAnswerDeltas()
        var preview = ""
        for scalar in raw.unicodeScalars {
            parser.consume(String(scalar))
            preview += parser.takeText() ?? ""
            precondition(expected.hasPrefix(preview))
        }
        precondition(preview == expected)

        let line = "中文回复 12345\n"
        let encoded = try JSONEncoder().encode(line)
        let delta = String(decoding: encoded.dropFirst().dropLast(), as: UTF8.self)
        var longReply = CareerAnswerDeltas()
        longReply.consume(#"{"answer":""#)
        for _ in 0..<10_000 {
            longReply.consume(delta)
            precondition(longReply.takeText() == line)
        }
        longReply.consume(#"","actions":["profile"]}"#)
        precondition(longReply.takeText() == nil)
        print("PASS incremental replies, split JSON escapes and surrogate pairs, nested fields and 10,000 batches")
    }
}
