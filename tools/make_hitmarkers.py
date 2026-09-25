#!/usr/bin/env python3
"""Bakes the hit marker textures this mod draws itself.

    python3 tools/make_hitmarkers.py

So far: a plain diagonal cross, one piece.
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


def cross(size, margin, thickness, samples=8):
    """A plain diagonal cross: two strokes of even width, corner to corner,
    meeting in the middle and cut square at the edges. Supersampled so the
    diagonals stay smooth when the UI shrinks it down."""
    rows = []
    half = size / 2
    reach = half - margin
    for y in range(size):
        row = []
        for x in range(size):
            hits = 0
            for sy in range(samples):
                for sx in range(samples):
                    dx = x + (sx + 0.5) / samples - half
                    dy = y + (sy + 0.5) / samples - half
                    if max(abs(dx), abs(dy)) > reach:
                        continue
                    # distance from the nearer of the two diagonals
                    if abs(abs(dx) - abs(dy)) / 1.4142 <= thickness / 2:
                        hits += 1
            row.append((1.0, 1.0, 1.0, hits / samples ** 2))
        rows.append(row)
    return size, size, rows


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    write_png(OUT / "cross.png", *cross(32, 1, 4.5))


if __name__ == "__main__":
    main()
