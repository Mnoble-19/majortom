import {Cue, Gloss, MediaInfo, Settings} from '../shared/types';
import {Adapter} from '../capture/adapters';
import {bgGloss, bgTranslateSubs} from '../shared/messaging';
import {getSentences, saveSentences} from '../shared/storage';
import {cueIndexAt} from '../capture/parsers';
import {log} from '../shared/logger';

/** Translations indexed by primary-cue position, so rendering is a lookup. */
export type SecondaryLines = string[];

interface Grouping {
    /** Sentence-sized texts to translate. */
    texts: string[];
    /** cueGroup[i] = index into `texts` for primary cue i. */
    cueGroup: number[];
}

const SENTENCE_END = /[.!?…"»)\]]\s*$/;
const MAX_GROUP_CHARS = 220;
const MAX_GROUP_CUES = 6;
const MAX_GAP_SECONDS = 2.5;

/**
 * Broadcaster subtitles split sentences across several cues, and translating
 * those fragments in isolation is exactly why machine subtitles read badly.
 * We regroup cues into whole sentences, translate those, and show the sentence
 * translation for every cue it spans — so the translation line stays steady
 * while the original advances through it.
 */
export function groupSentences(cues: Cue[]): Grouping {
    const texts: string[] = [];
    const cueGroup: number[] = [];
    let buf: string[] = [];
    let bufCues = 0;

    const flush = () => {
        if (buf.length === 0) return;
        texts.push(buf.join(' ').replace(/\s+/g, ' ').trim());
        buf = [];
        bufCues = 0;
    };

    for (let i = 0; i < cues.length; i++) {
        const cue = cues[i];
        const prev = cues[i - 1];
        const gap = prev ? cue.start - prev.end : 0;

        if (buf.length > 0 && (gap > MAX_GAP_SECONDS || bufCues >= MAX_GROUP_CUES)) flush();

        buf.push(cue.text.replace(/\n/g, ' '));
        bufCues++;
        cueGroup[i] = texts.length; // the group this cue will land in once flushed

        const joined = buf.join(' ');
        if (SENTENCE_END.test(joined) || joined.length >= MAX_GROUP_CHARS) flush();
    }
    flush();

    return {texts, cueGroup};
}

/** Map a translated cue list onto primary cue positions by time overlap. */
function alignByTime(primary: Cue[], secondary: Cue[]): SecondaryLines {
    const out: SecondaryLines = new Array(primary.length).fill('');
    let j = 0;
    for (let i = 0; i < primary.length; i++) {
        const mid = (primary[i].start + primary[i].end) / 2;
        while (j < secondary.length - 1 && secondary[j].end < mid) j++;
        const s = secondary[j];
        if (s && mid >= s.start - 0.75 && mid <= s.end + 0.75) out[i] = s.text;
    }
    return out;
}

export interface TranslateOptions {
    cues: Cue[];
    sourceLangHint: string;
    settings: Settings;
    media: MediaInfo;
    adapter: Adapter | null;
    /** Playback position, so the lines you are about to see go first. */
    now: () => number;
    /** True once this job has been superseded; checked before every request. */
    isStale: () => boolean;
    /** Called as batches land, so the overlay fills in while you watch. */
    onProgress: (lines: SecondaryLines, done: boolean) => void;
    /** Short status for the overlay; '' clears it. */
    onStatus: (text: string, hideAfterMs?: number) => void;
}

/** The source language: what the popup says, else what the track says. */
function sourceCode(hint: string, settings: Settings): string {
    return (settings.sourceLang.trim() || hint || '').split('-')[0].toUpperCase();
}

/**
 * Small first so the line on screen fills in fast, then larger for
 * throughput. Capped by length as well as count: automatic captions make
 * 220-character "sentences", and 24 of those plus their translation would
 * overrun a 4k context. 1,500 characters stays near 1,500 tokens all told.
 */
const FIRST_BATCH = 8;
const BATCH = 24;
const BATCH_CHARS = 1500;
/** Sentences before a batch sent along as context, not translated. */
const CONTEXT = 3;

/**
 * Pick where to translate next: the first untranslated sentence at or after
 * the one playing, else the first one anywhere. Recomputed every batch, so a
 * seek moves the work to wherever you went.
 */
export function nextBatch(
    done: boolean[], cueGroup: number[], cues: Cue[], t: number, size: number,
    lengths: number[] = [], maxChars = Infinity,
): number[] {
    let at = cueIndexAt(cues, t);
    if (at < 0) at = cues.findIndex(c => c.start > t);
    const from = at < 0 ? 0 : cueGroup[at];

    let start = done.indexOf(false, from);
    if (start < 0) start = done.indexOf(false);
    if (start < 0) return [];

    const batch: number[] = [];
    let chars = 0;
    for (let g = start; g < done.length && batch.length < size && !done[g]; g++) {
        chars += lengths[g] || 0;
        // Always at least one, however long, or a long sentence would stall.
        if (batch.length > 0 && chars > maxChars) break;
        batch.push(g);
    }
    return batch;
}

export async function translateCues(opts: TranslateOptions): Promise<SecondaryLines> {
    const {cues, settings, media, adapter, onProgress, onStatus, isStale} = opts;
    const empty: SecondaryLines = new Array(cues.length).fill('');
    if (cues.length === 0 || !settings.showSecondary) return empty;

    const target = settings.targetLang;

    // 1. A track a person wrote in your language beats any machine.
    if (adapter?.nativeTranslation) {
        try {
            const native = await adapter.nativeTranslation(target);
            if (isStale()) return empty;
            if (native?.length) {
                log.info(`translation: site's own ${target} track (${native.length} cues)`);
                const lines = alignByTime(cues, native);
                onProgress(lines, true);
                return lines;
            }
        } catch (e) {
            log.warn('site translation failed, falling back:', (e as Error)?.message);
        }
    }

    // 2. The local model, a sentence at a time, starting where you are.
    const {texts, cueGroup} = groupSentences(cues);
    const source = sourceCode(opts.sourceLangHint, settings);
    const cacheKey = `${media.key}|${source}|${target.split('-')[0]}`;
    const cache = await getSentences(cacheKey);
    if (isStale()) return empty;

    const result = texts.map(t => cache[t] || '');
    const lengths = texts.map(t => t.length);
    const done = texts.map(t => t in cache);

    const cached = done.filter(Boolean).length;
    if (cached === texts.length) {
        log.info('translation: all cached');
        const lines = cues.map((_, i) => result[cueGroup[i]] || '');
        onProgress(lines, true);
        return lines;
    }

    // The site's machine translation, where there is one, fills the line at
    // once while the model works; each sentence is swapped for the model's as
    // it lands. A cold model takes twenty seconds or more to answer at all.
    let placeholder: SecondaryLines | null = null;
    if (adapter?.machineTranslation) {
        const machine = await adapter.machineTranslation(target).catch(() => null);
        if (isStale()) return empty;
        if (machine?.length) placeholder = alignByTime(cues, machine);
    }
    const expand = (): SecondaryLines => cues.map((_, i) => result[cueGroup[i]] || placeholder?.[i] || '');

    log.info(`translation: local model ${source || 'auto'}→${target}, ${texts.length - cached} of ${texts.length} sentences to do`);
    if (cached || placeholder) onProgress(expand(), false);

    let first = true;
    for (;;) {
        const batch = nextBatch(done, cueGroup, cues, opts.now(), first ? FIRST_BATCH : BATCH,
            lengths, BATCH_CHARS);
        if (batch.length === 0) break;
        if (isStale()) return expand();

        const left = done.filter(d => !d).length;
        onStatus(first && cached === 0
            ? 'translating…'
            : `translating… ${Math.round(100 * (1 - left / texts.length))}%`);

        const context = texts.slice(Math.max(0, batch[0] - CONTEXT), batch[0]);
        const out = await bgTranslateSubs(batch.map(g => texts[g]), context, source, target);

        if ('error' in out) {
            // Whatever the model finished stays; the rest keeps the site's
            // machine translation if there is one.
            onStatus(placeholder
                ? 'local model unavailable — showing YouTube’s translation'
                : `translation stopped: ${out.error}`, 10000);
            onProgress(expand(), true);
            return expand();
        }

        batch.forEach((g, k) => {
            result[g] = out.lines[k];
            done[g] = true;
            cache[texts[g]] = out.lines[k];
        });
        // Saved even if the job went stale: the work is good, and rewatching
        // or coming back should not pay for it twice.
        await saveSentences(cacheKey, cache);
        if (isStale()) return expand();
        onProgress(expand(), false);
        first = false;
    }

    onStatus('');
    onProgress(expand(), true);
    return expand();
}

/** Look up a clicked word in the sentence it was said in. */
export async function translateOne(
    word: string, sentence: string, sourceHint: string, settings: Settings,
): Promise<Gloss | { error: string }> {
    return bgGloss(word, sentence, sourceCode(sourceHint, settings), settings.targetLang);
}
