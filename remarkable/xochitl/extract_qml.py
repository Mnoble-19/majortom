#!/usr/bin/env python3
"""Extract the Qt resources (QML, images, ...) compiled into a Qt binary.

Used to read the native reader's own QML, which is what majortom.qmd patches.
Re-run it after a reMarkable update to see what changed under the patch:

    scp root@10.11.99.1:/usr/bin/xochitl /tmp/xochitl
    python3 -m pip install zstandard
    python3 extract_qml.py /tmp/xochitl /tmp/qml
    # the patched files:
    #   /tmp/qml/qml/device/view/documentview/GlyphSelectionHandler.qml
    #   /tmp/qml/qml/device/view/documentview/DeviceSceneView.qml

rcc emits three tables per bundle: a tree of 22-byte nodes, a name table, and a
data table. Nothing in the binary says where they are, so each is found and then
*verified*: names carry Qt's own hash, so a wrong guess about the name table
fails loudly instead of producing garbage paths.
"""
import re
import struct
import sys
import zlib
from pathlib import Path

import zstandard

NODE = 22                      # rcc format v2/v3: node with 8-byte mtime
DIR, ZLIB, ZSTD = 0x02, 0x01, 0x04


def qt_hash(name: str) -> int:
    h = 0
    raw = name.encode("utf-16-be")
    for i in range(0, len(raw), 2):
        h = (h << 4) + (raw[i] << 8 | raw[i + 1])
        h ^= (h & 0xF0000000) >> 23
        h &= 0x0FFFFFFF
    return h


def u16(b, o): return struct.unpack_from(">H", b, o)[0]
def u32(b, o): return struct.unpack_from(">I", b, o)[0]


def find_name_entries(blob: bytes) -> dict[int, str]:
    """Every position holding a valid rcc name entry: len, qt_hash, UTF-16BE."""
    found = {}
    for m in re.finditer(rb"(?:\x00[\x20-\x7e]){1,255}", blob):
        start = m.start() - 6
        if start < 0:
            continue
        length = u16(blob, start)
        if length == 0 or length * 2 > m.end() - m.start():
            continue
        name = blob[m.start():m.start() + length * 2].decode("utf-16-be", "replace")
        if u32(blob, start + 2) == qt_hash(name):
            found[start] = name
    return found


def root_candidates(blob: bytes):
    # Root: name 0, flags DIR, N children, first child 1. The mtime is not
    # reliably zero -- rcc stamps real build times -- so it is not matched on.
    pat = re.compile(rb"\x00\x00\x00\x00\x00\x02(.{4})\x00\x00\x00\x01", re.S)
    for m in pat.finditer(blob):
        n = u32(blob, m.start() + 6)
        if 0 < n < 5000:
            yield m.start()


def walk(blob, tree):
    """All nodes reachable from the root, as index -> (name_off, flags, a, b)."""
    nodes, queue, seen = {}, [0], set()
    while queue:
        i = queue.pop()
        if i in seen:
            continue
        seen.add(i)
        o = tree + i * NODE
        if o + NODE > len(blob):
            return None
        name_off, flags = u32(blob, o), u16(blob, o + 4)
        if flags & ~0x07:
            return None
        if flags & DIR:
            count, first = u32(blob, o + 6), u32(blob, o + 10)
            if count > 5000 or first > 200000:
                return None
            nodes[i] = (name_off, flags, count, first)
            queue.extend(range(first, first + count))
        else:
            nodes[i] = (name_off, flags, 0, u32(blob, o + 10))
        if len(nodes) > 200000:
            return None
    return nodes


def best_base(offsets, positions):
    """The base B maximising how many B+off land on a known position.

    Every known position proposes one base (position minus a probe offset). All
    of them are tried: each proposal is equally likely a priori, so sampling a
    few would miss the true base almost every time.
    """
    offsets = sorted(set(offsets))
    probe = offsets[len(offsets) // 2]
    best, hits = None, 0
    for p in positions:
        base = p - probe
        h = sum((base + off) in positions for off in offsets)
        if h > hits:
            best, hits = base, h
            if h == len(offsets):
                break
    return best, hits, len(offsets)


def extract(binary: Path, out: Path):
    blob = binary.read_bytes()
    names = find_name_entries(blob)
    name_positions = set(names)
    zstd_positions = {m.start() for m in re.finditer(rb"\x28\xb5\x2f\xfd", blob)}
    print(f"{len(names)} valid name entries, {len(zstd_positions)} zstd frames")

    dctx = zstandard.ZstdDecompressor()
    written = 0
    for tree in root_candidates(blob):
        nodes = walk(blob, tree)
        if not nodes or len(nodes) < 3:
            continue
        child_offs = [n[0] for i, n in nodes.items() if i != 0]
        nbase, nhits, ntotal = best_base(child_offs, name_positions)
        if nbase is None or nhits < ntotal * 0.95:
            continue

        files = {i: n for i, n in nodes.items() if not n[1] & DIR}
        z = [n[3] for n in files.values() if n[1] & ZSTD]
        # Data entries are [u32 size][payload]; a zstd payload starts with magic.
        if z:
            dbase, dhits, dtotal = best_base(z, {p - 4 for p in zstd_positions})
        else:
            dbase, dhits, dtotal = None, 0, 0
        if dbase is None:
            print(f"tree @{tree:#x}: {len(files)} files, no zstd anchor, skipped")
            continue

        # Build paths top-down.
        paths = {0: ""}
        order = [0]
        while order:
            i = order.pop()
            name_off, flags, count, first = nodes[i]
            if flags & DIR:
                for c in range(first, first + count):
                    if c in nodes:
                        paths[c] = paths[i] + "/" + names.get(nbase + nodes[c][0], f"?{c}")
                        order.append(c)

        ok = 0
        for i, (name_off, flags, _, data_off) in files.items():
            o = dbase + data_off
            size = u32(blob, o)
            payload = blob[o + 4:o + 4 + size]
            try:
                if flags & ZSTD:
                    data = dctx.decompress(payload, max_output_size=64 << 20)
                elif flags & ZLIB:
                    data = zlib.decompress(payload[4:])
                else:
                    data = payload
            except Exception:
                continue
            dest = out / paths[i].lstrip("/")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
            ok += 1
        written += ok
        print(f"tree @{tree:#x}: names {nhits}/{ntotal}, data anchors {dhits}/{dtotal}, "
              f"extracted {ok}/{len(files)}")
    print(f"total written: {written}")


if __name__ == "__main__":
    extract(Path(sys.argv[1]), Path(sys.argv[2]))
