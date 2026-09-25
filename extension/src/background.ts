import {BgRequest, BgResponse} from './shared/types';
import {getSettings, onSettingsChanged} from './shared/storage';
import {gloss, translateSubs} from './translate/llm';
import {watchVocab} from './sync/desktop';

/** Subtitle files are text; anything much bigger than this is not one. */
const MAX_BODY_BYTES = 8 * 1024 * 1024;

let registering = Promise.resolve();
let registeredFor = '';

/** Serialised, because two overlapping runs would register the same ids. */
function syncScripts(): void {
    registering = registering.then(registerScripts).catch(e => console.warn('MajorTom: register failed', e));
}

chrome.runtime.onInstalled.addListener(() => {
    syncScripts();
    void dropRetiredSettings();
});
chrome.runtime.onStartup.addListener(syncScripts);
onSettingsChanged(s => {
    // Settings change on every slider move; only the site list matters here.
    if (s.enabledHosts.join() !== registeredFor) syncScripts();
});

watchVocab();

/** Settings from before the local model, including the DeepL key. */
async function dropRetiredSettings(): Promise<void> {
    const r = await chrome.storage.local.get('mt_settings');
    const stored = r.mt_settings as Record<string, unknown> | undefined;
    if (!stored) return;
    const retired = ['deeplKey', 'provider', 'enabled', 'disabledHosts'];
    if (!retired.some(k => k in stored)) return;
    for (const k of retired) delete stored[k];
    await chrome.storage.local.set({mt_settings: stored});
    // Keyed by sentence count and sized for DeepL; the new cache is per sentence.
    await chrome.storage.local.remove('mt_tcache');
}

/**
 * The page scripts are registered only for the sites you turned on, rather
 * than declared in the manifest for every URL. The capture script patches the
 * page's fetch and XHR, which no site you did not ask for should ever get.
 */
async function registerScripts(): Promise<void> {
    const {enabledHosts} = await getSettings();
    registeredFor = enabledHosts.join();
    const matches = enabledHosts.flatMap(h => [`*://${h}/*`, `*://*.${h}/*`]);

    const existing = await chrome.scripting.getRegisteredContentScripts();
    if (existing.length) await chrome.scripting.unregisterContentScripts();
    if (matches.length === 0) return;

    await chrome.scripting.registerContentScripts([
        {
            id: 'mt-capture', js: ['injected.js'], matches, world: 'MAIN',
            runAt: 'document_start', allFrames: true,
        },
        {
            id: 'mt-content', js: ['content.js'], matches,
            runAt: 'document_idle', allFrames: true,
        },
    ]);
}

async function handle(msg: BgRequest): Promise<BgResponse> {
    switch (msg.type) {
        case 'FETCH': {
            const res = await fetch(msg.url, {
                credentials: 'include',
                headers: msg.init?.headers,
            });
            if (!res.ok) return {ok: false, error: `HTTP ${res.status}`};

            const len = Number(res.headers.get('content-length') || 0);
            if (len > MAX_BODY_BYTES) return {ok: false, error: 'response too large'};

            return {ok: true, data: await res.text()};
        }

        case 'SYNC_SCRIPTS': {
            syncScripts();
            await registering;
            return {ok: true};
        }

        case 'LLM_SUBS':
            return {ok: true, data: await translateSubs(msg.lines, msg.context, msg.source, msg.target)};

        case 'LLM_GLOSS':
            return {ok: true, data: await gloss(msg.word, msg.sentence, msg.source, msg.target)};

        default:
            return {ok: false, error: 'unknown message'};
    }
}

chrome.runtime.onMessage.addListener((msg: BgRequest, _sender, sendResponse) => {
    handle(msg)
        .then(sendResponse)
        .catch((e: Error) => sendResponse({ok: false, error: e?.message || String(e)}));
    return true; // keep the channel open for the async reply
});
