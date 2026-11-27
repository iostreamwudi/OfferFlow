import SwiftUI
import WebKit
import Vision
import AppKit

struct InterviewCard: Decodable, Identifiable {
    var id: String
    var title: String
    var author: String
    var date: String
    var url: String
}
enum InterviewImages {
    static var directory: URL { LocalAIStorage.directory.appendingPathComponent("InterviewImages") }
    static func url(_ name: String) -> URL? {
        guard !name.contains("/"), !name.contains("..") else { return nil }
        return directory.appendingPathComponent(name)
    }
    static func recognize(_ data: Data, label: String, id: String, storageDirectory: URL = InterviewImages.directory) async throws -> InterviewSegment {
        guard data.count <= 20_000_000 else { throw AIError.message("单张图片超过 20 MB，请压缩后导入。") }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(data: data).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            let name = UUID().uuidString + ".image"
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            try data.write(to: storageDirectory.appendingPathComponent(name), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageDirectory.appendingPathComponent(name).path)
            return InterviewSegment(id: id, label: label + " · OCR 待核对", text: text, imageFile: name)
        }.value
    }
    static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && ["xhscdn.com", "nowcoder.com"].contains { domain in url.host == domain || url.host?.hasSuffix("." + domain) == true }
    }
    private final class Redirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(request.url.map(allowed) == true ? request : nil)
        }
    }
    static let session = URLSession(configuration: .ephemeral, delegate: Redirects(), delegateQueue: nil)
    static func fetch(_ url: URL) async throws -> Data {
        guard allowed(url) else { throw AIError.message("图片来源不受支持，请保存截图后导入。") }
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url, timeoutInterval: 45))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.expectedContentLength <= 20_000_000 else { throw AIError.message("图片无法下载，请导入截图补充。") }
        var data = Data()
        for try await byte in bytes {
            if data.count >= 20_000_000 { throw AIError.message("图片过大，请压缩后导入。") }
            data.append(byte)
        }
        return data
    }
}
@MainActor final class InterviewBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var source: InterviewSource = .xiaohongshu
    @Published var address = "https://www.xiaohongshu.com/explore"
    @Published var cards: [InterviewCard] = []
    @Published var busy = false
    @Published var loading = false
    @Published var status = "登录后搜索面经，点击读取列表。"
    @Published var error: String?
    private var operation: Task<Void, Never>?
    private var ticket = UUID()
    private let world = WKContentWorld.world(name: "CareerAI.Interviews")
    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "Version/17.6 Safari/605.1.15"
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.setAccessibilityLabel("面经来源浏览器")
    }
    static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && InterviewSource.detect(url.absoluteString) != nil
    }
    func open(_ raw: String) {
        guard let url = URL(string: raw), Self.allowed(url) else { error = "内置采集支持小红书、牛客网 HTTPS 链接；其他来源可粘贴文字导入。"; return }
        if let next = InterviewSource.detect(raw), next != source { cards = [] }
        source = InterviewSource.detect(raw) ?? source
        cancel(); error = nil; address = InterviewRules.canonical(raw).isEmpty ? raw : InterviewRules.canonical(raw)
        webView.load(URLRequest(url: url))
    }
    func search(_ keyword: String) {
        cards = []; open(source.searchURL(keyword).absoluteString)
    }

    func cancel() { ticket = UUID(); operation?.cancel(); operation = nil; busy = false }
    static func destination(for card: InterviewCard) -> URL? {
        guard InterviewRules.sourceID(card.url) == card.id, var url = URLComponents(string: card.url) else { return nil }
        if InterviewSource.detect(card.url) == .nowcoder { return URL(string: InterviewRules.canonical(card.url)) }
        // Search cards carry the access context, but their /search_result/:id path
        // is handled by the SPA. Direct navigation uses the observed note route.
        url.path = "/explore/" + card.id
        if !(url.queryItems ?? []).contains(where: { $0.name == "xsec_source" && !($0.value ?? "").isEmpty }) {
            var items = (url.queryItems ?? []).filter { $0.name != "xsec_source" }
            items.append(URLQueryItem(name: "xsec_source", value: "pc_search"))
            url.queryItems = items
        }
        return url.url.flatMap { Self.allowed($0) ? $0 : nil }
    }
    func openCard(_ card: InterviewCard) {
        guard let url = Self.destination(for: card) else { error = "帖子链接无效，请重新读取当前列表。"; return }
        status = "正在打开所选帖子…"
        guard let page = webView.url, InterviewSource.detect(page.absoluteString) == .xiaohongshu,
              InterviewSource.detect(card.url) == .xiaohongshu, !loading else { open(url.absoluteString); return }
        cancel(); error = nil
        let current = ticket; busy = true
        operation = Task {
            defer { if ticket == current { busy = false } }
            do {
                let result = try await run("open", selectedID: card.id)
                guard ticket == current else { return }
                if result["missing"] as? Bool == true {
                    open(url.absoluteString)
                } else if result["id"] as? String == card.id {
                    status = "已选择「" + card.title + "」。"
                }
            } catch is CancellationError {} catch { if ticket == current { self.error = error.localizedDescription } }
        }
    }
    private func run(_ mode: String, selectedID: String = "") async throws -> [String: Any] {
        guard let currentURL = webView.url, Self.allowed(currentURL), let provider = InterviewSource.detect(currentURL.absoluteString) else { throw AIError.message("请先打开小红书或牛客网。") }
        guard let url = Bundle.main.url(forResource: provider.reader, withExtension: "js") else { throw AIError.message("面经读取组件缺失，请重新安装。") }
        let script = try String(contentsOf: url, encoding: .utf8)
        let result = try await webView.callAsyncJavaScript(script, arguments: ["mode": mode, "selectedID": selectedID], in: nil, contentWorld: world)
        guard let payload = result as? [String: Any] else { throw AIError.message("网页返回格式无法识别。") }
        if let error = payload["error"] as? String, payload["pending"] as? Bool != true { throw AIError.message(error) }
        return payload
    }
    func readList() {
        guard !busy, !loading else { return }
        cancel(); let current = ticket; busy = true; error = nil
        operation = Task {
            defer { if ticket == current { busy = false } }
            do {
                let payload = try await run("list"); try Task.checkCancellation()
                guard ticket == current else { return }
                let result = try JSONDecoder().decode([InterviewCard].self, from: JSONSerialization.data(withJSONObject: payload["cards"] ?? []))
                var byID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
                for item in result { byID[item.id] = item }
                let previous = Set(cards.map(\.id))
                cards = cards.map { byID[$0.id]! } + result.filter { !previous.contains($0.id) }
                status = result.isEmpty ? "当前页没有读到笔记卡片。请完成登录，在站内搜索后重试。" : "累计读取 \(cards.count) 条。可继续滚动网页，再读取并合并结果。"
            } catch { if ticket == current { self.error = error.localizedDescription } }
        }
    }
    func readNote(store: InterviewStore, analyze: Bool = false, company: String = "", role: String = "", onReady: ((String) -> Void)? = nil, onSaved: @escaping (String) -> Void) {
        guard !busy, !loading else { return }
        let targetID = store.target.id
        var savedID: String?
        cancel(); let current = ticket; busy = true; error = nil
        operation = Task {
            defer { if ticket == current { busy = false } }
            do {
                status = "正在读取本篇正文和图片…"
                var payload = try await run("detail")
                for _ in 0..<5 where payload["pending"] as? Bool == true {
                    try await Task.sleep(for: .milliseconds(500))
                    try Task.checkCancellation()
                    payload = try await run("detail")
                }
                try Task.checkCancellation()
                if let message = payload["error"] as? String { throw AIError.message(message) }
                guard ticket == current else { return }
                guard let raw = payload["url"] as? String, let id = InterviewRules.noteID(raw) else {
                    throw AIError.message("无法识别本篇链接，请打开具体的面经再收集。")
                }
                let originalURL = webView.url
                var note = InterviewNote(id: id, title: payload["title"] as? String ?? "面经")
                note.preparationTargetIDs = [targetID]
                if !company.isEmpty, FlowCompanyRole.companyMatches(note.title, query: company) { note.sourceCompany = company }
                if !role.isEmpty, FlowCompanyRole.role(note.title).contains(FlowCompanyRole.role(role)) { note.sourceRole = role }
                note.sourceURL = InterviewRules.canonical(raw); note.author = payload["author"] as? String ?? ""; note.dateRaw = payload["date"] as? String ?? ""
                note.aiNotice = payload["aiNotice"] as? Bool ?? false
                let body = payload["body"] as? String ?? ""
                if !body.isEmpty { note.segments = [.init(id: "body", label: "网页正文", text: body)] }
                let images = payload["images"] as? [String] ?? []
                note.completeness = "正文已读取；图文完整度待核对"
                // Commit source text before OCR so an image/network failure does not lose it.
                store.upsert(note)
                guard store.error == nil else { return }
                savedID = note.id
                onSaved(note.id)
                var failures = 0
                for (index, rawImage) in images.enumerated() {
                    try Task.checkCancellation()
                    guard ticket == current, webView.url == originalURL else { throw CancellationError() }
                    status = "正在识别图片 \(index + 1)/\(images.count)…正文已保留"
                    do {
                        guard let url = URL(string: rawImage) else { throw AIError.message("无效图片") }
                        let data = try await InterviewImages.fetch(url)
                        let segment = try await InterviewImages.recognize(data, label: "图片 \(index + 1)", id: "image-\(index + 1)")
                        try Task.checkCancellation()
                        guard ticket == current, webView.url == originalURL else { throw CancellationError() }
                        note.segments.append(segment)
                        if segment.text.isEmpty { failures += 1 }
                        store.upsert(note)
                    } catch is CancellationError { throw CancellationError() }
                    catch { failures += 1 }
                }
                guard ticket == current, webView.url == originalURL else { throw CancellationError() }
                note.completeness = "正文 \(body.isEmpty ? "未读到" : "已保存") · 图片共 \(images.count) 张，已读取 \(max(0, images.count - failures)) 张" + (failures > 0 ? "，\(failures) 张待补齐" : "")
                store.upsert(note)
                if analyze {
                    status = "正在整理成可练习的问题…"
                    let source = store.library.notes.first(where: { $0.id == note.id }) ?? note
                    let (category, questions, model) = try await InterviewAI.extract(source)
                    try Task.checkCancellation()
                    guard ticket == current, store.library.notes.first(where: { $0.id == note.id })?.fingerprint == source.fingerprint else { return }
                    store.update(note.id) { $0.applyExtraction(questions, category: category, model: model) }
                    let count = store.library.notes.first { $0.id == note.id }?.questions.count ?? 0
                    status = count == 0 ? "原文已保存，本篇未发现明确原题。" : "已整理 \(count) 道有原文依据的问题。" + (failures > 0 ? "部分图片待补齐。" : "")
                    guard store.error == nil else { return }
                    onReady?(note.id)
                } else { status = "原文已保存，可稍后提取问题。"; if store.error == nil { onReady?(note.id) } }
            } catch is CancellationError { if ticket == current { status = "读取已停止，已保存的内容保留。" } }
            catch {
                guard ticket == current else { return }
                self.error = error.localizedDescription
                if let savedID { onReady?(savedID) }
            }
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { cancel(); loading = true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false; error = nil; source = webView.url.flatMap { InterviewSource.detect($0.absoluteString) } ?? source; address = webView.url.map { InterviewRules.canonical($0.absoluteString) } ?? address }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loading = false; if ![NSURLErrorCancelled, 102].contains((error as NSError).code), self.error == nil { self.error = "网页加载失败：\(error.localizedDescription)" } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loading = false; if ![NSURLErrorCancelled, 102].contains((error as NSError).code), self.error == nil { self.error = "网页加载失败：\(error.localizedDescription)" } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { cancel(); loading = false; error = "网页已停止，请刷新重试。" }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == false, ["https", "about"].contains(url.scheme ?? "") { decisionHandler(.allow); return }
        if url.scheme == "http", var secure = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            secure.scheme = "https"
            if let upgraded = secure.url, Self.allowed(upgraded) { webView.load(URLRequest(url: upgraded)); decisionHandler(.cancel); return }
        }
        guard Self.allowed(url) else { self.error = "页面跳转暂不支持：" + (url.scheme ?? "未知协议") + "://" + (url.host ?? ""); decisionHandler(.cancel); return }
        if navigationAction.targetFrame == nil { open(url.absoluteString); decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { open(url.absoluteString) }; return nil
    }
}
struct InterviewWebView: NSViewRepresentable {
    let browser: InterviewBrowser
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
