// A cheap readiness path avoids scanning every field during transition waits.
if(action==='activity') {
 let activity=globalThis.__careerApplicationActivity;
 if(!activity||activity.document!==document) {
  activity={document,revision:0};
  activity.observer=new MutationObserver(()=>activity.revision++);
  activity.observer.observe(document,{subtree:true,childList:true,attributes:true,characterData:true});
  globalThis.__careerApplicationActivity=activity;
 }
 const busy=[...document.querySelectorAll('[aria-busy="true"],.el-loading-mask,.ant-spin-spinning,[data-loading="true"]')].some(el=>{const s=getComputedStyle(el);return !el.hidden&&s.display!=='none'&&s.visibility!=='hidden'&&el.getClientRects().length>0;});
 return {revision:activity.revision,ready:document.readyState!=='loading',busy};
}
// Executed only after the user's Fill action, in an isolated WKContentWorld.
// No site bridge, HTTP requests, credentials, final submissions or consent clicks.
// Explicit intermediate save/next actions are planned separately and revalidated before clicking.
const normalize = value => String(value || '').normalize('NFKC').toLowerCase().replace(/[\s*＊:：()（）\[\]【】_\-]/g, '');
const blocked = /密码|验证码|短信码|动态口令|校验码|图形验证|同意|隐私|协议|条款|授权|承诺|声明|本人[^。\n]{0,30}(?:知悉|知晓|确认|保证)|确认(?:上述|以上|信息真实)|password|captcha|otp|verificationcode|acceptterms|consent|agree|signature/i;
const adapter = typeof siteRules === 'object' && siteRules ? siteRules : {};
const adapterNodes = (root, selectors) => (selectors || []).flatMap(selector => { try { return [...root.querySelectorAll(selector)]; } catch { return []; } });
const sectionRules = [ ['education',/教育|学历|学位|education/i], ['work',/工作经历|实习经历|任职|employment|workexperience|internship/i], ['project',/项目经历|项目经验|project/i], ['campus',/在校|校园|社团|campus/i], ['award',/获奖|奖励|荣誉|award/i], ['language',/语言|外语|language/i], ['computer',/计算机|技能|computer/i], ['certificate',/证书|资格|certificate/i], ['family',/家庭|亲属|family/i], ['paper',/论文|期刊|publication|paper/i], ['patent',/专利|patent/i], ['intention',/求职意向|期望|jobpreference/i], ['portfolio',/作品|portfolio/i], ['competition',/竞赛|competition/i], ['evaluation',/自我评价|兴趣爱好|自我介绍|selfevaluation/i], ['basic',/基本信息|个人信息|联系方式|个人资料|personalinformation|contactinformation/i] ];
const resumeSlot = label => /简历|resume|curriculum.?vitae|(?:^|\b)cv(?:\b|$)/i.test(label)&&!/快速|解析|导入|身份证|照片|成绩单|学历证|学位证|证书|作品集/.test(label);
const visible = el => { const w=el.ownerDocument.defaultView; const s=w.getComputedStyle(el); return !el.hidden && s.display!=='none' && s.visibility!=='hidden' && el.getClientRects().length>0; };
const checked = el => ['radio','checkbox'].includes(el.type)?el.checked:el.getAttribute('aria-checked')==='true';
function readCurrent(el) {
  const sd=el.closest('[class*="sd-Select-container"]');
  if(sd){const text=(sd.querySelector('[class*="sd-Input-display-value"]')?.textContent||'').replace(/[\ue000-\uf8ff]/g,'').trim();if(text&&!/^(请选择|选择|年$|月$|日$)/.test(text))return text;return '';}

  const ant=el.closest('.ant-select');if(ant){const selected=[...ant.querySelectorAll('.ant-select-selection-item')].map(n=>n.getAttribute('title')||n.textContent.trim()).filter(Boolean);if(selected.length)return selected.join('、');}
  if(el.isContentEditable)return el.textContent||'';
  if('value' in el)return el.value||'';
  if(el.getAttribute('role')==='combobox')return el.getAttribute('aria-valuetext')||el.querySelector('.ant-select-selection-item')?.textContent||el.textContent||'';
  return '';
}
function placeholderValue(el,value) {return !String(value||'').trim()||(/^(请选择|选择|select|please select)/i.test(String(value).trim())&&(el.tagName==='SELECT'||el.getAttribute('role')==='combobox'||!!el.closest('.el-select,.ant-select,.arco-select,[class*="sd-Select-container"]')));}
const roots=[]; let inaccessibleFrames=0;
function discover(root) { roots.push(root); for(const el of root.querySelectorAll('*')) { if(el.shadowRoot) discover(el.shadowRoot); if(el.tagName==='IFRAME' && visible(el)) { try { if(el.contentDocument?.documentElement) discover(el.contentDocument); else inaccessibleFrames++; } catch { inaccessibleFrames++; } } } }
discover(document);
function isChoiceControl(el) {
  return el.tagName==='SELECT'||el.getAttribute('role')==='combobox'||!!el.closest('.el-select,.ant-select,.arco-select,[class*="sd-Select-container"]');
}
// Label wrappers in responsive forms can expose the same desktop/mobile caption several times.
function caption(text) {
  const parts=String(text||'').replace(/[*＊]/g,'').split(/[：:\n]/).map(s=>s.trim()).filter(Boolean);
  const unique=[...new Set(parts)];
  let value=unique.join(' ').replace(/^(?:请输入|请填写|请选择|请填入|输入|选择)(?:您的|你的|您|你)?/,'').trim();
  return value.replace(/[(（](?:必填|选填|单位[：: ]*[^()（）]{1,8}|18位(?:数字)?)[)）]/g,'').trim();
}
function isIdentityLabel(label) {return /^(?:本人|申请人|应聘者)?(?:居民身份证|公民身份|证件|身份证件|身份证|身份文件)(?:号|号码|编号|类型|信息|种类|类别)?$/.test(normalize(label));}
function identitySectionHeading(value) {
  const text=normalize(value).replace(/^[0-9]+|[0-9]+$/g,'').replace(/(?:必填|选填|未完成|已完成)$/g,'');
  if(/^(基本信息|个人信息|个人资料|联系方式|应聘者信息|候选人信息|basic|personalinformation)$/.test(text))return 'basic';
  if(/^(家庭情况|家庭信息|家庭成员|家属信息|亲属信息|family)$/.test(text))return 'family';
  if(/^(教育经历|教育背景|education)$/.test(text))return 'education';
  if(/^(工作经历|实习经历|工作与实习|work)$/.test(text))return 'work';
  if(/^(紧急联系人|证明人信息|推荐人信息)$/.test(text))return 'other-person';
  return '';
}
function identityScope(el,label) {
  // A field caption such as "最高学历" is not an education section. Recognize
  // actual containing section markers before falling back to document order.
  if(/家属|家庭|亲属/.test(label))return 'family';
  let parent=el.parentElement;
  for(let depth=0;parent&&depth<8;depth++,parent=parent.parentElement) {
    const explicit=identitySectionHeading(parent.getAttribute('data-section')||'');if(explicit)return explicit;
    if(/(?:family|relative|emergency|reference)[_.\-\[]/i.test(parent.id||''))return /family|relative/i.test(parent.id)?'family':'other-person';
    for(const child of parent.children) {
      if(child.contains(el)||child.matches('input,select,textarea')||child.querySelector('input,select,textarea'))continue;
      const text=child.textContent.trim();if(text.length>32)continue;
      const found=identitySectionHeading(text);if(found&&visible(child))return found;
    }
  }
  return '';
}

const exactSectionNames = new Map(Object.entries({
 '申请信息':'intention','求职意向':'intention','个人信息':'basic','个人基本信息':'basic','基本信息':'basic','个人资料':'basic','联系方式':'basic',
 '教育背景':'education','教育经历':'education','高中经历':'highSchool','高中教育':'highSchool','获奖经历':'award','获奖情况':'award','奖励荣誉':'award',
 '在校职务':'campus','在校经历':'campus','校园经历':'campus','实习经历':'work','工作经历':'work','实习/工作经历':'work','工作与实习':'work',
 '项目经验':'project','项目经历':'project','证书':'certificate','资格证书':'certificate','语言能力':'language','外语能力':'language','专业技能':'computer','计算机技能':'computer',
 '自我描述':'evaluation','自我评价':'evaluation','家庭情况':'family','家庭成员':'family','紧急联系人信息':'emergency','论文期刊':'paper','专利':'patent'
}));
const exactHeadingCache=new WeakMap();
for (const [title, section] of Object.entries(adapter.sectionAliases || {})) exactSectionNames.set(title, section);
function exactHeading(text){return String(text||'').replace(/[*＊\ue000-\uf8ff]/g,'').replace(/(?:必填|选填|未完成|已完成)/g,'').trim().replace(/\s*[（(]?\d+[）)]?$/,'').trim();}
function structuralSection(el) {
 const explicit=el.closest('[data-section]')?.getAttribute('data-section');
 if(explicit&&['basic','intention','education','highSchool','work','campus','award','project','certificate','language','computer','family','emergency','paper','patent','evaluation'].includes(explicit))return explicit;
 const root=el.getRootNode();
 if(!exactHeadingCache.has(root))exactHeadingCache.set(root,[...root.querySelectorAll('h1,h2,h3,h4,h5,h6,legend,div,span')].filter(n=>{
  if(n.textContent.length>45||n.querySelector('input,textarea,select')||!visible(n))return false;
  const title=exactHeading(n.textContent);return exactSectionNames.has(title)&&![...n.children].some(c=>exactHeading(c.textContent)===title);
 }));
 const heading=exactHeadingCache.get(root).findLast(n=>(n.compareDocumentPosition(el)&Node.DOCUMENT_POSITION_FOLLOWING));
 return heading?exactSectionNames.get(exactHeading(heading.textContent)):'';
}
function fieldRow(el) {
 for(const selector of adapter.fieldRows || []) { try { const row=el.closest(selector); if(row)return row; } catch {} }
 const standard=el.closest('.form-item,.form-group,.ant-form-item,.el-form-item,.van-field,[data-field],[class*="apply-field-"]');
 if(standard)return standard;
 for(let parent=el.parentElement,depth=0;parent&&depth<6;depth++,parent=parent.parentElement){
  const labels=[...parent.querySelectorAll('label,legend,[class*="label"],[class*="Label"],[class*="title"],[class*="Title"]')].filter(n=>n!==el&&!n.contains(el)&&!n.querySelector('input,select,textarea')&&n.textContent.trim().length>0&&n.textContent.trim().length<100&&(n.compareDocumentPosition(el)&Node.DOCUMENT_POSITION_FOLLOWING));
  const values=[...new Set(labels.map(n=>caption(n.textContent)))].filter(Boolean);
  if(values.length===1&&!exactSectionNames.has(exactHeading(values[0])))return parent;
  if(values.length>1)break;
 }
 return null;
}
function rowCaption(row){return caption(row?.querySelector('label,legend,.label,.ant-form-item-label,.el-form-item__label,[class*="label"],[class*="Label"],[class*="title"],[class*="Title"]')?.textContent||'');}

function labelFor(el) {
 const raw=rawLabelFor(el);
 // A rule may not turn a password/consent caption into a normal profile field.
 return blocked.test(raw) ? raw : (adapter.fieldAliases?.[raw] || raw);
}
function rawLabelFor(el) {
  const doc=el.ownerDocument;
  const root=el.getRootNode();
  const tableCell=el.closest('.table-item');
  if(tableCell && !['radio','checkbox'].includes(el.type)) {
    const walker=doc.createTreeWalker(tableCell,NodeFilter.SHOW_TEXT);let n,parts=[];
    while(n=walker.nextNode()){if(n.compareDocumentPosition(el)&Node.DOCUMENT_POSITION_FOLLOWING)parts.push(n.textContent);}
    const heading=caption(parts.join('').split(/[：:]/)[0]);
    if(heading && heading.length<60)return heading;
  }
  const labels=[...(el.labels||[])].map(x=>x.innerText.trim()).filter(Boolean);
  const aria=(el.getAttribute('aria-labelledby')||'').split(/\s+/).map(id=>(root.getElementById?.(id)||doc.getElementById(id))?.textContent||'').join(' ');
  let label=el.getAttribute('aria-label')||aria||labels.join(' ')||'';
  if(!label) label=rowCaption(fieldRow(el));
  let result=String(label||el.getAttribute('placeholder')||el.name||el.id||'未命名字段').trim().replace(/^(请输入|请填写|请选择|请填入|输入|选择)(您的|你的|您|你)?/, '').slice(0,160);
  result=caption(result);
  if(el.placeholder==='项目中职责')result='项目中职责';
  if(result==='日期'&&doc.location.hostname==='jsdg.zhaopin.com'&&doc.location.hash.startsWith('#/pages/application-form/'))return '填表日期';
  if(isIdentityLabel(result)) {
    // Moka-like compound rows use one caption for both a document-kind select
    // and a document-number input. They are two different local profile fields.
    if(isChoiceControl(el))return '证件类型';
    const row=el.closest('.form-item,.form-group,.ant-form-item,.el-form-item,.van-field');
    const placeholder=el.getAttribute('placeholder')||'';
    if(/号码|编号|身份证号|居民身份证|^身份证$/.test(result)||/证件.*号|身份证.*号/.test(placeholder)||row?.querySelector('select,[role="combobox"],.el-select,.ant-select,.arco-select,[class*="sd-Select-container"]'))return '证件号码';
  }
  return result;
}
function componentFor(el) {
 const raw=caption(el.getAttribute('placeholder')||el.getAttribute('aria-label')||'');
 const types={年:'year',年份:'year',月:'month',月份:'month',日:'day',日期:'day',省:'province',省份:'province',市:'city',城市:'city',区:'district',区县:'district',县:'district'};
 const component=types[raw];if(!component)return null;
 const row=fieldRow(el);
 let base=rowCaption(row);
 if(!base||base===raw)return null;
 if(['year','month','day'].includes(component)&&!/日期|时间|年月|生日|出生|入学|毕业|到岗/.test(base))return null;
 if(['province','city','district'].includes(component)&&!/籍贯|户籍|户口|居住|所在地|城市|地址|出生地|生源/.test(base))return null;
 if(['year','month','day'].includes(component)&&/^(就读时间|起止时间|在校时间|工作时间|项目时间)$/.test(base)){
  const peers=[...row.querySelectorAll('input,select')].filter(n=>types[caption(n.placeholder||n.getAttribute('aria-label')||'')]===component);
  const index=peers.indexOf(el);if(peers.length===2)base=index===0?'开始时间':'结束时间';
 }
 return {component,label:base};
}
function dateWidget(el) {return el.tagName==='INPUT'&&!!el.closest('.el-date-editor,.ant-picker,.react-datepicker-wrapper,[data-date-picker]');}
const headingCache=new WeakMap();const repeatRowCache=new Map();
function sectionFor(el,label) {
  if(/^(意向工作城市|是否可接受工作城市调剂|最初从何处了解到该校招职位信息|是否可实习)$/.test(label))return 'intention';
  const identityField=isIdentityLabel(label);
  if(identityField){const scoped=identityScope(el,label);if(scoped)return scoped;}
  // Flat recruitment forms often use plain text section dividers instead of legends.
  const ownerDoc=el.ownerDocument;
  const form=el.closest('form') || ownerDoc.body;
  const scopeNames=new Map([['紧急联络人','emergency'],['紧急联系人信息','emergency'],['家庭成员','family'],['主要家庭成员及社会关系','family'],['家庭成员情况','family'],['家庭情况','family'],['个人基本信息','basic'],['个人信息','basic'],['教育经历','education'],['工作经历','work'],['工作（实习）经历','work'],['项目经历','project'],['校园经历','campus']]);
  if(ownerDoc.location.hostname==='jsdg.zhaopin.com' && ownerDoc.location.hash.startsWith('#/pages/application-form/')) {
    const heading=n=>n.textContent.replace(/[*＊\s]/g,'').replace(/[（(]请.*$/,'');
    if(!headingCache.has(form))headingCache.set(form,[...form.querySelectorAll('h2,h3,legend,span,div,uni-text,uni-view')].filter(n=>n.textContent.length<100&&scopeNames.has(heading(n))&&visible(n)));
    if(/^(婚育状况|目前状态)$/.test(label))return 'basic';if(/^是否|^(?:填表)?日期$/.test(label))return 'declaration';
    const nearest=headingCache.get(form).findLast(n=>(n.compareDocumentPosition(el)&Node.DOCUMENT_POSITION_FOLLOWING));
    if(nearest)return scopeNames.get(heading(nearest));
    // This form starts with the applicant block and names the contact block separately.
    return 'basic';
  }
  const structured=structuralSection(el);if(structured)return structured;
  let hints=[el.name||'',el.id||'']; let parent=el.parentElement;
  for(let depth=0;parent&&depth<6;depth++,parent=parent.parentElement) {
    hints.push(parent.getAttribute('data-section')||'',parent.id||'');
    const title=parent.querySelector(':scope > legend,:scope > h1,:scope > h2,:scope > h3,:scope > h4,:scope > .section-title,:scope > .title');
    if(title) hints.push(title.textContent||'');
  }
  // A visible preceding heading is a useful fallback for common application forms.
  if(hints.join('').length<8) { const headings=[...el.getRootNode().querySelectorAll('h2,h3,h4,legend')].filter(h=>(h.compareDocumentPosition(el)&Node.DOCUMENT_POSITION_FOLLOWING)&&visible(h)); if(headings.length) hints.push(headings.at(-1).textContent||''); }
  for(const hint of hints) { if(identityField){const scoped=identitySectionHeading(hint);if(scoped)return scoped;}else for(const [section,pattern] of sectionRules)if(pattern.test(hint))return section; }
  const headingCandidates=[...el.getRootNode().querySelectorAll('h2,h3,h4,legend,[class*=title],[class*=heading]')].filter(h=>(h.compareDocumentPosition(el)&Node.DOCUMENT_POSITION_FOLLOWING)&&visible(h)&&h.textContent.trim().length<60);
  for(const h of headingCandidates.reverse()){if(identityField){const scoped=identitySectionHeading(h.textContent);if(scoped)return scoped;}else for(const [section,pattern]of sectionRules)if(pattern.test(h.textContent))return section;}
  if(/学校|院校|学位|学历|专业|GPA|绩点|school|university|major|degree/i.test(label)) return 'education';
  if(/项目名称|项目描述|项目职责/i.test(label)) return 'project';
  if(/公司名称|单位名称|工作职责|离职/i.test(label)) return 'work';
  return '';
}
function geographicControl(el) { return el.tagName==='INPUT'&&el.readOnly&&/籍贯|户口|户籍|现居(?:住)?城市|居住地|学校所在地|生源地/.test(labelFor(el)); }
const controls=[]; const seen=new Set(); const occurrences=new Map(); const entryTrust=new WeakMap(); const manualFields=[]; let loginVisible=false;
function entryIndexFor(el,section,label) {
  if(el.ownerDocument.location.hostname==='jsdg.zhaopin.com' && ['education','work','project','family'].includes(section)) {
    const row=el.closest('.table-item')?.parentElement;
    if(row){if(!repeatRowCache.has(section))repeatRowCache.set(section,[...new Set([...el.ownerDocument.querySelectorAll('.table-item')].filter(n=>{const c=n.querySelector('input,textarea,select');return c&&sectionFor(c,labelFor(c))===section}).map(n=>n.parentElement))]);const rows=repeatRowCache.get(section);if(rows.includes(row)){entryTrust.set(el,true);return rows.indexOf(row);}}
  }
  if(['basic','intention','evaluation','emergency'].includes(section))return 0;
  const moka=el.closest('[class*="apply-fields-"]');
  if(moka&&moka.className.includes('multi-')){const block=moka.closest('[class*="apply-block-"]');if(block){const groups=[...block.querySelectorAll('[class*="apply-fields-"]')].filter(n=>n.className.includes('multi-'));entryTrust.set(el,true);return groups.indexOf(moka);}}
  const named=[el.name,el.id].join(' '); const explicit=named.match(/(?:education|work|project|family|campus|award|certificate|language)(?:\[|_|-|\.)(\d+)/i);
  if(explicit){entryTrust.set(el,true);return Number(explicit[1]);}
  const group=el.closest('[data-entry-index],fieldset,.education-item,.work-item,.project-item,.experience-item');
  if(group) {
    const specified=group.getAttribute('data-entry-index');if(specified!==null&&/^\d+$/.test(specified)){entryTrust.set(el,true);return Number(specified);}
    const title=group.querySelector('legend,h2,h3,h4')?.textContent||'';
    const sectionPattern=sectionRules.find(x=>x[0]===section)?.[1];
    const groups=roots.flatMap(r=>[...r.querySelectorAll('fieldset,.education-item,.work-item,.project-item,.experience-item')]).filter(g=>sectionPattern?.test(g.querySelector('legend,h2,h3,h4')?.textContent||g.className)&&visible(g));
    if(sectionPattern?.test(title||group.className)&&groups.includes(group)){entryTrust.set(el,true);return groups.indexOf(group);}
  }
  let canonical=normalize(label);
  const aliases=[[/^(学校|学校名称|毕业院校|院校|school|university)$/,'school'],[/^(开始时间|开始日期|入学时间|入学日期|入学年月|startdate)$/,'start'],[/^(结束时间|结束日期|毕业时间|毕业日期|毕业年月|enddate)$/,'end'],[/^(公司|公司名称|工作单位|company)$/,'company']];
  for(const [pattern,name]of aliases)if(pattern.test(canonical)){canonical=name;break;}
  const key=section+'|'+canonical;const occurrence=occurrences.get(key)||0;occurrences.set(key,occurrence+1);return occurrence;
}
for(const root of roots) for(const el of root.querySelectorAll('input,select,textarea,[contenteditable="true"],[role="combobox"],[role="radio"],[role="checkbox"]')) {
  if(seen.has(el)||!visible(el)||el.disabled||el.getAttribute('aria-disabled')==='true') continue;
  if(el.getAttribute('role')==='combobox'&&el.querySelector('input,select'))continue;
  if(['radio','checkbox'].includes(el.getAttribute('role'))&&el.querySelector('input'))continue;
  seen.add(el); const customSelect=(!!el.closest('.el-select,.ant-select,.arco-select,[class*="sd-Select-container"],.el-cascader')||geographicControl(el))&&el.tagName!=='SELECT'; const type=dateWidget(el)&&el.readOnly?'date-widget':customSelect?'combobox':(['radio','checkbox'].includes(el.getAttribute('role'))&&el.tagName!=='INPUT'?'aria-'+el.getAttribute('role'):(el.getAttribute('type')||el.type||el.getAttribute('role')||el.tagName).toLowerCase());
  const component=componentFor(el);const label=component?.label||labelFor(el); const hint=[label,el.name,el.id,el.autocomplete].join(' ');
  if(type==='password'||/one-time-code/.test(el.autocomplete||'')||/验证码|短信码|captcha|otp/i.test(hint)) {loginVisible=true;manualFields.push(label);continue;}
  if(['hidden','submit','reset','button','image'].includes(type))continue;
  if(type==='checkbox'&&/^(至今|其他)$/.test(label)&&(el.closest('.table-item')||(label==='至今'&&el.closest('.form-item,.el-form-item,.ant-form-item,.form-group')?.querySelector('input[readonly],input[type="date"],input[type="month"]'))))continue;
  if(type==='file'||type==='search'||/^(搜索|search)|职位关键字|^\+\d{1,4}$/i.test(label)||el.closest('nav,header,[role="banner"],[class*="navbar-"]'))continue;
  if(blocked.test(hint)){manualFields.push(label);continue;}
  if(el.readOnly && !customSelect && type!=='date-widget' && el.getAttribute('role')!=='combobox'){manualFields.push(label);continue;}
  let nodes=[el], options=[];
  if(type==='aria-radio'||type==='aria-checkbox') {
    const role=el.getAttribute('role'),group=el.closest('[role="radiogroup"],[role="group"],fieldset,.form-item,.form-group,.ant-form-item,.el-form-item');
    if(!group){manualFields.push(label);continue;}
    nodes=[...group.querySelectorAll('[role="'+role+'"]')].filter(n=>visible(n)&&n.getAttribute('aria-disabled')!=='true'&&!n.querySelector('input'));
    nodes.forEach(n=>seen.add(n));
    const actualLabel=caption(group.getAttribute('aria-label')||group.querySelector('legend,.label,.el-form-item__label,.ant-form-item-label')?.textContent||'');
    if(!actualLabel||blocked.test(actualLabel)){if(actualLabel)manualFields.push(actualLabel);continue;}
    const section=sectionFor(el,actualLabel),entryIndex=entryIndexFor(el,section,actualLabel);
    options=nodes.map(n=>({value:n.getAttribute('data-value')||n.getAttribute('aria-label')||n.textContent.trim(),label:n.getAttribute('aria-label')||n.textContent.trim()}));
    controls.push({nodes,el,label:actualLabel,section,entryIndex,type,options,required:group.getAttribute('aria-required')==='true',hasValue:nodes.some(checked)});continue;
  }
  if(type==='radio'||type==='checkbox') {
    if(el.name) nodes=[...root.querySelectorAll('input')].filter(n=>n.type===type&&n.name===el.name&&visible(n)&&!n.disabled);
    nodes.forEach(n=>seen.add(n));
    const group=el.closest('fieldset,.form-item,.form-group,.ant-form-item,.el-form-item,[role="radiogroup"]');
    const groupLabel=group?.getAttribute('aria-label')||el.closest('.el-form-item')?.querySelector('.el-form-item__label')?.textContent||group?.querySelector('legend,.ant-form-item-label,.el-form-item__label')?.textContent;
    const actualLabel=caption(groupLabel||rowCaption(fieldRow(el))||el.getAttribute('aria-label')||label);
    if(blocked.test(actualLabel)){manualFields.push(actualLabel);continue;}
    options=nodes.map(n=>({value:n.value,label:labelFor(n)}));
    const section=sectionFor(el,actualLabel); const occurrence=entryIndexFor(el,section,actualLabel);
    controls.push({nodes,el,label:actualLabel,section,entryIndex:occurrence,type,options,required:nodes.some(n=>n.required),hasValue:nodes.some(n=>n.checked)}); continue;
  }
  if(el.tagName==='SELECT') options=[...el.options].map(o=>({value:o.value,label:o.textContent.trim(),disabled:o.disabled}));
  const section=sectionFor(el,label); const occurrence=entryIndexFor(el,section,component?label+'|'+component.component:label);
  const value=readCurrent(el);
  const selectedPlaceholder=el.tagName==='SELECT'&&(!value||/^(请选择|选择|select|please select)/i.test(el.selectedOptions?.[0]?.textContent.trim()||''));
  controls.push({nodes,el,label,component:component?.component,section,entryIndex:occurrence,type,options,required:el.required||el.getAttribute('aria-required')==='true',hasValue:!placeholderValue(el,value)&&!selectedPlaceholder});
}
for(const c of controls){c.groupTrusted=entryTrust.get(c.el)===true;c.signature=[labelFor(c.el),c.el.name,c.el.id,c.el.type,c.el.getAttribute('type'),c.el.tagName,c.el.getAttribute('role'),sectionFor(c.el,labelFor(c.el))].join('|');}
const uploadControls=roots.flatMap(r=>[...r.querySelectorAll('input[type="file"]')]).map(el=>({el,container:el.closest('.el-form-item,.form-item,.form-group,.ant-form-item')||el.closest('.el-upload')?.parentElement,label:labelFor(el)})).filter(c=>c.container&&visible(c.container)&&!c.el.disabled&&resumeSlot(c.label));

// Observe structural affordances separately from action selection. Ambiguous
// controls require a grounded model decision; the executor never guesses an ID.
const journeySectionNames=/^(个人信息|基本信息|个人资料|联系方式|教育经历|教育背景|学历信息|求职意向|实习[\/／、与和]?工作经历|工作[\/／、与和]?实习经历|工作经历|实习经历|项目经历|项目经验|语言能力|外语能力|专业技能|计算机技能|奖励荣誉|获奖情况|校园经历|在校经历|社团经历|家庭情况|家庭成员|资格证书|证书|论文期刊|论文|专利|作品集|附件|附件材料|其他信息|补充信息|自我评价|兴趣爱好|personal information|education|experience|skills|attachments)$/i;
function journeyCaption(text) {
 return String(text||'').replace(/[\ue000-\uf8ff*＊]/g,'').replace(/(?:未完成|已完成|待完善|必填|选填|\d+\s*%)/g,'').replace(/\s+/g,' ').trim().replace(/^[^\p{L}\p{N}]+/u,'');
}
function journeyRegion(el) {
 const semantic=el.closest('section,fieldset,[data-section],.profile-section,.resume-section,form');
 let parent=el.parentElement;
 for(let depth=0;parent&&parent!==el.ownerDocument.body&&depth<9;depth++,parent=parent.parentElement){
  const titles=[...parent.querySelectorAll('h1,h2,h3,h4,h5,h6,legend,[class*="title"],[class*="Title"],[class*="heading"]')].filter(visible).map(n=>journeyCaption(n.textContent)).filter(t=>journeySectionNames.test(t));
  const unique=[...new Set(titles)];
  if(unique.length===1)return {el:parent,title:unique[0]};
  if(unique.length>1)break;
 }
 // An inner form often has no heading. Keep looking through semantic
 // containers so its save/next buttons inherit the enclosing profile title.
 for(let container=semantic;container;container=container.parentElement?.closest('section,fieldset,[data-section],.profile-section,.resume-section,form')) {
  const title=(container.querySelector('h1,h2,h3,h4,h5,h6,legend,.section-title')?.textContent||container.getAttribute('data-section')||'').trim().slice(0,100);
  if(title)return {el:container,title};
 }
 return {el:semantic,title:''};
}
function journeyClickable(el) {
 return el.matches('button,a,input[type="button"],input[type="submit"],[role="button"],[role="tab"],[onclick],[tabindex]')||el.ownerDocument.defaultView.getComputedStyle(el).cursor==='pointer';
}
function journeySectionLink(el) {
 const label=journeyCaption(el.textContent);
 if(!journeySectionNames.test(label)||!journeyClickable(el))return false;
 if(el.getAttribute('role')==='tab')return true;
 let parent=el.parentElement;
 for(let d=0;parent&&parent!==el.ownerDocument.body&&d<5;d++,parent=parent.parentElement){
  // A sidebar/step-list has multiple section captions, unlike a field label.
  const r=parent.getBoundingClientRect();if(r.width>el.ownerDocument.defaultView.innerWidth*0.65)continue;
  const names=[...parent.querySelectorAll('h1,h2,h3,h4,h5,h6,li,a,span,div')].filter(visible).map(n=>journeyCaption(n.textContent)).filter(t=>journeySectionNames.test(t));
  if(new Set(names).size>=2)return true;
 }
 return false;
}
function journeySnapshot() {
 const dialogs=roots.flatMap(r=>[...r.querySelectorAll('[role=dialog],[role=alertdialog],dialog[open],.el-message-box,.el-dialog,.ant-modal')]).filter(visible);
 const modal=dialogs.filter(n=>!dialogs.some(other=>other!==n&&n.contains(other))).at(-1);
 const modalContext=modal?(modal.querySelector('.el-message-box__message,.el-dialog__body,.ant-modal-body')?.textContent||modal.textContent).trim().slice(0,300):null;
 const fields=controls.map(c=>[c.section,c.entryIndex,c.label,c.type].join(':'));
 const formNames=/基本|个人|联系|教育|学历|工作|实习|项目|家庭|亲属|校园|在校|奖|语言|外语|技能|证书|论文|专利|作品|求职|意向|附件|自我|兴趣|补充|其他信息|personal|contact|education|employment|experience|skills|attachment/i;
 const nativeSelector='button,a,input[type="button"],input[type="submit"],[role="button"],[role="tab"],[aria-expanded]';
 const extraSelector='div,span,li,h1,h2,h3,h4,h5,h6,i[title],svg[aria-label]';
 const allNodes=roots.flatMap(r=>[...r.querySelectorAll(nativeSelector+','+extraSelector)]);
 const nodes=allNodes.filter(el=>{
   if(el.matches(nativeSelector))return true;
   const label=journeyCaption(el.getAttribute('aria-label')||el.title||el.textContent);
   if(!/^(编辑|修改|完善|填写|保存|保存信息|保存资料|保存本段|保存本页|edit|save)$/i.test(label)&&!journeySectionNames.test(label))return false;
   if(!journeyClickable(el)||el.closest('button,a,[role="button"],[role="tab"]'))return false;
   return ![...el.children].some(n=>journeyCaption(n.getAttribute('aria-label')||n.textContent)===label&&journeyClickable(n));
 });
 const active=[...new Set(roots.flatMap(r=>[...r.querySelectorAll('[role="tab"][aria-selected="true"],[aria-current="step"],.el-step.is-process,.el-steps .is-process,.ant-steps-item-process'),...adapterNodes(r,adapter.activeSections)]))].filter(visible).map(n=>n.textContent.trim().slice(0,100));
 const headings=roots.flatMap(r=>[...r.querySelectorAll('h1,h2,h3,h4,h5,h6,legend')]).filter(visible).map(n=>n.textContent.trim().slice(0,100));
 const scope=JSON.stringify([location.href,active,headings]);
 const candidates=[];
 for(const el of nodes) {
   if(!visible(el)||el.disabled||el.getAttribute('aria-disabled')==='true'||(modal&&!modal.contains(el)))continue;
   if(el.getAttribute('role')==='tab'&&el.getAttribute('aria-selected')==='true')continue;
   if(el.getAttribute('aria-expanded')==='true')continue;
   const rawLabel=(el.getAttribute('aria-label')||el.value||el.textContent||'').trim().replace(/\s+/g,' ');
   const sectionLink=journeySectionLink(el);
   const label=sectionLink?journeyCaption(rawLabel):rawLabel.replace(/[\ue000-\uf8ff]/g,'').trim().replace(/^[^\p{L}\p{N}]+/u,'');
   const compact=normalize(label);
   // Site navigation is outside this application's form journey.
   if(/^(个人中心|用户中心|账户中心|首页|主页|岗位列表|职位列表|招聘首页|我的报名|我的申请|帮助中心|消息中心|personalcenter|account|dashboard|home)$/i.test(compact))continue;
   if(el.closest('header,footer,[role="banner"],[role="contentinfo"],[role="menu"]')&&!el.closest('form,fieldset,[data-section],.profile-section,.resume-section'))continue;
   if(!label||label.length>70||blocked.test(compact)||/不保存|放弃|discard|donotsave|dontsave/.test(compact)||/提交|报名|投递|发送|支付|删除|撤回|退出|注销|重置|清空|确认|完成|搜索|查找|下载|取消|登录|注册|submit|apply|send|pay|delete|withdraw|finish|confirm|reset|clear|search|download|cancel|login|register|sign.?in/i.test(compact))continue;
   if(el.matches('a[href]')){try{const u=new URL(el.href,location.href);if(u.origin!==location.origin)continue;}catch{continue;}}
   let kind='',allowedKinds=[];
   const inferred=journeyRegion(el),region=inferred.el;
   const context=modal?modalContext:sectionLink?label:inferred.title;
   if(/^(保存并(?:下一步|继续|进入下一步|跳转|离开)|保存后(?:继续|跳转)|saveandcontinue|saveandnext|savenext)$/.test(compact))kind='save-next';
   else if(/^(下一步|下一页|继续填写|next|nextstep|continue)$/.test(compact))kind='next';
   else if(/^(保存|保存本段|保存本页|保存信息|保存资料|保存并关闭|保存当前模块|save|savesection|savechanges)$/.test(compact))kind='save';
   else if(sectionLink)kind='tab';
   else if(el.getAttribute('aria-expanded')==='false'&&formNames.test(label))kind='expand';
   else if(el.getAttribute('role')==='tab'&&el.getAttribute('aria-selected')!=='true'&&formNames.test(label))kind='tab';
   // An edit button is valid only inside a named profile section.
   else if(/^(编辑|修改|完善|填写|edit)$/.test(compact)) {
     if(region&&formNames.test(context)&&![...region.querySelectorAll('input:not([type="hidden"]),textarea,select')].some(visible))kind='edit';
   }
   if(!kind) {
     if(el.getAttribute('role')!=='tab'&&/上传|选择文件|upload|browse.?file/i.test(label))continue;
     const formScoped=!!el.closest('form,section[data-section],fieldset,.profile-section,.resume-section');
     const safeButton=(el.tagName==='BUTTON'&&el.type==='button')||(el.tagName==='INPUT'&&el.type==='button')||el.getAttribute('role')==='button';
     if(el.getAttribute('role')==='tab'&&el.getAttribute('aria-selected')!=='true'&&formScoped)allowedKinds=['tab'];
     else if(el.getAttribute('aria-expanded')==='false'&&formScoped)allowedKinds=['expand'];
     else if(safeButton&&formScoped&&context&&!el.closest('[role="menu"],nav,header,footer')) {
       allowedKinds=['edit','expand'];
       if(region&&[...region.querySelectorAll('input:not([type="hidden"]),textarea,select')].some(visible))allowedKinds.push('save','save-next','next');
     }
     if(!allowedKinds.length)continue;
     kind='semantic';
   } else allowedKinds=[kind];
   const siblings=nodes.filter(n=>visible(n)&&journeyCaption(n.getAttribute('aria-label')||n.value||n.textContent)===journeyCaption(label));
   const index=siblings.indexOf(el);
   candidates.push({el,id:kind+'|'+context+'|'+label+'|'+index,label,kind,context,allowedKinds});
 }
 // Inspect scrollable form regions as well as currently rendered fields. This
 // exposes lazy-loaded sections without scrolling open option menus.
 const scrollers=modal?[]:[document.scrollingElement,...document.querySelectorAll('form,section,div,main')].filter((el,i,all)=>el&&all.indexOf(el)===i&&visible(el)&&el.clientHeight>180&&el.scrollHeight>el.clientHeight+40&&!el.closest('[role="listbox"],.el-select-dropdown,.el-cascader__dropdown,.ant-select-dropdown')&&(el===document.scrollingElement||/auto|scroll/.test(getComputedStyle(el).overflowY))&&(el.querySelector('input,textarea,select')||candidates.some(c=>['edit','expand'].includes(c.kind)&&el.contains(c.el))));
 for(const [i,el] of scrollers.entries()) {
   if(el.scrollTop+el.clientHeight>=el.scrollHeight-4)continue;
   candidates.push({el,id:'scroll|'+i+'|'+Math.round(el.scrollTop),label:'查看下方资料',kind:'scroll',context:'尚未查看的表单滚动区域',allowedKinds:['scroll']});
 }
 const validation=roots.flatMap(r=>[...r.querySelectorAll('[role="alert"],.el-form-item__error,.ant-form-item-explain-error,.field-error,.error-message')]).filter(visible).map(n=>n.textContent.trim().slice(0,160)).filter(Boolean);
 const invalid=controls.filter(c=>c.el.validity?.valid===false||c.el.getAttribute('aria-invalid')==='true').map(c=>c.label);
 const fingerprint=JSON.stringify([scope,fields,modalContext]);
 const sectionTitles=[...active,...headings].map(journeyCaption).filter(t=>journeySectionNames.test(t)||exactSectionNames.has(t));
 const resumeSection=sectionTitles[0]||'';
 return {scope,fingerprint,modalContext,progress:JSON.stringify([fingerprint,controls.map(c=>c.hasValue)]),headings,activeSections:active,resumeSection,candidates,validation:[...new Set([...validation,...invalid])],hasFields:!modal&&(controls.length>0||uploadControls.length>0),needsLogin:loginVisible};
}
if(action==='journey'||action==='journeyAction') {
 const snap=journeySnapshot();
 if(action==='journeyAction') {
   if(desiredSections.fingerprint!==snap.fingerprint)return {error:'page-changed'};
   const choices=snap.candidates.filter(c=>c.id===desiredSections.id);
   if(choices.length!==1)return {error:'action-changed'};
   const c=choices[0];if(c.kind==='scroll'){if(desiredSections.step==='execute'){c.el.scrollBy({top:Math.max(160,c.el.clientHeight*0.8),behavior:'instant'});return {activated:true,kind:'scroll'};}return {kind:'scroll'};}if(c.kind==='semantic'&&!c.allowedKinds.includes(desiredSections.kind))return {error:'unresolved-action'};c.el.scrollIntoView({block:'center',behavior:'instant'});
   const r=c.el.getBoundingClientRect();
   // Never use synthetic form.submit() or dispatch an Enter key.
   if(desiredSections.step==='execute'){c.el.click();return {activated:true,kind:c.kind,label:c.label};}
   return {click:{x:r.x+r.width/2,y:r.y+r.height/2},kind:c.kind,label:c.label};
 }
 return {scope:snap.scope,fingerprint:snap.fingerprint,modalContext:snap.modalContext,progress:snap.progress,headings:snap.headings,activeSections:snap.activeSections,resumeSection:snap.resumeSection,actions:snap.candidates.map(({el,...c})=>c),validation:snap.validation,hasFields:snap.hasFields,needsLogin:snap.needsLogin};
}

if(action==='layoutDiagnostics')return {menus:[...document.querySelectorAll('[class*="sd-"]')].filter(n=>visible(n)&&/option|menu|dropdown/i.test(n.className)).map(n=>({cls:n.className,tag:n.tagName,role:n.getAttribute('role'),text:n.textContent.slice(0,100)})),inputs:roots.flatMap(r=>[...r.querySelectorAll('input,textarea,select')]).filter(visible).map(n=>{let parents=[],p=n.parentElement;for(let i=0;p&&i<9;i++,p=p.parentElement)parents.push({tag:p.tagName,cls:p.className,role:p.getAttribute('role'),caption:rowCaption(p).slice(0,100)});return {label:labelFor(n),section:sectionFor(n,labelFor(n)),component:componentFor(n),tag:n.tagName,type:n.type,readOnly:n.readOnly,role:n.getAttribute('role'),classes:n.className,placeholder:n.placeholder,selectParts:[...(n.closest('[class*="sd-Select-container"]')?.querySelectorAll('*')||[])].map(x=>({tag:x.tagName,cls:x.className,role:x.getAttribute('role'),text:x.tagName==='INPUT'?'':x.textContent.slice(0,80)})),parents};})};
if(action==='scan') {
  globalThis.__careerControlIDs??=new WeakMap();
  const identity=el=>{if(!globalThis.__careerControlIDs.has(el))globalThis.__careerControlIDs.set(el,crypto.randomUUID());return globalThis.__careerControlIDs.get(el);};
  const token=crypto.randomUUID(); globalThis.__careerApplicationState={token,href:location.href,document,controls,uploads:uploadControls};
  return {token,url:location.href,title:document.title,uploads:uploadControls.map((c,i)=>({id:"u"+i,identity:identity(c.el),label:c.label,accept:c.el.accept||"",hasValue:!!c.container.querySelector('.el-upload-list__item.is-success,.ant-upload-list-item-done,[data-upload-state="success"]')})),needsLogin:loginVisible, inaccessibleFrames,manualFields,fields:controls.map((c,i)=>({id:'f'+i,identity:identity(c.el),label:c.label,component:c.component,section:c.section,entryIndex:c.entryIndex,type:c.type,options:c.options,required:c.required,hasValue:c.hasValue,maxLength:c.el.maxLength>0?c.el.maxLength:undefined}))};
}
if(action==='expand') {
 for(const block of document.querySelectorAll('[class*="apply-block-"]')) {
  const groups=[...block.querySelectorAll('[class*="apply-fields-"]')].filter(n=>n.className.includes('multi-'));
  const first=block.querySelector('input,textarea,select');if(!groups.length||!first)continue;
  const section=sectionFor(first,labelFor(first)),wanted=desiredSections[section]||0;
  if(groups.length>=wanted)continue;
  const buttons=[...block.querySelectorAll('button,span,div')].filter(n=>visible(n)&&n.textContent.trim()==='添加'&&!n.disabled&&n.getAttribute('aria-disabled')!=='true'&&![...n.children].some(c=>c.textContent.trim()==='添加'));
  if(buttons.length===1){buttons[0].click();return {added:1};}
 }

  if(location.hostname==='jsdg.zhaopin.com' && location.hash.startsWith('#/pages/application-form/')) {
    for(const section of ['education','work','project','family']) {
      const existing=new Set(controls.filter(c=>c.section===section&&c.groupTrusted).map(c=>c.entryIndex)).size;
      if(existing >= (desiredSections[section]||0))continue;
      const candidates=[...document.querySelectorAll('button')].filter(n=>visible(n)&&!n.disabled&&n.textContent.trim()==='新增'&&sectionFor(n,'')===section);
      if(candidates.length===1){const n=candidates[0];n.scrollIntoView({block:'center',behavior:'instant'});const r=n.getBoundingClientRect();return {added:1,click:{x:r.x+r.width/2,y:r.y+r.height/2}};}
    }
    return {added:0};
  }
  let added=0; const reasons=[];
  const captions={education:/^(添加|新增|增加|继续添加)(一段)?教育(经历|背景)$/,work:/^(添加|新增|增加|继续添加)(一段)?(工作|实习)(经历|经验)$/,project:/^(添加|新增|增加|继续添加)(一段)?项目(经历|经验)$/,campus:/^(添加|新增|增加|继续添加)(一段)?(在校|校园|社团)经历$/,award:/^(添加|新增|增加|继续添加)(获奖|奖励)(情况|经历)?$/,language:/^(添加|新增|增加|继续添加)(外语|语言)(能力)?$/,certificate:/^(添加|新增|增加|继续添加)(资格)?证书$/,family:/^(添加|新增|增加|继续添加)(家庭成员|亲属)$/,paper:/^(添加|新增|增加|继续添加)(论文|期刊)$/,patent:/^(添加|新增|增加|继续添加)专利$/,portfolio:/^(添加|新增|增加|继续添加)(个人)?作品$/,competition:/^(添加|新增|增加|继续添加)竞赛(经历)?$/};
  for(const [section,wanted] of Object.entries(desiredSections||{})) {
    if(!captions[section]||wanted<1)continue;
    const existing=controls.filter(c=>c.section===section).reduce((n,c)=>Math.max(n,c.entryIndex+1),0);
    if(existing>=wanted)continue;
    const buttons=roots.flatMap(root=>[...root.querySelectorAll('button[type="button"],[role="button"]')]).filter(el=>visible(el)&&!el.disabled&&captions[section].test(el.getAttribute('aria-label')||el.textContent.trim())&&!blocked.test(el.textContent));
    // One exact, non-submit add control per section. Caller rescans between steps.
    if(buttons.length===1){buttons[0].click();added++;} else reasons.push(section);
  }
  return {added,unsupportedSections:reasons};
}
if(!['fill','fillDiagnostics','repair','audit','upload'].includes(action)) return {error:'unknown-action'};
const state=globalThis.__careerApplicationState;
if(!state||state.token!==token||state.href!==location.href||state.document!==document) return {error:'page-changed',results:[]};
// Native pointer fallback: coordinates refer only to a scanned field or its open menu.
const rectFor=n=>{n.scrollIntoView({block:'nearest',behavior:'instant'});const r=n.getBoundingClientRect();let w=n.ownerDocument.defaultView,x=(Math.max(0,r.left)+Math.min(w.innerWidth,r.right))/2,y=(Math.max(0,r.top)+Math.min(w.innerHeight,r.bottom))/2;while(w!==window){const frame=w.frameElement;if(!frame)return {x:-1,y:-1};frame.scrollIntoView({block:'nearest',behavior:'instant'});const box=frame.getBoundingClientRect(),sx=box.width/frame.offsetWidth,sy=box.height/frame.offsetHeight;x=box.left+(x+frame.clientLeft)*sx;y=box.top+(y+frame.clientTop)*sy;w=frame.ownerDocument.defaultView;}return {x,y};};
const pointer=(n,extra={})=>{const click=rectFor(n);if(desiredSections.perform===true&&(n.closest('.el-cascader')||n.closest('.el-cascader-node'))){const w=n.ownerDocument.defaultView;n.dispatchEvent(new w.MouseEvent('mouseover',{bubbles:true,clientX:click.x,clientY:click.y}));n.dispatchEvent(new w.MouseEvent('mouseenter',{bubbles:false,clientX:click.x,clientY:click.y}));n.click();return {...extra,click,invoked:true};}return {...extra,click};};
const choiceEqual=(x,y)=>normalize(x)===normalize(y)||({'研究生':'硕士研究生','硕士':'硕士研究生','本科生':'本科','大学本科':'本科','男生':'男','女生':'女','团员':'共青团员','党员':'中共党员'}[normalize(x)]||normalize(x))===({'研究生':'硕士研究生','硕士':'硕士研究生','本科生':'本科','大学本科':'本科','男生':'男','女生':'女','团员':'共青团员','党员':'中共党员'}[normalize(y)]||normalize(y));
function sameValue(a,b){
 if(normalize(a)===normalize(b))return true;
 const date=v=>{const m=String(v).match(/^(\d{4})[年/.\-](\d{1,2})(?:[月/.\-](\d{1,2}))?日?月?$/);return m?m[1]+'-'+m[2].padStart(2,'0')+(m[3]?'-'+m[3].padStart(2,'0'):''):null;};
 return date(a)!==null&&date(a)===date(b);
}
function resolveControl(id) {
 const index=Number(id.slice(1));let c=state.controls[index];
 if(c&&(!c.el.isConnected||!visible(c.el)||c.el.disabled)){const fresh=controls.filter(n=>n.label===c.label&&n.section===c.section&&n.entryIndex===c.entryIndex&&n.component===c.component);if(fresh.length===1)state.controls[index]=c=fresh[0];}
 return c?.el.isConnected?c:null;
}
function dateParts(value) {
 const m=String(value).trim().match(/^(\d{4})[年/.\-](\d{1,2})(?:[月/.\-](\d{1,2}))?[日月]?$/);if(!m)return null;
 const year=+m[1],month=+m[2],day=m[3]?+m[3]:null;
 if(month<1||month>12||day!==null&&(day<1||new Date(year,month-1,day).getMonth()!==month-1))return null;
 return {year,month,day};
}
function componentValue(c,value) {
 if(!c.component)return value;
 if(c.component==='year'&&/^\d{4}年?$/.test(String(value).trim()))return String(value).trim().slice(0,4);
 if(['year','month','day'].includes(c.component)){const d=dateParts(value);return d&&d[c.component]!=null?String(d[c.component]):null;}
 const text=String(value).replace(/[\s/·,，]/g,'');
 const municipality=text.match(/^(北京市|上海市|天津市|重庆市)(.*)$/);
 if(municipality)return c.component==='district'?municipality[2]||null:municipality[1];
 const match=text.match(/^(.*?(?:省|自治区|特别行政区))?(.*?(?:市|自治州|地区|盟))?(.*?(?:区|县|旗|市))?$/);
 return match?match[{province:1,city:2,district:3}[c.component]]||null:null;
}
function optionEqual(c,actual,expected) {
 if(expected==null)return false;
 if(/城市|工作地点|现居住地/.test(c.label)){const clean=x=>String(x).replace(/[·\s]/g,'').replace(/市$/,'');if(clean(actual)===clean(expected))return true;}

 if(['year','month','day'].includes(c.component)){const clean=x=>String(x).trim().replace(/[年月日]$/,'');return /^\d+$/.test(clean(actual))&&+clean(actual)===+expected;}
 return choiceEqual(actual,expected);
}
function valueParts(value){return String(value).split(/[,，;；、\n]/).map(s=>s.trim()).filter(Boolean);}
function siteValue(c,value) {
 if(c.component)return componentValue(c,value);
 if(c.el.closest('.el-date-editor--month')&&/^\d{4}[-/.]\d{2}/.test(value))return value.slice(0,7).replace(/[/.]/g,'-');
 if(c.el.maxLength>0&&value.length>c.el.maxLength&&/项目名称/.test(c.label)){const title=value.split(/[｜|：:（(]/)[0].trim();if(title&&title.length<=c.el.maxLength)return title;}
 return value;
}
const searchKey=c=>[c.section,c.entryIndex,c.label,c.component||''].join('|');
function accepts(c,value) {
 const present=presentControl(c,value);if(present&&checked(present))return true;
 const search=state.searches?.[searchKey(c)],picked=state.searchPicks?.[searchKey(c)];
 if(search&&(!picked||(visible(picked)&&picked.getAttribute('aria-selected')!=='true'&&!picked.classList.contains('selected')&&!picked.classList.contains('is-selected'))))return false;
 const expected=siteValue(c,value);if(expected==null)return false;
 if(c.type==='aria-radio'||c.type==='aria-checkbox'){const values=valueParts(expected);const chosen=c.nodes.filter(checked);return chosen.length===values.length&&values.every(v=>chosen.filter(n=>choiceEqual(n.getAttribute('aria-label')||n.textContent,v)||choiceEqual(n.getAttribute('data-value'),v)).length===1);}
 if(c.el.tagName==='SELECT'&&c.el.multiple){const values=valueParts(expected),chosen=[...c.el.selectedOptions];return chosen.length===values.length&&values.every(v=>chosen.filter(o=>choiceEqual(o.textContent,v)||choiceEqual(o.value,v)).length===1);}
 if(['radio','checkbox'].includes(c.type)){const semantic=state.semanticChoices?.get(c);if(semantic?.source===value&&c.nodes.some(n=>n.checked&&normalize(labelFor(n))===normalize(semantic.label)))return true;}
 if(['radio','checkbox'].includes(c.type)){
  if(c.type==='checkbox'&&c.nodes.length===1&&/^(是|有|true|yes|1)$/i.test(expected))return c.nodes[0].checked;
  const values=valueParts(expected),selected=c.nodes.filter(n=>n.checked);return selected.length===values.length&&values.every(v=>selected.filter(n=>choiceEqual(labelFor(n),v)||choiceEqual(n.value,v)).length===1);
 }
 const actual=readCurrent(c.el);if(!actual.trim())return false;
 const semantic=state.semanticChoices?.get(c);if(semantic?.source===value&&normalize(actual)===normalize(semantic.value))return true;
 if(c.el.tagName==='SELECT'&&[...c.el.selectedOptions].some(o=>optionEqual(c,o.textContent,expected)||optionEqual(c,o.value,expected)))return true;
 if(optionEqual(c,actual,expected))return true;
 if(choiceEqual(actual,expected)||sameValue(actual,expected))return true;
 if(geographicControl(c.el)&&locationAccepts(c,value))return true;
 if(c.el.closest('.el-cascader')&&normalize(actual).replace(/[\/省市]/g,'')===normalize(expected).replace(/[\/省市]/g,''))return true;
 return /最高.*(?:奖学金|荣誉)/.test(c.label)&&normalize(actual).length>=2&&normalize(expected).includes(normalize(actual));
}
if(action==='audit')return {results:assignments.map(a=>{const c=resolveControl(a.fieldID);return {id:a.fieldID,status:c&&accepts(c,a.value)?'filled':'unverified'};})};
if(action==='upload') {
 const a=assignments[0],index=Number(a?.fieldID?.slice(1));let u=state.uploads?.[index];
 if(u&&!u.el.isConnected){const fresh=uploadControls.filter(n=>n.label===u.label&&n.el.accept===u.el.accept);if(fresh.length===1)state.uploads[index]=u=fresh[0];}
 if(!u||!u.el.isConnected||!visible(u.container)||labelFor(u.el)!==u.label)return {error:'changed'};
 if(desiredSections.step==='prepare') {
   if(u.container.querySelector('.el-upload-list__item.is-success,.ant-upload-list-item-done,[data-upload-state="success"]'))return {preserved:true};
   const receipts=[...u.container.querySelectorAll('a[href]')].filter(n=>n.textContent.includes(a.value)&&/^https?:/i.test(n.href));
   if(receipts.length===1&&!u.container.querySelector('[role="progressbar"],.is-uploading,.is-fail,.ant-upload-list-item-uploading,.ant-upload-list-item-error,[data-upload-state="error"]'))return {preserved:true};
   const associated=[...(u.el.labels||[])].filter(visible);
   const buttons=[...u.container.querySelectorAll('button,[role="button"],label')].filter(n=>visible(n)&&!n.disabled&&/^(?:点击)?(?:上传(?:简历|文件|附件)?|选择(?:简历|文件|附件)|浏览|upload(?: resume| file)?|choose file|browse)$/i.test(n.textContent.trim()));
   const button=u.el.closest('.el-upload')?.querySelector('button')||u.el.closest('.el-upload')||(associated.length===1?associated[0]:buttons.length===1?buttons[0]:visible(u.el)?u.el:null);
   if(!button||!visible(button))return {error:'unsupported',canTrigger:true};
   button.scrollIntoView({block:'center',behavior:'instant'});return {click:rectFor(button),canTrigger:true};
 }
 if(desiredSections.step==='trigger'){u.el.click();return {invoked:true};}
 const items=[...u.container.querySelectorAll('.el-upload-list__item,.ant-upload-list-item,[data-upload-state]')];
 const successes=items.filter(n=>n.classList.contains('is-success')||n.classList.contains('ant-upload-list-item-done')||n.getAttribute('data-upload-state')==='success');
 const failed=items.some(n=>n.classList.contains('is-fail')||n.classList.contains('ant-upload-list-item-error')||n.getAttribute('data-upload-state')==='error');
 const selected=[...u.el.files].some(f=>f.name===a.value);
 const receiptLinks=[...u.container.querySelectorAll('a[href]')].filter(n=>n.textContent.includes(a.value)&&/^https?:/i.test(n.href));
 const progress=!!u.container.querySelector('[role="progressbar"],.is-uploading,.ant-upload-list-item-uploading');
 return {complete:!failed&&!progress&&(successes.some(n=>n.textContent.includes(a.value))||receiptLinks.length===1),selected,failed,fileLabelPresent:u.container.textContent.includes(a.value),structure:[...u.container.querySelectorAll('*')].map(n=>({tag:n.tagName,cls:n.className?.baseVal||n.className,filename:n.textContent.trim()===a.value}))};
}
function optionsFor(c) {
 const el=c.el,doc=el.ownerDocument,root=el.getRootNode();
 const sd=el.closest('[class*="sd-Select-container"]');
 if(sd){const container=sd.closest('[class*="sd-Dropdown-container"]');return [...(container?.querySelectorAll('[class*="sd-Menu-content-item"]')||[])].filter(n=>visible(n)&&n.getAttribute('aria-disabled')!=='true'&&!/disabled/i.test(n.className));}
 const select=el.closest('.el-select,.ant-select,.arco-select,[class*="sd-Select-container"],.el-cascader,[role="combobox"]');
 const ids=[el.getAttribute('aria-controls'),el.getAttribute('aria-owns'),select?.getAttribute('aria-controls'),select?.getAttribute('aria-owns')].filter(Boolean).join(' ').split(/\s+/).filter(Boolean);
 const owned=[...new Set(ids.map(id=>root.getElementById?.(id)||doc.getElementById(id)).filter(Boolean))];
 const selector='[role="option"],.el-select-dropdown__item,.el-cascader-node,.ant-select-item-option,[class*="sd-Select-option"],[class*="sd-Menu-item"]';
 const enabled=n=>visible(n)&&n.getAttribute('aria-disabled')!=='true'&&!n.classList.contains('is-disabled');
 if(ids.length)return owned.flatMap(n=>visible(n)?[...n.querySelectorAll(selector)]:[]).filter(enabled);
 const all=[...doc.querySelectorAll(selector)].filter(enabled);
 if(el.closest('.el-cascader'))return all.filter(n=>n.classList.contains('el-cascader-node'));
 const menus=new Set(all.map(n=>n.closest('[role="listbox"],.el-select-dropdown,.ant-select-dropdown,[class*="sd-Dropdown-dropdown"],[class*="sd-Dropdown-menu"],[class*="sd-Select-menu"]')||n.parentElement));
 return menus.size===1?all:[];
}
function widgetClick(node) {
 if(!node||!visible(node)||node.disabled||node.getAttribute('aria-disabled')==='true')return {done:false};
 node.scrollIntoView({block:'nearest',behavior:'instant'});
 const w=node.ownerDocument.defaultView;
 node.dispatchEvent(new w.MouseEvent('mousedown',{bubbles:true}));node.dispatchEvent(new w.MouseEvent('mouseup',{bubbles:true}));node.click();
 return {invoked:true,continue:true};
}
function locationParts(value) {
 const text=String(value).replace(/[\s/·,，-]/g,'');
 const direct=text.match(/^(北京市|上海市|天津市|重庆市)(.*)$/);if(direct)return [direct[1],direct[2]].filter(Boolean);
 return ['province','city','district'].map(component=>componentValue({component},value)).filter(Boolean);
}
function geoText(value) {return normalize(value).replace(/[\ue000-\uf8ff/·,，-]/g,'').replace(/维吾尔自治区|壮族自治区|回族自治区|特别行政区|自治区|省|市/g,'');}
function locationLeaves(panel) {
 const nodes=[...panel.querySelectorAll('span,li,div,a,button,[role="tab"],[role="option"]')].filter(n=>visible(n)&&!n.disabled&&n.getAttribute('aria-disabled')!=='true');
 return nodes.filter(n=>!nodes.some(child=>child!==n&&n.contains(child)&&geoText(child.textContent)===geoText(n.textContent)));
}
function locationPanelCandidates(doc) {
 const panels=[];
 const inputs=[...doc.querySelectorAll('input')].filter(n=>visible(n)&&/搜索.*(?:城市|区县|地区)/.test(n.placeholder||''));
 for(const input of inputs){let p=input.parentElement;for(let i=0;p&&p!==doc.body&&i<8;i++,p=p.parentElement){if((p.textContent.match(/北京|上海|湖北|湖南|广东|河北/g)||[]).length>=2){panels.push(p);break}}}
 // Some selectors expose province/city/district tabs and no search input.
 // Find their smallest shared container; never use the document/body as a menu.
 const captions=[...doc.querySelectorAll('span,div,li,a,button,[role="tab"]')].filter(n=>visible(n)&&/^(省份|城市|县区|区县)$/.test(normalize(n.textContent)));
 const provinceTabs=captions.filter(n=>normalize(n.textContent)==='省份');
 for(const tab of provinceTabs){let p=tab.parentElement;for(let depth=0;p&&p!==doc.body&&depth<8;depth++,p=p.parentElement){
   if(p.querySelectorAll('input:not([readonly]):not([type="hidden"]),textarea').length>1)break;
   const names=new Set(captions.filter(n=>p.contains(n)).map(n=>normalize(n.textContent)));
   if(names.has('省份')&&names.has('城市')&&(names.has('县区')||names.has('区县'))){panels.push(p);break;}
 }}
 const unique=[...new Set(panels)].filter(p=>visible(p)&&p!==doc.documentElement&&p!==doc.body);
 // Tab strip alone is not a panel. Ascend only through a narrow ancestor until
 // it also contains actual region options; do not infer from a CSS class name.
 const expanded=unique.map(p=>{let node=p;for(let depth=0;node&&node!==doc.body&&depth<4;depth++,node=node.parentElement){
   if(node.querySelectorAll('input:not([readonly]):not([type="hidden"]),textarea').length>1)break;
   const leaves=locationLeaves(node),options=leaves.filter(n=>!captions.includes(n)&&!/^(?:省份|城市|县区|区县)+$/.test(normalize(n.textContent))&&n.textContent.trim().length>0&&n.textContent.trim().length<24&&!n.querySelector('input,textarea,select'));
   if(options.length>=1)return node;
 }return null;}).filter(Boolean);
 return [...new Set(expanded)].filter(p=>!expanded.some(q=>q!==p&&p.contains(q)));
}
function locationPopup(c) {
 const doc=c.el.ownerDocument,root=c.el.getRootNode();
 const candidates=locationPanelCandidates(doc);
 const ownedIDs=(c.el.getAttribute('aria-controls')||c.el.getAttribute('aria-owns')||'').split(/\s+/).filter(Boolean);
 const owned=ownedIDs.map(id=>root.getElementById?.(id)||doc.getElementById(id)).filter(Boolean);
 const row=fieldRow(c.el);
 const opening=state.locationOpening;
 const scoped=candidates.filter(panel=>owned.some(n=>n===panel||n.contains(panel))||(row&&row.contains(panel))||(opening?.el===c.el&&(!opening.previous.has(panel)||opening.panel===panel)));
 if(scoped.length!==1)return null;
 if(opening?.el===c.el)opening.panel=scoped[0];
 return scoped[0];
}
function locationAccepts(c,value) {
 const actual=geoText(readCurrent(c.el)),expected=geoText(value);if(!actual)return false;
 if(actual===expected)return true;
 const parts=locationParts(value),progress=state.locationProgress?.[searchKey(c)]||0;
 // Only an observed two-level picker may accept a shortened location. A
 // province/city/district picker must actually commit the known district.
 return parts.length>=2&&progress>=2&&!state.locationDistrict?.[searchKey(c)]&&!locationPopup(c)&&actual===parts.slice(0,progress).map(geoText).join('');
}
function locationStep(c,value) {
 if(locationAccepts(c,value))return {done:true};
 const panel=locationPopup(c),parts=locationParts(value),key=searchKey(c);
 state.locationProgress??={};state.locationPending??={};state.locationDistrict??={};
 if(panel&&locationLeaves(panel).some(n=>/^(县区|区县)$/.test(normalize(n.textContent))))state.locationDistrict[key]=true;
 let level=state.locationProgress[key]||0;
 const pending=state.locationPending[key];
 if(pending){
   const actual=geoText(readCurrent(c.el)),prefix=parts.slice(0,pending.level+1).map(geoText).join('');
   const signature=panel?locationLeaves(panel).map(n=>geoText(n.textContent)).join('|'):'';
   const next=parts[pending.level+1];
   const nextVisible=panel&&next&&locationLeaves(panel).some(n=>geoText(n.textContent)===geoText(next));
   // Invocation is not receipt: wait for a committed value or a changed menu
   // displaying the next exact known region before advancing the level.
   if((actual&&actual===prefix)||(nextVisible&&signature!==pending.signature)){
     level=pending.level+1;state.locationProgress[key]=level;delete state.locationPending[key];
   }else return {done:false};
 }
 if(locationAccepts(c,value))return {done:true};
 if(!panel||!parts[level])return {done:false};
 const expected=geoText(parts[level]);
 const leaves=locationLeaves(panel).filter(n=>geoText(n.textContent)===expected);
 if(leaves.length!==1)return {done:false};
 const node=leaves[0],w=node.ownerDocument.defaultView;
 const signature=locationLeaves(panel).map(n=>geoText(n.textContent)).join('|');
 node.dispatchEvent(new w.MouseEvent('mouseover',{bubbles:true}));node.dispatchEvent(new w.MouseEvent('mouseenter',{bubbles:false}));
 const clicked=widgetClick(node);
 if(clicked.invoked){state.locationPending[key]={level,signature};return {...clicked,click:rectFor(node),continue:true};}
 return {done:false};
}
function calendarPopup(c) {
 const doc=c.el.ownerDocument,root=c.el.getRootNode();
 const controlled=(c.el.getAttribute('aria-controls')||'').split(/\s+/).map(id=>root.getElementById?.(id)||doc.getElementById(id)).filter(n=>n&&visible(n));
 if(controlled.length===1)return controlled[0];
 const all=[...doc.querySelectorAll('.el-picker-panel,.ant-picker-dropdown,[role="dialog"],[data-calendar]')].filter(n=>visible(n)&&n.querySelector('[role="grid"],.el-date-table,.el-year-table,.el-month-table,.ant-picker-panel,[data-calendar-view]'));
 const outer=all.filter(n=>!all.some(other=>other!==n&&other.contains(n)));
 return outer.length===1?outer[0]:null;
}
function enabledCalendarNode(n) {return visible(n)&&!n.disabled&&n.getAttribute('aria-disabled')!=='true'&&!n.closest('[aria-disabled="true"],.disabled,.is-disabled,.ant-picker-cell-disabled');}
function calendarNavigation(panel,direction,large=false) {
 const backwards=direction<0,side=backwards?'prev':'next';
 const all=[...panel.querySelectorAll('button,[role="button"],.el-picker-panel__icon-btn')].filter(enabledCalendarNode);
 const labeled=all.filter(n=>{const label=[n.getAttribute('aria-label'),n.title,n.getAttribute('data-calendar-action')].join(' ');return (backwards?/previous|prev|上一|前一|上十|前十/:/next|下一|后一|下十|后十/).test(label)&&(!large||/year|decade|年/.test(label));});
 const scoped=all.filter(n=>large?(n.classList.contains('ant-picker-header-super-'+side+'-btn')||n.classList.contains(backwards?'d-arrow-left':'d-arrow-right')):n.classList.contains('ant-picker-header-'+side+'-btn')||n.classList.contains(backwards?'arrow-left':'arrow-right'));
 const preferred=large?labeled.filter(n=>/decade|十年/.test([n.getAttribute('aria-label'),n.title].join(' '))):labeled.filter(n=>/month|月/.test([n.getAttribute('aria-label'),n.title].join(' ')));
 const list=preferred.length?preferred:scoped.length?scoped:labeled;
 return list.length===1?list[0]:null;
}
function presentControl(c,value) {
 if(!/^(至今|现在|present|current)$/i.test(String(value).trim()))return null;
 const row=c.el.closest('.table-item,.el-form-item,.form-item,.ant-form-item,.form-group');
 const matches=[...(row?.querySelectorAll('input[type="checkbox"],[role="checkbox"]')||[])].filter(n=>visible(n)&&!n.disabled&&n.getAttribute('aria-disabled')!=='true'&&/^(至今|现在|present|current)$/i.test(labelFor(n)));
 return matches.length===1?matches[0]:null;
}
function calendarStep(c,value) {
 const present=presentControl(c,value);if(present){if(checked(present))return {done:true};return widgetClick(present);}
 const d=dateParts(value),monthOnly=!!c.el.closest('.el-date-editor--month')||/^(yyyy[-/]mm|yyyy年mm月)$/i.test(c.el.getAttribute('data-format')||c.el.placeholder||'');
 if(!d||!d.month||!monthOnly&&!d.day)return {done:false,missingDetail:true};
 if(accepts(c,value))return {done:true};
 const panel=calendarPopup(c);if(!panel)return {done:false};
 const yearPanel=[...panel.querySelectorAll('.el-year-table,.ant-picker-year-panel,[data-calendar-view="year"]')].find(visible);
 if(yearPanel) {
   const cells=[...yearPanel.querySelectorAll('td,[role="gridcell"],button')].filter(enabledCalendarNode).filter(n=>/^\d{4}$/.test(n.textContent.trim()));
   const matches=cells.filter(n=>+n.textContent.trim()===d.year).filter(n=>!cells.some(other=>other!==n&&n.contains(other)));
   if(matches.length===1)return widgetClick(matches[0].querySelector('a,.cell,.ant-picker-cell-inner')||matches[0]);
   const years=cells.map(n=>+n.textContent.trim());if(!years.length)return {done:false};
   const direction=d.year<Math.min(...years)?-1:d.year>Math.max(...years)?1:0;
   return direction?widgetClick(calendarNavigation(panel,direction,true)):{done:false};
 }
 const header=panel.querySelector('.el-date-picker__header,.ant-picker-header-view,[data-calendar-header],[role="heading"]');
 const headerText=header?.textContent||'';
 const year=Number(headerText.match(/\d{4}/)?.[0]);
 const monthMatch=headerText.match(/(?:年\s*|\d{4}\s*[-/]\s*)(\d{1,2})\s*月?/);
 const month=monthMatch?Number(monthMatch[1]):Number(headerText.match(/(?:^|\s)(\d{1,2})月/)?.[1]);
 const headerNodes=[...(header||panel).querySelectorAll('button,[role="button"],.el-date-picker__header-label,.ant-picker-year-btn,.ant-picker-month-btn')].filter(enabledCalendarNode);
 const yearButton=headerNodes.filter(n=>/选择年|choose.?year/i.test(n.getAttribute('aria-label')||'')||n.classList.contains('ant-picker-year-btn')||/^\d{4}年?$/.test(n.textContent.trim()));
 if(year&&year!==d.year&&yearButton.length===1)return widgetClick(yearButton[0]);
 const monthPanel=[...panel.querySelectorAll('.el-month-table,.ant-picker-month-panel,[data-calendar-view="month"]')].find(visible);
 if(monthPanel) {
   if(year!==d.year)return {done:false};
   const chinese=['一','二','三','四','五','六','七','八','九','十','十一','十二'];
   const cells=[...monthPanel.querySelectorAll('td,[role="gridcell"],button')].filter(enabledCalendarNode);
   const matches=cells.filter(n=>{const text=n.textContent.trim();return text===d.month+'月'||text===chinese[d.month-1]+'月'||n.getAttribute('data-month')===String(d.month)}).filter(n=>!cells.some(other=>other!==n&&n.contains(other)&&other.textContent.trim()===n.textContent.trim()));
   return matches.length===1?widgetClick(matches[0].querySelector('a,.cell,.ant-picker-cell-inner')||matches[0]):{done:false};
 }
 const cells=[...panel.querySelectorAll('[data-date],td[title],[role="gridcell"]')].filter(enabledCalendarNode);
 const exact=cells.filter(n=>{const text=n.getAttribute('data-date')||n.getAttribute('title')||n.getAttribute('aria-label')||'';const parts=dateParts(text);return parts&&parts.year===d.year&&parts.month===d.month&&parts.day===d.day;}).filter(n=>!cells.some(other=>other!==n&&n.contains(other)&&(other.getAttribute('data-date')||other.title||other.getAttribute('aria-label'))===(n.getAttribute('data-date')||n.title||n.getAttribute('aria-label'))));
 if(!monthOnly&&exact.length===1)return widgetClick(exact[0].querySelector('button,a,.cell,.ant-picker-cell-inner')||exact[0]);
 if(year===d.year&&month!==d.month) {
   const monthButtons=headerNodes.filter(n=>/选择月|choose.?month/i.test(n.getAttribute('aria-label')||'')||n.classList.contains('ant-picker-month-btn')||/^\d{1,2}月$/.test(n.textContent.trim()));
   if(monthButtons.length===1)return widgetClick(monthButtons[0]);
   if(month)return widgetClick(calendarNavigation(panel,d.month<month?-1:1));
 }
 if(!monthOnly&&year===d.year&&month===d.month) {
   const matches=cells.filter(n=>!n.closest('.prev-month,.next-month')&&(!n.classList.contains('ant-picker-cell')||n.classList.contains('ant-picker-cell-in-view'))&&/^\d{1,2}$/.test(n.textContent.trim())&&+n.textContent.trim()===d.day);
   return matches.length===1?widgetClick(matches[0].querySelector('button,a,.cell,.ant-picker-cell-inner')||matches[0]):{done:false};
 }
 return {done:false};
}

if(action==='repair') {
 const a=assignments[0],index=Number(a?.fieldID?.slice(1));let c=state.controls[index];
 if(c&&(!c.el.isConnected||!visible(c.el)||c.el.disabled)){const fresh=controls.filter(n=>n.label===c.label&&n.section===c.section&&n.entryIndex===c.entryIndex&&n.component===c.component);if(fresh.length===1){state.controls[index]=c=fresh[0];}}
 if(!c||!c.el.isConnected||blocked.test(c.label))return {done:false};
 const el=c.el,step=desiredSections.step,value=siteValue(c,a.value);
 if(value==null)return {done:false,missingDetail:true};
 if(step==='calendar')return calendarStep(c,a.value);
 if(step==='dismiss'){const search=state.searches?.[searchKey(c)];if(search&&!accepts(c,a.value)&&el.value===search.typed){Object.getOwnPropertyDescriptor(el.ownerDocument.defaultView.HTMLInputElement.prototype,'value').set.call(el,search.original);for(const name of ['input','change'])el.dispatchEvent(new el.ownerDocument.defaultView.Event(name,{bubbles:true}));}const w=el.ownerDocument.defaultView;el.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Escape',code:'Escape',keyCode:27,bubbles:true}));el.blur();for(const name of ['mousedown','mouseup','click'])el.ownerDocument.documentElement.dispatchEvent(new w.MouseEvent(name,{bubbles:true}));await Promise.resolve();return {done:true};}
 const equal=choiceEqual;
 if(step==='verify')return {done:accepts(c,a.value),missingDetail:!!state.pathLevels?.[a.fieldID]&&!readCurrent(el).trim()&&[...document.querySelectorAll('.el-cascader-menu')].filter(visible).length>state.pathLevels[a.fieldID]};
 if(step==='open') {
   if(geographicControl(el)&&!el.closest('.el-cascader')){state.locationOpening={el,previous:new Set(locationPanelCandidates(el.ownerDocument))};state.locationProgress??={};state.locationPending??={};state.locationProgress[searchKey(c)]=0;delete state.locationPending[searchKey(c)];}
   el.scrollIntoView({block:'center',behavior:'instant'});
   if(c.type==='date-widget'){const present=presentControl(c,a.value);if(present)return checked(present)?{done:true}:widgetClick(present);const d=dateParts(a.value);if(!d)return {done:false,missingDetail:true};return widgetClick(el);}
   if(c.type==='radio'){const n=c.nodes.find(n=>equal(labelFor(n),a.value));return n?pointer(n.closest('label')||n):{done:false};}
   return pointer(el.closest('.el-cascader')?.querySelector('.el-input__suffix')||el);
 }
 if(step==='choose') {
   if(geographicControl(el)&&!el.closest('.el-cascader'))return locationStep(c,a.value);
   if(el.closest('.el-select') && !el.readOnly && !readCurrent(el).trim()) {
     state.searches??={};state.searches[searchKey(c)]={original:el.value,typed:value};el.focus();el.select?.();el.ownerDocument.execCommand('insertText',false,value);await new Promise(r=>setTimeout(r,700));
   }
   const options=optionsFor(c);
   const matches=options.filter(n=>{const text=n.querySelector('.el-cascader-node__label')?.textContent||n.textContent;
     return optionEqual(c,text,value)||((c.label==='专业')&&normalize(text).startsWith(normalize(value))&&/^(普通本科|专业硕士|学术硕士|高职本科|专科|工学|理学)/.test(normalize(text).slice(normalize(value).length)))||(/最高.*(?:奖学金|荣誉)/.test(c.label)&&normalize(text).length>=2&&normalize(value).includes(normalize(text)));
   });
   if(matches.length===0&&el.closest('[class*="sd-Select-container"]')&&/学校|院校|专业/.test(c.label)&&!state.searches?.[searchKey(c)]) {
     state.searches??={};state.searches[searchKey(c)]={original:el.value,typed:value};el.focus();el.select?.();el.ownerDocument.execCommand('insertText',false,value);
     await new Promise(r=>setTimeout(r,350));return {done:false};
   }
   if(matches.length===1){state.searchPicks??={};state.searchPicks[searchKey(c)]=matches[0];return pointer(matches[0].querySelector('.el-radio,.el-checkbox')||matches[0]);}
   if(el.closest('.el-cascader')) {
     const compact=x=>normalize(x).replace(/[\/·,，]/g,'').replace(/省|市|自治区|特别行政区/g,'');
     const path=compact(value),progress=state.pathProgress?.[a.fieldID]||'';
     const rest=path.startsWith(progress)?path.slice(progress.length):path;
     const candidates=options.filter(n=>n.classList.contains('el-cascader-node') && (()=>{const text=compact(n.querySelector('.el-cascader-node__label')?.textContent||n.textContent);return text&&rest.startsWith(text)})());
     if(candidates.length===1){const n=candidates[0],text=compact(n.querySelector('.el-cascader-node__label')?.textContent||n.textContent);state.pathProgress??={};state.pathProgress[a.fieldID]=progress+text;state.pathLevels??={};state.pathLevels[a.fieldID]=(state.pathLevels[a.fieldID]||0)+1;return pointer(progress+text===path?(n.querySelector('.el-radio,.el-checkbox')||n):n,{continue:progress+text!==path});}
   }
   return {done:false,options:options.map(n=>n.textContent.trim()),debugMenus:[...document.querySelectorAll('[class*="sd-"]')].filter(n=>visible(n)&&/option|menu|dropdown|item/i.test(n.className)&&n.textContent.length<100).map(n=>({cls:n.className,role:n.getAttribute('role'),text:n.textContent}))};
 }

 if(step==='options'||step==='selectOption') {
   if(el.closest('.el-cascader')||geographicControl(el))return {options:[]}; // Never infer a missing geographic level.
   let candidates=[];
   if(el.tagName==='SELECT')candidates=[...el.options].filter(n=>!n.disabled&&n.value&&!/^(请选择|选择|select|please select)/i.test(n.textContent.trim())).map(n=>({node:n,label:n.textContent.trim(),value:n.value}));
   else if(c.type==='radio')candidates=c.nodes.map(n=>({node:n,label:labelFor(n),value:n.value}));
   else if(c.type==='combobox') {
     const all=optionsFor(c);
     const menus=new Set(all.map(n=>n.closest('[role="listbox"],.el-select-dropdown,.ant-select-dropdown,[class*="sd-Dropdown-dropdown"],[class*="sd-Dropdown-menu"],[class*="sd-Select-menu"]')||n.parentElement));
     if(menus.size===1)candidates=all.map(n=>({node:n,label:n.textContent.trim(),value:n.textContent.trim()}));
   }
   const signature=JSON.stringify(candidates.map(n=>[n.label,n.value]));
   if(step==='options')return {signature,options:candidates.map((n,i)=>({id:'o'+i,label:n.label}))};
   if(signature!==desiredSections.signature||!/^o\d+$/.test(desiredSections.optionID||''))return {done:false};
   const chosen=candidates[Number(desiredSections.optionID.slice(1))];if(!chosen||candidates.filter(n=>n.label===chosen.label).length!==1)return {done:false};
   state.searchPicks??={};state.searchPicks[searchKey(c)]=chosen.node;state.semanticChoices??=new Map();state.semanticChoices.set(c,{source:a.value,value:chosen.value,label:chosen.label});
   if(el.tagName==='SELECT') {
     Object.getOwnPropertyDescriptor(el.ownerDocument.defaultView.HTMLSelectElement.prototype,'value').set.call(el,chosen.value);
     for(const name of ['input','change'])el.dispatchEvent(new el.ownerDocument.defaultView.Event(name,{bubbles:true}));
     await new Promise(r=>setTimeout(r,150));return {done:accepts(c,a.value)};
   }
   return pointer(chosen.node.closest('label')||chosen.node);
 }

 if(step==='custom') {
   if(!/^(学校名称|专业)$/.test(c.label))return {done:false};
   const box=el.closest('.customInput_box');const toggle=box?.querySelector('input[type="checkbox"]');
   if(toggle&&!toggle.checked&&/其他/.test(toggle.closest('label')?.textContent||''))return pointer(toggle.closest('label'));
   return {done:false};
 }
 if(step==='customText') {
   if(el.readOnly||el.disabled||el.closest('.el-select')||!c.el.closest('.table-item')?.querySelector('input[type="checkbox"]:checked'))return {done:false};
   el.focus();el.select?.();el.ownerDocument.execCommand('insertText',false,a.value);el.blur();await Promise.resolve();return {done:accepts(c,a.value)};
 }
 if(step==='text') {const v=siteValue(c,a.value);el.focus();el.select?.();const ok=el.ownerDocument.execCommand('insertText',false,v);el.blur();await Promise.resolve();return {done:ok&&accepts(c,a.value)};}
 return {done:false};
}
const results=[];const checks=[];
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function emit(el){const w=el.ownerDocument.defaultView;el.dispatchEvent(new w.Event('input',{bubbles:true,composed:true}));el.dispatchEvent(new w.Event('change',{bubbles:true}));}
function setValue(el,value){const w=el.ownerDocument.defaultView;const proto=el.tagName==='TEXTAREA'?w.HTMLTextAreaElement.prototype:el.tagName==='SELECT'?w.HTMLSelectElement.prototype:w.HTMLInputElement.prototype;const setter=Object.getOwnPropertyDescriptor(proto,'value')?.set;if(setter)setter.call(el,value);else if(el.isContentEditable)el.textContent=value;emit(el);}
let processed=0;
for(const assignment of assignments||[]) {
  if((processed++ % 8)===0)await Promise.resolve();
  if(globalThis.__careerApplicationState?.token!==state.token||state.href!==location.href||state.document!==document) {results.push({id:assignment.fieldID,status:'page-changed'});break;}
  const match=/^f(\d+)$/.exec(assignment.fieldID); const c=match?state.controls[Number(match[1])]:null;
  if(!c||typeof assignment.value!=='string'||!assignment.value.trim()) {results.push({id:assignment.fieldID,status:'invalid'});continue;}
  const el=c.el;let value=assignment.value; if(el.closest('.el-date-editor--month')&&/^\d{4}[-/.]\d{2}/.test(value))value=value.slice(0,7).replace(/[/.]/g,'-'); const out={id:assignment.fieldID,label:c.label,status:'unsupported',...(assignment.note?{note:assignment.note}:{})};
  const present=presentControl(c,assignment.value);if(present){if(!checked(present))widgetClick(present);out.status=checked(present)?'filled':'unverified';results.push(out);continue;}
  if(!el.isConnected||!visible(el)||el.disabled||(el.readOnly&&!['combobox','date-widget'].includes(c.type))||c.signature!==[labelFor(el),el.name,el.id,el.type,el.getAttribute('type'),el.tagName,el.getAttribute('role'),sectionFor(el,labelFor(el))].join('|')||blocked.test([labelFor(el),el.name,el.id,el.autocomplete].join(' '))) {out.status='changed';results.push(out);continue;}
  const current=readCurrent(el);
  const placeholder=el.tagName==='SELECT'&&(!current||/^(请选择|选择|select|please select)/i.test(el.selectedOptions?.[0]?.textContent.trim()||''));
  if(accepts(c,assignment.value)) {out.status='preserved';results.push(out);continue;}
  value=siteValue(c,assignment.value);
  if(value==null){out.status='missing-detail';results.push(out);continue;}
  try {
    if(c.type==='date-widget'){out.status='widget-pending';}
    else if(c.type==='aria-radio'||c.type==='aria-checkbox') {
      const parts=valueParts(value);const choices=parts.map(v=>c.nodes.filter(n=>choiceEqual(n.getAttribute('aria-label')||n.textContent,v)||choiceEqual(n.getAttribute('data-value'),v)));
      if(choices.length&&choices.every(a=>a.length===1)&&(c.type!=='aria-radio'||choices.length===1)&&new Set(choices.map(a=>a[0])).size===choices.length){const wanted=new Set(choices.map(a=>a[0]));for(const n of c.nodes)if(c.type==='aria-checkbox'&&checked(n)!==wanted.has(n)||c.type==='aria-radio'&&wanted.has(n)&&!checked(n))n.click();await Promise.resolve();out.status=accepts(c,assignment.value)?'filled':'unverified';}else out.status='option-missing';
    } else if(el.tagName==='SELECT'&&el.multiple) {
      const parts=valueParts(value);const choices=parts.map(v=>[...el.options].filter(o=>!o.disabled&&(choiceEqual(o.textContent,v)||choiceEqual(o.value,v))));
      if(choices.length&&choices.every(a=>a.length===1)&&new Set(choices.map(a=>a[0])).size===choices.length){const selected=new Set(choices.map(a=>a[0]));for(const option of el.options)option.selected=selected.has(option);emit(el);await Promise.resolve();out.status=accepts(c,assignment.value)?'filled':'unverified';}else out.status='option-missing';
    } else if(el.tagName==='SELECT') {
      const candidates=[...el.options].filter(o=>!o.disabled&&(optionEqual(c,o.textContent,value)||optionEqual(c,o.value,value)));
      if(candidates.length===1){setValue(el,candidates[0].value);out.status=el.value===candidates[0].value?'filled':'unverified';}else out.status='option-missing';
    } else if(c.type==='radio'||c.type==='checkbox') {
      const values=valueParts(value);
      const matches=values.map(v=>c.nodes.filter(n=>choiceEqual(labelFor(n),v)||choiceEqual(n.value,v)));
      if(c.type==='checkbox'&&c.nodes.length===1&&/^(是|有|true|yes|1)$/i.test(value))matches.splice(0,matches.length,c.nodes);
      if(matches.length>0&&matches.every(m=>m.length===1)&&(c.type!=='radio'||matches.length===1)&&new Set(matches.map(m=>m[0])).size===matches.length) {
        const wanted=new Set(matches.map(m=>m[0]));for(const n of c.nodes)if(c.type==='checkbox'&&n.checked!==wanted.has(n)||c.type==='radio'&&wanted.has(n)&&!n.checked)n.click();
        await Promise.resolve();out.status=accepts(c,value)?'filled':'unverified';
      } else out.status='option-missing';
    } else if((c.type==='combobox'||el.getAttribute('role')==='combobox') && el.tagName!=='SELECT') {
      out.status='option-missing';
      if(!geographicControl(el)&&!el.closest('.el-select,.el-cascader,.ant-select,.arco-select')) {
        el.click();await Promise.resolve();
        const candidates=optionsFor(c).filter(n=>choiceEqual(n.textContent,value));
        if(candidates.length===1){candidates[0].click();await Promise.resolve();out.status=accepts(c,value)?'filled':'unverified';}
      } // Complex framework widgets use the scoped native pointer fallback.
    } else {
      if(c.type==='date'||c.type==='month') {
        const parts=value.match(/^(\d{4})[年/.\-](\d{1,2})(?:[月/.\-](\d{1,2}))?日?月?$/);
        if(!parts || Number(parts[2])<1||Number(parts[2])>12 || (c.type==='date'&&!parts[3])){out.status='unsupported';results.push(out);continue;}
        value=parts[1]+'-'+parts[2].padStart(2,'0');
        if(c.type==='date') {const date=new Date(Date.UTC(Number(parts[1]),Number(parts[2])-1,Number(parts[3])));if(date.getUTCDate()!==Number(parts[3])||date.getUTCMonth()!==Number(parts[2])-1){out.status='unsupported';results.push(out);continue;}value+='-'+parts[3].padStart(2,'0');}
      }
      if(el.maxLength>0&&value.length>el.maxLength&&/项目名称/.test(c.label)){const title=value.split(/[｜|：:（(]/)[0].trim();if(title&&title.length<=el.maxLength)value=title;}
      if(el.maxLength>0&&value.length>el.maxLength){out.status='too-long';results.push(out);continue;}
      el.focus();if(el.tagName!=='SELECT'&&el.type==='text'&&el.select){el.select();if(!el.ownerDocument.execCommand('insertText',false,value))setValue(el,value);}else setValue(el,value);await Promise.resolve();el.blur();await Promise.resolve();out.status=String(el.isContentEditable?el.textContent:el.value)===value?'filled':'unverified';
    }
  } catch {out.status='unsupported';}
  if(out.status==='filled') {
    const expected=c.nodes.map(n=>({node:n,value:n.isContentEditable?n.textContent:n.value,checked:checked(n)}));
    checks.push({out,expected,type:c.type,signature:c.signature,el});
  }
  results.push(out);
}
await pause(100);
for(const check of checks) {
  const same=state.href===location.href&&check.el.isConnected&&check.signature===[labelFor(check.el),check.el.name,check.el.id,check.el.type,check.el.getAttribute('type'),check.el.tagName,check.el.getAttribute('role'),sectionFor(check.el,labelFor(check.el))].join('|');
  if(!same||!check.expected.every(e=>['radio','checkbox','aria-radio','aria-checkbox'].includes(check.type)?checked(e.node)===e.checked:String(e.node.isContentEditable?e.node.textContent:e.node.value)===String(e.value)))check.out.status='unverified';
}
return {results,inaccessibleFrames};
