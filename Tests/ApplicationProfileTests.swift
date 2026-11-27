import Foundation
import AppKit

@main struct ApplicationProfileTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }
    @MainActor static func main() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("career-profile-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let storage = ApplicationProfileStorage(directory: temporary)
        var profile = ApplicationProfile()
        profile.values["basic.name"] = "手动确认姓名"
        profile.values["basic.phone"] = "测试号码"
        profile.entries["work"] = [.init(values: ["company": "已有公司", "position": "研发实习生", "responsibilities": "手动补充职责"])]
        profile.entries["custom"] = [.init(values: ["question": "是否接受异地", "answer": "仅上海"])]
        profile.attachments = [.init(name: "测试附件", path: "/private/not-transmitted.pdf", kind: "pdf")]
        try storage.save(profile)
        let restored = try storage.load()
        require(restored == profile, "Persistence round-trip")
        let permissions = try FileManager.default.attributesOfItem(atPath: storage.url.path)[.posixPermissions] as? NSNumber
        require(permissions?.intValue == 0o600, "Sensitive profile permissions")
        require(profile.facts.contains { $0.id == "custom.0.answer" && $0.label == "是否接受异地" && $0.value == "仅上海" }, "Custom question facts")
        require(!profile.facts.contains { $0.value.contains("private/") }, "Attachment paths must stay local")
        require(profile.facts.contains { $0.id == "work.0.company" && $0.section == "work" && $0.entryIndex == 0 }, "Stable facts")
        let original = temporary.appendingPathComponent("测试简历.txt")
        try Data("SOURCE RESUME".utf8).write(to: original)
        let copied = try storage.importAttachment(from: original, kind: "简历")
        let copiedData = try Data(contentsOf: URL(fileURLWithPath: copied.path))
        require(copiedData == Data("SOURCE RESUME".utf8) && copied.name == original.lastPathComponent, "Managed attachment keeps original filename and bytes")
        require(FileManager.default.fileExists(atPath: original.path), "Original attachment is preserved")
        let attachmentPermissions = try FileManager.default.attributesOfItem(atPath: copied.path)[.posixPermissions] as? NSNumber
        require(attachmentPermissions?.intValue == 0o600, "Managed attachment is private")
        print("PASS full profile persistence, private permissions, stable facts, local attachments and custom questions")

        let source = "测试候选人\n邮箱 test@example.invalid\n示例大学 计算机专业 2022.09-2026.06\n新公司 产品实习生 2025.01-2025.06 完成产品调研。\n已有公司 研发实习生 负责测试开发。"
        let rows: [[String: Any]] = [
            ["section":"basic","key":"name","entryIndex":0,"value":"测试候选人","quote":"测试候选人"],
            ["section":"basic","key":"email","entryIndex":0,"value":"test@example.invalid","quote":"邮箱 test@example.invalid"],
            ["section":"education","key":"school","entryIndex":0,"value":"示例大学","quote":"示例大学 计算机专业 2022.09-2026.06"],
            ["section":"education","key":"startDate","entryIndex":0,"value":"2022.09","quote":"示例大学 计算机专业 2022.09-2026.06"],
            ["section":"work","key":"company","entryIndex":0,"value":"新公司","quote":"新公司 产品实习生 2025.01-2025.06 完成产品调研。"],
            ["section":"work","key":"position","entryIndex":0,"value":"产品实习生","quote":"新公司 产品实习生 2025.01-2025.06 完成产品调研。"],
            ["section":"work","key":"company","entryIndex":1,"value":"已有公司","quote":"已有公司 研发实习生 负责测试开发。"],
            ["section":"work","key":"position","entryIndex":1,"value":"研发实习生","quote":"已有公司 研发实习生 负责测试开发。"],
            ["section":"work","key":"responsibilities","entryIndex":1,"value":"负责测试开发。","quote":"已有公司 研发实习生 负责测试开发。"],
            ["section":"basic","key":"gender","entryIndex":0,"value":"男","quote":"测试候选人"],
            ["section":"basic","key":"ethnicity","entryIndex":0,"value":"汉族","quote":"不存在的汉族证据"],
            ["section":"basic","key":"madeUpField","entryIndex":0,"value":"测试候选人","quote":"测试候选人"],
            ["section":"work","key":"company","entryIndex":100,"value":"新公司","quote":"新公司"],
            ["section":"basic","key":"name","entryIndex":1,"value":"测试候选人","quote":"测试候选人"]
        ]
        let json = String(data: try JSONSerialization.data(withJSONObject: ["fields":rows]), encoding: .utf8)!
        let proposal = try ApplicationResumeParser.parseModelJSON(json, source: source, filename: "test.txt")
        require(proposal.suggestions.count == 9 && proposal.rejectedCount == 5, "Unverified evidence and bad fields rejected")
        let merged = proposal.merging(into: profile, selected: Set(proposal.suggestions.map(\.id)))
        require(merged.profile.values["basic.name"] == "手动确认姓名", "Manual basic fact preserved")
        require(merged.profile.values["basic.email"] == "test@example.invalid", "Empty field filled")
        require(merged.profile.values["basic.gender"] == nil, "Gender never inferred")
        require(merged.profile.entries["work"]?.count == 2, "New employer appended, existing entry matched by identity")
        require(merged.profile.entries["work"]?[0].values["responsibilities"] == "手动补充职责", "Manual work content preserved")
        require(merged.profile.entries["work"]?[1].values["company"] == "新公司", "Different employer not combined")
        require(merged.profile.entries["education"]?[0].values["startDate"] == "2022.09", "Original date intact")
        let again = proposal.merging(into: merged.profile, selected: Set(proposal.suggestions.map(\.id)))
        require(again.profile.entries["work"]?.count == 2, "Reimport does not duplicate matched records")
        require(again.added == 0, "Repeat import idempotent")
        var renamed = merged.profile
        renamed.entries["work"]?[1].values["company"] = "手动修改的公司"
        renamed.entries["work"]?[1].values["position"] = ""
        let renamedMerge = proposal.merging(into: renamed, selected: Set(proposal.suggestions.map(\.id)))
        require(renamedMerge.profile.entries["work"]?[1].values["position"] == "", "Provenance must not bypass changed identity")
        require(renamedMerge.profile.entries["work"]?.count == 3, "Original parsed employer gets separate entry after manual rename")
        let partial = proposal.merging(into: profile, selected: Set(proposal.suggestions.filter { $0.key != "company" && $0.key != "school" }.map(\.id)))
        let partialAgain = proposal.merging(into: partial.profile, selected: Set(proposal.suggestions.filter { $0.key != "company" && $0.key != "school" }.map(\.id)))
        require(partialAgain.profile.entries["work"]?.count == partial.profile.entries["work"]?.count, "Deselecting identity does not duplicate experiences")
        let languageFacts: [ApplicationResumeSuggestion] = [
            .init(section: "language", key: "name", entryIndex: 0, value: "英语", quote: "英语"),
            .init(section: "language", key: "exam", entryIndex: 0, value: "CET4", quote: "CET4"),
            .init(section: "language", key: "name", entryIndex: 1, value: "英语", quote: "英语"),
            .init(section: "language", key: "exam", entryIndex: 1, value: "CET6", quote: "CET6")]
        let languageProposal = ApplicationResumeProposal(filename: "test", suggestions: languageFacts, rejectedCount: 0)
        let languages = languageProposal.merging(into: ApplicationProfile(), selected: Set(languageFacts.map(\.id)))
        require(languages.profile.entries["language"]?.count == 2, "Different exams must not combine")
        var ambiguous = ApplicationProfile()
        ambiguous.entries["language"] = [.init(values: ["name": "英语"]), .init(values: ["name": "英语"])]
        let separate = languageProposal.merging(into: ambiguous, selected: Set(languageFacts.map(\.id)))
        require(separate.profile.entries["language"]?[0].values["exam"] == nil && separate.profile.entries["language"]?[1].values["exam"] == nil, "Never choose first ambiguous match")
        print("PASS grounded extraction, malformed facts, original dates, record grouping, manual preservation and idempotent merge")
        do { _ = try ApplicationResumeParser.parseModelJSON("{bad", source: source, filename: "test"); fatalError("Invalid JSON accepted") } catch { }
        do { _ = try ApplicationResumeParser.parseModelJSON("{\"fields\":[]}", source: source, filename: "test"); fatalError("Empty model accepted") } catch { }
        let txt = temporary.appendingPathComponent("resume.txt")
        try source.write(to: txt, atomically: true, encoding: .utf8)
        let extracted = try ApplicationResumeParser.extractText(from: txt)
        require(extracted == source, "Text extraction")
        let store = ApplicationProfileStore(directory: temporary)
        store.profile.values["basic.city"] = "测试城市"
        require(store.save(), "Store save")
        store.profile.values["basic.name"] = "退出前刚修改"
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        let flushed = try storage.load()
        require(flushed.values["basic.name"] == "退出前刚修改", "Pending autosave flushed on termination")
        require(ApplicationProfileCatalog.section("portfolio") != nil && ApplicationProfileCatalog.section("competition") != nil, "Portfolio and competitions covered")
        store.profile.values["basic.preEnrollmentHouseholdCity"] = "湖北省襄阳市襄城区"
        require(store.profile.facts.contains { $0.id == "basic.preEnrollmentHouseholdCity" && $0.value == "湖北省襄阳市襄城区" }, "Confirmed historical address is an independent fact")
        let sourceURL = "https://company.invalid/application/one"
        require(store.captureNewField(label: "专项计划类别", section: "basic", entryIndex: 0, sourceURL: sourceURL), "New field is captured")
        require(!store.captureNewField(label: "专项计划类别", section: "basic", entryIndex: 0, sourceURL: sourceURL), "Repeated scan deduplicates new fields")
        require(!store.profile.facts(forSourceURL: sourceURL).contains { $0.label == "专项计划类别" }, "Unanswered field never generates a fact")
        store.profile.entries["custom"]![store.profile.entries["custom"]!.count-1].values["answer"] = "测试类别"
        require(store.profile.facts(forSourceURL: sourceURL).contains { $0.label == "专项计划类别" && $0.value == "测试类别" && $0.section == "basic" }, "Confirmed new answer reused in its source form")
        require(!store.profile.facts(forSourceURL: "https://company.invalid/application/two").contains { $0.label == "专项计划类别" }, "Company-specific answer does not leak into another application")
        require(!store.captureNewField(label: "专项计划类别：", section: "basic", entryIndex: 0, sourceURL: sourceURL), "Caption punctuation does not duplicate a field")
        for label in ["验证码", "本人承诺信息真实", "I agree to the terms"] {
            require(!store.captureNewField(label: label, section: "basic", entryIndex: 0, sourceURL: sourceURL), "Secrets and declarations are not reusable personal facts")
        }
        let customIndex = store.profile.entries["custom"]!.count - 1
        store.profile.entries["custom"]![customIndex].values["reuseScope"] = "general"
        require(store.profile.facts(forSourceURL: "https://different.invalid/apply").contains { $0.label == "专项计划类别" && $0.section == "basic" }, "Explicitly confirmed general answers can be reused")
        store.profile.entries["custom"]![customIndex].values["reuseScope"] = "source"
        require(!store.profile.facts.contains { $0.label == "专项计划类别" }, "Disabling reuse restores source scope")
        require(store.save(), "New fields saved")
        let captured = try storage.load()
        require(captured.entries["custom"]?.last?.values["question"] == "专项计划类别", "Captured field persisted")
        print("PASS new-field capture, deduplication, confirmed reuse, source isolation and historical address")
        let invalid = Data("invalid JSON".utf8)
        try invalid.write(to: storage.url)
        let corrupted = ApplicationProfileStore(directory: temporary)
        require(!corrupted.save(), "Failed load must not overwrite original")
        let retained = try Data(contentsOf: storage.url)
        require(retained == invalid, "Corrupt cache retained")
        print("PASS malformed model handling, text extraction, store save and corrupted-file preservation")
    }
}
