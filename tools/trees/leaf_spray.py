#!/usr/bin/env python3
"""Builds the broadleaf spray atlas of the 3D trees from the free leaf set.

    python3 tools/trees/leaf_spray.py LEAF_ALBEDO LEAF_OPACITY OUT.png

The leaf set (ambientCG, CC0) is six photographed leaves. A leaf card of
the trees used to draw them one per cell of a grid, turned at random, and
at 20 to 30 cm a leaf; from a few metres off that read as a painted
cartoon, and further off as a halftone dot pattern. This lays the photo
leaves out the way a branch carries them instead: twigs from the bottom
of each spray, leaves of real size (7 to 11 cm on a 2 m card) along them,
pointing out, tilted (foreshortened) and overlapping, the ones behind
darker and each casting a soft shadow on what is below it. The result is
an RGBA atlas of 2 x 2 sprays, alpha the leaf coverage, colour bled out
into the gaps so mipmaps don't pick up a dark fringe. The game falls back
to the old cards when the atlas is missing, so Pillow is optional
(fetch_free_assets.py skips this without it).
"""

import math
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SPRAY = 1024  # pixels per spray, for a card 2 m across
GRID = 2  # sprays across and down
LEAF_PX = (36, 58)  # leaf length in pixels: 7 to 11 cm
TWIG = (112, 96, 76)


def _leaves(albedo: Image.Image, opacity: Image.Image) -> list:
    """The six leaves of the 3 x 2 set, cropped to their bounds, tip up."""
    out = []
    w, h = albedo.size
    cw, ch = w // 3, h // 2
    rgba = albedo.convert("RGB").copy()
    rgba.putalpha(opacity.convert("L").resize(albedo.size))
    for j in range(2):
        for i in range(3):
            cell = rgba.crop((i * cw, j * ch, (i + 1) * cw, (j + 1) * ch))
            box = cell.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
            if box:
                out.append(cell.crop(box))
    return out


