"""Repaints the free golfer's shoes as golf shoes, in the look pack.

    python3 tools/golfer/golf_shoes.py [--pack game/assets/golfer/free_golfer_parts.olg] [--preview out.png]

The MakeHuman shoes the pack is built with (shoes05, CC0) are running
shoes: a perforated mesh upper with dark chevrons and a green tread. Golf
shoes have a smooth leather upper and a plain rubber sole, so the upper is
smoothed to leather (the perforations and chevrons blurred out and lifted
to white, with a faint grain), the edge of the upper kept as a light grey
welt, and the tread made dark grey rubber. The player creator's shoe
colour still tints it (white, black or brown leather).

Runs once on a pack: the shoe material is marked "golf": true.
"""

import argparse
import gzip
import io
import json
import struct

import numpy as np
from PIL import Image, ImageFilter

VERSION = 2


def load(path):
    raw = open(path, "rb").read()
    assert raw[:4] == b"OLGL" and struct.unpack("<I", raw[4:8])[0] == VERSION
    data = gzip.decompress(raw[12:])
    head = struct.unpack("<I", data[:4])[0]
    return json.loads(data[4:4 + head]), bytearray(data[4 + head:])


def save(path, info, blob):
    head = json.dumps(info, separators=(",", ":")).encode()
    data = struct.pack("<I", len(head)) + head + bytes(blob)
    with open(path, "wb") as f:
        f.write(b"OLGL" + struct.pack("<II", VERSION, len(data)))
        f.write(gzip.compress(data, 9, mtime=0))


def repaint(img):
    a = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    h, w, _ = a.shape
    luma = a @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    ys, xs = np.mgrid[0:h, 0:w] / np.array([h, w], dtype=np.float32)[:, None, None]
    # The texture's islands: the tread along the top, a cloth swatch in
    # the bottom right corner, the black background, and the upper.
    tread = ((xs - 0.63) / 0.37) ** 2 + ((ys - 0.13) / 0.13) ** 2 < 1.0
    swatch = (ys > 0.84) & (xs > 0.75)
    # The background is black with JPEG noise; the islands' own darkest
    # parts are dark grey, so a smoothed threshold separates them.
    smooth = np.asarray(Image.fromarray((luma * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(7)),
                        dtype=np.float32) / 255.0
    shoe = smooth > 0.07
    upper = shoe & ~tread & ~swatch
    # Leather: the upper's shading kept at a coarse scale, perforations and
    # chevrons gone.
    soft = np.asarray(Image.fromarray((luma * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(9)),
                      dtype=np.float32) / 255.0
    shade = np.clip(soft / max(1e-3, float(np.percentile(soft[upper], 90))), 0.0, 1.0)
    rng = np.random.default_rng(2003)
    grain = np.asarray(Image.fromarray((rng.random((h, w)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)),
                       dtype=np.float32) / 255.0
    # Panel seams and the laces kept: the band between the perforations'
    # size and the panels', after the dark detail is filled.
    # A closing first fills the dark perforations and chevrons.
    closed = Image.fromarray((luma * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(15)).filter(
        ImageFilter.MinFilter(15))

    def blur(r):
        return np.asarray(closed.filter(ImageFilter.GaussianBlur(r)), dtype=np.float32) / 255.0
    seams = blur(2.5) - blur(10)
    leather = np.clip(0.56 + 0.3 * shade + 1.2 * seams + 0.05 * (grain - 0.5), 0.0, 0.9)
    # A light grey welt round the edge of the upper.
    m = Image.fromarray((upper * 255).astype(np.uint8))
    inner = np.asarray(m.filter(ImageFilter.MinFilter(17)), dtype=np.uint8) > 127
    welt = upper & ~inner
    out = a.copy()
    out[upper] = leather[upper, None]
    out[welt] = (0.42 + 0.12 * shade[welt])[:, None]
    # Dark grey rubber tread, keeping its pattern.
    out[tread & shoe] = (0.08 + 0.25 * luma[tread & shoe])[:, None]
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--pack", default="game/assets/golfer/free_golfer_parts.olg")
    ap.add_argument("--preview")
    args = ap.parse_args()
    info, blob = load(args.pack)
    mat = info["materials"]["Shoes"]
    if mat.get("golf"):
        print("already golf shoes")
        return
    entry = info["images"][mat["texture"]]
    off, n = entry["data"]
    img = repaint(Image.open(io.BytesIO(bytes(blob[off:off + n]))))
    if args.preview:
        img.save(args.preview)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=88)
    jpg = buf.getvalue()
    while len(blob) % 4:
        blob.append(0)
    # Same image index; the old bytes stay behind unreferenced (47 KB).
    entry.update(kind="jpg", data=[len(blob), len(jpg)])
    blob.extend(jpg)
    mat["roughness"] = 0.5
    mat["golf"] = True
    save(args.pack, info, blob)
    print(f"golf shoes: image {mat['texture']}, {len(jpg)} bytes")


if __name__ == "__main__":
    main()
