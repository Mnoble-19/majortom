import { BgRequest, BgResponse } from './types';
import { DEFAULT_SETTINGS } from './config';

/** Subtitle files are text; anything much bigger than this is not one. */
const MAX_BODY_BYTES = 8 * 1024 * 1024;

chrome.runtime.onInstalled.addListener(async () => {
  const existing = await chrome.storage.local.get('mt_settings');
  if (!existing.mt_settings) {
    await chrome.storage.local.set({ mt_settings: DEFAULT_SETTINGS });
  }
});

/* ── DeepL ────────────────────────────────────────────────────────────────── */

/** Free keys are suffixed `:fx` and live on a different host. */
function deeplEndpoint(key: string): string {
  return key.trim().endsWith(':fx')
    ? 'https://api-free.deepl.com/v2/translate'
    : 'https://api.deepl.com/v2/translate';
}

async function translate(
  texts: string[], source: string, target: string, key: string,
): Promise<string[]> {
  const body: Record<string, unknown> = {
    text: texts,
    target_lang: target,
    preserve_formatting: true,
  };
  // Omitting source_lang lets DeepL auto-detect, which is what '' means here.
  if (source) body.source_lang = source;

  const res = await fetch(deeplEndpoint(key), {
    method: 'POST',
    headers: {
      'Authorization': `DeepL-Auth-Key ${key.trim()}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    // These three are the ones worth explaining in the UI.
    if (res.status === 403) throw new Error('DeepL rejected the API key (403)');
    if (res.status === 456) throw new Error('DeepL quota exhausted for this billing period (456)');
    if (res.status === 429) throw new Error('DeepL rate limit hit (429) — try again shortly');
    throw new Error(`DeepL ${res.status}: ${detail.slice(0, 160)}`);
  }

  const json = await res.json() as { translations?: Array<{ text: string }> };
  return (json.translations || []).map(t => t.text);
}

/* ── Router ───────────────────────────────────────────────────────────────── */

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
