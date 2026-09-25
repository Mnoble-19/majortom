import {CueTrack, Gloss, MediaInfo, PageMessage, Settings, VocabEntry} from './shared/types';
import {NATIVE_CAPTION_SELECTORS} from './shared/config';
import {Adapter, adapterFor, mediaInfo} from './capture/adapters';
import {cueIndexAt, parse} from './capture/parsers';
import {Overlay} from './ui/overlay';
import {SecondaryLines, translateCues, translateOne} from './translate';
import {
  addWord,
  getSettings,
  getVocab,
  isHostEnabled,
  onSettingsChanged,
  removeWordEverywhere,
  setSettings,
  updateWord,
} from './shared/storage';
import {log} from './shared/logger';

/** How much a source is trusted; a higher-ranked track replaces a lower one. */
const SOURCE_RANK = {adapter: 4, texttrack: 3, network: 2, dom: 1} as const;

let settings: Settings;
let adapter: Adapter | null = null;
let media: MediaInfo;

let video: HTMLVideoElement | null = null;
let overlay: Overlay | null = null;
let best: CueTrack | null = null;
let secondary: SecondaryLines = [];
let savedWords = new Set<string>();
/** Word + sentence → gloss, so clicking the same word again costs nothing. */
const lookupCache = new Map<string, Gloss>();

let rafId = 0;
let cueHint = 0;
let currentIndex = -1;
let pausedForCue = -1;
let currentKey = '';

/** Bumped on navigation so in-flight async work knows it is stale. */
let translateToken = 0;
let adapterToken = 0;
/** Generic capture stays off until a video actually shows up on the page. */
let pageActivated = false;

/* ── Boot ─────────────────────────────────────────────────────────────────── */

async function boot() {
    settings = await getSettings();
    adapter = adapterFor();

    if (!isHostEnabled(settings)) {
        log.info('disabled for', location.hostname);
        configurePage(false);
        return;
    }

    log.info(`init on ${location.hostname}${adapter ? ` (adapter: ${adapter.id})` : ' (generic capture)'}`);
    listenToPage();
    installKeyboard();

    // Turning the site off is handled by the popup, which reloads the tab once
    // the scripts are unregistered. Nothing here reloads the page.
    onSettingsChanged(next => {
        settings = next;
        overlay?.applySettings(next);
        applyNativeCaptionCss();
    });

    // A single loop drives discovery: it notices new videos and SPA navigations
    // without needing site-specific navigation events.
    setInterval(tick, 700);
    tick();
}

/** Tell the MAIN-world script whether to capture, and flush anything buffered. */
function configurePage(active: boolean) {
    window.postMessage({
        src: 'majortom-cfg',
        active,
        hideNative: settings?.hideNativeCaptions ?? true,
        // Body sniffing is only worth its cost while we have nothing better.
        hungry: !best,
        // Which dub to keep and which caption track to prefer on YouTube.
        learning: (settings?.sourceLang || 'de').toLowerCase(),
    }, '*');
}

/* ── Discovery loop ───────────────────────────────────────────────────────── */

function pickVideo(): HTMLVideoElement | null {
    const vids = Array.from(document.querySelectorAll('video'))
        .filter(v => v.readyState > 0 || v.currentSrc || v.src);
    if (vids.length === 0) return null;
    // The one actually being watched is the biggest one on screen.
    return vids.sort((a, b) => b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight)[0];
}

function tick() {
    // The media key, not the URL: YouTube rewrites its query string after a
    // video loads, and that is not a new video.
    const key = mediaInfo(adapter).key;
    if (key !== currentKey) {
        currentKey = key;
        onMediaChanged();
    }

    const v = pickVideo();
    if (v && v !== video) {
        log.info('video element attached');
        video = v;
        // Generic capture only switches on once a video exists, so the network
        // hooks stay silent on ordinary pages.
        if (!pageActivated) {
            pageActivated = true;
            configurePage(true);
        }
        startSync();
        mountOverlay();
        if (adapter && !best) {
            overlay?.setStatus('MajorTom: looking for subtitles…', 4000);
            void resolveViaAdapter();
        }
        if (best) scheduleTranslation();
    }
}

