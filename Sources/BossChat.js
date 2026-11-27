(args) => {
  const visible = el => el && !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length) && getComputedStyle(el).visibility !== 'hidden' && getComputedStyle(el).display !== 'none';
  const norm = text => (text || '').normalize('NFKC').replace(/\s+/g, '');
  // Compare draft layout separately from fuzzy company/title matching.
  const draftText = text => (text || '').replace(/\r\n?/g, '\n').replace(/\u00a0/g, ' ');
  const sameDraft = (a, b) => draftText(a) === draftText(b);
  const url = new URL(location.href);
  const expected = new URL(args.jobURL);
  if (!/^(www\.)?zhipin\.com$/.test(url.hostname) || url.protocol !== 'https:') return {status:'wrong_site'};
  const expectedID = expected.pathname.match(/^\/job_detail\/([\w~-]+)\.html$/)?.[1];
  if (!expectedID) return {status:'invalid_job'};
  const batch = args.operation.startsWith('batch');
  if (batch && Array.from(document.querySelectorAll('[class*="verify"],[class*="captcha"],.dialog-container,.dialog-wrap,.toast,.toast-content'))
    .some(el => visible(el) && /验证码|安全验证|操作频繁|沟通.*上限|今日.*上限|登录后/.test(el.innerText || ''))) return {status:'gated'};
  if (args.operation === 'open' || args.operation === 'batchPreflight' || args.operation === 'batchOpen') {
    if (url.pathname !== expected.pathname) return {status:'wrong_job'};
    const roots = Array.from(document.querySelectorAll('.job-banner, .job-primary'));
    const scope = roots.length ? roots : [document];
    const button = scope.flatMap(root => Array.from(root.querySelectorAll('a,button'))).find(el => visible(el) && /^(立即沟通|继续沟通|立即开聊)$/.test((el.innerText || '').trim()));
    if (!button) return {status:'no_chat_button'};
    if (batch && /继续沟通/.test(button.innerText || '')) return {status:'already_contacted'};
    if (args.operation === 'batchPreflight') return {status:'ready'};
    button.click();
    return {status:'opening'};
  }
  if (url.pathname !== '/web/geek/chat') return {status:'waiting_chat'};
  // BOSS may remove jobId from the address after selecting the conversation.
  // An explicit conflicting id is rejected; the rendered active pane must also match below.
  const activeJobID = url.searchParams.get('jobId');
  if (activeJobID && activeJobID !== expectedID) return {status:'wrong_conversation'};
  const editors = Array.from(document.querySelectorAll('[contenteditable="true"],textarea')).filter(visible).filter(el => !el.disabled && !el.readOnly);
  if (editors.length !== 1) return {status:'no_unique_editor'};
  const editor = editors[0];
  let parent = editor.parentElement;
  let verified = false;
  for (let n = 0; parent && n < 9; n++, parent = parent.parentElement) {
    if (parent === document.body || parent.querySelector('input[placeholder*="联系人"]')) break;
    const context = norm(parent.innerText);
    if (context.includes(norm(args.company)) && context.includes(norm(args.title))) { verified = true; break; }
  }
  if (!verified) return {status:'identity_unverified'};
  const current = editor.tagName === 'TEXTAREA' ? editor.value : editor.innerText;
  if (args.operation === 'capture') return {status:'captured',text:current};
  if (batch) {
    // Require an actual job header/link in the active pane, not a mention in old messages.
    const links = Array.from(parent.querySelectorAll('a[href*="/job_detail/"]')).filter(visible);
    const linkedJob = links.some(el => { try { return new URL(el.href,location.href).pathname === expected.pathname; } catch { return false; } });
    const titledJob = Array.from(parent.querySelectorAll('.job-name,.job-title,.job-card *,.job-info *,.chat-job *')).filter(visible)
      .some(el => norm(el.innerText) === norm(args.title));
    if (!linkedJob && !(activeJobID === expectedID && titledJob)) return {status:'identity_unverified'};
    const outgoing = Array.from(parent.querySelectorAll('.item-myself,.message-item.is-self,.message-item.self,.message-item.me,.message-item.item-right,.message-item.message-right,.message-item-right')).filter(visible);
    const matches = outgoing.filter(el => {
      const parts = [el, ...el.querySelectorAll('.text,.text-message,.message-text,.message-content')];
      return parts.some(part => norm(part.innerText) === norm(args.text));
    });
    const receipt = window.__careerAIBatchReceipt;
    if (args.operation === 'batchReceipt') {
      if (!receipt || receipt.job !== expectedID || receipt.text !== args.text) return {status:'receipt_missing'};
      if (matches.some(el => el.querySelector('.send-fail,.send-error,.message-error,.retry') || /发送失败/.test(el.innerText))) return {status:'send_failed'};
      const settled = matches.filter(el => !el.matches('.sending,.pending,.loading') && !el.querySelector('.sending,.pending,.loading'));
      return !current.trim() && settled.length > receipt.before ? {status:'sent_visible'} : {status:'awaiting_receipt'};
    }
    if (outgoing.length) return {status:'already_contacted'};
    if (args.operation === 'batchProbe') return {status:current.trim() && !sameDraft(current, args.text) ? 'occupied' : 'ready'};
    if (args.operation === 'batchSend') {
      if (!args.text.trim() || !sameDraft(current, args.text)) return {status:'draft_changed'};
      if (receipt && receipt.job === expectedID && receipt.text === args.text) return {status:'send_already_attempted'};
      const buttons = Array.from(parent.querySelectorAll('button,a,[role="button"],.btn-send,.send-btn')).filter(el =>
        visible(el) && /^(发送|发送消息)$/.test((el.innerText || '').trim()) && !el.disabled && el.getAttribute('aria-disabled') !== 'true' && !/disabled/.test(el.className || ''));
      // Nested icon/text wrappers may exist; only a unique actionable send button is allowed.
      const unique = buttons.filter(el => !buttons.some(other => other !== el && other.contains(el)));
      if (unique.length !== 1) return {status:'no_unique_send_button'};
      window.__careerAIBatchReceipt = {job:expectedID,text:args.text,before:matches.length};
      unique[0].click();
      return {status:'send_started'};
    }
  }
  if (!['fill','probe','batchFill'].includes(args.operation)) return {status:'unsupported_operation'};
  if (sameDraft(current, args.text)) return {status:'filled',characters:args.text.length};
  if (current.trim() && !args.overwrite) return {status:'occupied'};
  if (args.operation === 'probe') return {status:'ready'};
  editor.focus();
  if (editor.tagName === 'TEXTAREA') {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set.call(editor,args.text);
  } else {
    // innerText's setter creates real line breaks in a contenteditable editor.
    // textContent alone collapses newlines under the site's normal white-space CSS.
    editor.innerText = draftText(args.text);
  }
  editor.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:args.text}));
  editor.dispatchEvent(new Event('change',{bubbles:true}));
  editor.scrollIntoView({block:'center'});
  const actual = editor.tagName === 'TEXTAREA' ? editor.value : editor.innerText;
  return sameDraft(actual, args.text) ? {status:'filled',characters:args.text.length} : {status:'fill_failed'};
}
