"""The free golfer's clubs, modelled to the size of real ones: a 460 cc
driver, a cavity-back 7-iron and a blade putter with a plumber's neck,
each with a ferrule, a steel shaft and a rubber grip.

The heads were first an ellipsoid and two boxes. They are now signed
distance shapes (tools/buggy/sdf.py) meshed with marching cubes, built in
a head frame:

    x  towards the toe, along the ground at address
    y  out of the face, towards the target (a square face, no loft)
    z  up
    origin  the hosel point: where build_free_golfer.club_parts ends the
            shaft (grip point + shaft direction * club.length)

The driver's and iron's soles sit where the old heads' did; the putter's
is 19 mm lower, since the old box floated about 20 mm above the green.
mocap_swing.py's impact correction then measures the swings against the
new heads.

Sizes, from makers' figures and the rules of golf (see docs/props.md):
- Driver: the rules cap a head at 460 cc inside 127 x 127 x 71 mm. This
  one is about 120 mm heel to toe, 117 mm front to back, a 59 mm deep face,
  10.5 degrees of loft with bulge and roll, and about 455 cc.
- 7-iron: a 73 mm blade, a 50 mm toe, a 7 mm top line, an 18 mm sole,
  34 degrees of loft, and a hosel 64 mm tall.
- Putter: about 100 x 28 x 23 mm, 3 degrees of loft, a plumber's neck
  with about a shaft's width of offset.

mocap_swing.py swaps them into free_golfer.glb (after the grip fit,
before the swings are measured against the heads), so a rebuild of the
golfer keeps them. To swap them alone, leaving the animations as they are:

    python3 tools/golfer/clubs.py [--glb FILE] [--out FILE]

The heads are measured into the same place every time (the grip fit's move
included), so either can be run again.
"""

import argparse
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "buggy"))
import pose  # noqa: E402
from sdf import gradient, mesh as sdf_mesh, smooth_intersect, smooth_union  # noqa: E402

MM = 0.001
# The grip: its radius at the butt and 0.27 m down, as grip.py fits the
# hands to (GRIP_R0, GRIP_R1). A 10.5 in grip with a rounded cap.
GRIP_LEN = 0.27
GRIP_SEGMENTS = 24
SHAFT_SEGMENTS = 12

# Where the sole sits below the hosel point (along z). The driver and iron
# keep the old heads' soles; the putter's comes down to the green.
SOLE = {"Driver": -0.017, "Iron": -0.004, "Putter": -0.019}

# Materials: name -> (linear colour, metallic, roughness). DriverHead is
# the crown, which the player creator paints (player_look club_head).
MATERIALS = {
    "DriverHead": ((0.012, 0.012, 0.014, 1.0), 0.4, 0.22),
    "DriverFace": ((0.26, 0.27, 0.28, 1.0), 1.0, 0.4),
    "DriverSole": ((0.30, 0.31, 0.33, 1.0), 1.0, 0.32),
    "IronHead": ((0.66, 0.67, 0.69, 1.0), 1.0, 0.3),
    "Grooves": ((0.16, 0.16, 0.17, 1.0), 1.0, 0.55),
    "PutterHead": ((0.55, 0.56, 0.58, 1.0), 1.0, 0.42),
    "Ferrule": ((0.01, 0.01, 0.01, 1.0), 0.0, 0.25),
}


def _smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _capsule(a, b, r0, r1=None):
    """A rounded rod from a to b, its radius going from r0 to r1."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    r1 = r0 if r1 is None else r1
    e = b - a
    ee = e @ e

    def f(x, y, z):
        wx, wy, wz = x - a[0], y - a[1], z - a[2]
        t = np.clip((wx * e[0] + wy * e[1] + wz * e[2]) / ee, 0.0, 1.0)
        d = np.sqrt((wx - e[0] * t) ** 2 + (wy - e[1] * t) ** 2 + (wz - e[2] * t) ** 2)
        return d - (r0 + (r1 - r0) * t)
    return f


def _tube(a, b, r0, r1=None):
    """A rod from a to b with flat ends."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    r1 = r0 if r1 is None else r1
    e = b - a
    length = math.sqrt(e @ e)
    u = e / length

    def f(x, y, z):
        wx, wy, wz = x - a[0], y - a[1], z - a[2]
        s = wx * u[0] + wy * u[1] + wz * u[2]
        rad = np.sqrt(np.maximum(wx * wx + wy * wy + wz * wz - s * s, 0.0))
        r = r0 + (r1 - r0) * np.clip(s / length, 0.0, 1.0)
        dr, ds = rad - r, np.abs(s - length / 2) - length / 2
        out = np.sqrt(np.maximum(dr, 0) ** 2 + np.maximum(ds, 0) ** 2)
        return out + np.minimum(np.maximum(dr, ds), 0)
    return f


