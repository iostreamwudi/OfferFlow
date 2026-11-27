import SwiftUI
import WebKit
import AppKit

@MainActor final class BossSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var keyword = "AI 产品经理"
    @Published var city = "上海"
    @Published var cards: [BossCard] = []
    @Published var selectedCard: BossCard?
    @Published var draft: Job?
    @Published var loading = false
    @Published var reading = false
    @Published var address = ""
    @Published var message = "输入岗位和城市，打开 BOSS 后可自行登录，再读取当前搜索结果。"
    @Published var isError = false
    @Published var reviewRequest = 0
    @Published var communicating = false
    @Published var communicationStatus = ""
    @Published var communicationJob: Job?
    @Published var generatedGreeting: AIResponse?
    @Published var overwriteRequested = false
    @Published var greetingBook = JobGreetingBook()
    @Published var batchBook = BossBatchBook()
    @Published var batchRunning = false
    @Published var batchStopping = false
    @Published var batchLoadError = ""
    var batchTask: Task<Void, Never>?
    weak var store: Store?
    var communicationTask: Task<Void, Never>?
    var selectionTask: Task<Void, Never>?
    var selectionTicket = UUID()
    var communicationTicket = UUID()
    let viewport = ApplicationViewport()
    private var readGeneration = 0
    private var navigationGeneration = 0
    override init() {
        super.init()
        greetingBook = LocalAIStorage.read("job-greeting-drafts.json", as: JobGreetingBook.self) ?? JobGreetingBook()
        restoreBatchBook()
    }
    lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.pageZoom = 0.75
        view.setAccessibilityLabel("BOSS 招聘网页")
        return view
    }()
    func say(_ value: String, error: Bool = false) { message = value; isError = error }
    func search() {
        guard !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        navigatePreservingGreeting {
            self.cards = []; self.selectedCard = nil; self.draft = nil
            self.generatedGreeting = nil; self.communicationJob = nil
            self.load(BossSite.searchURL(keyword: self.keyword, city: self.city))
            self.say("请在右侧 BOSS 页面完成登录，搜索结果显示后点击「读取列表」。")
        }
    }
    func load(_ url: URL) {
        guard BossSite.isBoss(url) else { say("只支持 BOSS 官方网页。", error: true); return }
        draft = nil
        webView.load(URLRequest(url: url, timeoutInterval: 40))
    }
    func openDetail(_ card: BossCard) {
        selectJob(card, startChat: false, savedJobs: [])
    }
    func backToSearch() {
        navigatePreservingGreeting {
            self.selectedCard = nil; self.draft = nil; self.generatedGreeting = nil; self.communicationJob = nil
            self.load(BossSite.searchURL(keyword: self.keyword, city: self.city))
            self.say("已返回搜索页，原有草稿保留在「有草稿」中。左侧仍可切换岗位。")
        }
    }
    func review() {
        if let draft, BossSite.canonical(webView.url?.absoluteString ?? "") == draft.sourceURL {
            reviewRequest += 1
        } else { read(detail: true, reviewAfterReading: true) }
    }
    func read(detail: Bool, reviewAfterReading: Bool = false) {
        guard !batchRunning else { return }
        guard !reading else { return }
        guard let url = webView.url, BossSite.isBoss(url) else { say("请先打开 BOSS 搜索页面。", error: true); return }
        guard let scriptURL = Bundle.main.url(forResource: "BossExtractor", withExtension: "js"), let script = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            say("读取组件缺失，请重新编译应用。", error: true); return
        }
        readGeneration += 1
        let generation = readGeneration
        let navigation = navigationGeneration
        let startingURL = url.absoluteString
        reading = true
        if detail { draft = nil }
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self, self.readGeneration == generation else { return }
            self.reading = false
            guard self.navigationGeneration == navigation, self.webView.url?.absoluteString == startingURL else { self.say("页面已切换，请在加载完成后重新读取。", error: true); return }
            if let error { self.say("页面读取失败：\(error.localizedDescription)", error: true); return }
            guard let raw = value as? String, let data = raw.data(using: .utf8), let result = try? JSONDecoder().decode(BossReadResult.self, from: data) else {
                self.say("页面返回格式无法识别，请重新加载后再试。", error: true); return
            }
            guard !result.gated else { self.say("BOSS 要求安全验证。请在右侧自行完成验证后再读取。", error: true); return }
            if detail {
                if result.detail == nil, let previewURL = result.previewURL, let canonical = BossSite.canonical(previewURL), let url = URL(string: canonical) {
                    self.selectedCard = self.cards.first { BossSite.canonical($0.url) == canonical }
                    self.load(url)
                    self.say("已打开当前岗位的详情页。完整内容显示后，请再次点击「读取完整 JD」或「核对并保存」。")
                    return
                }
                self.acceptDetail(result, reviewAfterReading: reviewAfterReading)
            }
            else {
                guard BossSite.canonical(result.pageURL) == nil else { self.say("当前是职位详情页，请先返回搜索页再读取列表。", error: true); return }
                let valid = result.cards.filter { BossSite.canonical($0.url) != nil }
                guard !valid.isEmpty else { self.say("未识别到岗位卡片。请确认已登录、搜索结果已显示；页面结构变化也可能影响读取。", error: true); return }
                self.cards = valid; self.selectedCard = nil; self.draft = nil
                self.say("已读取当前页 \(valid.count) 个岗位。选择感兴趣的岗位，打开详情读取完整 JD。")
            }
        }
    }
    private func acceptDetail(_ result: BossReadResult, reviewAfterReading: Bool) {
        do {
            let job = try BossDraftBuilder.make(result, cards: cards, fallbackCity: city)
            selectedCard = cards.first { BossSite.canonical($0.url) == job.sourceURL }
            draft = job
            say("已读取「\(job.title)」完整 JD（\(job.jd.count) 字）。点击「核对并保存」可修改岗位信息后保存。")
            if reviewAfterReading { reviewRequest += 1 }
        } catch { say(error.localizedDescription, error: true) }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationGeneration += 1
        readGeneration += 1; reading = false
        draft = nil; loading = true; address = webView.url?.absoluteString ?? ""
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; address = webView.url?.absoluteString ?? ""
        Task { await viewport.refresh() }
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // Tracking resources may keep loading long after the main page is usable.
        // Enable explicit reads once the new main document has committed.
        loading = false; address = webView.url?.absoluteString ?? ""
        if BossSite.canonical(address) != nil { say("当前已打开岗位详情。内容显示后即可读取完整 JD，也可以直接核对并保存。") }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        loading = false; say("网页加载失败：\(error.localizedDescription)。可点击刷新重试。", error: true)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loading = false; draft = nil; say("浏览器页面已停止，请刷新后重新读取。", error: true) }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        // Normal website scripts and verification subframes remain website-owned.
        // Only the main BOSS page is ever read by our extractor.
        if url.scheme == "about" || url.scheme == "javascript" || BossSite.isBoss(url) { decisionHandler(.allow) }
        else if navigationAction.targetFrame?.isMainFrame == false && url.scheme == "https" { decisionHandler(.allow) }
        else {
            decisionHandler(.cancel)
            if navigationAction.targetFrame?.isMainFrame != false { say("已停止跳转到外部链接（\(url.host ?? url.scheme ?? "未知地址")）。", error: true) }
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, BossSite.isBoss(url) { load(url) }
        return nil
    }
}

