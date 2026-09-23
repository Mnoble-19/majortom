/**
 * Every fact the site states lives here, so copy and code never drift apart.
 * Descriptions are drawn from the extension's own source and README.
 */

export const site = {
  name: "MajorTom",
  tagline: "Dual subtitles and click-to-save vocabulary, on any video site.",
  description:
    "A browser extension that stacks the original subtitle line above its translation on any video site, and makes every word clickable — click one to look it up and keep it with the sentence it came from.",
  version: "0.2.0",
  repo: "https://github.com/karamazov19/majortom",
  releases: "https://github.com/karamazov19/majortom/releases",
  issues: "https://github.com/karamazov19/majortom/issues",
  deepl: "https://www.deepl.com/pro-api",
  url: "https://karamazov19.github.io/majortom-site",
} as const;

export const nav = [
  { href: "/install", label: "Install" },
  { href: "/how-it-works", label: "How it works" },
  { href: "/sites", label: "Sites" },
  { href: "/shortcuts", label: "Shortcuts" },
  { href: "/roadmap", label: "Roadmap" },
] as const;

/* ── Home: the three principles ───────────────────────────────────────────── */

export const principles = [
  {
    n: "01",
    title: "Read it twice",
    body: "The line you hear stays on top. Its translation sits underneath, one size smaller and one shade quieter, so your eye lands on the original first. Blur the translation and it only resolves when you reach for it — you guess before you check.",
  },
  {
    n: "02",
    title: "Keep the word",
    body: "Every word in the original is a target. Click one and it is looked up, saved, and filed with the whole sentence it came from, the video title, and the timestamp — so it arrives in your list already carrying its context.",
  },
  {
    n: "03",
    title: "Never fight the player",
    body: "Shortcuts live on the bracket keys, because every video site has already claimed the letters and the arrows. The site's own captions are hidden rather than covered, so exactly one line is ever drawn on screen.",
  },
] as const;

/* ── The layered capture stack ────────────────────────────────────────────── */

export type CaptureLayer = {
  rank: string;
  name: string;
  status?: "best" | "off";
  how: string;
  detail: string;
  covers: string[];
};

export const captureLayers: CaptureLayer[] = [
  {
    rank: "04",
    name: "Adapter",
    status: "best",
    how: "Reads the site's own metadata API for a subtitle file URL.",
    detail:
      "Deterministic, needs no race against the player, and works whether or not you ever turn the site's captions on. This is the path every site should eventually get.",
    covers: ["ARD", "ZDF", "YouTube"],
  },
  {
    rank: "03",
    name: "Text tracks",
    how: "Hooks video.textTracks and forces each track to hidden.",
    detail:
      "Setting a track to hidden rather than showing populates its cues without the browser drawing them — which is exactly right, because MajorTom draws its own line.",
    covers: ["hls.js", "dash.js", "Shaka", "video.js", "JW", "Plyr", "<track>"],
  },
  {
    rank: "02",
    name: "Network",
    how: "Watches fetch and XHR responses, then sniffs the body itself.",
    detail:
      "URLs lie and extensions are often missing, so the format is detected from the first few hundred bytes of the response rather than trusted from its name.",
    covers: ["WebVTT", "TTML", "SRT", "json3"],
  },
  {
    rank: "01",
    name: "DOM",
    status: "off",
    how: "Reading captions straight off the page.",
    detail:
      "Designed for and ranked, but not implemented. It is the layer that would cover DRM sites generically, without an adapter per service.",
    covers: ["planned"],
  },
];

/* ── Site support ─────────────────────────────────────────────────────────── */

export type SiteStatus = "full" | "partial" | "generic" | "none";

export type SupportedSite = {
  name: string;
  status: SiteStatus;
  via: string;
  note: string;
};

export const statusLabel: Record<SiteStatus, string> = {
  full: "Adapter",
  partial: "Adapter, fragile",
  generic: "Generic capture",
  none: "Not covered",
};

export const supportedSites: SupportedSite[] = [
  {
    name: "YouTube",
    status: "full",
    via: "Adapter",
    note: "Caption list read from the player response. YouTube also translates its own subtitles server-side, so no API key is needed here at all.",
  },
  {
    name: "ARD Mediathek",
    status: "full",
    via: "Adapter",
    note: "Subtitle URL comes from the page-gateway API. The cleanest path of the three, and the reason the adapter layer exists.",
  },
  {
    name: "ZDF",
    status: "partial",
    via: "Adapter",
    note: "Subtitle URLs are scraped out of the page rather than asked for, because the API wants an auth token. More fragile than ARD's route.",
  },
  {
    name: "Sites using hls.js, dash.js, Shaka, video.js, JW or Plyr",
    status: "generic",
    via: "Text tracks",
    note: "Anything that creates real text tracks is picked up without a line of site-specific code.",
  },
  {
    name: "Sites that fetch a whole subtitle file",
    status: "generic",
    via: "Network",
    note: "If a VTT, TTML, SRT or json3 file crosses the network after the page loads, it gets caught and parsed.",
  },
  {
    name: "Netflix, Disney+ and other DRM services",
    status: "none",
    via: "—",
    note: "Custom caption renderers, and subtitle fetches the generic layers miss. Each needs its own adapter, or the DOM layer that is designed for but not built.",
  },
];

