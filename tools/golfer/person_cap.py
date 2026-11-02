"""Fits a tour cap to each realistic (Rocketbox) person's own head.

    python3 tools/golfer/person_cap.py [--pack game/assets/golfer/free_golfer_parts.olg]

rocketbox.py calls fit() for every person it adds; run on its own, this
refits the caps of the people already in a pack (and compacts it).

The first people caps were the creator's cap stretched to the bounding box
of each skull's top 10 cm. Rocketbox heads are shaped differently (and
some carry modelled hair, a bun or a ponytail), so the band stood 13 to
35 mm off the head, the cap sat down over the eyes and its top was lumpy.

This builds the cap (cap.shell, the same six-panel structured cap) on the
person's own skull instead, placed the way tour players wear one (real
caps and photos, see docs/golfer-cap.md):
- the brim seam about 2.5 cm above the eyebrows, so the peak shades the
  eyes without hiding them; the band runs above the ears and drops to the
  back of the skull;
- the crown wraps the skull with CAP_ROOM for the hair it presses down,
  stiffer and fuller at the front; ears, buns and other lumps that a cap
  pushes down are left out of the wrap;
- the head gets a "cap_press" blend shape that pulls whatever would poke
  through (a bun, modelled hair) in under the crown; FreeGolfer turns it
  on when the cap is on.
"""

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import cap as cap_mesh  # noqa: E402
import golf_shoes  # noqa: E402  (load and save)
import look_pack  # noqa: E402  (tangents)

# Room between the scalp and the crown: the cap's cloth and the hair it
# presses flat (Rocketbox hair is mostly painted on the scalp).
CAP_ROOM = 0.0045
# Brim seam above the eyebrows' middle (tour players in photos: about a
# finger's width).
SEAM_ABOVE_BROW = 0.018
# The nasion (between the eyes) above the nose tip.
NOSE_LENGTH = 0.047
# Eyebrows above the nasion (between the eyes).
BROW_ABOVE_NASION = 0.012
# Lumps further than this outside the skull's best-fit ellipsoid are ears,
# buns and ponytails, not skull.
LUMP = 0.015
# The press keeps the head this far inside the crown.
PRESS_GAP = 0.003
# How far the band drops round the back (to the back of the skull, above
# the nape), as an angle from the crown's centre.
BACK_DROP = math.radians(20)
# How far the structured front panels stand off the forehead at most,
# and how much fuller than the skull the crown is at the top.
FRONT_STAND = 0.018
TOP_FULL = 0.006
# How far the crown fills out to the dome over its band (1: all the way).
DOME = 0.97
# The skull (or pressed hair) under the crown rises at most this far above
# the brim seam: a real head's crown is 7 to 8 cm above it.
MAX_RISE = 0.085
# The peak: tour caps' pre-curved bill, 2 3/4 in (7 cm) from the seam
# (spec sheets), its sides bent down.
PEAK = {"half_span": math.radians(68), "tilt": math.radians(11), "length": 0.07, "curl": 0.05, "bend": True,
        # The sweatband tucks under the edge against the head: reaching up
        # the inside, it showed as a pale strip under the crown's edge.
        "band_lift": -0.002}

# The cap styles (PlayerLook.CAP_STYLES): part name suffix and shape.
# "tour": the structured mid-profile tour cap above.
# "dad": an unstructured low-profile cap (washed cotton, no buckram): the
# front panels lie on the forehead, the crown follows the head instead of
# standing up as a dome, the bill is softer and curved more, and there is
# an adjustable strap with an opening above it at the back.
STYLES = {
    "tour": {"part": "cap", "front_stand": FRONT_STAND, "top_full": TOP_FULL, "dome": DOME,
             "seam": SEAM_ABOVE_BROW, "peak": PEAK, "back_opening": False},
    # Soft cotton sits down on the head: it presses hair lower than the
    # stiff cap (max_rise) and its front panels lie on the forehead
    # (front_stand below the room for hair dents them in a little).
    "dad": {"part": "dadcap", "front_stand": -0.002, "top_full": 0.0, "dome": 0.0, "max_rise": 0.078,
            "seam": 0.015, "back_opening": True,
            "peak": dict(PEAK, curl=0.07, tilt=math.radians(13), length=0.068, half_span=math.radians(70))},
}
# The dad cap's back opening over its adjustable strap (a half ellipse,
# as on real ones): strap height, opening width and height (m).
STRAP_H = 0.016
OPENING_W = 0.07
OPENING_H = 0.035


