import {getVocab} from '../shared/storage';
import {log} from '../shared/logger';

/** Must match the manifest name registered by desktop/install-host.sh. */
const HOST = 'com.majortom.host';
const DEBOUNCE_MS = 1500;

let timer: ReturnType<typeof setTimeout> | undefined;
let warned = false;

/**
 * Pushes the whole vocabulary rather than a delta. The desktop side upserts, so
 * edits and stars propagate and the first push doubles as the initial import —
 * paid for by resending a list that only ever runs to a few hundred rows.
 *
 * Native messaging only works from the service worker, never a content script.
 */
async function push(): Promise<void> {
    const entries = await getVocab();
    if (!entries.length) return;

    try {
        const res = await chrome.runtime.sendNativeMessage(HOST, {type: 'sync', entries});
        warned = false;
        if (!res?.ok) log.warn('desktop sync rejected:', res?.error);
    } catch (e) {
        // The desktop app is optional: without it the extension still works,
        // and whatever is in storage syncs the next time a word is saved.
        if (!warned) {
            warned = true;
            log.info('desktop app not reachable, vocab stays local:', (e as Error).message);
        }
    }
}

export function schedulePush(): void {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
        timer = undefined;
        void push();
    }, DEBOUNCE_MS);
}

/**
 * Watching storage rather than hooking addWord keeps every caller — overlay,
 * popup, future importers — syncing without knowing the desktop app exists.
 */
export function watchVocab(): void {
    chrome.storage.onChanged.addListener((changes, area) => {
        if (area === 'local' && changes.mt_vocab) schedulePush();
    });
    void push();
}
