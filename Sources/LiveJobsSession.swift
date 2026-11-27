import SwiftUI
import WebKit
import AppKit

@MainActor final class LiveJobsSession: NSObject, ObservableObject, WKNavigationDelegate {
    static let sourceURL = URL(string: LiveJobParser.sourceURL)!
    @Published private(set) var snapshot: LiveJobSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusText = "正在准备岗位库"
    @Published private(set) var lastError: String?
    @Published private(set) var favoriteIDs = Set<String>()
    @Published var showSource = false
    var jobs: [LiveJobListing] { snapshot?.listings ?? [] }
    @Published private(set) var lastSuccessfulUpdate: Date?
    // A successful check can change the timestamp without invalidating 14,000 rows.
    @Published private(set) var dataRevision = 0
    @Published private(set) var syncWebView: WKWebView?
    private let cache: LiveJobCache
    private let cacheTask: Task<CachedJobs, Never>
    private var cacheLoaded = false
    private var refreshTask: Task<Void, Never>?
    private var loaded = false
    private var navigationError: String?
    private var lastAttempt = Date.distantPast
    private var periodicTask: Task<Void, Never>?
    private var pendingDropSignature: String?
    private var retrySoon = false

    private struct CachedJobs: Sendable {
        var snapshot: LiveJobSnapshot?
        var favorites = Set<String>()
        var error: String?
    }

    override init() {
        let cache = LiveJobCache()
        self.cache = cache
        // JSON decoding, schema checks and record hashes must never block AppKit.
        cacheTask = Task.detached(priority: .userInitiated) {
            var result = CachedJobs()
            do { result.snapshot = try cache.load() }
            catch { result.error = error.localizedDescription }
            do { result.favorites = try cache.loadFavorites() }
            catch { result.error = error.localizedDescription }
            return result
        }
        super.init()
        Task { [weak self] in await self?.loadCachedJobs() }
    }

    private func loadCachedJobs() async {
        let result = await cacheTask.value
        guard !cacheLoaded else { return }
        cacheLoaded = true
        snapshot = result.snapshot
        lastSuccessfulUpdate = result.snapshot?.fetchedAt
        favoriteIDs = result.favorites
        if result.snapshot != nil { dataRevision += 1 }
        if !isRefreshing {
            lastError = result.error
            statusText = snapshot == nil ? "准备获取最新岗位" : "已显示本机岗位"
        }
    }

