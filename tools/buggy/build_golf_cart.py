#!/usr/bin/env python3
"""Builds the golf buggy model, game/assets/buggy/golf_cart.glb, from code.

    python3 tools/buggy/build_golf_cart.py [out.glb]

A modern two-seat electric fleet golf cart, to the published dimensions of
a current model (2.38 m long, 1.20 m wide, 1.765 m to the sun top, 1.635 m
wheelbase, 0.89 m front and 0.98 m rear track, 295 mm floorboard, 105 mm
ground clearance, 18x8.5-8 tyres on 8 in rims) and its general shape: a
high rounded cowl with the headlights in pockets at its corners, a bench
seat in beige vinyl with tubular hip restraints, a beige sun top on square
rear posts and round front struts, a folding windscreen, black sills and
bumpers, and a bag well behind the seat. No maker's names or badges. Our
own work, released as CC0 like the rest of the free assets.

The moulded panels are signed distance shapes meshed with marching cubes
(sdf.py; needs scikit-image and fast-simplification from pip), with
ambient occlusion baked into the vertex colours.

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
sys.path.insert(0, os.path.dirname(__file__))
from gltf import FLOAT, UINT, USHORT, Gltf  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "game", "assets", "buggy", "golf_cart.glb")

# Real dimensions (metres). The tests check the built model against these.
LENGTH = 2.38
WIDTH = 1.20
HEIGHT = 1.765
WHEEL_R = 0.2286  # 18 in tyre
TYRE_W = 0.216  # 8.5 in
TRACK_F = 0.445  # half the front track, to the tyre centre
TRACK_R = 0.49
AXLE_F = -0.8175
AXLE_R = 0.8175  # 1.635 m wheelbase
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
#
# Panels are signed distance shapes (sdf.py), drawn the way a modeller works
# from blueprints: an outline from the side, one from above and sometimes one
# from the front, intersected with rounded edges, then wheel arches, light
# pockets and seams cut out. Positions are metres from the middle of the
# wheelbase at ground level.

from sdf import (cyl_x, cyl_y, mesh as sdf_mesh, mirrored_x, poly2d, rbox, rotated_x, side_plan,  # noqa: E402
                 smooth_cut, smooth_union, sphere, union, warped, ambient_occlusion)


def mirror_plan(half):
    """A plan outline from its right half (x >= 0), listed front to back."""
    return [(x, z) for x, z in half] + [(-x, z) for x, z in reversed(half)]


def smooth(poly, n=2):
    return chaikin(poly, n)


def arches(k=0.025):
    return [cyl_x(WHEEL_R, AXLE_F, ARCH_R, 0.30, 0.9, mirror=True),
            cyl_x(WHEEL_R, AXLE_R, ARCH_R, 0.30, 0.9, mirror=True)]


def paint_shape():
    # The rear body: rear fenders, the seat base and the bag deck, seen from
    # the side (z, y) and from above (x, z).
    rear_side = smooth([(0.02, 0.24), (0.02, 0.60), (0.12, 0.645), (0.58, 0.69), (0.97, 0.70),
                        (1.13, 0.68), (1.22, 0.62), (1.28, 0.50), (1.295, 0.36), (1.28, 0.24)])
    rear_plan = smooth(mirror_plan([(0.572, 0.02), (0.575, 0.40), (0.598, 0.56), (0.60, 1.10),
                                    (0.57, 1.25), (0.44, 1.30)]))
    rear = side_plan(rear_side, rear_plan, 0.07)
    # The front cowl: high and rounded, its back face leaning towards the
    # seat, the nose rolling under to the bumper.
    cowl_side = smooth([(-0.60, 0.24), (-0.557, 0.42), (-0.523, 0.60), (-0.505, 0.72), (-0.60, 0.765),
                        (-0.78, 0.82), (-0.905, 0.775), (-0.98, 0.665), (-1.012, 0.525), (-1.0, 0.40),
                        (-0.95, 0.33), (-0.80, 0.24)])
    cowl_plan = smooth(mirror_plan([(0.30, -1.035), (0.47, -1.0), (0.56, -0.93), (0.585, -0.80),
                                    (0.58, -0.49)]))
    cowl = side_plan(cowl_side, cowl_plan, 0.11)
    body = union(rear, cowl)
    for a in arches():
        body = smooth_cut(0.025, body, a)
    # Pockets for the headlights at the front corners, sweeping back along
    # the sides, and for the charging socket.
    pocket = mirrored_x(rotated_x(rbox((0.44, 0.665, -0.925), (0.12, 0.048, 0.085), 0.035), (0.44, 0.665, -0.925), 8))
    body = smooth_cut(0.012, body, pocket)
    # The crease along the rear body, under the seat.
    crease = mirrored_x(rbox((0.60, 0.55, 0.26), (0.03, 0.006, 0.26), 0.005))
    body = smooth_cut(0.006, body, crease)
    return body


def black_shape():
    parts = []
    # Rocker sills along the sides and the floorboard, 295 mm up.
    parts.append(mirrored_x(rbox((0.545, 0.25, -0.02), (0.045, 0.06, 0.56), 0.02)))
    parts.append(rbox((0.0, 0.282, -0.27), (0.54, 0.014, 0.29), 0.008))
    # Kick panel under the dash, leaning back like the cowl's back face.
    parts.append(rotated_x(rbox((0.0, 0.52, -0.545), (0.555, 0.215, 0.025), 0.02), (0.0, 0.52, -0.545), 12))
    # Dash pod with two trays and cup holders, and the centre console.
    dash = rbox((0.0, 0.80, -0.585), (0.575, 0.07, 0.13), 0.045)
    for x in (-0.3, 0.3):
        dash = smooth_cut(0.01, dash, rbox((x, 0.89, -0.60), (0.17, 0.05, 0.075), 0.02))
    for x in (-0.06, 0.06):
        dash = smooth_cut(0.006, dash, cyl_y(x, -0.52, 0.035, 0.80, 0.95))
    parts.append(dash)
    parts.append(rotated_x(rbox((0.0, 0.55, -0.50), (0.17, 0.2, 0.05), 0.03), (0.0, 0.55, -0.50), 12))
    # Headlight housings in the pockets, front bumper and chin, rear bumper.
    parts.append(mirrored_x(rotated_x(rbox((0.43, 0.665, -0.91), (0.105, 0.04, 0.07), 0.03), (0.43, 0.665, -0.91), 8)))
    parts.append(rbox((0.0, 0.335, -0.995), (0.40, 0.05, 0.04), 0.025))
    parts.append(rbox((0.0, 0.28, -0.94), (0.46, 0.04, 0.07), 0.02))
    parts.append(rbox((0.0, 0.33, 1.305), (0.52, 0.06, 0.04), 0.025))
    # Seat back shell, the bag well behind it and the bag rack arms.
    parts.append(rotated_x(rbox((0.0, 0.99, 0.665), (0.535, 0.18, 0.03), 0.02), (0.0, 0.99, 0.665), -18))
    well = rbox((0.0, 0.79, 0.90), (0.46, 0.09, 0.12), 0.03)
    well = smooth_cut(0.01, well, rbox((0.0, 0.86, 0.90), (0.435, 0.1, 0.095), 0.02))
    parts.append(well)
    parts.append(rbox((0.0, 1.06, 0.79), (0.56, 0.018, 0.022), 0.012))
    # Square rear posts from the body to the roof.
    parts.append(mirrored_x(rbox((0.50, 1.19, 0.745), (0.024, 0.50, 0.034), 0.01)))
    # Charging socket cover on the side of the seat base.
    parts.append(mirrored_x(cyl_x(0.52, 0.16, 0.035, 0.565, 0.585)))
    # Grab handle on the dash, passenger side.
    return union(*parts)


def vinyl_shape():
    cushion = rbox((0.0, 0.745, 0.30), (0.53, 0.075, 0.26), 0.065)
    cushion = smooth_cut(0.008, cushion, rbox((0.0, 0.83, 0.30), (0.004, 0.03, 0.3), 0.003))
    back_c = (0.0, 1.0, 0.615)
    back = rotated_x(rbox(back_c, (0.52, 0.175, 0.06), 0.06), back_c, -18)
    back = smooth_cut(0.08, back, sphere((0.0, 1.26, 0.70), 0.12))
    back = smooth_cut(0.006, back, rotated_x(rbox((0.0, 1.0, 0.56), (0.004, 0.2, 0.02), 0.003), back_c, -18))
    return smooth_union(0.01, cushion, back)


ROOF_TOP = 1.765  # overall height with the sun top


def roof_shape():
    crown = 0.012

    def dy(x, z):
        return crown * (1.0 - (x / 0.6) ** 2) * (1.0 - ((z - 0.122) / 0.85) ** 2)
    shell = rbox((0.0, ROOF_TOP - 0.03 - crown, 0.122), (0.60, 0.03, 0.846), 0.025)
    shell = smooth_cut(0.01, shell, rbox((0.0, ROOF_TOP - 0.07 - crown, 0.122), (0.565, 0.03, 0.81), 0.01))
    return warped(shell, dy)


def tubes(black, chrome, glass, lamp, amber, tail):
    for s in (-1, 1):
        # Front struts, round, from the cowl up to the roof.
        tube(black, [(s * 0.545, 0.76, -0.60), (s * 0.535, 0.90, -0.548), (s * 0.525, ROOF_TOP - 0.05, -0.37)], 0.017)
        # Windscreen side rails, a little further forward.
        tube(black, [(s * 0.555, 0.74, -0.70), (s * 0.545, ROOF_TOP - 0.05, -0.50)], 0.011, segs=8)
        # Hip restraints round the ends of the seat.
        tube(black, [(s * 0.565, 0.70, 0.66), (s * 0.575, 0.95, 0.60), (s * 0.58, 0.955, 0.16),
                     (s * 0.575, 0.90, 0.07), (s * 0.565, 0.70, 0.05)], 0.018)
        # Headlight lens and an amber marker along the side of the pocket.
        superquadric(lamp, (s * 0.43, 0.665, -0.985), (0.042, 0.042, 0.02), (1.0, 1.0), rows=8, cols=20)
        ring = [np.array((s * 0.43, 0.665, -0.99)) + np.array([0.05 * math.cos(a), 0.05 * math.sin(a), 0])
                for a in np.linspace(0, 2 * math.pi, 25)]
        tube(chrome, ring, 0.006, segs=6, closed_ends=False)
        superquadric(amber, (s * 0.555, 0.655, -0.88), (0.012, 0.012, 0.06), (0.4, 0.4), rows=6, cols=12)
        superquadric(tail, (s * 0.44, 0.56, 1.296), (0.05, 0.03, 0.01), (0.4, 0.4), rows=6, cols=12)
    # Windscreen: two panes on a fold, with the hinge bar between.
    def rail(t, s):
        a = np.array((s * 0.55, 0.74, -0.70))
        b = np.array((s * 0.545, ROOF_TOP - 0.05, -0.50))
        return a + (b - a) * t
    for t0, t1 in ((0.2, 0.52), (0.53, 0.86)):
        rows, cols = 4, 12
        P = np.zeros((rows, cols, 3))
        for r in range(rows):
            t = t0 + (t1 - t0) * r / (rows - 1)
            a, b = rail(t, -1), rail(t, 1)
            for c in range(cols):
                P[r, c] = a + (b - a) * c / (cols - 1) + np.array([0, 0, 0.006])
        pts, idx = grid(P)
        glass.add(pts, idx)
    tube(black, [rail(0.525, -1), rail(0.525, 1)], 0.008, segs=8)
    tube(black, [rail(0.87, -1), rail(0.87, 1)], 0.009, segs=8)
    # Mirror under the front of the roof, on a bar between the struts.
    tube(black, [(-0.53, ROOF_TOP - 0.09, -0.42), (0.53, ROOF_TOP - 0.09, -0.42)], 0.012, segs=8)
    superquadric(black, (0.0, ROOF_TOP - 0.15, -0.43), (0.11, 0.035, 0.012), (0.3, 0.3), rows=6, cols=16)
    # Badge on the nose: a plain metal disc.
    superquadric(chrome, (0.0, 0.70, -1.0), (0.035, 0.035, 0.008), (1.0, 1.0), rows=8, cols=20,
                 basis=rot_x(-35))


def steering(black, chrome):
    a = np.array([-0.27, 0.80, -0.36])
    b = np.array([-0.27, 1.07, -0.04])
    tube(black, [a, b], 0.022)
    axis = (b - a) / np.linalg.norm(b - a)
    # The wheel's plane is square to the column.
    u = np.array([1.0, 0.0, 0.0])
    v = np.cross(axis, u)
    centre = b + axis * 0.02
    ring = [centre + 0.185 * (math.cos(t) * u + math.sin(t) * v) for t in np.linspace(0, 2 * math.pi, 49)]
    tube(black, ring, 0.02, segs=12, closed_ends=False)
    for t in (math.pi * 0.0, math.pi * 1.0, math.pi * 1.5):
        tube(black, [centre, centre + 0.175 * (math.cos(t) * u + math.sin(t) * v)], 0.014, segs=8)
    superquadric(black, centre + axis * 0.01, (0.06, 0.06, 0.03), (0.5, 0.5), rows=8, cols=16,
                 basis=np.stack([u, v, axis], axis=1))


def running_gear(black, metal):
    for x in (-0.3, 0.3):
        superquadric(black, (x, 0.2, 0.05), (0.035, 0.045, 1.0), (0.2, 0.2), rows=6, cols=12)
    # Rear axle with the motor and differential; front struts and wishbones.
    tube(metal, [(-TRACK_R + 0.06, WHEEL_R, AXLE_R), (TRACK_R - 0.06, WHEEL_R, AXLE_R)], 0.035)
    superquadric(metal, (0.0, 0.24, AXLE_R), (0.12, 0.12, 0.12), (0.8, 0.8), rows=10, cols=20)
    tube(metal, [(0.0, 0.25, AXLE_R - 0.1), (0.0, 0.25, AXLE_R - 0.36)], 0.09, segs=16)
    for s in (-1, 1):
        tube(metal, [(s * (TRACK_F - 0.07), WHEEL_R + 0.02, AXLE_F), (s * 0.36, 0.56, AXLE_F + 0.03)], 0.025, segs=10)
        tube(black, [(s * (TRACK_F - 0.07), WHEEL_R - 0.03, AXLE_F), (s * 0.12, 0.2, AXLE_F)], 0.015, segs=8)


def wheel():
    tyre, rim, nuts = Part(), Part(), Part()
    bead = 0.1016  # 8 in rim
    sec = []
    for k in range(29):
        a = -math.pi / 2 + math.pi * k / 28
        w = TYRE_W / 2 * math.copysign(abs(math.sin(a)) ** 0.45, math.sin(a))
        r = bead + 0.005 + (WHEEL_R - bead - 0.005) * abs(math.cos(a)) ** 0.28
        sec.append((w, r))

    def tread(w, r, t):
        if r < WHEEL_R - 0.03:
            return 0.0
        # Two rows of chunky blocks, staggered, with a zigzag centre groove.
        n = 26
        f = (t * n / (2 * math.pi) + (0.5 if w > 0 else 0.0)) % 1.0
        centre = abs(w) < 0.01 + 0.006 * abs(f - 0.5)
        shoulder = abs(w) > TYRE_W / 2 - 0.02 and (t * n * 2 / (2 * math.pi)) % 1.0 > 0.55
        return -0.008 if (f > 0.7 or centre or shoulder) else 0.0

    lathe_x(tyre, sec, 156, (0, 0, 0), modulate=tread)
    # Steel rim: barrel, a dished centre with four nuts and a cap.
    # A flange at the bead, then the face dished in a little to the hub.
    face = [(0.095, bead + 0.008), (0.1, bead - 0.002), (0.098, 0.09), (0.088, 0.08), (0.082, 0.062),
            (0.082, 0.032), (0.09, 0.022), (0.09, 0.0)]
    lathe_x(rim, face, 48, (0, 0, 0), flip=True)
    superquadric(rim, (0.09, 0, 0), (0.012, 0.03, 0.03), (0.6, 0.8), rows=6, cols=16)
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        superquadric(nuts, (0.086, 0.047 * math.cos(a), 0.047 * math.sin(a)), (0.008, 0.009, 0.009), (0.3, 0.8),
                     rows=4, cols=6)
    return tyre, rim, nuts


ARCH_R = 0.30


def build(path):
    g = Gltf()
    g.doc["asset"]["generator"] = "OpenLinks2003 tools/buggy"
    g.doc["extensionsUsed"] = ["KHR_materials_clearcoat"]

    def mat(name, colour, rough, metal=0.0, clearcoat=0.0, emissive=None, double=False, blend=False):
        m = g.material(name, colour=colour, roughness=rough, metallic=metal, double_sided=double)
        d = g.doc["materials"][m]
        if clearcoat:
            d.setdefault("extensions", {})["KHR_materials_clearcoat"] = {"clearcoatFactor": clearcoat,
                                                                        "clearcoatRoughnessFactor": 0.08}
        if emissive:
            d["emissiveFactor"] = list(emissive)
        if blend:
            d["alphaMode"] = "BLEND"
        return m

    mats = {
        # A slate blue-grey metallic, the beige of the seats and sun top,
        # and textured black plastics.
        "paint": mat("Paint", (0.15, 0.19, 0.24, 1), 0.3, metal=0.3, clearcoat=1.0),
        "roof": mat("SunTop", (0.4, 0.36, 0.29, 1), 0.75),
        "black": mat("BlackPlastic", (0.03, 0.03, 0.033, 1), 0.65),
        "vinyl": mat("Vinyl", (0.48, 0.42, 0.33, 1), 0.6),
        "chrome": mat("Chrome", (0.9, 0.9, 0.9, 1), 0.15, metal=1.0),
        "metal": mat("Metal", (0.12, 0.12, 0.13, 1), 0.6, metal=0.5),
        "glass": mat("Glass", (0.75, 0.8, 0.82, 0.18), 0.04, double=True, blend=True),
        "lamp": mat("Lamp", (0.95, 0.95, 0.92, 1), 0.05, emissive=(0.5, 0.5, 0.46)),
        "tail": mat("TailLight", (0.55, 0.03, 0.02, 1), 0.15, emissive=(0.3, 0.0, 0.0)),
        "amber": mat("Amber", (0.9, 0.45, 0.05, 1), 0.2, emissive=(0.25, 0.1, 0.0)),
        "rubber": mat("Tyre", (0.035, 0.035, 0.035, 1), 0.9),
        "rim": mat("SteelRim", (0.025, 0.025, 0.028, 1), 0.4, metal=0.4, double=True),
        "nuts": mat("WheelNuts", (0.6, 0.6, 0.62, 1), 0.3, metal=1.0),
    }
    shapes = {"paint": paint_shape(), "black": black_shape(), "vinyl": vinyl_shape(), "roof": roof_shape()}
    boxes = {"paint": ((-0.63, 0.2, -1.06), (0.63, 0.86, 1.33), 0.006, 30000),
             "black": ((-0.63, 0.2, -1.06), (0.63, 1.72, 1.37), 0.006, 22000),
             "vinyl": ((-0.58, 0.64, 0.0), (0.58, 1.22, 0.75), 0.006, 9000),
             "roof": ((-0.63, 1.6, -0.76), (0.63, 1.78, 1.0), 0.008, 5000)}
    parts = {k: Part() for k in ["paint", "black", "vinyl", "roof", "chrome", "metal", "glass", "lamp", "amber", "tail"]}
    for key, (lo, hi, step, faces) in boxes.items():
        p, n, i = sdf_mesh(shapes[key], lo, hi, step, faces)
        parts[key].add(p, i, n)
    tubes(parts["black"], parts["chrome"], parts["glass"], parts["lamp"], parts["amber"], parts["tail"])
    steering(parts["black"], parts["chrome"])
    running_gear(parts["black"], parts["metal"])

    solid = union(*shapes.values())
    wheels = [cyl_x(WHEEL_R, z, WHEEL_R, x - TYRE_W / 2, x + TYRE_W / 2)
              for x in (-TRACK_F, TRACK_F) for z in (AXLE_F,)] + \
             [cyl_x(WHEEL_R, AXLE_R, WHEEL_R, x - TYRE_W / 2, x + TYRE_W / 2) for x in (-TRACK_R, TRACK_R)]

    def scene(x, y, z):
        d = np.minimum(solid(x, y, z), y)  # the ground too
        for w in wheels:
            d = np.minimum(d, w(x, y, z))
        return d

    def mesh(name, items, ao):
        prims = []
        tris = 0
        for key, part in items:
            if part.count == 0:
                continue
            p, n, i = part.arrays()
            attrs = {"POSITION": g.accessor(p, FLOAT, 34962, minmax=True), "NORMAL": g.accessor(n, FLOAT, 34962)}
            if ao and key != "glass" and not os.environ.get("NOAO"):
                a = ambient_occlusion(scene, p.astype(np.float64), n.astype(np.float64))
                col = np.stack([a, a, a, np.ones_like(a)], axis=1).astype(np.float32)
                attrs["COLOR_0"] = g.accessor(col, FLOAT, 34962)
            itype = USHORT if len(p) < 65536 else UINT
            prims.append({"attributes": attrs, "indices": g.accessor(i.reshape(-1), itype, 34963),
                          "material": mats[key]})
            tris += len(i)
        g.doc["meshes"].append({"name": name, "primitives": prims})
        return len(g.doc["meshes"]) - 1, tris

    body_mesh, body_tris = mesh("Body", list(parts.items()), True)
    tyre, rim, nuts = wheel()
    wheel_mesh, wheel_tris = mesh("Wheel", [("rubber", tyre), ("rim", rim), ("nuts", nuts)], False)
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