# --- The heads -------------------------------------------------------------------

def driver_shape(shaft):
    """shaft: the shaft's direction (head to grip) in the head frame."""
    sole = SOLE["Driver"]
    loft = math.radians(10.5)
    tc, fc = 0.047, -0.042  # the middle of the head seen from above

    def plan(x, y):
        # A rounded, pear-ish outline 120 mm heel to toe: fuller at the toe
        # and the back, the heel tucked in.
        u = (x - tc) / np.where(x > tc, 0.061, 0.059)
        v = (y - fc) / np.where(y > fc, 0.066, 0.056 + 0.008 * np.clip((x - tc) / 0.06, -1, 1))
        p = 1.9
        r = (np.abs(u) ** p + np.abs(v) ** p) ** (1 / p)
        return (r - 1.0) * 0.06

    def body(x, y, z):
        # The crown: a dome highest about 30 mm behind the face.
        # The crown: a dome highest about 25 mm behind the face, falling
        # away to a low skirt at the back.
        yy = (y + 0.025) / np.where(y > -0.025, 0.08, 0.086)
        h = sole + 0.002 + 0.056 * np.sqrt(np.clip(1 - yy ** 2 - ((x - tc) / 0.07) ** 2, 0, 1))
        crown = (z - h) * 0.8
        # The sole: a gentle camber, 400 mm radius.
        s = sole + ((x - tc) ** 2 + (y - fc) ** 2) / (2 * 0.4)
        bottom = s - z
        # The face: lofted, with bulge (heel to toe) and roll (top to bottom).
        zc = sole + 0.029
        front = 0.013 - (z - sole) * math.tan(loft) - (x - tc) ** 2 / (2 * 0.305) - (z - zc) ** 2 / (2 * 0.254)
        face = (y - front) * math.cos(loft)
        d = smooth_intersect(0.006, lambda *_: plan(x, y), lambda *_: crown)(x, y, z)
        d = smooth_intersect(0.004, lambda *_: d, lambda *_: bottom)(x, y, z)
        return smooth_intersect(0.0015, lambda *_: d, lambda *_: face)(x, y, z)

    s = pose.unit(shaft)
    # The hosel: up from the heel along the shaft, its top about 52 mm above
    # the sole, where the ferrule starts.
    hosel = _tube(-s * 0.004, s * HOSEL_TOP["Driver"], 0.0072, 0.0064)
    return smooth_union(0.007, body, hosel)


def driver_regions(p):
    """Where each material ends, as functions that are negative inside it:
    the face (up to the rounded edge with the crown), then the sole and
    the lower skirt."""
    sole, loft = SOLE["Driver"], math.radians(10.5)
    tc = 0.047
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    zc = sole + 0.029
    front = 0.013 - (z - sole) * math.tan(loft) - (x - tc) ** 2 / (2 * 0.305) - (z - zc) ** 2 / (2 * 0.254)
    face = np.maximum(-((y - front) * math.cos(loft) + 0.0009), -0.004 - x)
    return [("DriverFace", face), ("DriverSole", z - (sole + 0.0055))]


