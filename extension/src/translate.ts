import { Cue, MediaInfo, Settings } from './types';
import { Adapter } from './adapters';
import { bgTranslate } from './messaging';
import { getCached, setCached } from './storage';
import { log } from './logger';

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

  return { texts, cueGroup };
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
  /** Called as batches land, so the overlay fills in while you watch. */
  onProgress: (lines: SecondaryLines, done: boolean) => void;
}

/** DeepL wants a bare source code; targets keep their region (EN-US). */
function toSourceCode(hint: string, settings: Settings): string {
  const explicit = settings.sourceLang.trim();
  if (explicit) return explicit.toUpperCase();
  return (hint || '').split('-')[0].toUpperCase();
}

export async function translateCues(opts: TranslateOptions): Promise<SecondaryLines> {
  const { cues, settings, media, adapter, onProgress } = opts;
  const empty: SecondaryLines = new Array(cues.length).fill('');
  if (cues.length === 0 || !settings.showSecondary) return empty;

  // 1. The site's own translation is free and instant — always prefer it.
  if (adapter?.translated) {
    try {
      const native = await adapter.translated(settings.targetLang);
      if (native && native.length > 0) {
        log.info(`translation: site-provided (${native.length} cues)`);
        const lines = alignByTime(cues, native);
        onProgress(lines, true);
        return lines;
      }
    } catch (e) {
      log.warn('site translation failed, falling back:', (e as Error)?.message);
    }
  }

  if (settings.provider !== 'deepl') return empty;
  if (!settings.deeplKey.trim()) {
    log.info('translation: no DeepL key set — primary line only');
    return empty;
  }

  const { texts, cueGroup } = groupSentences(cues);
  const source = toSourceCode(opts.sourceLangHint, settings);
  const target = settings.targetLang;
  const cacheKey = `${media.key}|${source}|${target}|${cues.length}`;

  const expand = (groups: string[]): SecondaryLines =>
    cues.map((_, i) => groups[cueGroup[i]] || '');

  // 2. Cached from a previous watch of the same video.
  const cached = await getCached(cacheKey);
  if (cached && cached.length === texts.length) {
    log.info('translation: cache hit');
    const lines = expand(cached);
    onProgress(lines, true);
    return lines;
  }

  // 3. Translate in batches, publishing progress as each one returns.
  log.info(`translation: DeepL ${source || 'auto'}→${target}, ${texts.length} sentences from ${cues.length} cues`);
  const BATCH = 40;
  const result: string[] = new Array(texts.length).fill('');
  let failed = false;

  for (let i = 0; i < texts.length; i += BATCH) {
    const slice = texts.slice(i, i + BATCH);
    const out = await bgTranslate(slice, source, target, settings.deeplKey);
    if (!out) { failed = true; break; }
    for (let k = 0; k < out.length; k++) result[i + k] = out[k];
    onProgress(expand(result), false);
  }

  if (failed) {
    log.warn('translation: aborted after a failed batch');
    // Keep whatever landed — a partly translated line beats a blank one.
    return expand(result);
  }

  await setCached(cacheKey, result);
  const lines = expand(result);
  onProgress(lines, true);
  return lines;
}

/** Translate a single word or phrase on demand (click-to-look-up). */
export async function translateOne(
  text: string, sourceHint: string, settings: Settings,
): Promise<string> {
  if (settings.provider !== 'deepl' || !settings.deeplKey.trim()) return '';
  const out = await bgTranslate(
    [text], toSourceCode(sourceHint, settings), settings.targetLang, settings.deeplKey,
  );
  return out?.[0] || '';
}
