import {Cue, CueTrack} from '../../shared/types';
import {parse} from '../parsers';
import {bgFetch} from '../../shared/messaging';
import {log} from '../../shared/logger';

/**
 * A site adapter resolves subtitles from a site's *own* metadata API.
 *
 * This is by far the most reliable capture path: it is deterministic, needs no
 * race against the player, and works whether or not the user ever turns the
 * site's captions on. The generic layers in ../injected.ts are the fallback for
 * sites we have no adapter for.
 *
 * To support a new site, add a file here and register it in ./index.ts.
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

/** Collect every string in a JSON structure matching a predicate. */
export function deepStrings(
    value: unknown, test: (s: string) => boolean, out: string[] = [],
): string[] {
    if (typeof value === 'string') {
        if (test(value)) out.push(value);
    } else if (Array.isArray(value)) {
        for (const v of value) deepStrings(v, test, out);
    } else if (value && typeof value === 'object') {
        for (const v of Object.values(value as Record<string, unknown>)) deepStrings(v, test, out);
    }
    return out;
}

/** Fetch a subtitle file through the service worker and parse it into a track. */
export async function fetchCues(
    url: string, label: string, lang: string, id: string,
): Promise<CueTrack | null> {
    const body = await bgFetch(url);
    if (!body) return null;
    const cues = parse(body, url);
    if (cues.length === 0) {
        log.warn('adapter: fetched but parsed 0 cues from', url.slice(0, 120));
        return null;
    }
    return {id, lang, label, source: 'adapter', cues};
}
