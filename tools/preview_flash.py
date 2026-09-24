#!/usr/bin/env python3
"""Runs cc_blowout.omwfx's own arithmetic over an image, outside the game.

    <blender>/python/bin/python3 preview_flash.py in.png out.png [uniform=value ...]

The uniform defaults are read straight out of the shader, so this previews what
the file actually ships. Needs numpy; ImageMagick does the PNG reading.
"""
import re, subprocess, sys
from pathlib import Path
import numpy as np

SHADER = Path(__file__).resolve().parent.parent / "shaders" / "cj_flash.omwfx"

def defaults():
    text = SHADER.read_text()
    out = {}
    for kind, name, body in re.findall(r"uniform_(\w+)\s+(\w+)\s*\{(.*?)\}", text, re.S):
        m = re.search(r"default\s*=\s*([^;]+);", body)
        if not m: continue
        v = m.group(1).strip()
        if v.startswith("vec3"):
            inside = v[v.index("(") + 1:v.rindex(")")]
            out[name] = np.array([float(x) for x in inside.split(",")])
        else:
            out[name] = float(v)
    return out

def read(path):
    w, h = subprocess.run(["magick", path, "-format", "%w %h", "info:"],
                          capture_output=True, text=True).stdout.split()
    raw = subprocess.run(["magick", path, "-depth", "8", "rgb:-"], capture_output=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(int(h), int(w), 3).astype(np.float64) / 255.0

def write(img, path):
    h, w, _ = img.shape
    data = (np.clip(img, 0, 1) * 255).astype(np.uint8).tobytes()
    subprocess.run(["magick", "-size", f"{w}x{h}", "-depth", "8", "rgb:-", path],
                   input=data, check=True)

def zoom_blur(img, amount, taps=6):
    h, w, _ = img.shape
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    cy, cx = (h - 1) / 2, (w - 1) / 2
    out, total = np.zeros_like(img), 0.0
    for i in range(taps):
        f = i / (taps - 1) * amount
        weight = 1.0 - 0.55 * (i / (taps - 1))
        sy = np.clip(((ys - cy) * (1 - f) + cy).round().astype(int), 0, h - 1)
        sx = np.clip(((xs - cx) * (1 - f) + cx).round().astype(int), 0, w - 1)
        out += img[sy, sx] * weight
        total += weight
    return out / total

def box_blur(img, radius):
    """Stand-in for the quarter res buffer plus its spiral taps."""
    k = max(1, int(radius))
    pad = np.pad(img, ((k, k), (k, k), (0, 0)), mode="edge")
    cum = pad.cumsum(0).cumsum(1)
    cum = np.pad(cum, ((1, 0), (1, 0), (0, 0)))
    n = 2 * k + 1
    out = (cum[n:, n:] - cum[:-n, n:] - cum[n:, :-n] + cum[:-n, :-n]) / (n * n)
    return out

LUMA = np.array([0.2126, 0.7152, 0.0722])

def flash(img, u, s=1.0):
    def tone(c):
        contrast = 1.0 + (u["uContrastMul"] - 1.0) * s
        c = (c - u["uPivot"]) * contrast + u["uPivot"]
        return np.maximum(c * (1.0 + u["uExposureMul"] * s), 0.0)

    color = tone(zoom_blur(img, u["uRadial"] * s))

    bright = tone(img)
    luma = bright @ LUMA
    over = np.clip((luma - u["uThreshold"]) / max(1 - u["uThreshold"], 1e-3), 0, 2)
    glare = box_blur(bright * over[..., None], img.shape[0] * u["uBloomRadius"] * 0.5)

    # the bloom is repainted in the tint, then a flat wash on top
    glare_luma = glare @ LUMA
    colorize = u.get("uGlareColorize", 0.0)
    glare = (glare * (1 - colorize) + glare_luma[..., None] * colorize) * u["uGlareTint"]
    color = color + glare * u["uBloom"] * s

    luma = color @ LUMA
    color = luma[..., None] + (color - luma[..., None]) * (1.0 + (u["uSaturation"] - 1.0) * s)

    # the wash and the tint are held off the shadows
    lo = u.get("uLitFrom", 0.0)
    t = np.clip((luma - lo) / 0.45, 0, 1)
    lit = (t * t * (3 - 2 * t))[..., None]
    color = color + u["uGlareTint"] * u.get("uWash", 0.0) * s * lit
    amt = u["uTintAmount"] * s * lit
    color = color * (1 - amt) + u["uTint"] * luma[..., None] * amt
    return color

if __name__ == "__main__":
    u = defaults()
    for arg in sys.argv[3:]:
        k, v = arg.split("=")
        u[k] = np.array([float(x) for x in v.split(",")]) if "," in v else float(v)
    img = read(sys.argv[1])
    out = flash(img, u)
    write(out, sys.argv[2])
    inner = (slice(30, 350), slice(40, 600))
    a, b = img[inner], np.clip(out[inner], 0, 1)
    fmt = lambda x: f"r={x[...,0].mean():.3f} g={x[...,1].mean():.3f} b={x[...,2].mean():.3f}"
    print(f"  in : {fmt(a)}")
    print(f"  out: {fmt(b)}  {'COLD' if b[...,2].mean() > b[...,0].mean() else 'warm'}")
