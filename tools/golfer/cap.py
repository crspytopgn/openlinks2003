"""Rebuilds the free golfer's cap in the look pack as a structured tour cap.

    python3 tools/golfer/cap.py [--pack game/assets/golfer/free_golfer_parts.olg]

The first cap (build_free_golfer.cap_mesh) was a single shrink-wrapped
shell with a flat peak: it read as a helmet, its peak vanished from the
front, the shorter hair styles poked through it and skin showed between
the band and the peak.

This one follows real structured six-panel golf caps (spec sheets give a
crown about 9 cm tall at the front and a peak about 7 cm long and 18 cm
across):
- the crown is wrapped over the head and every hair style the cap is worn
  with, so no hair pokes through, with a stiffer, fuller front;
- six panels meeting at a button on top, with a seam down the front, the
  seams drawn into the texture with twin stitching and an eyelet in each
  panel;
- a pre-curved peak with a real thickness, tilted down about 12 degrees,
  its sides curling down, rows of stitching following its edge and a
  darker under-peak;
- a sweatband that closes the gap between the cap and the forehead.

The texture and normal map are grey (the player's cap colour tints them),
drawn here from the mesh's own layout. The cap's blend shapes follow the
nearest head vertex, as before. Run it on the original pack (see
upgrade_pack.py); it refuses a pack that has it already ("cap_v2").
"""

import argparse
import io
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import golf_shoes  # noqa: E402  (load and save)
import look_pack  # noqa: E402  (tangents)

CAP_HAIR = ("short", "crop", "side_part", "ponytail")
SEGMENTS = 60
RINGS = 14
HAIR_ROOM = 0.004
PEAK_LENGTH = 0.07
PEAK_HALF_SPAN = math.radians(72)
PEAK_TILT = math.radians(12)
PEAK_CURL = 0.02
PEAK_THICK = 0.0035
TEX = 512
# Texture layout (u, v ranges): crown, peak top, peak underside, band.
CROWN_U = (0.0, 0.70)
PEAK_TOP = (0.72, 1.0, 0.0, 0.48)
PEAK_UNDER = (0.72, 1.0, 0.52, 1.0)
BAND_V = (0.0, 0.04)  # under the crown's own strip, along the bottom edge


def span(blob, s, dtype):
    return np.frombuffer(bytes(blob[s[0]:s[0] + s[1]]), dtype)


def part_arrays(info, blob, name):
    e = info["parts"][name]
    pos = span(blob, e["positions"], np.float32).reshape(-1, 3)
    bones = span(blob, e["bones"], np.int32).reshape(-1, 4)
    weights = span(blob, e["weights"], np.float32).reshape(-1, 4)
    return pos, bones, weights


def shape_offsets(info, blob, name, shape, count):
    e = info["parts"][name]["shapes"].get(shape)
    out = np.zeros((count, 3), np.float32)
    if e is None:
        return out
    rows = span(blob, e["rows"], np.int32)
    out[rows] = span(blob, e["positions"], np.float16).reshape(-1, 3).astype(np.float32)
    return out


def crown(points, brow_y, centre):
    """The crown as a (RINGS+1, SEGMENTS, 3) grid of points round `centre`,
    reaching over `points` plus HAIR_ROOM."""
    rel = points - centre
    dist = np.linalg.norm(rel, axis=1)
    dirs = rel / dist[:, None]

    def reach(u):
        near = dirs @ u > math.cos(math.radians(8))
        return (dist[near].max() if near.any() else 0.09) + HAIR_ROOM

    grid = np.zeros((RINGS + 1, SEGMENTS, 3))
    for i in range(RINGS + 1):
        phi = math.pi / 2 * (i / RINGS) ** 0.9
        for k in range(SEGMENTS):
            th = 2 * math.pi * k / SEGMENTS
            back = max(0.0, math.cos(th))  # +z is the back of the head
            phi_eff = phi - (1 - i / RINGS) * math.radians(20) * back
            u = np.array([math.cos(phi_eff) * math.sin(th), math.sin(phi_eff), math.cos(phi_eff) * math.cos(th)])
            grid[i, k] = reach(u) * u
    r = np.linalg.norm(grid, axis=2)
    # Cloth over a stiff frame: smooth out the skull and the hair's lumps,
    # never moving inwards, so nothing pokes through.
    for _ in range(6):
        s = (r + np.roll(r, 1, axis=1) + np.roll(r, -1, axis=1)) / 3
        s[1:-1] = (s[1:-1] * 2 + s[:-2] + s[2:]) / 4
        r = np.maximum(r, s)
    # The structured front: the front panels stand up off the forehead.
    for i in range(RINGS + 1):
        t = i / RINGS
        for k in range(SEGMENTS):
            th = 2 * math.pi * k / SEGMENTS
            front = max(0.0, -math.cos(th))
            r[i, k] += 0.008 * front ** 1.5 * math.sin(math.pi * min(1.0, t * 1.3))
    grid = grid / np.linalg.norm(grid, axis=2, keepdims=True) * r[..., None]
    # The top is one point (the button sits on it).
    grid[RINGS] = grid[RINGS].mean(axis=0)
    return grid


