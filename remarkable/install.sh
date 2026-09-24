#!/usr/bin/env bash
#
# Patches the reMarkable's own reader so that highlighting text opens a menu
# with Translate and Save.
#
# Needs XOVI and qt-resource-rebuilder on the tablet (ReManager installs both)
# and a built hashtable. Re-run after every reMarkable update, once ReManager
# has rebuilt the hashtable. Saved words live outside the reader and are never
# touched.

set -euo pipefail

TABLET="root@10.11.99.1"
SAVES="/home/root/.majortom"

XOVI="/home/root/xovi"
QRR_DIR="$XOVI/exthome/qt-resource-rebuilder"
XOCHITL_CONF="/home/root/.config/remarkable/xochitl.conf"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
on()  { ssh -o BatchMode=yes "$TABLET" "$@"; }

say "Checking the tablet…"
if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$TABLET" true 2>/dev/null; then
    echo "Cannot reach the tablet at $TABLET." >&2
    echo "Plug it in over USB. If this is a new Mac, run: ssh-copy-id $TABLET" >&2
    exit 1
fi

if ! on "[ -f $QRR_DIR/hashtab ]" 2>/dev/null; then
    echo "qt-resource-rebuilder is not set up on the tablet." >&2
    echo "Install XOVI and qt-resource-rebuilder with ReManager, build the hashtable, then re-run." >&2
    exit 1
fi

say "Patching the reader…"
on "mkdir -p $SAVES/inbox"
scp -q "$HERE/xochitl/majortom.qmd" "$TABLET:$QRR_DIR/majortom.qmd"

# The menu the patch extends is reMarkable's own, shipped switched off outside
# their internal builds. The reader rewrites its settings on exit, so it has to
# be stopped before the flag is written, not after.
if ! on "grep -q '^GlyphSelection=true' $XOCHITL_CONF"; then
    say "Enabling text selection…"
    on "cp $XOCHITL_CONF $SAVES/xochitl.conf.bak-\$(date +%Y%m%d-%H%M%S)"
    on "systemctl stop xochitl; sleep 2
        if grep -q '^GlyphSelection=' $XOCHITL_CONF; then
            sed -i 's/^GlyphSelection=.*/GlyphSelection=true/' $XOCHITL_CONF
        else
            sed -i '/^\[Experimental\]/a GlyphSelection=true' $XOCHITL_CONF
        fi"
fi

# Through XOVI rather than systemctl, so the patch is loaded.
say "Restarting the reader…"
on "cd $XOVI && ./start" >/dev/null 2>&1

say "Done."
cat <<EOF

Highlight text in a book (highlighter, with snap to text on) and a menu opens
with Translate. After translating: Save word or Save phrase. The selection
tool works too.

Translation needs the tablet on wifi at that moment; without it you can still
save, untranslated.

Nothing imports on its own. Plug the tablet in and press Sync in the desktop
app's Books tab, or:

  ./sync.py               import now
  ./sync.py --dry-run     show what is on the tablet, write nothing
EOF
