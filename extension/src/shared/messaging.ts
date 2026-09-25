import {BgRequest, BgResponse, Gloss} from './types';
import {log} from './logger';

function send<T>(msg: BgRequest): Promise<BgResponse<T>> {
    return new Promise(resolve => {
        try {
            chrome.runtime.sendMessage(msg, (res: BgResponse<T>) => {
                if (chrome.runtime.lastError) {
                    resolve({ok: false, error: chrome.runtime.lastError.message});
                } else {
                    resolve(res ?? {ok: false, error: 'no response'});
                }
            });
        } catch (e) {
            resolve({ok: false, error: (e as Error)?.message || 'send failed'});
        }
    });
}

/**
 * Fetch through the service worker. Requests from there carry the extension's
 * own host permissions, so cross-origin subtitle APIs work without CORS games.
 */
export async function bgFetch(url: string): Promise<string | null> {
    const res = await send<string>({type: 'FETCH', url});
    if (!res.ok) {
        log.warn('fetch failed', url.slice(0, 120), res.error);
        return null;
    }
    return res.data ?? null;
}

/** Resolves once the page scripts match the current site list. */
export async function bgSyncScripts(): Promise<void> {
    await send({type: 'SYNC_SCRIPTS'});
}

/** Resolves to the translations, or to the reason there are none. */
export async function bgTranslateSubs(
    lines: string[], context: string[], source: string, target: string,
): Promise<{ lines: string[] } | { error: string }> {
    const res = await send<string[]>({type: 'LLM_SUBS', lines, context, source, target});
    if (res.ok && res.data) return {lines: res.data};
    log.warn('translate failed:', res.error);
    return {error: res.error || 'no answer'};
}

export async function bgGloss(
    word: string, sentence: string, source: string, target: string,
): Promise<Gloss | { error: string }> {
    const res = await send<Gloss>({type: 'LLM_GLOSS', word, sentence, source, target});
    if (res.ok && res.data) return res.data;
    log.warn('gloss failed:', res.error);
    return {error: res.error || 'no answer'};
}
