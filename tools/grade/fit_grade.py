#!/usr/bin/env python3
"""Fits the learned colour grade (docs/colour-grade.md).

Measures the sky, turf, trees and sand in real golf photos and in our own
renders, in CIE Lab, and bakes a 32x32x32 colour lookup that moves each
region of the renders onto the photos' colours. The game applies it at the
end of the post pass (post_process.gdshader, PostProcess.lut_for).

    fit_grade.py --refs DIR [--refs DIR ...] --renders DIR --out LUT.png
                 [--strength 0.8] [--preview DIR] [--report FILE]

The photos are only measured: nothing of them goes into the lookup but a
handful of averages per region, and they are never committed. Needs numpy
and Pillow.
"""

import argparse
import glob
import json
import os
import sys

import numpy as np
from PIL import Image

N = 32  # lookup size per axis
CLASSES = ["sky", "turf", "trees", "sand"]
# How far a region's spread may be stretched or squeezed.
SPREAD_LIMITS = (0.6, 1.6)
# How widely each region claims colours near its own (in its spreads), and
# how strongly colours like none of the regions keep their own colour.
WIDTH = 2.0
NEUTRAL = 3.0
LOW_SUN = False  # --low-sun: golden hour region rules (classify)
OTHER = 0.03


# --- colour --------------------------------------------------------------

def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


_M = np.array([[0.4124564, 0.3575761, 0.1804375],
               [0.2126729, 0.7151522, 0.0721750],
               [0.0193339, 0.1191920, 0.9503041]])
_M_INV = np.linalg.inv(_M)
_WHITE = np.array([0.95047, 1.0, 1.08883])


def _f(t):
    return np.where(t > (6 / 29) ** 3, np.cbrt(t), t / (3 * (6 / 29) ** 2) + 4 / 29)


def _f_inv(t):
    return np.where(t > 6 / 29, t ** 3, 3 * (6 / 29) ** 2 * (t - 4 / 29))


def srgb_to_lab(rgb):
    """sRGB 0..1 (..., 3) to Lab."""
    xyz = srgb_to_linear(rgb) @ _M.T / _WHITE
    f = _f(xyz)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def lab_to_srgb(lab):
    fy = (lab[..., 0] + 16) / 116
    fx = fy + lab[..., 1] / 500
    fz = fy - lab[..., 2] / 200
    xyz = np.stack([_f_inv(fx), _f_inv(fy), _f_inv(fz)], -1) * _WHITE
    return linear_to_srgb(xyz @ _M_INV.T)


# --- regions -------------------------------------------------------------

def classify(lab, rows):
    """Masks of each region from colour and height in the frame (rows: 0 at
    the top, 1 at the bottom). Deliberately strict: a pixel that isn't
    clearly one of them (people, carts, water, buildings) is left out."""
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    chroma = np.hypot(a, b)
    hue = np.degrees(np.arctan2(b, a)) % 360
    green = (hue > 95) & (hue < 175) & (chroma > 8)
    sky = (rows < 0.65) & (((hue > 200) & (hue < 290) & (L > 35)) | ((L > 78) & (chroma < 10)))
    trees = green & (L < 42) & (rows < 0.85)
    turf = green & (L >= 38) & (rows > 0.3)
    if LOW_SUN:
        # A low sun: the sky near the sun goes warm, the turf falls into
        # long shade, and green alone can't tell turf from trees. Tell
        # them apart by height instead: trees stand above the horizon.
        green = (hue > 85) & (hue < 175) & (chroma > 6)
        sky = sky | ((rows < 0.5) & (L > 50) & (chroma < 40) & ((hue < 100) | (hue > 290)))
        trees = green & (L < 45) & (rows < 0.55)
        turf = green & (rows > 0.55)
    sand = (L > 62) & (chroma > 4) & (chroma < 30) & (hue > 55) & (hue < 100) & (rows > 0.35)
    return {"sky": sky, "turf": turf, "trees": trees, "sand": sand}


def load(path, width=480):
    im = Image.open(path).convert("RGB")
    im = im.resize((width, max(1, round(im.height * width / im.width))), Image.BILINEAR)
    rgb = np.asarray(im, dtype=np.float64) / 255.0
    rows = np.repeat((np.arange(rgb.shape[0]) + 0.5)[:, None] / rgb.shape[0], rgb.shape[1], 1)
    return rgb, rows


PERCENTILES = np.linspace(2, 98, 25)


