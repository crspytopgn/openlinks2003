"""Grows the clothing masks of the Rocketbox people already in the look
pack out to the edges of each piece of cloth (rocketbox.grow_edges), so a
dyed shirt shows no pale stripe of its source colour along its seams.

    python3 tools/golfer/grow_regions.py [--pack game/assets/golfer/free_golfer_parts.olg]

New packs get this from rocketbox.py itself; this updates one built
before it. It refuses a pack it has already been run on.
"""

import argparse
import io
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from golf_shoes import load, save  # noqa: E402
from upgrade_pack import compact  # noqa: E402
from rocketbox import ROOT, grow_edges, linear  # noqa: E402


def image(info, blob, index):
    off, size = info["images"][index]["data"]
    return Image.open(io.BytesIO(bytes(blob[off:off + size])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default=os.path.join(ROOT, "game/assets/golfer/free_golfer_parts.olg"))
    args = ap.parse_args()
    info, blob = load(args.pack)
    if info.get("regions_grown"):
        sys.exit("already grown")
    for name, mat in info["materials"].items():
        if "regions" not in mat or mat.get("tint") != "person":
            continue
        mask = np.asarray(image(info, blob, mat["regions"]).convert("RGB")) > 127
        tex = linear(np.asarray(image(info, blob, mat["texture"]).convert("RGB").resize(mask.shape[1::-1], Image.BILINEAR)) / 255.0)
        grown = grow_edges(mask, tex)
        img = Image.fromarray((grown * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
        buf = io.BytesIO()
        img.save(buf, "PNG", optimize=True)
        data = buf.getvalue()
        while len(blob) % 4:
            blob.append(0)
        info["images"][mat["regions"]]["data"] = [len(blob), len(data)]
        blob.extend(data)
        print("%s: %d texels added" % (name, int(grown.sum() - mask.sum())))
    info["regions_grown"] = True
    save(args.pack, info, compact(info, blob))


if __name__ == "__main__":
    main()
