import AppKit
import WebKit

@main struct ApplicationViewportTests {
 @MainActor static func main() async throws {
  setbuf(stdout,nil)
  let app=NSApplication.shared; app.setActivationPolicy(.prohibited)
  let web=WKWebView(frame:NSRect(x:0,y:0,width:1000,height:700))
  let window=NSWindow(contentRect:NSRect(x:-20000,y:-20000,width:1000,height:700),styleMask:[.borderless],backing:.buffered,defer:false);window.contentView=web;window.orderBack(nil)
  let loader=Loader();web.navigationDelegate=loader
  await loader.load("""
  <style>html,body{margin:0;overflow-x:hidden}main{width:1400px;height:1300px}#right{position:absolute;left:1300px;top:220px;width:80px}footer{position:fixed;bottom:0;width:1400px;text-align:right}</style>
  <main><input id=retained value='synthetic unchanged'><button id=right onclick='window.clicked=true'>右侧操作</button></main><footer>固定宽度页脚</footer>
  """,in:web)
  let viewport=ApplicationViewport();viewport.start(web);await viewport.refresh()
  defer{viewport.stop();window.orderOut(nil)}
  precondition(viewport.maximum>=399 && viewport.maximum<=401)
  _ = try await web.evaluateJavaScript("window.scrollTo(0,170)")
  viewport.scroll(to:viewport.maximum);try await Task.sleep(for:.milliseconds(200))
  let reached=try await web.evaluateJavaScript("document.getElementById('right').getBoundingClientRect().right<=innerWidth && scrollX>390 && scrollY===170") as? Bool
  precondition(reached==true)
  print("PASS fixed-width page with hidden horizontal overflow: right controls reachable; vertical position and form values retained")
  viewport.fit();try await Task.sleep(for:.milliseconds(500));await viewport.refresh()
  precondition(viewport.zoom<1 && viewport.maximum<2)
  let unchanged=try await web.evaluateJavaScript("document.getElementById('retained').value==='synthetic unchanged' && window.clicked!==true") as? Bool;precondition(unchanged==true)
  print("PASS fit-to-width: full page visible without changing fields or pressing page actions")
  viewport.setZoom(1);try await Task.sleep(for:.milliseconds(150));await viewport.refresh();precondition(viewport.maximum>390)
  window.setContentSize(NSSize(width:800,height:700));try await Task.sleep(for:.milliseconds(150));await viewport.refresh();precondition(viewport.maximum>590)
  print("PASS restoring 100% and resizing recomputes the horizontal range")
  _ = try await web.evaluateJavaScript("document.documentElement.style.overflowX='hidden';document.body.style.overflowX='hidden';document.body.insertAdjacentHTML('beforeend','<div role=dialog aria-modal=true>对话框</div>')")
  await viewport.refresh();precondition(viewport.maximum==0)
  let locked=try await web.evaluateJavaScript("getComputedStyle(document.documentElement).overflowX==='hidden'") as? Bool;precondition(locked==true)
  print("PASS website modal scroll lock respected")
  _ = try await web.evaluateJavaScript("document.body.innerHTML='<div style=\"width:100%;overflow:hidden\"><main style=\"width:1400px;height:900px\"><button id=nestedRight style=\"margin-left:1300px\">右侧</button></main></div>'")
  await viewport.refresh();precondition(viewport.maximum>590)
  viewport.scroll(to:viewport.maximum);try await Task.sleep(for:.milliseconds(200))
  let nested=try await web.evaluateJavaScript("document.getElementById('nestedRight').getBoundingClientRect().right<=innerWidth") as? Bool;precondition(nested==true)
  print("PASS document-width-normal nested clipping: independent horizontal control reaches the right edge")

  viewport.stop()
  let automatic = ApplicationViewport(automaticallyFitsWidth: true)
  automatic.start(web)
  defer { automatic.stop() }
  func settle() async throws {
      for _ in 0..<4 {
          await automatic.refresh()
          try await Task.sleep(for: .milliseconds(100))
      }
  }
  try await settle()
  precondition(automatic.zoom < 0.6 && automatic.maximum < 2)
  window.setContentSize(NSSize(width: 1200, height: 700))
  try await settle()
  precondition(automatic.zoom > 0.8 && automatic.maximum < 2)
  automatic.setZoom(1)
  window.setContentSize(NSSize(width: 800, height: 700))
  try await settle()
  precondition(automatic.zoom == 1 && automatic.maximum > 590)
  automatic.fit()
  try await settle()
  precondition(automatic.zoom < 0.6 && automatic.maximum < 2)
  _ = try await web.evaluateJavaScript("document.body.innerHTML='<main style=\"width:100%\">Fluid layout</main>';history.pushState({},'', '/another-post')")
  try await settle()
  precondition(automatic.zoom == 1 && automatic.maximum < 2)
  print("PASS automatic fit follows pane width and page changes, preserves manual zoom, and resumes on request")
 }
 @MainActor final class Loader:NSObject,WKNavigationDelegate{
  var continuation:CheckedContinuation<Void,Never>?
  func load(_ html:String,in web:WKWebView)async{await withCheckedContinuation{continuation=$0;web.loadHTMLString(html,baseURL:URL(string:"https://viewport-fixture.invalid"))}}
  func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){continuation?.resume();continuation=nil}
 }
}
