#!/usr/bin/env python3
"""Pull saved vocabulary off the reMarkable and into the MajorTom library.

The patched reader writes one small JSON file per save and never rewrites
one, so this replays all of them every time. Both UNIQUE constraints in the
schema turn a replay into a no-op, which is why there is no watermark to keep in
sync and nothing to corrupt if a run is interrupted.

Usage:
    ./sync.py            import whatever the tablet has
    ./sync.py --dry-run  show what would be imported
"""

import argparse
import html
import json
import os
import re
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# The tablet's USB-ethernet address. This is fixed by the device and does not
# depend on either machine's wifi.
TABLET = "root@10.11.99.1"
CONNECT_TIMEOUT = 8

# One file per save: QML can write a file but not append to one, and a file
# that is never rewritten cannot be half-overwritten.
REMOTE_INBOX = "/home/root/.majortom/inbox"
XOCHITL_DOCS = "/home/root/.local/share/remarkable/xochitl"

READ_ALL = (
    f"for f in {REMOTE_INBOX}/*.json; do [ -f \"$f\" ] && {{ cat \"$f\"; echo; }}; done; "
    "true"
)


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


def remote(command: str) -> str:
    result = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", f"ConnectTimeout={CONNECT_TIMEOUT}",
         TABLET, command],
        capture_output=True, text=True,
    )
    # ssh reserves 255 for its own transport errors, which is the only signal
    # that the tablet is really not there. Commands end in `true`, so a missing
    # file -- nothing saved yet -- is not mistaken for a failed connection.
    if result.returncode == 255:
        raise Unplugged
    if result.returncode != 0:
        raise ConnectionError(result.stderr.strip() or "reading the tablet failed")
    return result.stdout


def authors_for(document_ids: set) -> dict:
    """Author per book, read from the EPUB itself.

    reMarkable's own metadata carries only the title. Every EPUB names its
    author in its package file, and the tablet has unzip. PDFs have no such
    file and simply come back without an author.
    """
    ids = sorted(i for i in document_ids if re.fullmatch(r"[0-9a-f-]{36}", i))
    if not ids:
        return {}
    script = "; ".join(
        f"printf '%s\\t' {i}; "
        f"unzip -p {XOCHITL_DOCS}/{i}.epub '*.opf' 2>/dev/null "
        f"| grep -o '<dc:creator[^>]*>[^<]*' | head -n 1 | sed 's/.*>//'; echo"
        for i in ids
    ) + "; true"
    authors = {}
    for line in remote(script).splitlines():
        doc_id, _, name = line.partition("\t")
        if name.strip():
            authors[doc_id.strip()] = html.unescape(name.strip())
    return authors


def fetch() -> list:
    """Every save on the tablet. Empty when there are none."""
    output = remote(READ_ALL)

    entries = []
    for line_no, line in enumerate(output.splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            # A save interrupted mid-write. Skip it rather than fail the rest.
            log(f"skipped malformed save {line_no}", error=True)

    missing = {e["document_id"] for e in entries
               if not e.get("author") and isinstance(e.get("document_id"), str)}
    if missing:
        authors = authors_for(missing)
        for e in entries:
            if not e.get("author") and isinstance(e.get("document_id"), str):
                e["author"] = authors.get(e["document_id"], "")
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
                   translation = COALESCE(NULLIF(excluded.translation, ''), item.translation),
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


def run(dry_run: bool) -> dict:
    """Do the work and describe what happened. The caller decides how to say it."""
    try:
        entries = fetch()
    except Unplugged:
        return {"status": "unplugged"}
    except ConnectionError as err:
        return {"status": "error", "message": str(err)}

    if not entries:
        return {"status": "empty"}

    if dry_run:
        return {"status": "dry-run", "entries": entries}

    path = db_path()
    if not path.exists():
        return {"status": "error",
                "message": f"no library at {path} — run the desktop app once first"}

    conn = sqlite3.connect(path, timeout=5.0)
    conn.execute("PRAGMA journal_mode=WAL")
    try:
        written, books = import_entries(conn, entries)
    finally:
        conn.close()

    return {"status": "imported", "imported": written, "books": books}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="print what is on the tablet without writing")
    parser.add_argument("--json", action="store_true",
                        help="print one JSON object instead of prose (for the app)")
    args = parser.parse_args()

    result = run(args.dry_run)

    if args.json:
        # The app parses this, so it must be the only thing on stdout.
        entries = result.pop("entries", None)
        if entries is not None:
            result["entries"] = len(entries)
        print(json.dumps(result))
        return 0 if result["status"] != "error" else 1

    # if/elif rather than match: the app runs this with /usr/bin/python3, which
    # is 3.9 on macOS, and match arrived in 3.10.
    status = result["status"]
    if status == "unplugged":
        # Quiet by default: an absent tablet is the normal state, not a fault.
        if args.dry_run:
            log("tablet not plugged in")
    elif status == "error":
        log(result["message"], error=True)
        return 1
    elif status == "empty":
        log("connected; nothing saved on the tablet yet")
    elif status == "dry-run":
        for entry in result["entries"]:
            print(f"  [{entry.get('kind'):6}] {entry.get('text')}"
                  f"  →  {entry.get('translation') or '(untranslated)'}"
                  f"   [{entry.get('book')} p{entry.get('page')}]")
        print(f"\n{len(result['entries'])} entries, not written (--dry-run)")
    elif status == "imported":
        log(f"imported {result['imported']} entries across {result['books']} book(s)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
