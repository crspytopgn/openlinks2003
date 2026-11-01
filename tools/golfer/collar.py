"""Gives the free golfer's polo shirts a real polo collar and placket, in
the look pack.

    python3 tools/golfer/collar.py [--pack game/assets/golfer/free_golfer_parts.olg]

The MakeHuman tops the pack is built from are crew-neck T-shirts, so the
"polo" read as a T-shirt. Tour polos have a knitted collar (a stand about
3 cm high round the neck, folded over into a fall about 4 cm deep that
ends in two points at the front) and a buttoned placket down the chest
(about 13 cm long and 3 cm wide, two or three buttons). This adds, for the
"polo" and "shorts" outfits:
- Collar_<outfit>: stand and fall built round the shirt's own neckline,
  open at the front over the placket, tinted with the top's colour;
- Placket_<outfit>: the placket strip on the chest;
- Buttons_<outfit>: two pearl buttons on it.

Each new vertex is skinned like, and follows the blend shapes of, the
nearest vertex of the shirt. It refuses a pack that has them already
("collar_v1").
"""

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import golf_shoes  # noqa: E402
import look_pack  # noqa: E402
from cap import part_arrays, shape_offsets, span  # noqa: E402

OUTFITS = ("polo", "shorts")
SAMPLES = 64
FRONT_GAP = math.radians(13)
STAND = 0.03
FALL = 0.04
POINT_FALL = 0.065
PLACKET_LEN = 0.13
PLACKET_HALF_W = 0.015
BUTTON_R = 0.0055


def neck_axis(info, blob):
    body, _, _ = part_arrays(info, blob, "Body")
    band = body[(body[:, 1] > 1.47) & (body[:, 1] < 1.53) & (np.abs(body[:, 0]) < 0.08)]
    return np.array([0.0, 0.0, float(band[:, 2].mean())])


def neckline(top, axis):
    """The shirt's neckline: per angle round the neck (0 at the back, +z;
    pi at the front), the highest shirt point near the neck."""
    rel = top - axis
    rad = np.hypot(rel[:, 0], rel[:, 2])
    near = (rad < 0.12) & (top[:, 1] > 1.35)
    ang = np.arctan2(rel[:, 0], rel[:, 2]) % (2 * math.pi)
    pts = []
    for k in range(SAMPLES):
        th = 2 * math.pi * k / SAMPLES
        d = np.abs((ang - th + math.pi) % (2 * math.pi) - math.pi)
        width = 1.5
        m = near & (d < math.pi / SAMPLES * width)
        while not m.any() and width < 12:
            width *= 2
            m = near & (d < math.pi / SAMPLES * width)
        if not m.any():
            pts.append([th, np.nan, np.nan])
            continue
        cand = top[m]
        best = cand[np.argmax(cand[:, 1])]
        pts.append([th, float(np.hypot(*(best - axis)[[0, 2]])), float(best[1])])
    pts = np.array(pts)
    for c in (1, 2):
        bad = np.isnan(pts[:, c])
        if bad.any():
            good = np.nonzero(~bad)[0]
            pts[bad, c] = np.interp(np.nonzero(bad)[0], good, pts[good, c], period=SAMPLES)
    # Smooth radius and height round the loop.
    for _ in range(10):
        for c in (1, 2):
            pts[:, c] = (np.roll(pts[:, c], 1) + 2 * pts[:, c] + np.roll(pts[:, c], -1)) / 4
    return pts


def shirt_height(top, axis, th, r, y_neck):
    """The shirt's surface height at angle th, distance r from the neck."""
    rel = top - axis
    rad = np.hypot(rel[:, 0], rel[:, 2])
    ang = np.arctan2(rel[:, 0], rel[:, 2]) % (2 * math.pi)
    d = np.abs((ang - th % (2 * math.pi) + math.pi) % (2 * math.pi) - math.pi)
    for tol in (0.006, 0.012, 0.025):
        m = (np.abs(rad - r) < tol) & (d < math.radians(8)) & (top[:, 1] < y_neck + 0.01) & (top[:, 1] > 1.2)
        if m.any():
            return float(top[m][:, 1].max())
    return y_neck - 0.02


def on_circle(axis, th, r, y):
    return np.array([axis[0] + r * math.sin(th), y, axis[2] + r * math.cos(th)])


