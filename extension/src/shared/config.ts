import { Settings } from './types';

/** Injected at build time by esbuild's `define`. */
declare const __MT_DEV__: boolean;

/** True only in dev builds; production compiles the dev-only branches away. */
export const DEV = typeof __MT_DEV__ !== 'undefined' ? __MT_DEV__ : false;

export const DEFAULT_SETTINGS: Settings = {
  enabled: true,
  sourceLang: '',
  targetLang: 'EN-US',
  provider: 'deepl',
  deeplKey: '',
  blurSecondary: false,
  autoPause: false,
  loopCue: false,
  showSecondary: true,
  hideNativeCaptions: true,
  fontScale: 1,
  // Clears the control bar on YouTube, ARD and ZDF, which sit ~10-13% up.
  offsetPct: 15,
  disabledHosts: [],
};

/** DeepL target languages. Source codes are derived by stripping the region. */
export const TARGET_LANGS: Array<[string, string]> = [
  ['EN-US', 'English (US)'],
  ['EN-GB', 'English (UK)'],
  ['DE', 'German'],
  ['FR', 'French'],
  ['ES', 'Spanish'],
  ['IT', 'Italian'],
  ['PT-PT', 'Portuguese'],
  ['PT-BR', 'Portuguese (BR)'],
  ['NL', 'Dutch'],
  ['PL', 'Polish'],
  ['RU', 'Russian'],
  ['UK', 'Ukrainian'],
  ['TR', 'Turkish'],
  ['SV', 'Swedish'],
  ['DA', 'Danish'],
  ['NB', 'Norwegian'],
  ['FI', 'Finnish'],
  ['CS', 'Czech'],
  ['EL', 'Greek'],
  ['HU', 'Hungarian'],
  ['RO', 'Romanian'],
  ['ID', 'Indonesian'],
  ['JA', 'Japanese'],
  ['KO', 'Korean'],
  ['ZH', 'Chinese'],
  ['AR', 'Arabic'],
];

export const SOURCE_LANGS: Array<[string, string]> = [
  ['', 'Auto-detect'],
  ['DE', 'German'],
  ['FR', 'French'],
  ['ES', 'Spanish'],
  ['IT', 'Italian'],
  ['PT', 'Portuguese'],
  ['NL', 'Dutch'],
  ['PL', 'Polish'],
  ['RU', 'Russian'],
  ['UK', 'Ukrainian'],
  ['TR', 'Turkish'],
  ['SV', 'Swedish'],
  ['DA', 'Danish'],
  ['NB', 'Norwegian'],
  ['FI', 'Finnish'],
  ['CS', 'Czech'],
  ['EL', 'Greek'],
  ['HU', 'Hungarian'],
  ['RO', 'Romanian'],
  ['ID', 'Indonesian'],
  ['JA', 'Japanese'],
  ['KO', 'Korean'],
  ['ZH', 'Chinese'],
  ['EN', 'English'],
  ['AR', 'Arabic'],
];

/**
 * CSS that hides each site's own caption rendering, so ours is the only one.
 * Keyed loosely — a selector that matches nothing is harmless.
 */
export const NATIVE_CAPTION_SELECTORS = [
  '.ytp-caption-window-container',                 // YouTube
  '.ardplayer-subtitle, [class*="ardplayer"][class*="subtitle"]', // ARD
  '[class*="zdfplayer"][class*="subtitle"]',       // ZDF
  '.player-timedtext',                             // Netflix
  '.vjs-text-track-display',                       // video.js
  '.shaka-text-container',                         // Shaka
  '.plyr__captions',                               // Plyr
  '.jw-captions',                                  // JW Player
  'video::cue',                                    // native rendering
];