struct BossWebView: NSViewRepresentable {
    let session: BossSession
    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct BossSearchSheet: View {
    @EnvironmentObject private var journey: FlowJourney
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @ObservedObject var session: BossSession
    var embedded = false
    var onReturn: (() -> Void)? = nil
    @State private var showingResults = true
    @State private var reviewing: Job?
    @State private var configuringGreeting = false
    @State private var greetingConfiguration = BossGreetingConfiguration()
    @State private var draftOnly = false
    @State private var showingBatchReport = false
    @State private var showingBatchSelection = false
    private func consumeIntent() {
        guard !session.batchRunning, let request = journey.intent, request.route == "boss" else { return }
        if let value = request.role ?? request.keyword, !value.isEmpty { session.keyword = value }
        journey.intent = nil
    }
    var displayedCards: [BossCard] {
        draftOnly ? session.greetingBook.entries.values.sorted { $0.updatedAt > $1.updatedAt }.map(\.card) : session.cards
    }
    var body: some View {
        FlowSurface {
        VStack(alignment: .leading, spacing: 0) {
            topBar.disabled(session.batchRunning)
            HStack(spacing: 8) {
                step("1", "搜索与登录", active: session.cards.isEmpty)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(muted)
                step("2", "读取列表，选择岗位", active: !session.cards.isEmpty && session.draft == nil)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(muted)
                step("3", "沟通与草稿", active: session.communicationJob != nil || session.communicating)
                Spacer()
            }.padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            HStack(spacing: 0) {
                if showingResults {
                    results.frame(width: 290)
                    Divider()
                }
                VStack(spacing: 0) {
                    browserBar.disabled(session.batchRunning)
                    Divider()
                    ZStack {
                        BossWebView(session: session)
                            .allowsHitTesting(!session.batchRunning)
                        if session.address.isEmpty && !session.loading {
                            VStack(spacing: 14) {
                                Image(systemName: "globe").font(.system(size: 38)).foregroundStyle(accent.opacity(0.5))
                                Text("在这里打开 BOSS 搜索").font(.system(size: 18, weight: .semibold))
                                Text("登录由你在 BOSS 官方页面完成。\n页面显示岗位后，点击「读取列表」。").font(.system(size: 12)).foregroundStyle(muted).multilineTextAlignment(.center).lineSpacing(6)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
                        }
                    }
                    ApplicationHorizontalScroll(viewport: session.viewport).disabled(session.batchRunning)
                }.frame(minWidth: 0, maxWidth: .infinity)
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            .clipped()
            Divider()
            footer.fixedSize(horizontal: false, vertical: true)
        }.frame(width: embedded ? nil : 1220, height: embedded ? nil : 800)
            .frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(ink).background(.white)
            .onDisappear {
                session.viewport.stop()
                if session.batchRunning { session.stopBatch() }
                else { session.selectionTask?.cancel(); session.cancelCommunication(); Task { await session.preserveCurrentGreeting() } }
            }
            .onAppear {
                session.viewport.start(session.webView)
                session.attach(store)
                greetingConfiguration = (try? BossGreetingConfiguration.load()) ?? BossGreetingConfiguration()
                if session.address.isEmpty { session.keyword = store.profile.target.isEmpty ? "AI 产品经理" : store.profile.target }; consumeIntent()
            }
            .onChange(of: journey.revision) { _, _ in consumeIntent() }
            .onChange(of: session.reviewRequest) { _, _ in reviewing = session.draft }
            .sheet(item: $reviewing) { job in
                BossReviewSheet(job: job) {
                    session.say("岗位已保存到工作台，可继续查看匹配分析。")
                    reviewing = nil
                    if let onReturn { onReturn() } else { dismiss() }
                }.environmentObject(store)
            }
            .sheet(isPresented: $configuringGreeting) {
                BossGreetingTemplateSheet(previewJob: session.communicationJob ?? session.draft) { value in
                    greetingConfiguration = value
                    session.say("已启用：" + value.label + "。点击岗位的立即沟通或继续沟通即可使用；聊天框中已有的文字不会立即改动。")
                }
            }
            .sheet(isPresented: $showingBatchSelection) {
                BossBatchSelection(cards: displayedCards, template: greetingConfiguration.label) { cards, onePerCompany, skipCompany in session.startBatch(cards, onePerCompany: onePerCompany, skipContactedCompany: skipCompany) }
            }
            .sheet(isPresented: $showingBatchReport) { BossBatchReport(session: session) }
            .alert("聊天框里已有草稿", isPresented: $session.overwriteRequested) {
                Button("保留原草稿", role: .cancel) {}
                Button("替换为新草稿") { session.fillGenerated(overwrite: true) }
            } message: { Text("替换只修改输入框，不会发送消息。请确认这是你要沟通的岗位。") }
    
        }
    }
    var topBar: some View {
        HStack(spacing: 12) {
            Button("返回工作区", systemImage: "chevron.left") { if let onReturn { onReturn() } else { dismiss() } }
                .keyboardShortcut(.cancelAction)
                .help("返回打开 BOSS 搜索前的页面，保留岗位与草稿")
            if !embedded { VStack(alignment: .leading, spacing: 6) {
                Text("发现 BOSS 上的真实机会").font(.system(size: 21, weight: .bold))
                Text("当前页读取 · 本机保存 · 由你选择岗位").font(.system(size: 11)).foregroundStyle(muted)
            } }
            Spacer()
            Button("打招呼模板", systemImage: "text.alignleft") { configuringGreeting = true }.disabled(session.communicating)
            TextField("输入岗位关键词", text: $session.keyword).textFieldStyle(.flow).frame(width: 200).onSubmit { session.search() }.accessibilityLabel("BOSS 岗位关键词")
            FlowSelect(title: "城市", selection: $session.city, options: BossSite.cities.map { ($0, $0) }).frame(width: 100).accessibilityLabel("BOSS 搜索城市")
            Button("打开 BOSS 搜索", systemImage: "magnifyingglass") { session.search() }.buttonStyle(.flowPrimary).disabled(session.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(24)
    }
    func step(_ number: String, _ title: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            Text(number).font(.system(size: 10, weight: .semibold)).frame(width: 20, height: 20).background(active ? accent : muted.opacity(0.1), in: Circle()).foregroundStyle(active ? .white : muted)
            Text(title).font(.system(size: 11, weight: active ? .semibold : .regular)).foregroundStyle(active ? accent : muted)
        }
    }
    var browserBar: some View {
        HStack(spacing: 8) {
            Button { showingResults.toggle() } label: { Image(systemName: "sidebar.left") }
                .help(showingResults ? "收起岗位列表，展开网页" : "显示岗位列表")
                .accessibilityLabel(showingResults ? "收起岗位列表" : "显示岗位列表")
            Button { session.navigatePreservingGreeting { session.webView.goBack() } } label: { Image(systemName: "chevron.left") }.help("浏览器后退，保留当前草稿").disabled(!session.webView.canGoBack)
            Button { session.webView.reload() } label: { Image(systemName: "arrow.clockwise") }.help("刷新网页").disabled(session.address.isEmpty)
            Text(session.address.isEmpty ? "BOSS 官方网页" : session.address).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled).frame(minWidth: 30, maxWidth: .infinity, alignment: .leading)
                .help(session.address)
            ApplicationViewportTools(viewport: session.viewport).disabled(session.address.isEmpty)
            if session.loading { ProgressView().controlSize(.small) }
            Button { session.backToSearch() } label: { Image(systemName: "magnifyingglass") }
                .help("返回搜索页").accessibilityLabel("返回搜索页").disabled(session.address.isEmpty)
        }.buttonStyle(.browserIcon).padding(.horizontal, 10).padding(.vertical, 8).background(.white)
    }
    var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("读取到的岗位").font(.system(size: 13, weight: .semibold)); Text("\(session.cards.count)").font(.system(size: 11)).foregroundStyle(muted); Spacer(); Button("读取列表") { session.read(detail: false) }.disabled(session.batchRunning || session.loading || session.reading || session.address.isEmpty) }.padding(16)
            FlowSegments(selection: $draftOnly, options: [(false, "当前列表 \(session.cards.count)"), (true, "有草稿 \(session.greetingBook.entries.count)")]).padding(.horizontal, 12).padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("当前使用：" + greetingConfiguration.label).font(.system(size: 11)).foregroundStyle(muted)
                    Spacer()
                }
                if session.batchRunning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(session.batchStopping ? "正在停止…" : "正在按岗位发送招呼").font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button("停止") { session.stopBatch() }.disabled(session.batchStopping)
                    }
                } else {
                    Button("批量发送招呼", systemImage: "paperplane.fill") { showingBatchSelection = true }
                        .buttonStyle(.flowPrimary)
                        .disabled(displayedCards.isEmpty || session.communicating || session.reading || !session.batchLoadError.isEmpty)
                }
                Text("选择要沟通的岗位，按模板准备并发送招呼；范围和同公司规则可调整。")
                    .font(.system(size: 10)).foregroundStyle(muted)
                if !session.batchLoadError.isEmpty { Text(session.batchLoadError).font(.system(size: 10)).foregroundStyle(.orange) }
                if !session.batchBook.items.isEmpty { Button("查看批量进度与记录") { showingBatchReport = true }.font(.system(size: 11)) }
            }.padding(.horizontal, 12).padding(.bottom, 12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 9) {
                    if displayedCards.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "rectangle.stack.badge.plus").font(.title2).foregroundStyle(accent)
                            Text(draftOnly ? "还没有保留的草稿" : "先搜索，再读取").font(.system(size: 14, weight: .semibold))
                            Text(draftOnly ? "生成打招呼语后会按岗位保留，可以随时回来继续沟通。" : "在右侧完成登录和搜索，点击上方「读取列表」。每次只读取当前页，不自动翻页。").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(6)
                        }.padding(18).padding(.top, 25)
                    }
                    ForEach(displayedCards) { card in resultCard(card).disabled(session.batchRunning) }
                }.padding(12)
            }.frame(minHeight: 0, maxHeight: .infinity)
            if let job = session.communicationJob, let record = store.application(for: job) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("沟通记录：\(record.stage.rawValue)").font(.system(size: 11, weight: .semibold))
                    Text("\(job.company) · \(job.title)").font(.system(size: 10)).lineLimit(2)
                    Button("我已在 BOSS 发送") { session.confirmSent() }
                        .disabled(session.batchRunning || session.communicating || record.sentAt != nil || record.stage.order > ApplicationStage.sent.order)
                        .help("仅登记当前岗位的发送结果，不会向 BOSS 发送消息")
                    Text("在 BOSS 手动发送后再登记；回复与后续进展在「求职管理」记录。").font(.system(size: 9)).foregroundStyle(muted)
                }.padding(12)
            }
            Text("单个岗位沟通会保留草稿；批量投递会按所选方式自动发送招呼。").font(.system(size: 10)).foregroundStyle(muted).lineSpacing(4).padding(12)
        }.background(canvas.opacity(0.6))
    }
    func resultCard(_ card: BossCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { session.openDetail(card) } label: {
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(session.selectedCard?.id == card.id ? "正在浏览" : "点击查看详情").font(.system(size: 9)).foregroundStyle(session.selectedCard?.id == card.id ? accent : muted)
                    Spacer()
                    if session.greetingBook.draft(for: card.url) != nil { Label("草稿已保留", systemImage: "doc.text").font(.system(size: 9)).foregroundStyle(accent) }
                }
                Text(card.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text(card.company).font(.system(size: 11)).foregroundStyle(muted)
                Text(card.salary.isEmpty ? "薪资未展示" : card.salary).font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                Text([card.city, card.experience].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(muted).lineLimit(2)
              }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("查看岗位：\(card.title)，\(card.company)").help("点击切换到本岗位详情，当前草稿会保留")
                HStack {
                    Button("查看详情", systemImage: "arrow.up.right") { session.openDetail(card) }.buttonStyle(.borderless)
                    Spacer()
                    Button(cardRecord(card).map { $0.shouldOpenExistingChat ? "打开聊天" : "继续沟通" } ?? (session.greetingBook.draft(for: card.url) == nil ? "立即沟通" : "继续沟通"), systemImage: "bubble.left.and.text.bubble.right") { session.communicate(card, savedJobs: store.jobs) }.buttonStyle(.flowPrimary)
                }.font(.system(size: 10))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(session.selectedCard?.id == card.id ? accent : .black.opacity(0.06)))
    }
    func cardRecord(_ card: BossCard) -> ApplicationRecord? {
        guard let job = store.jobs.first(where: { $0.sourceURL == BossSite.canonical(card.url) }) else { return nil }
        return store.application(for: job)
    }
    var footer: some View {
        HStack(spacing: 16) {
            Image(systemName: session.isError ? "exclamationmark.circle" : "info.circle").foregroundStyle(session.isError ? .orange : accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(session.communicationStatus.isEmpty ? session.message : session.communicationStatus).font(.system(size: 11)).foregroundStyle(session.isError ? Color.orange : ink).lineLimit(3)
                Text("登录与验证码由你处理。页面读取受 BOSS 平台规则限制，正式商业接入仍需取得许可。").font(.system(size: 9)).foregroundStyle(muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if session.communicating { ProgressView().controlSize(.small); Button("取消") { session.cancelCommunication() } }
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 10) {
                    Button { session.read(detail: true) } label: { Label(session.reading ? "正在读取…" : "读取完整 JD", systemImage: "doc.text.viewfinder") }
                        .disabled(session.batchRunning || session.reading || session.address.isEmpty).help("读取右侧当前岗位，无需先在左侧选中；后台资源加载不影响读取。")
                    Button { session.review() } label: { Label("核对并保存", systemImage: "checkmark.square") }
                        .buttonStyle(.flowPrimary).disabled(session.batchRunning || session.reading || session.address.isEmpty)
                        .help("打开可编辑的核对页；尚未读取时，会先尝试读取当前岗位。")
                }
                Text(session.address.isEmpty ? "先打开 BOSS，再进入一个岗位" : session.reading ? "正在提取岗位信息，请稍候" : session.draft == nil ? "读取右侧当前岗位，也可直接点击核对并保存" : "JD 已就绪，可核对、修改并保存")
                    .font(.system(size: 10)).foregroundStyle(muted)
            }
        }.padding(18)
    }
}