def iron_shape(shaft):
    sole = SOLE["Iron"]
    loft = math.radians(34.0)
    fn = np.array([0.0, math.cos(loft), math.sin(loft)])  # out of the face
    up = np.array([0.0, -math.sin(loft), math.cos(loft)])  # up the face
    lead = np.array([0.0, 0.004, sole])  # the leading edge, middle of the sole

    def outline(x, h):
        # The blade seen square on, in the face plane (h up the face):
        # 73 mm long, 36 mm tall at the heel rising to 50 mm near the toe,
        # a round toe, a straight sole.
        top = 0.036 + 0.016 * _smoothstep(0.004, 0.06, x)
        top = top / math.cos(loft)
        toe_r = 0.024
        toe_x, toe_h = 0.077 - toe_r, top - toe_r
        d_top = h - (top - 0.004 * ((x - 0.04) / 0.04) ** 2)
        d_bot = -h
        d_heel = 0.0 - x
        # The toe rounds over from the top line down to the sole.
        dx, dh = np.maximum(x - toe_x, 0), np.maximum(h - toe_h, 0)
        d_toe = np.where((dx > 0) & (dh > 0), np.sqrt(dx ** 2 + dh ** 2) - toe_r, x - 0.077)
        return np.maximum(np.maximum(d_top, d_bot), np.maximum(d_heel, d_toe))

    def body(x, y, z):
        q = np.stack([x - lead[0], y - lead[1], z - lead[2]], axis=-1)
        d = -(q @ fn)  # depth behind the face
        h = q @ up
        o = outline(x, h)
        inner = -o
        # Thickness behind the face: a 3 mm face, a raised rim round the
        # cavity, the weight low behind the sole.
        t = 0.0045 + 0.005 * (1 - _smoothstep(0.005, 0.009, inner))
        t = t + 0.017 * (1 - _smoothstep(0.0, 0.022, h)) ** 1.3
        back = d - t
        front = -d
        shape = smooth_intersect(0.0012, lambda *_: o, lambda *_: back)(x, y, z)
        shape = smooth_intersect(0.0008, lambda *_: shape, lambda *_: front)(x, y, z)
        # A flat sole with a little camber from heel to toe.
        s = sole + (x - 0.04) ** 2 / (2 * 0.3)
        return smooth_intersect(0.0015, lambda *_: shape, lambda *_: s - z)(x, y, z)

    s = pose.unit(shaft)
    hosel = _tube(-s * 0.006, s * HOSEL_TOP["Iron"], 0.0074, 0.0066)
    head = smooth_union(0.006, body, hosel)
    return lambda x, y, z: np.maximum(head(x, y, z), sole - z)


def iron_regions(p):
    return []


def iron_grooves():
    """Score lines: dark strips just proud of the face. 0.9 mm wide on a
    3.6 mm pitch, stopping short of the heel and toe."""
    sole, loft = SOLE["Iron"], math.radians(34.0)
    fn = np.array([0.0, math.cos(loft), math.sin(loft)])
    up = np.array([0.0, -math.sin(loft), math.cos(loft)])
    lead = np.array([0.0, 0.004, sole]) + fn * 0.0002
    pos, idx = [], []
    for k in range(10):
        h = 0.0045 + 0.0036 * k
        x0, x1 = 0.012, 0.064 - 0.002 * max(0, k - 6)
        base = len(pos)
        for x, dh in ((x0, 0.0), (x1, 0.0), (x1, 0.0009), (x0, 0.0009)):
            pos.append(lead + np.array([x, 0, 0]) + up * (h + dh))
        idx += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
    pos = np.array(pos)
    nrm = np.tile(fn, (len(pos), 1))
    idx = np.array(idx)
    f = np.cross(pos[idx[:, 1]] - pos[idx[:, 0]], pos[idx[:, 2]] - pos[idx[:, 0]])
    if np.sum(f @ fn) < 0:
        idx = idx[:, [0, 2, 1]]
    return pos, nrm, idx


