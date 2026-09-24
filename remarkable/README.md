# MajorTom — reMarkable

Save German words and phrases while reading on a reMarkable 2, with the
sentence they came from, and import them into the library as
`source.kind = 'book'`.

Reading happens in [KOReader](https://github.com/koreader/koreader) rather than
reMarkable's own reader, because xochitl has no way to add a button to a text
selection. KOReader already has selection, dictionaries and a translator; this
project adds the one thing missing — a **Save** button — and the import on the
Mac side.

## Install

The tablet needs KOReader installed first. Use
[ReManager](https://remanager.io); Toltec is deprecated and only ever supported
firmware 2.x.

Then, with the tablet plugged in over USB:

```bash
./install.sh
```

That copies the plugin onto the tablet and checks it parses there. Restart
KOReader afterwards to pick the plugin up.

First time on a new Mac, set up a key so nothing prompts for a password:

```bash
ssh-copy-id root@10.11.99.1
```

The tablet's root password is on the device under Settings → Help → About →
Copyrights and licenses, below the "GPLv3 Compliance" heading. `10.11.99.1` is
the USB-ethernet address; it is fixed, and works regardless of what network
either machine is on.

## Reading

Select a word or a sentence and tap **Save to MajorTom**. It translates, shows
you the result, and saves only if you confirm — as a word or as a phrase, your
choice. In the dictionary popup the definition is already on screen and
offline, so the button there saves immediately without asking.

Translation is KOReader's built-in translator: no API key, but it needs wifi at
that moment. With no connection you are still offered the save, untranslated,
because losing the word is worse than losing the translation.

## Sync

The tablet appends one JSON object per line to `/home/root/.majortom/vocab.jsonl`
and never rewrites it.

Nothing imports on its own. Plug the tablet in over USB and press **Sync** in
the desktop app's Books tab, which reports what it did — imported, nothing new,
or tablet not connected.

An earlier version polled on a timer from a launch agent. It worked, but it
meant a background job running all day to catch the few minutes a week the
tablet is plugged in, and the result only ever landed in a log file nobody
reads. A button you press when you plug in is the honest shape of this.

The same script is the command-line path, and the app drives it rather than
reimplementing the import in Swift:

```bash
./sync.py              # import now
./sync.py --dry-run    # show what is on the tablet, write nothing
./sync.py --json       # one JSON object; what the app parses
```

There is no watermark and no sync state. Every run replays the whole log, and
both `UNIQUE` constraints in the schema turn a replay into a no-op — the same
property that lets the extension resend its whole vocabulary on every save. An
interrupted run can therefore be re-run with no thought about what it did.

Nothing leaves the machine. No cloud, no account, no background daemon on the
tablet.

## Surviving firmware updates

An update replaces the tablet's entire root partition and leaves `/home`
untouched. Everything here — KOReader, the plugin, and your saved words — lives
under `/home/root`, so the files survive.

What breaks is the launcher: it hooks into xochitl, and an update ships a new
xochitl. Turn off automatic updates (Settings → General → Software), and before
updating deliberately, check in ReManager whether the mods support the new
version. Nothing is lost while you wait — the saved words are a plain text file
on the data partition.

Separately, on current firmware the mod layer is tethered: after a reboot the
tablet comes back stock until you press the power button three times.

## Layout

```
majortom.koplugin/
  _meta.lua            name and description KOReader shows in the plugin list
  main.lua             the two buttons, the translate-then-confirm flow, the log
sync.py                pull the log, import it, idempotently
install.sh             push the plugin to a plugged-in tablet
```

## Known gaps

- **Page numbers are approximate in EPUB.** `position` comes from KOReader's
  current page, which shifts with font size. It is a locator, not a citation.
- **`context_translation` is never filled.** The schema has it; the tablet has
  no cheap way to produce it, and translating context separately would double
  the network calls for something rarely read.
- **Word lookup saves the first three meanings**, pulled from the Ding entry's
  English blocks. Good enough for a table column; the full entry, with every
  sense and the German cross-references, stays in the dictionary. A word whose
  fourth sense is the one you met will look wrong.
- **A save made with no connection keeps an empty translation.** Nothing fills
  it in later — by choice, since the fix is to have wifi on while reading.
- **Translation quality is Google's**, not DeepL's, which is noticeably flatter
  on long literary sentences. DeepL would need an API key on the tablet; doing
  it at import time on the Mac instead would be the better fix.