def tone_curve(ref_paths, ren_paths, amount):
    """A lightness curve (Lab L in, L out) taking the renders' spread of
    light and dark onto the photos': whole frames, percentile to
    percentile, `amount` of the way."""
    def pct(paths):
        rows = []
        for p in paths:
            rgb, _ = load(p, 240)
            rows.append(np.percentile(srgb_to_lab(rgb)[..., 0], PERCENTILES))
        return np.median(np.array(rows), 0)
    src = pct(ren_paths)
    dst = pct(ref_paths)
    dst = src + (dst - src) * amount
    src = np.concatenate([[0.0], src, [100.0]])
    dst = np.maximum.accumulate(np.concatenate([[0.0], dst, [100.0]]))
    return lambda L: np.interp(L, src, dst), src, dst


def measure(paths, min_turf=0.0, used=None, sky_b=None, tone=None):
    """Per region: the median over images of each image's Lab mean and
    spread, and how many images had enough of it. Photos with less than
    `min_turf` of the frame in turf (portraits, clubhouses, crowds) are
    skipped; `used` collects the ones kept."""
    per = {c: [] for c in CLASSES}
    for p in paths:
        rgb, rows = load(p)
        lab = srgb_to_lab(rgb)
        masks = classify(lab, rows)
        if tone is not None:
            lab[..., 0] = tone(lab[..., 0])
        if masks["turf"].mean() < min_turf or (min_turf > 0 and masks["sky"].mean() < 0.03):
            continue
        if sky_b is not None and (masks["sky"].mean() < 0.03 or lab[masks["sky"]][:, 2].mean() > sky_b):
            continue  # not a blue sky: not a sunny-day photo
        if used is not None:
            used.append(p)
        for c, m in masks.items():
            if m.mean() < 0.02:
                continue
            v = lab[m]
            per[c].append(np.concatenate([v.mean(0), v.std(0)]))
    out = {}
    for c, rows_ in per.items():
        if len(rows_) < 2:
            continue
        arr = np.array(rows_)
        out[c] = {"mean": np.median(arr[:, :3], 0), "std": np.median(arr[:, 3:], 0), "images": len(rows_)}
    return out


# --- the lookup ----------------------------------------------------------

def build_lut(ref, ren, strength, tone=None):
    """Lab transfer per region, blended by how much each input colour looks
    like that region in the renders; colours like none of them (the
    golfer's shirt, the ball, the HUD) stay as they are."""
    g = (np.arange(N) + 0.0) / (N - 1)
    b_, g_, r_ = np.meshgrid(g, g, g, indexing="ij")
    rgb = np.stack([r_, g_, b_], -1).reshape(-1, 3)
    lab = srgb_to_lab(rgb)
    if tone is not None:
        lab[:, 0] = tone(lab[:, 0])
    weights = []
    moved = []
    for c in CLASSES:
        if c not in ref or c not in ren:
            continue
        m_r, s_r = ren[c]["mean"], np.maximum(ren[c]["std"], [3.0, 2.0, 2.0])
        m_t, s_t = ref[c]["mean"], np.maximum(ref[c]["std"], [3.0, 2.0, 2.0])
        # Lightness stretches to the photos' spread; colour only shifts.
        # A colour stretch, even blended in faintly, throws colours far
        # from the region about (cloud shading turned peach).
        scale = np.array([np.clip(s_t[0] / s_r[0], *SPREAD_LIMITS), 1.0, 1.0])
        moved.append(m_t + (lab - m_r) * scale)
        # Gaussian membership, widened so the blend between regions is soft.
        z = (lab - m_r) / (s_r * WIDTH)
        weights.append(np.exp(-0.5 * (z ** 2).sum(-1)))
    if not weights:
        sys.exit("no region was found in both the photos and the renders")
    w = np.array(weights)
    # "None of these": keep the colour (after the tone curve). Greys and
    # whites (clouds, white caps, the flagstick) stay neutral too, or the
    # sky's shift would tint them blue and the turf's green.
    chroma = np.hypot(lab[:, 1], lab[:, 2])
    other = OTHER + NEUTRAL * np.exp(-0.5 * (chroma / 6.0) ** 2)
    total = w.sum(0) + other
    out_lab = (np.einsum("kn,knc->nc", w, np.array(moved)) + other[:, None] * lab) / total[:, None]
    out = lab_to_srgb(out_lab)
    out = rgb + (out - rgb) * strength
    return np.clip(out, 0.0, 1.0).reshape(N, N, N, 3)  # [b][g][r]