def putter_shape(shaft):
    sole = SOLE["Putter"]
    loft = math.radians(3.0)
    top = sole + 0.023
    face_y = -0.007  # the face, a shaft's width behind the shaft line
    back_y = face_y - 0.028
    x0, x1 = -0.008, 0.092

    def body(x, y, z):
        # Seen from above: a rounded bar 100 x 28 mm.
        r = 0.005
        qx = np.abs(x - (x0 + x1) / 2) - ((x1 - x0) / 2 - r)
        qy = np.abs(y - (face_y + back_y) / 2) - ((face_y - back_y) / 2 - r)
        plan = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - r
        face = (y - (face_y - (z - sole) * math.tan(loft))) * math.cos(loft)
        d = smooth_intersect(0.001, lambda *_: plan, lambda *_: face)(x, y, z)
        s = sole + (x - 0.042) ** 2 / (2 * 0.9)
        d = smooth_intersect(0.0015, lambda *_: d, lambda *_: s - z)(x, y, z)
        d = smooth_intersect(0.0012, lambda *_: d, lambda *_: z - top)(x, y, z)
        # The cavity behind the face plate, above the flange: 6 mm face
        # plate, 10 mm flange, full-height heel and toe.
        cx = np.abs(x - 0.042) - 0.031
        cy = np.abs(y - (face_y - 0.006 - 0.012)) - 0.0118
        cz = (sole + 0.010) - z
        cav = np.maximum(np.maximum(cx, cy), cz)
        return -smooth_union(0.0025, lambda *_: -d, lambda *_: cav)(x, y, z)

    s = pose.unit(shaft)
    # The plumber's neck: up from the top line near the heel, across to the
    # shaft line (giving the offset), then up into the shaft.
    sock = s * ((top + 0.02 - 0.0) / s[2])
    post0 = np.array([0.006, face_y - 0.004, top - 0.003])
    post1 = np.array([0.006, face_y - 0.004, sock[2]])
    neck = smooth_union(0.002,
                        _capsule(post0, post1, 0.0042),
                        _capsule(post1, sock, 0.0042),
                        _tube(sock, s * HOSEL_TOP["Putter"], 0.0052, 0.0049))
    return smooth_union(0.002, body, neck)


def putter_regions(p):
    return []


# How far up the shaft line (from the hosel point) each hosel ends and the
# ferrule begins.
HOSEL_TOP = {"Driver": 0.046, "Iron": 0.068, "Putter": 0.058}
FERRULE = 0.019
# Where the shaft stops inside the head (along the shaft from the hosel
# point; past the old 0.02 m tail, which poked out under the iron's sole).
SHAFT_TIP = {"Driver": 0.01, "Iron": 0.02, "Putter": 0.045}
HEADS = {
    "Driver": (driver_shape, driver_regions, (-0.03, -0.12, -0.03), (0.12, 0.03, 0.06), 0.0008, 1700),
    "Iron": (iron_shape, iron_regions, (-0.035, -0.04, -0.01), (0.085, 0.02, 0.07), 0.0005, 1100),
    "Putter": (putter_shape, putter_regions, (-0.03, -0.04, -0.025), (0.096, 0.012, 0.05), 0.0005, 800),
}


def head_parts(name, shaft):
    """The head's pieces in the head frame: [(material, pos, nrm, idx)].
    shaft: the shaft direction (head to grip) in that frame."""
    make, regions, lo, hi, step, faces = HEADS[name]
    shape = make(shaft)
    p, n, i = _simplified(shape, lo, hi, step, faces)
    parts = []
    base = {"Driver": "DriverHead", "Iron": "IronHead", "Putter": "PutterHead"}[name]
    for k in range(len(regions(p[:1]))):
        # Cut the triangles along the region's edge, so the edge between
        # two materials is a clean line rather than a row of steps.
        p, i = _split(p, i, lambda q: regions(q)[k][1], shape)
        g = regions(p)[k][1]
        inside = g[i].mean(axis=1) < 0
        parts.append((regions(p[:1])[k][0], p, i[inside]))
        i = i[~inside]
    parts.append((base, p, i))
    out = []
    for m, pp, tris in parts:
        used, remap = np.unique(tris, return_inverse=True)
        out.append((m, pp[used], gradient(shape, pp[used]), remap.reshape(-1, 3)))
    parts = out
    s = pose.unit(shaft)
    a, b = s * HOSEL_TOP[name], s * (HOSEL_TOP[name] + FERRULE)
    side = np.cross(s, [1.0, 0.0, 0.0])
    fp, fn, fi = lathe([(0.0, 0.0), (0.0, 0.0062), (0.003, 0.0063), (FERRULE - 0.003, 0.0052),
                        (FERRULE, 0.0049), (FERRULE, 0.0)], s, side, SHAFT_SEGMENTS)
    parts.append(("Ferrule", fp + a, fn, fi))
    if name == "Iron":
        parts.append(("Grooves",) + iron_grooves())
    return parts


