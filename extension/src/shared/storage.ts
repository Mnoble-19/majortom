import {Settings, VocabEntry} from './types';
import {DEFAULT_SETTINGS} from './config';

const SETTINGS_KEY = 'mt_settings';
const VOCAB_KEY = 'mt_vocab';
const CACHE_KEY = 'mt_tcache';
/** Translated videos to keep before evicting the least recently used. */
const CACHE_LIMIT = 40;

/* ── Settings ─────────────────────────────────────────────────────────────── */

export async function getSettings(): Promise<Settings> {
    const r = await chrome.storage.local.get(SETTINGS_KEY);
    return {...DEFAULT_SETTINGS, ...(r[SETTINGS_KEY] || {})};
}

/** Stores only what the user has changed, so a better default reaches every
 *  setting they never touched instead of being frozen by the first save. */
export async function setSettings(patch: Partial<Settings>): Promise<Settings> {
    const r = await chrome.storage.local.get(SETTINGS_KEY);
    const changed = {...(r[SETTINGS_KEY] || {}), ...patch};
    await chrome.storage.local.set({[SETTINGS_KEY]: changed});
    return {...DEFAULT_SETTINGS, ...changed};
}

export function onSettingsChanged(fn: (s: Settings) => void): void {
    chrome.storage.onChanged.addListener((changes, area) => {
        if (area === 'local' && changes[SETTINGS_KEY]) {
            fn({...DEFAULT_SETTINGS, ...changes[SETTINGS_KEY].newValue});
        }
    });
}

export function isHostEnabled(s: Settings, host = location.hostname): boolean {
    return s.enabled && !s.disabledHosts.includes(host.replace(/^www\./, ''));
}

/* ── Vocabulary ───────────────────────────────────────────────────────────── */

/** Vocab lives under its own key so saving a word never rewrites settings. */
export async function getVocab(): Promise<VocabEntry[]> {
    const r = await chrome.storage.local.get(VOCAB_KEY);
    return (r[VOCAB_KEY] || []) as VocabEntry[];
}

/** An entry is identified by word + the media it came from. */
function sameEntry(a: VocabEntry, word: string, mediaUrl: string) {
    return a.word === word && a.url === mediaUrl;
}

export async function addWord(entry: VocabEntry): Promise<void> {
    const vocab = await getVocab();
    if (vocab.some(v => sameEntry(v, entry.word, entry.url))) return;
    vocab.push(entry);
    await chrome.storage.local.set({[VOCAB_KEY]: vocab});
}

export async function removeWord(word: string, mediaUrl: string): Promise<void> {
    const vocab = await getVocab();
    await chrome.storage.local.set({
        [VOCAB_KEY]: vocab.filter(v => !sameEntry(v, word, mediaUrl)),
    });
}

/** Remove every entry for a word, wherever it was saved. Used by the popup. */
export async function removeWordEverywhere(word: string): Promise<void> {
    const vocab = await getVocab();
    await chrome.storage.local.set({[VOCAB_KEY]: vocab.filter(v => v.word !== word)});
}

export async function toggleStar(word: string, mediaUrl: string): Promise<void> {
    const vocab = await getVocab();
    const found = vocab.find(v => sameEntry(v, word, mediaUrl));
    if (!found) return;
    found.starred = !found.starred;
    await chrome.storage.local.set({[VOCAB_KEY]: vocab});
}

export async function updateWord(
    word: string, mediaUrl: string, patch: Partial<VocabEntry>,
): Promise<void> {
    const vocab = await getVocab();
    const found = vocab.find(v => sameEntry(v, word, mediaUrl));
    if (!found) return;
    Object.assign(found, patch);
    await chrome.storage.local.set({[VOCAB_KEY]: vocab});
}

/* ── Translation cache ────────────────────────────────────────────────────── */

interface CacheEntry {
    at: number;
    texts: string[]
}

export async function getCached(key: string): Promise<string[] | null> {
    const r = await chrome.storage.local.get(CACHE_KEY);
    const cache: Record<string, CacheEntry> = r[CACHE_KEY] || {};
    const hit = cache[key];
    if (!hit) return null;
    hit.at = Date.now();
    await chrome.storage.local.set({[CACHE_KEY]: cache});
    return hit.texts;
}

export async function setCached(key: string, texts: string[]): Promise<void> {
    const r = await chrome.storage.local.get(CACHE_KEY);
    const cache: Record<string, CacheEntry> = r[CACHE_KEY] || {};
    cache[key] = {at: Date.now(), texts};

    const keys = Object.keys(cache);
    if (keys.length > CACHE_LIMIT) {
        keys.sort((a, b) => cache[a].at - cache[b].at)
            .slice(0, keys.length - CACHE_LIMIT)
            .forEach(k => delete cache[k]);
    }
    await chrome.storage.local.set({[CACHE_KEY]: cache});
}

export async function clearCache(): Promise<void> {
    await chrome.storage.local.remove(CACHE_KEY);
}
