// Route and native-bridge smoke checks; native UI is verified separately.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync(require('path').join(__dirname,'../Resources/Workspace/app.js'),'utf8');
const listeners={},windowListeners={},nodes={},messages=[],writes=[];
function node(id){const events={};return nodes[id]={id,innerHTML:'',textContent:'',dataset:{},value:'',open:false,className:'',classList:{add(){},remove(){},contains(){return false}},addEventListener(t,f){(events[t]??=[]).push(f)},showModal(){this.open=true},close(){this.open=false;(events.close||[]).forEach(f=>f())},querySelectorAll(){return[]},focus(){doc.activeElement=this},setAttribute(){}}}
['sidebar','topbar','main','modal','toast','command-query','command-results'].forEach(node);
const rootAttributes={};
const doc={documentElement:{setAttribute(k,v){rootAttributes[k]=v}},activeElement:null,getElementById:id=>nodes[id]||null,querySelector:s=>s.startsWith('#')?nodes[s.slice(1)]||null:null,addEventListener(t,f){(listeners[t]??=[]).push(f)}};
const context={document:doc,window:{addEventListener(t,f){(windowListeners[t]??=[]).push(f)},scrollTo(){}},location:{hash:'#community'},history:{replaceState(_state,_title,url){context.location.hash=url}},localStorage:{getItem(){return JSON.stringify({mode:'community',market:{shop:{name:'OLD COMMUNITY MERCHANT'}}})},setItem(k,v){writes.push([k,JSON.parse(v)])}},setTimeout(){},clearTimeout(){},navigator:{},console};
vm.createContext(context);vm.runInContext(source,context);
const run=s=>vm.runInContext(s,context),forbidden=/服务社区|商家中心|服务发现|我的咨询|经验内容|导师|OLD COMMUNITY MERCHANT/;
assert.equal(context.location.hash,'#home');assert.equal(run('state.mode'),'personal');assert.equal(writes[0][1].mode,'personal');
const routes=['home','opportunities','opportunity/cc/overview','opportunity/cc/interview','opportunity/cc/application','opportunity/cc/progress','profile','profile/zhou','applications','saved','liveJobs'];
for(const route of routes){context.location.hash='#'+route;run('render()');assert(nodes.main.innerHTML.length>0,route);for(const id of ['sidebar','topbar','main'])assert(!forbidden.test(nodes[id].innerHTML),route+' '+id)}
const oldRoutes=['community','service/resume','provider/chen','content/evidence','consultations','merchant','merchant/services','merchant/content','merchant/leads','mentor','students','templates','review','student-profile/zhou','opportunity/zhou/application'];
for(const route of oldRoutes){context.location.hash='#'+route;run('render()');assert.equal(context.location.hash,'#home',route);assert(!forbidden.test(nodes.main.innerHTML),route);assert.equal(run('state.mode'),'personal')}
assert(nodes.sidebar.innerHTML.includes('投递管理'));assert(!nodes.sidebar.innerHTML.includes('<select'));assert(!nodes.sidebar.innerHTML.includes('product-segments'));assert(!nodes.sidebar.innerHTML.includes('澄川智能'));assert(!nodes.sidebar.innerHTML.includes('林知夏'));assert(!nodes.sidebar.innerHTML.includes('免费'));
context.window.webkit={messageHandlers:{careerAI:{postMessage:m=>messages.push(m)}}};
context.location.hash='#liveJobs';run('render()');assert.equal(messages.at(-1).action,'openLiveJobs');run('workspaceSettings()');assert.equal(messages.at(-1).action,'suspendNativeSurface');run('closeModal()');assert.equal(messages.at(-1).action,'openLiveJobs');assert(run('navigationCommands()').some(c=>c.native==='openAccount'));
context.location.hash='#applications';run('render()');assert.equal(messages.at(-1).action,'openApplications');
run('workspaceSettings()');assert.equal(messages.at(-1).action,'suspendNativeSurface');assert(!forbidden.test(nodes.modal.innerHTML));assert(nodes.modal.open);run('render()');assert.equal(messages.at(-1).action,'suspendNativeSurface');run('closeModal()');assert.equal(messages.at(-1).action,'openApplications');
run('pricingModal()');assert.equal(messages.at(-1).action,'suspendNativeSurface');assert(nodes.modal.innerHTML.includes('订阅与支付尚未开放'));assert(!forbidden.test(nodes.modal.innerHTML));assert(!nodes.modal.innerHTML.includes('¥'));run('closeModal()');assert.equal(messages.at(-1).action,'openApplications');
context.location.hash='#saved';run('render()');assert.equal(messages.at(-1).action,'openSavedJobs');run('quickSearch()');assert.equal(messages.at(-1).action,'suspendNativeSurface');assert(nodes.modal.innerHTML.includes('已保存岗位'));assert(!forbidden.test(nodes.modal.innerHTML));assert(run("commandResults('boss')").includes('岗位发现'));assert(run("commandResults('社区')").includes('没有找到'));run('closeModal()');assert.equal(messages.at(-1).action,'openSavedJobs');
context.location.hash='#profile/zhou';run('render()');run('downloadMaterial()');assert.equal(messages.at(-1).action,'exportMaterial');assert(!forbidden.test(messages.at(-1).text));assert(!/周予安|企业指标目录/.test(messages.at(-1).text));assert(messages.at(-1).text.includes('示例资料导出'));
context.location.hash='#home';run('render()');assert.equal(messages.at(-1).action,'openHome');
windowListeners['careerAI:command'].forEach(f=>f({detail:{action:'settings'}}));assert(nodes.modal.innerHTML.includes('账户与设置'));run('closeModal()');windowListeners['careerAI:command'].forEach(f=>f({detail:{action:'quickSearch'}}));assert(nodes.modal.innerHTML.includes('快速查找'));
let prevented=false;listeners.keydown.forEach(f=>f({key:'Escape',target:nodes['command-query'],preventDefault(){prevented=true}}));assert(prevented);assert(!nodes.modal.open);assert.equal(messages.at(-1).action,'openHome');
context.location.hash='#profile';run('render()');assert.equal(messages.at(-1).action,'openApplicationProfile');assert(!nodes.main.innerHTML.includes('林知夏'));
assert(nodes.sidebar.innerHTML.includes('toggle-sidebar'));assert(nodes.sidebar.innerHTML.includes('title="实时岗位库"'));
run('toggleSidebar()');assert.equal(rootAttributes['data-sidebar-collapsed'],'true');assert.equal(messages.at(-1).action,'collapseSidebar');assert(nodes.sidebar.innerHTML.includes('展开侧边栏'));assert.equal(writes.at(-1)[0],'career-ai-sidebar-collapsed');
run('toggleSidebar()');assert.equal(rootAttributes['data-sidebar-collapsed'],'false');assert.equal(messages.at(-1).action,'expandSidebar');assert(nodes.sidebar.innerHTML.includes('收起侧边栏'));
windowListeners['careerAI:command'].forEach(f=>f({detail:{action:'toggleSidebar'}}));assert.equal(rootAttributes['data-sidebar-collapsed'],'true');run('toggleSidebar()');
console.log(`PASS: ${routes.length} personal routes; ${oldRoutes.length} legacy redirects; stored community-mode migration; native modal lifecycle; personal-only pricing, commands and export.`);