    private func makeSyncPage() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), configuration: configuration)
        view.navigationDelegate = self
        view.setAccessibilityLabel("岗位更新服务")
        syncWebView = view
        return view
    }

    private func releaseSyncPage() {
        guard let view = syncWebView else { return }
        view.stopLoading()
        view.navigationDelegate = nil
        view.loadHTMLString("", baseURL: nil)
        view.removeFromSuperview()
        syncWebView = nil
    }

    func activate() {
        guard !isRefreshing, Date().timeIntervalSince(lastAttempt) > 5 else { return }
        refresh()
    }

    func foreground() {
        guard Date().timeIntervalSince(lastAttempt) >= 60 else { return }
        activate()
    }

    func startPeriodicUpdates() {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self else { return }
                if NSApp.isActive, Date().timeIntervalSince(self.lastAttempt) >= (self.lastError == nil ? 300 : 60) {
                    self.activate()
                }
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true; lastError = nil; loaded = false; navigationError = nil
        lastAttempt = Date(); statusText = "正在检查最新岗位…"
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.loadCachedJobs()
            await self.readLatest()
        }
    }

    func openSource() { showSource = true }
    func closeSource() { showSource = false }
    func toggleFavorite(_ id: String) {
        var ids = favoriteIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        do { try cache.saveFavorites(ids); favoriteIDs = ids }
        catch { lastError = "收藏保存失败：\(error.localizedDescription)" }
    }

    private func readLatest() async {
        defer {
            releaseSyncPage()
            isRefreshing = false; refreshTask = nil
            if retrySoon {
                retrySoon = false
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    self?.activate()
                }
            }
        }
        let webView = makeSyncPage()
        webView.load(URLRequest(url: Self.sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45))
        do {
            guard let scriptURL = Bundle.main.url(forResource: "FeishuReader", withExtension: "js") else {
                throw SyncError.message("岗位读取组件缺失，请重新安装。")
            }
            let script = try String(contentsOf: scriptURL, encoding: .utf8)
            var readyCount = 0
            for _ in 0..<45 {
                try Task.checkCancellation()
                if let navigationError { throw SyncError.message(navigationError) }
                if loaded {
                    let result = try await evaluate(script, mode: "probe", in: webView)
                    if result["state"] as? String == "ready" { readyCount += 1 } else { readyCount = 0 }
                    if readyCount >= 3 { break }
                }
                try await Task.sleep(for: .seconds(1))
            }
            guard readyCount >= 3 else { throw SyncError.message("岗位库暂未加载完成，已保留已有内容，将自动重试。") }
            statusText = "正在读取并核对最新岗位…"
            let result = try await evaluate(script, mode: "copy", in: webView)
            guard let text = result["text"] as? String, !text.isEmpty else {
                throw SyncError.message("数据源暂时无法自动读取，请稍后重试。")
            }
            guard let count = result["count"] as? Int, count > 0,
                  let headers = result["headers"] as? [String], headers == LiveJobParser.expectedHeaders else {
                throw SyncError.message("尚未确认招聘数据的完整字段，本次保留原有岗位。")
            }
            // Release the third-party page as soon as copying completes. Parsing
            // only needs the returned text, and the page has no reason to stay live.
            releaseSyncPage()
            let signature = await Task.detached(priority: .utility) {
                LiveJobParser.fingerprint(text: text)
            }.value
            if snapshot?.sourceFingerprint == signature, snapshot?.sourceRecordCount == count {
                lastSuccessfulUpdate = Date()
                lastError = nil; pendingDropSignature = nil
                statusText = "已是最新内容"
                return
            }
            if let previous = snapshot, count < previous.sourceRecordCount * 4 / 5 {
                if pendingDropSignature != signature {
                    pendingDropSignature = signature; retrySoon = true
                    throw SyncError.message("招聘记录数变化较大，正在重新读取复核；暂时显示已有岗位。")
                }
            }
            let cache = self.cache
            let next = try await Task.detached(priority: .userInitiated) {
                let next = try LiveJobParser.parse(text, expectedRecordCount: count, headers: headers)
                try cache.save(next)
                return next
            }.value
            snapshot = next; dataRevision += 1; lastSuccessfulUpdate = next.fetchedAt
            lastError = nil; pendingDropSignature = nil; statusText = "已更新至最新内容"
        } catch {
            lastError = error.localizedDescription
            statusText = snapshot == nil ? "本次更新未完成" : "正在显示上次成功更新的岗位"
        }
    }

    // WebKit scripts can stall on a loading/error page. Resume exactly once so
    // every failed attempt also reaches readLatest's page-release path.
    private func evaluate(_ script: String, mode: String, in page: WKWebView) async throws -> [String: Any] {
        let value: Any = try await withCheckedThrowingContinuation { continuation in
            let pending = ScriptEvaluation(continuation)
            pending.timeout = Task {
                do { try await Task.sleep(for: .seconds(mode == "copy" ? 45 : 8)) } catch { return }
                pending.finish(.failure(SyncError.message("读取超时，已保留本机岗位，稍后将自动重试。")))
            }
            page.callAsyncJavaScript(script, arguments: ["mode": mode], in: nil, in: .page) { result in
                pending.finish(result)
            }
        }
        return value as? [String: Any] ?? [:]
    }

    @MainActor private final class ScriptEvaluation {
        var continuation: CheckedContinuation<Any, Error>?
        var timeout: Task<Void, Never>?
        init(_ continuation: CheckedContinuation<Any, Error>) { self.continuation = continuation }
        func finish(_ result: Result<Any, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            timeout?.cancel(); timeout = nil
            continuation.resume(with: result)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === syncWebView else { return }
        loaded = true
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === syncWebView else { return }
        failed(error)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === syncWebView else { return }
        failed(error)
    }
    private func failed(_ error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { navigationError = error.localizedDescription }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === syncWebView else { return }
        navigationError = "数据源进程已停止，请重试更新。"
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard webView === syncWebView else { decisionHandler(.cancel); return }
        guard navigationAction.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
        guard let url = navigationAction.request.url, url.scheme == "https", url.host == "my.feishu.cn",
              url.port == nil || url.port == 443, url.path == Self.sourceURL.path,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "table", value: "tblCNHUxBdaYvYvx")) == true,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "view", value: "vewIPUzblP")) == true else {
            navigationError = "数据源需要重新确认访问状态，请稍后重试更新。"
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    private enum SyncError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
    }
}

struct LiveJobsSyncHost: NSViewRepresentable {
    @ObservedObject var session: LiveJobsSession
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ host: NSView, context: Context) {
        if let page = session.syncWebView, page.superview !== host {
            host.subviews.forEach { $0.removeFromSuperview() }
            page.frame = host.bounds
            page.autoresizingMask = [.width, .height]
            host.addSubview(page)
        } else if session.syncWebView == nil {
            host.subviews.forEach { $0.removeFromSuperview() }
        }
    }
}

struct LiveJobsSourceWebView: NSViewRepresentable {
    @ObservedObject var session: LiveJobsSession
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.load(URLRequest(url: LiveJobsSession.sourceURL))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
