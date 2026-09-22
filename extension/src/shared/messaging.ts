import {BgRequest, BgResponse} from './types';
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

export async function bgTranslate(
    texts: string[], source: string, target: string, key: string,
): Promise<string[] | null> {
    const res = await send<string[]>({type: 'TRANSLATE', texts, source, target, key});
    if (!res.ok) {
        log.warn('translate failed:', res.error);
        return null;
    }
    return res.data ?? null;
}
