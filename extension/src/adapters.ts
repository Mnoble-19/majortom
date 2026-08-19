import { Cue, CueTrack, MediaInfo } from './types';
import { parse } from './parsers';
import { bgFetch } from './messaging';
import { log } from './logger';

/**
 * A site adapter resolves subtitles from a site's *own* metadata API.
 *
 * This is by far the most reliable capture path: it is deterministic, needs no
 * race against the player, and works whether or not the user ever turns the
 * site's captions on. Generic capture (text tracks / network sniffing / DOM)
 * exists as a fallback for sites we have no adapter for.
 */
export interface Adapter {
  id: string;
  matches(host: string): boolean;
  /** Identifies the current media; a change means we reload subtitles. */
  mediaKey(): string;
  title(): string;
  /** Subtitles in the video's own language. */
  resolve(): Promise<CueTrack[]>;
  /**
   * Some sites can serve a machine translation themselves (YouTube's `tlang`),
   * which is free and instant. Returning null falls through to the translator.
   */
  translated?(target: string): Promise<Cue[] | null>;
}

/* ── Shared helpers ───────────────────────────────────────────────────────── */

/** Collect every string in a JSON structure matching a predicate. */
export function deepStrings(value: unknown, test: (s: string) => boolean, out: string[] = []): string[] {
  if (typeof value === 'string') {
    if (test(value)) out.push(value);
  } else if (Array.isArray(value)) {
    for (const v of value) deepStrings(v, test, out);
  } else if (value && typeof value === 'object') {
    for (const v of Object.values(value as Record<string, unknown>)) deepStrings(v, test, out);
  }
  return out;
}

async function fetchCues(url: string, label: string, lang: string, id: string): Promise<CueTrack | null> {
  const body = await bgFetch(url);
  if (!body) return null;
  const cues = parse(body, url);
  if (cues.length === 0) {
    log.warn('adapter: fetched but parsed 0 cues from', url.slice(0, 120));
    return null;
  }
  return { id, lang, label, source: 'adapter', cues };
}

/* ── ARD Mediathek ────────────────────────────────────────────────────────── */

/**
 * ARD renders captions with a custom DOM renderer over MSE and fetches the
 * subtitle file once at player init — too early to intercept, and it creates no
 * text tracks at all. Its page-gateway API, however, hands out a plain WebVTT
 * URL for the item, which is what we use.
 */
/**
 * Find the subtitle file in an ARD page-gateway item payload. Kept pure and
 * exported so it can be checked against live API responses.
 */
export function pickArdSubtitleUrl(json: unknown): string | null {
  const urls = deepStrings(json, s => s.includes('/player-service/subtitle/'));
  // WebVTT is cleaner to parse than the EBU-TT variant of the same track.
  return urls.find(u => u.includes('/webvtt/')) || urls.find(u => u.includes('/ebutt/')) || null;
}

