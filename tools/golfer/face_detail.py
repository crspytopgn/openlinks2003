"""Gives the free golfer's face the fine detail of a real scanned face:
pores, fine lines, creases round the eyes, nose and mouth, and the uneven
colour of real skin, at three times the resolution of the body texture.

    python3 tools/golfer/face_detail.py --scan DIR [--pack game/assets/golfer/free_golfer_parts.olg] [--preview out.png]

DIR holds the Infinite Realities "Lee Perry-Smith" head scan as three.js
ships it (LeePerrySmith.glb, Map-COL.jpg, Infinite-Level_02_Tangent_SmoothUV.jpg;
CC BY 3.0, see docs/credits.md), fetched with --fetch.

The scan's detail is moved across in 3D, not by its texture layout:
- its face is fitted to ours by thirteen landmarks (eye corners, brows, nose
  tip and wings, mouth corners, lips, chin): a similarity, then a thin-plate
  spline so the features line up;
- every texel of a new texture over our face's part of the body layout is
  traced to the nearest point of the scan's surface;
- only the scan's detail comes across: its colour over a blur of itself
  (no face colour, beard, brows or lip colour: our own skin, regions and
  stubble shader keep those) and its normal map less a blur of itself, in
  our face's tangent frame.

The pack gets two images (materials.Skin.face_detail: {albedo, normal, rect},
the rect in body uvs), and the Body part gets tangents (the skin's normal maps had none
to work in). It refuses a pack that has them already.
"""

import argparse
import io
import os
import sys
import urllib.request

import numpy as np
from PIL import Image
from scipy.interpolate import RBFInterpolator
from scipy.ndimage import distance_transform_edt, gaussian_filter

sys.path.insert(0, os.path.dirname(__file__))
import glb_edit  # noqa: E402
import golf_shoes  # noqa: E402
import look_pack  # noqa: E402
from cap import part_arrays, span  # noqa: E402
from skin_regions import regions  # noqa: E402

SCAN_URL = "https://raw.githubusercontent.com/mrdoob/three.js/r160/examples/models/gltf/LeePerrySmith/"
SCAN_FILES = ("LeePerrySmith.glb", "Map-COL.jpg", "Infinite-Level_02_Tangent_SmoothUV.jpg")
SIZE = 1024
# Detail kept: finer than this (scan texture pixels, 1024 across his
# head, about 0.7 mm each): creases and folds as well as pores.
ALBEDO_BLUR = 18
NORMAL_BLUR = 26
# Both are faint on his maps; kept this much stronger (the skin shader's
# strengths of 1 give this).
ALBEDO_GAIN = 2.5
NORMAL_GAIN = 5.0
# The spline's pins on the rest of the head: this far from the landmarks.
ANCHOR_GAP = 0.03
# The scan's landmarks, as pixels of his 1024 colour map, paired with ours
# (face_fit's names; the left of his map is his left once turned to face
# -z like ours). Picked by eye on the map.
SCAN_MARKS = {
    "l_eye_outer": (408, 300), "l_eye_inner": (490, 307), "r_eye_inner": (532, 307), "r_eye_outer": (615, 300),
    "l_brow": (440, 262), "r_brow": (585, 262), "l_nose_wing": (480, 405), "r_nose_wing": (542, 405),
    "l_mouth": (455, 477), "r_mouth": (567, 477), "upper_lip": (511, 462), "lower_lip": (511, 492),
    "chin": (511, 595),
}
# Parts of his map left out of the colour detail (how much is kept): his
# painted brows, shut eyes, the shine on his nose and his lips, and his
# stubble, which would print on every golfer.
SCAN_SKIP = [(((380, 235), (650, 285)), 0.15), (((400, 285), (630, 325)), 0.15), (((470, 300), (555, 400)), 0.3),
             (((440, 455), (585, 500)), 0.15), (((320, 420), (700, 760)), 0.12)]


def fetch(scan):
    os.makedirs(scan, exist_ok=True)
    for f in SCAN_FILES:
        path = os.path.join(scan, f)
        if not os.path.exists(path):
            urllib.request.urlretrieve(SCAN_URL + f, path)


