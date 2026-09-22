# MajorTom

Dual subtitles and click-to-save vocabulary for language learning — on any video
site, not a hardcoded list of three.

The original subtitle line stays on top, a translation sits underneath, and every
word in the original is clickable: click it to look it up and save it with the
sentence it came from.

## Install

```bash
npm install && npm run build
```

Then in Chrome (or Brave — same steps):

1. Open `chrome://extensions`
2. Turn on **Developer mode** (top right)
3. **Load unpacked** → select the `dist/extension` folder

Re-run `npm run build` after changing anything, then hit reload on the extension
card. `npm run dev` rebuilds on save.

## Translation

YouTube translates its own subtitles server-side, so it works with no setup.

Everywhere else needs a [DeepL API key](https://www.deepl.com/pro-api) — the free
tier covers 500,000 characters a month, which is roughly 15 feature-length films.
Paste it into the extension popup under **Subtitles → DeepL** and press *Test*.

Translations are cached per video, so rewatching costs nothing.

## Keys

| Key | Action                                         |
|-----|------------------------------------------------|
| `[` | Previous subtitle                              |
| `]` | Next subtitle                                  |
| `\` | Replay the current subtitle                    |
| `P` | Toggle auto-pause at the end of each line      |
| `L` | Loop the current line (shadowing practice)     |
| `H` | Toggle the blurred translation ("guess first") |

Bracket keys are used deliberately: every video site already claims the letters
and arrow keys for its own player, and the extension should not fight it. All
shortcuts are ignored while you are typing in a text box.

## How subtitles are found

Sites differ wildly in how they deliver captions, so capture is layered. The
first layer that produces cues wins, and a better source replaces a worse one if
it turns up later.

| Layer           | How it works                                                                                        | Covers                                                      |
|-----------------|-----------------------------------------------------------------------------------------------------|-------------------------------------------------------------|
| **Adapter**     | Reads the site's own metadata API for a subtitle file URL                                           | ARD, ZDF, YouTube                                           |
| **Text tracks** | Hooks `video.textTracks`, forcing tracks to `hidden` so cues populate without the site drawing them | hls.js, dash.js, Shaka, video.js, JW, Plyr, plain `<track>` |
| **Network**     | Sniffs fetch/XHR responses and content-sniffs the body for VTT/TTML/SRT/json3                       | sites that fetch a whole subtitle file                      |
| **DOM**         | —                                                                                                   | *not implemented; see below*                                |

The adapter layer exists because interception alone is not enough. ARD is the
clearest example: it renders captions with a custom DOM renderer over MSE, it
creates **no text tracks at all**, and it fetches its subtitle file once at
player init — before any content script could hook the network. Its
`page-gateway` API, though, hands out a plain WebVTT URL. Reading that is
deterministic and needs no race.

The MAIN-world capture script runs at `document_start` so it is installed before
the page makes its first request, but it stays silent until a `<video>` element
actually appears on the page.

## Translation quality

Broadcaster subtitles split sentences across several cues, and translating those
fragments in isolation is the main reason machine-translated subtitles read
badly. Cues are regrouped into whole sentences first; the sentence translation
is then shown for every cue it spans, so the translation line stays steady while
the original advances through it.

## Layout

```
extension/
  manifest.json
  src/
    content.ts              orchestrator: discovery, sync loop, keyboard
    background.ts           service worker: fetch proxy + translation router
    capture/
      injected.ts           MAIN world: text-track + network hooks
      parsers.ts            VTT / TTML / SRT / json3 → Cue[]
      adapters/             one file per site; register in index.ts
    translate/
      index.ts              sentence regrouping, caching, orchestration
      deepl.ts              provider (a local-model provider goes beside it)
    ui/
      overlay.ts            the on-video overlay (shadow DOM)
      popup.ts / popup.html
    shared/                 types, config, logger, storage, messaging
scripts/                    icons, smoke tests, dev log server
```

Adding a site means writing one file in `capture/adapters/` and listing it in
that folder's `index.ts`. Nothing else needs to change.

## Development

```bash
npm run dev        # rebuild on save
npm run smoke      # parser / cue-lookup / adapter tests
npm run smoke -- --live   # also hits the real ARD API
npm run typecheck
npm run logs       # log server on :7777, dev builds mirror to it
```

Dev builds mirror logs to the local log server. Production builds compile that
out entirely and never touch the network for logging.

## Known gaps

- **Netflix, Disney+ and other DRM sites are unverified.** The network layer
  content-sniffs response bodies (not just URLs) while it has no cues, which is
  the mechanism that *could* pick them up — but this has never been tested
  against either service, so treat it as untried rather than supported. A
  confirmed fix would most likely be a small adapter per service.
- **ZDF** relies on scraping subtitle URLs out of the page, which is more
  fragile than ARD's API path.
- **Live streams** work, but translation only covers cues that have arrived.
- **Burned-in subtitles cannot be hidden.** German broadcasters often render
  translations of foreign-language speech directly into the video picture (most
  Y-Kollektiv episodes do this). Those are pixels, not text — no extension can
  remove them, so you will occasionally see them under our line.
- **Word lookup is translation, not a dictionary** — no lemmas, genders, or
  declensions. `translateOne` in `translate.ts` is the seam where a real
  dictionary would go.
- Local translation models are not wired up. The provider interface in
  `translate.ts` is the place for it.
