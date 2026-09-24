#!/usr/bin/env python3
"""Bakes the hit marker textures this mod draws itself.

    python3 tools/make_hitmarkers.py

So far: a diagonal cross, as four separate arms so it can be drawn either as one
piece or as four that slide apart, and a single-piece version of the same.
Plain stdlib; PNG is simple enough to write by hand.
"""

import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "textures" / "MaxYari" / "combat juice" / "hitmarkers"


def write_png(path, width, height, pixels):
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw += bytes(int(min(max(v, 0.0), 1.0) * 255 + 0.5) for v in (r, g, b, a))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    path.write_bytes(png)
    print(f"wrote {path.name} ({width}x{height})")


def bar(size, thickness, taper, flip):
    """One arm of the cross: a tapered diagonal stroke, corner to corner."""
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            u = (x + 0.5) / size
            v = (y + 0.5) / size
            if flip:
                u = 1.0 - u
            # distance from the diagonal, and how far along it we are
            along = (u + v) * 0.5
            across = abs(u - v) / 1.4142
            width = thickness * (1.0 - taper * along)
            edge = max(0.0, 1.0 - across / max(width, 1e-4))
            # fade the inner end so the four arms meet softly at the middle
            alpha = edge ** 1.5 * min(1.0, along * 4.0)
            row.append((1.0, 1.0, 1.0, alpha))
        rows.append(row)
    return size, size, rows


def cross(size, thickness):
    """All four arms in one texture, for markers drawn as a single piece."""
    rows = []
    half = size / 2
    for y in range(size):
        row = []
        for x in range(size):
            dx = (x + 0.5 - half) / half
            dy = (y + 0.5 - half) / half
            d = min(abs(abs(dx) - abs(dy)) / 1.4142, 1.0)
            reach = max(abs(dx), abs(dy))
            edge = max(0.0, 1.0 - d / thickness)
            alpha = edge ** 1.5 * min(1.0, reach * 3.0) * max(0.0, 1.0 - max(reach - 0.75, 0.0) * 4.0)
            row.append((1.0, 1.0, 1.0, alpha))
        rows.append(row)
    return size, size, rows


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, flip in (("tl", False), ("br", False), ("tr", True), ("bl", True)):
        write_png(OUT / f"cross_{name}.png", *bar(32, 0.16, 0.55, flip))
    write_png(OUT / "cross.png", *cross(64, 0.10))


if __name__ == "__main__":
    main()
