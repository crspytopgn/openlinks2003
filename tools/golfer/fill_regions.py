"""Fills the holes in the realistic people's clothing masks, in the look pack.

    python3 tools/golfer/fill_regions.py [--pack game/assets/golfer/free_golfer_parts.olg] [--preview out.png]

Each Rocketbox person's body texture has a regions map (R shirt, G
trousers, B shoes) that says where golfer_person.gdshader dyes the clothes
the look's colours. rocketbox.py builds it from each texel's colour, and
it left holes inside the garments: faded patches on jeans, deep creases,
dark prints. There the source clothes' own colour showed through, so
khaki or white trousers carried pale blue denim blotches, which glowed in
the sun. rocketbox.py now fills them as it builds (fill_holes); this
applies the same fill to a pack built before that, without the sources.
Running it again changes nothing.
"""

import argparse
import io
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from golf_shoes import load, save  # noqa: E402
from rocketbox import MASK_SIZE, fill_holes, linear  # noqa: E402


def image(info, blob, index):
    off, size = info["images"][index]["data"]
    return Image.open(io.BytesIO(bytes(blob[off:off + size])))


def put_png(info, blob, index, img):
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    while len(blob) % 4:
        blob.append(0)
    info["images"][index] = {"kind": "png", "data": [len(blob), len(buf.getvalue())]}
    blob.extend(buf.getvalue())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default=os.path.join(os.path.dirname(__file__), "../../game/assets/golfer/free_golfer_parts.olg"))
    ap.add_argument("--preview", help="a sheet of each mask before and after")
    args = ap.parse_args()
    info, blob = load(args.pack)
    sheets = []
    changed = 0
    for name, who in info.get("people", {}).items():
        mats = {info["parts"][p]["material"] for p in who["parts"] if p in info["parts"]}
        body = [m for m in mats if m.endswith("_body") and int(info["materials"][m].get("regions", -1)) >= 0]
        head = [m for m in mats if m.endswith("_head")]
        if not body or not head:
            continue
        m = info["materials"][body[0]]
        size = (MASK_SIZE, MASK_SIZE)
        tex = linear(np.asarray(image(info, blob, int(m["texture"])).convert("RGB").resize(size, Image.BILINEAR)) / 255.0)
        face = linear(np.asarray(image(info, blob, int(info["materials"][head[0]]["texture"])).convert("RGB").resize((512, 512))) / 255.0)
        skin = np.median(face[200:300, 200:310].reshape(-1, 3), axis=0)  # as rocketbox.py: cheeks and nose
        old = image(info, blob, int(m["regions"])).convert("RGB")
        mask = np.asarray(old.resize(size, Image.BILINEAR)) > 127
        # rocketbox.py's skin test, on the texture as the pack holds it.
        lum = tex @ np.array([0.2126, 0.7152, 0.0722])
        chroma = tex / np.maximum(tex.sum(-1, keepdims=True), 1e-6)
        sk = skin / max(skin.sum(), 1e-6)
        is_skin = (np.linalg.norm(chroma - sk, axis=-1) < 0.05) & (np.abs(lum - skin @ [0.2126, 0.7152, 0.0722]) < 0.2)
        is_skin &= ~mask[..., 2]
        filled = fill_holes(mask, is_skin)
        added = int((filled > 0.5).sum() - mask.sum())
        print("%s: %d texels filled" % (name, added))
        if added == 0:
            continue
        new = Image.fromarray((filled * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
        # Keep the old soft edges where nothing was filled.
        new = Image.fromarray(np.maximum(np.asarray(new), np.asarray(old.resize(size))))
        put_png(info, blob, int(m["regions"]), new)
        changed += 1
        sheets.append((old.resize(size), new))
    if changed:
        save(args.pack, info, blob)
    if args.preview and sheets:
        w = Image.new("RGB", (2 * MASK_SIZE, MASK_SIZE * len(sheets)))
        for i, (a, b) in enumerate(sheets):
            w.paste(a, (0, i * MASK_SIZE))
            w.paste(b, (MASK_SIZE, i * MASK_SIZE))
        w.save(args.preview)


if __name__ == "__main__":
    main()