def _split(p, i, g_of, shape):
    """Splits every triangle that g (a function of positions) changes sign
    across, along g = 0, with the new points put back on the surface."""
    g = g_of(p)
    neg = g[i] < 0
    mixed = neg.any(axis=1) & ~neg.all(axis=1)
    keep = [i[~mixed]]
    pts = [p]
    count = len(p)
    cache = {}

    def cross(a, b):
        nonlocal count
        key = (min(a, b), max(a, b))
        if key not in cache:
            t = g[a] / (g[a] - g[b])
            q = p[a] + (p[b] - p[a]) * t
            for _ in range(3):
                d = shape(q[None, 0], q[None, 1], q[None, 2])
                q = q - gradient(shape, q[None])[0] * d[0]
            pts.append(q[None])
            cache[key] = count
            count += 1
        return cache[key]

    new = []
    for tri in i[mixed]:
        s = [g[v] < 0 for v in tri]
        # Rotate so the odd vertex out is first.
        for r in range(3):
            if s[r] != s[(r + 1) % 3] and s[r] != s[(r + 2) % 3]:
                break
        a, b, c = tri[r], tri[(r + 1) % 3], tri[(r + 2) % 3]
        ab, ac = cross(a, b), cross(a, c)
        new += [(a, ab, ac), (ab, b, c), (ab, c, ac)]
    p = np.vstack(pts)
    return p, np.vstack(keep + ([np.array(new)] if new else []))


def _simplified(shape, lo, hi, step, faces):
    import fast_simplification
    # Off the grid by a fraction of a step: flat soles exactly on grid
    # points leave marching cubes with holes.
    lo = np.asarray(lo) + step * 0.371
    p, n, i = sdf_mesh(shape, lo, hi, step, faces)
    for agg in (7, 10):
        if len(i) <= faces * 1.2:
            break
        v, t = fast_simplification.simplify(p.astype(np.float32), i.astype(np.int64),
                                            target_reduction=1.0 - faces / len(i), agg=agg)
        p, i = v.astype(np.float64), t
        for _ in range(4):
            d = shape(p[:, 0], p[:, 1], p[:, 2])
            p = p - gradient(shape, p) * d[:, None]
        f = np.cross(p[i[:, 1]] - p[i[:, 0]], p[i[:, 2]] - p[i[:, 0]])
        i = i[np.linalg.norm(f, axis=1) > 1e-12]
        n = gradient(shape, p)
        f = np.cross(p[i[:, 1]] - p[i[:, 0]], p[i[:, 2]] - p[i[:, 0]])
        if np.sum(f * n[i[:, 0]]) < 0:
            i = i[:, [0, 2, 1]]
    return p, n, i


def volume(parts):
    """The volume (m^3) of a closed mesh split into parts [(pos, idx)]."""
    v = 0.0
    for pos, idx in parts:
        a, b, c = pos[idx[:, 0]], pos[idx[:, 1]], pos[idx[:, 2]]
        v += np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0
    return abs(v)


# --- Grip and shaft --------------------------------------------------------------

