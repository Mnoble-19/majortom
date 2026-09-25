import {Settings, VocabEntry} from './types';
import {DEFAULT_SETTINGS} from './config';

const SETTINGS_KEY = 'mt_settings';
const VOCAB_KEY = 'mt_vocab';
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

/** A hostname as the site list stores it. */
export function siteOf(host: string): string {
    return host.replace(/^www\./, '');
}

/** A listed site covers its subdomains too, so ARD's player hosts come along. */
export function isHostEnabled(s: Settings, host = location.hostname): boolean {
    const h = siteOf(host);
    return s.enabledHosts.some(e => h === e || h.endsWith(`.${e}`));
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

/**
 * Translations are kept per video as sentence → translation, not as one array
 * for one particular set of cues. So a better subtitle source turning up, a
 * track that keeps growing, or a half-finished job resumed after a reload all
 * reuse every sentence already done instead of starting over.
 *
 * Each video has its own storage key, so saving a batch rewrites that video
 * alone; the index holds last-used times for eviction.
 */
const TC_PREFIX = 'mt_tc:';
const TC_INDEX = 'mt_tcindex';

export type SentenceCache = Record<string, string>;

export async function getSentences(key: string): Promise<SentenceCache> {
    const k = TC_PREFIX + key;
    const r = await chrome.storage.local.get([k, TC_INDEX]);
    const index: Record<string, number> = r[TC_INDEX] || {};
    index[key] = Date.now();
    await chrome.storage.local.set({[TC_INDEX]: index});
    return r[k] || {};
}

export async function saveSentences(key: string, sentences: SentenceCache): Promise<void> {
    const r = await chrome.storage.local.get(TC_INDEX);
    const index: Record<string, number> = r[TC_INDEX] || {};
    index[key] = Date.now();

    const keys = Object.keys(index);
    const evicted = keys.length > CACHE_LIMIT
        ? keys.sort((a, b) => index[a] - index[b]).slice(0, keys.length - CACHE_LIMIT)
        : [];
    for (const k of evicted) delete index[k];

    await chrome.storage.local.set({[TC_PREFIX + key]: sentences, [TC_INDEX]: index});
    if (evicted.length) await chrome.storage.local.remove(evicted.map(k => TC_PREFIX + k));
}

export async function clearCache(): Promise<void> {
    const all = await chrome.storage.local.get(null);
    await chrome.storage.local.remove(
        Object.keys(all).filter(k => k.startsWith(TC_PREFIX) || k === TC_INDEX || k === 'mt_tcache'));
}
