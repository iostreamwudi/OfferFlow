import Foundation
import AppKit
import WebKit
@main struct ApplicationMokaTests {
 @MainActor static func main() async throws {
  setbuf(stdout,nil)
  let root=URL(fileURLWithPath:CommandLine.arguments[1]);let script=try String(contentsOf:root.appendingPathComponent("Sources/ApplicationAutofill.js"),encoding:.utf8)
  NSApplication.shared.setActivationPolicy(.prohibited)
  let web=WKWebView(frame:NSRect(x:0,y:0,width:1000,height:900));let window=NSWindow(contentRect:NSRect(x:-20000,y:-20000,width:1000,height:900),styleMask:[.borderless],backing:.buffered,defer:false);window.contentView=web;window.orderBack(nil)
  defer{window.orderOut(nil)}
  let loader=Loader();web.navigationDelegate=loader
  await loader.load(try String(contentsOf:root.appendingPathComponent("Tests/Fixtures/application-moka.html"),encoding:.utf8),in:web)
  let world=WKContentWorld.world(name:"Moka.Test")
  let pack = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Sources/ApplicationSiteRules.json"))) as! [String:Any]
  let adapter = (pack["sites"] as! [[String:Any]]).first { $0["id"] as? String == "moka" }!
  func call(_ action:String,_ extra:[String:Any]=[:])async throws->[String:Any]{var args:[String:Any]=["action":action,"token":"","assignments":[],"desiredSections":[:],"identities":[:],"siteRules":adapter];extra.forEach{args[$0.key]=$0.value};return try await web.callAsyncJavaScript(script,arguments:args,in:nil,contentWorld:world) as? [String:Any] ?? [:]}
  var profile=ApplicationProfile();profile.values=["basic.name":"档案里的姓名","basic.documentType":"身份证","basic.documentNumber":"TEST-NUMBER","basic.highestDegree":"硕士","basic.graduationDate":"2027-06-01"]
  profile.entries["education"]=[.init(values:["school":"档案大学甲","startDate":"2024-09","endDate":"2027-06"]),.init(values:["school":"档案大学乙"])]
  profile.entries["work"]=[.init(values:["company":"档案公司","responsibilities":"档案职责"])]
  let scan=try JSONDecoder().decode(ApplicationFormScan.self,from:JSONSerialization.data(withJSONObject:try await call("scan")))
  precondition(scan.fields.filter{$0.label=="证件类型"}.count==1 && scan.fields.filter{$0.label=="证件号码"}.count==1)
  precondition(scan.fields.filter{$0.section=="education" && $0.label=="开始时间"}.count==2)
  precondition(scan.fields.filter{$0.section=="education" && $0.label=="结束时间"}.count==2)
  precondition(scan.fields.filter{$0.section=="highSchool"}.count==1)
  let assignments=ApplicationAutofillPlanner.plan(fields:scan.fields,facts:profile.facts)
  let encoded=try JSONSerialization.jsonObject(with:JSONEncoder().encode(assignments))
  let result=try await call("fill",["token":scan.token,"assignments":encoded])
  for row in result["results"] as? [[String:Any]] ?? [] where row["status"] as? String == "option-missing" {
   let assignment=assignments.first{$0.fieldID==row["id"] as? String}!
   let encodedOne=try JSONSerialization.jsonObject(with:JSONEncoder().encode([assignment]))
   for step in ["open","choose"] {
    let action=try await call("repair",["token":scan.token,"assignments":encodedOne,"desiredSections":["step":step]])
    if let point=action["click"] as? [String:Double],let x=point["x"],let y=point["y"] {_ = try await web.evaluateJavaScript("document.elementFromPoint(\(x),\(y)).click()")}
   }
   let audit=try await call("audit",["token":scan.token,"assignments":encodedOne])
   precondition((audit["results"] as? [[String:Any]])?.first?["status"] as? String == "filled",assignment.fieldID+" failed")
  }
  let ok=try await web.evaluateJavaScript("document.getElementById('name').value==='档案里的姓名' && idnumber.value==='TEST-NUMBER' && school0.value==='档案大学甲' && school1.value==='档案大学乙' && company.value==='档案公司' && work.value==='档案职责' && highschool.value==='已有高中' && unknown.value==='网站原有备注' && committed.gradM==='06月' && committed.degree==='硕士'") as? Bool
  precondition(ok==true)
  print("PASS Moka structure: applicant vs education/high school/work; compound ID type/number; custom dropdown commits; split start/end year-month; repeated records; known profile overwrites existing fields, unknown content untouched")
 }
 @MainActor final class Loader:NSObject,WKNavigationDelegate {var continuation:CheckedContinuation<Void,Never>?;func load(_ html:String,in web:WKWebView)async{await withCheckedContinuation{continuation=$0;web.loadHTMLString(html,baseURL:URL(string:"https://example.invalid"))}};func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){continuation?.resume();continuation=nil}}
}
