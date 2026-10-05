import {Settings, VocabEntry} from '../shared/types';
import {DEFAULT_SETTINGS, SOURCE_LANGS, TARGET_LANGS} from '../shared/config';
import {
    clearCache,
    getSettings,
    getVocab,
    isHostEnabled,
    removeWord,
    setSettings,
    siteOf,
    toggleStar,
} from '../shared/storage';
import {bgGloss, bgSyncScripts} from '../shared/messaging';

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
        settings = await setSettings({[id]: el.checked} as Partial<Settings>);
    });
}

async function currentTab(): Promise<{id?: number; host: string}> {
    const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
    try {
        const url = new URL(tab?.url || '');
        // chrome://, file:// and the like are never somewhere to turn it on.
        return {id: tab?.id, host: /^https?:$/.test(url.protocol) ? siteOf(url.hostname) : ''};
    } catch {
        return {id: tab?.id, host: ''};
    }
}

async function initSettings() {
    settings = await getSettings();
    const tab = await currentTab();
    host = tab.host;

    $('siteLabel').textContent = host || 'no active site';

    const siteToggle = $<HTMLInputElement>('siteToggle');
    siteToggle.checked = !!host && isHostEnabled(settings, host);
    siteToggle.disabled = !host;
    siteToggle.addEventListener('change', async () => {
        const hosts = new Set(settings.enabledHosts);
        if (siteToggle.checked) hosts.add(host); else hosts.delete(host);
        settings = await setSettings({enabledHosts: [...hosts]});
        // The page scripts go in at document_start, so the tab has to load
        // again either way: to get them, or to be rid of the patched fetch.
        await bgSyncScripts();
        if (tab.id !== undefined) await chrome.tabs.reload(tab.id);
        window.close();
    });

    fillSelect($<HTMLSelectElement>('sourceLang'), SOURCE_LANGS, settings.sourceLang);
    fillSelect($<HTMLSelectElement>('targetLang'), TARGET_LANGS, settings.targetLang);
    $('sourceLang').addEventListener('change', async e => {
        settings = await setSettings({sourceLang: (e.target as HTMLSelectElement).value});
    });
    $('targetLang').addEventListener('change', async e => {
        settings = await setSettings({targetLang: (e.target as HTMLSelectElement).value});
    });

    (['showSecondary', 'useSiteTranslation', 'blurSecondary', 'hoverPause', 'showToolbar', 'autoPause', 'loopCue', 'hideNativeCaptions'] as const)
        .forEach(bindToggle);

    const font = $<HTMLInputElement>('fontScale');
    font.value = String(settings.fontScale);
    font.addEventListener('input', async () => {
        settings = await setSettings({fontScale: Number(font.value)});
    });

    const offset = $<HTMLInputElement>('offsetPct');
    offset.value = String(settings.offsetPct);
    offset.addEventListener('input', async () => {
        settings = await setSettings({offsetPct: Number(offset.value)});
    });

    bindText('llmEndpoint', v => v.replace(/\/+$/, ''));
    bindText('llmModel', v => v);

    $('testModel').addEventListener('click', () => void testModel());
    $('clearCache').addEventListener('click', async () => {
        await clearCache();
        setStatus('Translation cache cleared.', 'ok');
    });
}

/** A text setting saved as you type; empty falls back to the default. */
function bindText(id: 'llmEndpoint' | 'llmModel', clean: (v: string) => string) {
    const input = $<HTMLInputElement>(id);
    // The endpoint shows its default as a placeholder, so an untouched field
    // stays empty and a better default still reaches it.
    input.value = settings[id] === DEFAULT_SETTINGS[id] ? '' : settings[id];
    let timer: number;
    input.addEventListener('input', () => {
        clearTimeout(timer);
        timer = window.setTimeout(async () => {
            settings = await setSettings({[id]: clean(input.value.trim()) || DEFAULT_SETTINGS[id]});
        }, 350);
    });
}

function setStatus(msg: string, cls: 'ok' | 'err' | 'busy') {
    const el = $('modelStatus');
    el.textContent = msg;
    el.className = `status ${cls}`;
}

async function testModel() {
    setStatus('Asking the model… (the first request loads it, which can take a while)', 'busy');
    const out = await bgGloss('abbringen', 'Sie hat sich nicht davon abbringen lassen.', 'DE', settings.targetLang);
    if ('error' in out) setStatus(`Not working: ${out.error}`, 'err');
    else setStatus(`Working — “abbringen” → “${out.meaning}”`, 'ok');
}

/* ── Words ────────────────────────────────────────────────────────────────── */

const ICONS = {
    star: 'm12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z',
    play: 'M8 5.5v13l10.5-6.5z',
    trash: 'M5 7h14M10 7V4.5h4V7M6.5 7l1 13h9l1-13',
};

/** Built with DOM calls rather than markup, like everything else here. */
function iconButton(name: keyof typeof ICONS, title: string, onClick: () => void): HTMLButtonElement {
    const ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', name === 'trash' ? 'none' : 'currentColor');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', name === 'trash' ? '2' : '1.2');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    const path = document.createElementNS(ns, 'path');
    path.setAttribute('d', ICONS[name]);
    svg.appendChild(path);

    const button = document.createElement('button');
    button.title = title;
    button.setAttribute('aria-label', title);
    button.appendChild(svg);
    button.addEventListener('click', onClick);
    return button;
}

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
            v.word.toLowerCase().includes(q) || v.translation.toLowerCase().includes(q)
            || v.context.toLowerCase().includes(q))
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

            const star = iconButton('star', v.starred ? 'Unstar' : 'Star', async () => {
                await toggleStar(v.word, v.url);
                await reloadVocab();
            });
            if (v.starred) star.classList.add('star', 'on');

            const jump = iconButton('play', `Open at ${fmtTime(v.time)}`, () => {
                const url = new URL(v.url);
                if (url.hostname.endsWith('youtube.com')) url.searchParams.set('t', `${Math.floor(v.time)}s`);
                void chrome.tabs.create({url: url.toString()});
            });

            const del = iconButton('trash', 'Delete', async () => {
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

    const url = URL.createObjectURL(new Blob([body], {type: 'text/tab-separated-values'}));
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
