#!/usr/bin/env python3
"""Builds the player's stand bag, game/assets/props/stand_bag.glb, and its
light version stand_bag_lite.glb (low quality and the Web build).

    python3 tools/props/build_stand_bag.py [out_dir]

A modern lightweight stand bag of the "players" kind, modelled from photos
Michael sent of a black and red tour-brand stand bag (2026-11-02) and the
maker's published size for that model: 34.8 in (88.4 cm) tall, an 8.5 in
(21.6 cm) top cuff and a 9.1 in (23.1 cm) base, a 4-way top, about 2.4 kg.
Black polyester with red piping on the panel seams, a padded round cuff
with a moulded carry handle across it, grey hinge blocks under the cuff for
the two red legs, a rubber-soled base with a row of rivets, a big ball
pocket on the front, a long side pocket, a mesh hip pad at the back, buckles
for the double strap, and a chrome towel ring.

No maker's names, wordmarks or logos: the repo is public. The side panel
that carries the maker's script on the real bag is left plain black, with
the red piping only, and the woven label on the front is a blank white tab.

It stands as a stand bag does on the ground: leaning back about 20 degrees
on its two legs, which splay out behind it. In it are a driver, a 3-wood and
a hybrid under headcovers, nine irons (4 to PW and two wedges) with their
heads up, and a putter under a mallet cover, each at its real length.

Axes as Godot: +y up, the front of the bag (the ball pocket) towards +z,
legs towards -z, the origin on the ground under the foot.
"""

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_props as bp  # noqa: E402
from build_props import (Prop, box, capsule, cut, ellipsoid, inter, oval_column, shell,  # noqa: E402
                         slab, torus_y, turned)
from build_golf_cart import Part, superquadric, tube  # noqa: E402
from sdf import rbox, smooth_union, sphere, union  # noqa: E402

OUT = bp.OUT

H = 0.884     # bag height, 34.8 in
A = 0.112     # body half width (x) at the foot: a 9.1 in (23.1 cm) base with the side pocket
B = 0.098     # body half depth (z)
TAPER = 0.06  # narrows to the 8.5 in (21.6 cm) cuff
TILT = 20.0   # degrees it leans back on its legs
LEG_R = 0.0065  # 13 mm legs
LEG_LEN = 0.80
CUFF_Y = 0.835  # the cuff's foot
INCH = 0.0254


def tilt_matrix():
    a = math.radians(-TILT)
    return np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])


# It leans back about a point a little behind the middle of the foot: the
# real base is a wedge, its sole flat on the ground with the front lifted.
PIVOT = np.array([0.0, 0.0, -0.03])


def to_world(p):
    """A point of the upright bag to where it is, leaning on its legs."""
    p = np.asarray(p, dtype=np.float64).reshape(-1, 3)
    return (tilt_matrix() @ (p - PIVOT).T).T + PIVOT


def ground_up(x, y, z):
    return -y


class Bag:
    """Shapes are given upright; this leans them back and meshes them."""

    def __init__(self, name, lite):
        self.pr = Prop(name)
        self.lite = lite
        self.k = 0.07 if lite else 0.42

    def shape(self, key, s, lo, hi, step, faces):
        if self.lite:
            step *= 1.6
        world = turned(s, tuple(PIVOT), "x", -TILT)
        world = inter(world, ground_up)  # the wedge: nothing below the ground
        corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
        w = to_world(corners)
        self.pr.shape(key, world, w.min(axis=0) - 0.01, w.max(axis=0) + 0.01, step, max(int(faces * self.k), 60))

    def mesh(self, key, build):
        """Mesh parts (tubes, superquadrics) built upright by build(part)."""
        part = Part()
        build(part)
        if part.count == 0:
            return
        p, n, i = part.arrays()
        m = tilt_matrix()
        self.pr.parts[key].add(to_world(p), i, (m @ n.T).T)


