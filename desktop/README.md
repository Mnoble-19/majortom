# MajorTom Desktop

Native macOS app (SwiftUI) that holds everything you save while learning: words
from the browser extension today, call keywords and book vocabulary later.

The browser extension keeps working without this app. The app is a library on
top of it, not a dependency.

## Build and install

```bash
./build.sh                          # assembles build/MajorTom.app
./install-host.sh <extension-id>    # registers the native messaging host
```

The extension ID is on its card at `chrome://extensions`. An unpacked
extension's ID is a hash of its folder, so the same folder loaded in several
browsers gives the same ID and one argument covers them all; pass several IDs
if you loaded it from different folders.

`install-host.sh` writes a pointer file into every Chromium browser it finds
(Chrome, Brave, Chromium, Edge, Vivaldi, Arc, plus beta channels). They all
spawn the same binary, so every browser writes to one database.

## Where the data lives

```
<repo>/data/majortom.sqlite
```

Resolved at runtime by walking up from the binary to the folder containing
`package.json`. If the `.app` is moved out of the tree it falls back to
`~/Library/Application Support/MajorTom/`. Set `MAJORTOM_DB=/path/to.sqlite`
to override — useful for tests, and it applies to both the app and the host.

SQLite needs no server. WAL mode plus a 5s busy timeout lets several browsers
write while the app reads. The app re-reads on window focus and every 3s, so
external writes appear without a restart.

`data/` is gitignored.

## Schema

Two tables. Sources are anything you saved *from*; items are what you saved.

```sql
CREATE TABLE source (
    id         INTEGER PRIMARY KEY,
    kind       TEXT NOT NULL,           -- 'show' | 'call' | 'book'
    title      TEXT NOT NULL,           -- shown as the card/heading label
    site       TEXT NOT NULL DEFAULT '',-- hostname, or the other party for a call
    url        TEXT NOT NULL DEFAULT '',-- deep link back, '' if none
    created_at TEXT NOT NULL,           -- ISO-8601 with fractional seconds
    UNIQUE(kind, url, title)
);

CREATE TABLE item (
    id                  INTEGER PRIMARY KEY,
    source_id           INTEGER NOT NULL REFERENCES source(id) ON DELETE CASCADE,
    kind                TEXT NOT NULL,           -- 'word' | 'phrase'
    text                TEXT NOT NULL,           -- the saved term, source language
    translation         TEXT NOT NULL DEFAULT '',
    context             TEXT NOT NULL DEFAULT '',-- sentence it appeared in
    context_translation TEXT NOT NULL DEFAULT '',
    position            REAL NOT NULL DEFAULT 0, -- see below
    starred             INTEGER NOT NULL DEFAULT 0,
    created_at          TEXT NOT NULL,
    UNIQUE(source_id, kind, text)
);

CREATE INDEX item_source ON item(source_id, kind);
```

`position` is "where in the source", per kind: playback seconds for a show,
seconds into the recording for a call, a page or locator for a book. `0` means
unknown and renders as `—`.

Both UNIQUE constraints are the dedup keys — use `ON CONFLICT ... DO UPDATE` to
make writes idempotent, which is how the extension can safely resend its whole
vocabulary on every save.

## Adding a new source kind (read this first, calls project)

The schema already covers calls and books; `SourceKind` and the sidebar have
entries for both. **You do not need to change the app to make data appear** —
insert rows with `source.kind = 'call'` and they show up under the Calls tab.

Write directly to the SQLite file:

```sql
INSERT INTO source (kind, title, site, url, created_at)
VALUES ('call', 'Call with Ana — 2026-09-20', 'ana', '', '2026-09-20T19:00:00.000Z')
ON CONFLICT(kind, url, title) DO NOTHING;

INSERT INTO item (source_id, kind, text, translation, context,
                  context_translation, position, starred, created_at)
VALUES (?, 'word', 'beharrlich', 'persistent',
        'Er blieb beharrlich bei seiner Forderung.',
        'He remained persistent in his demand.', 142.0, 0, '2026-09-20T19:04:00.000Z')
ON CONFLICT(source_id, kind, text) DO UPDATE SET
    translation = excluded.translation,
    context = excluded.context,
    context_translation = excluded.context_translation;
```

Open the DB with `PRAGMA journal_mode=WAL` and a busy timeout, and keep writes
in a transaction. The app will pick them up within 3 seconds.

The one thing **not** reusable is the native messaging host: it hardcodes
`kind = 'show'` because its only caller is the browser extension. A calls
pipeline should write SQL directly rather than route through it. If you do want
to reuse it, generalise `NativeHost.write` in
[NativeHost.swift](Sources/MajorTom/NativeHost.swift).

Phrase capture (`item.kind = 'phrase'`) is schema-complete but nothing writes
it yet; the Phrases tab renders an empty state.

## Native messaging protocol

Chrome spawns the app binary with `--native-host` and talks over stdio:
a 4-byte native-endian length, then that many bytes of UTF-8 JSON.

```jsonc
// →  request
{ "type": "sync", "entries": [ /* VocabEntry from extension/src/shared/types.ts */ ] }
// ←  response
{ "ok": true, "written": 4 }
```

`{"type":"ping"}` is a liveness check. Because the browser spawns the host on
demand, the app does not need to be running to receive saves.

## Layout

```
Package.swift            SwiftPM manifest; no .xcodeproj to keep in sync
Info.plist               copied into the bundle by build.sh
build.sh                 swift build + hand-assembled .app
install-host.sh          registers the host with every Chromium browser
Sources/MajorTom/
  main.swift             dispatches: --native-host, else the app
  Database.swift         SQLite wrapper, path resolution, migrations
  Models.swift           Source, Item, wire types
  Store.swift            queries + change polling, published to the UI
  NativeHost.swift       stdio protocol, upserts from the extension
  Theme.swift            palette and type scale, shared with the extension overlay
  Views/                 RootView, ShowsView, ShowDetailView, Components
```
