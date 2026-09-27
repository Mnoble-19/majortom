# MajorTom — browser extension

Dual subtitles and click-to-save vocabulary for language learning — on any video
site, not a hardcoded list of three.

The original subtitle line stays on top, a translation sits underneath, and every
word in the original can be looked up by resting on it or clicking it. A
two-finger tap on a word saves it with the sentence it came from; with Shift
held, it saves the whole line as a phrase. (A two-finger tap reaches the
page as a right-click, so a right-click does the same with a mouse.)

## Install

```bash
cd extension
npm install && npm run build
```

Then in Chrome (or Brave — same steps):

1. Open `chrome://extensions`
2. Turn on **Developer mode** (top right)
3. **Load unpacked** → select the `extension/dist/unpacked` folder

Re-run `npm run build` after changing anything, then hit reload on the extension
card. `npm run dev` rebuilds on save.

## Turning it on

The extension does nothing until you turn it on for a site: open the popup on
that site and flip the switch in the header. The tab reloads once, and from then
on that site (and its subdomains) gets the overlay. No other page is touched —
the capture script patches `fetch` and `XMLHttpRequest`, so it is only ever
registered for sites on your list.

## Translation

Translation runs on a local model: any OpenAI-compatible server, by default
llama-server at `http://localhost:9931/v1` (the same endpoint the desktop app
uses). With no model named in the popup, the first one the server lists is used.
**Subtitles → Local model → Test** checks it end to end.

In order of preference:

1. **A human-made track in your language**, when the site has one (YouTube).
2. **The local model.** As soon as the subtitles are found, all of them are
   queued, a batch at a time, starting from where you are in the video, so the
   line on screen fills in first. A seek moves the work to wherever you went.
3. **YouTube's own machine translation**, shown the instant subtitles load and
   replaced sentence by sentence as the model's lines arrive — or kept, if the
   model can't be reached.

Translations are cached per video, sentence by sentence, so rewatching, a
reload, or a better subtitle source turning up reuses everything already done.

Clicking a word asks the model for its dictionary form (`holt … raus` →
`rausholen`) and what it means in that sentence.

## YouTube

YouTube returns an empty caption file unless the request carries a token only
its player can make. The capture script therefore lets the player fetch
captions once — switching them on for a moment if they are off, then back —
keeps that token, and fetches the tracks it wants with it.

It also picks the track in the language being spoken (an authored one over the
automatic transcript), and when YouTube has auto-dubbed a video into another
language, it switches the audio back to the original. A dub in the language set
under **Video is in** is left alone.

## Keys

| Key | Action                                         |
|-----|------------------------------------------------|
| `Q` | Previous subtitle                              |
| `W` | Replay the current subtitle                    |
| `E` | Next subtitle                                  |
| `R` | Toggle the blurred translation ("guess first") |
| `T` | Toggle auto-pause at the end of each line      |
| `Y` | Loop the current line (shadowing practice)     |

The top-left row, matched by physical key, so they stay under the left hand on
any layout (on a German keyboard, `Y` is the key marked Z). While subtitles are
showing they take precedence over the player's own use of those keys. All
shortcuts are ignored while you are typing in a text box.

The control bar above the subtitles is off by default; turn it on in the popup
under **While watching**.

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
manifest.json
src/
  content.ts                orchestrator: discovery, sync loop, keyboard
  background.ts             service worker: fetch proxy + translation router
  capture/
    injected.ts             MAIN world: text-track + network hooks
    parsers.ts              VTT / TTML / SRT / json3 → Cue[]
    adapters/               one file per site; register in index.ts
  translate/
    index.ts                sentence regrouping, caching, playhead-first batching
    llm.ts                  the local model client (runs in the service worker)
  ui/
    overlay.ts              the on-video overlay (shadow DOM)
    popup.ts / popup.html
  shared/                   types, config, logger, storage, messaging
scripts/                    icons, smoke tests, dev log server
dist/unpacked/              the built extension — this is what you load
```

The saved words sync into the [desktop app](../desktop); the
[transcriber](../transcriber) is the same idea for calls.

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
- **The model has to be running.** With it down, YouTube falls back to its own
  machine translation; other sites show the original line only, and the overlay
  says why.
- **A long video takes a few minutes to translate in full** (about 4 seconds per
  batch of sentences on Gemma 4 once loaded). Starting at the playhead hides
  this unless you jump around a lot.
