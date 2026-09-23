#!/usr/bin/env python3
"""Pull saved vocabulary off the reMarkable and into the MajorTom library.

The tablet appends one JSON object per line and never rewrites the file, so
this replays the whole log every time. Both UNIQUE constraints in the schema
turn a replay into a no-op, which is why there is no watermark to keep in
sync and nothing to corrupt if a run is interrupted.

Usage:
    ./sync.py            import whatever the tablet has
    ./sync.py --dry-run  show what would be imported
"""

import argparse
import json
import os
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# The tablet's USB-ethernet address. This is fixed by the device and does not
# depend on either machine's wifi.
TABLET = "root@10.11.99.1"
REMOTE_FILE = "/home/root/.majortom/vocab.jsonl"
CONNECT_TIMEOUT = 8


def log(message: str, error: bool = False) -> None:
    """Timestamped, because the agent's output is only useful after the fact."""
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"{stamp}  {message}", file=sys.stderr if error else sys.stdout, flush=True)


def db_path() -> Path:
    override = os.environ.get("MAJORTOM_DB")
    if override:
        return Path(override)
    return Path(__file__).resolve().parent.parent / "data" / "majortom.sqlite"


class Unplugged(Exception):
    """The tablet is not connected. The normal state, not an error."""


def fetch() -> list[dict]:
    """Read the log off the tablet. Empty when nothing has been saved yet."""
    result = subprocess.run(
        # `|| true` so a missing file — nothing saved yet — is not mistaken for
        # a failed connection. ssh reserves 255 for its own transport errors,
        # which is the only signal that the tablet is really not there.
        ["ssh", "-o", "BatchMode=yes", "-o", f"ConnectTimeout={CONNECT_TIMEOUT}",
         TABLET, f"cat {REMOTE_FILE} 2>/dev/null || true"],
        capture_output=True, text=True,
    )
    if result.returncode == 255:
        raise Unplugged
    if result.returncode != 0:
        raise ConnectionError(result.stderr.strip() or "reading the tablet failed")

    entries = []
    for line_no, line in enumerate(result.stdout.splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            # A half-written last line is the one failure mode of an append-only
            # log. Skip it; the next save rewrites a complete line after it.
            log(f"skipped malformed line {line_no}", error=True)
    return entries


def import_entries(conn: sqlite3.Connection, entries: list[dict]) -> tuple[int, int]:
    now = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    sources_seen: dict[str, int] = {}
    written = 0

    for entry in entries:
        book = (entry.get("book") or "").strip()
        text = (entry.get("text") or "").strip()
        if not book or not text:
            continue

        if book not in sources_seen:
            conn.execute(
                """INSERT INTO source (kind, title, site, url, created_at)
                   VALUES ('book', ?, ?, '', ?)
                   ON CONFLICT(kind, url, title) DO NOTHING""",
                (book, entry.get("author") or "", entry.get("saved_at") or now),
            )
            row = conn.execute(
                "SELECT id FROM source WHERE kind = 'book' AND url = '' AND title = ?",
                (book,),
            ).fetchone()
            sources_seen[book] = row[0]

        kind = entry.get("kind") if entry.get("kind") in ("word", "phrase") else "word"

        conn.execute(
            """INSERT INTO item (source_id, kind, text, translation, context,
                                 context_translation, position, starred, created_at)
               VALUES (?, ?, ?, ?, ?, '', ?, 0, ?)
               ON CONFLICT(source_id, kind, text) DO UPDATE SET
                   translation = excluded.translation,
                   context     = excluded.context,
                   position    = excluded.position""",
            (
                sources_seen[book],
                kind,
                text,
                entry.get("translation") or "",
                entry.get("context") or "",
                float(entry.get("page") or 0),
                entry.get("saved_at") or now,
            ),
        )
        written += 1

    conn.commit()
    return written, len(sources_seen)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="print what is on the tablet without writing")
    args = parser.parse_args()

    try:
        entries = fetch()
    except Unplugged:
        # The agent runs on a timer and the tablet is usually absent, so this
        # must stay silent or the log fills with it.
        if args.dry_run:
            log("tablet not plugged in")
        return 0
    except ConnectionError as err:
        log(str(err), error=True)
        return 1

    if not entries:
        log("connected; nothing saved on the tablet yet")
        return 0

    if args.dry_run:
        for entry in entries:
            print(f"  [{entry.get('kind'):6}] {entry.get('text')}"
                  f"  →  {entry.get('translation') or '(untranslated)'}"
                  f"   [{entry.get('book')} p{entry.get('page')}]")
        print(f"\n{len(entries)} entries, not written (--dry-run)")
        return 0

    path = db_path()
    if not path.exists():
        log(f"no library at {path} — run the desktop app once first", error=True)
        return 1

    conn = sqlite3.connect(path, timeout=5.0)
    conn.execute("PRAGMA journal_mode=WAL")
    try:
        written, books = import_entries(conn, entries)
    finally:
        conn.close()

    log(f"imported {written} entries across {books} book(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