def load_scan(scan):
    g = glb_edit.Glb(os.path.join(scan, SCAN_FILES[0]))
    prim = g.doc["meshes"][0]["primitives"][0]
    pos = g.read(prim["attributes"]["POSITION"]).astype(np.float64)
    uv = g.read(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
    tris = g.read(prim["indices"]).reshape(-1, 3).astype(np.int64)
    # He faces +z; ours faces -z.
    pos[:, 0] *= -1
    pos[:, 2] *= -1
    # Only his skin: not the eyeballs (the discs in the map's top corners)
    # or the flaps at its foot.
    c = uv[tris].mean(axis=1)
    tris = tris[(c[:, 1] > 0.1) & ~((c[:, 1] > 0.88) & ((c[:, 0] < 0.1) | (c[:, 0] > 0.9)))]
    col = np.asarray(Image.open(os.path.join(scan, SCAN_FILES[1])).convert("RGB"), np.float64) / 255
    nrm = np.asarray(Image.open(os.path.join(scan, SCAN_FILES[2])).convert("RGB"), np.float64) / 255
    return pos, uv, tris, col, nrm


def scan_point(pos, uv, tris, px, py, n=1024):
    """The scan's surface point at a pixel of his maps (rows from the top)."""
    q = np.array([px / n, 1 - py / n])
    a, b, c = uv[tris[:, 0]], uv[tris[:, 1]], uv[tris[:, 2]]
    v0, v1, v2 = b - a, c - a, q - a
    d = v0[:, 0] * v1[:, 1] - v0[:, 1] * v1[:, 0]
    d = np.where(np.abs(d) < 1e-15, 1e-15, d)
    w1 = (v2[:, 0] * v1[:, 1] - v2[:, 1] * v1[:, 0]) / d
    w2 = (v0[:, 0] * v2[:, 1] - v0[:, 1] * v2[:, 0]) / d
    inside = (w1 >= -1e-6) & (w2 >= -1e-6) & (w1 + w2 <= 1 + 1e-6)
    k = int(np.nonzero(inside)[0][0])
    t = tris[k]
    return pos[t[0]] * (1 - w1[k] - w2[k]) + pos[t[1]] * w1[k] + pos[t[2]] * w2[k]


def our_marks(info, blob, pos, nrm):
    """face_fit's landmarks on our rest head, in the rig."""
    ff = info["face_fit"]
    pts = dict(zip(ff["points"], (np.array(p) for p in ff["base"])))
    eyes, _, _ = part_arrays(info, blob, "Eyes")
    eye_y = float((eyes[:, 1].min() + eyes[:, 1].max()) / 2)
    head = pos[:, 1] > 1.45
    near = head & (np.abs(pos[:, 0]) < 0.004)
    nose = pos[near][np.argmin(pos[near][:, 2])]
    ff_eye = (pts["l_eye_outer"][1] + pts["l_eye_inner"][1]) / 2
    s = (eye_y - nose[1]) / (ff_eye - pts["nose_tip"][1])
    front = head & (nrm[:, 2] < -0.2)
    fp = pos[front]
    out = {"nose_tip": nose}
    for name in SCAN_MARKS:
        x, y = pts[name][0] * s, (pts[name][1] - pts["nose_tip"][1]) * s + nose[1]
        d = np.hypot(fp[:, 0] - x, fp[:, 1] - y)
        close = d < max(0.004, d.min() * 1.5)
        z = fp[close][:, 2].min()
        out[name] = np.array([x, y, z])
    return out


def similarity(src, dst):
    """Scale, rotation and offset taking src points onto dst (Umeyama)."""
    ms, md = src.mean(0), dst.mean(0)
    a, b = src - ms, dst - md
    u, sv, vt = np.linalg.svd(b.T @ a / len(src))
    d = np.eye(3)
    if np.linalg.det(u @ vt) < 0:
        d[2, 2] = -1
    r = u @ d @ vt
    scale = np.trace(np.diag(sv) @ d) / (a ** 2).sum(1).mean()
    return scale, r, md - scale * r @ ms


def blur(img, radius):
    return gaussian_filter(img, (radius, radius, 0), mode="nearest")


def sample(img, uv):
    """Bilinear samples of an image at glTF uvs (v up from the bottom row)."""
    h, w = img.shape[:2]
    x = np.clip(uv[:, 0] * w - 0.5, 0, w - 1.001)
    y = np.clip((1 - uv[:, 1]) * h - 0.5, 0, h - 1.001)
    x0, y0 = x.astype(int), y.astype(int)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy) + img[y0 + 1, x0] * (1 - fx) * fy
            + img[y0 + 1, x0 + 1] * fx * fy)


