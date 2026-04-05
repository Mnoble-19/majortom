setInterval(() => {
  fetch(chrome.runtime.getURL('content.js'))
    .then(r => r.text())
    .then(text => {
      const hash = text.length.toString();
      chrome.storage.session.get('buildHash', (data) => {
        if (data.buildHash && data.buildHash !== hash) {
          chrome.runtime.reload();
        }
        chrome.storage.session.set({ buildHash: hash });
      });
    })
    .catch(() => {});
}, 2000);

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.set({
    majortom: {
      enabled: true,
      primaryLang: 'de',
      secondaryLang: 'en',
      savedWords: [],
    },
  });
});

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.type === 'FETCH_SUBTITLE') {
    fetch(msg.url, { credentials: 'include' })
      .then(async r => {
        const text = await r.text();
        console.log('[MajorTom BG] fetch', msg.url.substring(0, 80), 'status:', r.status, 'length:', text.length);
        return text;
      })
      .then(text => sendResponse({ content: text }))
      .catch(e => {
        console.error('[MajorTom BG] fetch error:', e);
        sendResponse({ content: '' });
      });
    return true;
  }
});