def arrays(info, blob, part):
    e = info["parts"][part]

    def a(k, dt, c):
        o, n = e[k]
        return np.frombuffer(bytes(blob[o:o + n]), dt).reshape(-1, c)
    return a("positions", np.float32, 3).astype(np.float64), a("indices", np.int32, 3)


def landmarks(pos):
    """(top of the head, nasion height): +y up, the face
    towards -z."""
    top = pos[:, 1].max()
    mid = pos[np.abs(pos[:, 0] - np.median(pos[:, 0])) < 0.012]
    # The nose tip: the front-most midline point 10 to 20 cm below the top.
    band = mid[(mid[:, 1] < top - 0.10) & (mid[:, 1] > top - 0.20)]
    tip = band[np.argmin(band[:, 2])]
    # The nasion, a nose's length (adults: about 4.7 cm) above the tip:
    # the profile's dip there is too shallow on these low-poly heads to
    # find reliably (it put two people's caps over their eyes).
    nasion_y = tip[1] + NOSE_LENGTH
    return top, nasion_y


def fit_ellipsoid(p, centre_y):
    """The axis-aligned ellipsoid that best fits p, centred at height
    centre_y (only the top of the head is known, so the height is given):
    centre and radii."""
    y = p[:, 1] - centre_y
    a = np.c_[p[:, 0] ** 2, y ** 2, p[:, 2] ** 2, p[:, 0], p[:, 2]]
    (qa, qb, qc, d, f), *_ = np.linalg.lstsq(a, np.ones(len(p)), rcond=None)
    q = np.array([qa, qb, qc])
    c = np.array([-d / (2 * qa), centre_y, -f / (2 * qc)])
    k = 1 + qa * c[0] ** 2 + qc * c[2] ** 2
    return c, np.sqrt(np.abs(k / np.where(np.abs(q) > 1e-9, q, 1e-9)))


def outside(p, c, r):
    """About how far each point is outside the ellipsoid (m)."""
    rel = p - c
    s = np.sqrt(((rel / r) ** 2).sum(axis=1))
    return (s - 1) * np.linalg.norm(rel, axis=1) / np.maximum(s, 1e-9)


def skull(pos, tris, floor_y, centre_y):
    """The triangles over the skull above floor_y, with ears and lumps
    (buns, ponytails) left out: (T, 3, 3) corners, kept vertex mask."""
    above = pos[:, 1] > floor_y
    keep = above.copy()
    for _ in range(5):
        c, r = fit_ellipsoid(pos[keep], centre_y)
        keep = above & (outside(pos, c, r) < LUMP)
    good = tris[keep[tris].all(axis=1)]
    return pos[good], keep


def raycast(origin, dirs, tri):
    """Distance along each ray to the furthest triangle it crosses (NaN
    where it crosses none)."""
    v0, e1, e2 = tri[:, 0], tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]
    out = np.full(len(dirs), np.nan)
    for i0 in range(0, len(dirs), 64):
        d = dirs[i0:i0 + 64][:, None, :]
        p = np.cross(d, e2[None])
        det = (e1[None] * p).sum(-1)
        ok = np.abs(det) > 1e-12
        inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        t0 = origin - v0
        u = (t0[None] * p).sum(-1) * inv
        q = np.cross(t0, e1)
        v = (d * q[None]).sum(-1) * inv
        t = (e2[None] * q[None]).sum(-1) * inv
        hit = ok & (u >= -1e-6) & (v >= -1e-6) & (u + v <= 1 + 1e-6) & (t > 0)
        t = np.where(hit, t, -1.0)
        best = t.max(axis=1)
        out[i0:i0 + 64] = np.where(best > 0, best, np.nan)
    return out


