import Foundation
import AppKit
import WebKit

@main struct InterviewTests {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = InterviewStore(directory: folder)
        let id = "6a69ef4f00000000010012be"
        precondition(InterviewRules.sourceID("https://evil.test/explore/\(id)") == nil)
        precondition(InterviewRules.canonical("https://www.xiaohongshu.com/search_result/\(id)?xsec_token=SECRET") == "https://www.xiaohongshu.com/explore/\(id)")
        let card = InterviewCard(id:id, title:"测试", author:"", date:"", url:"https://www.xiaohongshu.com/search_result/\(id)?xsec_token=TEST&xsec_source=")
        let destination = InterviewBrowser.destination(for:card)!
        let parameters = URLComponents(url:destination, resolvingAgainstBaseURL:false)!.queryItems!
        precondition(destination.path == "/explore/" + id)
        precondition(parameters.first { $0.name == "xsec_token" }?.value == "TEST")
        precondition(parameters.first { $0.name == "xsec_source" }?.value == "pc_search")
        precondition(InterviewRules.noteID("https://www.nowcoder.com/discuss/957899?source=test") == "nowcoder:discuss:957899")
        precondition(InterviewRules.canonical("https://www.nowcoder.com/discuss/957899?source=test") == "https://www.nowcoder.com/discuss/957899")
        precondition(InterviewRules.sourceID("https://nowcoder.com.evil.test/discuss/957899") == nil)
        precondition(InterviewRules.sourceID("https://www.nowcoder.com/discuss/tag/11075") == nil)
        precondition(InterviewRules.noteID("https://www.nowcoder.com/feed/main/detail/0123456789abcdef0123456789abcdef") == "nowcoder:feed:0123456789abcdef0123456789abcdef")
        precondition(InterviewBrowser.destination(for: InterviewCard(id:"discuss:957899", title:"",author:"",date:"",url:"https://www.nowcoder.com/discuss/957899?x=1"))?.path == "/discuss/957899")
        precondition(InterviewSource.nowcoder.searchURL("字节跳动 产品经理 面经").query?.contains("query=") == true)
        let searchParams = URLComponents(url: InterviewSource.nowcoder.searchURL("字节 产品经理"), resolvingAgainstBaseURL: false)!.queryItems!
        precondition(searchParams.contains { $0.name == "type" && $0.value == "all" })
        precondition(searchParams.contains { $0.name == "subType" && $0.value == "818" })
        precondition(!InterviewImages.allowed(URL(string:"https://nowcoder.com.evil.test/a.png")!))
        precondition(InterviewImages.allowed(URL(string:"https://uploadfiles.nowcoder.com/a.png")!))
        var note = InterviewNote(id: "xiaohongshu:" + id, title: "合成测试面经")
        note.segments = [.init(id: "body", label: "正文", text: "你怎样评估检索策略是否改善了回答质量？"), .init(id: "image-1", label: "旧图片", text: "旧图片中保留的问题")]
        note.memo = "用户备注"
        store.upsert(note)
        var update = note; update.segments = [.init(id: "body", label: "正文", text: "新正文")]; update.memo = "不能覆盖"
        store.upsert(update)
        precondition(store.library.notes.count == 1 && store.library.notes[0].segments.count == 2 && store.library.notes[0].memo == "用户备注")
        precondition(InterviewStore(directory: folder).library.notes == store.library.notes)
        let target = InterviewTarget(company: "美图", role: "产品经理 | B端AI创意工具")
        let scoped = InterviewSearch(company: target.company, role: target.role)
        var related = InterviewNote(id: "nowcoder:discuss:123", title: "美图影像产品面经")
        precondition(!scoped.matches(related, target: target))
        related.preparationTargetIDs = [target.id]
        store.upsert(related)
        let secondTarget = InterviewTarget(company: "美图", role: "影像产品经理")
        related.preparationTargetIDs = [secondTarget.id]
        store.upsert(related)
        let saved = InterviewStore(directory: folder).library.notes.first { $0.id == related.id }!
        precondition(saved.preparationTargetIDs == [target.id, secondTarget.id] && saved.sourceRole == nil)
        precondition(scoped.matches(saved, target: target) && scoped.revealing(saved, target: target) == scoped)
        var narrower = scoped; narrower.keyword = "另一个关键词"
        precondition(!narrower.matches(saved, target: target) && narrower.revealing(saved, target: target) == scoped)
        precondition(!InterviewSearch(company: "其他公司").matches(saved, target: target))
        print("PASS: collected post visible for linked preparation targets, unrelated filters respected, links persist across reload")
        let valid = #"{"category":"面试复盘","questions":[{"original":"你怎样评估检索策略是否改善了回答质量？","segmentID":"body","intent":"评估方法","reasoning":"问法涉及评估，仍是推断","category":"评估","answerMode":"direct","modeReason":"可从评估方法直接展开。"}]}"#
        let (_, questions) = try InterviewAI.parseExtraction(valid, note: note)
        precondition(questions.count == 1 && questions[0].answerMode == .direct)
        var mixed = try JSONSerialization.jsonObject(with: Data(valid.utf8)) as! [String: Any]
        let good = (mixed["questions"] as! [[String: Any]])[0]
        var wrongSegment = good; wrongSegment["segmentID"] = "image-99"
        var invented = good; invented["original"] = "原文没有出现过的问题？"
        mixed["questions"] = [wrongSegment, invented, ["original": "缺少字段"]]
        let (_, verified) = try InterviewAI.parseExtraction(String(decoding: JSONSerialization.data(withJSONObject: mixed), as: UTF8.self), note: note)
        precondition(verified.count == 1 && verified[0].segmentID == "body")
        var retained = note
        retained.applyExtraction(verified, category: "复盘", model: "test")
        retained.applyExtraction([], category: "复盘", model: "test")
        precondition(retained.questions.first?.id == verified.first?.id)
        precondition(related.relevance(to: target) == "同公司参考")
        precondition(saved.relevance(to: target) == "已关联")
        store.saveTarget(target)
        store.prepareForApplication(jobID: "existing-job", company: target.company, role: target.role, jd: nil)
        precondition(store.target.id == target.id && store.target.jobID == "existing-job")
        store.prepareForApplication(jobID: "existing-job", company: target.company, role: "新岗位名称", jd: nil)
        precondition(store.target.id == target.id && saved.relevance(to: store.target) == "已关联")
        print("PASS: mixed model output retains verified questions, retry preserves originals, legacy targets survive job renames")
        let oldQuestion = try JSONDecoder().decode(InterviewQuestion.self, from: Data(#"{"id":"legacy","original":"你的职责是什么？","segmentID":"body","intent":"职责","reasoning":"个人贡献","category":"项目"}"#.utf8))
        precondition(oldQuestion.answerMode == nil)
        let (_, routed) = try InterviewAI.parseExtraction(valid.replacingOccurrences(of: "direct", with: "project"), note: note)
        precondition(routed.first?.answerMode == .project)
        precondition(InterviewAI.sourceQuote("怎样评估RAG质量？", in:"前文\n怎样评估 RAG\n质量？\n后文") == "怎样评估 RAG\n质量？")
        precondition(InterviewAI.sourceQuote("怎样评估RAG成本？", in:"怎样评估 RAG\n质量？") == nil)
        do { _ = try InterviewAI.parseExtraction(valid.replacingOccurrences(of: "你怎样评估检索策略是否改善了回答质量？", with: "模型虚构的新问题"), note: note); fatalError("Invented quote accepted") } catch {}
        var profile = ApplicationProfile()
        profile.values["basic.documentNumber"] = "PRIVATE-ID-SHOULD-NOT-LEAVE"
        profile.entries["work"] = [ApplicationProfileEntry(values: ["company":"测试单位", "responsibilities":"验证检索效果", "supervisorPhone":"PRIVATE-PHONE"])]
        let project = InterviewProject.from(profile)[0]
        precondition(!project.facts.joined().contains("PRIVATE"))
        do { _ = try InterviewAI.parseAdaptation(#"{"question":"练习题","outline":["步骤"],"followups":[],"missing":[],"evidenceIDs":[999]}"#, project: project); fatalError("Invalid evidence accepted") } catch {}
        print("PASS: source normalization, dedup, persistent reload, failed-image retention, note preservation, exact source quotes, fact-ID validation, private fields excluded")

        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        let web = WKWebView(frame: NSRect(x:0,y:0,width:1000,height:900))
        let window = NSWindow(contentRect: NSRect(x:-20000,y:-20000,width:1000,height:900), styleMask:[.borderless], backing:.buffered, defer:false)
        window.contentView = web; window.orderBack(nil)
        let loader = Loader(); web.navigationDelegate = loader
        let html = """
        <section class="note-item"><a href="/explore/\(id)?xsec_token=test"><span class="title">面经标题</span></a><span class="author"><b class="name">作者</b></span></section>
        <section class="note-item"><a hidden href="/explore/\(id)"></a><a class="cover" href="/search_result/\(id)?xsec_token=other"><span class="title">同篇笔记</span></a></section>
        <div class="note-detail-mask"><div id="detail-title">笔记标题</div><div id="detail-desc">第一段问题？<br>第二段问题？</div><div class="date">编辑于 09-10</div><div class="comments">私密评论不应混入正文</div><div class="swiper-slide"><img src="https://image.xhscdn.com/example.webp"></div><div class="swiper-slide"><img src="https://image.xhscdn.com/example.webp"></div><div class="swiper-slide"><img src="https://evil.test/image.png"></div></div>
        """
        await loader.load(html, in: web, id: id)
        let script = try String(contentsOf: root.appendingPathComponent("Sources/XiaohongshuReader.js"), encoding: .utf8)
        func read(_ mode: String, selectedID: String = "") async throws -> [String:Any] { try await web.callAsyncJavaScript(script, arguments:["mode":mode,"selectedID":selectedID], in:nil, contentWorld:.world(name:"Interview.Test")) as? [String:Any] ?? [:] }
        let list = try await read("list")
        let cards = try JSONDecoder().decode([InterviewCard].self, from: JSONSerialization.data(withJSONObject: list["cards"]!))
        precondition(cards.count == 1 && cards[0].url.contains("xsec_token=other"))
        _ = try await web.evaluateJavaScript("window.cardClicks=0; document.querySelectorAll('.note-item a').forEach(a=>a.addEventListener('click',e=>{e.preventDefault();window.cardClicks++;history.pushState({},'',a.pathname)}))")
        _ = try await web.evaluateJavaScript("history.replaceState({}, '', '/search_result')")
        let opened = try await read("open", selectedID:id)
        precondition(opened["id"] as? String == id)
        let clicks = try await web.evaluateJavaScript("window.cardClicks") as? Int
        precondition(clicks == 1)
        _ = try await web.evaluateJavaScript("history.replaceState({}, '', '/search_result');document.querySelectorAll('.note-item').forEach(n=>n.remove())")
        let missing = try await read("open", selectedID:id)
        precondition(missing["missing"] as? Bool == true && InterviewBrowser.destination(for: cards[0])?.path == "/explore/" + id)
        _ = try await web.evaluateJavaScript("history.replaceState({}, '', '/explore/\(id)')")
        let detail = try await read("detail")
        precondition(detail["body"] as? String == "第一段问题？\n第二段问题？")
        precondition((detail["images"] as? [String])?.count == 1)
        precondition(!(detail["body"] as? String ?? "").contains("评论"))
        _ = try await web.evaluateJavaScript("document.body.insertAdjacentHTML('beforeend','<div class=login-container>登录</div>')")
        let blocked = try await read("detail"); precondition(blocked["error"] != nil)
        let nowHTML = """
        <main><li><a href="/discuss/957899?tracking=1">牛客面经</a><a href="/discuss/957899">重复链接</a></li><li><a href="https://evil.test/discuss/123">非本站</a></li><li><a href="/feed/main/detail/0123456789abcdef0123456789abcdef">动态面经</a></li></main>
        <div class="main-content-container"><header class="content-user-info"><span class="name-text">测试作者</span><span class="time-text">2026-11-19</span></header><section class="post-content-box"><div class="content-post-title"><h1>牛客原题</h1></div><div class="nc-post-content">项目为什么采用 RAG？<div>如何评价效果？</div><img src="https://uploadfiles.nowcoder.com/test.png"><img src="https://uploadfiles.nowcoder.com/test.png"><img src="https://evil.test/test.png"></div></section><div class="comment-list">评论不能混入原文</div></div>
        """
        await loader.loadURL(nowHTML, in: web, url: "https://www.nowcoder.com/discuss/957899")
        let nowScript = try String(contentsOf: root.appendingPathComponent("Sources/NowcoderReader.js"), encoding: .utf8)
        func nowRead(_ mode:String) async throws -> [String:Any] { try await web.callAsyncJavaScript(nowScript, arguments:["mode":mode], in:nil, contentWorld:.world(name:"Nowcoder.Test")) as? [String:Any] ?? [:] }
        let nowList = try await nowRead("list")
        precondition((nowList["cards"] as? [[String:Any]])?.count == 2)
        let nowDetail = try await nowRead("detail")
        precondition(nowDetail["body"] as? String == "项目为什么采用 RAG？\n如何评价效果？")
        precondition(nowDetail["author"] as? String == "测试作者")
        precondition((nowDetail["images"] as? [String])?.count == 1)
        precondition(nowDetail["id"] as? String == "discuss:957899")
        _ = try await web.evaluateJavaScript("document.querySelector('.nc-post-content').className = 'nc-slate-editor-content'")
        let slate = try await nowRead("detail"); precondition(slate["body"] as? String == nowDetail["body"] as? String)
        _ = try await web.evaluateJavaScript("document.querySelector('.nc-slate-editor-content').remove()")
        let noBody = try await nowRead("detail"); precondition(noBody["error"] != nil)
        _ = try await web.evaluateJavaScript("document.querySelector('.post-content-box').insertAdjacentHTML('beforeend','<div class=nc-post-content><img src=https://uploadfiles.nowcoder.com/only.png></div>')")
        let imageOnly = try await nowRead("detail")
        precondition(imageOnly["error"] == nil && (imageOnly["images"] as? [String])?.count == 1)
        let feedHTML = """
        <div class="main-content-container"><header class="content-user-info"><span class="name-text">动态作者</span></header><section><h1>动态面经</h1><div class="feed-content-text">动态第一题？<br>动态第二题？</div><div class="feed-img"><img src="https://uploadfiles.nowcoder.com/feed.png"></div></section><div class="comment-list">不采集评论<img src="https://uploadfiles.nowcoder.com/comment.png"></div></div>
        """
        await loader.loadURL(feedHTML, in: web, url: "https://www.nowcoder.com/feed/main/detail/0123456789abcdef0123456789abcdef")
        let feed = try await nowRead("detail")
        precondition(feed["body"] as? String == "动态第一题？\n动态第二题？")
        precondition(feed["author"] as? String == "动态作者")
        precondition((feed["images"] as? [String]) == ["https://uploadfiles.nowcoder.com/feed.png"])
        print("PASS: Nowcoder list dedup, source identity, post body/author, missing-body rejection, comments exclusion and image allowlist")
        window.orderOut(nil)
        let image = NSImage(size: NSSize(width:1000,height:160))
        image.lockFocus(); NSColor.white.setFill(); NSRect(x:0,y:0,width:1000,height:160).fill()
        ("How do you evaluate RAG retrieval?" as NSString).draw(at:NSPoint(x:30,y:70), withAttributes:[.font:NSFont.systemFont(ofSize:38),.foregroundColor:NSColor.black])
        image.unlockFocus()
        let segment = try await InterviewImages.recognize(image.tiffRepresentation!, label:"Synthetic OCR fixture", id:"test", storageDirectory:folder)
        precondition(segment.text.lowercased().contains("evaluate") && segment.text.contains("RAG"))
        precondition(FileManager.default.fileExists(atPath:folder.appendingPathComponent(segment.imageFile!).path))
        print("PASS: local Vision OCR with retained original image, no model transmission")
        print("PASS: real WKWebView source extraction, card and image dedup, multiline source, comment exclusion, image allowlist and login stop")
    }
    @MainActor final class Loader: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void,Never>?
        func load(_ html:String, in view:WKWebView, id:String) async { await withCheckedContinuation { continuation=$0; view.loadHTMLString(html, baseURL:URL(string:"https://www.xiaohongshu.com/explore/\(id)")) } }
        func loadURL(_ html:String, in view:WKWebView, url:String) async { await withCheckedContinuation { continuation=$0; view.loadHTMLString(html, baseURL:URL(string:url)) } }
        func webView(_ webView:WKWebView, didFinish navigation:WKNavigation!) { continuation?.resume(); continuation=nil }
    }
}