def scan_surface(pos, uv, tris, per_tri=24):
    """Dense points over the scan's surface: position, uv, and the frame of
    his tangent-space normal map at each."""
    rng = np.random.default_rng(1)
    p0, p1, p2 = (pos[tris[:, k]] for k in range(3))
    t0, t1, t2 = (uv[tris[:, k]] for k in range(3))
    e1, e2 = p1 - p0, p2 - p0
    d1, d2 = t1 - t0, t2 - t0
    r = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
    r = np.where(np.abs(r) < 1e-15, 1e-15, r)
    tan = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) / r[:, None]
    bit = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) / r[:, None]
    n = np.cross(e1, e2)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-15)
    tan -= n * (tan * n).sum(1, keepdims=True)
    tan /= np.maximum(np.linalg.norm(tan, axis=1, keepdims=True), 1e-15)
    bit -= n * (bit * n).sum(1, keepdims=True) + tan * (bit * tan).sum(1, keepdims=True)
    bit /= np.maximum(np.linalg.norm(bit, axis=1, keepdims=True), 1e-15)
    a = rng.random((len(tris), per_tri, 2))
    flip = a.sum(2) > 1
    a[flip] = 1 - a[flip]
    w1, w2 = a[..., 0:1], a[..., 1:2]
    pts = p0[:, None] + e1[:, None] * w1 + e2[:, None] * w2
    uvs = t0[:, None] + d1[:, None] * w1 + d2[:, None] * w2
    rep = lambda x: np.repeat(x, per_tri, axis=0)  # noqa: E731
    return pts.reshape(-1, 3), uvs.reshape(-1, 2), rep(tan), rep(bit), rep(n)


def spread(points, marks, gap):
    """Points of `points` at least `gap` from the landmarks and each other."""
    d = np.linalg.norm(points[:, None] - marks[None], axis=2).min(1)
    out = []
    for i in np.argsort(-d):
        if d[i] < gap:
            break
        if all(np.linalg.norm(points[i] - q) >= gap for q in out):
            out.append(points[i])
    return np.array(out).reshape(-1, 3)


def outermost(points, queries, bins=(2048, 1024)):
    """For each query, the surface point (index) met first going in from
    outside along the line from the middle of the head through the query:
    a lookup by direction of the outermost surface point. Robust where a
    nearest-point snap would smear (the warped face is never exactly on his)."""
    centre = np.array([np.median(points[:, 0]), np.median(points[:, 1]), np.median(points[:, 2])])

    def cell(p):
        d = p - centre
        r = np.linalg.norm(d, axis=1)
        theta = np.arctan2(d[:, 0], d[:, 2])
        phi = np.arccos(np.clip(d[:, 1] / np.maximum(r, 1e-12), -1, 1))
        i = np.clip(((theta + np.pi) / (2 * np.pi) * bins[0]).astype(int), 0, bins[0] - 1)
        j = np.clip((phi / np.pi * bins[1]).astype(int), 0, bins[1] - 1)
        return i, j, r

    i, j, r = cell(points)
    order = np.argsort(r)
    grid = np.full(bins, -1, np.int64)
    grid[i[order], j[order]] = order  # the farthest out is written last
    empty = grid < 0
    if empty.any():
        _, (fi, fj) = distance_transform_edt(empty, return_indices=True)
        grid = grid[fi, fj]
    qi, qj, _ = cell(queries)
    return grid[qi, qj]


def face_island(pos, nrm, tris, nose):
    """The front-of-head triangles of the uv island holding the nose (uv
    seams split vertices, so an island is a set of triangles joined by
    shared vertices)."""
    front = (pos[:, 1] > 1.47) & (nrm[:, 2] < 0.35) & (pos[:, 2] < -0.02)
    cand = tris[front[tris].all(axis=1)]
    start = int(np.argmin(np.linalg.norm(pos - nose, axis=1)))
    seen = {start}
    keep = np.zeros(len(cand), bool)
    while True:
        hit = ~keep & np.isin(cand, list(seen)).any(axis=1)
        if not hit.any():
            return cand[keep]
        keep |= hit
        seen.update(cand[hit].reshape(-1).tolist())


