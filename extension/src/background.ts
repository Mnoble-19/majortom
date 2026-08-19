import { BgRequest, BgResponse } from './shared/types';
import { DEFAULT_SETTINGS } from './shared/config';
import { translate } from './translate/deepl';

/** Subtitle files are text; anything much bigger than this is not one. */
const MAX_BODY_BYTES = 8 * 1024 * 1024;

chrome.runtime.onInstalled.addListener(async () => {
  const existing = await chrome.storage.local.get('mt_settings');
  if (!existing.mt_settings) {
    await chrome.storage.local.set({ mt_settings: DEFAULT_SETTINGS });
  }
});

async function handle(msg: BgRequest): Promise<BgResponse> {
  switch (msg.type) {
    case 'FETCH': {
      const res = await fetch(msg.url, {
        credentials: 'include',
        headers: msg.init?.headers,
      });
      if (!res.ok) return { ok: false, error: `HTTP ${res.status}` };

      const len = Number(res.headers.get('content-length') || 0);
      if (len > MAX_BODY_BYTES) return { ok: false, error: 'response too large' };

      return { ok: true, data: await res.text() };
    }

    case 'TRANSLATE': {
      if (!msg.key?.trim()) return { ok: false, error: 'no API key configured' };
      return { ok: true, data: await translate(msg.texts, msg.source, msg.target, msg.key) };
    }

    default:
      return { ok: false, error: 'unknown message' };
  }
}

chrome.runtime.onMessage.addListener((msg: BgRequest, _sender, sendResponse) => {
  handle(msg)
    .then(sendResponse)
    .catch((e: Error) => sendResponse({ ok: false, error: e?.message || String(e) }));
  return true; // keep the channel open for the async reply
});
