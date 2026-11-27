import Foundation
import AppKit
import WebKit

@MainActor final class Runner: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    let extractor: String
    var index = 0
    let fullJD = "负责大模型与 RAG 产品设计，完成需求分析与效果评估。与工程团队合作改进检索质量，分析用户反馈并持续迭代产品。"
    var cases: [(String, String, (BossReadResult) -> Bool)] = []
    init(extractor: String) {
        self.extractor = extractor
        super.init()
        web.navigationDelegate = self
        let card = """
        <div class="job-card-wrap"><a href="/job_detail/abc123.html"><span class="job-name">AI 产品经理</span></a><span class="salary">20–30K</span><ul class="tag-list"><li>1-3年</li><li>本科</li><li>RAG</li></ul><a href="/gongsi/company.html">测试企业</a><span class="company-location">上海·徐汇区</span></div>
        """
        cases = [
            ("list-dedupe-fields", "<html><body>" + card + card + "<div style='display:none'>" + card.replacingOccurrences(of: "abc123", with: "hidden") + "</div></body></html>", { result in
                result.cards.count == 1 && result.cards[0].city == "上海·徐汇区" && result.cards[0].salary == "20–30K" && result.cards[0].experience == "1-3年 · 本科" && result.cards[0].url == "https://www.zhipin.com/job_detail/abc123.html"
            }),
            ("list-over-60", "<html><body>" + (0..<137).map { card.replacingOccurrences(of: "abc123", with: "job\($0)") }.joined() + card.replacingOccurrences(of: "abc123", with: "job136") + "<div style='display:none'>" + card.replacingOccurrences(of: "abc123", with: "hidden") + "</div></body></html>", { result in
                result.cards.count == 137 && Set(result.cards.map(\.url)).count == 137 && result.cards.last?.url == "https://www.zhipin.com/job_detail/job136.html"
            }),
            ("full-detail", "<html><body><div class='job-banner'><h1>AI 产品经理</h1><span class='salary'>25-40K·16薪</span><p>上海 3-5年 本科</p></div><div class='company-info'><span class='name'>测试企业</span></div><div class='job-sec-text'>\(fullJD)</div><div style='display:none'>登录查看完整内容</div></body></html>", { $0.detail?.complete == true && $0.detail?.title == "AI 产品经理" && $0.detail?.company == "测试企业" && $0.detail?.salary == "25-40K·16薪" && $0.detail?.city == "上海" }),
            ("truncated-detail", "<html><body><h1>AI 产品经理</h1><div class='job-sec-text'>\(fullJD)</div><div>登录查看完整内容</div></body></html>", { $0.detail?.complete == false }),
            ("verification", "<html><body><h1>安全验证</h1><div>请完成验证</div></body></html>", { $0.gated && $0.detail?.complete == false }),
            ("search-preview", "<html><body><a href='/job_detail/current.html?securityId=test'>查看更多信息</a></body></html>", { $0.detail == nil && $0.previewURL == "https://www.zhipin.com/job_detail/current.html" })
        ]
    }
    func start() {
        let url = cases[index].0.hasPrefix("list-") || cases[index].0 == "search-preview" ? "https://www.zhipin.com/web/geek/jobs" : "https://www.zhipin.com/job_detail/abc123.html"
        web.loadHTMLString(cases[index].1, baseURL: URL(string: url))
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = cases[index].0.hasPrefix("list-") || cases[index].0 == "search-preview" ? "https://www.zhipin.com/web/geek/jobs" : "https://www.zhipin.com/job_detail/abc123.html"
        let quotedURL = String(data: try! JSONEncoder().encode(url), encoding: .utf8)!
        let script = extractor.replacingOccurrences(of: "location.href", with: quotedURL)
        web.evaluateJavaScript(script) { value, error in
            guard error == nil, let raw = value as? String, let data = raw.data(using: .utf8), let result = try? JSONDecoder().decode(BossReadResult.self, from: data), self.cases[self.index].2(result) else {
                print("FAIL \(self.cases[self.index].0): \(error?.localizedDescription ?? String(describing: value))")
                exit(1)
            }
            print("PASS \(self.cases[self.index].0)")
            self.index += 1
            if self.index == self.cases.count { print("All connector checks passed."); exit(0) }
            self.start()
        }
    }
}

