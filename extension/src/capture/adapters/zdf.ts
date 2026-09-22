import {Adapter, fetchCues} from './adapter';
import {log} from '../../shared/logger';

/**
 * ZDF embeds its player config in the page, including subtitle URLs on
 * utstreaming.zdf.de. We scrape those out of the document rather than dealing
 * with the API's auth token — more fragile than ARD's path, so the generic
 * capture layers remain the backstop.
 */
export const zdf: Adapter = {
    id: 'zdf',
    matches: h => h.endsWith('zdf.de'),

    mediaKey() {
        return location.pathname;
    },

    title() {
        return document.title
            .replace(/\s*[-|]\s*ZDFmediathek.*$/i, '')
            .replace(/\s*-\s*ZDFheute.*$/i, '')
            .trim();
    },

    async resolve() {
        const html = document.documentElement.innerHTML;
        const found = new Set<string>();
        // URLs appear inside embedded JSON, so slashes may be backslash-escaped.
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
