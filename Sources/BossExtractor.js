// Reads rendered DOM only. No cookies, credentials, private endpoints or page scripts are read.
(() => {
  const clean = value => (value || '').replace(/\u00a0/g, ' ').replace(/[ \t]+/g, ' ').trim();
  const visible = el => !!el && !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length) && getComputedStyle(el).visibility !== 'hidden' && getComputedStyle(el).display !== 'none';
  const text = el => visible(el) ? clean(el.innerText) : '';
  const first = (root, selectors) => {
    for (const selector of selectors.split(',')) {
      for (const el of root.querySelectorAll(selector.trim())) { const value = text(el); if (value) return value; }
    }
    return '';
  };
  const salaryText = value => /[\uE000-\uF8FF]/.test(value) ? '' : value;
  const canonical = raw => {
    try {
      const url = new URL(raw, location.href);
      if (!/^(www\.|m\.)?zhipin\.com$/.test(url.hostname) || !/^\/job_detail\/[\w~-]+\.html$/.test(url.pathname)) return '';
      return 'https://www.zhipin.com' + url.pathname;
    } catch { return ''; }
  };
  const gateText = text(document.body);
  const gated = /安全验证|请完成验证|访问异常|访问过于频繁|请先通过验证/.test(gateText);
  const cards = [];
  const seen = new Set();
  for (const link of document.querySelectorAll('a[href*="/job_detail/"]')) {
    const url = canonical(link.href);
    const title = first(link, '.job-name, .job-title') || text(link);
    if (!url || seen.has(url) || !title || /查看更多|查看详情|立即沟通/.test(title) || title.length > 180) continue;
    let root = link.closest('.job-card-wrap, .job-card-wrapper, .job-card-box');
    if (!root) {
      let parent = link.parentElement;
      for (let n = 0; parent && n < 6; n++, parent = parent.parentElement) {
        if (parent.querySelector('a[href*="/gongsi/"]') && parent.querySelectorAll('a[href*="/job_detail/"]').length <= 2) { root = parent; break; }
      }
    }
    if (!root || !visible(root)) continue;
    const company = first(root, '.company-name, .boss-name .company-name, a[href*="/gongsi/"]');
    if (!company) continue;
    const tags = Array.from(root.querySelectorAll('.tag-list li, .job-labels span, .job-tag')).map(text).filter(Boolean);
    const area = first(root, '.job-area, .job-area-wrapper, .area-text, .company-location') || (text(root).match(/(?:上海|北京|深圳|广州|杭州|成都|苏州|南京|武汉|西安)(?:[·•][^\n]{1,40})?/) || [''])[0];
    const experience = tags.filter(t => /年|经验|应届|在校|本科|专科|大专|硕士|博士|学历|天\/周|个月/.test(t)).join(' · ');
    cards.push({ title, company, city: area, salary: salaryText(first(root, '.salary, .salary-text, .job-salary')), experience, tags: [...new Set(tags)].slice(0, 8), url });
    seen.add(url);
  }
  let detail = null;
  const currentURL = canonical(location.href);
  if (currentURL) {
    const jd = first(document, '.job-sec-text, .job-detail-body .desc, .job-detail-section .desc, .job-detail .job-description');
    const restricted = /登录查看完整|登录后查看完整|展开全部.*登录|登录后可查看/.test(gateText) || /登录|扫码|验证/.test(jd.slice(0, 25));
    const title = first(document, '.job-banner .name h1, .job-banner h1, .job-title h1, h1');
    const company = first(document, '.sider-company .company-info a, .company-info .name, .company-name, .job-company .company-name');
    const banner = first(document, '.job-banner, .job-primary');
    const salary = salaryText(first(document, '.job-banner .salary, .job-primary .salary, .job-banner .salary-text')) || (banner.match(/\d+(?:\.\d+)?\s*[-–]\s*\d+(?:\.\d+)?[Kk万千元](?:[·•]\d+薪)?/) || [''])[0];
    const city = first(document, '.job-banner .text-city, .job-primary .text-city') || (banner.match(/上海|北京|深圳|广州|杭州|成都|苏州|南京|武汉|西安/) || [''])[0];
    const experience = (banner.match(/\d+\s*[-–]\s*\d+年|\d+年以上|经验不限|在校[\/／]应届/) || [''])[0];
    detail = { title, company, jd, salary, city, experience, url: currentURL, complete: !!jd && jd.length >= 30 && !restricted && !gated };
  }
  const previewLink = Array.from(document.querySelectorAll('a[href*="/job_detail/"]')).find(el => visible(el) && /查看更多信息|查看职位详情/.test(text(el)));
  return JSON.stringify({ pageURL: location.href, gated, cards, detail, previewURL: previewLink ? canonical(previewLink.href) : null });
})()