def lathe(profile, axis, side, segments, crease=35.0):
    """A surface of revolution, profile [(distance along axis, radius)].
    Normals follow the profile's slope, smoothed between segments unless
    they meet at more than `crease` degrees (the cap, the shaft's steps)."""
    a = pose.unit(axis)
    u = pose.unit(side - a * np.dot(side, a))
    v = np.cross(a, u)
    prof = [q for k, q in enumerate(profile) if k == 0 or q != profile[k - 1]]
    seg_n = []
    for (d0, r0), (d1, r1) in zip(prof, prof[1:]):
        ln = math.hypot(d1 - d0, r1 - r0)
        seg_n.append(np.array([-(r1 - r0) / ln, (d1 - d0) / ln]))  # (along, radial)
    # Rings: one per profile point, two where a crease is.
    rings = []  # (d, r, normal (along, radial), segment it starts)
    for k, (d, r) in enumerate(prof):
        before = seg_n[k - 1] if k > 0 else None
        after = seg_n[k] if k < len(seg_n) else None
        if before is None or after is None:
            rings.append((d, r, before if after is None else after))
        elif np.degrees(np.arccos(np.clip(before @ after, -1, 1))) > crease:
            rings.append((d, r, before))
            rings.append((d, r, after))
        else:
            m = before + after
            rings.append((d, r, m / np.linalg.norm(m)))
    pos, nrm, idx = [], [], []
    for d, r, (na, nr) in rings:
        for s in range(segments):
            th = 2 * math.pi * s / segments
            radial = math.cos(th) * u + math.sin(th) * v
            pos.append(a * d + radial * r)
            nrm.append(pose.unit(a * na + radial * nr))
    for k in range(len(rings) - 1):
        if rings[k][:2] == rings[k + 1][:2]:
            continue  # the two rings of a crease
        for s in range(segments):
            a0 = k * segments + s
            a1 = k * segments + (s + 1) % segments
            b0, b1 = a0 + segments, a1 + segments
            idx += [(a0, b0, a1), (a1, b0, b1)]
    pos, nrm, idx = np.array(pos), np.array(nrm), np.array(idx)
    f = np.cross(pos[idx[:, 1]] - pos[idx[:, 0]], pos[idx[:, 2]] - pos[idx[:, 0]])
    if np.sum(f * nrm[idx[:, 0]]) < 0:
        idx = idx[:, [0, 2, 1]]
    # Drop the degenerate triangles at the cap centres.
    f = np.cross(pos[idx[:, 1]] - pos[idx[:, 0]], pos[idx[:, 2]] - pos[idx[:, 0]])
    return pos, nrm, idx[np.linalg.norm(f, axis=1) > 1e-14]


def grip_profile():
    """A rubber grip, 10.5 in long: the butt cap rounded over, the radius
    that grip.py fits the hands to (13.5 mm at the butt, 10.5 mm 0.27 m
    down), and a short tapered tail onto the shaft."""
    b = -0.085
    prof = [(b - 0.0015, 0.0), (b - 0.0013, 0.006), (b - 0.0006, 0.0108), (b, 0.0128), (b + 0.002, 0.0135)]
    for k in range(1, 5):
        t = k / 4
        prof.append((b + 0.002 + t * (GRIP_LEN - 0.012), 0.0135 - 0.003 * t ** 1.15))
    end = b + GRIP_LEN
    prof += [(end, 0.0104), (end + 0.006, 0.0082), (end + 0.008, 0.0078)]
    return prof


def shaft_profile(length, tip):
    """A steel shaft: 15 mm at the butt (inside the grip) to 9 mm at the
    hosel, stepped down every few inches on its lower half. It ends `tip`
    short of the hosel point, inside the head."""
    start = GRIP_LEN - 0.09
    length = length - tip
    prof = [(start, 0.0075)]
    steps = 4
    lower = start + (length - start) * 0.42
    prof.append((lower, 0.0062))
    for k in range(steps):
        d = lower + (length - lower) * (k + 1) / (steps + 1)
        r = 0.0062 - (0.0062 - 0.0045) * (k + 1) / (steps + 1)
        prof += [(d - 0.003, r + 0.00018), (d, r)]
    prof.append((length, 0.0045))
    return prof


def club_parts(grip, a, toe, f, up, club):
    """Every piece of the club in the rest frame: [(piece, material, pos,
    nrm, idx)]. grip: the grip point; a: the shaft direction (grip to head);
    toe, f, up: the head frame's axes (see the module docstring)."""
    b = np.cross(a, f)
    hosel = grip + a * club.length
    out = []
    p, n, i = lathe(grip_profile(), a, b, GRIP_SEGMENTS)
    out.append(("grip", "Grip", p + grip, n, i))
    p, n, i = lathe(shaft_profile(club.length, SHAFT_TIP[club.name]), a, b, SHAFT_SEGMENTS)
    out.append(("shaft", "Shaft", p + grip, n, i))
    axes = np.column_stack([toe, f, up])
    shaft_local = axes.T @ -a
    for m, p, n, i in head_parts(club.name, shaft_local):
        out.append(("head", m, (axes @ p.T).T + hosel, (axes @ n.T).T, i))
    return out