function onMediaChanged() {
    log.info('media changed →', location.href.slice(0, 120));
    translateToken++;
    teardownOverlay();
    best = null;
    secondary = [];
    cueHint = 0;
    currentIndex = -1;
    pausedForCue = -1;
    media = mediaInfo(adapter);
    void loadVocab();
    // Only a frame with a video does any work. Embedded frames on the same
    // site would otherwise each fetch and translate the same subtitles.
    if (video) void resolveViaAdapter();
}

/* ── Cue acquisition ──────────────────────────────────────────────────────── */

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

/**
 * Sites publish their player metadata some time after navigation — YouTube in
 * particular swaps the URL well before the new track list exists — so a single
 * attempt loses the race on SPA navigations.
 */
const ADAPTER_RETRY_MS = [0, 500, 1200, 2500, 5000, 10000, 20000];

async function resolveViaAdapter() {
    if (!adapter) return;
    const token = ++adapterToken;

    for (const delay of ADAPTER_RETRY_MS) {
        if (delay) await sleep(delay);
        if (token !== adapterToken) return; // navigated away mid-flight

        try {
            const tracks = await adapter.resolve(settings.sourceLang || 'de');
            if (token !== adapterToken) return;
            if (tracks.length > 0) {
                for (const t of tracks) offerTrack(t);
                return;
            }
        } catch (e) {
            log.warn(`adapter ${adapter.id} failed:`, (e as Error)?.message);
        }
    }

    log.info(`adapter ${adapter.id}: no subtitles after retries`);
    if (!best) {
        overlay?.setStatus('MajorTom: no subtitles for this video', 6000);
    }
}

/** Accept a candidate track, keeping the best source seen for this media. */
function offerTrack(track: CueTrack) {
    if (track.cues.length === 0) return;

    if (best) {
        const better = SOURCE_RANK[track.source] > SOURCE_RANK[best.source];
        const sameTrackGrew = best.id === track.id && track.cues.length > best.cues.length;
        if (!better && !sameTrackGrew) return;
    }

    const wasHungry = !best;
    best = track;
    log.info(`cues: ${track.cues.length} from ${track.source} (${track.label})`);
    if (wasHungry && pageActivated) configurePage(true); // stop body sniffing

    mountOverlay();
    overlay?.setStatus('');
    // A grown track is translated again too: the cache holds every sentence
    // already done, so only the new ones reach the model.
    if (video) scheduleTranslation();
}

function listenToPage() {
    window.addEventListener('message', e => {
        const d = e.data as PageMessage;
        if (e.source !== window || !d || d.src !== 'majortom') return;

        if (d.kind === 'track-cues') {
            offerTrack({
                id: `tt:${d.trackId}`, lang: d.lang, label: d.label,
                source: 'texttrack', cues: d.cues,
            });
        } else if (d.kind === 'sub-file') {
            const cues = parse(d.body, d.url);
            if (cues.length === 0) return;
            offerTrack({
                id: `net:${d.url.slice(0, 120)}`, lang: '', label: 'captured',
                source: 'network', cues,
            });
        } else if (d.kind === 'media-meta' && d.title) {
            media = {...media, title: d.title};
        } else if (d.kind === 'yt-update' && video && !best) {
            // The caption token arrived: the adapter can fetch tracks now.
            void resolveViaAdapter();
        }
    });
}

/* ── Translation ──────────────────────────────────────────────────────────── */

let translateTimer: ReturnType<typeof setTimeout> | undefined;

/**
 * Waits for the sources to settle first. A page often offers the same
 * subtitles several times in its first seconds — captured off the network,
 * then from a text track, then from the site's API — and each used to start
 * a full translation of its own.
 */
function scheduleTranslation() {
    translateToken++; // stops whatever is running now, before its next request
    clearTimeout(translateTimer);
    translateTimer = setTimeout(() => void runTranslation(), 1200);
}