def build(info, blob):
    body, b_bones, b_weights = part_arrays(info, blob, "Body")
    head_j = info["bones"].index("head")
    on_head = (b_bones == head_j).__and__(b_weights > 0.5).any(axis=1)
    brows, _, _ = part_arrays(info, blob, "Eyebrows")
    brow_y = float(brows[:, 1].mean() + 0.022)
    pts = [body[on_head]]
    for h in CAP_HAIR:
        hp, _, _ = part_arrays(info, blob, "Hair_" + h)
        pts.append(hp)
    allp = np.concatenate(pts)
    allp = allp[allp[:, 1] > brow_y - 0.06]
    head_top = body[on_head]
    top = head_top[head_top[:, 1] > brow_y]
    lo, hi = top.min(axis=0), top.max(axis=0)
    centre = np.array([(lo[0] + hi[0]) / 2, brow_y, (lo[2] + hi[2]) / 2])
    grid = crown(allp, brow_y, centre)

    pos, nrm, uv, tris = [], [], [], []

    def add(p, n, t):
        p, n = np.asarray(p, float).reshape(3), np.asarray(n, float).reshape(3)
        pos.append(p)
        nrm.append(n / max(np.linalg.norm(n), 1e-9))
        uv.append(t)
        return len(pos) - 1

    # Crown: a seam column at k == SEGMENTS (u wraps), outward normals.
    # u starts at the back (+z) and goes round; the front seam is mid-way.
    idx = np.zeros((RINGS + 1, SEGMENTS + 1), int)
    for i in range(RINGS + 1):
        for k in range(SEGMENTS + 1):
            p = grid[i, k % SEGMENTS]
            u = CROWN_U[0] + (CROWN_U[1] - CROWN_U[0]) * k / SEGMENTS
            v = BAND_V[1] + (1 - BAND_V[1]) * i / RINGS
            idx[i, k] = add(p + centre, p, (u, v))
    for i in range(RINGS):
        for k in range(SEGMENTS):
            a0, a1, b0, b1 = idx[i, k], idx[i, k + 1], idx[i + 1, k], idx[i + 1, k + 1]
            tris += [(a0, b0, a1), (a1, b0, b1)]
    # Smooth normals over the crown from the faces.
    # Sweatband: from the crown's lower edge 1.2 cm up the inside.
    band_in = np.zeros(SEGMENTS + 1, int)
    for k in range(SEGMENTS + 1):
        p = grid[0, k % SEGMENTS]
        inward = p * (1 - 0.006 / np.linalg.norm(p)) + np.array([0, 0.012, 0])
        u = CROWN_U[0] + (CROWN_U[1] - CROWN_U[0]) * k / SEGMENTS
        band_in[k] = add(inward + centre, -p, (u, BAND_V[0]))
    for k in range(SEGMENTS):
        tris += [(idx[0, k], idx[0, k + 1], band_in[k]), (idx[0, k + 1], band_in[k + 1], band_in[k])]
    crown_end = len(pos)

    # The peak (rigid: it follows the band in the blend shapes).
    peak_start = len(pos)
    band = grid[0] + centre

    def band_at(th):
        kf = (th % (2 * math.pi)) / (2 * math.pi) * SEGMENTS
        k0 = int(math.floor(kf)) % SEGMENTS
        f = kf - math.floor(kf)
        return band[k0] * (1 - f) + band[(k0 + 1) % SEGMENTS] * f

    steps, depth = 28, 8
    left, right = band_at(math.pi - PEAK_HALF_SPAN), band_at(math.pi + PEAK_HALF_SPAN)
    half_w = (abs(left[0] - centre[0]) + abs(right[0] - centre[0])) / 2
    # Which way round the band runs: a = +1 is on this side of the face.
    side_sign = 1.0 if right[0] > centre[0] else -1.0
    zc = (left[2] + right[2]) / 2
    z_front = band_at(math.pi)[2]
    reach_c = (zc - z_front) + PEAK_LENGTH
    top_rows, under_rows = [], []
    for s in range(steps + 1):
        a = -1.0 + 2.0 * s / steps
        root = band_at(math.pi + a * PEAK_HALF_SPAN)
        # Start the peak a little inside the crown and above its edge, so
        # no gap shows between them.
        root = centre + (root - centre) * (1 - 0.004 / np.linalg.norm(root - centre)) + np.array([0.0, 0.004, 0.0])
        edge = np.array([centre[0] + side_sign * a * half_w * 1.04, root[1], zc - reach_c * math.sqrt(max(0.0, 1 - a * a))])
        trow, urow = [], []
        for d in range(depth + 1):
            t = d / depth
            q = root * (1 - t) + edge * t
            out = max(0.0, root[2] - q[2])
            q[1] -= math.tan(PEAK_TILT) * out + PEAK_CURL * a * a * t ** 1.2
            n_top = np.array([0.0, 1.0, 0.0]) + np.array([-side_sign * a * 0.5 * t, 0.0, -math.tan(PEAK_TILT)])
            tu = PEAK_TOP[0] + (PEAK_TOP[1] - PEAK_TOP[0]) * (s / steps)
            trow.append(add(q, n_top, (tu, PEAK_TOP[2] + (PEAK_TOP[3] - PEAK_TOP[2]) * t)))
            qu = q - np.array([0.0, PEAK_THICK, 0.0])
            urow.append(add(qu, -n_top, (tu, PEAK_UNDER[2] + (PEAK_UNDER[3] - PEAK_UNDER[2]) * t)))
        top_rows.append(trow)
        under_rows.append(urow)
    for s in range(steps):
        for d in range(depth):
            a0, a1 = top_rows[s][d], top_rows[s][d + 1]
            b0, b1 = top_rows[s + 1][d], top_rows[s + 1][d + 1]
            tris += [(a0, a1, b0), (a1, b1, b0)]
            a0, a1 = under_rows[s][d], under_rows[s][d + 1]
            b0, b1 = under_rows[s + 1][d], under_rows[s + 1][d + 1]
            tris += [(a0, b0, a1), (a1, b0, b1)]

    # The edge, top to underside round the tip, on plain cloth in the
    # texture (its own vertices, so it doesn't stretch the stitching).
    edge_uv = (PEAK_TOP[0] + 0.02, PEAK_TOP[2] + 0.02)
    et, eu = [], []
    for s in range(steps + 1):
        a, b = top_rows[s][depth], under_rows[s][depth]
        out = pos[a] - (centre + np.array([0.0, pos[a][1] - centre[1], 0.0]))
        et.append(add(pos[a], out, edge_uv))
        eu.append(add(pos[b], out, edge_uv))
    for s in range(steps):
        tris += [(et[s], eu[s], et[s + 1]), (et[s + 1], eu[s], eu[s + 1])]

    peak_end = len(pos)
    # The button: a flat dome 1.3 cm across on top.
    tip = grid[RINGS, 0] + centre
    up = grid[RINGS, 0] / np.linalg.norm(grid[RINGS, 0])
    side = np.cross(up, [0, 0, 1.0])
    side /= np.linalg.norm(side)
    fwd = np.cross(side, up)
    c = add(tip + up * 0.004, up, (0.69, 0.995))
    ring = []
    for k in range(12):
        ang = 2 * math.pi * k / 12
        d = side * math.cos(ang) + fwd * math.sin(ang)
        ring.append(add(tip + d * 0.0065 + up * 0.0005, up + d, (0.69, 0.99)))
    for k in range(12):
        tris.append((c, ring[k], ring[(k + 1) % 12]))

    pos = np.array(pos, np.float32)
    nrm = np.array(nrm, np.float32)
    uv = np.array(uv, np.float32)
    tris = np.array(tris, np.int32)
    # Crown normals from its faces (smoother than the radial ones).
    crown_tris = tris[np.all(tris < crown_end, axis=1)]
    fn = np.cross(pos[crown_tris[:, 1]] - pos[crown_tris[:, 0]], pos[crown_tris[:, 2]] - pos[crown_tris[:, 0]])
    acc = np.zeros_like(pos)
    for kk in range(3):
        np.add.at(acc, crown_tris[:, kk], fn)
    ln = np.linalg.norm(acc, axis=1)
    good = (np.arange(len(pos)) < crown_end) & (ln > 1e-12)
    # Faces wind so their cross product points out (anticlockwise seen
    # from outside); keep the sign that agrees with the radial normal.
    acc[good] /= ln[good, None]
    flip = (acc[good] * nrm[good]).sum(axis=1) < 0
    acc_good = acc[good]
    acc_good[flip] *= -1
    nrm[good] = acc_good
    # The crown's seam column shares positions: average its normals.
    for i in range(RINGS + 1):
        a, b = idx[i, 0], idx[i, SEGMENTS]
        m = nrm[a] + nrm[b]
        nrm[a] = nrm[b] = m / max(np.linalg.norm(m), 1e-9)
    return pos, nrm, uv, tris, head_j, body, on_head, (peak_start, peak_end, idx[0, :SEGMENTS])


