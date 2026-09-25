import {Adapter} from './adapter';
import {parse} from '../parsers';
import {Cue, CueTrack} from '../../shared/types';
import {log} from '../../shared/logger';

export interface YtTrack {
    baseUrl: string;
    languageCode: string;
    name?: string;
    kind?: string;
}

export interface YtPayload {
    v?: string;
    /** The player's proof-of-origin params; without them every fetch is empty. */
    token: Record<string, string> | null;
    /** Language of the audio playing now, or '' / 'und' when there is one track. */
    audio: string;
    tracks: YtTrack[];
}

/**
 * The MAIN-world capture script publishes the player's track list, and the
 * caption token it saw, on a DOM attribute so we can read it synchronously.
 *
 * The payload is stamped with the video id, and we refuse it when it does not
 * match the current URL — YouTube navigates before it refreshes the player, so
 * an unchecked read hands back the *previous* video's subtitles.
 */
export function parseYtPayload(raw: string | null, wantedId: string | null): YtPayload | null {
    if (!raw) return null;
    try {
        const data = JSON.parse(raw) as Partial<YtPayload>;
        if (wantedId && data.v && data.v !== wantedId) return null;
        return {
            v: data.v,
            token: data.token || null,
            audio: data.audio || '',
            tracks: Array.isArray(data.tracks) ? data.tracks : [],
        };
    } catch {
        return null;
    }
}

const base = (code: string) => (code || '').split('-')[0].toLowerCase();

/**
 * The track in the language actually being spoken: the audio's language when
 * YouTube tells us (a dub), otherwise the automatic transcript's, which is
 * always the spoken one. An authored track beats the transcript in the same
 * language, since it has punctuation and no misheard words.
 */
export function pickSpokenTrack(p: YtPayload, learning: string): YtTrack | undefined {
    const asr = p.tracks.find(t => t.kind === 'asr');
    const audio = p.audio && p.audio !== 'und' ? p.audio : '';
    const spoken = audio || (asr ? base(asr.languageCode) : '') || base(learning);
    const authored = (lang: string) => p.tracks.find(t => t.kind !== 'asr' && base(t.languageCode) === lang);
    return authored(spoken)
        || p.tracks.find(t => t.kind === 'asr' && base(t.languageCode) === spoken)
        || authored(base(learning))
        || p.tracks[0];
}

function payload(): YtPayload | null {
    return parseYtPayload(
        document.documentElement.getAttribute('data-majortom-yt'),
        new URLSearchParams(location.search).get('v'),
    );
}

function trackUrl(t: YtTrack, token: Record<string, string>, tlang?: string): string {
    const u = new URL(t.baseUrl, location.origin);
    for (const [k, v] of Object.entries(token)) u.searchParams.set(k, v);
    u.searchParams.set('fmt', 'json3');
    if (tlang) u.searchParams.set('tlang', tlang);
    return u.toString();
}

/**
 * Fetched here rather than through the service worker: it is same-origin for
 * the page, so it carries YouTube's cookies, which the token is bound to.
 */
async function fetchTrack(url: string): Promise<Cue[] | null> {
    try {
        const res = await fetch(url, {credentials: 'include'});
        if (!res.ok) return null;
        const body = await res.text();
        if (!body) return null;
        const cues = parse(body, url);
        return cues.length ? cues : null;
    } catch (e) {
        log.warn('youtube: track fetch failed', (e as Error)?.message);
        return null;
    }
}

/** What `resolve` chose, so the translation methods start from the same track. */
let chosen: { v: string; track: YtTrack } | null = null;

export const youtube: Adapter = {
    id: 'youtube',
    matches: h => h.endsWith('youtube.com') || h === 'youtu.be',

    mediaKey() {
        return new URLSearchParams(location.search).get('v') || location.pathname;
    },

    title() {
        const h = document.querySelector('#title h1, h1.ytd-watch-metadata');
        return (h?.textContent || document.title.replace(/\s*-\s*YouTube$/, '')).trim();
    },

    async resolve(learning) {
        const p = payload();
        if (!p?.v || !p.token || p.tracks.length === 0) return [];
        const pick = pickSpokenTrack(p, learning);
        if (!pick?.baseUrl) return [];

        const cues = await fetchTrack(trackUrl(pick, p.token));
        if (!cues) return [];
        chosen = {v: p.v, track: pick};
        const track: CueTrack = {
            id: `yt:${p.v}:${pick.languageCode}:${pick.kind || ''}`,
            lang: pick.languageCode,
            label: pick.name || pick.languageCode,
            source: 'adapter',
            cues,
        };
        return [track];
    },

    /** A track someone actually wrote in your language. The best there is. */
    async nativeTranslation(target) {
        const p = payload();
        if (!p?.token || !chosen || chosen.v !== p.v) return null;
        const want = base(target);
        if (base(chosen.track.languageCode) === want) return null;
        const t = p.tracks.find(t => t.kind !== 'asr' && base(t.languageCode) === want);
        return t ? fetchTrack(trackUrl(t, p.token)) : null;
    },

    /** YouTube's own machine translation: instant, free, line by line. */
    async machineTranslation(target) {
        const p = payload();
        if (!p?.token || !chosen || chosen.v !== p.v) return null;
        return fetchTrack(trackUrl(chosen.track, p.token, base(target)));
    },
};
