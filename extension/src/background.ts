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

function bgLog(msg: string) {
  console.log('[MajorTom BG]', msg);
  fetch('http://localhost:7777', { method: 'POST', body: `[BG] ${msg}` }).catch(() => {});
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.type === 'FETCH_SUBTITLE') {
    bgLog(`fetching ${msg.url.substring(0, 100)}`);
    fetch(msg.url, { credentials: 'include' })
      .then(async r => {
        const text = await r.text();
        bgLog(`fetch status:${r.status} length:${text.length} url:${msg.url.substring(0, 80)}`);
        return text;
      })
      .then(text => sendResponse({ content: text }))
      .catch(e => {
        bgLog(`fetch error: ${e?.message} url:${msg.url.substring(0, 80)}`);
        sendResponse({ content: '' });
      });
    return true;
  }
});