def build(info, blob, scan):
    pos, _, _ = part_arrays(info, blob, "Body")
    pos = pos.astype(np.float64)
    e = info["parts"]["Body"]
    nrm = span(blob, e["normals"], np.float16).reshape(-1, 3).astype(np.float64)
    uv = span(blob, e["uvs"], np.float32).reshape(-1, 2).astype(np.float64)
    tris = span(blob, e["indices"], np.int32).reshape(-1, 3)
    tangents = look_pack.tangents(pos, nrm, uv, tris)
    s_pos, s_uv, s_tris, s_col, s_nrm = load_scan(scan)

    ours = our_marks(info, blob, pos, nrm)
    theirs = {k: scan_point(s_pos, s_uv, s_tris, *v) for k, v in SCAN_MARKS.items()}
    theirs["nose_tip"] = s_pos[np.argmin(s_pos[:, 2])]
    names = list(SCAN_MARKS) + ["nose_tip"]
    a = np.array([ours[k] for k in names])
    b = np.array([theirs[k] for k in names])
    scale, rot, off = similarity(a, b)
    fitted = (scale * (rot @ a.T)).T + off
    # Our point -> his space: the similarity, then the spline's correction,
    # which fades to nothing on the rest of the head (anchors with none):
    # unpinned, a spline flings the forehead and temples anywhere.
    face_tris = face_island(pos, nrm, tris, ours["nose_tip"])
    anchors = spread(pos[np.unique(face_tris)], a, ANCHOR_GAP)
    warp = RBFInterpolator(np.concatenate([a, anchors]),
                           np.concatenate([b - fitted, np.zeros((len(anchors), 3))]),
                           kernel="thin_plate_spline", smoothing=1e-7)
    print(f"scan fit: scale {scale:.2f}, landmark error before the spline "
          f"{np.linalg.norm(b - fitted, axis=1).mean() / scale * 1000:.1f} mm, {len(anchors)} anchors")

    # Our face's part of the body layout: the uv island round the nose,
    # the front of the head.
    lo, hi = uv[np.unique(face_tris)].min(0), uv[np.unique(face_tris)].max(0)
    pad = (hi - lo) * 0.02
    lo, hi = np.maximum(lo - pad, 0), np.minimum(hi + pad, 1)

    # Every texel of the new texture: its point, normal and frame on our face.
    reg = regions(info, blob)
    vals = np.concatenate([pos, nrm, tangents[:, :3], tangents[:, 3:4], reg], axis=1)
    img = np.zeros((SIZE, SIZE, vals.shape[1]))
    got = np.zeros((SIZE, SIZE), bool)
    q = (uv - lo) / (hi - lo) * SIZE
    for t in face_tris:
        tq = q[t]
        x0, y0 = np.maximum(np.floor(tq.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(tq.max(0)).astype(int) + 1, SIZE)
        if x1 <= x0 or y1 <= y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1), np.arange(y0, y1))
        p = np.stack([xs + 0.5, ys + 0.5], -1).reshape(-1, 2)
        ta, tb, tc = tq
        v0, v1 = tb - ta, tc - ta
        d = v0[0] * v1[1] - v0[1] * v1[0]
        if abs(d) < 1e-12:
            continue
        w1 = ((p[:, 0] - ta[0]) * v1[1] - (p[:, 1] - ta[1]) * v1[0]) / d
        w2 = (v0[0] * (p[:, 1] - ta[1]) - v0[1] * (p[:, 0] - ta[0])) / d
        inside = (w1 >= -0.02) & (w2 >= -0.02) & (w1 + w2 <= 1.04)
        w0 = 1 - w1 - w2
        val = (w0[inside, None] * vals[t[0]] + w1[inside, None] * vals[t[1]] + w2[inside, None] * vals[t[2]])
        py, px = p[inside, 1].astype(int), p[inside, 0].astype(int)
        img[py, px] = val
        got[py, px] = True
    texels = img[got]
    P = texels[:, 0:3]
    N = texels[:, 3:6]
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
    T = texels[:, 6:9]
    T -= N * (T * N).sum(1, keepdims=True)
    T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-12)
    B = np.cross(N, T) * np.where(texels[:, 9:10] < 0, -1.0, 1.0)
    R = texels[:, 10:14]

    # Traced to his surface along the line from the middle of his head.
    Q = (scale * (rot @ P.T)).T + off + warp(P)
    sp, suv, stan, sbit, sn = scan_surface(s_pos, s_uv, s_tris)
    nearest = outermost(sp, Q)
    huv = suv[nearest]
    # Fade out where our face strays far from his (under the chin, the
    # hairline) and round our open eyes (his are shut: his lids' creases
    # would ring them).
    off_by = np.linalg.norm(Q - sp[nearest], axis=1) / scale
    fade = np.clip((0.04 - off_by) / 0.02, 0, 1)
    for side in ("l", "r"):
        eye = (ours[side + "_eye_inner"] + ours[side + "_eye_outer"]) / 2
        near_eye = np.hypot(P[:, 0] - eye[0], (P[:, 1] - eye[1]) * 1.4)
        fade *= np.clip((near_eye - 0.013) / 0.01, 0, 1) * 0.8 + 0.2
    fade = fade[:, None]

    # Colour detail: his colour over a blur of itself, mostly brightness
    # (pores, blotches) with a little of the redness; none on his brows,
    # eyelids and lips.
    ratio = s_col / np.maximum(blur(s_col, ALBEDO_BLUR), 1e-3)
    damp = np.ones(s_col.shape[:2])
    for ((x0, y0), (x1, y1)), k in SCAN_SKIP:
        damp[y0:y1, x0:x1] = k
    damp = gaussian_filter(damp, 8)[..., None]
    ratio = 1.0 + (ratio - 1.0) * damp
    ratio = np.clip(ratio, 0.6, 1.12)  # his scan's baked-in shine, not ours
    lum = ratio.mean(axis=2, keepdims=True)
    ratio = lum + (ratio - lum) * 0.5
    alb = sample(ratio, huv)
    # Not where our lips and beard are drawn (the regions map), where his
    # lip edge and stubble would print on every golfer.
    keep = 1 - np.clip(R[:, 2:3] * 1.5 + R[:, 1:2] * 0.85, 0, 1)
    alb = 1 + (alb - 1) * keep * fade

    # Normal detail: his normal map less a blur of it (the face's shape is
    # in our mesh already), from his tangent frame to ours.
    tn = s_nrm * 2 - 1
    hp = tn - blur(tn, NORMAL_BLUR)
    hp[..., :2] *= 0.3 + 0.7 * damp  # stubble and shine leave bumps too
    d = sample(hp, huv)
    world = stan[nearest] * d[:, 0:1] + sbit[nearest] * d[:, 1:2]
    world = (rot.T @ world.T).T  # his space back to ours (the similarity's turn)
    dx = (world * T).sum(1)
    dy = (world * B).sum(1)
    # Godot's normal maps point y up the image, against our v.
    dn = np.stack([dx, -dy], 1) * (1 - R[:, 2:3] * 0.6) * fade

    alb_img = np.full((SIZE, SIZE, 3), 0.5)
    nrm_img = np.full((SIZE, SIZE, 3), 0.5)
    nrm_img[..., 2] = 1.0
    alb_img[got] = np.clip((1 + (alb - 1) * ALBEDO_GAIN) * 0.5, 0, 1)
    n3 = np.concatenate([dn * NORMAL_GAIN, np.ones((len(dn), 1))], 1)
    n3 /= np.linalg.norm(n3, axis=1, keepdims=True)
    nrm_img[got] = n3 * 0.5 + 0.5
    return alb_img, nrm_img, (lo, hi), tangents


