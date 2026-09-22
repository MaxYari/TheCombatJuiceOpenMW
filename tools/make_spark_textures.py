#!/usr/bin/env python3
"""Bakes the streak texture used by meshes/e/impact/*.nif.

    python3 tools/make_spark_textures.py

It is an additive sprite (the NIFs blend it SRC_ALPHA + ONE), so the alpha
channel is the brightness and the RGB is the tint. The tint runs white-hot at
the head to blue down the tail - the "less yellow, a little bit blueish" look.
Plain stdlib, no Pillow: PNG is simple enough to write by hand.
"""

import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "textures" / "MaxYari" / "cinematic combat"

# Tint ramp, hottest first. Positions are 0 (core / head) to 1 (edge / tail).
RAMP = [
    (0.00, (1.00, 1.00, 1.00)),  # white hot
    (0.35, (0.82, 0.92, 1.00)),  # cooling, turning blue
    (0.70, (0.50, 0.72, 1.00)),
    (1.00, (0.32, 0.55, 1.00)),  # cold blue tail
]


def ramp(t):
    t = min(max(t, 0.0), 1.0)
    for i in range(len(RAMP) - 1):
        t0, c0 = RAMP[i]
        t1, c1 = RAMP[i + 1]
        if t <= t1:
            f = (t - t0) / (t1 - t0)
            return tuple(a + (b - a) * f for a, b in zip(c0, c1))
    return RAMP[-1][1]


def write_png(path, width, height, pixels):
    """pixels: list of rows, each row a list of (r, g, b, a) floats in 0..1."""
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type: none
        for r, g, b, a in row:
            raw += bytes(int(min(max(v, 0.0), 1.0) * 255 + 0.5) for v in (r, g, b, a))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)
    print(f"wrote {path.relative_to(path.parent.parent.parent.parent)} ({width}x{height})")


def make_streak(width=64, height=16):
    """Comet head at u=0 tapering to a tail at u=1, for the oriented streaks."""
    rows = []
    for y in range(height):
        v = abs((y + 0.5) / height * 2.0 - 1.0)    # 0 on the centre line, 1 at the edge
        row = []
        for x in range(width):
            u = (x + 0.5) / width                  # 0 head, 1 tail
            along = (1.0 - u) ** 1.6               # fade out towards the tail
            along *= min(1.0, (1.0 - u) * 6.0 + 0.55)
            thickness = 1.0 - u * 0.55             # tail is thinner than the head
            across = max(0.0, 1.0 - (v / thickness) ** 2) ** 1.8
            a = along * across
            a = min(1.0, a * 1.3 + (0.85 * across if u < 0.06 else 0.0))
            row.append((*ramp(max(u, v * 0.5)), a))
        rows.append(row)
    return width, height, rows


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    write_png(OUT / "spark_streak.png", *make_streak())


if __name__ == "__main__":
    main()
