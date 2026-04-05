import { SubtitleTrack } from './types';
import { parseYouTubeXML, parseVTT } from './parsers';
import { SubtitleOverlay } from './overlay';

let overlay: SubtitleOverlay | null = null;

function injectPageScript() {
  const script = document.createElement('script');
  script.src = chrome.runtime.getURL('injected.js');
  (document.head || document.documentElement).appendChild(script);
  script.onload = () => script.remove();
}

function getVideoElement(): HTMLVideoElement | null {
  return document.querySelector('video');
}

function getVideoContainer(): HTMLElement | null {
  const hostname = window.location.hostname;
  if (hostname.includes('youtube.com')) {
    return document.querySelector('#movie_player') || document.querySelector('.html5-video-player');
  }
  if (hostname.includes('zdf.de') || hostname.includes('ardmediathek.de')) {
    const video = getVideoElement();
    return video?.closest('.player-container') || video?.parentElement || null;
  }
  return null;
}

async function fetchSubtitleContent(url: string): Promise<string> {
  const resp = await fetch(url);
  return resp.text();
}

async function loadTrack(track: SubtitleTrack, allTracks: SubtitleTrack[]): Promise<import('./types').Cue[]> {
  const langCode = track.languageCode;
  const isMachineTranslate = langCode.startsWith('mt:');

  if (isMachineTranslate) {
    const targetLang = langCode.replace('mt:', '');
    const sourceTrack = allTracks.find(t => !t.languageCode.startsWith('mt:') && t.isTranslatable);
    if (!sourceTrack) return [];
    const mtUrl = sourceTrack.url + `&tlang=${targetLang}`;
    const xml = await fetchSubtitleContent(mtUrl);
    return parseYouTubeXML(xml);
  }

  const content = await fetchSubtitleContent(track.url);
  if (content.trim().startsWith('WEBVTT') || content.includes('-->')) {
    return parseVTT(content);
  }
  return parseYouTubeXML(content);
}

async function handleTracksDiscovered(tracks: SubtitleTrack[], title: string) {
  const video = getVideoElement();
  const container = getVideoContainer();
  if (!video || !container) return;

  if (overlay) overlay.unmount();
  overlay = new SubtitleOverlay(video);
  overlay.setTitle(title);
  overlay.mount(container);

  overlay.populateLanguageSelectors(tracks, async (primaryLang, secondaryLang) => {
    const primaryTrack = tracks.find(t => t.languageCode === primaryLang)
      || { languageCode: primaryLang, label: primaryLang, url: '' };
    const secondaryTrack = tracks.find(t => t.languageCode === secondaryLang)
      || { languageCode: secondaryLang, label: secondaryLang, url: '' };

    const [primaryCues, secondaryCues] = await Promise.all([
      loadTrack(primaryTrack, tracks),
      loadTrack(secondaryTrack, tracks),
    ]);

    overlay!.setCues(primaryCues, secondaryCues);
  });
}

function initYouTube() {
  injectPageScript();

  window.addEventListener('message', (e) => {
    if (e.data?.type === 'MAJORTOM_TRACKS') {
      handleTracksDiscovered(e.data.tracks, e.data.title);
    }
  });
}

function initZDFARD() {
  const observer = new MutationObserver(() => {
    const video = getVideoElement();
    if (!video) return;

    const trackEls = video.querySelectorAll('track');
    if (trackEls.length === 0) {
      const allTracks = document.querySelectorAll('track');
      if (allTracks.length === 0) return;
    }

    observer.disconnect();

    const tracks: SubtitleTrack[] = [];
    document.querySelectorAll('track').forEach(el => {
      const src = el.getAttribute('src');
      const label = el.getAttribute('label') || el.getAttribute('srclang') || 'Unknown';
      const lang = el.getAttribute('srclang') || 'unknown';
      if (src) {
        tracks.push({
          label,
          languageCode: lang,
          url: new URL(src, window.location.href).href,
        });
      }
    });

    const title = document.title.replace(/ - ZDF| - ARD/i, '').trim();
    if (tracks.length > 0) {
      handleTracksDiscovered(tracks, title);
    }
  });

  observer.observe(document.body, { childList: true, subtree: true });
}

function init() {
  const hostname = window.location.hostname;

  if (hostname.includes('youtube.com')) {
    initYouTube();
  } else if (hostname.includes('zdf.de') || hostname.includes('ardmediathek.de')) {
    initZDFARD();
  }
}

init();
