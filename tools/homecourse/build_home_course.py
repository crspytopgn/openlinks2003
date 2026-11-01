#!/usr/bin/env python3
"""Builds the built-in course, Kettle Hollow (game/assets/courses/home.olc).

A nine-hole parkland course laid on real ground: a 1.4 km patch of glacial
kettle-moraine farmland in Wisconsin, from the open Terrarium elevation
tiles (USGS 3DEP lidar there, public domain). The routing, yardages, green
sizes and slopes, bunker sizes, fairway widths and rough bands follow real
course design figures (see docs/home-course.md); the shapes are drawn
organic, never boxes or circles.

    python3 tools/homecourse/build_home_course.py [--cache /tmp/dem] [--preview out.png]

Writes the course as the designer's JSON (DesignedCourse, docs/course-designer.md),
so it can also be opened and edited in the course designer.
"""

import argparse
import base64
import gzip
import json
import math
import os
import sys
import urllib.request
import zlib

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geom  # noqa: E402

# Surface.Type names, as the .olc stores them.
TEE, FAIRWAY, FRINGE, GREEN, ROUGH, DEEP, SAND, WATER = (
    "Tee", "Fairway", "Fringe", "Green", "Rough", "Deep rough", "Sand", "Water")

CELL = 2.0
LAT, LON = 43.42, -88.30  # centre of the elevation patch (farmland, no course)
ZOOM = 15
SPAN = 1600.0  # metres of elevation fetched round the centre
YARD = 0.9144

# Map metres east (E) and south (S) of the patch's north-west corner. The
# game's x runs west and z north (as for real courses), centred on CENTRE.
CENTRE = (820.0, 560.0)


def to_game(p):
    return (CENTRE[0] - p[0], CENTRE[1] - p[1])


# --- The routing ------------------------------------------------------------
# Each hole: par, back tee, aim points, green centre (map E, S), green size
# (length, width in metres), fairway widths, bunkers and features. Bunkers:
# ("fw", metres from the back tee, metres right of the line (+) or left (-),
# length, width) for fairway bunkers, ("gs", clock angle round the green in
# degrees from the front (0) clockwise seen from the tee, length, width)
# for greenside ones. Green contour: tier (fraction from the front, rise m),
# tilt (back-to-front %, right-to-left %), and a seed for its knobs.
HOLES = [
    dict(par=4, tee=(1002, 556), route=[(905, 640)], green=(748, 822), gsize=(31, 23),
         fw=(34, 32, 25), bunkers=[("fw", 238, 19, 26, 11), ("fw", 262, -21, 18, 9), ("gs", 300, 13, 7),
                                   ("gs", 75, 15, 6)],
         tilt=(2.2, 0.6), tier=None, seed=11),
    dict(par=4, tee=(742, 884), route=[(560, 902)], green=(372, 986), gsize=(33, 22),
         fw=(33, 30, 24), bunkers=[("fw", 205, -18, 30, 12), ("fw", 252, 22, 20, 10), ("gs", 270, 17, 7),
                                   ("gs", 40, 10, 6), ("gs", 110, 9, 6)],
         tilt=(1.8, -0.8), tier=(0.55, 0.45), seed=23),
    dict(par=3, tee=(322, 947), route=[], green=(300, 786), gsize=(28, 25),
         fw=None, bunkers=[("gs", 300, 14, 7), ("gs", 60, 12, 6), ("gs", 165, 10, 5)],
         pond=((309, 850), 22, 12, 0.15),
         tilt=(2.4, 0.4), tier=None, seed=37),
    dict(par=5, tee=(248, 742), route=[(262, 515), (232, 360)], green=(236, 276), gsize=(34, 21),
         fw=(36, 31, 23), bunkers=[("fw", 222, 20, 28, 12), ("fw", 368, -17, 22, 10), ("fw", 380, 14, 14, 8),
                                   ("gs", 290, 15, 7), ("gs", 85, 13, 6)],
         tilt=(1.6, 1.0), tier=(0.6, 0.4), seed=41),
    dict(par=4, tee=(296, 226), route=[], green=(586, 150), gsize=(26, 24),
         fw=(30, 26, 22), bunkers=[("fw", 180, -15, 24, 10), ("gs", 320, 12, 6), ("gs", 20, 14, 6),
                                   ("gs", 70, 9, 5)],
         tilt=(2.6, -0.5), tier=None, seed=53),
    dict(par=4, tee=(622, 196), route=[(806, 300)], green=(960, 404), gsize=(32, 22),
         fw=(35, 32, 24), bunkers=[("fw", 250, 20, 30, 12), ("fw", 214, -22, 16, 9), ("gs", 285, 16, 7),
                                   ("gs", 95, 13, 6)],
         tilt=(2.0, 0.9), tier=(0.5, 0.4), seed=67),
    dict(par=3, tee=(1000, 332), route=[], green=(1158, 228), gsize=(30, 22),
         fw=None, bunkers=[("gs", 260, 16, 7), ("gs", 15, 13, 6), ("gs", 100, 15, 6)],
         tilt=(2.2, -0.6), tier=None, seed=71),
    dict(par=4, tee=(1192, 252), route=[], green=(1350, 592), gsize=(30, 23),
         fw=(34, 31, 24), bunkers=[("fw", 232, 18, 28, 11), ("fw", 245, -20, 20, 9), ("gs", 300, 12, 6),
                                   ("gs", 60, 15, 7)],
         tilt=(1.9, 0.5), tier=None, seed=83),
    dict(par=5, tee=(1402, 652), route=[(1196, 838)], green=(1012, 772), gsize=(33, 24),
         fw=(36, 32, 24), bunkers=[("fw", 258, -19, 30, 12), ("fw", 395, 16, 22, 10), ("gs", 280, 15, 7),
                                   ("gs", 70, 14, 7), ("gs", 0, 9, 5)],
         pond=((1092, 846), 34, 17, 0.4),
         tilt=(1.7, -0.7), tier=(0.45, 0.4), seed=97),
]
STROKE_INDEX = [7, 3, 15, 5, 13, 1, 17, 9, 11]
# Forward of the back tee, the middle and forward tees, in metres.
TEE_STEPS = {3: (14, 30), 4: (26, 58), 5: (30, 66)}


