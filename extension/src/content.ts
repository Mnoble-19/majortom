import { Cue } from './types';
import { parseYouTubeJSON, parseEBUTT, parseVTT } from './parsers';
import { SubtitleOverlay } from './overlay';
import { log } from './logger';
import { getState } from './storage';

let overlay: SubtitleOverlay | null = null;
let syncInterval: ReturnType<typeof setInterval> | null = null;
let started = false;
let listenerAdded = false;

let interceptedDE: string | null = null;
let interceptedURL: string | null = null;
let pendingVideo: HTMLVideoElement | null = null;
let pendingContainer: HTMLElement | null = null;
let pendingTitle = '';
let primaryLang = 'de';
let secondaryLang = 'en';

async function init() {
  const state = await getState();
  primaryLang = state.primaryLang;
  secondaryLang = state.secondaryLang;

  const hostname = window.location.hostname;
  log.info('init on', hostname, `primary=${primaryLang} secondary=${secondaryLang}`);

  if (hostname.includes('youtube.com')) {
    injectScript();
    waitForVideo();
    window.addEventListener('yt-navigate-finish', () => {
      cleanup();
      interceptedDE = null;
      interceptedURL = null;
      setTimeout(waitForVideo, 1000);
    });
  } else if (hostname.includes('zdf.de') || hostname.includes('ardmediathek.de')) {
    injectScript();
    waitForVideoDE();
  }
}

function injectScript() {
  const script = document.createElement('script');
  script.src = chrome.runtime.getURL('injected.js');
  (document.head || document.documentElement).appendChild(script);
  script.onload = () => script.remove();
}

function waitForVideo() {
  const video = document.querySelector('video') as HTMLVideoElement;
  const container = document.querySelector('#movie_player') as HTMLElement;
  if (!video || !container) { setTimeout(waitForVideo, 500); return; }
  if (started) return;
  started = true;
  pendingVideo = video;
  pendingContainer = container;

  if (!listenerAdded) {
    listenerAdded = true;
    window.addEventListener('message', (e) => {
      if (e.data?.type === 'MAJORTOM_TRACKS') {
        const v = document.querySelector('video') as HTMLVideoElement;
        const c = document.querySelector('#movie_player') as HTMLElement;
        if (v && c) { pendingVideo = v; pendingContainer = c; pendingTitle = e.data.title || ''; }
        log.info('tracks received:', (e.data.tracks || []).map((t: any) => t.languageCode));
      }
      if (e.data?.type === 'MAJORTOM_SUBTITLE_INTERCEPTED') {
        onSubtitleIntercepted(e.data.url, e.data.content);
      }
      if (e.data?.type === 'MAJORTOM_URL_SEEN') {
        log.info(`[url:${e.data.via}]`, e.data.url.substring(0, 140));
      }
    });
  }
}

function waitForVideoDE() {
  const video = document.querySelector('video') as HTMLVideoElement;
  if (!video) { setTimeout(waitForVideoDE, 500); return; }
  if (started) return;
  started = true;

  // Find nearest positioned ancestor as overlay container
  let container: HTMLElement | null = video.parentElement;
  while (container && getComputedStyle(container).position === 'static') {
    container = container.parentElement;
  }
  if (!container) container = video.parentElement;

  pendingVideo = video;
  pendingContainer = container;
  pendingTitle = document.title.replace(/ [-|].*$/, '').trim();

  log.info('DE/ARD video found, title:', pendingTitle, 'container:', container?.tagName, container?.className?.substring(0, 60));

  if (!listenerAdded) {
    listenerAdded = true;
    window.addEventListener('message', (e) => {
      if (e.data?.type === 'MAJORTOM_SUBTITLE_INTERCEPTED') {
        onSubtitleIntercepted(e.data.url, e.data.content);
      }
      if (e.data?.type === 'MAJORTOM_URL_SEEN') {
        log.info(`[url:${e.data.via}]`, e.data.url.substring(0, 140));
      }
    });
  }

  // Re-check container after player fully loads
  setTimeout(() => {
    if (!overlay) {
      const v = document.querySelector('video') as HTMLVideoElement;
      if (v && v !== pendingVideo) {
        log.info('video element changed, updating');
        pendingVideo = v;
      }
    }
  }, 3000);
}

