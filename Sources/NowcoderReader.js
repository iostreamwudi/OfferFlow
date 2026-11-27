// Only read rendered source content; comments, recommendations and page scripts are not source text.
const visible = e => !!e && e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden';
const text = e => (e?.innerText || e?.textContent || '').trim();
const parse = raw => {
  try {
    const u = new URL(raw, location.href);
    if (!['http:','https:'].includes(u.protocol) || u.username || u.password || !(u.hostname === 'nowcoder.com' || u.hostname.endsWith('.nowcoder.com'))) return null;
    const post = u.pathname.match(/^\/discuss\/(\d+)\/?$/);
    const feed = u.pathname.match(/^\/feed\/main\/detail\/([a-f0-9]{32})\/?$/i);
    if (!post && !feed) return null;
    return {id:(post ? 'discuss:' : 'feed:') + (post || feed)[1], url:'https://www.nowcoder.com' + u.pathname.replace(/\/$/,'')};
  } catch { return null; }
};
if (!(location.hostname === 'nowcoder.com' || location.hostname.endsWith('.nowcoder.com'))) return {error:'请先打开牛客搜索结果或帖子。'};
if ([...document.querySelectorAll('[class*="captcha"], .login-modal, .login-dialog, [role="dialog"]')].some(e => visible(e) && /登录|验证/.test(text(e)))) return {error:'请在网页完成登录或验证后再读取。'};
if (mode === 'list') {
  const found = new Map();
  const root = document.querySelector('.search-content, .search-result, .search-main, .nk-main, main') || document.body;
  for (const a of root.querySelectorAll('a[href]')) {
    const item = parse(a.href);
    if (!item || !visible(a) || a.closest('.hotList, .recommend-list, .comment-list, .reply-list')) continue;
    let card = a.closest('.feed-item, .feed-item-container, .discuss-item, li, article') || a.parentElement;
    // New feed layouts have utility classes only. Expand within a single source item.
    for (let n = card.parentElement, depth = 0; n && depth < 6 && n !== root && n !== document.body; n = n.parentElement, depth++) {
      const ids = new Set([...n.querySelectorAll('a[href]')].map(link => parse(link.href)?.id).filter(Boolean));
      if (ids.size !== 1 || !ids.has(item.id)) break;
      card = n;
    }
    const title = text(card.querySelector('.feed-title, .content-title, .discuss-title, h2, h3')) || text(a);
    if (!title || /^\(?\d+\)?$/.test(title)) continue;
    if (!found.has(item.id)) found.set(item.id, {...item, title:title.slice(0,300), author:text(card.querySelector('.user-name, .user-nickname, .name-text, .discuss-author')), date:text(card.querySelector('.time-text, .show-time, .feed-time, .discuss-time, time'))});
  }
  return {url:location.href, cards:[...found.values()]};
}
const item = parse(location.href);
if (!item) return {error:'请先打开一篇牛客帖子，再读取本篇图文。'};
const root = ['.main-content-container', '.discuss-detail', '.post-detail', 'main'].map(s => document.querySelector(s)).find(visible) || document;
const bodyElement = [...root.querySelectorAll('.nc-post-content, .nc-slate-editor-content, .feed-content-text, .post-topic-des, .discuss-content')].find(visible);
if (!bodyElement && !root.querySelector('.feed-img img')) return {pending:true, error:'帖子正文尚未加载，或当前帖子需要登录/展开后查看。请在网页中处理后重试。'};
const body = text(bodyElement);
const title = text(root.querySelector('.content-post-title h1, .post-title, h1')) || document.title.replace(/_牛客网.*$/,'').trim();
const images = new Map();
const feed = !bodyElement || bodyElement.matches('.feed-content-text');
const media = feed ? (bodyElement || root.querySelector('.feed-img')).closest('section') || root : bodyElement;
for (const img of media.querySelectorAll(feed ? '.feed-content-text img, .feed-img img' : 'img')) {
  try {
    const raw = img.getAttribute('data-src') || img.currentSrc || img.src;
    if (!raw) continue;
    const u = new URL(raw, location.href);
    if (!(u.hostname === 'nowcoder.com' || u.hostname.endsWith('.nowcoder.com')) || !['http:','https:'].includes(u.protocol)) continue;
    u.protocol = 'https:';
    images.set(u.origin + u.pathname, u.href);
  } catch {}
}
if (!body && !images.size) return {pending:true, error:'帖子正文和图片尚未加载，请展开帖子后重试。'};
return {...item, title:title || '牛客面经', body, author:text(root.querySelector('.content-user-info .name-text, .post-detail .user-name, .post-header .name')), date:text(root.querySelector('.content-user-info .time-text, .post-time')), images:[...images.values()], aiNotice:/可能含\s*AI\s*生成内容/i.test(body)};
