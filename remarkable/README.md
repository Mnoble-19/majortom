# MajorTom — reMarkable

Save German words and phrases while reading on a reMarkable 2, in reMarkable's
own reader. Highlight text and a menu opens with **Translate**; after
translating, **Save word** or **Save phrase**. Saves land in the desktop app's
Books tab when you plug the tablet in and press Sync.

Nothing replaces the reader. A patch adds three buttons to a menu reMarkable
already ships, and everything else — the page, the highlight, the menu's look —
is theirs.

## Install

The tablet needs XOVI and qt-resource-rebuilder, and a built hashtable.
[ReManager](https://remanager.io) installs both and has a button for the
hashtable. On a reMarkable 2 this needs no factory reset (Developer Mode is a
Paper Pro requirement).

First time on a new Mac, set up a key so nothing prompts for a password:

```bash
ssh-copy-id root@10.11.99.1
```

The tablet's root password is under Settings → Help → About → Copyrights and
licenses, below "GPLv3 Compliance". `10.11.99.1` is the USB-ethernet address;
it is fixed and works whatever network either machine is on.

Then, with the tablet plugged in over USB:

```bash
./install.sh
```

It copies the patch over, switches on the setting the menu depends on (backing
up the settings file first), and restarts the reader.

## Reading

With the **highlighter** — snap to text on — highlight a word or sentence. The
highlight is made as usual, and a menu opens next to it: Copy, and Translate.
Translate shows the English below the menu and turns the buttons into Save word
and Save phrase. Saving shows reMarkable's own notification.

The **selection tool** opens the same menu, but drawing a loop that catches
exactly the right words takes a few tries, which is why the highlighter was
wired up too.

Translation needs wifi at that moment. Without it the panel says so and you can
still save, untranslated.

## How it works

### The menu was already there

reMarkable ships a menu for text picked out of a book —
`GlyphSelectionHandler.qml` — with one button, Copy. It is behind a setting,
`[Experimental] GlyphSelection` in `xochitl.conf`, which defaults to on only in
their internal nightly builds. `install.sh` turns it on.

The selected text is already a property of that menu (`selectedText`), so the
new buttons read it directly.

### The patch

`xochitl/majortom.qmd` is a [QMLDiff](https://github.com/asivery/qmldiff) file.
qt-resource-rebuilder applies it to the reader's QML as the reader loads. It
only ever *adds* — no function reMarkable wrote is replaced — so there is less
of their code for an update to move out from under it.

It touches two files:

- **`GlyphSelectionHandler.qml`** gets Translate, Save word and Save phrase,
  the translation panel, and the code behind them. The save needs the open book
  and page, which belong to the reader view further up; rather than patch that
  view too, the code walks up its parent chain at runtime to find them.
- **`DeviceSceneView.qml`** gets two listeners for the highlighter. A
  highlighter stroke goes to `highlightWithLine`, which draws the highlight and
  hands back no text; a selection stroke goes to `selectWithLine`, which
  reports the words under it. So after a highlight snapped to text, the patch
  runs `selectWithLine` on the same stroke and opens the menu with what comes
  back. reMarkable's own handler closes that selection straight away, because
  the highlighter is not the selection tool, so the menu is reopened with
  `Qt.callLater`, after every handler for the event has run.

### Saving and translating

QML can make network requests, and XOVI starts the reader with
`QML_XHR_ALLOW_FILE_WRITE=1`, so it can write files too. Translation is a
request to Google Translate's public endpoint; no key.

A save is one small JSON file in `/home/root/.majortom/inbox/`. QML can write a
file but not append to one, and a file that is never rewritten cannot be
half-overwritten, so a failed write loses that save and nothing else.
`/home/root` survives firmware updates.

### Sync

The **Sync reMarkable** button in the desktop app runs `sync.py`, which reads
every file in the inbox over the USB cable and writes it into
`data/majortom.sqlite` as `source.kind = 'book'`. reMarkable's metadata has the
title but no author, so the author is read from the EPUB's package file on the
tablet.

There is no watermark and no sync state. Every run replays all the saves, and
both `UNIQUE` constraints in the schema make a replay a no-op, so an interrupted
run can simply be run again.

```bash
./sync.py              # import now
./sync.py --dry-run    # show what is on the tablet, write nothing
./sync.py --json       # one JSON object; what the app parses
```

It runs under `/usr/bin/python3`, which is 3.9 on macOS: a GUI app does not
inherit a shell's PATH, so whatever newer Python you have is not what it gets.

## After a reMarkable update

This is the fragile part. An update replaces the whole root partition — the
reader included — and leaves `/home` alone, so the patch file and your saves
survive, but the QML the patch was written against may have changed.

1. Keep automatic updates off (Settings → General → Software) and check in
   ReManager that XOVI supports a version before installing it.
2. After updating, rebuild the hashtable in ReManager's Maintenance tab.
3. Re-run `./install.sh`.
4. Highlight something. If the menu does not appear, see what changed in the
   two patched files:

   ```bash
   scp root@10.11.99.1:/usr/bin/xochitl /tmp/xochitl
   python3 -m pip install zstandard
   python3 xochitl/extract_qml.py /tmp/xochitl /tmp/qml
   ```

   `extract_qml.py` pulls every QML file out of the reader binary. Neither XOVI
   nor qmldiff can dump them, and the one existing extractor needs Mono. The
   patch errors, if any, are in `journalctl -u xochitl | grep qmldiff`.

Separately: on current firmware XOVI is tethered. After a reboot the tablet
comes back stock, patch not loaded, until you press the power button three
times.

## How we got here

The first version read books in KOReader, with a plugin for the Save button,
because xochitl looked impossible to extend. It worked end to end but looked
out of place on the tablet, and was removed. What made the native reader
possible was finding reMarkable's own disabled selection menu by extracting
the reader's QML — the search started from `TextSelectionMenu.qml`, which turned
out to be the typed-text menu for notebooks, not the one for books.

## Layout

```
xochitl/
  majortom.qmd         the patch: buttons, translation panel, highlighter hook
  extract_qml.py       dump the reader's QML, for checking the patch after updates
sync.py                pull the saves off the tablet, import them, idempotently
install.sh             put the patch on a plugged-in tablet and switch the menu on
```

## Known gaps

- **Every highlight opens the menu.** Tap outside it to dismiss when you only
  wanted the highlight.
- **No offline translation.** The German dictionary that shipped with the
  KOReader version is gone with it; reading the same StarDict files from QML
  would make single words translate with no wifi.
- **No context.** A save has the text you picked, not the sentence around it.
- **Page numbers are reMarkable's page index plus one**, which for an EPUB
  depends on the reader's layout settings. A locator, not a citation.
- **A save made without wifi keeps an empty translation.** Nothing fills it in
  later — by choice.
- **Translation quality is Google's**, flatter than DeepL on long literary
  sentences.