async function runTranslation() {
    if (!best || !video) return;
    const token = ++translateToken;
    const cues = best.cues;
    const stale = () => token !== translateToken;

    // Keep showing what we had until the new job has something, so a grown
    // track does not blank the line while its first batch is out.
    if (secondary.length !== cues.length) secondary = new Array(cues.length).fill('');

    const lines = await translateCues({
        cues,
        sourceLangHint: best.lang,
        settings,
        media,
        adapter,
        now: () => video?.currentTime || 0,
        isStale: stale,
        onProgress: partial => {
            if (!stale()) secondary = partial;
        },
        onStatus: (text, ms) => {
            if (!stale()) overlay?.setStatus(text, ms);
        },
    });

    if (stale()) return;
    secondary = lines;
}

/* ── Overlay + playback sync ──────────────────────────────────────────────── */

/**
 * Mounted as soon as a video exists rather than waiting for cues, so the
 * status line can report what is happening — including that nothing was found.
 */
function mountOverlay() {
    if (!video || overlay) return;
    applyNativeCaptionCss();

    overlay = new Overlay(video, settings, {
        isSaved: w => savedWords.has(w),
        savedPhrases: () => [...savedWords].filter(w => w.includes(' ')),
        lookup: async w => {
            const sentence = best?.cues[currentIndex]?.text || '';
            // Keyed by sentence too: the whole point is the meaning in context.
            const key = `${w}\n${sentence}`;
            const hit = lookupCache.get(key);
            if (hit) return hit;
            const out = await translateOne(w, sentence, best?.lang || '', settings);
            // Failures are not cached, so starting the model and clicking
            // again works.
            if (!('error' in out)) lookupCache.set(key, out);
            return out;
        },
        saveWord: async (word, translation) => {
            const entry: VocabEntry = {
                word,
                translation,
                context: best?.cues[currentIndex]?.text || '',
                contextTranslation: secondary[currentIndex] || '',
                site: media.site,
                title: media.title,
                url: media.url,
                time: video?.currentTime || 0,
                createdAt: new Date().toISOString(),
                starred: false,
            };
            savedWords.add(word);
            await addWord(entry);
        },
        setMeaning: async (word, translation) => {
            // Only ever fills a blank, never replaces a meaning already there.
            const entry = (await getVocab()).find(v => v.word === word && v.url === media.url);
            if (entry && !entry.translation) await updateWord(word, media.url, {translation});
        },
        removeWord: async word => {
            savedWords.delete(word);
            await removeWordEverywhere(word);
        },
        patchSettings: patch => {
            void setSettings(patch);
        },
        seekToCue: delta => seekCue(delta),
        replayCue: () => replayCue(),
    });

    overlay.mount();
    startSync();
    log.info('overlay mounted');
}

function teardownOverlay() {
    overlay?.unmount();
    overlay = null;
    cancelAnimationFrame(rafId);
    rafId = 0;
    document.getElementById('majortom-native-css')?.remove();
}

function startSync() {
    cancelAnimationFrame(rafId);
    const frame = () => {
        rafId = requestAnimationFrame(frame);
        if (!video || !best || !overlay) return;

        const t = video.currentTime;
        const i = cueIndexAt(best.cues, t, cueHint);
        if (i >= 0) cueHint = i;

        if (i !== currentIndex) {
            currentIndex = i;
            overlay.setLines(i >= 0 ? best.cues[i].text : '', i >= 0 ? (secondary[i] || '') : '');
        } else if (i >= 0 && overlay) {
            // Translation may have arrived after the cue was first shown.
            overlay.setLines(best.cues[i].text, secondary[i] || '');
        }

        if (settings.loopCue) loopCue(t);
        else if (settings.autoPause) autoPause(t);
    };
    rafId = requestAnimationFrame(frame);
}