struct BossReviewSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var job: Job
    @State private var error = ""
    let onSaved: () -> Void
    var existing: Bool { store.jobs.contains { $0.sourceURL == job.sourceURL } }
    var valid: Bool { [job.title, job.company, job.city, job.jd].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var body: some View {
        FlowSurface {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("核对岗位信息").font(.system(size: 23, weight: .bold)); Spacer(); Text(existing ? "更新已有岗位" : "保存新岗位").font(.system(size: 11)).foregroundStyle(accent) }
            Text("检查并修改识别结果，确认后保存到本机工作台。").font(.system(size: 12)).foregroundStyle(muted)
            HStack(spacing: 16) { field("岗位名称 *", text: $job.title); field("公司名称 *", text: $job.company) }
            HStack(spacing: 16) { field("城市 *", text: $job.city); field("薪资", text: $job.salary); field("经验与学历", text: $job.experience) }
            HStack { Text("完整 JD *").font(.system(size: 12, weight: .semibold)); Spacer(); Text("\(job.jd.count) 字").font(.system(size: 10)).foregroundStyle(muted) }
            TextEditor(text: $job.jd).font(.system(size: 12)).lineSpacing(5).padding(10).frame(height: 260).background(canvas).overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.2))).accessibilityLabel("核对完整 JD")
            Text(job.sourceURL ?? "").font(.system(size: 10)).foregroundStyle(muted).textSelection(.enabled)
            Text(existing ? "保存会更新此岗位的 JD 和信息，保留原有收藏及投递清单状态。" : "保存后将进入此岗位的匹配分析。岗位原链接与读取时间一并保留。")
                .font(.system(size: 11)).foregroundStyle(muted)
            if !error.isEmpty { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled) }
            HStack { Button("返回检查") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(existing ? "更新并查看匹配分析" : "保存并查看匹配分析") {
                job.title = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
                job.company = job.company.trimmingCharacters(in: .whitespacesAndNewlines)
                job.city = job.city.trimmingCharacters(in: .whitespacesAndNewlines)
                job.tags = Analysis.vocabulary.filter { Analysis.contains(job.jd, $0) }
                if store.importBoss(job) { dismiss(); onSaved() }
                else { error = store.notice; store.notice = "" }
            }.buttonStyle(.flowPrimary).disabled(!valid).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 700).foregroundStyle(ink)
    
        }
    }
    func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(label).font(.system(size: 11)).foregroundStyle(muted); TextField(label, text: text).textFieldStyle(.flow).labelsHidden().accessibilityLabel(label) }
    }
}
