import Foundation

@main struct FlowJourneyTests {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("offerflow-journey-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(storageDirectory: directory)
        store.jobs = []; store.applications = [:]
        precondition(ApplicationRecording.roleChoices(",AI 产品经理,算法工程师；产品经理（AI、数据方向）,AI 产品经理") == ["AI 产品经理", "算法工程师", "产品经理（AI、数据方向）"])
        precondition(ApplicationRecording.roleChoices(" , ").isEmpty)
        let address = "https://careers.example.com/jobs"
        let first = store.trackApplication(company: "示例公司", role: "产品经理", url: address)!
        precondition(store.applications[first]?.stage == .planned)
        store.recordFormProgress(first, state: "填写结束 · 待核对提交", resumeVersion: "test")
        precondition(store.applications[first]?.stage == .planned)
        let second = store.trackApplication(company: "示例公司", role: "后端工程师", url: address)!
        precondition(first != second && store.jobs.count == 2)
        precondition(store.trackApplication(company: "示例公司", role: "产品经理", url: address) == first)
        precondition(store.trackApplication(company: "示例公司", role: "", url: address) == nil)
        let time = Date(timeIntervalSince1970: 2_000_000_000)
        _ = store.updateApplication(first, stage: .submitted, notes: "等待回复", followUpAt: time)
        let projected = FlowCalendarProjection.followups(jobs: store.jobs, applications: store.applications, existing: [])
        precondition(projected.count == 1 && projected[0].jobID == first)
        var custom = projected[0]; custom.reminderMinutes = 60; custom.notes = "向 HR 确认时间"
        _ = store.updateApplication(first, stage: nil, notes: "等待回复", followUpAt: time.addingTimeInterval(3600))
        let moved = FlowCalendarProjection.followups(jobs: store.jobs, applications: store.applications, existing: [custom])
        precondition(moved.count == 1 && moved[0].id == custom.id && moved[0].start == time.addingTimeInterval(3600))
        precondition(moved[0].notes == custom.notes && moved[0].reminderMinutes == 60)
        let manual = CareerCalendarEvent(title: "人工创建面试")
        let combined = FlowCalendarProjection.replacing([custom, manual], prefix: "followup-", desired: moved)
        precondition(combined.count == 2 && combined.contains(where: { $0.id == manual.id }))
        _ = store.updateApplication(first, stage: nil, notes: "已跟进", followUpAt: nil)
        precondition(FlowCalendarProjection.followups(jobs: store.jobs, applications: store.applications, existing: combined).isEmpty)
        precondition(FlowCalendarProjection.replacing(combined, prefix: "followup-", desired: []).map(\.id) == [manual.id])
        let review = FlowCalendarProjection.event(source: "review-test", company: "示例", role: "产品经理", kind: "复习", date: time, duration: 1800, existing: [])
        let reviewMoved = FlowCalendarProjection.event(source: "review-test", company: "示例", role: "产品经理", kind: "复习", date: time.addingTimeInterval(86400), duration: 1800, existing: [review])
        precondition(review.id == reviewMoved.id)
        precondition(FlowCalendarProjection.replacing([reviewMoved, manual], prefix: "review-", desired: []).count == 1)
        precondition(store.renameApplication(first, company: "更正公司", role: "高级产品经理"))
        store.recordFormProgress(first, state: "填写结束 · 待核对提交", resumeVersion: "version-test")
        let restored = Store(storageDirectory: directory)
        precondition(restored.jobs.first(where: { $0.id == first })?.title == "高级产品经理")
        precondition(restored.applications[first]?.stage == .submitted && restored.applications[first]?.resumeVersion == "version-test")
        print("PASS company + role identity, repeat opening, status persistence, rename, calendar update/cancellation and stable review IDs")

        let original = ResumeMaterial(filename: "old.pdf", name: "示例用户", text: "旧简历中的旧经历")
        var profile = ApplicationProfile()
        profile.values["basic.name"] = "示例用户"
        profile.values["basic.documentNumber"] = "SECRET-ID"
        precondition(CandidateMaterials.resolve(profile: profile, original: original)?.text == original.text)
        profile.entries["project"] = [ApplicationProfileEntry(values: ["name": "新项目", "description": "已确认的新项目事实"])]
        let effective = CandidateMaterials.resolve(profile: profile, original: original)!
        precondition(effective.text.contains("新项目") && !effective.text.contains("旧经历") && !effective.text.contains("SECRET-ID"))
        let suggestion = ApplicationResumeSuggestion(section: "basic", key: "name", entryIndex: 0, value: "更新姓名", quote: "更新姓名")
        let proposal = ApplicationResumeProposal(filename: "new.pdf", suggestions: [suggestion], rejectedCount: 0)
        precondition(proposal.merging(into: profile, selected: [suggestion.id]).profile.values["basic.name"] == "示例用户")
        precondition(proposal.merging(into: profile, selected: [suggestion.id], replaceExisting: true).profile.values["basic.name"] == "更新姓名")
        print("PASS one coherent professional source, private data excluded, original fallback and explicit profile update")

        func card(_ id: String, company: String = "示例公司") -> BossCard { .init(title: "岗位" + id, company: company, city: "上海", salary: "", experience: "", tags: [], url: "https://www.zhipin.com/job_detail/\(id).html") }
        let cards = [card("abc"), card("def"), card("ghi", company: "第二家公司")]
        func prepare(_ book: BossBatchBook = BossBatchBook(), one: Bool = false, skip: Bool = false) -> [BossBatchItem] { BossBatchPolicy.prepare(cards, book: book, jobs: [], applications: [:], onePerCompany: one, skipContactedCompany: skip) }
        precondition(prepare().filter { $0.state == .queued }.count == 3)
        precondition(prepare(one: true).filter { $0.state == .queued }.count == 2)
        var uncertain = BossBatchItem(card: cards[0]); uncertain.state = .uncertain
        let book = BossBatchBook(items: [uncertain])
        precondition(prepare(book).filter { $0.state == .queued }.map { $0.card.id } == [cards[1].id, cards[2].id])
        precondition(prepare(book, skip: true).filter { $0.state == .queued }.map { $0.card.id } == [cards[2].id])
        precondition(BossBatchPolicy.prepare([cards[0], cards[0]], book: BossBatchBook(), jobs: [], applications: [:], onePerCompany: false, skipContactedCompany: false).filter { $0.state == .queued }.count == 1)
        print("PASS per-role selection, optional per-company dedupe, repeated URLs and uncertain-send blocking; no network sends")

        let intent = FlowIntent(route: "coach", jobID: first, company: "更正公司", role: "高级产品经理", round: "二面")
        let restoredIntent = try JSONDecoder().decode(FlowIntent.self, from: JSONEncoder().encode(intent))
        precondition(restoredIntent == intent)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored.applications[first]!)) as! [String: Any]
        legacy.removeValue(forKey: "formState"); legacy.removeValue(forKey: "resumeVersion")
        let oldRecord = try JSONDecoder().decode(ApplicationRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(oldRecord.formState == nil && oldRecord.resumeVersion == nil)
        print("PASS route context round-trip and old application records")
    }
}
