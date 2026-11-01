"""Turns the free golfer's jeans into tailored golf trousers, in the look
pack.

    python3 tools/golfer/tailored.py [--pack game/assets/golfer/free_golfer_parts.olg] [--preview out.png]

The MakeHuman outfits the pack is built from have denim jeans: a streaky
washed weave, faded thighs and dark outlined seams, which read as jeans in
any colour. Tour players wear flat-front trousers in a smooth stretch
fabric. This keeps the clothes' layout, folds (their normal maps are left
alone) and the faint lines of the seams, pockets and belt loops, but
flattens the denim's streaks and wash to an even, slightly mottled cloth.
The same pass calms the shirts' knit, which had the same heavy wash.
The player's trouser and shirt colours still tint it.

Running it again is refused ("tailored" in the pack); check the pack out
again first.
"""

import argparse
import io
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import golf_shoes  # noqa: E402
from cap import span  # noqa: E402


def flatten(img):
    a = np.asarray(img.convert("L"), np.float32) / 255.0
    pil = Image.fromarray((a * 255).astype(np.uint8))
    # The garment islands against the flat grey background.
    bg = float(np.median(a[:8, :8]))
    smooth = np.asarray(pil.filter(ImageFilter.MedianFilter(5)), np.float32) / 255.0
    cloth = np.abs(smooth - bg) > 0.02
    cloth = np.asarray(Image.fromarray((cloth * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7)),
                       np.float32) > 127
    base = np.asarray(pil.filter(ImageFilter.MedianFilter(9)).filter(ImageFilter.GaussianBlur(6)), np.float32) / 255.0
    fine = a - np.asarray(pil.filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255.0
    seams = np.asarray(pil.filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255.0 - base
    mean = float(a[cloth].mean()) if cloth.any() else 0.9
    rng = np.random.default_rng(7)
    mottle = np.asarray(Image.fromarray((rng.random(a.shape) * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(3)), np.float32) / 255.0 - 0.5
    out = 0.92 + (base - mean) * 0.25 + np.clip(seams, -0.25, 0.0) * 0.35 + fine * 0.08 + mottle * 0.03
    res = np.where(cloth, np.clip(out, 0, 1), a)
    return Image.fromarray((res * 255).astype(np.uint8)).convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default="game/assets/golfer/free_golfer_parts.olg")
    ap.add_argument("--preview", default="")
    args = ap.parse_args()
    info, blob = golf_shoes.load(args.pack)
    if info.get("tailored"):
        raise SystemExit("the pack's clothes are already tailored; check it out again first")
    textures = sorted({int(info["materials"][m]["texture"]) for m in info["materials"]
                       if m.startswith(("Top_", "Bottom_"))})
    for i in textures:
        entry = info["images"][i]
        img = Image.open(io.BytesIO(bytes(span(blob, entry["data"], np.uint8))))
        out = flatten(img)
        if args.preview and i == textures[0]:
            out.save(args.preview)
        b = io.BytesIO()
        out.save(b, "JPEG", quality=90, optimize=True)
        data = b.getvalue()
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(data)
        entry["kind"] = "jpg"
        entry["data"] = [off, len(data)]
        print(f"image {i}: {len(data)} bytes")
    info["tailored"] = True
    golf_shoes.save(args.pack, info, blob)
    print(f"pack {os.path.getsize(args.pack)} bytes")


if __name__ == "__main__":
    main()
