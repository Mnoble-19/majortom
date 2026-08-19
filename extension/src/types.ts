export interface Cue {
  start: number;
  end: number;
  text: string;
}

/** Where a set of cues came from, in descending order of trustworthiness. */
export type CaptureSource = 'adapter' | 'texttrack' | 'network' | 'dom';

export interface CueTrack {
  id: string;
  lang: string;
  label: string;
  source: CaptureSource;
  cues: Cue[];
}

/** Metadata about the thing currently playing, used for vocab attribution. */
export interface MediaInfo {
  title: string;
  site: string;
  url: string;
  /** Stable-ish key for caching translations per video. */
  key: string;
}

export type ProviderId = 'none' | 'deepl' | 'yt-tlang';

export interface Settings {
  enabled: boolean;
  /** Language of the video's own subtitles. '' = auto/whatever the site gives us. */
  sourceLang: string;
  /** Language we translate into (DeepL target code, e.g. 'EN-US'). */
  targetLang: string;
  provider: ProviderId;
  deeplKey: string;
  /** Hide the translation line until hovered — forces you to try first. */
  blurSecondary: boolean;
  /** Pause automatically at the end of every cue. */
  autoPause: boolean;
  showSecondary: boolean;
  hideNativeCaptions: boolean;
  fontScale: number;
  /** Vertical offset from the bottom of the player, in % of player height. */
  offsetPct: number;
  /** Hosts where the overlay is explicitly turned off. */
  disabledHosts: string[];
}

export interface VocabEntry {
  word: string;
  translation: string;
  context: string;
  contextTranslation: string;
  site: string;
  title: string;
  url: string;
  /** Playback position, so you can jump back to the moment. */
  time: number;
  createdAt: string;
  starred: boolean;
}

/* ── Messages: MAIN world (captured page internals) → content script ───────── */

export type PageMessage =
  | { src: 'majortom'; kind: 'track-cues'; trackId: string; lang: string; label: string; cues: Cue[] }
  | { src: 'majortom'; kind: 'sub-file'; url: string; body: string }
  | { src: 'majortom'; kind: 'media-meta'; title: string; extra?: Record<string, unknown> };

/* ── Messages: content/popup → background service worker ───────────────────── */

export type BgRequest =
  | { type: 'FETCH'; url: string; init?: { headers?: Record<string, string> } }
  | { type: 'TRANSLATE'; texts: string[]; source: string; target: string; key: string };

export interface BgResponse<T = unknown> {
  ok: boolean;
  data?: T;
  error?: string;
}
