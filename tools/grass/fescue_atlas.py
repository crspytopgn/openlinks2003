#!/usr/bin/env python3
"""Draws the fescue tuft atlas for the long grass on the hills (FescueField).

    python3 tools/grass/fescue_atlas.py OUT.png

Out of play, a links or parkland course leaves its slopes as tall fescue:
fine blades 40 to 80 cm, green at the base and straw-gold towards the
tips, with seed stalks above them, leaning every way and bending at the
top. From the tee that reads as a soft, wispy, golden-green pile over the
hills, where a flat ground texture reads as felt. This draws four such
tufts (2 x 2, each 512 px for a tuft 1 m wide and 1 m tall), alpha the
blades, colour bled into the gaps for clean mipmaps. Nothing is photographed
or downloaded, so it needs only Pillow.
"""

import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

CELL = 512
GRID = 2
BASE = (74, 92, 44)  # green at the root
MID = (128, 136, 70)
TIP = (196, 178, 112)  # straw at the tips
SEED = (170, 140, 86)


def _mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _blade_colour(t, dry, shade):
    c = _mix(BASE, MID, min(t * 1.6, 1.0)) if t < 0.6 else _mix(MID, TIP, (t - 0.6) / 0.4)
    c = _mix(c, TIP, dry * 0.6)
    return tuple(max(0, min(255, int(v * shade))) for v in c)


def _tuft(rng: random.Random) -> Image.Image:
    # Drawn at twice the size and shrunk, for smooth thin blades.
    s = CELL * 2
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    root_x = s * 0.5
    blades = []
    for _ in range(rng.randint(150, 190)):
        rx = root_x + rng.gauss(0, s * 0.07)
        height = rng.uniform(0.35, 0.82) * s
        lean = rng.gauss(0, 0.25)
        bend = rng.uniform(0.2, 0.9) * (1 if lean >= 0 else -1)
        blades.append((rng.random(), rx, height, lean, bend, rng.random() < 0.3, False))
    for _ in range(rng.randint(10, 18)):
        rx = root_x + rng.gauss(0, s * 0.05)
        blades.append((rng.random(), rx, rng.uniform(0.75, 0.97) * s, rng.gauss(0, 0.18), rng.uniform(-0.15, 0.15), True, True))
    blades.sort()  # depth: back to front
    for depth, rx, height, lean, bend, dry, stalk in blades:
        shade = 0.62 + 0.38 * depth
        steps = 14
        pts = []
        for i in range(steps + 1):
            t = i / steps
            # Rises, leans, and bends over towards the tip.
            x = rx + (lean * t + bend * t * t * t * 0.5) * height * 0.6
            y = s - 4 - height * (t - 0.18 * abs(bend) * t * t * t)
            pts.append((x, y, t))
        width0 = 7 if not stalk else 4
        for i in range(steps):
            x0, y0, t0 = pts[i]
            x1, y1, t1 = pts[i + 1]
            w = max(1, int(round(width0 * (1.0 - t0 * 0.85))))
            d.line([(x0, y0), (x1, y1)], fill=_blade_colour(t0, 1.0 if dry else 0.0, shade) + (255,), width=w)
        if stalk:
            # A loose seed head: small grains along the top fifth.
            x, y, _t = pts[-1]
            for k in range(rng.randint(7, 12)):
                u = k / 10.0
                gx = x + rng.gauss(0, 7) - lean * u * 30
                gy = y + u * height * 0.18
                r = rng.uniform(3, 5)
                d.ellipse([gx - r, gy - r * 1.8, gx + r, gy + r * 1.8], fill=tuple(int(v * shade) for v in SEED) + (255,))
    return img.resize((CELL, CELL), Image.LANCZOS)


def _bleed(img: Image.Image) -> Image.Image:
    alpha = img.getchannel("A")
    mask = alpha.point(lambda v: 255 if v > 8 else 0)
    filled = img.convert("RGB")
    for radius in (2, 4, 8, 16, 32):
        blur = filled.filter(ImageFilter.GaussianBlur(radius))
        filled = Image.composite(filled, blur, mask)
        mask = mask.filter(ImageFilter.GaussianBlur(radius)).point(lambda v: 255 if v > 20 else 0)
    out = filled.convert("RGBA")
    out.putalpha(alpha)
    return out


def build(out_path: str, seed: int = 2003) -> None:
    rng = random.Random(seed)
    atlas = Image.new("RGBA", (CELL * GRID, CELL * GRID), (0, 0, 0, 0))
    for j in range(GRID):
        for i in range(GRID):
            atlas.alpha_composite(_tuft(rng), (i * CELL, j * CELL))
    _bleed(atlas).save(out_path, optimize=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    build(sys.argv[1])