def orient(pos, nrm, tris):
    """Winds every triangle anticlockwise seen from its normal's side."""
    fn = np.cross(pos[tris[:, 1]] - pos[tris[:, 0]], pos[tris[:, 2]] - pos[tris[:, 0]])
    vn = nrm[tris].sum(axis=1)
    flip = (fn * vn).sum(axis=1) < 0
    tris = tris.copy()
    tris[flip] = tris[flip][:, [0, 2, 1]]
    return tris


def texture(pos, uv, tris):
    """Grey albedo and a normal map for the cap's layout."""
    n = TEX
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    u, v = (xs + 0.5) / n, 1.0 - (ys + 0.5) / n  # v up, image rows down
    rng = np.random.default_rng(1974)
    # Cotton twill: fine diagonal ribs.
    twill = 0.5 + 0.5 * np.sin((xs + ys) * 2 * math.pi / 3.0)
    noise = np.asarray(Image.fromarray((rng.random((n, n)) * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(0.7)), np.float32) / 255.0
    shade = 0.94 + 0.015 * twill + 0.04 * (noise - 0.5)
    height = 0.12 * twill + 0.2 * noise
    crown = u < CROWN_U[1] + 0.005
    cu = (u - CROWN_U[0]) / (CROWN_U[1] - CROWN_U[0])  # 0..1 round from the back
    cv = (v - BAND_V[1]) / (1 - BAND_V[1])
    px_per_u = n * (CROWN_U[1] - CROWN_U[0])
    # Panel seams every sixth of the way round, one of them at the front
    # (cu = 0.5); twin stitch rows 3 px either side.
    for k in range(7):
        d = np.abs(cu - k / 6.0) * px_per_u
        seam = crown & (d < 1.2) & (cv > 0.0)
        shade[seam] *= 0.72
        height[seam] -= 1.5
        for off in (3.0, 4.5):
            stitch = crown & (np.abs(d - off) < 0.55) & (cv > 0.02) & ((ys.astype(int) // 2) % 2 == 0)
            shade[stitch] *= 0.86
            height[stitch] += 0.6
    # Eyelets: a small stitched ring near the top of each panel.
    for k in range(6):
        cx = (k + 0.5) / 6.0 * px_per_u + CROWN_U[0] * n
        cy = (1.0 - (BAND_V[1] + (1 - BAND_V[1]) * 0.72)) * n
        r = np.hypot(xs - cx, ys - cy)
        shade[r < 2.2] *= 0.55
        height[r < 2.2] -= 1.0
        ring_ = (r >= 2.2) & (r < 3.6)
        shade[ring_] *= 0.85
        height[ring_] += 0.8
    # A stitched line round the bottom of the crown, and the sweatband.
    bottom = crown & (cv > 0.03) & (cv < 0.05) & ((xs.astype(int) // 2) % 2 == 0)
    shade[bottom] *= 0.85
    band = crown & (v < BAND_V[1])
    shade[band] = 0.55 + 0.05 * noise[band]
    # Peak: rows of stitching following the edge, darker under-peak.
    pt = (u >= PEAK_TOP[0]) & (v <= PEAK_TOP[3])
    t = (v - PEAK_TOP[2]) / (PEAK_TOP[3] - PEAK_TOP[2])
    for row in (0.42, 0.52, 0.62, 0.72, 0.82, 0.92):
        st = pt & (np.abs(t - row) * n * (PEAK_TOP[3] - PEAK_TOP[2]) < 0.6) & ((xs.astype(int) // 2) % 2 == 0)
        shade[st] *= 0.84
        height[st] += 0.7
    under = (u >= PEAK_UNDER[0]) & (v >= PEAK_UNDER[2])
    shade[under] *= 0.72
    # Button: same cloth, a touch darker.
    shade[(u > 0.685) & (u < 0.70) & (v > 0.985)] *= 0.9
    shade = np.clip(shade, 0, 1)
    albedo = Image.fromarray((shade * 255).astype(np.uint8)).convert("RGB")
    h = height.astype(np.float32)
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    strength = 0.35
    nm = np.stack([-dx * strength, dy * strength, np.ones_like(h)], -1)
    nm /= np.linalg.norm(nm, axis=2, keepdims=True)
    normal = Image.fromarray(((nm * 0.5 + 0.5) * 255).astype(np.uint8))
    return albedo, normal


def encode(img, kind):
    b = io.BytesIO()
    if kind == "jpg":
        img.save(b, "JPEG", quality=88, optimize=True)
    else:
        img.save(b, "PNG", optimize=True)
    return b.getvalue()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default="game/assets/golfer/free_golfer_parts.olg")
    ap.add_argument("--preview", default="")
    args = ap.parse_args()
    info, blob = golf_shoes.load(args.pack)
    if "cap_v2" in info:
        raise SystemExit("the pack already has the new cap; check it out again first")
    old = info["parts"]["Cap"]
    pos, nrm, uv, tris, head_j, body, on_head, (peak_start, peak_end, band_ids) = build(info, blob)
    tris = orient(pos, nrm, tris)
    while len(blob) % 4:
        blob.append(0)

    def put(a, dtype):
        a = np.ascontiguousarray(a, dtype=dtype)
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(a.tobytes())
        return [off, a.nbytes]

    albedo, normal = texture(pos, uv, tris)
    if args.preview:
        albedo.save(args.preview)
    img_a = len(info["images"])
    info["images"].append({"kind": "jpg", "data": put(np.frombuffer(encode(albedo, "jpg"), np.uint8), np.uint8)})
    # The normal map as a JPEG: a PNG of it is 230 KB, this about 40 KB.
    info["images"].append({"kind": "jpg", "data": put(np.frombuffer(encode(normal, "jpg"), np.uint8), np.uint8)})
    info["materials"]["Cap"].update({"texture": img_a, "normal": img_a + 1, "roughness": 0.9})
    # Blend shapes: the crown moves with the head under it (an average of
    # the nearest head vertices, so it stays smooth) and the peak moves
    # rigidly with the nearest point of the band, so it never kinks.
    head_ids = np.nonzero(on_head)[0]
    hp = body[head_ids]
    K = 12
    near_ids = np.empty((len(pos), K), int)
    near_w = np.empty((len(pos), K))
    for i0 in range(0, len(pos), 256):
        d = ((pos[i0:i0 + 256, None, :] - hp[None]) ** 2).sum(axis=2)
        nn = np.argsort(d, axis=1)[:, :K]
        dd = np.sqrt(np.take_along_axis(d, nn, axis=1)) + 1e-4
        w = 1.0 / dd ** 2
        near_ids[i0:i0 + 256] = head_ids[nn]
        near_w[i0:i0 + 256] = w / w.sum(axis=1, keepdims=True)
    peak = np.arange(peak_start, peak_end)
    band_pos = pos[band_ids]
    anchor = np.arange(len(pos))
    anchor[peak] = band_ids[np.argmin(((pos[peak, None, :] - band_pos[None]) ** 2).sum(axis=2), axis=1)]
    shapes = {}
    for shape in info["parts"]["Body"]["shapes"]:
        full = shape_offsets(info, blob, "Body", shape, len(body))
        off = (full[near_ids] * near_w[..., None]).sum(axis=1)
        off = off[anchor]
        rows = np.nonzero(np.abs(off).max(axis=1) > 1e-4)[0]
        if len(rows) == 0:
            continue
        shapes[shape] = {"rows": put(rows.astype(np.int32), np.int32), "positions": put(off[rows], np.float16)}
    n = len(pos)
    entry = {
        "material": "Cap", "count": n,
        "positions": put(pos, np.float32), "normals": put(nrm, np.float16), "uvs": put(uv, np.float32),
        "bones": put(np.tile([head_j, 0, 0, 0], (n, 1)), np.int32),
        "weights": put(np.tile([1.0, 0, 0, 0], (n, 1)), np.float32),
        # Godot's front faces wind clockwise.
        "indices": put(tris[:, ::-1].reshape(-1), np.int32),
        "tangents": put(look_pack.tangents(pos.astype(np.float64), nrm.astype(np.float64), uv.astype(np.float64),
                                           tris), np.float16),
        "shapes": shapes,
    }
    del old
    info["parts"]["Cap"] = entry
    info["cap_v2"] = True
    golf_shoes.save(args.pack, info, blob)
    print(f"cap: {n} vertices, {len(tris)} triangles, {len(shapes)} shapes, pack {os.path.getsize(args.pack)} bytes")


if __name__ == "__main__":
    main()