def build_collar(line, axis, top):
    """Stand and fall as a strip of quads, open at the front."""
    pos, nrm, tris = [], [], []
    ths = np.linspace(math.pi + FRONT_GAP, 3 * math.pi - FRONT_GAP, 48)

    def at(th):
        k = (th % (2 * math.pi)) / (2 * math.pi) * SAMPLES
        k0 = int(math.floor(k)) % SAMPLES
        f = k - math.floor(k)
        a, b = line[k0], line[(k0 + 1) % SAMPLES]
        return a[1] * (1 - f) + b[1] * f, a[2] * (1 - f) + b[2] * f

    # Cross-section, (outward, up) from the neckline: up the stand, over
    # the fold, down the fall.
    rows = []
    for th in ths:
        r, y = at(th)
        front = max(0.0, -math.cos(th))  # 1 at the front
        from_front = abs((th % (2 * math.pi)) - math.pi)
        to_point = min(1.0, max(0.0, 1.0 - (from_front - FRONT_GAP) / math.radians(40)))
        stand = STAND * (1 - 0.2 * front)
        fall = FALL + (POINT_FALL - FALL) * to_point ** 3
        # Up the stand (leaning back a touch), round the fold, then the
        # fall lying on the shirt 2.5 mm off it, longest at the points.
        row = [on_circle(axis, th, r + 0.003, y - 0.002), on_circle(axis, th, r + 0.001, y + stand * 0.5),
               on_circle(axis, th, r + 0.001, y + stand), on_circle(axis, th, r + 0.0045, y + stand + 0.0035),
               on_circle(axis, th, r + 0.008, y + stand)]
        for d in (0.35, 0.6, 0.82, 1.0):
            out = 0.006 + fall * d
            surface = shirt_height(top, axis, th, r + out, y)
            # The fall drapes from the fold down to the shirt.
            lift = (stand - 0.004) * (1 - d) ** 2
            row.append(on_circle(axis, th, r + out, max(surface + 0.004, min(y + stand, surface + 0.004 + lift))))
        rows.append(row)
    rows = np.array(rows)
    # Smooth the fall round the neck: the shirt's surface is sampled from
    # a coarse mesh, and lumps would show (keep it off the shirt).
    for _ in range(6):
        sm = rows.copy()
        sm[1:-1, 5:] = (rows[:-2, 5:] + 2 * rows[1:-1, 5:] + rows[2:, 5:]) / 4
        sm[..., 1] = np.maximum(sm[..., 1], rows[..., 1])
        rows = sm
    n_sec = rows.shape[1]
    for i in range(len(ths)):
        for j in range(n_sec):
            pos.append(rows[i, j])
    for i in range(len(ths) - 1):
        for j in range(n_sec - 1):
            a, b = i * n_sec + j, i * n_sec + j + 1
            c, d = a + n_sec, b + n_sec
            tris += [(a, b, c), (b, d, c)]
    pos = np.array(pos)
    tris = np.array(tris)
    nrm = vertex_normals(pos, tris)
    # Point the normals away from the neck (both sides are drawn).
    out = pos - np.array([axis[0], 0, axis[2]]) * np.array([1, 0, 1])
    out[:, 1] = 0
    flip = (nrm * out).sum(axis=1) < 0
    nrm[flip] *= -1
    return pos, nrm, tris


def vertex_normals(pos, tris):
    fn = np.cross(pos[tris[:, 1]] - pos[tris[:, 0]], pos[tris[:, 2]] - pos[tris[:, 0]])
    acc = np.zeros_like(pos)
    for k in range(3):
        np.add.at(acc, tris[:, k], fn)
    return acc / np.maximum(np.linalg.norm(acc, axis=1, keepdims=True), 1e-12)


def chest_front(top, y):
    """The shirt's front surface at x = 0, height y."""
    m = (np.abs(top[:, 0]) < 0.02) & (np.abs(top[:, 1] - y) < 0.012) & (top[:, 2] < 0)
    if not m.any():
        m = (np.abs(top[:, 0]) < 0.04) & (np.abs(top[:, 1] - y) < 0.03) & (top[:, 2] < 0)
    return float(top[m][:, 2].min())


