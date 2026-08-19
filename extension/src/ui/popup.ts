import { Settings, VocabEntry } from '../shared/types';
import { SOURCE_LANGS, TARGET_LANGS } from '../shared/config';
import {
  getSettings, setSettings, getVocab, toggleStar, removeWord, clearCache,
} from '../shared/storage';
import { bgTranslate } from '../shared/messaging';

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;

let settings: Settings;
let vocab: VocabEntry[] = [];
let host = '';

/* ── Tabs ─────────────────────────────────────────────────────────────────── */

document.querySelectorAll<HTMLButtonElement>('nav button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('nav button').forEach(b => b.classList.remove('on'));
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('on'));
    btn.classList.add('on');
    $(`tab-${btn.dataset.tab}`).classList.add('on');
  });
});

/* ── Settings ─────────────────────────────────────────────────────────────── */

function fillSelect(el: HTMLSelectElement, opts: Array<[string, string]>, value: string) {
  el.textContent = '';
  for (const [v, label] of opts) {
    const o = document.createElement('option');
    o.value = v;
    o.textContent = label;
    el.appendChild(o);
  }
  el.value = value;
}

function bindToggle(id: keyof Settings) {
  const el = $<HTMLInputElement>(id);
  el.checked = Boolean(settings[id]);
  el.addEventListener('change', async () => {
    settings = await setSettings({ [id]: el.checked } as Partial<Settings>);
  });
}

async function currentHost(): Promise<string> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  try {
    return new URL(tab?.url || '').hostname.replace(/^www\./, '');
  } catch {
    return '';
  }
}

async function initSettings() {
  settings = await getSettings();
  host = await currentHost();

  $('siteLabel').textContent = host || 'no active site';

  const siteToggle = $<HTMLInputElement>('siteToggle');
  const enabledHere = settings.enabled && !settings.disabledHosts.includes(host);
  siteToggle.checked = enabledHere;
  siteToggle.disabled = !host;
  siteToggle.addEventListener('change', async () => {
    const disabled = new Set(settings.disabledHosts);
    if (siteToggle.checked) disabled.delete(host); else disabled.add(host);
    settings = await setSettings({ enabled: true, disabledHosts: [...disabled] });
  });

  fillSelect($<HTMLSelectElement>('sourceLang'), SOURCE_LANGS, settings.sourceLang);
  fillSelect($<HTMLSelectElement>('targetLang'), TARGET_LANGS, settings.targetLang);
  $('sourceLang').addEventListener('change', async e => {
    settings = await setSettings({ sourceLang: (e.target as HTMLSelectElement).value });
  });
  $('targetLang').addEventListener('change', async e => {
    settings = await setSettings({ targetLang: (e.target as HTMLSelectElement).value });
  });

  (['showSecondary', 'blurSecondary', 'autoPause', 'loopCue', 'hideNativeCaptions'] as const)
    .forEach(bindToggle);

  const font = $<HTMLInputElement>('fontScale');
  font.value = String(settings.fontScale);
  font.addEventListener('input', async () => {
    settings = await setSettings({ fontScale: Number(font.value) });
  });

  const offset = $<HTMLInputElement>('offsetPct');
  offset.value = String(settings.offsetPct);
  offset.addEventListener('input', async () => {
    settings = await setSettings({ offsetPct: Number(offset.value) });
  });

  const key = $<HTMLInputElement>('deeplKey');
  key.value = settings.deeplKey;
  let keyTimer: number;
  key.addEventListener('input', () => {
    clearTimeout(keyTimer);
    keyTimer = window.setTimeout(async () => {
      settings = await setSettings({ deeplKey: key.value.trim() });
    }, 350);
  });

  $('testKey').addEventListener('click', () => void testKey());
  $('clearCache').addEventListener('click', async () => {
    await clearCache();
    setStatus('Translation cache cleared.', 'ok');
  });
}

function setStatus(msg: string, cls: 'ok' | 'err' | 'busy') {
  const el = $('keyStatus');
  el.textContent = msg;
  el.className = `status ${cls}`;
}

