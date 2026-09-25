#!/usr/bin/env python3
"""Packs the logo into the texture the settings page shows at its top.

    python3 tools/make_logo_texture.py

Reads imgs/nexus/logo.png, scales it to 960 wide - twice what the page draws,
so it halves cleanly - centres it on a power-of-two canvas and writes
textures/MaxYari/combat juice/logo.dds: uncompressed, with the full mip chain,
each level averaged by alpha so the edges do not darken (the same writer as
They Bleed's logo). Prints the content rectangle, which menu.lua crops to.

Needs ImageMagick (`magick`).
"""

import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "imgs" / "nexus" / "logo.png"
OUT = ROOT / "textures" / "MaxYari" / "combat juice" / "logo.dds"
TEX_W, TEX_H = 1024, 128
LOGO_W = 960


def write_dds_rect(path, pixels, w, h):
    """Uncompressed A8R8G8B8 DDS with the full mip chain, alpha-weighted colour averaging."""
    levels = [(w, h, pixels)]
    while w > 1 or h > 1:
        nw, nh = max(1, w // 2), max(1, h // 2)
        src = levels[-1][2]
        out = []
        for y in range(nh):
            for x in range(nw):
                quad = [src[min(y * 2 + dy, h - 1) * w + min(x * 2 + dx, w - 1)] for dy in (0, 1) for dx in (0, 1)]
                a = sum(p[3] for p in quad)
                if a > 0:
                    rgb = [sum(p[c] * p[3] for p in quad) / a for c in range(3)]
                else:
                    rgb = [sum(p[c] for p in quad) / 4 for c in range(3)]
                out.append((rgb[0], rgb[1], rgb[2], a / 4))
        levels.append((nw, nh, out))
        w, h = nw, nh
    W, H = levels[0][0], levels[0][1]
    header = struct.pack("<4sIIIIIII44x", b"DDS ", 124, 0x1 | 0x2 | 0x4 | 0x8 | 0x1000 | 0x20000, H, W, W * 4, 0,
                         len(levels))
    header += struct.pack("<IIIIIIII", 32, 0x41, 0, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)
    header += struct.pack("<IIII4x", 0x1000 | 0x400000 | 0x8, 0, 0, 0)
    body = bytearray()
    for _, _, level in levels:
        for r, g, b, a in level:
            body += bytes((round(b), round(g), round(r), round(a)))
    path.write_bytes(header + body)


def main():
    raw = subprocess.run(["magick", str(SOURCE), "-resize", f"{LOGO_W}x", "-background", "none",
                          "-gravity", "center", "-extent", f"{TEX_W}x{TEX_H}", "-depth", "8", "rgba:-"],
                         capture_output=True, check=True).stdout
    pixels = [tuple(raw[i:i + 4]) for i in range(0, len(raw), 4)]
    xs = [i % TEX_W for i, p in enumerate(pixels) if p[3] > 0]
    ys = [i // TEX_W for i, p in enumerate(pixels) if p[3] > 0]
    write_dds_rect(OUT, pixels, TEX_W, TEX_H)
    print(f"wrote {OUT.name} ({TEX_W}x{TEX_H}); content offset ({min(xs)}, {min(ys)}) "
          f"size ({max(xs) - min(xs) + 1}, {max(ys) - min(ys) + 1})")


if __name__ == "__main__":
    main()
