import {Adapter, fetchCues} from './adapter';
import {parse} from '../parsers';
import {bgFetch} from '../../shared/messaging';

interface YtTrack {
    baseUrl: string;
    languageCode: string;
    name?: string;
    kind?: string;
}

/**
 * YouTube's caption track list lives on `ytInitialPlayerResponse`, in the page
 * world. The MAIN-world capture script copies it onto a DOM attribute so we can
 * read it synchronously here instead of racing a message.
 *
 * The payload is stamped with the video id, and we refuse it when it does not
 * match the current URL — YouTube navigates before it refreshes that object, so
 * an unchecked read hands back the *previous* video's subtitles.
 */
export function parseYtPayload(raw: string | null, wantedId: string | null): YtTrack[] {
    if (!raw) return [];
    try {
        const data = JSON.parse(raw) as { v?: string; tracks?: YtTrack[] };
        // Reject a payload that belongs to a different video than the URL names.
        if (wantedId && data.v && data.v !== wantedId) return [];
        return Array.isArray(data.tracks) ? data.tracks : [];
    } catch {
        return [];
    }
}

function tracks(): YtTrack[] {
    return parseYtPayload(
        document.documentElement.getAttribute('data-majortom-yt'),
        new URLSearchParams(location.search).get('v'),
    );
}

/** Prefer an authored track over YouTube's automatic speech transcript. */
function preferred(list: YtTrack[]): YtTrack | undefined {
    return list.find(t => t.kind !== 'asr') || list[0];
}

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

    async resolve() {
        const pick = preferred(tracks());
        if (!pick?.baseUrl) return [];
        const url = pick.baseUrl.includes('fmt=') ? pick.baseUrl : `${pick.baseUrl}&fmt=json3`;
        const track = await fetchCues(url, pick.name || pick.languageCode, pick.languageCode, 'yt-primary');
        return track ? [track] : [];
    },

    /** YouTube will translate a track server-side for free — use it when we can. */
    async translated(target) {
        const pick = preferred(tracks());
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
