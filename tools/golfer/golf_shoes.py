"""Repaints the free golfer's shoes as golf shoes, in the look pack.

    python3 tools/golfer/golf_shoes.py [--pack game/assets/golfer/free_golfer_parts.olg] [--preview out.png]

The MakeHuman shoes the pack is built with (shoes05, CC0) are running
shoes: a perforated mesh upper with dark chevrons and a green tread. Golf
shoes have a smooth leather upper and a plain rubber sole, so the upper is
smoothed to leather (the perforations and chevrons blurred out and lifted
to white, with a faint grain), the edge of the upper kept as a light grey
welt, and the tread made dark grey rubber. The player creator's shoe
colour still tints it (white, black or brown leather).

On top of that, the shoe's own geometry (each texel's place on the shoe,
found by drawing the mesh's triangles into the texture) paints the parts
that make a golf shoe read as one from a distance: a white sole with a
dark outsole and a stitched welt, a darker saddle across the instep, a
toe cap seam and a heel counter.

The original texture's bytes are kept in the pack (the material's
"golf_source"), so running it again repaints from the original.
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


# Shoe zones, metres above the sole and fractions of the length from the
# toe (0) to the heel (1).
SOLE_TOP = 0.024
OUTSOLE_TOP = 0.007
WELT = 0.0035
SADDLE = (0.42, 0.66)
SADDLE_TOP = 0.09
TOE_CAP = 0.17
HEEL_COUNTER = 0.82


def shoe_places(info, blob, size):
    """Each texel's position on the right shoe (rest frame), and a mask."""
    e = info["parts"]["Shoes"]
    span = lambda s: bytes(blob[s[0]:s[0] + s[1]])  # noqa: E731
    pos = np.frombuffer(span(e["positions"]), np.float32).reshape(-1, 3)
    uv = np.frombuffer(span(e["uvs"]), np.float32).reshape(-1, 2)
    idx = np.frombuffer(span(e["indices"]), np.int32).reshape(-1, 3)
    out = np.zeros((size, size, 3), np.float32)
    got = np.zeros((size, size), bool)
    for tri in idx:
        p = pos[tri]
        if p[:, 0].mean() < 0:
            continue  # both shoes share the texture
        q = uv[tri] * size
        x0, y0 = np.maximum(np.floor(q.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(q.max(0)).astype(int), size)
        xs, ys = np.meshgrid(np.arange(x0, x1), np.arange(y0, y1))
        pts = np.stack([xs + 0.5, ys + 0.5], -1).reshape(-1, 2)
        a, b, c = q
        v0, v1 = b - a, c - a
        d = v0[0] * v1[1] - v0[1] * v1[0]
        if abs(d) < 1e-9 or len(pts) == 0:
            continue
        w1 = ((pts[:, 0] - a[0]) * v1[1] - (pts[:, 1] - a[1]) * v1[0]) / d
        w2 = (v0[0] * (pts[:, 1] - a[1]) - v0[1] * (pts[:, 0] - a[0])) / d
        inside = (w1 >= -0.02) & (w2 >= -0.02) & (w1 + w2 <= 1.04)
        place = (1 - w1 - w2)[inside, None] * p[0] + w1[inside, None] * p[1] + w2[inside, None] * p[2]
        py, px = pts[inside, 1].astype(int), pts[inside, 0].astype(int)
        out[py, px] = place
        got[py, px] = True
    return out, got, pos[:, 1].min(), pos[:, 2].min(), pos[:, 2].max()


def golf_parts(out, places, got, bottom, toe, heel):
    """Paints the sole, welt, saddle, toe cap seam and heel counter."""
    h = places[..., 1] - bottom
    t = (places[..., 2] - toe) / (heel - toe)
    upper = got & (h >= SOLE_TOP)

    def band(x, centre, half):
        return np.abs(x - centre) < half

    shade = out[..., 0].copy()
    sole = got & (h < SOLE_TOP)
    shade[sole] = 0.86
    shade[got & (h < OUTSOLE_TOP)] = 0.22
    shade[got & band(h, SOLE_TOP, WELT / 2)] = 0.4
    saddle = upper & (t > SADDLE[0]) & (t < SADDLE[1]) & (h < SADDLE_TOP)
    shade[saddle] = 0.3 + 0.1 * shade[saddle]
    length = heel - toe
    for edge in SADDLE:
        shade[upper & (h < SADDLE_TOP) & band(t, edge, 0.0025 / length)] = 0.18
    shade[upper & band(t, TOE_CAP, 0.002 / length)] *= 0.6
    counter = upper & (t > HEEL_COUNTER)
    shade[counter] *= 0.82
    out[got] = shade[got, None]
    return out


def repaint(img, geometry=None):
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
    if geometry is not None:
        places, got, bottom, toe, heel = geometry
        out = golf_parts(out, places, got & ~tread & ~swatch, bottom, toe, heel)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--pack", default="game/assets/golfer/free_golfer_parts.olg")
    ap.add_argument("--preview")
    args = ap.parse_args()
    info, blob = load(args.pack)
    mat = info["materials"]["Shoes"]
    entry = info["images"][mat["texture"]]
    off, n = mat.get("golf_source", entry["data"])
    src = Image.open(io.BytesIO(bytes(blob[off:off + n])))
    img = repaint(src, shoe_places(info, blob, src.size[0]))
    if args.preview:
        img.save(args.preview)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=88)
    jpg = buf.getvalue()
    old_off, old_n = entry["data"]
    if mat.get("golf") and old_off + old_n == len(blob):
        del blob[old_off:]  # the last repaint, at the end: replace it
    while len(blob) % 4:
        blob.append(0)
    # Same image index; the original's bytes stay as the source.
    mat["golf_source"] = [off, n]
    entry.update(kind="jpg", data=[len(blob), len(jpg)])
    blob.extend(jpg)
    mat["roughness"] = 0.5
    mat["golf"] = True
    save(args.pack, info, blob)
    print(f"golf shoes: image {mat['texture']}, {len(jpg)} bytes")


if __name__ == "__main__":
    main()