def surface_point(shape, p, out=0.0):
    """Walks a point onto the shape's surface, then `out` along its normal."""
    p = np.asarray(p, dtype=np.float64).reshape(-1, 3)
    for _ in range(12):
        d = shape(p[:, 0], p[:, 1], p[:, 2])
        p = p - bp.gradient(shape, p) * d[:, None]
    return p + bp.gradient(shape, p) * out


def oval_at(y, th, grow=0.0):
    t = np.clip(y / H, 0, 1)
    s = 1.0 - TAPER * t
    return np.array([(A * s + grow) * math.cos(th), y, (B * s + grow) * math.sin(th)])


def piping(bag, key, shape, path, r=0.0034, segs=7):
    """A red piping cord along the seam through these upright points."""
    pts = surface_point(shape, path, out=r * 0.6)
    bag.mesh(key, lambda part: tube(part, pts[::3] if bag.lite else pts, r, segs=segs if not bag.lite else 4))


def build(out, lite=False):
    bp.FACES = 1.0  # the budgets below are the high-res model's own
    name = "stand_bag_lite" if lite else "stand_bag"
    bag = Bag(name, lite)
    pr = bag.pr
    # Colours (sRGB) picked from the photos.
    pr.material("fabric", (0.058, 0.058, 0.064, 1), 0.94)
    pr.material("mesh", (0.085, 0.085, 0.09, 1), 0.97)
    pr.material("red", (0.70, 0.035, 0.05, 1), 0.6)
    pr.material("rubber", (0.045, 0.045, 0.048, 1), 0.62)
    pr.material("plastic", (0.20, 0.20, 0.21, 1), 0.45)
    pr.material("legs", (0.70, 0.06, 0.08, 1), 0.32, metal=0.55)
    pr.material("chrome", (0.88, 0.88, 0.89, 1), 0.28, metal=0.75)
    pr.material("cover", (0.055, 0.055, 0.06, 1), 0.55, clearcoat=0.15)
    pr.material("white", (0.90, 0.90, 0.88, 1), 0.6)
    pr.material("grip", (0.06, 0.06, 0.065, 1), 0.75)

    # --- The body ---------------------------------------------------------
    tube_ = oval_column(A, B, 0.05, CUFF_Y + 0.01, 0.025, taper=TAPER)
    # The big ball pocket on the front: a rounded block from just above the
    # foot to half way up, standing 6 cm proud, its top cut flat.
    ball = rbox((0.0, 0.30, B + 0.01), (0.072, 0.19, 0.05), 0.035)
    pouch = rbox((0.0, 0.52, B * 0.96 - 0.012), (0.06, 0.05, 0.03), 0.025)  # small pouch above it
    # The long side pocket down the right (+x), where the real bag has its
    # maker's script; plain here.
    side = rbox((A - 0.01, 0.38, 0.01), (0.03, 0.30, 0.085), 0.04)
    # The left side's apparel pocket, flatter.
    left = rbox((-A + 0.012, 0.36, -0.005), (0.022, 0.26, 0.075), 0.035)
    body = smooth_union(0.02, tube_, ball, pouch, side, left)
    lo, hi = (-0.17, 0.03, -0.14), (0.17, 0.86, 0.19)
    bag.shape("fabric", body, lo, hi, 0.0035, 26000)

    # The mesh hip pad at the back, between the legs, a panel stitched on
    # proud of the body from about 45 to 78 cm up.
    hip = inter(shell(body, 0.002, 0.008), box((-0.075, 0.47, -0.3), (0.075, 0.79, -0.04)))
    bag.shape("mesh", hip, (-0.1, 0.45, -0.14), (0.1, 0.81, -0.0), 0.0025, 3000)

    # Red piping: the side pocket's seam, which runs down the back edge of
    # the right side from the cuff, sweeps forward across it, then down the
    # front edge to the foot (as in the side photo); the ball pocket's top
    # seam; a seam on the left; and round the hip pad.
    def p_at(y, deg, grow=0.03):
        return oval_at(y, math.radians(deg), grow)
    right = [p_at(0.82, -55), p_at(0.70, -50), p_at(0.62, -40), p_at(0.52, -5), p_at(0.45, 22),
             p_at(0.36, 32), p_at(0.22, 34), p_at(0.09, 34)]
    piping(bag, "red", body, smooth_path(right, 3))
    zip_ = [p_at(0.56, -30), p_at(0.50, 0), p_at(0.40, 18), p_at(0.25, 20), p_at(0.10, 18)]
    piping(bag, "red", body, smooth_path(zip_, 3))
    left_seam = [p_at(0.80, 230), p_at(0.62, 215), p_at(0.50, 165), p_at(0.30, 150), p_at(0.10, 148)]
    piping(bag, "red", body, smooth_path(left_seam, 3))
    hip_edge = [(-0.06, 0.48, -0.2), (-0.075, 0.62, -0.2), (-0.075, 0.78, -0.2)]
    piping(bag, "red", body, smooth_path(hip_edge, 3))
    if not lite:
        ball_top = [(-0.075, 0.47, B + 0.1), (0.0, 0.49, B + 0.1), (0.075, 0.47, B + 0.1)]
        piping(bag, "red", body, smooth_path(ball_top, 3), r=0.0022)

    # The base: a moulded foot, its rubber sole flaring a little, and a ring
    # of rivets holding the fabric skirt to it.
    foot = oval_column(A + 0.008, B + 0.012, 0.0, 0.075, 0.02)
    sole = oval_column(A + 0.012, B + 0.016, 0.0, 0.022, 0.009)
    bag.shape("rubber", union(cut(foot, box((-1, 0.022, -1), (1, 1, 1))), sole), (-0.15, -0.01, -0.13),
              (0.15, 0.08, 0.13), 0.003, 5000)
    bag.shape("fabric", cut(foot, box((-1, -1, -1), (1, 0.022, 1))), (-0.15, 0.0, -0.13), (0.15, 0.09, 0.13),
              0.0035, 4000)
    if not lite:
        rivets = []
        for k in range(14):
            th = 2 * math.pi * k / 14
            q = np.array([(A + 0.0105) * math.cos(th), 0.045, (B + 0.0145) * math.sin(th)])
            q[1] = 0.04
            rivets.append(sphere(tuple(q), 0.0042))
        bag.shape("chrome", union(*rivets), (-0.15, 0.02, -0.14), (0.15, 0.06, 0.14), 0.0011, 2600)

    # The cuff: a padded oval roll round the mouth, mesh-covered, with the
    # 4-way dividers inside, and the moulded handle arching over the front.
    ca, cb = A * (1 - TAPER) + 0.003, B * (1 - TAPER) + 0.003

    def cuff_roll(x, y, z):
        q = np.sqrt((x / ca) ** 2 + (z / cb) ** 2)
        rad = (q - 1.0) * min(ca, cb)
        return np.sqrt(rad ** 2 + (y - H + 0.018) ** 2) - 0.018
    collar = cut(oval_column(ca + 0.004, cb + 0.004, CUFF_Y - 0.01, H - 0.012, 0.01, taper=0.0),
                 oval_column(ca - 0.012, cb - 0.012, CUFF_Y - 0.1, H + 0.1, 0.0))
    bag.shape("mesh", union(cuff_roll, collar), (-0.14, 0.8, -0.13), (0.14, 0.92, 0.13), 0.0025, 9000)
    # Dividers: one across, one front to back in the back half, the floor.
    divs = union(box((-ca + 0.01, H - 0.05, 0.012), (ca - 0.01, H - 0.012, 0.022), 0.004),
                 box((-ca + 0.01, H - 0.05, -0.048), (ca - 0.01, H - 0.012, -0.038), 0.004),
                 box((-0.005, H - 0.05, -0.04), (0.005, H - 0.014, 0.015), 0.004),
                 box((-ca, H - 0.11, -cb), (ca, H - 0.1, cb)))
    bag.shape("rubber", divs, (-0.13, 0.75, -0.12), (0.13, 0.9, 0.12), 0.002, 3000)
    # The handle: a flat moulded bar on two posts, across the front of the cuff.
    hz = cb - 0.005
    handle = union(capsule((-0.055, H + 0.045, hz), (0.055, H + 0.045, hz), 0.011),
                   capsule((-0.075, H - 0.01, hz - 0.005), (-0.055, H + 0.045, hz), 0.010),
                   capsule((0.075, H - 0.01, hz - 0.005), (0.055, H + 0.045, hz), 0.010))
    handle = inter(handle, slab((0, 0, hz), (0, 0, 1), 0.007))
    bag.shape("rubber", handle, (-0.1, H - 0.03, hz - 0.03), (0.1, H + 0.07, hz + 0.03), 0.0018, 3000)

    # The leg hinges: two grey moulded blocks under the back of the cuff.
    hinge_y = CUFF_Y - 0.03
    hinges = []
    for sx in (-1, 1):
        c = (sx * 0.062, hinge_y, -cb - 0.008)
        hinges.append(rbox(c, (0.022, 0.035, 0.018), 0.009))
    bag.shape("plastic", union(*hinges), (-0.11, hinge_y - 0.06, -0.15), (0.11, hinge_y + 0.06, -0.06), 0.002, 3000)

    # Buckles for the double strap, the webbing grab loop and the blank
    # woven label on the front; the towel ring on the left.
    if not lite:
        buckles = [rbox((sx * 0.05, 0.64, B + 0.002), (0.016, 0.012, 0.006), 0.003) for sx in (-1, 1)]
        loop = capsule((0.0, 0.70, B * 0.97 + 0.004), (0.0, 0.80, B * 0.95 + 0.004), 0.009)
        loop = inter(loop, slab((0, 0, B * 0.96 + 0.004), (0, 0, 1), 0.003))
        bag.shape("rubber", union(*buckles, loop), (-0.09, 0.6, B - 0.04), (0.09, 0.83, B + 0.04), 0.0015, 2500)
        label = rbox((0.0, 0.822, B * (1 - TAPER) + 0.004), (0.02, 0.006, 0.0015), 0.001)
        bag.shape("white", label, (-0.05, 0.8, B - 0.03), (0.05, 0.85, B + 0.03), 0.0008, 400)
        ring_c = (-ca - 0.02, 0.80, 0.03)
        ring = turned(torus_y(ring_c, 0.016, 0.0025), ring_c, "z", 90)
        bag.shape("chrome", ring, (-0.17, 0.76, -0.01), (-0.09, 0.84, 0.07), 0.0009, 1200)

    # --- The clubs --------------------------------------------------------
    clubs(bag, lite)

    # --- The legs (built where they stand, not leaned) --------------------
    def legs(part):
        for sx in (-1, 1):
            h = to_world([sx * 0.062, hinge_y - 0.02, -cb - 0.02])[0]
            foot_x = sx * 0.21
            reach = LEG_LEN ** 2 - h[1] ** 2 - (foot_x - h[0]) ** 2
            foot_z = h[2] - math.sqrt(max(reach, 0.01))
            f = np.array([foot_x, 0.012, foot_z])
            d = (f - h) / np.linalg.norm(f - h)
            tube(part, [h, f - d * 0.05], LEG_R, segs=12 if not lite else 6)
    legs_part = Part()
    legs(legs_part)
    p, n, i = legs_part.arrays()
    pr.parts["legs"].add(p, i, n)
    # Rubber feet on the legs' tips.
    for sx in (-1, 1):
        h = to_world([sx * 0.062, hinge_y - 0.02, -cb - 0.02])[0]
        foot_x = sx * 0.21
        foot_z = h[2] - math.sqrt(max(LEG_LEN ** 2 - h[1] ** 2 - (foot_x - h[0]) ** 2, 0.01))
        f = np.array([foot_x, 0.012, foot_z])
        d = (f - h) / np.linalg.norm(f - h)
        tip = capsule(tuple(f - d * 0.06), tuple(f), LEG_R + 0.0025)
        pr.shape("rubber", tip, tuple(f - 0.08), tuple(f + 0.08), 0.0015 if not lite else 0.003,
                 int(600 * bag.k) + 40)
        # And the thin rod that kicks the legs out from the base.
        rod_a = to_world([sx * 0.04, 0.06, -B - 0.01])[0]
        rod_b = h + (f - h) * 0.45
        part = Part()
        tube(part, [rod_a, rod_b], 0.0022, segs=6 if not lite else 4)
        p, n, i = part.arrays()
        pr.parts["plastic"].add(p, i, n)

    if os.environ.get("BAG_STATS"):
        for key, part in pr.parts.items():
            if part.count:
                print("  %-8s %6d triangles" % (key, sum(len(i) for i in part.idx)))
    pr.save(out)