def build_placket(top, line, axis):
    y0 = float(line[SAMPLES // 2, 2]) + 0.004
    pos, tris = [], []
    steps = 10
    for s in range(steps + 1):
        y = y0 - PLACKET_LEN * s / steps
        z = chest_front(top, y) - 0.0025
        for x in (-PLACKET_HALF_W, 0.0, PLACKET_HALF_W):
            pos.append([x, y, z - (0.001 if x == 0 else 0.0)])
    for s in range(steps):
        for c in range(2):
            a = s * 3 + c
            tris += [(a, a + 3, a + 1), (a + 1, a + 3, a + 4)]
    pos = np.array(pos)
    tris = np.array(tris)
    nrm = vertex_normals(pos, tris)
    flip = nrm[:, 2] > 0
    nrm[flip] *= -1
    buttons, btris = [], []
    for k in range(2):
        y = y0 - 0.035 - 0.045 * k
        z = chest_front(top, y) - 0.0045
        c = len(buttons)
        buttons.append([0.0, y, z - 0.0012])
        for i in range(10):
            a = 2 * math.pi * i / 10
            buttons.append([BUTTON_R * math.cos(a), y + BUTTON_R * math.sin(a), z])
        for i in range(10):
            btris.append((c, c + 1 + i, c + 1 + (i + 1) % 10))
    buttons = np.array(buttons)
    btris = np.array(btris)
    bn = vertex_normals(buttons, btris)
    bn[bn[:, 2] > 0] *= -1
    return (pos, nrm, tris), (buttons, bn, btris)


def orient(pos, nrm, tris):
    fn = np.cross(pos[tris[:, 1]] - pos[tris[:, 0]], pos[tris[:, 2]] - pos[tris[:, 0]])
    flip = (fn * nrm[tris].sum(axis=1)).sum(axis=1) < 0
    tris = tris.copy()
    tris[flip] = tris[flip][:, [0, 2, 1]]
    return tris


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default="game/assets/golfer/free_golfer_parts.olg")
    args = ap.parse_args()
    info, blob = golf_shoes.load(args.pack)
    if "collar_v1" in info:
        raise SystemExit("the pack already has collars; check it out again first")

    def put(a, dtype):
        a = np.ascontiguousarray(a, dtype=dtype)
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(a.tobytes())
        return [off, a.nbytes]

    axis = neck_axis(info, blob)
    info["materials"]["Buttons"] = {"texture": -1, "normal": -1, "roughness": 0.35, "cutoff": 0.0,
                                    "double_sided": False, "tint": "", "colour": [0.92, 0.91, 0.88]}
    for outfit in OUTFITS:
        top_name = "Top_" + outfit
        top, t_bones, t_weights = part_arrays(info, blob, top_name)
        top_uv = span(blob, info["parts"][top_name]["uvs"], np.float32).reshape(-1, 2)
        line = neckline(top, axis)
        collar = build_collar(line, axis, top)
        placket, buttons = build_placket(top, line, axis)
        mat = info["parts"][top_name]["material"]
        for name, (pos, nrm, tris), material, double in (
                (f"Collar_{outfit}", collar, mat, True), (f"Placket_{outfit}", placket, mat, False),
                (f"Buttons_{outfit}", buttons, "Buttons", False)):
            tris = orient(pos, nrm, tris)
            if double:
                # Both sides of the collar show: a back copy with its own
                # normals.
                n0 = len(pos)
                pos = np.concatenate([pos, pos])
                nrm = np.concatenate([nrm, -nrm])
                tris = np.concatenate([tris, tris[:, [0, 2, 1]] + n0])
            nearest = np.argmin(((pos[:, None, :] - top[None]) ** 2).sum(axis=2), axis=1)
            uvs = top_uv[nearest] if material != "Buttons" else np.full((len(pos), 2), 0.5)
            shapes = {}
            for shape in info["parts"][top_name]["shapes"]:
                off = shape_offsets(info, blob, top_name, shape, len(top))[nearest]
                rows = np.nonzero(np.abs(off).max(axis=1) > 1.5e-3)[0]
                if len(rows):
                    shapes[shape] = {"rows": put(rows.astype(np.int32), np.int32),
                                     "positions": put(off[rows], np.float16)}
            n = len(pos)
            info["parts"][name] = {
                "material": material, "count": n,
                "positions": put(pos, np.float32), "normals": put(nrm, np.float16),
                "uvs": put(uvs, np.float32),
                "bones": put(t_bones[nearest], np.int32), "weights": put(t_weights[nearest], np.float32),
                "indices": put(tris[:, ::-1].reshape(-1), np.int32), "shapes": shapes,
            }
            if material != "Buttons":
                info["parts"][name]["tangents"] = put(look_pack.tangents(
                    pos.astype(np.float64), nrm.astype(np.float64), uvs.astype(np.float64), tris), np.float16)
            print(f"{name}: {n} vertices, {len(tris)} triangles")
    info["collar_v1"] = True
    golf_shoes.save(args.pack, info, blob)
    print(f"pack {os.path.getsize(args.pack)} bytes")


if __name__ == "__main__":
    main()