def crown(tri, centre, style):
    """cap.crown's grid, fitted by casting rays at the skull instead of
    taking the furthest point in a cone (which caught the bump of the
    back of the head and left the band standing off the nape)."""
    rings, segs = cap_mesh.RINGS, cap_mesh.SEGMENTS
    dirs = np.zeros((rings + 1, segs, 3))
    for i in range(rings + 1):
        phi = math.pi / 2 * (i / rings) ** 0.9
        for k in range(segs):
            th = 2 * math.pi * k / segs
            back = max(0.0, math.cos(th))  # +z is the back of the head
            phi_eff = phi - (1 - i / rings) * BACK_DROP * back
            dirs[i, k] = [math.cos(phi_eff) * math.sin(th), math.sin(phi_eff), math.cos(phi_eff) * math.cos(th)]
    r = raycast(centre, dirs.reshape(-1, 3), tri).reshape(rings + 1, segs)
    # Rays that slip between triangles take their neighbours' reach.
    for _ in range(8):
        if not np.isnan(r).any():
            break
        nb = np.stack([np.roll(r, 1, 1), np.roll(r, -1, 1)])
        cnt = (~np.isnan(nb)).sum(axis=0)
        mean = np.where(cnt > 0, np.nansum(nb, axis=0) / np.maximum(cnt, 1), np.nan)
        r = np.where(np.isnan(r), mean, r)
    r = np.where(np.isnan(r), np.nanmedian(r), r) + CAP_ROOM
    # Hair piled higher than a skull (some people's modelled hair) is
    # pressed down: the crown rises at most MAX_RISE over the brim seam
    # before its structure is added.
    rise = (dirs[..., 1] * r).max()
    max_rise = style.get("max_rise", MAX_RISE)
    if rise > max_rise:
        p = dirs * r[..., None]
        p[..., 1] = np.where(p[..., 1] > 0, p[..., 1] * (max_rise / rise), p[..., 1])
        r = np.linalg.norm(p, axis=2)
        dirs = p / r[..., None]
    # Stiff panels over the skull's small bumps: smooth, never inwards.
    for _ in range(12):
        sm = (r + np.roll(r, 1, axis=1) + np.roll(r, -1, axis=1)) / 3
        sm[1:-1] = (sm[1:-1] * 2 + sm[:-2] + sm[2:]) / 4
        r = np.maximum(r, sm)
    # A structured cap is its own shape, not the skull's: the front panels
    # (stiffened) stand up off the forehead and the crown is fuller over the
    # top, so the button sits above the head (real caps on a head, side on).
    for i in range(rings + 1):
        t = i / rings
        for k in range(segs):
            front = max(0.0, -math.cos(2 * math.pi * k / segs))
            r[i, k] += style["front_stand"] * front ** 1.3 * math.sin(math.pi / 2 * min(1.0, t * 1.6)) * (1 - 0.35 * t)
            r[i, k] += style["top_full"] * t ** 1.5
    for _ in range(4):
        sm = (r + np.roll(r, 1, axis=1) + np.roll(r, -1, axis=1)) / 3
        sm[1:-1] = (sm[1:-1] * 2 + sm[:-2] + sm[2:]) / 4
        r[1:] = sm[1:]
    # Six stiff panels make a dome, fuller at the shoulders than the skull
    # (which narrows to the top): the crown fills out to the dome over its
    # band, as tall as it already is.
    band = dirs[0] * r[0][:, None]
    ax = np.abs(band[:, 0]).max()
    az = np.abs(band[:, 2]).max()
    height = (dirs[..., 1] * r).max()
    dome = 1.0 / np.sqrt((dirs[..., 0] / ax) ** 2 + (dirs[..., 1] / height) ** 2 + (dirs[..., 2] / az) ** 2)
    up = np.clip(dirs[..., 1] / 0.25, 0.0, 1.0)  # not round the band's drop at the back
    r = np.maximum(r, r + (dome * style["dome"] - r) * up)
    for i in range(rings - 4, rings + 1):
        w = (i - (rings - 4)) / 4
        r[i] = r[i] * (1 - w) + r[i].mean() * w
    grid = dirs * r[..., None]
    grid[rings] = grid[rings].mean(axis=0)
    return grid