def _spray(leaves: list, rng: random.Random) -> Image.Image:
    size = SPRAY
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    placed = []  # (depth, x, y, angle, length, squash, leaf index)
    twigs = []
    # A main stem from the bottom middle, with side twigs off it, each
    # bending a little, and leaves along every twig.
    base = (size * rng.uniform(0.45, 0.55), size * 0.98)
    stem_dir = -math.pi / 2 + rng.uniform(-0.25, 0.25)
    pts = [base]
    x, y, a = base[0], base[1], stem_dir
    for _ in range(18):
        a += rng.uniform(-0.12, 0.12)
        x += math.cos(a) * size * 0.048
        y += math.sin(a) * size * 0.048
        pts.append((x, y))
    twigs.append((pts, 5.0))
    def grow(start, a, length, side, width, depth):
        seg = [start]
        x, y = start
        n = 10
        for _ in range(n):
            a += rng.uniform(-0.1, 0.1) - side * 0.03
            x += math.cos(a) * length / n
            y += math.sin(a) * length / n
            x = min(max(x, 90), size - 90)
            y = min(max(y, 90), size - 90)
            seg.append((x, y))
        twigs.append((seg, width))
        if depth > 0:
            # Shorter twigs off this one, on alternate sides.
            for k in range(2):
                s2 = 1 if k % 2 == 0 else -1
                at = seg[rng.randint(3, n - 2)]
                grow(at, a + s2 * rng.uniform(0.5, 1.0), length * rng.uniform(0.35, 0.55), s2, width * 0.6, depth - 1)

    for k in range(rng.randint(8, 10)):
        start = pts[rng.randint(2, len(pts) - 3)]
        side = 1 if k % 2 == 0 else -1
        grow(start, stem_dir + side * rng.uniform(0.6, 1.4), rng.uniform(0.25, 0.42) * size, side, 2.5, 1)
    for seg, width in twigs:
        for i in range(len(seg) - 1):
            wdt = max(1, int(width * (1.0 - i / len(seg) * 0.7)))
            draw.line([seg[i], seg[i + 1]], fill=TWIG + (255,), width=wdt)
        # Leaves in pairs along the twig, every few centimetres.
        total = len(seg) - 1
        for i in range(1, total + 1):
            px, py = seg[i]
            qx, qy = seg[i - 1]
            along = math.atan2(py - qy, px - qx)
            for side in (-1, 1):
                if rng.random() < 0.15:
                    continue
                ang = along + side * rng.uniform(0.5, 1.1)
                length = rng.uniform(*LEAF_PX)
                placed.append((rng.random(), px, py, ang, length, rng.uniform(0.45, 1.0), rng.randrange(len(leaves))))
        # A leaf at the tip, pointing on.
        ex, ey = seg[-1]
        placed.append((rng.random(), ex, ey, along, rng.uniform(*LEAF_PX), rng.uniform(0.6, 1.0), rng.randrange(len(leaves))))
    # A few loose leaves to thicken the middle.
    for _ in range(60):
        seg, _w = twigs[rng.randrange(len(twigs))]
        px, py = seg[rng.randrange(len(seg))]
        placed.append((rng.random(), px + rng.uniform(-25, 25), py + rng.uniform(-25, 25), rng.uniform(0, math.tau),
                       rng.uniform(*LEAF_PX), rng.uniform(0.4, 1.0), rng.randrange(len(leaves))))
    placed.sort()
    shadow_off = (5, 7)
    for depth, px, py, ang, length, squash, idx in placed:
        leaf = leaves[idx]
        lw, lh = leaf.size
        s = length / lh
        img = leaf.resize((max(2, int(lw * s * squash)), max(2, int(lh * s))), Image.LANCZOS)
        if rng.random() < 0.5:
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
        # The photo's tip is up; turn it to point along ang (image y down).
        img = img.rotate(-math.degrees(ang) - 90, resample=Image.BICUBIC, expand=True)
        # Back leaves darker and a touch bluer; front ones lit.
        shade = 0.68 + 0.32 * depth
        r, g, b, alpha = img.split()
        r = r.point(lambda v: int(v * shade * 0.97))
        g = g.point(lambda v: int(v * shade))
        b = b.point(lambda v: int(v * shade * 1.05))
        img = Image.merge("RGBA", (r, g, b, alpha))
        # The petiole sits at the twig: offset by half the leaf along ang.
        cx = px + math.cos(ang) * length * 0.5
        cy = py + math.sin(ang) * length * 0.5
        ox = int(cx - img.width / 2)
        oy = int(cy - img.height / 2)
        # Soft shadow on what is already drawn (the leaves behind).
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        sh.putalpha(alpha.point(lambda v: int(v * 0.3)).filter(ImageFilter.GaussianBlur(3)))
        below = Image.new("RGBA", layer.size, (0, 0, 0, 0))
        below.paste(sh, (ox + shadow_off[0], oy + shadow_off[1]))
        # Darken only where something is drawn: multiply rgb, keep alpha.
        rgb = layer.convert("RGB")
        dark = Image.new("RGB", layer.size, (0, 0, 0))
        mask = ImageChops.multiply(below.getchannel("A"), layer.getchannel("A"))
        rgb = Image.composite(dark, rgb, mask)
        a0 = layer.getchannel("A")
        layer = rgb.convert("RGBA")
        layer.putalpha(a0)
        layer.alpha_composite(img, (ox, oy)) if 0 <= ox and 0 <= oy and ox + img.width <= size and oy + img.height <= size \
            else _paste_clipped(layer, img, ox, oy)
    return layer


def _paste_clipped(layer: Image.Image, img: Image.Image, ox: int, oy: int) -> None:
    tmp = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    tmp.paste(img, (ox, oy), img)
    layer.alpha_composite(tmp)


def _bleed(img: Image.Image) -> Image.Image:
    """Spread the leaves' colour into the transparent gaps (alpha kept)."""
    alpha = img.getchannel("A")
    rgb = img.convert("RGB")
    filled = rgb
    mask = alpha.point(lambda v: 255 if v > 8 else 0)
    for radius in (2, 4, 8, 16, 32, 64):
        # Blur the filled colour (not normalised by coverage: the gaps just
        # need a leafy green, not an exact one).
        blur = filled.filter(ImageFilter.GaussianBlur(radius))
        cover = mask.filter(ImageFilter.GaussianBlur(radius))
        filled = Image.composite(filled, blur, mask)
        mask = ImageChops.lighter(mask, cover.point(lambda v: 255 if v > 20 else 0))
    out = filled.convert("RGBA")
    out.putalpha(alpha)
    return out


def build(albedo_path: str, opacity_path: str, out_path: str, seed: int = 2003) -> None:
    leaves = _leaves(Image.open(albedo_path), Image.open(opacity_path))
    rng = random.Random(seed)
    atlas = Image.new("RGBA", (SPRAY * GRID, SPRAY * GRID), (0, 0, 0, 0))
    for j in range(GRID):
        for i in range(GRID):
            atlas.paste(_spray(leaves, rng), (i * SPRAY, j * SPRAY))
    _bleed(atlas).save(out_path, optimize=True)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2], sys.argv[3])