def encode(img):
    b = io.BytesIO()
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(b, "JPEG", quality=90)
    return np.frombuffer(b.getvalue(), np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default="game/assets/golfer/free_golfer_parts.olg")
    ap.add_argument("--scan", default=os.path.join(os.path.expanduser("~"), ".cache", "lee-perry-smith"))
    ap.add_argument("--preview", default="")
    args = ap.parse_args()
    fetch(args.scan)
    info, blob = golf_shoes.load(args.pack)
    if "face_detail" in info["materials"]["Skin"]:
        raise SystemExit("the pack already has its face detail; check it out again first")
    alb, nrm, (lo, hi), tangents = build(info, blob, args.scan)
    if args.preview:
        Image.fromarray((np.concatenate([alb, nrm], 1) * 255).astype(np.uint8)).save(args.preview)

    def put(a):
        a = np.ascontiguousarray(a)
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(a.tobytes())
        return [off, a.nbytes]

    first = len(info["images"])
    info["images"].append({"kind": "jpg", "data": put(encode(alb))})
    info["images"].append({"kind": "jpg", "data": put(encode(nrm))})
    info["parts"]["Body"]["tangents"] = put(tangents.astype(np.float16))
    info["materials"]["Skin"]["face_detail"] = {"albedo": first, "normal": first + 1,
                                                 "rect": [float(lo[0]), float(lo[1]), float(hi[0]), float(hi[1])]}
    golf_shoes.save(args.pack, info, blob)
    print(f"face detail: images {first}, {first + 1}, rect {np.round(lo, 3)}..{np.round(hi, 3)}; "
          f"pack {os.path.getsize(args.pack)} bytes")


if __name__ == "__main__":
    main()