/* ── Keyboard ─────────────────────────────────────────────────────────────── */

export const shortcuts = [
  { key: "[", action: "Previous subtitle", note: "Jumps to the start of the line before this one." },
  { key: "]", action: "Next subtitle", note: "Jumps to the start of the line after this one." },
  { key: "\\", action: "Replay the current subtitle", note: "Seeks back to the start of the line you are on." },
  { key: "P", action: "Toggle auto-pause", note: "Pauses once at the end of every line, so you get a beat to read it." },
  { key: "H", action: "Toggle the blurred translation", note: "Guess-first mode. The translation resolves on hover." },
] as const;

/* ── Settings reference ───────────────────────────────────────────────────── */

export const settings = [
  { name: "Source language", value: "Auto-detect", body: "The language the video's own subtitles are in. Left on auto, whatever the site hands over is used." },
  { name: "Target language", value: "EN-US", body: "The language the second line is translated into. Twenty-six DeepL targets are available." },
  { name: "Provider", value: "DeepL", body: "Where translations come from. YouTube's own server-side translation is always preferred when it is available, because it is free and instant." },
  { name: "Blur translation", value: "Off", body: "Hides the second line behind a blur until you hover it." },
  { name: "Auto-pause", value: "Off", body: "Pauses playback at the end of each cue. Resuming moves on rather than re-pausing on the same line." },
  { name: "Hide native captions", value: "On", body: "Suppresses the site's own caption rendering, so only MajorTom's line is drawn." },
  { name: "Font scale", value: "1.0", body: "Scales both lines together." },
  { name: "Vertical offset", value: "15%", body: "How far up from the bottom of the player the lines sit. The default clears the control bar on YouTube, ARD and ZDF." },
  { name: "Disabled hosts", value: "None", body: "Sites where the overlay is explicitly turned off." },
] as const;

/* ── Roadmap ──────────────────────────────────────────────────────────────── */

export const gaps = [
  {
    title: "Netflix, Disney+ and the other DRM sites",
    body: "They render captions with custom renderers and fetch them in ways the generic layers miss. Each needs an adapter — or the DOM-scraping layer that would cover them generically, which is designed for but not implemented.",
    tag: "Blocked on the DOM layer",
  },
  {
    title: "ZDF is scraped, not asked",
    body: "Its subtitle URLs are pulled out of the page's HTML rather than from an API, because the API path wants an auth token. It works, but a markup change breaks it in a way ARD's route cannot break.",
    tag: "Fragile",
  },
  {
    title: "Live streams translate late",
    body: "They play and they show dual lines, but only the cues that have actually arrived can be translated. There is no lookahead to buy.",
    tag: "By nature",
  },
  {
    title: "Lookup is translation, not a dictionary",
    body: "Clicking a word sends it to the translator on its own. No lemmas, no genders, no declensions, no example sentences. translateOne is the seam where a real dictionary would drop in.",
    tag: "Wanted",
  },
  {
    title: "Nothing runs locally",
    body: "Every translation is a round trip to DeepL. The provider interface in translate.ts is the place a local model would go, and nothing else would have to change.",
    tag: "Wanted",
  },
  {
    title: "No spaced repetition, no export",
    body: "Saved words live in the popup with their sentence, title and timestamp. Getting them into Anki, or reviewing them on a schedule, is not built.",
    tag: "Wanted",
  },
] as const;

/* ── Permissions ──────────────────────────────────────────────────────────── */

export const permissions = [
  {
    name: "host_permissions: <all_urls>",
    why: "The whole premise is that the extension works on any video site rather than a list of three, so it cannot know in advance which origins it needs. It also lets the background worker fetch a subtitle file from the site's own CDN without tripping over CORS.",
  },
  {
    name: "storage",
    why: "Settings, your saved vocabulary, and the per-video translation cache. All of it is chrome.storage.local — on your machine, never synced anywhere.",
  },
  {
    name: "A content script at document_start",
    why: "It has to be installed before the page makes its first request, or the network layer would miss subtitle files fetched during player init. It stays dormant until a <video> element actually appears on the page.",
  },
] as const;
