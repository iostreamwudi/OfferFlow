import Foundation
import AppKit
import WebKit
@main struct ApplicationIdentityDOMTests {
 @MainActor static func main() async throws {
  setbuf(stdout,nil)
  let root=URL(fileURLWithPath:CommandLine.arguments[1]);let script=try String(contentsOf:root.appendingPathComponent("Sources/ApplicationAutofill.js"),encoding:.utf8)
  let html=try String(contentsOf:root.appendingPathComponent("Tests/Fixtures/application-moka-identity.html"),encoding:.utf8)
  let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
  let web=WKWebView(frame:NSRect(x:0,y:0,width:1000,height:900));let window=NSWindow(contentRect:NSRect(x:-20000,y:-20000,width:1000,height:900),styleMask:[.borderless],backing:.buffered,defer:false);window.contentView=web;window.orderBack(nil)
  let loader=Loader();web.navigationDelegate=loader;await loader.load(html,in:web)
  let world=WKContentWorld.world(name:"CareerAI.IdentityDOM.Test")
  func call(_ action:String,_ extra:[String:Any]=[:])async throws->[String:Any]{var args:[String:Any]=["action":action,"token":"","assignments":[],"desiredSections":[:],"identities":[:]];extra.forEach{args[$0.key]=$0.value};return try await web.callAsyncJavaScript(script,arguments:args,in:nil,contentWorld:world) as? [String:Any] ?? [:]}
  let scan=try await call("scan");let fields=scan["fields"] as! [[String:Any]]
  print("Identity metadata only:",fields.map{["label":$0["label"]!,"section":$0["section"]!,"entryIndex":$0["entryIndex"]!,"type":$0["type"]!]})
  if CommandLine.arguments.contains("--reproduce") {window.orderOut(nil);return}
  let own=fields.filter{$0["section"] as? String == "basic"}
  guard let kind=own.first(where:{$0["label"] as? String=="证件类型"}),let number=own.first(where:{$0["label"] as? String=="证件号码"})else{fatalError("Own document controls not separated or scoped")}
  precondition(kind["entryIndex"] as? Int == 0 && number["entryIndex"] as? Int == 0)
  let family=fields.filter{$0["section"] as? String=="family"};precondition(family.contains{$0["label"] as? String=="证件号码"})
  precondition((scan["manualFields"] as? [String])?.contains(where:{$0.contains("本人知悉")}) == true)
  precondition(!fields.contains{($0["label"] as? String ?? "").contains("本人知悉")})
  let result=try await call("fill",["token":scan["token"]!,"assignments":[["fieldID":kind["id"]!,"value":"身份证"],["fieldID":number["id"]!,"value":"TEST-DOCUMENT-NOT-REAL"]]])
  let outcomes=result["results"] as! [[String:Any]];precondition(outcomes.count==2&&outcomes.allSatisfy{$0["status"] as? String=="filled"})
  let valid=try await web.evaluateJavaScript("document.querySelector('#document-kind').value==='id' && document.querySelector('#document-value').value==='TEST-DOCUMENT-NOT-REAL' && document.querySelector('#family-document').value==='' && !document.querySelector('#acknowledge').checked && submissions===0") as! Bool
  precondition(valid)
  print("PASS Moka-shaped shared label split, basic section despite highest-degree field heading, family isolated, acknowledgement manual, zero submit")
  // The actual site's section caption may be a plain text DIV. A preceding
  // highest-degree field has a title-like class but must not own identity fields.
  let plainCaption=html.replacingOccurrences(of:"<h2>基本信息</h2>",with:"<div class=module-caption>个人信息</div>")
      .replacingOccurrences(of:"<h3 class=\"field-title\">最高学历</h3>",with:"<div class=field-title>最高学历</div>")
  await loader.load(plainCaption,in:web)
  let plain=try await call("scan");let plainFields=plain["fields"] as! [[String:Any]]
  precondition(plainFields.filter{$0["section"] as? String=="basic"&&$0["label"] as? String=="证件号码"}.count==1)
  precondition(plainFields.filter{$0["section"] as? String=="family"&&$0["label"] as? String=="证件号码"}.count==1)
  // Compound captions also appear as “document type”, with number-specific
  // placeholder text on the right. The text input must still be the number.
  await loader.load(plainCaption.replacingOccurrences(of:"<label>证件号码</label>",with:"<label>证件类型</label>"),in:web)
  let typeCaption=try await call("scan");let typeFields=typeCaption["fields"] as! [[String:Any]]
  precondition(typeFields.contains{$0["section"] as? String=="basic"&&$0["label"] as? String=="证件号码"&&$0["type"] as? String=="text"})
  print("PASS plain-text personal section caption, preceding title-class degree caption and inverse compound caption")
  let records=try String(contentsOf:root.appendingPathComponent("Tests/Fixtures/application-zhaopin-records.html"),encoding:.utf8)
  await loader.load(records,in:web,base:URL(string:"https://jsdg.zhaopin.com/zk/#/pages/application-form/index")!)
  let recordScan=try await call("scan");let recordFields=recordScan["fields"] as! [[String:Any]]
  precondition(recordFields.filter{$0["section"] as? String=="education"}.count==4)
  precondition(recordFields.filter{$0["label"] as? String=="学校名称"}.map{$0["entryIndex"] as! Int}==[0,1])
  precondition(recordFields.filter{$0["label"] as? String=="姓名"}.map{$0["entryIndex"] as! Int}==[0,1])
  precondition(!recordFields.contains{$0["label"] as? String=="其他"})
  let declarations=recordFields.filter{($0["label"] as? String ?? "").hasPrefix("是否")}
  precondition(declarations.count==1 && declarations[0]["section"] as? String=="declaration")
  let edits=recordFields.filter{["education","family"].contains($0["section"] as? String ?? "")}.map{f -> [String:Any] in
    let index=f["entryIndex"] as! Int;return ["fieldID":f["id"]!,"value":f["label"] as? String=="入学时间" ? "2024-09" : "测试记录\(index)"]
  }
  let recordResult=try await call("fill",["token":recordScan["token"]!,"assignments":edits])
  precondition((recordResult["results"] as! [[String:Any]]).allSatisfy{$0["status"] as? String=="filled"})
  let untouched=try await web.evaluateJavaScript("!document.querySelector('input[name=relatives]:checked') && submissions===0") as! Bool;precondition(untouched)
  print("PASS repeated labels, two education/family records, no mid-fill identity conflict, auxiliary controls excluded, declarations isolated")
  window.orderOut(nil)
 }
 @MainActor final class Loader:NSObject,WKNavigationDelegate {
  var continuation:CheckedContinuation<Void,Never>?
  func load(_ html:String,in view:WKWebView,base:URL=URL(string:"https://fixture.invalid")!)async{await withCheckedContinuation{continuation=$0;view.loadHTMLString(html,baseURL:base)}}
  func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){continuation?.resume();continuation=nil}
 }
}
