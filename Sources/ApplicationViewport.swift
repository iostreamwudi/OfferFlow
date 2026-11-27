import SwiftUI
import WebKit

/// A viewport-only helper: never reads or modifies application field values.
@MainActor final class ApplicationViewport: ObservableObject {
    @Published private(set) var offset = 0.0
    @Published private(set) var maximum = 0.0
    @Published private(set) var visibleFraction = 1.0
    @Published private(set) var zoom = 1.0
    private weak var webView: WKWebView?
    private var monitor: Task<Void, Never>?
    private var adjusting = false
    private let supportsAutomaticFit: Bool
    private var automaticFit: Bool
    private var measuredWidth: CGFloat = 0
    private var measuredURL: URL?

    init(automaticallyFitsWidth: Bool = false) {
        supportsAutomaticFit = automaticallyFitsWidth
        automaticFit = automaticallyFitsWidth
    }
    static let world = WKContentWorld.world(name: "CareerAI.ApplicationViewport")
    static let script = #"""
    const root=document.scrollingElement||document.documentElement,body=document.body;
    if(!root||!body)return {offset:0,maximum:0,fraction:1,width:0,content:0};
    const modal=[...document.querySelectorAll('dialog[open],[aria-modal="true"],.el-overlay,.ant-modal-wrap')].some(n=>n.getClientRects().length&&getComputedStyle(n).visibility!=='hidden');
    const width=document.documentElement.clientWidth;
    const content=Math.max(root.scrollWidth,body.scrollWidth);
    if(content>width+2&&!modal){
      // Fixed-width recruitment sites sometimes hide horizontal document overflow.
      // Keep their vertical scrolling and all form layout/values intact.
      if(['hidden','clip'].includes(getComputedStyle(document.documentElement).overflowX))document.documentElement.style.setProperty('overflow-x','auto','important');
      if(['hidden','clip'].includes(getComputedStyle(body).overflowX))body.style.setProperty('overflow-x','visible','important');
    }
    // Some sites clip a full-page wrapper, so document.scrollWidth looks normal.
    // Only consider broad form/layout regions, never input editors or carousels.
    const candidates=[root,...document.querySelectorAll('main,div,section')].filter((el,i,all)=>all.indexOf(el)===i&&el.clientWidth>=width*0.75&&el.scrollWidth>el.clientWidth+2&&el.getClientRects().length&&!el.closest('[role="dialog"],[role="listbox"],.swiper,.slick-slider,.carousel')&&(el===root||el.clientHeight>=Math.min(innerHeight*0.4,300)||el.querySelector('form,table')));
    const wide=candidates.filter(el=>el===root||['hidden','clip','auto','scroll'].includes(getComputedStyle(el).overflowX));
    wide.sort((a,b)=>(b.scrollWidth-b.clientWidth)-(a.scrollWidth-a.clientWidth)||b.clientHeight-a.clientHeight);
    const target=wide[0]||root;
    if(!modal&&target!==root&&['hidden','clip'].includes(getComputedStyle(target).overflowX))target.style.setProperty('overflow-x','auto','important');
    const maximum=Math.max(0,target.scrollWidth-target.clientWidth);
    if(typeof requested==='number'&&!modal)target.scrollTo({left:Math.max(0,Math.min(maximum,requested)),top:target.scrollTop,behavior:'instant'});
    return {offset:target.scrollLeft,maximum:modal?0:maximum,fraction:Math.min(1,target.clientWidth/Math.max(target.clientWidth,target.scrollWidth)),width,content:Math.max(root.scrollWidth,width+maximum)};
    """#

    func start(_ webView: WKWebView) {
        stop(); self.webView = webView
        zoom = webView.pageZoom
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .milliseconds(700)) } catch { break }
            }
        }
    }
    func stop() { monitor?.cancel(); monitor = nil }
    private func snapshot(requested: Double? = nil) async -> [String: Double]? {
        guard let webView else { return nil }
        let result = try? await webView.callAsyncJavaScript(Self.script, arguments: ["requested": requested.map { $0 as Any } ?? NSNull()], in: nil, contentWorld: Self.world)
        return result as? [String: Double]
    }
    func refresh() async {
        guard !adjusting, let webView else { return }
        let width = webView.bounds.width
        let url = webView.url
        if automaticFit, width > 0 {
            // A new document can have a different layout. A wider pane can
            // return towards 100% without first zooming a fixed-width site out.
            if measuredWidth == 0 || url != measuredURL {
                applyZoom(1)
            } else if width > measuredWidth, zoom < 1 {
                applyZoom(min(1, zoom * width / measuredWidth))
            }
            measuredWidth = width
            measuredURL = url
        }
        let measuredZoom = zoom
        guard let result = await snapshot(), !Task.isCancelled, !adjusting,
              webView.bounds.width == width, webView.url == url, measuredZoom == zoom else { return }
        if automaticFit, width > 0, (result["maximum"] ?? 0) > 2,
           let visible = result["width"], let content = result["content"], content > visible, visible > 0 {
            applyZoom(floor(zoom * visible / content * 100) / 100)
        }
        update(result)
    }
    private func update(_ result: [String: Double]) {
        let nextMaximum = result["maximum"] ?? 0, nextOffset = result["offset"] ?? 0, nextFraction = result["fraction"] ?? 1
        if abs(maximum-nextMaximum)>0.5 { maximum = nextMaximum }
        if abs(offset-nextOffset)>0.5 { offset = nextOffset }
        if abs(visibleFraction-nextFraction)>0.001 { visibleFraction = nextFraction }
        if ProcessInfo.processInfo.arguments.contains("--viewport-diagnostics") {
            try? JSONSerialization.data(withJSONObject: result.merging(["zoom": zoom]) { _, b in b }).write(to: URL(fileURLWithPath: "/tmp/careerai-viewport/metrics.json"), options: .atomic)
        }
    }
    func scroll(to position: Double) {
        Task { [weak self] in
            guard let self, let result = await self.snapshot(requested: position) else { return }
            self.update(result)
        }
    }
    func setZoom(_ value: Double) {
        automaticFit = false
        applyZoom(value)
        Task { await refresh() }
    }
    private func applyZoom(_ value: Double) {
        let next = min(1.5, max(0.5, (value * 100).rounded() / 100))
        guard let webView, webView.pageZoom != next else { return }
        webView.pageZoom = next
        zoom = next
    }
    func fit() {
        if supportsAutomaticFit {
            automaticFit = true
            measuredWidth = 0
            Task { await refresh() }
            return
        }
        guard !adjusting else { return }
        adjusting = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.adjusting = false }
            // Measure at 100%, including fixed-width elements positioned offscreen.
            self.webView?.pageZoom = 1; self.zoom = 1
            try? await Task.sleep(for: .milliseconds(120))
            for _ in 0..<4 {
                guard let result = await self.snapshot(), let width = result["width"], let content = result["content"], content > 0 else { return }
                if (result["maximum"] ?? 0) < 2 { self.update(result); break }
                let next = max(0.5,min(1,floor(self.zoom*width/content*100)/100))
                if next >= self.zoom { break }
                self.setZoom(next)
                try? await Task.sleep(for: .milliseconds(150))
            }
            if let fitted = await self.snapshot(requested: 0) { self.update(fitted) }
        }
    }
}

struct ApplicationViewportTools: View {
    @ObservedObject var viewport: ApplicationViewport
    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Button { viewport.setZoom(viewport.zoom-0.1) } label: { Image(systemName: "minus") }.help("缩小网页").accessibilityLabel("缩小网页")
                Button("\(Int((viewport.zoom*100).rounded()))%") { viewport.setZoom(1) }.monospacedDigit().frame(width: 48).help("恢复网页原始大小")
                Button { viewport.setZoom(viewport.zoom+0.1) } label: { Image(systemName: "plus") }.help("放大网页").accessibilityLabel("放大网页")
            }.buttonStyle(.browserIcon).background(Color(white: 0.965), in: RoundedRectangle(cornerRadius: 9))
            Button("适应宽度") { viewport.fit() }.buttonStyle(.browserToolbar).help("将网页完整缩放到当前窗口宽度")
        }.fixedSize(horizontal: true, vertical: false)
    }
}

struct ApplicationHorizontalScroll: View {
    @ObservedObject var viewport: ApplicationViewport
    var body: some View {
        if viewport.maximum > 1 {
            HStack(spacing: 0) {
                Button { viewport.scroll(to: viewport.offset-160) } label: { Image(systemName: "chevron.left").font(.system(size: 9)) }
                    .buttonStyle(.borderless).frame(width: 22).accessibilityLabel("向左滚动网页")
                ApplicationScroller(offset: viewport.offset, maximum: viewport.maximum, fraction: viewport.visibleFraction) { viewport.scroll(to: $0) }
                Button { viewport.scroll(to: viewport.offset+160) } label: { Image(systemName: "chevron.right").font(.system(size: 9)) }
                    .buttonStyle(.borderless).frame(width: 22).accessibilityLabel("向右滚动网页")
            }.frame(height: 15).background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
private struct ApplicationScroller: NSViewRepresentable {
    var offset: Double; var maximum: Double; var fraction: Double; var move: (Double) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScroller {
        let scroller = NSScroller(frame: NSRect(x: 0,y: 0,width: 400,height: 15))
        scroller.scrollerStyle = .legacy; scroller.controlSize = .small
        scroller.target = context.coordinator; scroller.action = #selector(Coordinator.changed(_:))
        scroller.setAccessibilityLabel("网页横向滚动")
        return scroller
    }
    func updateNSView(_ view: NSScroller, context: Context) {
        context.coordinator.parent = self
        view.isEnabled = maximum > 1; view.knobProportion = fraction
        view.doubleValue = maximum > 0 ? offset/maximum : 0
    }
    @MainActor final class Coordinator: NSObject {
        var parent: ApplicationScroller
        init(_ parent: ApplicationScroller) { self.parent = parent }
        @objc func changed(_ sender: NSScroller) {
            let page = parent.maximum*parent.fraction/max(0.01,1-parent.fraction)*0.8
            let delta: Double
            switch sender.hitPart {
            case .decrementLine: delta = -60
            case .incrementLine: delta = 60
            case .decrementPage: delta = -page
            case .incrementPage: delta = page
            default: parent.move(sender.doubleValue*parent.maximum); return
            }
            parent.move(min(parent.maximum,max(0,parent.offset+delta)))
        }
    }
}
