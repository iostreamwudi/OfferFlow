import Foundation
import AppKit
import WebKit
import SwiftUI

// Theme constants normally live beside the app entry point.
let accent = Color.green
let ink = Color.primary
let muted = Color.secondary
let canvas = Color.white

@main struct ApplicationJourneyTests {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let base = URL(string: CommandLine.arguments[2])!
        var observations: [ApplicationJourneyAgent.Observation] = []
        var useLiveDecision = false
        var mappingRequests = 0
        let browser = ApplicationBrowserSession(url: base.appendingPathComponent("start.html"), scriptURL: root.appendingPathComponent("Sources/ApplicationAutofill.js"), decisionProvider: { observation in
            observations.append(observation)
            if useLiveDecision {
                let decision = try await ApplicationJourneyAgent.choose(observation)
                print("live plan:", decision as Any)
                return decision
            }
            let priorities = ["edit":0,"expand":1,"scroll":2,"save":3,"save-next":4,"next":5,"tab":6]
            let semanticKinds = ["补全个人档案":"edit", "暂存这部分":"save", "前往另一组材料":"next", "更多内容":"tab"]
            let choices = observation.actions.compactMap { action -> (ApplicationJourneyAgent.Action, String)? in
                let kind = action.kind == "semantic" ? semanticKinds[action.label] : action.kind
                guard let kind, priorities[kind] != nil else { return nil }
                return (action,kind)
            }.sorted { priorities[$0.1]! < priorities[$1.1]! }
            guard let selected = choices.first else { return nil }
            return .init(actionID: selected.0.id, kind: selected.1, confidence: 1)
        }, semanticProvider: { fields, facts in
            mappingRequests += 1
            return fields.filter { $0.label == "你的称呼" }.compactMap { field in
                guard let fact = facts.first(where: { $0.id == "basic.name" }) else { return nil }
                return .init(fieldID: field.id, factID: fact.id, value: fact.value)
            }
        }, mappingCache: ApplicationFieldMappingCache(persistent: false))
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 850, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Career AI · 本地网申流程验证"; window.contentView = browser.webView; browser.webView.frame = NSRect(x: 0, y: 0, width: 850, height: 700); window.makeKeyAndOrderFront(nil)
        defer { browser.close(); window.orderOut(nil) }
        for _ in 0..<100 {
            if !browser.isLoading, (try? await browser.webView.evaluateJavaScript("!!document.getElementById('name')")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        func fact(_ id: String, _ label: String, _ section: String, _ value: String) -> ApplicationAutofillFact {
            .init(id: id, label: label, section: section, entryIndex: 0, value: value)
        }
        let facts = [fact("basic.name","姓名","basic","测试候选人"), fact("basic.gender","性别","basic","男"), fact("basic.email","电子邮箱","basic","test@example.invalid"), fact("basic.address","通讯地址","basic","测试地址"), fact("basic.wechat","微信号","basic","test-account"), fact("basic.github","GitHub 地址","basic","https://example.invalid/test"), fact("intention.city","期望城市","intention","上海")]
        func runRecovery() async throws {
            let flat = ApplicationJourneySnapshot(scope: "flat", fingerprint: "flat", actions: [], validation: [], hasFields: true, needsLogin: false)
            precondition(flat.recoverySection == "当前表单")
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("career-recovery-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            let bundledURL = root.appendingPathComponent("Sources/ApplicationSiteRules.json")
            let rules = ApplicationSiteRuleStore(directory: temp.appendingPathComponent("rules"), bundledURL: bundledURL)
            precondition(rules.rule(for: URL(string: "https://app.mokahr.com/campus-recruitment/hq/45417#/job/A/apply")!)?.id == "moka")
            precondition(rules.rule(for: URL(string: "https://xiaoyuan.zhaopin.com/scrd/resume2?pid=1")!)?.id == "zhaopin-campus")
            precondition(rules.rule(for: URL(string: "https://jsdg.zhaopin.com/zk/#/pages/application-form/1")!)?.id == "zhaopin-jsdg")
            for url in ["https://app.mokahr.com.evil.invalid/campus-recruitment", "https://app.mokahr.com/campus-recruitment-other", "https://example.invalid/"] {
                precondition(rules.rule(for: URL(string: url)!) == nil)
            }
            var pack = rules.pack!; pack.version = 2
            pack.sites.append(.init(id: "test-local", version: 1, hosts: ["127.0.0.1"], pathPrefixes: ["/"], fieldRows: [], activeSections: [], fieldAliases: ["联络电邮":"电子邮箱", "密码":"姓名"], sectionAliases: [:], actionOrder: ["edit","expand","scroll","save","save-next","next","tab"]))
            let update = temp.appendingPathComponent("update.json")
            try JSONEncoder().encode(pack).write(to: update)
            try rules.install(update)
            precondition(rules.pack?.version == 2 && rules.canRollback)
            let reloaded = ApplicationSiteRuleStore(directory: temp.appendingPathComponent("rules"), bundledURL: bundledURL)
            precondition(reloaded.pack?.version == 2)
            var bad = pack; bad.version = 3; bad.sites[0].actionOrder[0] = "submit"
            let invalid = temp.appendingPathComponent("invalid.json")
            try JSONEncoder().encode(bad).write(to: invalid)
            do { try rules.install(invalid); preconditionFailure("unsafe rule accepted") } catch {}
            precondition(rules.pack?.version == 2)
            try rules.rollback(); precondition(rules.pack?.version == 1)
            try rules.install(update)
            print("PASS versioned site rules: exact host/path, install/reload/rollback, invalid actions rejected, generic fallback")

            let file = temp.appendingPathComponent("resume.json")
            let store = ApplicationJourneyRecoveryStore(file: file)
            let target = URL(string: "recovery.html?job=" + UUID().uuidString, relativeTo: base)!.absoluteURL
            let profile = [fact("basic.name","姓名","basic","测试候选人"),fact("basic.email","电子邮箱","basic","recovery@example.invalid"),fact("education.0.school","学校名称","education","测试大学"),fact("work.0.company","公司名称","work","测试公司")]
            let key = ApplicationJourneyRecoveryStore.key(url: target.absoluteString, facts: profile, revision: rules.revision)
            store.record(key: key, section: "教育经历", pendingSave: true)
            let disk = ApplicationJourneyRecoveryStore(file: file)
            precondition(disk.bookmark(for: key)?.pendingSave == true)
            precondition(disk.bookmark(for: ApplicationJourneyRecoveryStore.key(url: target.absoluteString + "&job=other", facts: profile, revision: rules.revision)) == nil)
            precondition(disk.bookmark(for: ApplicationJourneyRecoveryStore.key(url: target.absoluteString, facts: Array(profile.dropLast()), revision: rules.revision)) == nil)
            precondition(disk.bookmark(for: ApplicationJourneyRecoveryStore.key(url: target.absoluteString, facts: profile, revision: "rules-3")) == nil)
            let bytes = try String(contentsOf: file, encoding: .utf8)
            precondition(!bytes.contains("recovery@example.invalid") && !bytes.contains(target.absoluteString))
            store.clear([key])
            print("PASS recovery isolation: restart persistence; different job/profile/rules invalidated; no profile values or URLs persisted")

            var recoveryMappedLabels: [String] = []
            func make(_ recovery: ApplicationJourneyRecoveryStore) -> ApplicationBrowserSession {
                ApplicationBrowserSession(url: target, scriptURL: root.appendingPathComponent("Sources/ApplicationAutofill.js"), decisionProvider: { _ in nil }, semanticProvider: { fields,_ in recoveryMappedLabels += fields.map(\.label); return [] }, mappingCache: ApplicationFieldMappingCache(persistent: false), siteRuleStore: rules, recoveryStore: recovery)
            }
            func attachRecovery(_ session: ApplicationBrowserSession) async throws {
                window.contentView = session.webView; session.webView.frame = NSRect(x:0,y:0,width:850,height:700)
                for _ in 0..<100 {
                    if !session.isLoading, (try? await session.webView.evaluateJavaScript("window.current==='basic'")) as? Bool == true { return }
                    try await Task.sleep(for: .milliseconds(100))
                }
                preconditionFailure("recovery fixture failed to load")
            }
            let first = make(store); try await attachRecovery(first)
            first.fill(using: profile)
            var interrupted = false
            for _ in 0..<400 {
                if (try? await first.webView.evaluateJavaScript("window.pending==='education'")) as? Bool == true { interrupted = true; break }
                try await Task.sleep(for: .milliseconds(50))
            }
            precondition(interrupted, first.error ?? first.status)
            first.cancelFill()
            precondition(store.bookmark(for: key)?.section == "教育经历" && store.bookmark(for: key)?.pendingSave == true)
            // Reload destroys the in-flight save timer. No success may be inferred.
            first.reload()
            try await attachRecovery(first)
            let notSaved = try await first.webView.evaluateJavaScript("!values.education") as? Bool
            precondition(notSaved == true)
            first.close()
            let resumed = make(ApplicationJourneyRecoveryStore(file: file)); defer { resumed.close() }
            try await attachRecovery(resumed)
            resumed.enablePreparation { _ in profile }
            precondition(resumed.resumableSection == "教育经历")
            resumed.fill(using: profile)
            for _ in 0..<800 { if !resumed.isFilling { break }; try await Task.sleep(for: .milliseconds(50)) }
            precondition(!resumed.isFilling && resumed.error == nil, resumed.error ?? resumed.status)
            let result = try await resumed.webView.evaluateJavaScript("JSON.stringify({values,edits,visits,saved,submissions})") as! String
            let object = try JSONSerialization.jsonObject(with: Data(result.utf8)) as! [String:Any]
            let values = object["values"] as! [String:[String:String]]
            precondition((object["visits"] as! [String]).prefix(2).elementsEqual(["basic","education"]), result)
            precondition(values["basic"]?["email"] == "recovery@example.invalid", result)
            precondition(values["education"]?["school"] == "测试大学" && values["work"]?["company"] == "测试公司" && values["work"]?["unknown"] == "", result)
            precondition(object["submissions"] as? Int == 0)
            precondition((object["saved"] as! [String]).filter { $0 == "education" }.count == 1, result)
            precondition(!recoveryMappedLabels.contains("联络电邮") && !recoveryMappedLabels.contains("电子邮箱") && resumed.performance.decisionModelCalls == 0)
            precondition(ApplicationJourneyRecoveryStore(file: file).bookmark(for: key) == nil)
            print("PASS interrupted-save recovery: stop + refresh + new session, resume education first, reread/refill/verify all sections, adapter alias without model, unknown blank, no duplicate save or submission")
            // Rule aliases must not transform a protected field into an editable fact.
            _ = try await resumed.webView.evaluateJavaScript("document.querySelector('aside').remove();content.innerHTML='<section data-section=basic><h3>个人信息</h3><label>密码<input id=secret></label></section>'")
            resumed.fill(using: profile)
            for _ in 0..<200 { if !resumed.isFilling { break }; try await Task.sleep(for: .milliseconds(50)) }
            let secret = try await resumed.webView.evaluateJavaScript("document.getElementById('secret')?.value") as? String
            precondition(secret == "")
            print("PASS adapter guard: password alias cannot bypass protected-field exclusion")
        }
        if CommandLine.arguments.contains("--recovery-only") { try await runRecovery(); print("PASS zoomed page skipped for focused recovery regression"); return }
        func runZoom() async throws {
        browser.open(base.appendingPathComponent("zoom.html"))
        for _ in 0..<100 {
            if !browser.isLoading, (try? await browser.webView.evaluateJavaScript("!!document.getElementById('gender')")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        browser.viewport.setZoom(0.7)
        try await Task.sleep(for: .milliseconds(150))
        browser.fill(using: [.init(id: "basic.gender", label: "性别", section: "basic", entryIndex: 0, value: "男")])
        for _ in 0..<300 { if !browser.isFilling { break };try await Task.sleep(for: .milliseconds(100)) }
        let zoomChoice = try await browser.webView.evaluateJavaScript("window.received==='男'") as? Bool
        print("zoom status",browser.status,"error",browser.error ?? "none", "rows",browser.outcomes.map{($0.label ?? "")+":"+$0.status})
        if zoomChoice != true {
        print("zoom diagnostics",try await browser.webView.evaluateJavaScript("JSON.stringify({events:window.events,rect:document.getElementById('gender').getBoundingClientRect().toJSON(),width:innerWidth,scrollX,scrollY,hidden:document.getElementById('choices').hidden,value:document.getElementById('gender').value})") as Any)
        }
        precondition(zoomChoice == true && browser.outcomes.contains { $0.status == "filled" })
        print("PASS zoomed page: native pointer opens the actual dropdown and selects the intended option at 70%")
        }
        if CommandLine.arguments.contains("--zoom-only") { try await runZoom(); return }
        func runReadonlySections() async throws {
            browser.open(base.appendingPathComponent("readonly-sections.html"))
            for _ in 0..<100 {
                if !browser.isLoading, (try? await browser.webView.evaluateJavaScript("window.current==='basic'")) as? Bool == true { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            browser.fill(using: [fact("basic.name","姓名","basic","不同的新名字"),fact("basic.email","电子邮箱","basic","test@example.invalid"),fact("education.0.school","学校名称","education","测试大学"),fact("work.0.company","公司名称","work","测试公司"),fact("computer.0.name","技能名称","computer","SQL")])
            for _ in 0..<900 { if !browser.isFilling { break };try await Task.sleep(for: .milliseconds(100)) }
            print("readonly status",browser.status,"error",browser.error ?? "none")
            let state=try await browser.webView.evaluateJavaScript("JSON.stringify({edits,saved,values,submissions})") as! String
            print("readonly fixture",state)
            let result=try JSONSerialization.jsonObject(with:Data(state.utf8)) as! [String:Any]
            let edits=result["edits"] as! [String:Int],saved=result["saved"] as! [String:Int],values=result["values"] as! [String:[String:String]]
            precondition(!browser.isFilling && browser.error==nil)
            precondition(edits.count==4 && edits.values.allSatisfy{$0==1})
            precondition(saved["basic"]==1 && saved["education"]==1 && saved["computer"]==1 && saved["work"]==nil)
            precondition(values["basic"]?["name"]=="不同的新名字" && values["basic"]?["email"]=="test@example.invalid")
            precondition(values["education"]?["school"]=="测试大学" && values["work"]?["company"]=="测试公司" && values["work"]?["unknown"]=="" && values["computer"]?["skill"]=="SQL")
            precondition(result["submissions"] as? Int == 0)
            precondition(browser.performance.decisionModelCalls == 0)
        print("PERFORMANCE readonly journey:",browser.performance)
        print("PASS readonly sections: non-button Edit, status-decorated sidebar, save before switch, blocked section does not stop later sections, no edit loops or final submission")
        }
        if CommandLine.arguments.contains("--readonly-only") { try await runReadonlySections(); print("PASS zoomed page skipped for focused readonly regression"); return }
        func runSaveDialog() async throws {
            browser.open(base.appendingPathComponent("save-dialog.html"))
            for _ in 0..<100 {
                if !browser.isLoading, (try? await browser.webView.evaluateJavaScript("window.dialogFixture===true")) as? Bool == true { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            browser.fill(using:[fact("basic.email","电子邮箱","basic","dialog@example.invalid")])
            for _ in 0..<400 { if !browser.isFilling { break };try await Task.sleep(for: .milliseconds(100)) }
            let verified=try await browser.webView.evaluateJavaScript("saved==='dialog@example.invalid' && discard===0 && submissions===0 && finished") as? Bool
            print("save dialog status",browser.status)
            precondition(verified==true)
            print("PASS save dialog: only foreground actions considered; save-and-jump preserves filled data, never discard or submit")
        }
        if CommandLine.arguments.contains("--dialog-only") { try await runSaveDialog(); print("PASS zoomed page skipped for focused dialog regression"); return }


        browser.fill(using: facts)
        for i in 0..<900 {
            if !browser.isFilling { break }
            if i % 100 == 0 { print("progress:", browser.status) }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(!browser.isFilling, "journey did not terminate")
        print("journey status:", browser.status, "error:", browser.error ?? "none")
        print("outcomes:", browser.outcomes.map { ($0.label ?? "") + ":" + $0.status }.joined(separator: ","))
        precondition(browser.error == nil)
        let result = try await browser.webView.evaluateJavaScript("JSON.stringify({first:JSON.parse(sessionStorage.first||'{}'),address:document.getElementById('address')?.value,wechat:document.getElementById('wechat')?.value,github:document.getElementById('github')?.value,city:document.getElementById('city')?.value,phone:document.getElementById('phone')?.value,saved:+(sessionStorage.saved||0),nextAttempts:+(sessionStorage.nextAttempts||0),submits:+(sessionStorage.finalSubmits||0)})") as! String
        let data = try JSONSerialization.jsonObject(with: Data(result.utf8)) as! [String: Any]
        let first = data["first"] as! [String: Any]
        precondition(first["name"] as? String == "测试候选人" && first["email"] as? String == "test@example.invalid")
        precondition(first["gender"] as? String == "M" && first["unknown"] as? String == "")
        precondition(data["address"] as? String == "测试地址" && data["wechat"] as? String == "test-account" && data["city"] as? String == "上海")
        precondition(data["github"] as? String == "https://example.invalid/test" && data["phone"] as? String == "")
        precondition((data["saved"] as? Int ?? 0) >= 1 && (data["nextAttempts"] as? Int ?? 0) >= 1)
        precondition(data["submits"] as? Int == 0)
        precondition(!browser.outcomes.contains { $0.label == "手机号码" }, "Unknown fields are skipped without creating pending records")
        precondition(!browser.outcomes.contains { $0.label == "邮政编码" })
        precondition(browser.performance.decisionModelCalls == 0, "Known navigation must not invoke the model")
        print("PERFORMANCE standard journey:", browser.performance)
        print("PASS full native WK session: save reveals fields; cross-document Next; missing first field does not block later fields; required missing blocks Next but other tabs/accordion still fill; aliases become choices; zero final submissions")
        let options = [ApplicationOptionMatcher.Option(id:"o0",label:"本科"), .init(id:"o1",label:"硕士")]
        let chosen = try ApplicationOptionMatcher.decode(Data(#"{"optionID":"o0","confidence":1,"relation":"equivalent"}"#.utf8), options: options)
        precondition(chosen == "o0")
        for json in [#"{"optionID":"invented","confidence":1,"relation":"equivalent"}"#, #"{"optionID":"o0","confidence":0.7,"relation":"equivalent"}"#, #"{"optionID":"o0","confidence":1,"relation":"guess"}"#] {
            let rejected = try ApplicationOptionMatcher.decode(Data(json.utf8), options: options); precondition(rejected == nil)
        }
        print("PASS semantic option reply validation: unknown IDs, guesses and low confidence rejected")
        // Exercise the DOM half of semantic selection without making a model request.
        browser.webView.loadHTMLString("<section data-section='basic'><h2>个人信息</h2><label>最高学历<select id='optionTest'><option value=''>请选择</option><option value='B'>本科及同等学历</option><option value='M'>硕士及以上</option></select></label></section>", baseURL: base)
        for _ in 0..<100 {
            if !browser.isLoading, (try? await browser.webView.evaluateJavaScript("!!document.getElementById('optionTest')")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let script = try String(contentsOf: root.appendingPathComponent("Sources/ApplicationAutofill.js"), encoding: .utf8)
        let optionWorld = WKContentWorld.world(name: "option-test")
        func call(_ action: String, _ extra: [String: Any] = [:]) async throws -> [String: Any] {
            var args: [String: Any] = ["action": action, "token": "", "assignments": [], "desiredSections": [:], "identities": [:]]
            extra.forEach { args[$0.key] = $0.value }
            return try await browser.webView.callAsyncJavaScript(script, arguments: args, in: nil, contentWorld: optionWorld) as? [String: Any] ?? [:]
        }
        let scan = try await call("scan")
        let token = scan["token"] as! String
        let assignment: [[String: Any]] = [["fieldID": "f0", "value": "本科"]]
        let menu = try await call("repair", ["token": token, "assignments": assignment, "desiredSections": ["step": "options"]])
        _ = try await browser.webView.evaluateJavaScript("document.querySelector('#optionTest option[value=B]').disabled=true")
        let rejected = try await call("repair", ["token": token, "assignments": assignment, "desiredSections": ["step": "selectOption", "optionID": "o0", "signature": menu["signature"]!]])
        precondition(rejected["done"] as? Bool == false)
        _ = try await browser.webView.evaluateJavaScript("document.querySelector('#optionTest option[value=B]').disabled=false")
        let selected = try await call("repair", ["token": token, "assignments": assignment, "desiredSections": ["step": "selectOption", "optionID": "o0", "signature": menu["signature"]!]])
        precondition(selected["done"] as? Bool == true)
        let audit = try await call("audit", ["token": token, "assignments": assignment])
        precondition((audit["results"] as? [[String: Any]])?.first?["status"] as? String == "filled")
        print("PASS semantic selection executor: stale menu refused; validated observed option selected and audited")
        _ = try await browser.webView.evaluateJavaScript("""
        document.body.innerHTML=`<section data-section="basic"><h2>个人信息</h2><div class="el-form-item"><label class="el-form-item__label">籍贯</label><div class="el-cascader"><input id="county" readonly placeholder="请选择"><span class="el-input__suffix" onclick="document.getElementById('p').hidden=false">展开</span></div></div></section><ul class="el-cascader-menu" id="p" hidden><li class="el-cascader-node" onmouseenter="document.getElementById('c').hidden=false"><span class="el-cascader-node__label">湖北省</span></li></ul><ul class="el-cascader-menu" id="c" hidden><li class="el-cascader-node" onmouseenter="document.getElementById('d').hidden=false"><span class="el-cascader-node__label">襄阳市</span></li></ul><ul class="el-cascader-menu" id="d" hidden><li class="el-cascader-node"><span class="el-cascader-node__label">襄城区</span><span class="el-radio" onclick="document.getElementById('county').value='湖北省 / 襄阳市 / 襄城区'">选中</span></li></ul>`;
        """)
        let countyScan = try await call("scan")
        let countyToken = countyScan["token"] as! String
        let countyAssignment: [[String: Any]] = [["fieldID": "f0", "value": "湖北省襄阳市襄城区"]]
        for step in ["open", "choose", "choose", "choose"] {
            let action = try await call("repair", ["token": countyToken, "assignments": countyAssignment, "desiredSections": ["step": step, "perform": true]])
            precondition(action["invoked"] as? Bool == true)
        }
        let countyAudit = try await call("audit", ["token": countyToken, "assignments": countyAssignment])
        precondition((countyAudit["results"] as? [[String: Any]])?.first?["status"] as? String == "filled")
        print("PASS three-level cascader: open, province, city, district and full-value audit")
        useLiveDecision = CommandLine.arguments.contains("--live-semantic")
        browser.open(base.appendingPathComponent("semantic.html"))
        for _ in 0..<100 {
            if !browser.isLoading, (try? await browser.webView.evaluateJavaScript("!!document.getElementById('semanticStart')")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        browser.fill(using: facts)
        for _ in 0..<900 {
            if !browser.isFilling { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(!browser.isFilling && browser.error == nil)
        let semanticResult = try await browser.webView.evaluateJavaScript("JSON.stringify({name:document.getElementById('semanticName').value,email:document.getElementById('semanticEmail').value,address:document.getElementById('semanticAddress').value,phone:document.getElementById('semanticPhone').value,submits:window.semanticSubmits})") as! String
        let semanticData = try JSONSerialization.jsonObject(with: Data(semanticResult.utf8)) as! [String: Any]
        print("semantic status:", browser.status)
        precondition(semanticData["name"] as? String == "测试候选人" && semanticData["email"] as? String == "test@example.invalid" && semanticData["address"] as? String == "测试地址")
        precondition(semanticData["phone"] as? String == "" && semanticData["submits"] as? Int == 0)
        if !useLiveDecision { precondition(!observations.isEmpty, "Ambiguous controls still receive model decisions") }
        precondition(!observations.flatMap(\.actions).contains { ["确认提交", "取消申请", "上传资料"].contains($0.label) })
        let guarded = ApplicationJourneySnapshot.Action(id: "edit-one", label: "补全资料", kind: "semantic", context: "基本信息", allowedKinds: ["edit"])
        precondition(ApplicationJourneyAgent.resolve(.init(actionID:"edit-one", kind:"next", confidence:1), candidates:[guarded]) == nil)
        precondition(ApplicationJourneyAgent.resolve(.init(actionID:"invented", kind:"edit", confidence:1), candidates:[guarded]) == nil)
        precondition(ApplicationJourneyAgent.resolve(.init(actionID:"edit-one", kind:"edit", confidence:0.5), candidates:[guarded]) == nil)
        print("PASS semantic journey: unknown edit/save/next/tab captions, observed validation fallback, unknown phone blank, forbidden actions excluded, malformed model choices rejected")
        useLiveDecision = false
        browser.open(base.appendingPathComponent("lazy.html"))
        for _ in 0..<100 {
            if !browser.isLoading, (try? await browser.webView.evaluateJavaScript("!!document.getElementById('lazyName')")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        browser.fill(using: facts)
        for _ in 0..<900 {
            if !browser.isFilling { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(!browser.isFilling && browser.error == nil)
        let lazyResult = try await browser.webView.evaluateJavaScript("document.getElementById('lazyEmail')?.value") as? String
        precondition(lazyResult == "test@example.invalid")
        print("PASS lazy form: scroll reveals an initially absent field; new field is scanned and filled")
        _ = try await browser.webView.evaluateJavaScript("document.body.innerHTML='<div class=\"el-form-item\"><label class=\"el-form-item__label\">民族</label><div class=\"el-select\"><input id=\"queryOnly\"></div></div><ul role=\"listbox\"><li role=\"option\">未知选项</li></ul>'")
        let queryScan = try await call("scan")
        let queryToken = queryScan["token"] as! String
        let queryAssignment: [[String: Any]] = [["fieldID":"f0", "value":"汉族"]]
        _ = try await call("repair", ["token":queryToken,"assignments":queryAssignment,"desiredSections":["step":"choose"]])
        let queryVerification = try await call("repair", ["token":queryToken,"assignments":queryAssignment,"desiredSections":["step":"verify"]])
        precondition(queryVerification["done"] as? Bool == false)
        _ = try await call("repair", ["token":queryToken,"assignments":queryAssignment,"desiredSections":["step":"dismiss"]])
        let queryValue = try await browser.webView.evaluateJavaScript("document.getElementById('queryOnly').value") as? String
        precondition(queryValue == "")
        print("PASS unmatched search in a select remains blank; typed query is not reported as a committed choice")
        let attachmentDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("careerai-upload-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: attachmentDirectory) }
        let resumeURL = attachmentDirectory.appendingPathComponent("测试简历.txt")
        try Data("SYNTHETIC RESUME CONTENT".utf8).write(to: resumeURL)
        browser.open(base.appendingPathComponent("upload.html"))
        for _ in 0..<100 {
            if !browser.isLoading, (try? await browser.webView.evaluateJavaScript("!!document.getElementById('resumeFile')")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        browser.fill(using: facts, attachments: [.init(name:resumeURL.lastPathComponent,path:resumeURL.path,kind:"简历"),.init(name:"照片.txt",path:resumeURL.path,kind:"证件照")], resumeFilename: resumeURL.lastPathComponent)
        for _ in 0..<500 { if !browser.isFilling { break };try await Task.sleep(for: .milliseconds(100)) }
        print("upload status:",browser.status,"error:",browser.error ?? "none")
        print("upload outcomes:",browser.outcomes.map { ($0.label ?? "")+":"+$0.status })
        precondition(!browser.isFilling && browser.error == nil)
        let uploaded = try await browser.webView.evaluateJavaScript("receivedContent==='SYNTHETIC RESUME CONTENT' && uploadCount===1 && extraUploads===0 && submissions===0") as? Bool
        precondition(uploaded == true)
        precondition(browser.outcomes.contains { $0.label=="简历上传" && $0.status=="filled" })
        precondition(!browser.outcomes.contains { ($0.label ?? "").contains("身份证附件") || $0.label=="照片" })
        print("PASS real native file chooser: configured resume bytes selected and receipt verified once; no other attachment selected or counted")
        try await runRecovery()
        window.contentView = browser.webView; browser.webView.frame = NSRect(x:0,y:0,width:850,height:700)
        try await runReadonlySections()
        try await runSaveDialog()
        try await runZoom()
        browser.open(base.appendingPathComponent("async-ready.html"))
        for _ in 0..<100 {
            if !browser.isLoading, (try? await browser.webView.evaluateJavaScript("!!document.getElementById('asyncName')")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        browser.fill(using:facts)
        for _ in 0..<500 { if !browser.isFilling { break }; try await Task.sleep(for: .milliseconds(100)) }
        let delayed = try await browser.webView.evaluateJavaScript("saved && document.getElementById('asyncEmail').value==='test@example.invalid' && early===0 && submits===0") as? Bool
        precondition(delayed == true && browser.error == nil)
        precondition(browser.performance.decisionModelCalls == 0 && browser.performance.transitionSeconds >= 1.1)
        print("PASS async readiness: wait through loading and delayed save; discover subsequent fields; no premature next or final submit", browser.performance)
        let requestsBefore = mappingRequests
        for index in 0..<2 {
            browser.open(base.appendingPathComponent("mapping-reuse.html"))
            for _ in 0..<100 {
                if !browser.isLoading, (try? await browser.webView.evaluateJavaScript("document.getElementById('nickname')?.value === ''")) as? Bool == true { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let name = index == 0 ? "初次测试名字" : "更新后的名字"
            browser.fill(using: [fact("basic.name","姓名","basic",name)])
            for _ in 0..<200 { if !browser.isFilling { break }; try await Task.sleep(for: .milliseconds(100)) }
            let actual = try await browser.webView.evaluateJavaScript("document.getElementById('nickname').value") as? String
            print("mapping reuse run",index,"value correct",actual == name,"outcomes",browser.outcomes.map(\.status),"metrics",browser.performance)
            precondition(actual == name && browser.outcomes.contains { $0.status == "filled" })
            precondition(mappingRequests == requestsBefore + 1)
            if index == 1 { precondition(browser.performance.cachedMappings >= 1 && browser.performance.mappingModelCalls == 0) }
        }
        print("PASS end-to-end learned mapping: first run resolves and audits; repeat uses latest profile value without another model request")
        // Compare the same form/provider with and without background preparation.
        browser.close()
        var liveFacts = [fact("basic.name", "姓名", "basic", "准备阶段姓名"), fact("basic.email", "电子邮箱", "basic", "prepared@example.invalid")]
        var prepRequests = 0
        func makePreparedBrowser() -> ApplicationBrowserSession {
            ApplicationBrowserSession(url: base.appendingPathComponent("mapping-reuse.html"), scriptURL: root.appendingPathComponent("Sources/ApplicationAutofill.js"), decisionProvider: { _ in nil }, semanticProvider: { fields, facts in
                prepRequests += 1
                try await Task.sleep(for: .milliseconds(800))
                return fields.compactMap { field in
                    guard field.label == "你的称呼", let name = facts.first(where: { $0.id == "basic.name" }) else { return nil }
                    return .init(fieldID: field.id, factID: name.id, value: name.value)
                }
            }, mappingCache: ApplicationFieldMappingCache(persistent: false))
        }
        func attach(_ session: ApplicationBrowserSession) async throws {
            window.contentView = session.webView; session.webView.frame = NSRect(x:0,y:0,width:850,height:700)
            for _ in 0..<100 {
                if !session.isLoading, (try? await session.webView.evaluateJavaScript("!!document.getElementById('nickname')")) as? Bool == true { return }
                try await Task.sleep(for: .milliseconds(100))
            }
            preconditionFailure("fixture did not load")
        }
        func waitFill(_ session: ApplicationBrowserSession) async throws {
            for _ in 0..<300 { if !session.isFilling { break }; try await Task.sleep(for: .milliseconds(50)) }
            precondition(!session.isFilling && session.error == nil)
        }
        let cold = makePreparedBrowser(); try await attach(cold)
        cold.fill(using: liveFacts); try await waitFill(cold)
        let coldSeconds = cold.performance.elapsedSeconds
        precondition(cold.performance.mappingModelCalls == 1)
        cold.close()
        let warm = makePreparedBrowser(); try await attach(warm)
        defer { warm.close() }
        warm.enablePreparation { _ in liveFacts }
        for _ in 0..<120 {
            if warm.preparedFieldCount == 1 && !warm.isPreparing { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(warm.preparedFieldCount == 1)
        let before = try await warm.webView.evaluateJavaScript("document.getElementById('nickname').value") as? String
        precondition(before == "", "preparation must never modify the form")
        warm.fill(using: liveFacts); try await waitFill(warm)
        let after = try await warm.webView.evaluateJavaScript("document.getElementById('nickname').value") as? String
        precondition(after == liveFacts[0].value && warm.performance.mappingModelCalls == 0 && warm.performance.preparedAssignments > 0)
        let warmSeconds = warm.performance.elapsedSeconds
        precondition(warmSeconds + 0.45 < coldSeconds)
        print("PASS background preparation: zero page edits before click; same correct answer; cold", coldSeconds, "warm", warmSeconds, "seconds, model wait simulated 800ms; preparation cost", warm.preparationSeconds)
        // New local values must replace prepared old answers, even without a UI refresh callback.
        liveFacts[0] = fact("basic.name", "姓名", "basic", "修改后的最新姓名")
        warm.fill(using: liveFacts); try await waitFill(warm)
        let actualLatest = try await warm.webView.evaluateJavaScript("document.getElementById('nickname').value") as? String
        precondition(actualLatest == liveFacts[0].value)
        precondition(warm.performance.preparedAssignments == 0)
        // Replace a prepared control's meaning and add a new one. Never reuse an old answer by index.
        try await warm.prepare(using: liveFacts)
        _ = try await warm.webView.evaluateJavaScript("document.querySelector('label').firstChild.textContent='电子邮箱';document.getElementById('nickname').value='';const label=document.createElement('label');label.innerHTML='姓名<input id=addedName>';document.querySelector('section').append(label)")
        warm.fill(using: liveFacts); try await waitFill(warm)
        let changed = try await warm.webView.evaluateJavaScript("document.getElementById('nickname').value==='prepared@example.invalid' && document.getElementById('addedName').value==='修改后的最新姓名'") as? Bool
        precondition(changed == true)
        print("PASS preparation invalidation: updated profile, changed field meaning, newly revealed fields all use fresh answers")
        // Click while model preparation is in flight: cancellation cannot publish or type stale results.
        warm.open(URL(string: "mapping-reuse.html?race=1", relativeTo: base)!.absoluteURL); try await attach(warm)
        let requests = prepRequests
        warm.enablePreparation { _ in liveFacts }
        for _ in 0..<80 { if prepRequests > requests { break }; try await Task.sleep(for: .milliseconds(50)) }
        precondition(warm.isPreparing)
        warm.fill(using: liveFacts); try await waitFill(warm)
        let racedValue = try await warm.webView.evaluateJavaScript("document.getElementById('nickname').value") as? String
        precondition(racedValue == liveFacts[0].value)
        print("PASS preparation/click race: in-flight preparation cancelled, fresh token filled correctly")








    }
}