context.location.hash='#opportunities';run('render()');assert.equal(messages.at(-1).action,'openInterviews');run('workspaceSettings()');assert.equal(messages.at(-1).action,'suspendNativeSurface');run('closeModal()');assert.equal(messages.at(-1).action,'openInterviews');

for (const [route, action] of Object.entries({boss:'openBoss',coach:'openCoach',calendar:'openCalendar',mail:'openMail'})) {
  context.location.hash='#'+route; run('render()'); assert.equal(context.location.hash,'#'+route); assert.equal(messages.at(-1).action, action);
}
assert(run('navigationCommands()').some(c=>c.route==='boss'));
console.log('PASS all tab routes and BOSS native bridge');

for (const route of ['resumes','events','matching','queue','knowledge','tasks','offers']) { context.location.hash='#'+route; run('render()'); assert.equal(context.location.hash,'#home'); }
console.log('PASS retired modules stay hidden');

const historyPanel=node('chat-history');
const first='10259f0c-ca7d-4083-b49a-5798f17c6a43',second='7854f045-aab3-4a1c-af01-5c0d7ec4c43c';
context.location.hash='#applications';
context.window.offerFlowSidebarUpdate({chats:[{id:first,title:'岗位分析'},{id:second,title:'面试准备'}],selected:first,replying:[first]});
assert(!historyPanel.innerHTML.includes('disabled'));
assert(historyPanel.innerHTML.includes('aria-label="岗位分析，正在回答"'));
assert(!historyPanel.innerHTML.includes('aria-current="page"'));
for(const id of [first,second]){
  const button={dataset:{action:'select-chat',id}};
  listeners.click.forEach(f=>f({target:{closest:selector=>selector==='[data-action]'?button:null}}));
  assert.equal(messages.at(-1).action,'selectChat:'+id);
}
context.location.hash='#home';
context.window.offerFlowSidebarUpdate({chats:[{id:first,title:'岗位分析'},{id:second,title:'面试准备'}],selected:second,replying:[]});
assert(historyPanel.innerHTML.includes('aria-label="面试准备" aria-current="page"'));
assert(!historyPanel.innerHTML.includes('正在回答'));
console.log('PASS recent conversations remain reachable from another page during generation');
assert(historyPanel.innerHTML.includes('aria-label="删除对话：面试准备"'));
const removeButton={dataset:{action:'delete-chat',id:second}};
const previous=messages.length;
listeners.click.forEach(f=>f({target:{closest:selector=>selector==='[data-action]'?removeButton:null}}));
assert.deepEqual(messages.slice(previous).map(m=>m.action),['deleteChat:'+second]);

context.window.offerFlowSidebarUpdate({chats:[{id:first,title:'岗位分析'}],selected:first,replying:[],hasMore:true});
assert(historyPanel.innerHTML.includes('显示更早的对话'));
const moreChats={dataset:{action:'more-chats'}};
listeners.click.forEach(f=>f({target:{closest:selector=>selector==='[data-action]'?moreChats:null}}));
assert.equal(messages.at(-1).action,'moreChats');
