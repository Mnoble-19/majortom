#!/usr/bin/env bash
#
# Puts the capture plugin and the offline dictionary onto the tablet.
#
# Run it after installing or updating KOReader, which replaces the folder both
# of them live in. Your saved words are not in there — they sit outside
# KOReader entirely and this script never touches them.
#
# The tablet must be plugged in over USB.

set -euo pipefail

TABLET="root@10.11.99.1"
KOREADER="/home/root/xovi/exthome/appload/koreader"
PLUGIN_DIR="$KOREADER/plugins/majortom.koplugin"
DICT_DIR="$KOREADER/data/dict/deu-eng"

# Ding, via FreeDict: 517k headwords with genders and word forms, which is what
# a dictionary gives you over a translator. ~36MB, so it is fetched only when
# missing.
DICT_URL="https://download.freedict.org/dictionaries/deu-eng/1.9-fd1/freedict-deu-eng-1.9-fd1.stardict.tar.xz"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '\033[1m%s\033[0m\n' "$*"; }

say "Checking the tablet…"
if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$TABLET" true 2>/dev/null; then
    echo "Cannot reach the tablet at $TABLET." >&2
    echo "Plug it in over USB. If this is a new Mac, run: ssh-copy-id $TABLET" >&2
    exit 1
fi

if ! ssh -o BatchMode=yes "$TABLET" "[ -d $KOREADER ]" 2>/dev/null; then
    echo "KOReader is not installed at $KOREADER." >&2
    echo "Install it with ReManager (remanager.io) first." >&2
    exit 1
fi

say "Installing the plugin…"
ssh -o BatchMode=yes "$TABLET" "mkdir -p $PLUGIN_DIR"
scp -q "$HERE/majortom.koplugin/main.lua" "$HERE/majortom.koplugin/_meta.lua" "$TABLET:$PLUGIN_DIR/"

# A syntax error here would only surface as KOReader silently skipping the
# plugin, so fail loudly now instead.
if ! ssh -o BatchMode=yes "$TABLET" \
    "cd $KOREADER && ./luajit -e 'assert(loadfile(\"plugins/majortom.koplugin/main.lua\"))'" 2>/dev/null; then
    echo "The plugin does not parse on the device." >&2
    exit 1
fi

if ssh -o BatchMode=yes "$TABLET" "[ -f $DICT_DIR/deu-eng.ifo ]" 2>/dev/null; then
    say "Dictionary already on the tablet, skipping."
else
    say "Installing the German dictionary (~36MB, once)…"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT

    curl -fsSL -o "$TMP/deu-eng.tar.xz" "$DICT_URL"
    tar -xJf "$TMP/deu-eng.tar.xz" -C "$TMP"
    # StarDict ships the index gzipped; KOReader wants it plain.
    gunzip -f "$TMP/deu-eng/deu-eng.idx.gz"

    ssh -o BatchMode=yes "$TABLET" "mkdir -p $DICT_DIR"
    scp -q "$TMP/deu-eng/deu-eng.ifo" "$TMP/deu-eng/deu-eng.idx" \
           "$TMP/deu-eng/deu-eng.dict.dz" "$TABLET:$DICT_DIR/"
fi

say "Done."
cat <<EOF

  Plugin      $PLUGIN_DIR
  Dictionary  $DICT_DIR

Restart KOReader on the tablet to load the plugin.

While reading: select a word or sentence, tap "Save to MajorTom", and it
translates, shows it, and saves if you confirm.

Nothing imports on its own. Plug the tablet in and press Sync in the desktop
app's Books tab, or run it here:

  ./sync.py               import now
  ./sync.py --dry-run     show what is on the tablet, write nothing
EOF
