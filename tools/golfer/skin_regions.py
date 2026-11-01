"""Adds a map of the face's regions to the free golfer's look pack, so the
skin shader (game/scripts/assets/golfer_surface.gd) can colour a face the
way real skin varies instead of tinting it one flat colour.

    python3 tools/golfer/skin_regions.py [--pack game/assets/golfer/free_golfer_parts.olg] [--preview out.png]

Channels of the map (in the body's UV layout, 512 px):
- R, flush: where blood shows through: the cheeks, the nose, the ears and
  the knuckles are redder than the forehead and jaw.
- G, beard: the jaw, chin, upper lip and lower cheeks, where stubble and
  a shaved man's blue-grey shadow sit (PlayerLook.stubble).
- B, lips: a deeper, redder colour, and a little sheen.
- A, shine: the T-zone (forehead, the bridge and tip of the nose, the chin)
  is oilier, so it catches the sun more.

Each region is placed from the face landmarks the pack already carries
(face_fit, the points photos are fitted to), on the front of the head, and
drawn into the texture through the mesh's own triangles. The material
"Skin" records the image as "regions". It refuses a pack that has it
already ("skin_regions").
"""

import argparse
import io
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import golf_shoes  # noqa: E402
from cap import part_arrays, span  # noqa: E402

SIZE = 512


