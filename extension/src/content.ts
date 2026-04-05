import { SubtitleOverlay } from './overlay';
import { translate } from './translate';
import { log } from './logger';

const PRIMARY_LANG = 'de';
const SECONDARY_LANG = 'en';

let overlay: SubtitleOverlay | null = null;
let syncInterval: ReturnType<typeof setInterval> | null = null;

function init() {
  const hostname = window.location.hostname;
  log.info('MajorTom init on', hostname);

  if (hostname.includes('youtube.com')) {
    initYouTube();
  }
}

function initYouTube() {
  const tryStart = () => {
    const video = document.querySelector('video') as HTMLVideoElement;
    const container = document.querySelector('#movie_player') || document.querySelector('.html5-video-player');
    if (!video || !container) {
      setTimeout(tryStart, 500);
      return;
    }
    startDomReading(video, container as HTMLElement);
  };

  tryStart();

  window.addEventListener('yt-navigate-finish', () => {
    cleanup();
    setTimeout(tryStart, 1000);
  });
}

function startDomReading(video: HTMLVideoElement, container: HTMLElement) {
  cleanup();

  overlay = new SubtitleOverlay(video);
  overlay.setTitle(document.title);
  overlay.mount(container);

  const style = document.createElement('style');
  style.id = 'majortom-hide-native';
  style.textContent = `.ytp-caption-window-container { opacity: 0.01 !important; pointer-events: none !important; }`;
  document.head.appendChild(style);

  let lastText = '';
  let lastNonEmpty = '';
  let emptyAt = 0;
  let lastTranslated = '';
  let translated = '';

  syncInterval = setInterval(() => {
    const segments = document.querySelectorAll('.ytp-caption-segment');
    const text = Array.from(segments).map(s => s.textContent?.trim()).filter(Boolean).join(' ');

    if (text && text !== lastText) {
      lastText = text;
      lastNonEmpty = text;
      emptyAt = 0;
    } else if (!text && lastText) {
      lastText = '';
      emptyAt = Date.now();
    }

    const display = text || (emptyAt && Date.now() - emptyAt < 2000 ? lastNonEmpty : '');
    if (display && display !== lastTranslated) {
      lastTranslated = display;
      translate(display, PRIMARY_LANG, SECONDARY_LANG).then(t => { translated = t; });
    }
    if (!display) translated = '';
    overlay?.setLiveText(display, translated);
  }, 50);

  log.info('DOM reading started');
}

function cleanup() {
  if (syncInterval) { clearInterval(syncInterval); syncInterval = null; }
  if (overlay) { overlay.unmount(); overlay = null; }
  document.getElementById('majortom-hide-native')?.remove();
}

init();