const ard: Adapter = {
  id: 'ard',
  matches: h => h.endsWith('ardmediathek.de'),

  mediaKey() {
    // …/video/<show>/<episode>/<channel>/<base64 crid>
    const m = location.pathname.match(/\/video\/[^/]+\/[^/]+\/[^/]+\/([^/?#]+)/)
      || location.pathname.match(/\/video\/([^/?#]+)/);
    return m ? m[1] : location.pathname;
  },

  title() {
    return document.title.replace(/\s*[-|·]\s*(ARD Mediathek|hier anschauen).*$/i, '').trim();
  },

  async resolve() {
    const id = this.mediaKey();
    if (!id) return [];
    const api = `https://api.ardmediathek.de/page-gateway/pages/ard/item/${encodeURIComponent(id)}?embedded=false&mcV6=true`;
    const raw = await bgFetch(api);
    if (!raw) return [];

    let json: unknown;
    try { json = JSON.parse(raw); } catch { return []; }

    const pick = pickArdSubtitleUrl(json);
    if (!pick) {
      log.info('ard: no subtitle url in item metadata (episode may have none)');
      return [];
    }

    const track = await fetchCues(pick, 'Deutsch (UT)', 'de', 'ard-primary');
    return track ? [track] : [];
  },
};

/* ── ZDF ──────────────────────────────────────────────────────────────────── */

/**
 * ZDF embeds its player config in the page, including subtitle URLs on
 * utstreaming.zdf.de. We scrape those out of the document rather than dealing
 * with the API's auth token.
 */
const zdf: Adapter = {
  id: 'zdf',
  matches: h => h.endsWith('zdf.de'),

  mediaKey() {
    return location.pathname;
  },

  title() {
    return document.title.replace(/\s*[-|]\s*ZDFmediathek.*$/i, '').replace(/\s*-\s*ZDFheute.*$/i, '').trim();
  },

  async resolve() {
    const html = document.documentElement.innerHTML;
    const found = new Set<string>();
    const re = /https?:\\?\/\\?\/utstreaming\.zdf\.de\/[^"'\\\s]+?\.(?:xml|vtt|ebutt)/gi;
    for (const m of html.matchAll(re)) found.add(m[0].replace(/\\\//g, '/'));

    for (const url of found) {
      const track = await fetchCues(url, 'Deutsch (UT)', 'de', 'zdf-primary');
      if (track) return [track];
    }
    log.info('zdf: no subtitle url found in page; falling back to generic capture');
    return [];
  },
};

/* ── YouTube ──────────────────────────────────────────────────────────────── */

interface YtTrack { baseUrl: string; languageCode: string; name?: string; kind?: string }

/**
 * YouTube's caption track list is on `ytInitialPlayerResponse`, which lives in
 * the page world. The MAIN-world capture script copies it onto a DOM dataset
 * attribute so the content script can read it without a message round-trip.
 */
function ytTracks(): YtTrack[] {
  const el = document.documentElement.getAttribute('data-majortom-yt');
  if (!el) return [];
  try { return JSON.parse(el) as YtTrack[]; } catch { return []; }
}

const youtube: Adapter = {
  id: 'youtube',
  matches: h => h.endsWith('youtube.com') || h === 'youtu.be',

  mediaKey() {
    return new URLSearchParams(location.search).get('v') || location.pathname;
  },

  title() {
    const h = document.querySelector('#title h1, h1.ytd-watch-metadata');
    return (h?.textContent || document.title.replace(/\s*-\s*YouTube$/, '')).trim();
  },

  async resolve() {
    const tracks = ytTracks();
    if (tracks.length === 0) return [];
    // Prefer a real authored track over YouTube's ASR transcript.
    const pick = tracks.find(t => t.kind !== 'asr') || tracks[0];
    const url = pick.baseUrl.includes('fmt=') ? pick.baseUrl : `${pick.baseUrl}&fmt=json3`;
    const track = await fetchCues(url, pick.name || pick.languageCode, pick.languageCode, 'yt-primary');
    return track ? [track] : [];
  },

  /** YouTube will translate a track server-side for free — use it when we can. */
  async translated(target) {
    const tracks = ytTracks();
    const pick = tracks.find(t => t.kind !== 'asr') || tracks[0];
    if (!pick?.baseUrl) return null;

    const u = new URL(pick.baseUrl, location.origin);
    // DeepL codes carry a region (EN-US); YouTube wants the bare language.
    u.searchParams.set('tlang', target.split('-')[0].toLowerCase());
    u.searchParams.set('fmt', 'json3');

    const body = await bgFetch(u.toString());
    if (!body) return null;
    const cues = parse(body, u.toString());
    return cues.length > 0 ? cues : null;
  },
};

/* ── Registry ─────────────────────────────────────────────────────────────── */

const ADAPTERS: Adapter[] = [ard, zdf, youtube];

export function adapterFor(host = location.hostname): Adapter | null {
  return ADAPTERS.find(a => a.matches(host)) || null;
}

export function mediaInfo(adapter: Adapter | null): MediaInfo {
  const site = location.hostname.replace(/^www\./, '');
  const title = adapter?.title() || document.title;
  return {
    title,
    site,
    url: location.href,
    key: `${site}:${adapter?.mediaKey() || location.pathname}`,
  };
}
