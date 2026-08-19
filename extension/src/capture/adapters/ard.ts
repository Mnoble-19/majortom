import { Adapter, deepStrings, fetchCues } from './adapter';
import { bgFetch } from '../../shared/messaging';
import { log } from '../../shared/logger';

/**
 * Find the subtitle file in an ARD page-gateway item payload. Kept pure and
 * exported so it can be checked against live API responses (see scripts/smoke).
 */
export function pickArdSubtitleUrl(json: unknown): string | null {
  const urls = deepStrings(json, s => s.includes('/player-service/subtitle/'));
  // WebVTT is cleaner to parse than the EBU-TT variant of the same track.
  return urls.find(u => u.includes('/webvtt/')) || urls.find(u => u.includes('/ebutt/')) || null;
}

/**
 * ARD renders captions with a custom DOM renderer over MSE, creates no text
 * tracks at all, and fetches its subtitle file once at player init — too early
 * for any content script to intercept. Its page-gateway API, however, hands out
 * a plain WebVTT URL for the item, which is what we use.
 */
export const ard: Adapter = {
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

    const url = pickArdSubtitleUrl(json);
    if (!url) {
      log.info('ard: no subtitle url in item metadata (episode may have none)');
      return [];
    }

    const track = await fetchCues(url, 'Deutsch (UT)', 'de', 'ard-primary');
    return track ? [track] : [];
  },
};
