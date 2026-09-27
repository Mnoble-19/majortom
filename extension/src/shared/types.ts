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

export interface Settings {
    /** Sites the extension runs on, without `www.`. Nothing runs anywhere else. */
    enabledHosts: string[];
    /** Language of the video's own subtitles. '' = auto/whatever the site gives us. */
    sourceLang: string;
    /** Language we translate into, e.g. 'EN-US'. Only the part before the dash matters. */
    targetLang: string;
    /** OpenAI-compatible base URL of the local model, e.g. llama-server's `/v1`. */
    llmEndpoint: string;
    /** '' uses the first model the endpoint lists. */
    llmModel: string;
    /** Hide the translation line until hovered — forces you to try first. */
    blurSecondary: boolean;
    /** Pause while the pointer is over the subtitles, resume when it leaves. */
    hoverPause: boolean;
    /** The bar of line controls above the subtitles. The keys work without it. */
    showToolbar: boolean;
    /** Pause automatically at the end of every cue. */
    autoPause: boolean;
    /** Repeat the current line until you move on — for shadowing practice. */
    loopCue: boolean;
    showSecondary: boolean;
    hideNativeCaptions: boolean;
    fontScale: number;
    /** Vertical offset from the bottom of the player, in % of player height. */
    offsetPct: number;
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
    | { src: 'majortom'; kind: 'media-meta'; title: string }
    /** New YouTube track data (or its token) is on the page attribute. */
    | { src: 'majortom'; kind: 'yt-update'; v: string };

/* ── Messages: content/popup → background service worker ───────────────────── */

export type BgRequest =
    | { type: 'FETCH'; url: string; init?: { headers?: Record<string, string> } }
    | { type: 'SYNC_SCRIPTS' }
    | { type: 'LLM_SUBS'; lines: string[]; context: string[]; source: string; target: string }
    | { type: 'LLM_GLOSS'; word: string; sentence: string; source: string; target: string };

/** A clicked word, as the model explains it. */
export interface Gloss {
    /** The form you would look up: `rausholen` for `holt … raus`. */
    form: string;
    /** What it means in this sentence. */
    meaning: string;
}

export interface BgResponse<T = unknown> {
    ok: boolean;
    data?: T;
    error?: string;
}
