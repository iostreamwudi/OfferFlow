// Runs in an isolated WK content world. Page content is data, never instructions.
const visible = e => !!e && e.getClientRects().length > 0;
const text = e => (e?.innerText || e?.textContent || '').trim();
const noteID = raw => { try { return new URL(raw, location.href).pathname.match(/\/(?:explore|search_result)\/([a-f0-9]{24})(?:\/|$)/i)?.[1] || ''; } catch { return ''; } };
const host = location.hostname;
if (!(host === 'xiaohongshu.com' || host.endsWith('.xiaohongshu.com'))) return {error:'请先打开小红书搜索结果或笔记。'};
const verification = [...document.querySelectorAll('[class*="captcha"], [class*="verify-modal"], .login-container, .login-modal')].some(visible);
if (verification) return {error:'请先在网页完成登录或验证，再点击读取。'};
if (mode === 'open') {
  const selection = globalThis.offerFlowOpening = Symbol();
  if (noteID(location.href) === selectedID && [...document.querySelectorAll('#noteContainer, .note-detail-mask')].some(visible)) return {id:selectedID};
  // Return through the site's own history so its existing search feed and
  // scroll position survive switching between detail overlays.
  const feed = document.querySelector('section.note-item, .note-item');
  if (noteID(location.href) && feed && globalThis.offerFlowSearchPage) {
    history.back();
    for (let i=0; i<24 && noteID(location.href); i++) await new Promise(resolve => setTimeout(resolve, 50));
  }
  const findCard = () => [...document.querySelectorAll('.note-item')].find(card =>
    [...card.querySelectorAll('a[href]')].some(a => noteID(a.href) === selectedID));
  let card = findCard();
  const saved = globalThis.offerFlowCardPositions?.get(selectedID);
  if (!card && saved && saved.scroller.isConnected) {
    saved.scroller.scrollTop = saved.top;
    for (let i=0; i<10 && !card; i++) {
      await new Promise(resolve => setTimeout(resolve, 60));
      card = findCard();
    }
  }
  if (globalThis.offerFlowOpening !== selection) return {};
  if (!card) return {missing:true};
  const links = [...card.querySelectorAll('a[href]')].filter(a => noteID(a.href) === selectedID && visible(a));
  const link = links.find(a => a.matches('.cover')) || links[0];
  if (!link) return {missing:true};
  link.scrollIntoView({block:'center',inline:'nearest'});
  link.click();
  for (let i=0; i<20; i++) {
    if (globalThis.offerFlowOpening !== selection) return {};
    if (noteID(location.href) === selectedID) return {id:selectedID};
    await new Promise(resolve => setTimeout(resolve, 75));
  }
  return {missing:true};
}
if (mode === 'list') {
  const found = new Map();
  globalThis.offerFlowSearchPage = !noteID(location.href);
  const positions = globalThis.offerFlowCardPositions ??= new Map();
  for (const card of document.querySelectorAll('section.note-item, .note-item')) {
    if (!visible(card)) continue;
    const links = [...card.querySelectorAll('a[href]')].filter(a => noteID(a.href));
    // A hidden permalink can precede the search link used by the visible cover.
    const link = links.find(a => new URL(a.href).searchParams.get('xsec_token')) ||
      links.find(a => a.matches('.cover')) || links[0];
    const id = link && noteID(link.href);
    if (!id) continue;
    let scroller = card.parentElement;
    while (scroller && !(scroller.scrollHeight > scroller.clientHeight && /auto|scroll/.test(getComputedStyle(scroller).overflowY))) scroller = scroller.parentElement;
    scroller ||= document.scrollingElement;
    if (scroller) positions.set(id, {scroller, top:scroller.scrollTop + card.getBoundingClientRect().top - (scroller === document.scrollingElement ? 0 : scroller.getBoundingClientRect().top) - scroller.clientHeight / 3});
    found.set(id, {id, title:text(card.querySelector('.title')) || text(link) || '未显示标题', author:text(card.querySelector('.author .name, .author-wrapper .name, .name')), date:text(card.querySelector('.time, .date')), url:link.href});
  }
  return {url:location.href, cards:[...found.values()]};
}
const id = noteID(location.href);
const root = [...document.querySelectorAll('.note-detail-mask, .note-container, #noteContainer')].find(visible);
if (!id || !root) return {pending:!!id,error:'请先打开一篇笔记，等待正文加载后再读取。'};
const desc = root.querySelector('#detail-desc, .desc, .note-text');
const title = text(root.querySelector('#detail-title, .title'));
const body = text(desc);

const imgs = new Map();
const noteImages = [...root.querySelectorAll('.swiper-slide img, .note-slider img, .media-container img')];
noteImages.sort((a,b) => {
  const index = img => { const raw = img.closest('[data-swiper-slide-index]')?.getAttribute('data-swiper-slide-index'); return raw == null ? Number.MAX_SAFE_INTEGER : Number(raw); };
  return index(a)-index(b);
});
for (const img of noteImages) {
  const url = img.getAttribute('data-src') || img.currentSrc || img.src;
  try {
    const u = new URL(url);
    if (u.protocol === 'http:') u.protocol = 'https:';
    if (u.protocol !== 'https:' || !(u.hostname === 'xhscdn.com' || u.hostname.endsWith('.xhscdn.com'))) continue;
    const key = u.origin + u.pathname;
    if (!imgs.has(key)) imgs.set(key, u.href);
  } catch {}
}
if (!body && !imgs.size) return {pending:true, error:'笔记正文和图片尚未加载，请展开笔记后重试。'};
const expansion = [...root.querySelectorAll('button, span, a')].some(e => visible(e) && /^(展开全文|展开|更多)$/.test(text(e)) && !!e.closest('.note-content, .desc'));
return {url:location.href, id, title:title || '未显示标题', author:text(root.querySelector('.author-container .username, .author .username, .author-wrapper .name')), date:text(root.querySelector('.bottom-container .date, .date')), body, images:[...imgs.values()], partial:expansion, aiNotice: /可能含\s*AI\s*生成内容/i.test(text(root))};