function parseSubtitle(url: string, content: string): Cue[] {
  if (url.includes('zdf.de') || content.trimStart().startsWith('<')) return parseEBUTT(content);
  if (url.includes('.vtt') || content.trimStart().startsWith('WEBVTT')) return parseVTT(content);
  return parseYouTubeJSON(content);
}

function onSubtitleIntercepted(url: string, content: string) {
  if (interceptedDE) return; // already have it
  log.info('intercepted subtitle, length:', content.length, 'url:', url.substring(0, 100));

  const cues = parseSubtitle(url, content);
  log.info('parsed cues:', cues.length);
  if (cues.length === 0) return;

  interceptedDE = content;
  interceptedURL = url;
  tryStart(cues);
}

async function tryStart(deCues: Cue[]) {
  if (overlay) return;
  if (!pendingVideo || !pendingContainer) { log.info('no video/container yet'); return; }

  let enCues: Cue[] = [];
  const hostname = window.location.hostname;

  if (hostname.includes('youtube.com') && interceptedURL) {
    // YouTube: use their own tlang translation endpoint
    const tlangUrl = interceptedURL + `&tlang=${secondaryLang}&fmt=json3`;
    log.info('fetching YT translation:', tlangUrl.substring(0, 120));
    try {
      const resp = await fetch(tlangUrl, { credentials: 'include' });
      const text = await resp.text();
      log.info('translation fetch status:', resp.status, 'length:', text.length);
      if (text) {
        enCues = parseYouTubeJSON(text);
        // Sanity check — if far fewer cues than primary, translation likely failed
        if (enCues.length < 5 && deCues.length > 20) {
          log.info('translation parse suspicious (got', enCues.length, 'cues), discarding. preview:', text.substring(0, 150));
          enCues = [];
        }
      }
      log.info('translation cues:', enCues.length);
    } catch (e: any) {
      log.info('translation fetch error:', e?.message);
    }
  }
  // ZDF/ARD: no tlang equivalent — secondary line empty for now

  startWithCues(pendingVideo, pendingContainer, deCues, enCues, pendingTitle);
}

function startWithCues(
  video: HTMLVideoElement,
  container: HTMLElement,
  primary: Cue[],
  secondary: Cue[],
  title: string
) {
  cleanup();

  overlay = new SubtitleOverlay(video);
  overlay.setTitle(title);
  overlay.mount(container);

  // Inject a persistent style tag — more reliable than inline styles against player JS
  const hideStyle = document.createElement('style');
  hideStyle.id = 'majortom-hide-captions';
  hideStyle.textContent = [
    `.ytp-caption-window-container { display: none !important; }`,   // YouTube
    `[class*="zdfplayer"][class*="subtitle"] { display: none !important; }`, // ZDF
    `[class*="subtitleContainer"] { display: none !important; }`,    // ARD
  ].join('\n');
  document.head.appendChild(hideStyle);

  syncInterval = setInterval(() => {
    const t = video.currentTime;
    const pCue = primary.find(c => t >= c.start && t <= c.end);
    const sCue = secondary.find(c => t >= c.start && t <= c.end);
    overlay?.setLiveText(pCue?.text || '', sCue?.text || '');
  }, 50);

  log.info(`STARTED — primary:${primary.length} cues, secondary:${secondary.length} cues`);
}

function cleanup() {
  if (syncInterval) { clearInterval(syncInterval); syncInterval = null; }
  if (overlay) { overlay.unmount(); overlay = null; }
  started = false;
  document.getElementById('majortom-hide-captions')?.remove();
}

init();