@main struct ConnectorTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let url = BossSite.searchURL(keyword: "AI 产品经理 & RAG", city: "上海")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(query.first { $0.name == "query" }!.value == "AI 产品经理 & RAG")
        precondition(query.first { $0.name == "city" }!.value == "101020100")
        precondition(BossSite.canonical("https://www.zhipin.com/job_detail/abc123.html?securityId=test") == "https://www.zhipin.com/job_detail/abc123.html")
        precondition(BossSite.canonical("https://www.zhipin.com.evil.test/job_detail/abc123.html") == nil)
        precondition(BossSite.canonical("http://www.zhipin.com/job_detail/abc123.html") == nil)
        print("PASS URL encoding, canonicalization, and host restrictions")
        let detail = BossDetail(title: "当前岗位", company: "当前公司", jd: "当前岗位的完整 JD 内容", url: "https://www.zhipin.com/job_detail/current.html", complete: true, salary: "14-17K", city: "上海", experience: "在校/应届")
        let result = BossReadResult(pageURL: detail.url, gated: false, cards: [], detail: detail)
        let stale = BossCard(title: "旧岗位", company: "旧公司", city: "北京", salary: "99K", experience: "10年", tags: [], url: "https://www.zhipin.com/job_detail/old.html")
        let current = try BossDraftBuilder.make(result, cards: [stale], fallbackCity: "全国")
        precondition(current.title == "当前岗位" && current.company == "当前公司" && current.salary == "14-17K" && current.experience == "在校/应届")
        var restricted = result; restricted.gated = true
        do { _ = try BossDraftBuilder.make(restricted, cards: [], fallbackCity: "上海"); preconditionFailure("Must reject verification") } catch BossDraftError.verification {}
        var mismatch = result; mismatch.pageURL = stale.url
        do { _ = try BossDraftBuilder.make(mismatch, cards: [], fallbackCity: "上海"); preconditionFailure("Must reject wrong source") } catch BossDraftError.mismatched {}
        print("PASS direct-detail reading without selection, stale selection exclusion, and source verification")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(storageDirectory: folder)
        let count = store.jobs.count
        var job = Job(title: "测试岗位", company: "测试公司", city: "上海", salary: "20K", experience: "1年", tags: ["RAG"], jd: "RAG 产品设计", source: "BOSS 直聘", sourceURL: "https://www.zhipin.com/job_detail/abc123.html", fetchedAt: Date())
        precondition(store.importBoss(job))
        let id = store.selected!
        store.toggleSaved(id); store.togglePipeline(id)
        job.jd = "RAG 产品设计与效果评估"
        precondition(store.importBoss(job))
        precondition(store.jobs.count == count + 1 && store.selected == id && store.saved.contains(id) && store.pipeline.contains(id))
        let reloaded = Store(storageDirectory: folder)
        precondition(reloaded.jobs.first { $0.id == id }!.jd == job.jd && reloaded.saved.contains(id))
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as! [String: Any]
        old.removeValue(forKey: "sourceURL"); old.removeValue(forKey: "fetchedAt")
        let migrated = try JSONDecoder().decode(Job.self, from: JSONSerialization.data(withJSONObject: old))
        precondition(migrated.sourceURL == nil && migrated.fetchedAt == nil)
        print("PASS upsert, preserved collections, persistence, and old-data migration")
        let originalJD = store.jobs.first { $0.id == id }!.jd
        try FileManager.default.removeItem(at: folder)
        try Data("blocked".utf8).write(to: folder)
        job.jd = "This change must not be published when disk write fails"
        precondition(!store.importBoss(job) && store.jobs.first { $0.id == id }!.jd == originalJD)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        precondition(store.importBoss(job) && store.notice.isEmpty)
        print("PASS failed saves leave records unchanged and successful retries clear errors")
        let progressDir = folder.appendingPathComponent("role-progress")
        let progress = Store(storageDirectory: progressDir)
        let aiRole = progress.registerApplication(company: "同一家公司", title: "AI 产品经理", stage: .submitted)!
        let dataRole = progress.registerApplication(company: "同一家公司", title: "数据产品经理", stage: .screen)!
        precondition(aiRole != dataRole)
        for stage in [ApplicationStage.oneActive, .onePass, .twoActive, .twoFail] {
            precondition(progress.updateApplication(aiRole, stage: stage, notes: stage.label, followUpAt: nil))
        }
        precondition(progress.registerApplication(company: "同一家公司", title: "AI 产品经理", stage: .planned) == aiRole)
        let storedProgress = Store(storageDirectory: progressDir)
        precondition(storedProgress.applications[aiRole]!.timeline.map(\.stage) == [.submitted, .oneActive, .onePass, .twoActive, .twoFail])
        precondition(!storedProgress.applications[aiRole]!.isOpen && storedProgress.applications[dataRole]!.stage == .screen)
        precondition(Set(ApplicationStage.groups.flatMap(\.stages)) == Set(ApplicationStage.allCases))
        print("PASS distinct roles, manual registration, round outcomes, persistent timeline")
        let trackingFolder = folder.appendingPathComponent("tracking")
        let tracker = Store(storageDirectory: trackingFolder)
        let selection = tracker.selected
        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        precondition(tracker.recordActivity(job: job, stage: .drafted, at: generatedAt))
        let tracked = tracker.application(for: job)!
        precondition(tracked.stage == .drafted && tracked.generatedAt == generatedAt && tracked.filledAt == nil && tracked.sentAt == nil)
        precondition(tracker.selected == selection && tracker.pipeline.contains(tracked.id))
        let filledAt = generatedAt.addingTimeInterval(20)
        precondition(tracker.recordActivity(job: job, stage: .filled, at: filledAt))
        precondition(tracker.application(for: job)!.stage == .filled && tracker.application(for: job)!.sentAt == nil)
        precondition(tracker.confirmSent(job))
        let firstSent = tracker.application(for: job)!.sentAt!
        precondition(tracker.application(for: job)!.confirmedAt != nil)
        precondition(tracker.confirmSent(job) && tracker.application(for: job)!.sentAt == firstSent)
        let followUp = Date().addingTimeInterval(86400)
        precondition(tracker.updateApplication(tracked.id, stage: .interview, notes: "用户登记：周三面试", followUpAt: followUp))
        precondition(tracker.recordActivity(job: job, stage: .drafted, at: generatedAt))
        precondition(tracker.recordActivity(job: job, stage: .filled, at: filledAt))
        precondition(tracker.application(for: job)!.stage == .interview)
        var partial = job; partial.jd = ""; partial.fetchedAt = nil
        precondition(tracker.recordActivity(job: partial, stage: .drafted, at: nil))
        precondition(tracker.jobs.first { $0.id == tracked.id }!.jd == job.jd)
        var reviewed = job; reviewed.jd = "用户核对后修改的 JD"; reviewed.fetchedAt = Date().addingTimeInterval(60)
        precondition(tracker.importBoss(reviewed))
        precondition(tracker.recordActivity(job: job, stage: .drafted, at: generatedAt))
        precondition(tracker.jobs.first { $0.id == tracked.id }!.jd == reviewed.jd)
        let persisted = Store(storageDirectory: trackingFolder)
        let restoredRecord = persisted.application(for: job)!
        precondition(restoredRecord.notes == "用户登记：周三面试" && restoredRecord.followUpAt == followUp && restoredRecord.sentAt == firstSent)
        precondition(restoredRecord.generatedAt == generatedAt && restoredRecord.filledAt == filledAt && restoredRecord.stage == .interview)
        precondition(persisted.jobs.filter { $0.sourceURL == job.sourceURL }.count == 1)
        print("PASS generated/filled/manual-sent separation, monotonic automatic progress, stable job identity, notes, follow-up dates, and restart restoration")
        precondition(tracker.updateApplication(tracked.id, stage: .replied, notes: "已回复", followUpAt: followUp))
        precondition(tracker.updateApplication(tracked.id, stage: nil, notes: "返回旧表单后只修改备注", followUpAt: followUp))
        precondition(tracker.application(for: job)!.stage == .replied && tracker.application(for: job)!.sentAt == firstSent)
        precondition(tracker.application(for: job)!.shouldOpenExistingChat)
        print("PASS notes-only saves preserve newer communication status and prevent greeting refill")
        let recordsBefore = tracker.applications
        let jobsBefore = tracker.jobs
        try FileManager.default.removeItem(at: trackingFolder)
        try Data("blocked".utf8).write(to: trackingFolder)
        precondition(!tracker.updateApplication(tracked.id, stage: .closed, notes: "must not persist", followUpAt: nil))
        var another = job; another.sourceURL = "https://www.zhipin.com/job_detail/newrecord.html"
        precondition(!tracker.recordActivity(job: another, stage: .drafted))
        precondition(tracker.applications == recordsBefore && tracker.jobs == jobsBefore)
        print("PASS failed tracking writes leave jobs and progress unchanged")
        let legacyFolder = folder.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
        let legacy = Store.Snapshot(jobs: [job], profile: Profile(), saved: [job.id], pipeline: [job.id])
        try JSONEncoder().encode(legacy).write(to: legacyFolder.appendingPathComponent("workspace.json"))
        let oldStore = Store(storageDirectory: legacyFolder)
        precondition(oldStore.applications[job.id]?.stage == .planned && oldStore.applications[job.id]?.sentAt == nil)
        precondition(oldStore.saved.contains(job.id))
        precondition(oldStore.recordActivity(job: job, stage: .filled, at: nil))
        precondition(oldStore.applications[job.id]?.generatedAt == nil && oldStore.applications[job.id]?.filledAt == nil && oldStore.applications[job.id]?.stage == .filled)
        print("PASS old pipeline and draft migration without invented send status or historical timestamps")
        let runner = Runner(extractor: try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8))
        runner.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 35) { print("FAIL WebKit checks timed out"); exit(1) }
        withExtendedLifetime(runner) { RunLoop.main.run() }
    }
}