def frame(poser, club):
    """The grip point, shaft direction and head axes in the rest frame,
    as build_free_golfer.club_parts sets them."""
    grip = poser.grip_rest["l"]
    a = poser.club_dir_rest["l"]
    f = poser.face_rest["l"]
    toe = pose.Poser._toe(a, f, club)
    up = pose.unit(np.cross(toe, f))
    if np.dot(up, a) > 0:
        up = -up
    return grip, a, toe, f, up


# --- Swapping them in the .glb ---------------------------------------------------

def swap(glb, rig):
    """Replaces every club mesh in the .glb with these, in the same place
    (including the grip fit's move). Returns the new meshes' head volumes."""
    import iron

    doc = glb.doc
    p = iron.poser(rig)
    mats = {m["name"]: k for k, m in enumerate(doc["materials"])}
    for name, (colour, metal, rough) in MATERIALS.items():
        m = {"name": name, "pbrMetallicRoughness": {"baseColorFactor": list(colour), "metallicFactor": metal,
                                                    "roughnessFactor": rough}}
        if name in mats:
            doc["materials"][mats[name]] = m
        else:
            doc["materials"].append(m)
            mats[name] = len(doc["materials"]) - 1
    nodes = {n.get("name"): n for n in doc["nodes"]}
    _, rest = rig.world([np.eye(3)] * len(rig.names), rig.offsets[0])
    clubs = {"Driver": pose.DRIVER, "Iron": iron.IRON, "Putter": pose.PUTTER}
    volumes = {}
    for cname, club in clubs.items():
        grip, a, toe, f, up = frame(p, club)
        # Where grip.fit moved the club joint, and its meshes, from the
        # grip point the Poser built them at.
        delta = rest[rig.index["club"]] - grip
        pieces = club_parts(grip, a, toe, f, up, club)
        head = [x for x in pieces if x[0] == "head" and x[1] not in ("Ferrule", "Grooves")]
        volumes[cname] = volume([(x[2], x[4]) for x in head])
        joint, skin = _skin_of(doc, nodes[f"{cname}_head"])
        for piece in ("grip", "shaft", "head"):
            prims = []
            for _, m, pos, nrm, idx in (x for x in pieces if x[0] == piece):
                prims.append(_primitive(glb, pos + delta, nrm, idx, joint, mats[m]))
            node = nodes[f"{cname}_{piece}"]
            doc["meshes"][node["mesh"]] = {"name": f"{cname}_{piece}", "primitives": prims}
    return volumes


def _skin_of(doc, node):
    prim = doc["meshes"][node["mesh"]]["primitives"][0]
    return prim["attributes"]["JOINTS_0"], node["skin"]


def _primitive(glb, pos, nrm, idx, joints_acc, material):
    doc = glb.doc
    joint = int(glb.read(joints_acc)[0][0])
    n = len(pos)
    prim = {"attributes": {
        "POSITION": glb.add(pos, minmax=True),
        "NORMAL": glb.add(nrm),
        "TEXCOORD_0": glb.add(np.zeros((n, 2))),
        "JOINTS_0": glb.add(np.tile([joint, 0, 0, 0], (n, 1)), component=5121),
        "WEIGHTS_0": glb.add(np.tile([1.0, 0, 0, 0], (n, 1)))},
        "indices": glb.add(np.asarray(idx).reshape(-1), component=5125),
        "material": material}
    for k in prim["attributes"].values():
        doc["bufferViews"][doc["accessors"][k]["bufferView"]]["target"] = 34962
    doc["bufferViews"][doc["accessors"][prim["indices"]]["bufferView"]]["target"] = 34963
    return prim


def main():
    import glb_edit
    import mocap_swing

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--glb", default=os.path.join(HERE, "..", "..", "game", "assets", "golfer", "free_golfer.glb"))
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    glb = glb_edit.Glb(args.glb)
    rig = mocap_swing.Rig(glb)
    for name, v in swap(glb, rig).items():
        print(f"{name}: head {v * 1e6:.0f} cc")
    glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
