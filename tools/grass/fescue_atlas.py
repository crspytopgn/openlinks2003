#!/usr/bin/env python3
"""Draws the fescue tuft atlas for the long grass on the hills (FescueField).

    python3 tools/grass/fescue_atlas.py OUT.png

Out of play, a links or parkland course leaves its slopes as tall fescue:
a low mass of fine grey-green blades, some of them straw towards the tips,
leaning every way and bending at the top, with thin stalks of pale buff
seed heads standing above them. From the tee that reads as a soft, wispy,
tawny-green pile over the hills, where a flat ground texture reads as felt
(and thick straw-gold blades read as yellow dots). This draws four such
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
# Real summer fescue (Geograph photos of links and heathland roughs): a
# grey-green mass of wiry blades, only some of them straw at the tips, and
# above it thin stalks carrying pale buff seed heads that catch the light.
BASE = (52, 66, 34)  # deep green, shaded, at the root
MID = (104, 118, 72)  # grey-green
TIP = (170, 162, 118)  # dry, pale straw
SEED = (196, 178, 134)  # pale buff panicles
STALK = (150, 142, 100)


def _mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _blade_colour(t, dry, shade):
    c = _mix(BASE, MID, min(t * 1.8, 1.0)) if t < 0.55 else _mix(MID, TIP, (t - 0.55) / 0.45 * 0.5)
    c = _mix(c, TIP, dry * 0.75 * t)
    return tuple(max(0, min(255, int(v * shade))) for v in c)


def _tuft(rng: random.Random) -> Image.Image:
    # Drawn at twice the size and shrunk, for smooth thin blades.
    s = CELL * 2
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    root_x = s * 0.5
    blades = []
    # Fine blades, most of them in a low, dense mass, a few long ones.
    for _ in range(rng.randint(220, 260)):
        rx = root_x + rng.gauss(0, s * 0.09)
        height = (rng.uniform(0.25, 0.55) if rng.random() < 0.7 else rng.uniform(0.55, 0.78)) * s
        lean = rng.gauss(0, 0.3)
        bend = rng.uniform(0.2, 0.9) * (1 if lean >= 0 else -1)
        blades.append((rng.random(), rx, height, lean, bend, rng.random() < 0.25, False))
    # Seed stalks standing clear above the blades.
    for _ in range(rng.randint(14, 22)):
        rx = root_x + rng.gauss(0, s * 0.07)
        blades.append((rng.random(), rx, rng.uniform(0.7, 0.97) * s, rng.gauss(0, 0.15), rng.uniform(-0.2, 0.2), True, True))
    blades.sort()  # depth: back to front
    for depth, rx, height, lean, bend, dry, stalk in blades:
        shade = 0.55 + 0.45 * depth
        steps = 14
        pts = []
        for i in range(steps + 1):
            t = i / steps
            # Rises, leans, and bends over towards the tip.
            x = rx + (lean * t + bend * t * t * t * 0.5) * height * 0.6
            y = s - 4 - height * (t - 0.18 * abs(bend) * t * t * t)
            pts.append((x, y, t))
        width0 = 4 if not stalk else 3
        for i in range(steps):
            x0, y0, t0 = pts[i]
            x1, y1, t1 = pts[i + 1]
            w = max(1, int(round(width0 * (1.0 - t0 * 0.7))))
            col = _mix(STALK, TIP, t0) if stalk else _blade_colour(t0, 1.0 if dry else 0.0, shade)
            if stalk:
                col = tuple(int(v * (0.7 + 0.3 * depth)) for v in col)
            d.line([(x0, y0), (x1, y1)], fill=col + (255,), width=w)
        if stalk:
            # An open panicle: short spikelets hanging off the top fifth,
            # on hair-thin branches, so it reads as a light, airy head.
            x, y, _t = pts[-1]
            for k in range(rng.randint(6, 10)):
                u = k / 9.0
                bx = x - lean * u * 30
                by = y + u * height * 0.2
                side = rng.choice((-1, 1))
                ex = bx + side * rng.uniform(6, 18)
                ey = by + rng.uniform(4, 14)
                d.line([(bx, by), (ex, ey)], fill=tuple(int(v * shade) for v in STALK) + (255,), width=1)
                r = rng.uniform(1.8, 2.6)
                d.ellipse([ex - r, ey - r * 2.2, ex + r, ey + r * 2.2], fill=tuple(min(255, int(v * (0.8 + 0.2 * depth))) for v in SEED) + (255,))
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