def lut_image(lut):
    """32 slices of 32x32 side by side: red across, green down, blue by
    slice (post_process.gdshader's lut_lookup)."""
    img = np.zeros((N, N * N, 3))
    for bi in range(N):
        img[:, bi * N:(bi + 1) * N] = lut[bi]
    return Image.fromarray(np.round(img * 255).astype(np.uint8))


def apply_lut(rgb, lut):
    """Trilinear lookup, as the shader does (for previews)."""
    x = np.clip(rgb, 0, 1) * (N - 1)
    i0 = np.floor(x).astype(int)
    i1 = np.minimum(i0 + 1, N - 1)
    f = x - i0
    out = np.zeros_like(rgb)
    for dr in (0, 1):
        for dg in (0, 1):
            for db in (0, 1):
                ri = i1[..., 0] if dr else i0[..., 0]
                gi = i1[..., 1] if dg else i0[..., 1]
                bi = i1[..., 2] if db else i0[..., 2]
                wgt = (f[..., 0] if dr else 1 - f[..., 0]) * (f[..., 1] if dg else 1 - f[..., 1]) * (f[..., 2] if db else 1 - f[..., 2])
                out += lut[bi, gi, ri] * wgt[..., None]
    return out


def describe(stats):
    return {c: {"L": round(v["mean"][0], 1), "a": round(v["mean"][1], 1), "b": round(v["mean"][2], 1),
                "spread": [round(x, 1) for x in v["std"]], "images": v["images"]} for c, v in stats.items()}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--refs", action="append", required=True, help="folder (or glob) of real photos")
    ap.add_argument("--renders", required=True, help="folder (or glob) of our renders, HUD hidden")
    ap.add_argument("--out", required=True, help="the lookup PNG to write")
    ap.add_argument("--strength", type=float, default=0.8)
    ap.add_argument("--preview", help="write each render graded into this folder")
    ap.add_argument("--report", help="write the measurements as JSON")
    ap.add_argument("--min-turf", type=float, default=0.15, help="skip photos with less turf than this (fraction of the frame)")
    ap.add_argument("--tone", type=float, default=0.4, help="how far to match the photos' light and dark overall (0 = not at all)")
    ap.add_argument("--low-sun", action="store_true", help="golden-hour photos and renders: warm skies, turf in long shade")
    ap.add_argument("--blue-sky", type=float, help="keep only photos whose sky is at least this blue (Lab b, e.g. -12)")
    ap.add_argument("--list-kept", help="write the photos used, one per line")
    args = ap.parse_args()
    global LOW_SUN
    LOW_SUN = args.low_sun

    def files(spec):
        if os.path.isdir(spec):
            return sorted(glob.glob(os.path.join(spec, "*.jpg")) + glob.glob(os.path.join(spec, "*.png")))
        return sorted(glob.glob(spec))

    refs = [p for spec in args.refs for p in files(spec)]
    renders = files(args.renders)
    kept = []
    ref = measure(refs, min_turf=args.min_turf, used=kept, sky_b=args.blue_sky)
    print("photos kept: %d of %d" % (len(kept), len(refs)), file=sys.stderr)
    tone, tone_src, tone_dst = tone_curve(kept, renders, args.tone) if args.tone > 0 else (None, [], [])
    ren = measure(renders)
    ren_toned = measure(renders, tone=tone) if tone else ren
    lut = build_lut(ref, ren_toned, args.strength, tone)
    lut_image(lut).save(args.out)
    graded = None
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        tmp = []
        for p in renders:
            rgb, _ = load(p, 960)
            out = apply_lut(rgb, lut)
            path = os.path.join(args.preview, os.path.basename(p))
            Image.fromarray(np.round(out * 255).astype(np.uint8)).save(path)
            tmp.append(path)
        graded = measure(tmp)
    if args.list_kept:
        with open(args.list_kept, "w") as f:
            f.write("\n".join(kept) + "\n")
    report = {"photos": len(kept), "renders": len(renders), "strength": args.strength,
              "tone_curve": [[round(a, 1), round(b, 1)] for a, b in zip(tone_src, tone_dst)],
              "photos_measured": describe(ref), "renders_measured": describe(ren)}
    if graded:
        report["graded_measured"] = describe(graded)
        report["distance_before"] = {c: round(float(np.linalg.norm(ren[c]["mean"] - ref[c]["mean"])), 1) for c in ref if c in ren}
        report["distance_after"] = {c: round(float(np.linalg.norm(graded[c]["mean"] - ref[c]["mean"])), 1) for c in ref if c in graded}
    text = json.dumps(report, indent=1)
    if args.report:
        with open(args.report, "w") as f:
            f.write(text)
    print(text)


if __name__ == "__main__":
    main()