async function testKey() {
  const key = $<HTMLInputElement>('deeplKey').value.trim();
  if (!key) { setStatus('Enter a key first.', 'err'); return; }
  settings = await setSettings({ deeplKey: key });

  setStatus('Testing…', 'busy');
  const out = await bgTranslate(['Guten Morgen'], 'DE', settings.targetLang, key);
  if (out?.[0]) setStatus(`Working — "Guten Morgen" → "${out[0]}"`, 'ok');
  else setStatus('Key rejected. Check it was copied in full.', 'err');
}

/* ── Words ────────────────────────────────────────────────────────────────── */

function fmtTime(s: number): string {
  const m = Math.floor(s / 60), sec = Math.floor(s % 60);
  return `${m}:${String(sec).padStart(2, '0')}`;
}

function renderWords() {
  const q = $<HTMLInputElement>('search').value.trim().toLowerCase();
  const list = $('list');
  list.textContent = '';

  const filtered = q
    ? vocab.filter(v =>
        v.word.includes(q) || v.translation.toLowerCase().includes(q) || v.context.toLowerCase().includes(q))
    : vocab;

  $('count').textContent = `${filtered.length}${q ? ` / ${vocab.length}` : ''}`;

  if (filtered.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = vocab.length === 0
      ? 'No saved words yet. Click a word in the subtitles to look it up and save it.'
      : 'Nothing matches that search.';
    list.appendChild(empty);
    return;
  }

  // Newest first, grouped by what you were watching.
  const groups = new Map<string, VocabEntry[]>();
  for (const v of [...filtered].reverse()) {
    const k = v.title || v.site;
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k)!.push(v);
  }

  for (const [title, items] of groups) {
    const h = document.createElement('div');
    h.className = 'grp';
    h.textContent = title;
    list.appendChild(h);

    for (const v of items) {
      const item = document.createElement('div');
      item.className = 'item';

      const main = document.createElement('div');
      main.className = 'main';

      const w = document.createElement('div');
      w.className = 'w';
      w.textContent = v.word;

      const t = document.createElement('div');
      t.className = 't';
      t.textContent = v.translation || '—';

      const c = document.createElement('div');
      c.className = 'c';
      c.textContent = v.context;
      main.append(w, t, c);

      const icons = document.createElement('div');
      icons.className = 'icons';

      const star = document.createElement('button');
      star.className = `star${v.starred ? ' on' : ''}`;
      star.textContent = '★';
      star.title = 'Star';
      star.addEventListener('click', async () => {
        await toggleStar(v.word, v.url);
        await reloadVocab();
      });

      const jump = document.createElement('button');
      jump.textContent = '▷';
      jump.title = `Open at ${fmtTime(v.time)}`;
      jump.addEventListener('click', () => {
        const url = new URL(v.url);
        if (url.hostname.endsWith('youtube.com')) url.searchParams.set('t', `${Math.floor(v.time)}s`);
        void chrome.tabs.create({ url: url.toString() });
      });

      const del = document.createElement('button');
      del.textContent = '×';
      del.title = 'Delete';
      del.addEventListener('click', async () => {
        await removeWord(v.word, v.url);
        await reloadVocab();
      });

      icons.append(star, jump, del);
      item.append(main, icons);
      list.appendChild(item);
    }
  }
}

async function reloadVocab() {
  vocab = await getVocab();
  renderWords();
}

/** TSV, which is what Anki's importer expects. */
function exportTsv() {
  const esc = (s: string) => s.replace(/[\t\r\n]+/g, ' ').trim();
  const rows = vocab.map(v =>
    [v.word, v.translation, esc(v.context), esc(v.contextTranslation), v.title, v.site, v.createdAt.slice(0, 10)]
      .map(esc).join('\t'));
  const body = ['word\ttranslation\tcontext\tcontext_translation\tsource\tsite\tdate', ...rows].join('\n');

  const url = URL.createObjectURL(new Blob([body], { type: 'text/tab-separated-values' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = `majortom-vocab-${new Date().toISOString().slice(0, 10)}.tsv`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

/* ── Go ───────────────────────────────────────────────────────────────────── */

$('search').addEventListener('input', renderWords);
$('export').addEventListener('click', exportTsv);

void (async () => {
  await initSettings();
  await reloadVocab();
})();