/** Jump back to the start of the current line as soon as it finishes. */
function loopCue(t: number) {
    if (!video || !best || video.paused) return;
    const cue = best.cues[cueHint];
    if (cue && t > cue.end) video.currentTime = cue.start + 0.01;
}

/**
 * Pause once, just after a cue ends, so you get a beat to read it. Resuming
 * moves on normally rather than re-pausing on the same cue.
 */
function autoPause(t: number) {
    if (!video || !best || video.paused) return;
    const prev = cueHint;
    const cue = best.cues[prev];
    if (!cue) return;
    if (t > cue.end && t < cue.end + 0.35 && pausedForCue !== prev) {
        pausedForCue = prev;
        video.pause();
    }
}

function seekCue(delta: number) {
    if (!video || !best) return;
    const at = cueIndexAt(best.cues, video.currentTime, cueHint);
    let target: number;
    if (at >= 0) {
        target = at + delta;
    } else {
        // Between cues: step to the neighbouring one in the requested direction.
        let next = best.cues.findIndex(c => c.start > video!.currentTime);
        if (next < 0) next = best.cues.length;
        target = delta > 0 ? next : next - 1;
    }
    target = Math.max(0, Math.min(best.cues.length - 1, target));
    video.currentTime = best.cues[target].start + 0.01;
    pausedForCue = -1;
    if (video.paused) void video.play().catch(() => {
    });
}

function replayCue() {
    if (!video || !best) return;
    const i = cueIndexAt(best.cues, video.currentTime, cueHint);
    const cue = best.cues[i >= 0 ? i : Math.max(0, cueHint)];
    if (!cue) return;
    video.currentTime = cue.start + 0.01;
    pausedForCue = -1;
    void video.play().catch(() => {
    });
}

/* ── Native captions ──────────────────────────────────────────────────────── */

function applyNativeCaptionCss() {
    document.getElementById('majortom-native-css')?.remove();
    if (!settings.hideNativeCaptions) return;
    const style = document.createElement('style');
    style.id = 'majortom-native-css';
    style.textContent = `${NATIVE_CAPTION_SELECTORS.join(',\n')} { display: none !important; }`;
    (document.head || document.documentElement).appendChild(style);
}

/* ── Vocabulary ───────────────────────────────────────────────────────────── */

async function loadVocab() {
    const vocab = await getVocab();
    savedWords = new Set(vocab.map(v => v.word));
    overlay?.refreshSaved();
}

/* ── Keyboard ─────────────────────────────────────────────────────────────── */

function isTyping(target: EventTarget | null): boolean {
    const el = target as HTMLElement | null;
    if (!el) return false;
    if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement) return true;
    return !!el.closest?.('[contenteditable=""], [contenteditable="true"]');
}

/**
 * Bracket keys are used because every video site already claims the letters and
 * arrows, and we should never fight the player for its own shortcuts.
 */
function installKeyboard() {
    document.addEventListener('keydown', e => {
        if (!overlay || e.metaKey || e.ctrlKey || e.altKey || isTyping(e.target)) return;

        switch (e.key) {
            case '[':
                e.preventDefault();
                e.stopPropagation();
                seekCue(-1);
                break;
            case ']':
                e.preventDefault();
                e.stopPropagation();
                seekCue(1);
                break;
            case '\\':
                e.preventDefault();
                e.stopPropagation();
                replayCue();
                break;
            case 'p':
            case 'P':
                e.preventDefault();
                e.stopPropagation();
                void setSettings({autoPause: !settings.autoPause});
                break;
            case 'h':
            case 'H':
                e.preventDefault();
                e.stopPropagation();
                void setSettings({blurSecondary: !settings.blurSecondary});
                break;
            case 'l':
            case 'L':
                e.preventDefault();
                e.stopPropagation();
                void setSettings({loopCue: !settings.loopCue});
                break;
            default:
                break;
        }
    }, true);
}

/* ── Go ───────────────────────────────────────────────────────────────────── */

chrome.storage.onChanged.addListener((changes, area) => {
    if (area === 'local' && changes.mt_vocab) void loadVocab();
});

void boot();
