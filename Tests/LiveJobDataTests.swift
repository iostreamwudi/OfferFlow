import Foundation

@main struct LiveJobDataTests {
    static func check(_ value: Bool) { precondition(value) }
    static func requireFailure(_ message: String, _ action: () throws -> Void) {
        do { try action(); fatalError(message) } catch { }
    }

    static func row(company: String = "测试公司", title: String = "AI 产品经理",
                    date: String = "2026/11/17", apply: String = "https://example.com/jobs?a=1#apply") -> [String] {
        [date, company, "民企", "IT", title, "上海", "尽快投递", "2027届", "本科", "秋招专场",
         "公司官网", "https://example.com/notice", apply, "备注", "计算机", "有笔试", "", "", "", "", "", "", ""]
    }

    static func parse(_ rows: [[String]], date: Date = Date(timeIntervalSince1970: 1_700_000_000)) throws -> LiveJobSnapshot {
        try LiveJobParser.parse(rows.map { $0.joined(separator: "\t") }.joined(separator: "\n"),
            expectedRecordCount: rows.count, headers: LiveJobParser.expectedHeaders, fetchedAt: date)
    }

    static func main() throws {
        var multiline = row(title: "产品经理\nAI 研发经理", apply: "https://example.com/a\nhttps://example.com/b?q=1")
        multiline[5] = "上海\n北京"
        multiline[13] = "第一行\r\r第二行\n第三行"
        multiline[14] = "计算机\n金融"
        let original = try parse([multiline])
        precondition(original.listings[0].rawFields == multiline)
        precondition(original.listings[0].applicationURLs.count == 2 && original.listings[0].applyURL == nil)
        precondition(original.listings[0].sourceRecordId == nil)
        precondition(original.latestSourceUpdated == "2026/11/17")
        print("PASS embedded LF/CR, intact long fields, multiple explicit URLs, no invented source ID")

        let data = row().joined(separator: "\t")
        check(LiveJobParser.fingerprint(text: "abc") ==
              "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        check(original.sourceFingerprint == LiveJobParser.fingerprint(text: multiline.joined(separator: "\t")))
        check(LiveJobParser.fingerprint(text: data) != LiveJobParser.fingerprint(text: data + "\n"))
        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        legacyJSON.removeValue(forKey: "sourceFingerprint")
        let legacy = try JSONDecoder().decode(LiveJobSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacyJSON))
        check(legacy.sourceFingerprint == nil && legacy.listings == original.listings)
        try legacy.validate()
        for fingerprint in ["", "abc", String(repeating: "g", count: 64), String(repeating: "0", count: 63)] {
            var corrupt = original; corrupt.sourceFingerprint = fingerprint
            requireFailure("Invalid source fingerprint must fail") { try corrupt.validate() }
        }
        print("PASS exact source fingerprint, invalid fingerprint rejection and legacy cache compatibility")
        var changedHeaders = LiveJobParser.expectedHeaders; changedHeaders.swapAt(1, 4)
        requireFailure("Must reject changed headers") {
            _ = try LiveJobParser.parse(data, expectedRecordCount: 1, headers: changedHeaders)
        }
        requireFailure("Must reject changed column count") { _ = try parse([Array(row().dropLast())]) }
        requireFailure("Must reject raw cell tabs") { _ = try parse([row(title: "岗位\t错误")]) }
        requireFailure("Must reject source count mismatch") {
            _ = try LiveJobParser.parse(data, expectedRecordCount: 2, headers: LiveJobParser.expectedHeaders)
        }
        requireFailure("Must reject incomplete clipboard") {
            _ = try LiveJobParser.parse(data + "\n2026/11/17\t半条记录", expectedRecordCount: 2,
                                       headers: LiveJobParser.expectedHeaders)
        }
        requireFailure("Must reject boundary newlines") { _ = try parse([row(date: "\n2026/11/17")]) }
        requireFailure("Must reject mismatched date fields") { _ = try parse([row(date: "测试公司")]) }
        requireFailure("Must reject invalid dates") { _ = try parse([row(date: "2026/02/30")]) }
        requireFailure("Must not publish an empty copy") {
            _ = try LiveJobParser.parse("", expectedRecordCount: 0, headers: LiveJobParser.expectedHeaders)
        }
        print("PASS changed schema, truncation, count mismatch, ambiguous delimiters and invalid source dates")

        let oldRow = row(date: "2026/11/16")
        var newRow = row(date: "2026/11/17"); newRow[6] = "2026-12-31"; newRow[14] = "新增专业要求"
        let empty = Array(repeating: "", count: 23)
        var partial = empty; partial[2] = "事业单位"
        let snapshot = try parse([oldRow, oldRow, newRow, empty, partial])
        precondition(snapshot.listings.count == 1 && snapshot.listings[0].deadline == "2026-12-31")
        precondition(snapshot.sourceRecordCount == 5 && snapshot.skippedRecordCount == 2)
        precondition(snapshot.duplicateRecordCount == 2 && snapshot.exactDuplicateRecordCount == 1)
        precondition(LiveJobListing(fields: oldRow).id == LiveJobListing(fields: newRow).id)
        precondition(LiveJobListing(fields: row(title: "另一个岗位")).id != snapshot.listings[0].id)
        print("PASS empty/missing rows, exact duplicates, newest duplicate data, stable local favorite identity")

        for invalid in ["javascript:alert(1)", "file:///tmp/test", "https://example.com/ x", "https://user:password@example.com",
                        "报名 https://example.com", "https://example.com\u{0}bad"] {
            precondition(LiveJobListing.safeHTTPURL(invalid) == nil)
        }
        precondition(LiveJobListing.safeHTTPURL("https://example.com/?q=a%20b&x=1#apply")?.absoluteString ==
                     "https://example.com/?q=a%20b&x=1#apply")
        print("PASS scheme, credentials and ambiguous text URL restrictions; query/fragment preserved")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LiveJobCache(directory: directory)
        check(try cache.load() == nil)
        check(try cache.loadFavorites().isEmpty)
        try cache.save(snapshot)
        try cache.saveFavorites([snapshot.listings[0].id, "saved-record-no-longer-in-current-view"])
        check(try cache.load() == snapshot)
        let savedFavorites = try cache.loadFavorites()
        try cache.save(try parse([row(company: "新公司")]))
        check(try cache.loadFavorites() == savedFavorites)
        let before = try Data(contentsOf: cache.snapshotURL)
        var invalid = snapshot; invalid.sourceRecordCount = 100
        requireFailure("Invalid save must fail") { try cache.save(invalid) }
        check(try Data(contentsOf: cache.snapshotURL) == before)
        var overflowed = snapshot
        overflowed.skippedRecordCount = Int.max
        overflowed.duplicateRecordCount = Int.max
        requireFailure("Corrupt cache counters must throw without overflowing") { try cache.save(overflowed) }
        check(try Data(contentsOf: cache.snapshotURL) == before)
        let blockedDirectory = directory.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blockedDirectory)
        requireFailure("Disk write must fail") { try LiveJobCache(directory: blockedDirectory).save(snapshot) }
        check(try Data(contentsOf: cache.snapshotURL) == before)
        var unknownVersion = snapshot; unknownVersion.version = 100
        try JSONEncoder().encode(unknownVersion).write(to: cache.snapshotURL, options: .atomic)
        requireFailure("Unknown cache version must fail") { _ = try cache.load() }
        print("PASS atomic cache persistence, independent favorites, failed saves and incompatible cache rejection")

        if CommandLine.arguments.count > 1 {
            let started = Date()
            let fixture = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
            let result = try LiveJobParser.parse(fixture, expectedRecordCount: 14_249,
                headers: LiveJobParser.expectedHeaders)
            precondition(result.sourceRecordCount == 14_249 && result.skippedRecordCount == 21)
            precondition(result.exactDuplicateRecordCount == 71)
            precondition(result.listings.count + result.duplicateRecordCount == 14_228)
            precondition(result.listings.contains { $0.rawFields.contains(where: { $0.contains("\r\r") }) })
            precondition(result.listings.first?.company == "江苏省数据集团")
            precondition(result.listings.first?.applyURL?.absoluteString == "https://jsdg2026.zhaopin.com/campus/index.html")
            try cache.save(result)
            check(try cache.load() == result)
            print("PASS real 14,249-record fixture: \(result.listings.count) listings, \(result.duplicateRecordCount) duplicates, \(Date().timeIntervalSince(started))s including disk round-trip")
        }
        print("All live job data checks passed.")
    }
}
