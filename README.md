# MajorTom

Tools for learning German, built around one idea: the words worth learning are
the ones you meet in the wild, and they are worth keeping together with the
sentence you met them in.

Each project captures vocabulary from somewhere different. They all write to one
SQLite file, so everything ends up in one library.

| Project | What it does |
|---------|--------------|
| [extension](extension) | Dual subtitles on any video site. Click a word to look it up and save it. |
| [desktop](desktop) | Native macOS app holding everything you save — the library itself. |
| [transcriber](transcriber) | Live transcription of a call on the Mac, and an iPhone app for the same thing in person. |
| [site](site) | The public page for the project. |
| [remarkable](remarkable) | A KOReader plugin that saves words while reading on the tablet. |

## How they fit together

```
extension ─────┐
transcriber ───┤
  mac          ├──→  data/majortom.sqlite  ──→  desktop
  phone ─(wifi)┤          (the library)         (reads and organises it)
remarkable ────┘
```

Only the Mac writes to the library. The iPhone sends what it collected over
the local network, and the reMarkable's file is pulled over USB — neither
touches the database itself.

`data/` sits at the root because no single project owns it. Two tables — sources
are what you saved *from* (a show, a call, a book), items are what you saved. The
schema is documented in [desktop/README.md](desktop/README.md), which is the
place to look before writing a new capture tool.

Each project is independent. The extension works without the desktop app; the
transcriber works without the extension. The library is the only thing they
share, and they only ever add rows to it.

`data/` is gitignored — it is your vocabulary, not source code.

## Getting set up

The desktop app and the extension install together, because the app registers
itself as the extension's sync host:

```bash
cd desktop && ./install.sh
```

Then, once per browser: `chrome://extensions` → Developer mode → **Load
unpacked** → pick `extension/dist/unpacked`.

Chromium derives an unpacked extension's id by hashing the absolute path of its
folder, so that path matters — moving the repo means re-running `install.sh` and
re-loading the extension. Details in [desktop/README.md](desktop/README.md).

The [transcriber](transcriber) is still command-line only; see its README.