def fit(info, blob, name):
    """Every style's cap mesh for the person, and the head's cap_press
    offsets: ({style: (pos, nrm, uv, tris)}, press_rows, press_offsets,
    landmarks)."""
    pos, tris = arrays(info, blob, "RB_%s_head" % name)
    top, nasion_y = landmarks(pos)
    brow_y = nasion_y + BROW_ABOVE_NASION
    tri, keep = skull(pos, tris, brow_y - 0.06, brow_y)
    caps = {}
    pressed = {}
    for style_name, style in STYLES.items():
        seam_y = brow_y + style["seam"]
        upper = tri.reshape(-1, 3)
        upper = upper[upper[:, 1] > seam_y]
        lo, hi = upper.min(axis=0), upper.max(axis=0)
        centre = np.array([(lo[0] + hi[0]) / 2, seam_y, (lo[2] + hi[2]) / 2])
        grid = crown(tri, centre, style)
        cp, cn, cu, ct, _ = cap_mesh.shell(grid, centre, style["peak"])
        ct = cap_mesh.orient(cp, cn, ct)
        if style["back_opening"]:
            cp, cn, ct = back_opening(cp, cn, ct)
        caps[style_name] = (cp, cn, cu, ct)
        # One press for every style: each vertex moves as far in as the
        # tightest crown over it needs.
        rows, offs = press(pos, grid, centre)
        for row, off in zip(rows, offs):
            if row not in pressed or np.linalg.norm(off) > np.linalg.norm(pressed[row]):
                pressed[row] = off
    press_rows = np.array(sorted(pressed), np.int32)
    press_offs = np.array([pressed[r] for r in press_rows], np.float32).reshape(-1, 3)
    marks = {"top": top, "brow": brow_y, "seam": brow_y + STYLES["tour"]["seam"]}
    return caps, press_rows, press_offs, marks


