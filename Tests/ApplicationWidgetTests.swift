import Foundation
import AppKit
import WebKit
@main struct ApplicationWidgetTests {
 @MainActor static func main() async throws {
  setbuf(stdout,nil)
  let root=URL(fileURLWithPath:CommandLine.arguments[1]);let script=try String(contentsOf:root.appendingPathComponent("Sources/ApplicationAutofill.js"),encoding:.utf8)
  let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
  let web=WKWebView(frame:NSRect(x:0,y:0,width:1000,height:900));let window=NSWindow(contentRect:NSRect(x:-20000,y:-20000,width:1000,height:900),styleMask:[.borderless],backing:.buffered,defer:false);window.contentView=web;window.orderBack(nil)
  defer{window.orderOut(nil)}
  let loader=Loader();web.navigationDelegate=loader;let html=try String(contentsOf:root.appendingPathComponent("Tests/Fixtures/application-special-widgets.html"),encoding:.utf8);await loader.load(html,in:web)
  let world=WKContentWorld.world(name:"Widgets.Test")
  func call(_ action:String,_ extra:[String:Any]=[:])async throws->[String:Any]{var args:[String:Any]=["action":action,"token":"","assignments":[],"desiredSections":[:],"identities":[:]];extra.forEach{args[$0.key]=$0.value};return try await web.callAsyncJavaScript(script,arguments:args,in:nil,contentWorld:world) as? [String:Any] ?? [:]}
  var scan=try await call("scan"),fields=scan["fields"] as! [[String:Any]]
  precondition((scan["uploads"] as! [[String:Any]]).map{$0["label"] as! String} == ["简历上传"])
  precondition(!(scan["manualFields"] as! [String]).contains(where:{$0.contains("照片")||$0.contains("身份证附件")}))
  precondition(fields.contains{$0["label"] as? String == "出生日期" && $0["type"] as? String == "date-widget"})
  let birthday=fields.first{$0["label"] as? String == "出生日期"}!
  let dateAssignments:[[String:Any]]=[["fieldID":birthday["id"]!,"value":"1997-02-17"]]
  _ = try await call("repair",["token":scan["token"]!,"assignments":dateAssignments,"desiredSections":["step":"open","perform":true]])
  var steps=0,done=false
  for _ in 0..<30 {let step=try await call("repair",["token":scan["token"]!,"assignments":dateAssignments,"desiredSections":["step":"calendar","perform":true]]);steps+=1;if step["done"] as? Bool == true {done=true;break};if step["invoked"] as? Bool != true {print("calendar stopped",step);break}}
  precondition(done && steps<15)
  let birthReceived=try await web.evaluateJavaScript("birthReceived") as? String;precondition(birthReceived=="1997-02-17")
  let partial=fields.first{$0["label"] as? String == "到岗时间"}!
  let incomplete=try await call("repair",["token":scan["token"]!,"assignments":[["fieldID":partial["id"]!,"value":"2027-03"]],"desiredSections":["step":"calendar"]])
  precondition(incomplete["missingDetail"] as? Bool == true)
  print("PASS readonly calendar: decades/year/month/day navigation commits application state; incomplete date is left blank")
  let values=["性别":"男","掌握技能":"Python、SQL","期望城市":"上海、杭州","毕业时间":"1997-02-17","籍贯":"湖北省襄阳市襄城区"]
  for _ in 0..<4 {
   scan=try await call("scan");fields=scan["fields"] as! [[String:Any]]
   let assignments=fields.filter{values[$0["label"] as! String] != nil && $0["hasValue"] as? Bool != true}.map{["fieldID":$0["id"]!,"value":values[$0["label"] as! String]!]}
   _ = try await call("fill",["token":scan["token"]!,"assignments":assignments])
  }
  let valid=try await web.evaluateJavaScript("genderReceived==='男' && document.querySelectorAll('[role=checkbox][aria-checked=true]').length===2 && [...document.getElementById('cities').selectedOptions].map(o=>o.value).join(',')==='SH,HZ' && document.getElementById('year').value==='Y97' && document.getElementById('month').value==='M2' && document.getElementById('day').value==='D17' && document.getElementById('province').value==='HB' && document.getElementById('city').value==='XY' && document.getElementById('district').value==='XC' && consents===0 && document.getElementById('partial').value===''") as? Bool
  if valid != true {print("field metadata",fields);print("widget values",try await web.evaluateJavaScript("JSON.stringify(['year','month','day','province','city','district'].map(id=>[id,document.getElementById(id).value]))") as Any)}
  precondition(valid==true)
  print("PASS ARIA radio/checkbox and native multiselect; dependent date/address selects and replaced nodes; original declarations untouched; only resume upload is considered")
  _ = try await web.evaluateJavaScript("document.body.innerHTML='<label>期望城市<input role=combobox id=own aria-controls=owned></label><div role=listbox id=owned><div role=option>杭州</div></div><div role=listbox id=unrelated><div role=option onclick=\"window.wrongOption=true\">上海</div></div>'")
  let scoped=try await call("scan");let scFields=scoped["fields"] as! [[String:Any]]
  let scopedResult=try await call("fill",["token":scoped["token"]!,"assignments":[["fieldID":scFields[0]["id"]!,"value":"上海"]]])
  precondition((scopedResult["results"] as? [[String:Any]])?.first?["status"] as? String == "option-missing")
  let unrelated=try await web.evaluateJavaScript("window.wrongOption===true") as? Bool;precondition(unrelated==false)
  print("PASS controlled popup isolation: a matching option in an unrelated menu is never selected")

  _ = try await web.evaluateJavaScript("document.body.innerHTML='<div class=form-item><label>结束时间</label><div data-date-picker><input id=end readonly></div><label><input id=present type=checkbox onclick=\"window.presentReceived=this.checked\">至今</label></div>'")
  let presentScan=try await call("scan"),presentFields=presentScan["fields"] as! [[String:Any]]
  precondition(presentFields.count==1)
  let presentFill=try await call("fill",["token":presentScan["token"]!,"assignments":[["fieldID":presentFields[0]["id"]!,"value":"至今"]]])
  precondition((presentFill["results"] as! [[String:Any]])[0]["status"] as? String == "filled")
  let presentReceived=try await web.evaluateJavaScript("window.presentReceived===true") as? Bool;precondition(presentReceived==true)
  print("PASS explicit current employment date maps to the site's 至今 checkbox")
  _ = try await web.evaluateJavaScript("document.body.innerHTML='<div id=shadowHost></div>';const root=document.getElementById('shadowHost').attachShadow({mode:'open'});root.innerHTML='<h2>个人信息</h2><span id=caption>电子邮箱</span><input aria-labelledby=caption id=email>'")
  let shadowScan=try await call("scan"),shadowFields=shadowScan["fields"] as! [[String:Any]]
  precondition(shadowFields.count==1 && shadowFields[0]["label"] as? String == "电子邮箱")
  _ = try await call("fill",["token":shadowScan["token"]!,"assignments":[["fieldID":shadowFields[0]["id"]!,"value":"synthetic@example.invalid"]]])
  let shadowValue=try await web.evaluateJavaScript("document.getElementById('shadowHost').shadowRoot.getElementById('email').value") as? String;precondition(shadowValue=="synthetic@example.invalid")
  _ = try await web.evaluateJavaScript("document.body.innerHTML='<iframe id=child style=\"margin-left:90px;margin-top:160px;width:500px;height:300px\"></iframe>';const doc=document.getElementById('child').contentDocument;doc.open();doc.write('<label>性别<input role=combobox id=gender readonly></label>');doc.close()")
  let frameScan=try await call("scan"),frameFields=frameScan["fields"] as! [[String:Any]]
  precondition(frameFields.count==1)
  let pointer=try await call("repair",["token":frameScan["token"]!,"assignments":[["fieldID":frameFields[0]["id"]!,"value":"男"]],"desiredSections":["step":"open"]])
  let coordinates=pointer["click"] as! [String:Double]
  let expected=try await web.evaluateJavaScript("(()=>{const f=document.getElementById('child'),b=f.getBoundingClientRect(),r=f.contentDocument.getElementById('gender').getBoundingClientRect();return {x:b.left+f.clientLeft+r.left+r.width/2,y:b.top+f.clientTop+r.top+r.height/2}})()") as! [String:Double]
  precondition(abs(coordinates["x"]!-expected["x"]!)<1 && abs(coordinates["y"]!-expected["y"]!)<1)
  print("PASS shadow-root labels and same-origin frame pointer translation")

  _ = try await web.evaluateJavaScript("document.body.innerHTML='<header><button aria-expanded=false>个人中心</button></header><section data-section=basic><h2>个人信息</h2><label>姓名<input></label><button type=button>保存</button></section>'")
  let navigation=try await call("journey")
  precondition((navigation["actions"] as! [[String:Any]]).allSatisfy{$0["label"] as? String != "个人中心"})
  precondition((navigation["actions"] as! [[String:Any]]).contains{$0["kind"] as? String == "save"})
  _ = try await web.evaluateJavaScript("document.body.innerHTML='<fieldset><legend>掌握技能</legend><label><input type=checkbox name=skills value=Python>Python</label><label><input type=checkbox name=skills value=SQL>SQL</label></fieldset>';window.choiceClicks=0;document.querySelectorAll('input').forEach(n=>n.onclick=()=>window.choiceClicks++)")
  let nativeScan=try await call("scan"),nativeFields=nativeScan["fields"] as! [[String:Any]]
  precondition(nativeFields.count==1)
  let unmatched=try await call("fill",["token":nativeScan["token"]!,"assignments":[["fieldID":nativeFields[0]["id"]!,"value":"Python、Java"]]])
  precondition((unmatched["results"] as! [[String:Any]])[0]["status"] as? String == "option-missing")
  let unselected=try await web.evaluateJavaScript("document.querySelectorAll('input:checked').length===0") as? Bool;precondition(unselected==true)
  let matched=try await call("fill",["token":nativeScan["token"]!,"assignments":[["fieldID":nativeFields[0]["id"]!,"value":"Python、SQL"]]])
  precondition((matched["results"] as! [[String:Any]])[0]["status"] as? String == "filled")
  let clicks=try await web.evaluateJavaScript("choiceClicks") as? Int;precondition(clicks==2)
  print("PASS global navigation excluded; checkbox groups commit via site click handlers and never partially match")

  _ = try await web.evaluateJavaScript("document.body.innerHTML=`<div class='el-form-item'><label class='el-form-item__label'>入学前户口所在地</label><input id=geo readonly onclick=\"pop.hidden=false\"></div><div id=pop hidden><input placeholder='搜索城市名/区县'><div>北京</div><button onclick=\"cities.hidden=false\"><span>湖北</span></button><div id=cities hidden><button onclick=\"districts.hidden=false\">襄阳</button></div><div id=districts hidden><button onclick=\"geo.value='湖北-襄阳-襄城区';pop.hidden=true\">襄城区</button></div></div>`")
  let geoScan=try await call("scan"),geoFields=geoScan["fields"] as! [[String:Any]]
  precondition(geoFields.count==1 && geoFields[0]["type"] as? String == "combobox")
  let geoAssignments:[[String:Any]]=[["fieldID":geoFields[0]["id"]!,"value":"湖北省襄阳市襄城区"]]
  _ = try await web.evaluateJavaScript("document.getElementById('geo').click()")
  for _ in 0..<4 { _ = try await call("repair",["token":geoScan["token"]!,"assignments":geoAssignments,"desiredSections":["step":"choose","perform":true]]) }
  let geoAudit=try await call("audit",["token":geoScan["token"]!,"assignments":geoAssignments])
  precondition((geoAudit["results"] as! [[String:Any]])[0]["status"] as? String == "filled")
  print("PASS custom read-only location picker: known province/city/district committed; internal search box is not a profile field")



 }
 @MainActor final class Loader:NSObject,WKNavigationDelegate{
  var continuation:CheckedContinuation<Void,Never>?
  func load(_ html:String,in web:WKWebView)async{await withCheckedContinuation{continuation=$0;web.loadHTMLString(html,baseURL:URL(string:"https://widget-fixture.invalid"))}}
  func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){continuation?.resume();continuation=nil}
 }
}
