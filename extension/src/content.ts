import { Cue, CueTrack, MediaInfo, PageMessage, Settings, VocabEntry } from './types';
import { NATIVE_CAPTION_SELECTORS } from './config';
import { adapterFor, mediaInfo, Adapter } from './adapters';
import { parse, cueIndexAt } from './parsers';
import { Overlay, norm } from './overlay';
import { SecondaryLines, translateCues, translateOne } from './translate';
import {
  getSettings, onSettingsChanged, setSettings, isHostEnabled,
  getVocab, addWord, removeWordEverywhere,
} from './storage';
import { log } from './logger';

/** How much a source is trusted; a higher-ranked track replaces a lower one. */
const SOURCE_RANK = { adapter: 4, texttrack: 3, network: 2, dom: 1 } as const;

let settings: Settings;
let adapter: Adapter | null = null;
let media: MediaInfo;

let video: HTMLVideoElement | null = null;
let overlay: Overlay | null = null;
let best: CueTrack | null = null;
let secondary: SecondaryLines = [];
let savedWords = new Set<string>();

let rafId = 0;
let cueHint = 0;
let currentIndex = -1;
let pausedForCue = -1;
let currentKey = '';
let translateToken = 0;

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

  onSettingsChanged(next => {
    const wasEnabled = isHostEnabled(settings);
    settings = next;
    overlay?.applySettings(next);
    applyNativeCaptionCss();
    if (wasEnabled !== isHostEnabled(next)) location.reload();
  });

  // A single loop drives discovery: it notices new videos and SPA navigations
  // without needing site-specific navigation events.
  setInterval(tick, 700);
  tick();
}

/** Tell the MAIN-world script whether to capture, and flush anything buffered. */
function configurePage(active: boolean) {
  window.postMessage({
    src: 'majortom-cfg', active, hideNative: settings?.hideNativeCaptions ?? true,
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
  const key = `${location.href}`;
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
    if (best) mountOverlay();
  }
}
let pageActivated = false;

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
  void resolveViaAdapter();
}

/* ── Cue acquisition ──────────────────────────────────────────────────────── */

async function resolveViaAdapter() {
  if (!adapter) return;
  const token = ++adapterToken;
  try {
    const tracks = await adapter.resolve();
    if (token !== adapterToken) return; // navigated away mid-fetch
    if (tracks.length === 0) {
      log.info(`adapter ${adapter.id}: no subtitles — waiting for generic capture`);
      return;
    }
    for (const t of tracks) offerTrack(t);
  } catch (e) {
    log.warn(`adapter ${adapter.id} failed:`, (e as Error)?.message);
  }
}
let adapterToken = 0;

/** Accept a candidate track, keeping the best source seen for this media. */
function offerTrack(track: CueTrack) {
  if (track.cues.length === 0) return;

  if (best) {
    const better = SOURCE_RANK[track.source] > SOURCE_RANK[best.source];
    const sameTrackGrew = best.id === track.id && track.cues.length > best.cues.length;
    if (!better && !sameTrackGrew) return;
  }

  const isNew = !best || best.id !== track.id;
  best = track;
  log.info(`cues: ${track.cues.length} from ${track.source} (${track.label})`);

  mountOverlay();
  if (isNew) void runTranslation();
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
      media = { ...media, title: d.title };
    }
  });
}

/* ── Translation ──────────────────────────────────────────────────────────── */

async function runTranslation() {
  if (!best) return;
  const token = ++translateToken;
  const cues = best.cues;

  secondary = new Array(cues.length).fill('');
  const needsWork = settings.showSecondary
    && (adapter?.translated !== undefined || (settings.provider === 'deepl' && !!settings.deeplKey.trim()));
  overlay?.setStatus(needsWork ? 'translating…' : '');

  const lines = await translateCues({
    cues,
    sourceLangHint: best.lang,
    settings,
    media,
    adapter,
    onProgress: (partial, done) => {
      if (token !== translateToken) return;
      secondary = partial;
      if (done) overlay?.setStatus('');
    },
  });

  if (token !== translateToken) return;
  secondary = lines;
  overlay?.setStatus(lines.some(Boolean) ? '' : '');
}

/* ── Overlay + playback sync ──────────────────────────────────────────────── */

function mountOverlay() {
  if (!video || !best || overlay) return;
  applyNativeCaptionCss();

  overlay = new Overlay(video, settings, {
    isSaved: w => savedWords.has(w),
    lookup: w => translateOne(w, best?.lang || '', settings),
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
    removeWord: async word => {
      savedWords.delete(word);
      await removeWordEverywhere(word);
    },
    patchSettings: patch => { void setSettings(patch); },
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

    if (settings.autoPause) autoPause(t);
  };
  rafId = requestAnimationFrame(frame);
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
  if (video.paused) void video.play().catch(() => {});
}

function replayCue() {
  if (!video || !best) return;
  const i = cueIndexAt(best.cues, video.currentTime, cueHint);
  const cue = best.cues[i >= 0 ? i : Math.max(0, cueHint)];
  if (!cue) return;
  video.currentTime = cue.start + 0.01;
  pausedForCue = -1;
  void video.play().catch(() => {});
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
      case '[': e.preventDefault(); e.stopPropagation(); seekCue(-1); break;
      case ']': e.preventDefault(); e.stopPropagation(); seekCue(1); break;
      case '\\': e.preventDefault(); e.stopPropagation(); replayCue(); break;
      case 'p': case 'P':
        e.preventDefault(); e.stopPropagation();
        void setSettings({ autoPause: !settings.autoPause });
        break;
      case 'h': case 'H':
        e.preventDefault(); e.stopPropagation();
        void setSettings({ blurSecondary: !settings.blurSecondary });
        break;
      default: break;
    }
  }, true);
}

/* ── Go ───────────────────────────────────────────────────────────────────── */

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && changes.mt_vocab) void loadVocab();
});

void boot();