# --- Elevation --------------------------------------------------------------

def tile_xy(lat, lon, z):
    n = 2 ** z
    return ((lon + 180) / 360 * n, (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)


def fetch_dem(cache):
    os.makedirs(cache, exist_ok=True)
    cx, cy = tile_xy(LAT, LON, ZOOM)
    mpp = 156543.03392 * math.cos(math.radians(LAT)) / 2 ** ZOOM
    half = SPAN / 2 / mpp
    x0, x1 = int(cx - half / 256), int(cx + half / 256)
    y0, y1 = int(cy - half / 256), int(cy + half / 256)
    rows = []
    for ty in range(y0, y1 + 1):
        row = []
        for tx in range(x0, x1 + 1):
            p = os.path.join(cache, f"{ZOOM}_{tx}_{ty}.png")
            if not os.path.exists(p):
                url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{ZOOM}/{tx}/{ty}.png"
                urllib.request.urlretrieve(url, p)
            a = np.asarray(Image.open(p).convert("RGB")).astype(np.float64)
            row.append(a[..., 0] * 256 + a[..., 1] + a[..., 2] / 256 - 32768)
        rows.append(np.hstack(row))
    m = np.vstack(rows)
    px, py = (cx - x0) * 256, (cy - y0) * 256
    h = int(half)
    return m[int(py - h):int(py + h), int(px - h):int(px + h)], mpp


def sample(dem, mpp, e, s):
    u = np.clip(e / mpp - 0.5, 0, dem.shape[1] - 1.001)
    v = np.clip(s / mpp - 0.5, 0, dem.shape[0] - 1.001)
    i = u.astype(int)
    j = v.astype(int)
    fu = u - i
    fv = v - j
    a = dem[j, i] * (1 - fu) + dem[j, i + 1] * fu
    b = dem[j + 1, i] * (1 - fu) + dem[j + 1, i + 1] * fu
    return a * (1 - fv) + b * fv


# --- Hole geometry ----------------------------------------------------------

class Hole:
    def __init__(self, n, spec):
        self.n = n
        self.spec = spec
        self.par = spec["par"]
        self.line = np.array([to_game(spec["tee"])] + [to_game(p) for p in spec["route"]] + [to_game(spec["green"])])
        self.green = self.line[-1]
        seg = np.hypot(*(self.line[1:] - self.line[:-1]).T)
        self.cum = np.concatenate([[0.0], np.cumsum(seg)])
        self.length = self.cum[-1]
        d = self.line[-1] - self.line[-2]
        self.approach = d / np.linalg.norm(d)  # direction into the green
        d0 = self.line[1] - self.line[0]
        self.first = d0 / np.linalg.norm(d0)

    def at(self, s):
        """Point and direction `s` metres along the line from the back tee."""
        s = float(np.clip(s, 0.0, self.length))
        i = min(int(np.searchsorted(self.cum, s, side="right")) - 1, len(self.line) - 2)
        a, b = self.line[i], self.line[i + 1]
        d = (b - a) / np.linalg.norm(b - a)
        return a + d * (s - self.cum[i]), d


def right_of(d):
    """Unit vector to the golfer's right when facing `d` (+x is left)."""
    return np.array([-d[1], d[0]])


# --- Building ---------------------------------------------------------------

def build(dem, mpp):
    holes = [Hole(i + 1, s) for i, s in enumerate(HOLES)]
    shapes = []  # (surface, control points)
    paths = []

    # Course area: everything round the holes, plus room for the woods.
    allp = np.vstack([h.line for h in holes])
    lo = allp.min(0) - 150.0
    hi = allp.max(0) + 150.0
    lo = np.floor(lo / CELL) * CELL
    hi = np.ceil(hi / CELL) * CELL
    area = (lo[0], lo[1], hi[0] - lo[0], hi[1] - lo[1])
    cols = int(round(area[2] / CELL)) + 1
    rows = int(round(area[3] / CELL)) + 1
    gx = area[0] + np.arange(cols) * CELL
    gz = area[1] + np.arange(rows) * CELL
    X, Z = np.meshgrid(gx, gz)

    # Real ground, softened: the lidar keeps field drains, tracks and crop
    # rows; a few metres of blur leaves the glacial landform itself.
    E = CENTRE[0] - X
    S = CENTRE[1] - Z
    raw = sample(dem, mpp, E, S)
    base = geom.gaussian(raw, 3.0)  # ~6 m
    smooth = geom.gaussian(raw, 10.0)  # ~20 m, for graded corridors
    # Ground movement too small for the tiles (fairways are never flat).
    micro = (0.28 * geom.value_noise(X, Z, 31.0, 1) + 0.12 * geom.value_noise(X, Z, 13.0, 2)
             + 0.05 * geom.value_noise(X, Z, 6.0, 3))

    corridor_w = np.zeros(X.shape)  # 1 in the playing corridors
    for h in holes:
        d, _ = geom.polyline_distance(h.line, X, Z)
        corridor_w = np.maximum(corridor_w, 1.0 - geom.smoothstep(22.0, 45.0, d))
    height = base + (smooth - base) * corridor_w * 0.55 + micro

    tee_list = []
    for h in holes:
        spec = h.spec
        rng = np.random.default_rng(spec["seed"])
        # Tees: three separate pads, back to forward, each a rounded box
        # about 9 m wide, set square to the line.
        steps = (0,) + TEE_STEPS[h.par]
        h.tees = []
        for k, step in enumerate(steps):
            p, d = h.at(step)
            # Each tee a little off the line, as real ones are staggered.
            p = p + right_of(d) * rng.uniform(-2.5, 2.5) * (k > 0)
            length = (16, 13, 10)[k] if h.par > 3 else (20, 16, 12)[k]
            pad = geom.rounded_rect(p, length, (10, 9, 8)[k], math.atan2(d[1], d[0]), spec["seed"] * 7 + k)
            shapes.append((TEE, pad))
            h.tees.append(p)
            tee_list.append((pad, p))

        # Green: an organic pear, long along the approach.
        gl, gw = spec["gsize"]
        ang = math.atan2(h.approach[1], h.approach[0])
        g_pts = geom.smooth_blob(h.green, gl, gw, ang + rng.uniform(-0.25, 0.25), spec["seed"] * 13, count=22, wobble=0.09)
        h.green_poly = geom.outline(g_pts)
        shapes.append((GREEN, g_pts))

        # Fairway from about 120 m off the back tee to the front of the
        # green, wide in the landing zone and narrowing to the approach.
        front = h.length - gl * 0.5 + 1.0
        if spec["fw"] is not None:
            w_land, w_mid, w_app = spec["fw"]
            start = 118.0 if h.par == 4 else 125.0
            s_pts = np.linspace(start, front, 6)
            line = [h.at(s)[0] for s in s_pts]
            widths = np.interp(s_pts, [start, start + 40, 250, front - 50, front], [w_land * 0.75, w_land, w_mid, w_app * 1.1, w_app])
            fw = geom.ribbon(line, widths, spec["seed"] * 3, wander=0.13, cap=0.7)
            shapes.append((FAIRWAY, fw))
            h.fairway = geom.outline(fw)
        else:
            # Par 3s: a short apron of fairway grass in front of the green.
            p, d = h.at(front - 12.0)
            apron = geom.blob(p, 30.0, gw * 0.9, ang, spec["seed"] * 5, count=12, wobble=0.08)
            shapes.append((FAIRWAY, apron))
            h.fairway = geom.outline(apron)

        # Rough: a band of semi-rough along the whole hole, beyond it deep rough.
        r_line = [h.at(s)[0] for s in np.linspace(0.0, h.length + gl * 0.4, 9)]
        rw = (spec["fw"][0] + 30.0) if spec["fw"] is not None else 52.0
        widths = np.interp(np.linspace(0, 1, 9), [0, 0.2, 0.75, 1], [34.0, rw * 0.9, rw, gw + 30.0])
        shapes.append((ROUGH, geom.ribbon(r_line, widths, spec["seed"] * 19, wander=0.12, cap=0.95)))

        # Bunkers.
        h.bunkers = []
        for b in spec["bunkers"]:
            if b[0] == "fw":
                _, s, off, bl, bw = b
                p, d = h.at(s)
                c = p + right_of(d) * off
                bang = math.atan2(d[1], d[0]) + rng.uniform(-0.35, 0.35)
                face = d  # the face looks back at the tee
            else:
                _, clock, bl, bw = b
                a = math.radians(clock)
                # Clock round the green seen from the tee: 0 front, 90 right.
                fwd = h.approach
                rgt = right_of(fwd)
                dirv = -fwd * math.cos(a) + rgt * math.sin(a)
                # Out from the green edge by half the bunker's width plus a collar.
                ge = gl * 0.5 * abs(math.cos(a)) + gw * 0.5 * abs(math.sin(a))
                c = h.green + dirv * (ge + bw * 0.5 + 2.6)
                bang = math.atan2(dirv[1], dirv[0]) + math.pi / 2 + rng.uniform(-0.2, 0.2)
                face = -dirv  # the face is the side by the green
            # Rounded, with no points: greenside bunkers curl a little round
            # the green, fairway ones bend gently either way.
            bend = 0.35 if b[0] == "gs" else rng.uniform(-0.25, 0.25)
            pts = geom.smooth_blob(c, bl, bw, bang, spec["seed"] * 101 + len(h.bunkers), bend=bend)
            shapes.append((SAND, pts))
            h.bunkers.append((c, bl, bw, bang, face))

        # Ponds.
        h.pond = None
        if "pond" in spec:
            pc, pl, pw, pang = spec["pond"]
            c = np.array(to_game(pc))
            pts = geom.smooth_blob(c, pl * 2, pw * 2, pang, spec["seed"] * 211, count=22, wobble=0.12)
            shapes.append((WATER, pts))
            h.pond = geom.outline(pts)

        h.green_ctrl = g_pts

    # --- Grading -------------------------------------------------------------
    for h in holes:
        spec = h.spec
        rng = np.random.default_rng(spec["seed"] + 5)
        poly = h.green_poly
        box = (np.abs(X - h.green[0]) < 60) & (np.abs(Z - h.green[1]) < 60)
        xs, zs = X[box], Z[box]
        sd = geom.signed_distance(poly, xs, zs)
        fwd = h.approach
        rgt = right_of(fwd)
        rel_f = (xs - h.green[0]) * fwd[0] + (zs - h.green[1]) * fwd[1]
        rel_r = (xs - h.green[0]) * rgt[0] + (zs - h.green[1]) * rgt[1]
        here = height[box]
        level = here[sd < 0].mean() + 0.45  # a push-up green, a little proud
        tilt_f, tilt_r = spec["tilt"]
        gl = spec["gsize"][0]
        # Back higher than the front (drains to the front), plus a cross tilt.
        surf = level + rel_f * tilt_f / 100.0 - rel_r * tilt_r / 100.0
        if spec["tier"] is not None:
            frac, rise = spec["tier"]
            at = (frac - 0.5) * gl
            surf += rise * geom.smoothstep(at - 3.0, at + 3.0, rel_f) - rise * 0.5
        # A couple of soft knobs and hollows (a few cm), so putts break.
        for k in range(3):
            c_f = rng.uniform(-0.3, 0.3) * gl
            c_r = rng.uniform(-0.3, 0.3) * spec["gsize"][1]
            amp = rng.uniform(-0.09, 0.09)
            r = rng.uniform(5.0, 7.0)
            surf += amp * np.exp(-((rel_f - c_f) ** 2 + (rel_r - c_r) ** 2) / (2 * r * r))
        # Surrounds: the green blends out over 10 m; a false front falls off
        # quicker, the sides and back roll down in grassy mounds.
        reach = np.where(rel_f < 0, 7.0, 11.0)
        w = 1.0 - geom.smoothstep(0.5, reach, sd)
        mounds = np.zeros_like(sd)
        for k in range(4):
            a = rng.uniform(0.6, math.tau - 0.6)  # never straight in front
            dirv = -fwd * math.cos(a) + rgt * math.sin(a)
            mc = h.green + dirv * (gl * 0.5 + 11.0)
            mounds += rng.uniform(0.5, 1.0) * np.exp(-((xs - mc[0]) ** 2 + (zs - mc[1]) ** 2) / (2 * 6.5 ** 2))
        mounds *= geom.smoothstep(3.0, 7.0, sd)
        height[box] = here * (1 - w) + surf * w + mounds

    for h in holes:
        # Bunker faces: built up 0.5 to 0.9 m on the side they face.
        for (c, bl, bw, bang, face) in h.bunkers:
            mc = c + face * (bw * 0.45)
            box = (np.abs(X - c[0]) < 40) & (np.abs(Z - c[1]) < 40)
            xs, zs = X[box], Z[box]
            ca, sa = math.cos(bang), math.sin(bang)
            lx = (xs - mc[0]) * ca + (zs - mc[1]) * sa
            lz = -(xs - mc[0]) * sa + (zs - mc[1]) * ca
            r = (lx / (bl * 0.55)) ** 2 + (lz / (bw * 0.5)) ** 2
            height[box] += 1.1 * np.exp(-r * 1.5)

    for pad, p in tee_list:
        # Tee pads: level, 0.4 m proud, with banks about 1 in 4.
        poly = geom.outline(pad)
        box = (np.abs(X - p[0]) < 25) & (np.abs(Z - p[1]) < 25)
        xs, zs = X[box], Z[box]
        sd = geom.signed_distance(poly, xs, zs)
        here = height[box]
        level = here[sd < 0].mean() + 0.4 if (sd < 0).any() else here.mean()
        w = 1.0 - geom.smoothstep(0.0, 3.5, sd)
        height[box] = here * (1 - w) + level * w

    for h in holes:
        if h.pond is None:
            continue
        # A pond sits in a basin: the ground round it is let down to near the
        # water so its banks are gentle, not a cliff on the high side.
        box = (np.abs(X - h.pond[:, 0].mean()) < 90) & (np.abs(Z - h.pond[:, 1].mean()) < 90)
        xs, zs = X[box], Z[box]
        sd = geom.signed_distance(h.pond, xs, zs)
        here = height[box]
        low = np.percentile(here[sd < 0], 20)
        w = 1.0 - geom.smoothstep(0.0, 22.0, sd)
        height[box] = np.minimum(here, here * (1 - w) + (low + 0.5) * w)

    height -= height.min()

    # --- Pins: on a part of the green flat enough to hold a putt (at most 3 %
    # within 2.5 m, as greenkeepers cut them), 4.5 m or more from the edge
    # and off the tiers' faces; front, middle and back in turn round the nine.
    gz_, gx_ = np.gradient(height, CELL)
    slope = np.hypot(gx_, gz_) * 100.0
    worst = slope.copy()
    for dj in (-1, 0, 1):
        for di in (-1, 0, 1):
            worst = np.maximum(worst, np.roll(np.roll(slope, dj, 0), di, 1))
    for i, h in enumerate(holes):
        poly = h.green_poly
        box = (np.abs(X - h.green[0]) < 30) & (np.abs(Z - h.green[1]) < 30)
        xs, zs = X[box], Z[box]
        ok = geom.inside(poly, xs, zs) & (geom.edge_distance(poly, xs, zs) >= 4.5) & (worst[box] <= 3.0)
        gl, gw = h.spec["gsize"]
        fwd, rgt = h.approach, right_of(h.approach)
        want = h.green + fwd * gl * (-0.22, 0.05, 0.25)[i % 3] + rgt * gw * (0.15, -0.2, 0.05, -0.1)[i % 4]
        if ok.any():
            d = (xs - want[0]) ** 2 + (zs - want[1]) ** 2
            d[~ok] = np.inf
            k = int(np.argmin(d))
            h.pin = np.array([xs[k], zs[k]])
        else:
            h.pin = h.green.copy()
        print(f"hole {h.n} pin: slope {worst[box][k] if ok.any() else -1:.1f} %")

    # --- Cart paths: from each green round to the next tee ----------------
    for i, h in enumerate(holes):
        g = h.green
        nxt = holes[(i + 1) % len(holes)].tees[0] if i + 1 < len(holes) else holes[0].tees[0]
        # Leave the green from its back corner on the side of the next tee.
        side = right_of(h.approach)
        sgn = 1.0 if (nxt - g) @ side > 0 else -1.0
        a = g + h.approach * 14.0 + side * sgn * 26.0
        b = nxt - holes[(i + 1) % len(holes)].first * 16.0 + right_of(holes[(i + 1) % len(holes)].first) * sgn * 12.0
        if i + 1 >= len(holes):
            continue
        # A gentle curve (quadratic Bezier), as cart paths are laid.
        mid = (a + b) * 0.5 + right_of((b - a) / max(np.linalg.norm(b - a), 1.0)) * 10.0
        n = max(4, int(np.linalg.norm(b - a) / 6.0))
        curve = [tuple((1 - t) ** 2 * a + 2 * (1 - t) * t * mid + t * t * b) for t in np.linspace(0, 1, n)]
        paths.append(curve)

    # --- Trees ----------------------------------------------------------------
    objects = place_trees(holes, shapes, X, Z, height, area)

    return holes, shapes, paths, objects, area, cols, rows, height


def place_trees(holes, shapes, X, Z, height, area):
    """Woods and tree lines in the deep rough: groves where a slow noise
    says so, thicker round the boundary, bushes in front of them."""
    rng = np.random.default_rng(2003)
    # Where trees may not stand: the rough bands, a margin round tees,
    # greens, bunkers, ponds and fairways, and 30 m either side of each line.
    blocked = np.zeros(X.shape, dtype=bool)
    for s, p in shapes:
        poly = geom.outline(p)
        margin = 4.0 if s == ROUGH else 12.0
        lo = poly.min(0) - margin
        hi = poly.max(0) + margin
        m = (X >= lo[0]) & (X <= hi[0]) & (Z >= lo[1]) & (Z <= hi[1])
        blocked[m] |= geom.signed_distance(poly, X[m], Z[m]) < margin
    for h in holes:
        d, _ = geom.polyline_distance(h.line, X, Z)
        blocked |= d < 30.0
    x0, z0, w, hh = area
    # Tree lines frame each hole 40 to 90 m off its line; groves elsewhere
    # where a slow noise says so; woods thicken round the boundary.
    near = np.full(X.shape, np.inf)
    for h in holes:
        d, _ = geom.polyline_distance(h.line, X, Z)
        near = np.minimum(near, d)
    dens = (geom.value_noise(X, Z, 140.0, 7) + 0.3 * geom.value_noise(X, Z, 45.0, 8)
            + 0.55 * np.exp(-((near - 60.0) / 28.0) ** 2) * (0.75 + geom.value_noise(X, Z, 60.0, 10)))
    edge = np.minimum.reduce([X - x0, x0 + w - X, Z - z0, z0 + hh - Z])
    dens = dens + 0.9 * (1.0 - geom.smoothstep(25.0, 70.0, edge))
    pine_zone = geom.value_noise(X, Z, 180.0, 9) > 0.12

    def cell(x, z):
        return int(round((z - z0) / CELL)), int(round((x - x0) / CELL))

    objects = []
    occupied = np.zeros(X.shape, dtype=np.int32)  # nearest-gap bookkeeping
    taken = []

    def clear(x, z, gap):
        j, i = cell(x, z)
        r = int(math.ceil(gap / CELL))
        js, je = max(0, j - r), min(X.shape[0], j + r + 1)
        is_, ie = max(0, i - r), min(X.shape[1], i + r + 1)
        if not occupied[js:je, is_:ie].any():
            return True
        for k in np.unique(occupied[js:je, is_:ie]):
            if k == 0:
                continue
            tx, tz = taken[k - 1]
            if (tx - x) ** 2 + (tz - z) ** 2 < gap * gap:
                return False
        return True

    def take(x, z):
        taken.append((x, z))
        j, i = cell(x, z)
        occupied[j, i] = len(taken)

    tries = 0
    while len(objects) < 3600 and tries < 300000:
        tries += 1
        x = rng.uniform(x0 + 6, x0 + w - 6)
        z = rng.uniform(z0 + 6, z0 + hh - 6)
        j, i = cell(x, z)
        d = dens[j, i]
        if blocked[j, i] or d < 0.12 or rng.random() > (d - 0.05) * 1.5:
            continue
        if not clear(x, z, 5.5 if d > 0.3 else 8.0):
            continue
        kind = "tree_pine" if pine_zone[j, i] else "tree_broadleaf"
        objects.append((kind, x, z, rng.uniform(0, 360), rng.uniform(0.85, 1.35)))
        take(x, z)
    # Deep woods away from the holes: batched and drawn as impostors from a
    # distance by the game (beyond DesignedCourse.HOLE_REACH of a hole), so
    # they can stand close, as real woodland does, for little cost.
    tries = 0
    deep = 0
    while deep < 4200 and tries < 400000:
        tries += 1
        x = rng.uniform(x0 + 4, x0 + w - 4)
        z = rng.uniform(z0 + 4, z0 + hh - 4)
        j, i = cell(x, z)
        if near[j, i] < 110.0 or blocked[j, i] or dens[j, i] < 0.18:
            continue
        if not clear(x, z, 5.0):
            continue
        kind = "tree_pine" if pine_zone[j, i] else "tree_broadleaf"
        objects.append((kind, x, z, rng.uniform(0, 360), rng.uniform(0.9, 1.4)))
        take(x, z)
        deep += 1
    trees = len(taken)
    tries = 0
    count = 0
    while count < 500 and tries < 40000:
        tries += 1
        tx, tz = taken[rng.integers(trees)]
        a = rng.uniform(0, math.tau)
        r = rng.uniform(5.0, 10.0)
        x, z = tx + math.cos(a) * r, tz + math.sin(a) * r
        if not (x0 + 2 < x < x0 + w - 2 and z0 + 2 < z < z0 + hh - 2):
            continue
        j, i = cell(x, z)
        if blocked[j, i] or not clear(x, z, 4.0):
            continue
        objects.append(("bush", x, z, rng.uniform(0, 360), rng.uniform(0.6, 1.1)))
        take(x, z)
        count += 1
    return objects


def encode_heights(height):
    flat = np.clip(height.ravel(), -150, 150)
    cm = np.round(flat * 100).astype(np.int64)
    deltas = np.diff(np.concatenate([[0], cm])).astype("<i2")
    raw = deltas.tobytes()
    return {"encoding": "cm-delta-s16-deflate-base64", "count": int(flat.size),
            "data": base64.b64encode(zlib.compress(raw, 9)).decode()}


def flat(pts):
    out = []
    for p in pts:
        out.extend([round(float(p[0]), 2), round(float(p[1]), 2)])
    return out


def write_course(path, holes, shapes, paths, objects, area, cols, rows, height):
    hole_list = []
    for i, h in enumerate(holes):
        route = [tuple(p) for p in h.line[1:-1]]
        hole_list.append({"par": h.par, "tees": flat(h.tees), "pin": flat([h.pin]), "route": flat(route),
                          "stroke_index": STROKE_INDEX[i]})
    # The deep rough under everything (the rough bands are painted over it).
    x0, z0, w, hh = area
    border = []
    n = 24
    for k in range(n):
        border.append((x0 - 4 + (w + 8) * k / n, z0 - 4))
    for k in range(n):
        border.append((x0 + w + 4, z0 - 4 + (hh + 8) * k / n))
    for k in range(n):
        border.append((x0 + w + 4 - (w + 8) * k / n, z0 + hh + 4))
    for k in range(n):
        border.append((x0 - 4, z0 + hh + 4 - (hh + 8) * k / n))
    shape_list = [{"surface": DEEP, "points": flat(border)}]
    shape_list += [{"surface": s, "points": flat(p)} for s, p in shapes]
    course = {
        "format": "openlinks-course",
        "version": 1,
        "name": "Kettle Hollow",
        "author": "OpenLinks2003",
        "area": [float(a) for a in area],
        "cell": CELL,
        "heights": encode_heights(height),
        "shapes": shape_list,
        "holes": hole_list,
        "objects": [{"id": o[0], "x": round(o[1], 1), "z": round(o[2], 1), "yaw": int(o[3]), "scale": round(o[4], 2)}
                    for o in objects],
        "paths": [{"points": flat(p), "width": 2.4, "bridge": False} for p in paths],
        "object_info": {},
        "credits": "Ground: Terrarium elevation tiles (Mapzen / AWS Open Data), from USGS 3DEP lidar (public domain).",
        "source": {"kind": "built-in", "lat": LAT, "lon": LON},
    }
    # Gzipped (DesignedCourse.load_file reads either): the export packs
    # files as they are, and the JSON is mostly tree positions that shrink
    # to a third. mtime 0 keeps rebuilds byte-identical.
    with open(path, "wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=9, mtime=0) as f:
        f.write(json.dumps(course, separators=(",", ":")).encode("utf-8"))


def preview(path, holes, shapes, paths, objects, area, height):
    """A top-down map: surfaces over a hillshade, for checking the layout."""
    x0, z0, w, hh = area
    scale = 1.0  # metres per pixel
    W, H = int(w / scale), int(hh / scale)
    # Image x runs east (game -x), y south (game -z).
    px = np.arange(W) * scale
    py = np.arange(H) * scale
    PX, PY = np.meshgrid(px, py)
    gxs = x0 + w - PX
    gzs = z0 + hh - PY
    colors = {DEEP: (52, 80, 32), ROUGH: (72, 110, 44), FAIRWAY: (104, 160, 62), TEE: (110, 168, 66),
              GREEN: (120, 188, 74), SAND: (226, 210, 160), WATER: (40, 80, 110)}
    img = np.zeros((H, W, 3))
    img[:] = colors[DEEP]
    order = [ROUGH, FAIRWAY, TEE, GREEN, SAND, WATER]
    for surf in order:
        for s, p in shapes:
            if s != surf:
                continue
            poly = geom.outline(p)
            lo = poly.min(0)
            hi = poly.max(0)
            m = (gxs >= lo[0]) & (gxs <= hi[0]) & (gzs >= lo[1]) & (gzs <= hi[1])
            sub = geom.inside(poly, gxs[m], gzs[m])
            idx = np.nonzero(m)
            img[idx[0][sub], idx[1][sub]] = colors[surf]
            if surf == GREEN:
                ring = geom.edge_distance(poly, gxs[m], gzs[m]) < 1.8
                ring &= ~sub
                img[idx[0][ring], idx[1][ring]] = (110, 175, 66)
    # Hillshade from the height grid.
    gi = np.clip(((gxs - x0) / CELL).astype(int), 0, height.shape[1] - 1)
    gj = np.clip(((gzs - z0) / CELL).astype(int), 0, height.shape[0] - 1)
    hh_ = height[gj, gi]
    dzdy, dzdx = np.gradient(hh_, scale)
    shade = np.clip(0.75 + (dzdx * 0.5 - dzdy * 0.5) * 2.5, 0.45, 1.3)
    img = img * shade[..., None]
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    from PIL import ImageDraw
    d = ImageDraw.Draw(out)

    def topx(p):
        return (x0 + w - p[0]) / scale, (z0 + hh - p[1]) / scale

    for p in paths:
        d.line([topx(q) for q in p], fill=(180, 175, 160), width=2)
    for o in objects:
        x, y = topx((o[1], o[2]))
        r = 2 if o[0] == "bush" else 4
        d.ellipse([x - r, y - r, x + r, y + r], fill=(30, 55, 25) if o[0] != "tree_pine" else (20, 45, 30))
    for h in holes:
        d.line([topx(p) for p in h.line], fill=(255, 255, 255), width=1)
        x, y = topx(h.tees[0])
        d.text((x + 6, y - 6), str(h.n), fill=(255, 255, 0))
    out.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default="/tmp/dem")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "..", "game", "assets", "courses", "home.olc"))
    ap.add_argument("--preview")
    args = ap.parse_args()
    dem, mpp = fetch_dem(args.cache)
    holes, shapes, paths, objects, area, cols, rows, height = build(dem, mpp)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    write_course(args.out, holes, shapes, paths, objects, area, cols, rows, height)
    total = 0
    for h in holes:
        y = h.length / YARD
        total += y
        print(f"hole {h.n}: par {h.par}, {y:.0f} yd ({h.length:.0f} m)")
    print(f"total {total:.0f} yd, area {area[2]:.0f} x {area[3]:.0f} m, {len(objects)} trees and bushes,"
          f" relief {height.max():.1f} m, file {os.path.getsize(args.out) / 1024:.0f} KB")
    if args.preview:
        preview(args.preview, holes, shapes, paths, objects, area, height)


if __name__ == "__main__":
    main()