def smooth_path(points, n):
    """A smooth curve through the points (Catmull-Rom), n steps per span."""
    P = np.asarray(points, dtype=np.float64)
    P = np.vstack([P[0] * 2 - P[1], P, P[-1] * 2 - P[-2]])
    out = []
    for k in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[k - 1], P[k], P[k + 1], P[k + 2]
        for t in np.linspace(0, 1, n, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-2])
    return np.array(out)


def clubs(bag, lite):
    """The set, in the bag upright. A club stands on the bag's floor (about
    4 cm up), so its top is about its length plus 4 cm from the ground."""
    floor = 0.04
    # Woods under headcovers at the back: (mouth x, z, lean direction, length in, cover half sizes).
    # Covers: (mouth x, z, lean, length in inches, head half sizes toe/up/back).
    woods = [(-0.035, -0.055, (-0.42, 1.0, -0.30), 45.5, (0.082, 0.046, 0.064), "driver"),
             (0.04, -0.06, (0.40, 1.0, -0.34), 43.0, (0.070, 0.040, 0.055), "wood"),
             (0.0, -0.02, (0.10, 1.0, -0.22), 40.5, (0.058, 0.036, 0.046), "hybrid")]
    for x, z, lean, inches, half, kind in woods:
        d = np.array(lean) / np.linalg.norm(lean)
        top_y = floor + inches * INCH
        base = np.array([x, H - 0.02, z])
        # Where the sock's top (the head) sits along the lean.
        length = (top_y - half[1] - base[1]) / d[1]
        neck = base + d * length
        # The head under its cover lies across the top of the shaft, its toe
        # out over the side of the bag, as a club head sits on its hosel.
        toe = np.array([d[0], 0.0, d[2]])
        toe = toe / np.linalg.norm(toe) if np.linalg.norm(toe) > 1e-6 else np.array([1.0, 0, 0])
        head_c = neck + toe * half[0] * 0.45
        yaw = math.degrees(math.atan2(-toe[2], toe[0]))
        head = turned(ellipsoid(tuple(head_c), half), tuple(head_c), "y", yaw)
        sock = smooth_union(0.04, capsule(tuple(base - d * 0.05), tuple(neck - d * 0.02), 0.041),
                            capsule(tuple(base), tuple(base + d * 0.1), 0.036))
        hc = smooth_union(0.045, sock, head)
        lo = np.minimum(base, head_c) - 0.12
        hi = np.maximum(base, head_c) + 0.12
        bag.shape("cover", hc, lo, hi, 0.0028, 6000)
        # Our own cover design: a white band round the neck with red piping
        # at its mouth (no maker's marks).
        band = inter(shell(hc, 0.001, 0.0025), slab(tuple(base + d * (length * 0.55)), d, 0.018))
        bag.shape("white", band, lo, hi, 0.002, 1600)
        rim = inter(shell(hc, 0.001, 0.003), slab(tuple(base + d * 0.012), d, 0.004))
        bag.shape("red", rim, lo, hi, 0.0016, 900)

    # The putter under a mallet cover, front left, two-tone red and grey.
    pc = np.array([-0.06, floor + 34 * INCH + 0.03, 0.055])
    tube_part = lambda part: tube(part, [(-0.06, H - 0.05, 0.055), tuple(pc - [0, 0.04, 0])], 0.0075, segs=10)
    bag.mesh("grip", tube_part)
    mallet = rbox(tuple(pc), (0.05, 0.03, 0.045), 0.026)
    bag.shape("red", inter(mallet, box(pc - [1, 1, 1], pc + [1, 1, 0.0])), pc - 0.08, pc + 0.08, 0.0022, 2400)
    bag.shape("plastic", inter(mallet, box(pc - [1, 1, 0.0], pc + [1, 1, 1])), pc - 0.08, pc + 0.08, 0.0022, 2400)

    # Nine irons and wedges, heads up and toes out, the long irons at the
    # back of the front sections. Lengths: 4-iron 38.5 in to the wedges' 35.
    irons = [38.5, 38.0, 37.5, 37.0, 36.5, 36.0, 35.75, 35.5, 35.25]
    lofts = [21, 24, 27, 31, 35, 40, 45, 50, 56]
    slots = []
    for k in range(5):
        slots.append((-0.035 + k * 0.026, 0.035))     # the front-middle row
    for k in range(4):
        slots.append((0.005 + k * 0.024, 0.075))      # the front row
    segs = 8 if not lite else 5

    def blade(q):
        # Taller at the toe (+x) than the heel, and thicker at the sole (-y).
        t = q[0] / 0.038
        return np.array([q[0], q[1] * (0.8 + 0.25 * t), q[2] * (1.25 - 0.45 * (q[1] / 0.024 + 1) / 2)])

    def build_irons(part, chrome):
        for k, (inches, loft) in enumerate(zip(irons, lofts)):
            x, z = slots[k]
            top = floor + inches * INCH
            hosel = np.array([x + 0.008 * (k % 3 - 1), top - 0.03, z + 0.004 * (k % 2)])
            if not chrome:
                # The shaft up from the cuff, steel, then the ferrule.
                tube(part, [(x, H - 0.03, z), tuple(hosel - [0, 0.012, 0])], 0.0048, segs=segs)
                continue
            tube(part, [tuple(hosel - [0, 0.012, 0]), tuple(hosel + [0, 0.035, 0])], 0.0062, segs=segs)
            yaw = math.radians(-50 + 14 * k + (35 if z > 0.05 else 0))
            dirx = np.array([math.cos(yaw), 0.0, math.sin(yaw)])
            basis = np.array([dirx, [0, 1, 0], np.cross(dirx, [0, 1, 0])]).T
            # Upside down in the bag the toe points about 28 degrees above
            # level (a 62 degree lie), the sole uppermost, the face turned
            # by its loft.
            lie = math.radians(28)
            rz = np.array([[math.cos(lie), -math.sin(lie), 0], [math.sin(lie), math.cos(lie), 0], [0, 0, 1]])
            r = math.radians(loft)
            rx = np.array([[1, 0, 0], [0, math.cos(r), -math.sin(r)], [0, math.sin(r), math.cos(r)]])
            basis = basis @ rz @ rx
            # A 75 mm blade, about 45 mm tall at the toe, 18 mm thick sole.
            centre = hosel + [0, 0.035, 0] + basis @ np.array([0.034, 0.012, 0.0])
            superquadric(part, tuple(centre), (0.038, 0.024, 0.0085),
                         e=(0.22, 0.3), rows=8 if not lite else 4, cols=20 if not lite else 8, basis=basis,
                         warp=blade)
    bag.mesh("chrome", lambda part: build_irons(part, True))
    bag.mesh("chrome", lambda part: build_irons(part, False))
    if not lite:
        # Black ferrules where the shafts meet the hosels.
        def ferrules(part):
            for k, inches in enumerate(irons):
                x, z = slots[k]
                hosel = np.array([x + 0.008 * (k % 3 - 1), floor + inches * INCH - 0.03, z + 0.004 * (k % 2)])
                tube(part, [tuple(hosel - [0, 0.03, 0]), tuple(hosel - [0, 0.012, 0])], 0.0064, segs=segs)
        bag.mesh("grip", ferrules)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else OUT
    which = sys.argv[2:] or ["full", "lite"]
    if "full" in which:
        build(out, lite=False)
    if "lite" in which:
        build(out, lite=True)