def smooth_step(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def gauss(x, y, cx, cy, sx, sy):
    return np.exp(-(((x - cx) / sx) ** 2 + ((y - cy) / sy) ** 2) / 2)


def regions(info, blob):
    """Per-vertex RGBA weights for the Body part."""
    pos, bones, weights = part_arrays(info, blob, "Body")
    e = info["parts"]["Body"]
    nrm = span(blob, e["normals"], np.float16).reshape(-1, 3).astype(np.float32)
    ff = info["face_fit"]
    pts = dict(zip(ff["points"], (np.array(p) for p in ff["base"])))
    eyes, _, _ = part_arrays(info, blob, "Eyes")
    eye_y = float((eyes[:, 1].min() + eyes[:, 1].max()) / 2)
    head = (pos[:, 1] > 1.45)
    near = head & (np.abs(pos[:, 0]) < 0.004)
    nose = pos[near][np.argmin(pos[near][:, 2])]
    # face_fit's frame to the rig's: scale and lift, matched at the eyes
    # and the tip of the nose.
    ff_eye = (pts["l_eye_outer"][1] + pts["l_eye_inner"][1]) / 2
    s = (eye_y - nose[1]) / (ff_eye - pts["nose_tip"][1])
    X = np.abs(pos[:, 0]) / s
    Y = (pos[:, 1] - nose[1]) / s + pts["nose_tip"][1]
    front = smooth_step(0.05, 0.35, -nrm[:, 2]) * head
    out = np.zeros((len(pos), 4), np.float32)

    lip_y = (pts["upper_lip"][1] + pts["lower_lip"][1]) / 2
    lip_w = pts["l_mouth"][0] + 0.002
    lip_h = (pts["upper_lip"][1] - pts["lower_lip"][1]) / 2 + 0.0035
    lips = 1 - smooth_step(0.75, 1.15, np.sqrt((X / lip_w) ** 2 + ((Y - lip_y) / lip_h) ** 2))
    lips *= front

    # Beard: under a line from below the nose out to the sideburn, above
    # the neck, inside the ears; not on the lips.
    wing = pts["l_nose_wing"]
    cheek = pts["l_cheek"]
    jaw_low = pts["l_jaw_low"]
    # The cheek line runs from beside the nose down and out, then up the
    # sideburn in front of the ear.
    cheek_line = wing[1] - 0.008 + (X - wing[0]) * 0.1
    sideburn = smooth_step(cheek[0] - 0.012, cheek[0], X) * 0.03
    top = np.where(X < wing[0], wing[1] - 0.004, cheek_line + sideburn)
    beard = smooth_step(0.0, 0.006, top - Y)
    beard *= 1 - smooth_step(cheek[0] - 0.004, cheek[0] + 0.006, X)
    # Down under the jaw onto the throat, fading out.
    beard *= smooth_step(pts["chin"][1] - 0.045, pts["chin"][1] - 0.02, Y)
    # Clear round the mouth's corners a touch less than the lips.
    beard *= 1 - 0.8 * lips
    beard *= head * smooth_step(-0.1, 0.25, -nrm[:, 2] + 0.25 * (Y < jaw_low[1]))

    flush = 0.12 * front
    flush += 0.75 * gauss(X, Y, cheek[0] * 0.68, pts["nose_tip"][1] + 0.005, 0.014, 0.012) * front
    flush += 0.7 * gauss(X, Y, 0.0, pts["nose_tip"][1], 0.009, 0.008) * front
    flush += 0.35 * gauss(X, Y, 0.0, pts["chin"][1] + 0.006, 0.012, 0.008) * front
    ears = head & (X > cheek[0] + 0.004) & (Y > pts["l_jaw"][1]) & (Y < pts["l_brow"][1] + 0.01)
    flush[ears] = np.maximum(flush[ears], 0.6)
    hand_bones = [i for i, n in enumerate(info["bones"]) if n.startswith(("hand_", "index_", "middle_", "ring_",
                                                                          "pinky_", "thumb_"))]
    hand = np.isin(bones, hand_bones) & (weights > 0.4)
    flush[hand.any(axis=1)] = 0.4
    flush = np.clip(flush, 0, 1)

    shine = 0.8 * gauss(X, Y, 0.0, pts["l_brow"][1] + 0.022, 0.03, 0.013)
    shine += 0.9 * gauss(X, Y, 0.0, (pts["nose_tip"][1] + ff_eye) / 2, 0.006, 0.02)
    shine += 0.5 * gauss(X, Y, 0.0, pts["chin"][1] + 0.006, 0.011, 0.008)
    shine = np.clip(shine * front, 0, 1)
    out[:, 0], out[:, 1], out[:, 2], out[:, 3] = flush, np.clip(beard, 0, 1), np.clip(lips, 0, 1), shine
    return out


def draw(info, blob, values, part="Body"):
    """Draws per-vertex values into the UV layout (with a dilated border)."""
    e = info["parts"][part]
    uv = span(blob, e["uvs"], np.float32).reshape(-1, 2)
    idx = span(blob, e["indices"], np.int32).reshape(-1, 3)
    img = np.zeros((SIZE, SIZE, values.shape[1]), np.float32)
    got = np.zeros((SIZE, SIZE), bool)
    for tri in idx:
        q = uv[tri] * SIZE
        x0, y0 = np.maximum(np.floor(q.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(q.max(0)).astype(int) + 1, SIZE)
        if x1 <= x0 or y1 <= y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1), np.arange(y0, y1))
        p = np.stack([xs + 0.5, ys + 0.5], -1).reshape(-1, 2)
        a, b, c = q
        v0, v1 = b - a, c - a
        d = v0[0] * v1[1] - v0[1] * v1[0]
        if abs(d) < 1e-12:
            continue
        w1 = ((p[:, 0] - a[0]) * v1[1] - (p[:, 1] - a[1]) * v1[0]) / d
        w2 = (v0[0] * (p[:, 1] - a[1]) - v0[1] * (p[:, 0] - a[0])) / d
        inside = (w1 >= -0.05) & (w2 >= -0.05) & (w1 + w2 <= 1.1)
        w0 = 1 - w1 - w2
        val = w0[inside, None] * values[tri[0]] + w1[inside, None] * values[tri[1]] + w2[inside, None] * values[tri[2]]
        py, px = p[inside, 1].astype(int), p[inside, 0].astype(int)
        img[py, px] = val
        got[py, px] = True
    # Grow the islands a few pixels so mipmaps and filtering don't pull in
    # the empty background.
    for _ in range(4):
        acc = np.zeros_like(img)
        cnt = np.zeros((SIZE, SIZE), np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            acc += np.roll(np.roll(img * got[..., None], dy, 0), dx, 1)
            cnt += np.roll(np.roll(got.astype(np.float32), dy, 0), dx, 1)
        grow = ~got & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow, None]
        got |= grow
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default="game/assets/golfer/free_golfer_parts.olg")
    ap.add_argument("--preview", default="")
    args = ap.parse_args()
    info, blob = golf_shoes.load(args.pack)
    if "skin_regions" in info:
        raise SystemExit("the pack already has its skin regions; rebuild it or check it out again first")
    vals = regions(info, blob)
    img = draw(info, blob, vals)
    pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(0.6))
    if args.preview:
        pil.save(args.preview)
    b = io.BytesIO()
    pil.save(b, "PNG", optimize=True)
    data = np.frombuffer(b.getvalue(), np.uint8)
    while len(blob) % 4:
        blob.append(0)
    off = len(blob)
    blob.extend(data.tobytes())
    info["images"].append({"kind": "png", "data": [off, len(data)]})
    info["materials"]["Skin"]["regions"] = len(info["images"]) - 1
    info["skin_regions"] = len(info["images"]) - 1
    golf_shoes.save(args.pack, info, blob)
    print(f"skin regions: image {len(info['images']) - 1}, {len(data)} bytes; pack {os.path.getsize(args.pack)} bytes")


if __name__ == "__main__":
    main()