def back_opening(pos, nrm, tris):
    """Cuts the strap opening into the crown: a half ellipse OPENING_W
    across and OPENING_H tall standing on a STRAP_H strap at the back.
    Triangles inside go, and the crown vertices round the hole move onto
    its edge so it is smooth, not stepped like the grid. Returns new
    positions, normals and triangles."""
    rings, segs, cols = cap_mesh.RINGS, cap_mesh.SEGMENTS, cap_mesh.SEGMENTS + 1
    crown_n = (rings + 1) * cols
    grid = pos[:crown_n].reshape(rings + 1, cols, 3)
    gn = nrm[:crown_n].reshape(rings + 1, cols, 3)
    # Height above the band and arc length round it, per crown vertex.
    kk = np.arange(cols)
    kk = np.where(kk > segs // 2, kk - segs, kk).astype(float)  # 0 at the back
    seg_len = np.linalg.norm(grid[0, 1] - grid[0, 0])
    h = grid[..., 1] - grid[0][None, :, 1]
    s = np.broadcast_to(kk * seg_len, h.shape)

    def rho(sv, hv):
        return np.hypot(sv / (OPENING_W / 2), (hv - STRAP_H) / OPENING_H)

    # Triangles whose middle is in the hole go.
    in_crown = (tris < crown_n).all(axis=1)
    ti, tk = np.minimum(tris // cols, rings), tris % cols
    sm = s[ti, tk].mean(axis=1)
    hm = h[ti, tk].mean(axis=1)
    cut = in_crown & (rho(sm, hm) < 1) & (hm > STRAP_H)
    kept = tris[~cut]
    # Vertices of kept triangles that touch the hole move onto its edge,
    # found along their column (k) between them and the strap.
    on_edge = np.zeros(len(pos), bool)
    for t in tris[cut]:
        on_edge[t] = True
    used = np.zeros(len(pos), bool)
    used[kept.reshape(-1)] = True
    pos, nrm = pos.copy(), nrm.copy()
    def sample(sv, hv):
        kf = sv / seg_len
        k0 = int(math.floor(kf))
        f = kf - k0
        c0, c1 = k0 % segs, (k0 + 1) % segs
        col = h[:, c0] * (1 - f) + h[:, c1] * f
        j = int(np.clip(np.searchsorted(col, hv) - 1, 0, rings - 1))
        g = float(np.clip((hv - col[j]) / max(col[j + 1] - col[j], 1e-9), 0, 1))

        def at(arr):
            lo = arr[j, c0] * (1 - f) + arr[j, c1] * f
            hi = arr[j + 1, c0] * (1 - f) + arr[j + 1, c1] * f
            return lo * (1 - g) + hi * g
        n = at(gn)
        return at(grid), n / max(np.linalg.norm(n), 1e-9)

    for v in np.nonzero(on_edge & used & (np.arange(len(pos)) < crown_n))[0]:
        i, k = divmod(int(v), cols)
        sv, hv = float(s[i, k]), float(h[i, k])
        r = max(float(rho(sv, hv)), 1e-6)
        # To whichever edge is nearer: the strap's top or the arch.
        to_strap = hv - STRAP_H
        to_arch = abs(1 - r) * min(OPENING_W / 2, OPENING_H)
        if hv <= STRAP_H or (r < 1 and to_strap < to_arch):
            sv = float(np.clip(sv, -OPENING_W / 2, OPENING_W / 2))
            hv = STRAP_H
        else:
            sv, hv = sv / r, STRAP_H + (hv - STRAP_H) / r
        pos[v], nrm[v] = sample(sv, hv)
    return pos, nrm, kept


def press(pos, grid, centre):
    """Head vertices under the crown that reach past its inside, moved in
    to PRESS_GAP under it (along the ray from the crown's centre)."""
    segs = grid.shape[1]
    r = np.linalg.norm(grid, axis=2)
    dirs = grid / r[..., None]
    rel = pos - centre
    d = np.linalg.norm(rel, axis=1)
    u = rel / np.maximum(d, 1e-9)[:, None]
    flat = dirs.reshape(-1, 3)
    best = np.argmax(u @ flat.T, axis=1)
    ring, seg = best // segs, best % segs
    # Above the band: the elevation over the band's at that azimuth.
    band_el = np.arcsin(np.clip(dirs[0, seg, 1], -1, 1))
    el = np.arcsin(np.clip(u[:, 1], -1, 1))
    inside_cap = (el > band_el - math.radians(4)) | (ring > 0)
    limit = r.reshape(-1)[best] - PRESS_GAP
    over = inside_cap & (d > limit)
    rows = np.nonzero(over)[0]
    offs = (u[rows] * (limit[rows] - d[rows])[:, None]).astype(np.float32)
    return rows.astype(np.int32), offs


def put(blob, a, dtype):
    a = np.ascontiguousarray(a, dtype=dtype)
    while len(blob) % 4:
        blob.append(0)
    off = len(blob)
    blob.extend(a.tobytes())
    return [off, a.nbytes]


def add(info, blob, name):
    """Puts the person's fitted caps in the pack (RB_<name>_cap, the tour
    cap, and RB_<name>_dadcap) and the cap_press shape on their head."""
    caps, rows, offs, marks = fit(info, blob, name)
    head_j = info["bones"].index("head")
    for style_name, (cp, cn, cu, ct) in caps.items():
        n = len(cp)
        # Every cap has the same vertex layout: the first one's uvs, bones
        # and weights serve them all.
        shared = info.setdefault("person_cap_shared", {})
        if shared.get("count") != n:
            shared.clear()
            shared.update({"count": n, "uvs": put(blob, cu, np.float32),
                           "bones": put(blob, np.tile([head_j, 0, 0, 0], (n, 1)), np.int32),
                           "weights": put(blob, np.tile([1.0, 0, 0, 0], (n, 1)), np.float32)})
        info["parts"]["RB_%s_%s" % (name, STYLES[style_name]["part"])] = {
            "material": "Cap", "count": n,
            "positions": put(blob, cp, np.float32), "normals": put(blob, cn, np.float16),
            "uvs": list(shared["uvs"]), "bones": list(shared["bones"]), "weights": list(shared["weights"]),
            # Godot's front faces wind clockwise.
            "indices": put(blob, ct[:, ::-1].reshape(-1), np.int32),
            "tangents": put(blob, look_pack.tangents(cp.astype(np.float64), cn.astype(np.float64),
                                                     cu.astype(np.float64), ct), np.float16),
            "shapes": {},
        }
    head = info["parts"]["RB_%s_head" % name]
    shapes = dict(head.get("shapes", {}))
    shapes.pop("cap_press", None)
    if len(rows):
        shapes["cap_press"] = {"rows": put(blob, rows, np.int32), "positions": put(blob, offs, np.float16)}
    head["shapes"] = shapes
    return marks, len(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default=os.path.join(os.path.dirname(__file__), "../../game/assets/golfer/free_golfer_parts.olg"))
    args = ap.parse_args()
    import upgrade_pack  # noqa: E402  (compact)
    info, blob = golf_shoes.load(args.pack)
    for name in info.get("people", {}):
        marks, pressed = add(info, blob, name)
        print("%s: brim seam %.1f cm under the top, %d head vertices pressed" % (
            name, (marks["top"] - marks["seam"]) * 100, pressed))
    blob = upgrade_pack.compact(info, blob)
    golf_shoes.save(args.pack, info, blob)
    print("pack %d bytes" % os.path.getsize(args.pack))


if __name__ == "__main__":
    main()
