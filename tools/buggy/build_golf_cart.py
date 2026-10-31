#!/usr/bin/env python3
"""Builds the golf buggy model, game/assets/buggy/golf_cart.glb, from code.

    python3 tools/buggy/build_golf_cart.py [out.glb]

A two-seat electric golf cart, modelled to the published dimensions of a
common fleet cart (Club Car Precedent: 2.39 m long, 1.19 m wide, 1.76 m
to the top of the canopy, 1.66 m wheelbase, 0.88 m front and 0.98 m rear
track, 18x8.5-8 tyres, seat about 0.8 m up)
and shaped with smooth lofted panels, lathed tyres with tread blocks and
alloy rims, padded seats, a canopy on four struts, a tinted windscreen,
lights and the running gear underneath. Our own work, released as CC0
like the rest of the free assets.

Godot axes: +y up, front towards -z, the driver on the left (-x). Nodes:
Body (everything that rides on the springs) and four wheels, Wheel_FL,
Wheel_FR, Wheel_RL, Wheel_RR, each centred on its hub with its axle along
x and its outer face towards +x (the left wheels are turned round). The
Godot importer makes the distance LODs.
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "golfer"))
from gltf import FLOAT, UINT, USHORT, Gltf  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "game", "assets", "buggy", "golf_cart.glb")

# Real dimensions (metres). The tests check the built model against these.
LENGTH = 2.39
WIDTH = 1.19
HEIGHT = 1.76
WHEEL_R = 0.2286  # 18 in tyre
TYRE_W = 0.216  # 8.5 in
TRACK_F = 0.44  # half the front track, to the tyre centre
TRACK_R = 0.49
AXLE_F = -0.83
AXLE_R = 0.83  # 1.66 m wheelbase
ROOF_Y = 1.70  # the canopy's middle; its crown reaches HEIGHT


# --- Mesh building -------------------------------------------------------------

class Part:
    """Triangles for one material."""

    def __init__(self):
        self.pos = []
        self.nor = []
        self.idx = []
        self.count = 0

    def add(self, positions, indices, normals=None):
        p = np.asarray(positions, dtype=np.float64).reshape(-1, 3)
        i = np.asarray(indices, dtype=np.int64).reshape(-1, 3)
        if normals is None:
            normals = smooth_normals(p, i)
        self.pos.append(p)
        self.nor.append(np.asarray(normals, dtype=np.float64).reshape(-1, 3))
        self.idx.append(i + self.count)
        self.count += len(p)

    def arrays(self):
        p = np.concatenate(self.pos).astype(np.float32)
        n = np.concatenate(self.nor)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        return p, n.astype(np.float32), np.concatenate(self.idx)


def smooth_normals(p, i):
    n = np.zeros_like(p)
    f = np.cross(p[i[:, 1]] - p[i[:, 0]], p[i[:, 2]] - p[i[:, 0]])
    for k in range(3):
        np.add.at(n, i[:, k], f)
    return n


def grid(P, wrap_cols=False, flip=False):
    """Quads over a rows x cols x 3 array of points."""
    rows, cols = P.shape[:2]
    idx = []
    cmax = cols if wrap_cols else cols - 1
    for r in range(rows - 1):
        for c in range(cmax):
            c2 = (c + 1) % cols
            a, b, d, e = r * cols + c, r * cols + c2, (r + 1) * cols + c, (r + 1) * cols + c2
            idx += [a, d, b, b, d, e] if not flip else [a, b, d, b, e, d]
    return P.reshape(-1, 3), idx


def cap(part, ring, centre, flip=False):
    """A flat fan closing a ring of points."""
    ring = np.asarray(ring)
    pts = np.vstack([ring, centre])
    c = len(ring)
    idx = []
    for k in range(c):
        a, b = k, (k + 1) % c
        idx += [c, a, b] if not flip else [c, b, a]
    n = np.cross(ring[1] - ring[0], ring[2] - ring[0])
    part.add(pts, idx)


def chaikin(poly, n=3, closed=True):
    p = np.asarray(poly, dtype=np.float64)
    for _ in range(n):
        q = []
        m = len(p) if closed else len(p) - 1
        for k in range(m):
            a, b = p[k], p[(k + 1) % len(p)]
            q += [0.75 * a + 0.25 * b, 0.25 * a + 0.75 * b]
        if not closed:
            q = [p[0]] + q + [p[-1]]
        p = np.array(q)
    return p


def resample(poly, n, closed=True):
    p = np.asarray(poly)
    pts = np.vstack([p, p[:1]]) if closed else p
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    t = np.linspace(0, s[-1], n, endpoint=not closed)
    return np.stack([np.interp(t, s, pts[:, k]) for k in range(pts.shape[1])], axis=1)


def loft(part, sections, zs, cap_ends=(True, True)):
    """Sections: closed 2D outlines (same point count) at depths zs."""
    P = np.array([[(x, y, z) for x, y in sec] for sec, z in zip(sections, zs)])
    pts, idx = grid(P, wrap_cols=True)
    part.add(pts, idx)
    if cap_ends[0]:
        ring = P[0]
        cap(part, ring, ring.mean(axis=0), flip=True)
    if cap_ends[1]:
        ring = P[-1]
        cap(part, ring, ring.mean(axis=0))


def lathe_x(part, profile, segs, centre, modulate=None, flip=False):
    """Revolves (axial, radius) points round the x axis through centre."""
    th = np.linspace(0, 2 * math.pi, segs, endpoint=False)
    P = np.zeros((len(profile), segs, 3))
    for r, (w, rad) in enumerate(profile):
        for c, t in enumerate(th):
            rr = rad + (modulate(w, rad, t) if modulate else 0.0)
            P[r, c] = (centre[0] + w, centre[1] + rr * math.cos(t), centre[2] + rr * math.sin(t))
    pts, idx = grid(P, wrap_cols=True, flip=flip)
    part.add(pts, idx)


def superquadric(part, centre, half, e=(0.3, 0.3), rows=14, cols=28, basis=None, warp=None):
    """A rounded box: e near 0 is boxy, 1 is an ellipsoid."""
    def spow(v, p):
        return math.copysign(abs(v) ** p, v)
    P = np.zeros((rows + 1, cols, 3))
    for r in range(rows + 1):
        v = -math.pi / 2 + math.pi * r / rows
        for c in range(cols):
            u = -math.pi + 2 * math.pi * c / cols
            x = half[0] * spow(math.cos(v), e[0]) * spow(math.cos(u), e[1])
            y = half[1] * spow(math.sin(v), e[0])
            z = half[2] * spow(math.cos(v), e[0]) * spow(math.sin(u), e[1])
            q = np.array([x, y, z])
            if warp is not None:
                q = warp(q)
            if basis is not None:
                q = basis @ q
            P[r, c] = q + np.asarray(centre)
    pts, idx = grid(P, wrap_cols=True, flip=True)
    part.add(pts, idx)


def tube(part, path, radius, segs=12, closed_ends=True):
    """A round tube along a polyline (rounded at the bends)."""
    path = np.asarray(path, dtype=np.float64)
    if len(path) > 2:
        path = chaikin(path, 3, closed=False)
    rings = []
    prev_n = None
    for k in range(len(path)):
        t = path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]
        t /= np.linalg.norm(t)
        if prev_n is None:
            a = np.array([0, 1, 0]) if abs(t[1]) < 0.9 else np.array([1, 0, 0])
            n = np.cross(t, a)
        else:
            n = prev_n - t * np.dot(prev_n, t)
        n /= np.linalg.norm(n)
        b = np.cross(t, n)
        prev_n = n
        rings.append([path[k] + radius * (math.cos(a) * n + math.sin(a) * b)
                      for a in np.linspace(0, 2 * math.pi, segs, endpoint=False)])
    P = np.array(rings)
    pts, idx = grid(P, wrap_cols=True, flip=True)
    part.add(pts, idx)
    if closed_ends:
        cap(part, P[0], path[0], flip=False)
        cap(part, P[-1], path[-1], flip=True)


def rot_x(deg):
    a = math.radians(deg)
    return np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])


def rot_y(deg):
    a = math.radians(deg)
    return np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])


# --- The cart --------------------------------------------------------------------

def tub_outline(y0, y1, wl, wu, ys, n=64):
    """A body cross-section: narrow below the fenders, wider above, round top."""
    half = [(0.0, y0), (wl - 0.05, y0), (wl, y0 + 0.05), (wl, ys - 0.04), (wu - 0.03, ys),
            (wu, ys + 0.04), (wu, y1 - 0.08), (wu - 0.1, y1), (0.0, y1)]
    full = half + [(-x, y) for x, y in reversed(half[1:-1])]
    return resample(chaikin(full, 4), n)


def ease(t):
    return math.sqrt(max(0.0, 1.0 - (1.0 - t) ** 2))


def body(paint, black):
    # Front cowl, nose to dash, rounded at the nose and rising to the dash.
    zs = np.concatenate([np.linspace(-1.14, -1.02, 7), np.linspace(-0.99, -0.5, 10)])
    secs = []
    for z in zs:
        t = (z + 1.14) / 0.64
        top = 0.64 + 0.26 * min(1.0, t * 1.15) ** 1.4
        s = ease(min(1.0, (z + 1.14) / 0.12 + 0.12))
        out = tub_outline(0.32, top, 0.31, 0.595, 0.5)
        cy = 0.5 * (0.32 + top)
        secs.append([(x * (0.55 + 0.45 * s), cy + (y - cy) * (0.45 + 0.55 * s)) for x, y in out])
    loft(paint, secs, zs, cap_ends=(False, True))
    # Rear tub under the seat, back to the rear bumper.
    zs = np.concatenate([np.linspace(-0.12, 1.0, 12), np.linspace(1.03, 1.13, 6)])
    secs = []
    for z in zs:
        s = ease(min(1.0, (1.13 - z) / 0.1 + 0.12))
        out = tub_outline(0.32, 0.68, 0.36, 0.595, 0.5)
        cy = 0.5
        secs.append([(x * (0.6 + 0.4 * s), cy + (y - cy) * (0.5 + 0.5 * s)) for x, y in out])
    loft(paint, secs, zs, cap_ends=(True, False))
    # Floor and footwell, rubber mat on top.
    superquadric(black, (0, 0.33, -0.33), (0.5, 0.035, 0.24), (0.2, 0.2))
    # Dash with a glove shelf and cup holders, in black plastic.
    superquadric(black, (0, 0.9, -0.52), (0.52, 0.05, 0.075), (0.35, 0.3))
    for x in (0.12, 0.24):
        lathe_x_y(black, (x, 0.95, -0.52), [(0.035, 0.0), (0.035, -0.04), (0.0, -0.04)])
    # Bumpers.
    superquadric(black, (0, 0.38, -1.135), (0.59, 0.07, 0.06), (0.3, 0.25))
    superquadric(black, (0, 0.38, 1.135), (0.59, 0.07, 0.06), (0.3, 0.25))
    # Rocker steps along the sides.
    for side in (-1, 1):
        superquadric(black, (side * 0.47, 0.34, -0.3), (0.07, 0.03, 0.26), (0.3, 0.3))
    # Seat-back frame and the bag well behind it.
    superquadric(black, (0, 0.86, 0.66), (0.54, 0.2, 0.04), (0.3, 0.3), basis=rot_x(-10))
    superquadric(black, (0, 0.7, 0.98), (0.5, 0.025, 0.14), (0.2, 0.2))


def lathe_x_y(part, centre, profile, segs=16):
    """A small round dish (cup holder, lamp bezel) opening upwards."""
    th = np.linspace(0, 2 * math.pi, segs, endpoint=False)
    P = np.array([[(centre[0] + r * math.cos(t), centre[1] + h, centre[2] + r * math.sin(t)) for t in th]
                  for r, h in profile])
    pts, idx = grid(P, wrap_cols=True)
    part.add(pts, idx)


def seats(vinyl, trim):
    # Bench cushion, piped at the edge.
    superquadric(vinyl, (0, 0.75, 0.24), (0.52, 0.07, 0.26), (0.28, 0.22),
                 warp=lambda q: q + np.array([0, -0.025 * (q[0] / 0.52) ** 2 * (q[1] > 0), 0]))
    superquadric(trim, (0, 0.69, 0.24), (0.54, 0.02, 0.28), (0.2, 0.2))
    # Two backrest pads.
    for x in (-0.26, 0.26):
        superquadric(vinyl, (x, 1.06, 0.58), (0.23, 0.2, 0.06), (0.3, 0.3), basis=rot_x(-12))
    # Hip restraints.
    for side in (-1, 1):
        tube(trim, [(side * 0.53, 0.7, 0.48), (side * 0.57, 0.9, 0.42), (side * 0.57, 0.92, 0.12),
                    (side * 0.55, 0.72, 0.04)], 0.016)


def canopy(roof, frame, glass):
    # Roof: a rounded slab with a crown and a lip.
    superquadric(roof, (0, ROOF_Y, 0.1), (0.6, 0.03, 0.93), (0.18, 0.12), rows=16, cols=48,
                 warp=lambda q: q + np.array([0, (HEIGHT - ROOF_Y - 0.03) * (1 - (q[0] / 0.6) ** 2) * (1 - (q[2] / 0.93) ** 2), 0]))
    # Struts: the front pair bends back above the windscreen.
    for side in (-1, 1):
        x = side * 0.53
        tube(frame, [(x, 0.86, -0.62), (x, 1.4, -0.6), (x * 1.02, 1.63, -0.5), (x * 1.02, ROOF_Y - 0.02, -0.42)], 0.022)
        tube(frame, [(x, 0.66, 0.78), (x, 1.3, 0.8), (x * 1.02, ROOF_Y - 0.02, 0.84)], 0.022)
    # Rear handle bar.
    tube(frame, [(-0.5, 1.2, 0.81), (0.5, 1.2, 0.81)], 0.016)
    # Windscreen, curved and leaning back, with a folding seam.
    cols, rows = 24, 10
    P = np.zeros((rows, cols, 3))
    for r in range(rows):
        v = r / (rows - 1)
        y = 0.94 + v * 0.66
        for c in range(cols):
            u = -1 + 2 * c / (cols - 1)
            P[r, c] = (u * 0.51, y, -0.6 + 0.05 * u * u + 0.07 * v)
    pts, idx = grid(P)
    glass.add(pts, idx)
    tube(frame, [(-0.51, 1.3, -0.565), (0.51, 1.3, -0.565)], 0.008, segs=8)


def steering(trim, chrome):
    col_a = np.array([-0.27, 0.86, -0.52])
    col_b = np.array([-0.27, 1.07, -0.33])
    tube(trim, [col_a, col_b], 0.025)
    # Wheel rim: a torus tilted towards the driver, with three spokes.
    tilt = rot_x(-50)
    centre = col_b + np.array([0, 0.02, 0.02])
    ring = []
    for k in range(40):
        a = 2 * math.pi * k / 40
        ring.append(centre + tilt @ np.array([0.17 * math.cos(a), 0, 0.17 * math.sin(a)]))
    ring.append(ring[0])
    tube(trim, ring, 0.016, segs=10, closed_ends=False)
    for a in (math.pi * 0.5, math.pi * 1.17, math.pi * 1.83):
        tube(trim, [centre, centre + tilt @ np.array([0.16 * math.cos(a), 0, 0.16 * math.sin(a)])], 0.011, segs=8)
    superquadric(chrome, centre, (0.035, 0.012, 0.035), (0.5, 0.5), basis=tilt, rows=6, cols=12)


def lights(chrome, lamp, tail):
    for side in (-1, 1):
        c = np.array([side * 0.34, 0.6, -1.125])
        # Bezel ring and a domed lens, facing forward.
        ring = [c + np.array([0.07 * math.cos(a), 0.07 * math.sin(a), 0]) for a in np.linspace(0, 2 * math.pi, 25)]
        tube(chrome, ring, 0.012, segs=8, closed_ends=False)
        superquadric(lamp, c + np.array([0, 0, -0.005]), (0.062, 0.062, 0.02), (1.0, 1.0), rows=8, cols=20)
        superquadric(tail, (side * 0.44, 0.56, 1.125), (0.06, 0.035, 0.012), (0.4, 0.4), rows=6, cols=16)


def running_gear(black, metal):
    for x in (-0.3, 0.3):
        superquadric(black, (x, 0.27, 0.0), (0.035, 0.045, 1.05), (0.2, 0.2), rows=6, cols=12)
    # Rear axle with the motor and differential; front beam.
    tube(metal, [(-TRACK_R + 0.06, WHEEL_R, AXLE_R), (TRACK_R - 0.06, WHEEL_R, AXLE_R)], 0.035)
    superquadric(metal, (0.0, 0.25, AXLE_R), (0.12, 0.12, 0.12), (0.8, 0.8), rows=10, cols=20)
    tube(metal, [(0.0, 0.27, AXLE_R - 0.1), (0.0, 0.27, AXLE_R - 0.35)], 0.09, segs=16)
    tube(black, [(-TRACK_F + 0.06, WHEEL_R, AXLE_F), (TRACK_F - 0.06, WHEEL_R, AXLE_F)], 0.03)
    # Leaf springs at the back.
    for x in (-0.3, 0.3):
        tube(black, [(x, 0.3, AXLE_R - 0.38), (x, 0.24, AXLE_R), (x, 0.3, AXLE_R + 0.32)], 0.018, segs=8)


def wheel():
    tyre, rim, cap_ = Part(), Part(), Part()
    # Tyre section: (axial, radius), from the inner bead round to the outer.
    sec = []
    for k in range(25):
        a = -math.pi / 2 + math.pi * k / 24
        w = TYRE_W / 2 * math.copysign(abs(math.sin(a)) ** 0.6, math.sin(a))
        r = 0.11 + (WHEEL_R - 0.11) * abs(math.cos(a)) ** 0.35
        sec.append((w, r))

    def tread(w, r, t):
        if r < WHEEL_R - 0.012:
            return 0.0
        block = (t * 30 / (2 * math.pi) + (0.5 if w > 0 else 0.0)) % 1.0
        groove = abs(w) < 0.012
        return -0.0 if (block < 0.62 and not groove) else -0.007

    lathe_x(tyre, sec, 120, (0, 0, 0), modulate=tread)
    # Alloy rim: barrel, dished face with eight spokes, a centre cap and nuts.
    face = [(0.08, 0.112), (0.085, 0.104), (0.087, 0.088), (0.078, 0.048), (0.082, 0.032), (0.09, 0.022), (0.095, 0.0)]

    th = np.linspace(0, 2 * math.pi, 64, endpoint=False)
    P = np.zeros((len(face), len(th), 3))
    for r_, (w, rad) in enumerate(face):
        for c, t in enumerate(th):
            s = (t * 8 / (2 * math.pi)) % 1.0
            dip = -0.018 if (0.035 < rad < 0.095 and s > 0.6) else 0.0
            P[r_, c] = (w + dip, rad * math.cos(t), rad * math.sin(t))
    pts, idx = grid(P, wrap_cols=True)
    rim.add(pts, idx)
    lathe_x(rim, [(-0.08, 0.112), (0.08, 0.112)], 64, (0, 0, 0), flip=True)
    superquadric(cap_, (0.094, 0, 0), (0.01, 0.024, 0.024), (0.6, 0.8), rows=6, cols=16)
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        tube(cap_, [(0.08, 0.038 * math.cos(a), 0.038 * math.sin(a)), (0.094, 0.038 * math.cos(a), 0.038 * math.sin(a))],
             0.008, segs=6)
    return tyre, rim, cap_


def build(path):
    g = Gltf()
    g.doc["asset"]["generator"] = "OpenLinks2003 tools/buggy"
    g.doc["extensionsUsed"] = ["KHR_materials_clearcoat"]

    def mat(name, colour, rough, metal=0.0, clearcoat=0.0, emissive=None, double=False, blend=False):
        m = g.material(name, colour=colour, roughness=rough, metallic=metal, double_sided=double)
        d = g.doc["materials"][m]
        if clearcoat:
            d.setdefault("extensions", {})["KHR_materials_clearcoat"] = {"clearcoatFactor": clearcoat,
                                                                        "clearcoatRoughnessFactor": 0.05}
        if emissive:
            d["emissiveFactor"] = list(emissive)
        if blend:
            d["alphaMode"] = "BLEND"
        return m

    mats = {
        "paint": mat("Paint", (0.9, 0.9, 0.88, 1), 0.3, clearcoat=1.0),
        "roof": mat("Roof", (0.92, 0.92, 0.9, 1), 0.45),
        "black": mat("BlackPlastic", (0.035, 0.035, 0.04, 1), 0.6),
        "frame": mat("Frame", (0.05, 0.05, 0.055, 1), 0.4, metal=0.6),
        "vinyl": mat("Vinyl", (0.36, 0.26, 0.18, 1), 0.5),
        "trim": mat("Trim", (0.06, 0.06, 0.065, 1), 0.45),
        "chrome": mat("Chrome", (0.95, 0.95, 0.95, 1), 0.12, metal=1.0),
        "metal": mat("Metal", (0.3, 0.3, 0.32, 1), 0.55, metal=0.8),
        "glass": mat("Glass", (0.6, 0.68, 0.72, 0.25), 0.04, double=True, blend=True),
        "lamp": mat("Lamp", (1, 1, 0.95, 1), 0.05, emissive=(0.8, 0.78, 0.7)),
        "tail": mat("TailLight", (0.6, 0.03, 0.03, 1), 0.1, emissive=(0.35, 0.0, 0.0)),
        "rubber": mat("Tyre", (0.03, 0.03, 0.03, 1), 0.92),
        "alloy": mat("Alloy", (0.72, 0.73, 0.75, 1), 0.3, metal=1.0),
    }
    parts = {k: Part() for k in ["paint", "roof", "black", "frame", "vinyl", "trim", "chrome", "metal", "glass", "lamp", "tail"]}
    body(parts["paint"], parts["black"])
    seats(parts["vinyl"], parts["trim"])
    canopy(parts["roof"], parts["frame"], parts["glass"])
    steering(parts["trim"], parts["chrome"])
    lights(parts["chrome"], parts["lamp"], parts["tail"])
    running_gear(parts["black"], parts["metal"])

    def mesh(name, items):
        prims = []
        tris = 0
        for key, part in items:
            if part.count == 0:
                continue
            p, n, i = part.arrays()
            itype = USHORT if len(p) < 65536 else UINT
            prims.append({"attributes": {"POSITION": g.accessor(p, FLOAT, 34962, minmax=True),
                                         "NORMAL": g.accessor(n, FLOAT, 34962)},
                          "indices": g.accessor(i.reshape(-1), itype, 34963), "material": mats[key]})
            tris += len(i)
        g.doc["meshes"].append({"name": name, "primitives": prims})
        return len(g.doc["meshes"]) - 1, tris

    body_mesh, body_tris = mesh("Body", list(parts.items()))
    tyre, rim, cap_ = wheel()
    wheel_mesh, wheel_tris = mesh("Wheel", [("rubber", tyre), ("alloy", rim), ("chrome", cap_)])
    root_children = [g.node(name="Body", mesh=body_mesh)]
    half_turn = [0, 1, 0, 0]  # quaternion: 180 degrees about y
    for name, x, z in [("Wheel_FL", -TRACK_F, AXLE_F), ("Wheel_FR", TRACK_F, AXLE_F),
                       ("Wheel_RL", -TRACK_R, AXLE_R), ("Wheel_RR", TRACK_R, AXLE_R)]:
        fields = {"name": name, "mesh": wheel_mesh, "translation": [x, WHEEL_R, z]}
        if x < 0:
            fields["rotation"] = half_turn
        root_children.append(g.node(**fields))
    root = g.node(name="GolfCart", children=root_children)
    g.doc["scenes"][0]["nodes"].append(root)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    g.save(path)
    print("%s: body %d triangles, wheel %d triangles (x4), %d KB" % (
        path, body_tris, wheel_tris, os.path.getsize(path) // 1024))


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else OUT)
