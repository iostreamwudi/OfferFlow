// Only uses the public document and the website's normal copy event. No network
// endpoints, application stores, cookies, or system clipboard are accessed.
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const url = new URL(location.href);
if (url.origin !== 'https://my.feishu.cn' || url.pathname !== '/base/ZBpybxIDfayhQssBHnYc9ZjEn7c' ||
    url.searchParams.get('table') !== 'tblCNHUxBdaYvYvx' || url.searchParams.get('view') !== 'vewIPUzblP') {
  return { state: 'wrong-page' };
}
const bodyText = document.body?.innerText || '';
const canvases = [...document.querySelectorAll('canvas')].map(el => ({ el, rect: el.getBoundingClientRect() }))
  .filter(x => x.rect.width > 400 && x.rect.height > 100)
  .sort((a, b) => b.rect.width * b.rect.height - a.rect.width * a.rect.height);
const ready = canvases.length > 0 && !/数据加载中|正在加载数据/.test(bodyText);
if (mode === 'probe') return {state: ready ? 'ready' : 'waiting'};
if (!ready || /已复制\s*[\d,]+\s*条记录/.test(bodyText)) return {state: 'waiting'};
const grid = canvases[0];
const x = grid.rect.left + Math.min(220, grid.rect.width / 3);
const y = grid.rect.top + Math.min(70, grid.rect.height / 3);
const hit = document.elementFromPoint(x, y) || grid.el;
for (const type of ['mousedown', 'mouseup', 'click']) hit.dispatchEvent(new MouseEvent(type, {bubbles:true, cancelable:true, clientX:x, clientY:y, button:0, buttons:type === 'mousedown' ? 1 : 0}));
await pause(100);
const target = document.activeElement || hit;
target.dispatchEvent(new KeyboardEvent('keydown', {bubbles:true, cancelable:true, key:'a', code:'KeyA', keyCode:65, which:65, metaKey:true}));
target.dispatchEvent(new KeyboardEvent('keyup', {bubbles:true, cancelable:true, key:'a', code:'KeyA', keyCode:65, which:65, metaKey:true}));
await pause(200);
const transfer = new DataTransfer();
const event = new ClipboardEvent('copy', {clipboardData:transfer, bubbles:true, cancelable:true});
(document.activeElement || hit).dispatchEvent(event);
await pause(600);
const text = transfer.getData('text/plain');
const html = transfer.getData('text/html');
const copiedDocument = new DOMParser().parseFromString(html, 'text/html');
const table = copiedDocument.querySelector('table.byte-bitable[data-byte-bitable]');
let copyMetadata = null;
try { copyMetadata = JSON.parse(table?.getAttribute('data-byte-bitable') || 'null'); } catch (_) {}
const metadataMatchesSource = copyMetadata?.tableId === 'tblCNHUxBdaYvYvx' && copyMetadata?.viewId === 'vewIPUzblP';
const headers = metadataMatchesSource && Array.isArray(copyMetadata.header) ? copyMetadata.header.map(x => x.name) : [];
const afterText = document.body?.innerText || '';
const copyCountMatch = afterText.match(/已复制\s*([\d,]+)\s*条记录/);
const copiedCount = copyCountMatch ? Number(copyCountMatch[1].replaceAll(',', '')) : 0;
const copiedRows = [...(table?.querySelectorAll('tr') || [])];
const fieldIDs = copyMetadata?.header?.map(x => x.id) || [];
const structureValid = metadataMatchesSource && fieldIDs.length === 23 &&
  fieldIDs.every(x => typeof x === 'string' && x.length > 0) && new Set(fieldIDs).size === 23 &&
  copiedCount > 0 && copiedRows.length === copiedCount &&
  copiedRows.every(row => row.children.length === 23 && [...row.children].every(cell => cell.tagName === 'TD'));
if (location.href !== url.href || !structureValid) return {state:'invalid-structure'};
return {state: text ? 'copied' : 'empty', text, headers, count:copiedCount};
