#!/usr/bin/env python3
"""Builds the course props in game/assets/props/ from code, each modelled
from reference photos of the real thing to its real size.

    python3 tools/props/build_props.py [out_dir]

    golf_bag.glb     a tour staff bag with woods under headcovers, irons,
                     a putter cover and a towel (caddie and buggy)
    tee_marker.glb   a spherical plastic tee marker, 127 mm across
    ball_washer.glb  a paddle ball washer on a post over a litter bin, on a
                     ring base (the tee "ensemble")
    tee_sign.glb     a hanging hole sign on a square post (the text is
                     added in the game)
    tee_bench.glb    a 5 ft slatted bench with a back and arms
    bunker_rake.glb  a 25 in (64 cm) bunker rake on a 54 in (1.37 m) handle

The sizes and where they come from are in docs/props.md. No makers' names
or logos. Our own work, released as CC0 like the other free assets.

Moulded and rounded parts are signed distance shapes meshed with marching
cubes (tools/buggy/sdf.py; needs scikit-image and fast-simplification from
pip), with ambient occlusion baked into the vertex colours. Each prop is one
mesh with one surface per material, so it costs a draw call per material.
Godot axes: +y up, origin on the ground under the prop.
"""

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "golfer"))
sys.path.insert(0, os.path.join(HERE, "..", "buggy"))
from gltf import FLOAT, UBYTE, UINT, USHORT, Gltf  # noqa: E402
from build_golf_cart import Part, superquadric, tube  # noqa: E402
from sdf import ambient_occlusion, mesh as sdf_mesh, rbox, smooth_union, sphere, union  # noqa: E402

# Every shape's triangle budget is scaled by this: the game's props are seen
# from a few metres at the closest, and Godot adds distance LODs on import.
FACES = 0.6

OUT = os.path.join(HERE, "..", "..", "game", "assets", "props")


# --- Shapes ----------------------------------------------------------------------

def capsule(a, b, r):
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    ba = b - a
    bb = ba @ ba

    def f(x, y, z):
        px, py, pz = x - a[0], y - a[1], z - a[2]
        h = np.clip((px * ba[0] + py * ba[1] + pz * ba[2]) / bb, 0.0, 1.0)
        return np.sqrt((px - ba[0] * h) ** 2 + (py - ba[1] * h) ** 2 + (pz - ba[2] * h) ** 2) - r
    return f


def slab(c, n, half):
    """Points within `half` of the plane through c across direction n."""
    def f(x, y, z):
        return np.abs((x - c[0]) * n[0] + (y - c[1]) * n[1] + (z - c[2]) * n[2]) - half
    return f


def ellipsoid(c, h):
    """An ellipsoid (centre, half sizes); a close distance near the surface."""
    def f(x, y, z):
        qx, qy, qz = (x - c[0]) / h[0], (y - c[1]) / h[1], (z - c[2]) / h[2]
        k0 = np.sqrt(qx * qx + qy * qy + qz * qz)
        return (k0 - 1.0) * min(h)
    return f


def oval_column(a, b, y0, y1, r, cx=0.0, cz=0.0, taper=0.0):
    """An upright column with an oval section (half widths a in x, b in z,
    shrinking by `taper` of themselves towards the top), its ends rounded by r."""
    def f(x, y, z):
        t = np.clip((y - y0) / (y1 - y0), 0.0, 1.0)
        s = 1.0 - taper * t
        aa, bb = a * s - r, b * s - r
        q = np.sqrt(((x - cx) / aa) ** 2 + ((z - cz) / bb) ** 2)
        d = (q - 1.0) * np.minimum(aa, bb)
        dy = np.maximum(y0 + r - y, y - (y1 - r))
        out = np.sqrt(np.maximum(d, 0) ** 2 + np.maximum(dy, 0) ** 2)
        return out + np.minimum(np.maximum(d, dy), 0) - r
    return f


def column(r0, r1, y0, y1, rr, cx=0.0, cz=0.0):
    """An upright round column, r0 at the bottom to r1 at the top."""
    def f(x, y, z):
        t = np.clip((y - y0) / (y1 - y0), 0.0, 1.0)
        rad = r0 + (r1 - r0) * t - rr
        d = np.sqrt((x - cx) ** 2 + (z - cz) ** 2) - rad
        dy = np.maximum(y0 + rr - y, y - (y1 - rr))
        out = np.sqrt(np.maximum(d, 0) ** 2 + np.maximum(dy, 0) ** 2)
        return out + np.minimum(np.maximum(d, dy), 0) - rr
    return f


def torus_y(c, big, small):
    def f(x, y, z):
        q = np.sqrt((x - c[0]) ** 2 + (z - c[2]) ** 2) - big
        return np.sqrt(q * q + (y - c[1]) ** 2) - small
    return f


def shell(shape, inner, outer):
    """The skin of a shape from `inner` under its surface to `outer` above."""
    def f(x, y, z):
        d = shape(x, y, z)
        return np.maximum(d - outer, -(d + inner))
    return f


def inter(*shapes):
    def f(x, y, z):
        d = shapes[0](x, y, z)
        for s in shapes[1:]:
            d = np.maximum(d, s(x, y, z))
        return d
    return f


def cut(a, b):
    def f(x, y, z):
        return np.maximum(a(x, y, z), -b(x, y, z))
    return f


def box(lo, hi, r=0.0):
    lo, hi = np.asarray(lo, dtype=np.float64), np.asarray(hi, dtype=np.float64)
    return rbox((lo + hi) / 2, (hi - lo) / 2, r)


def turned(shape, c, axis, deg):
    """The shape turned by deg about an axis ('x', 'y' or 'z') through c."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)

    def f(x, y, z):
        px, py, pz = x - c[0], y - c[1], z - c[2]
        if axis == "x":
            py, pz = ca * py + sa * pz, -sa * py + ca * pz
        elif axis == "y":
            px, pz = ca * px - sa * pz, sa * px + ca * pz
        else:
            px, py = ca * px + sa * py, -sa * px + ca * py
        return shape(px + c[0], py + c[1], pz + c[2])
    return f


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# --- Writing ------------------------------------------------------------------------

class Prop:
    """One glb: materials, shapes meshed per material, and loose parts."""

    def __init__(self, name):
        self.name = name
        self.g = Gltf()
        self.g.doc["asset"]["generator"] = "OpenLinks2003 tools/props"
        self.mats = {}
        self.parts = {}
        self.solids = []

    def material(self, key, colour, rough, metal=0.0, clearcoat=0.0, double=False):
        """colour is sRGB, as picked from a photo; glTF wants it linear."""
        colour = tuple(srgb_to_linear(c) for c in colour[:3]) + (colour[3],)
        m = self.g.material(key, colour=colour, roughness=rough, metallic=metal, double_sided=double)
        if clearcoat:
            used = self.g.doc.setdefault("extensionsUsed", [])
            if "KHR_materials_clearcoat" not in used:
                used.append("KHR_materials_clearcoat")
            self.g.doc["materials"][m]["extensions"] = {"KHR_materials_clearcoat": {
                "clearcoatFactor": clearcoat, "clearcoatRoughnessFactor": 0.25}}
        self.mats[key] = m
        self.parts[key] = Part()

    def shape(self, key, shape, lo, hi, step, faces):
        p, n, i = sdf_mesh(shape, lo, hi, step, int(faces * FACES))
        self.parts[key].add(p, i, n)
        self.solids.append(shape)

    def save(self, out_dir):
        g = self.g
        solids = self.solids

        def scene(x, y, z):
            d = y + 0.0  # the ground
            for s in solids:
                d = np.minimum(d, s(x, y, z))
            return d

        prims = []
        tris = 0
        for key, part in self.parts.items():
            if part.count == 0:
                continue
            p, n, i = part.arrays()
            a = ambient_occlusion(scene, p.astype(np.float64), n.astype(np.float64), step=0.012, strength=2.4)
            col = np.round(np.stack([a, a, a, np.ones_like(a)], axis=1) * 255).astype(np.uint8)
            colour = g.accessor(col, UBYTE, 34962)
            g.doc["accessors"][colour]["normalized"] = True
            attrs = {"POSITION": g.accessor(p, FLOAT, 34962, minmax=True), "NORMAL": g.accessor(n, FLOAT, 34962),
                     "COLOR_0": colour}
            itype = USHORT if len(p) < 65536 else UINT
            prims.append({"attributes": attrs, "indices": g.accessor(i.reshape(-1), itype, 34963),
                          "material": self.mats[key]})
            tris += len(i)
        g.doc["meshes"].append({"name": self.name, "primitives": prims})
        node = g.node(name=self.name, mesh=len(g.doc["meshes"]) - 1)
        g.doc["scenes"][0]["nodes"].append(node)
        path = os.path.join(out_dir, self.name + ".glb")
        os.makedirs(out_dir, exist_ok=True)
        g.save(path)
        print("%-16s %6d triangles, %d surfaces, %4d KB" % (self.name, tris, len(prims), os.path.getsize(path) // 1024))


# --- The tour staff bag -------------------------------------------------------------
#
# From tour photos of a staff bag standing on the fairway: an oval tube about
# 0.92 m tall and 0.29 by 0.25 m across, white synthetic leather with a
# coloured stripe panel, a black rubber foot and top cuff, a ball pocket and
# a long apparel pocket, a carry strap and a top handle. The woods stand at
# the back under long knitted headcovers that rise about 0.35 m above the
# cuff (a 45.5 in driver in a 36 in bag), the irons poke their heads up at
# the front, and a towel hangs over the side. Front (pockets) towards +z.

BAG_H = 0.92
BAG_A = 0.158  # half width (x) at the foot
BAG_B = 0.136  # half depth (z) at the foot
BAG_TAPER = 0.07


def bag_body(grow=0.0, y0=0.05, y1=0.87):
    return oval_column(BAG_A + grow, BAG_B + grow, y0, y1, 0.02, taper=BAG_TAPER)


def build_bag(out):
    pr = Prop("golf_bag")
    pr.material("leather", (0.88, 0.88, 0.86, 1), 0.55)
    pr.material("accent", (0.40, 0.07, 0.09, 1), 0.5)
    pr.material("black", (0.07, 0.07, 0.075, 1), 0.7)
    pr.material("chrome", (0.8, 0.8, 0.81, 1), 0.3, metal=0.85)
    pr.material("cloth", (0.93, 0.93, 0.91, 1), 0.95)

    body = bag_body()
    # The ball pocket low on the front, and a zipped pouch above it.
    pocket = rbox((0.0, 0.30, BAG_B - 0.02), (0.1, 0.15, 0.065), 0.05)
    pouch = rbox((-0.035, 0.63, BAG_B * 0.95 - 0.02), (0.075, 0.1, 0.05), 0.04)
    white = smooth_union(0.015, body, pocket, pouch)
    lo, hi = (-0.2, 0.0, -0.18), (0.2, 0.9, 0.22)
    pr.shape("leather", white, lo, hi, 0.005, 5000)

    # The stripe panel down the front right, the pocket's trim and the long
    # apparel pocket on the left side, all in the accent colour.
    stripe = inter(shell(white, 0.002, 0.003), box((0.035, 0.1, 0.0), (0.11, 0.83, 0.3)))
    trim = inter(shell(white, 0.002, 0.004), cut(box((-0.115, 0.14, 0.1), (0.115, 0.46, 0.3)),
                                                 box((-0.09, 0.165, 0.0), (0.09, 0.435, 0.3))))
    apparel = rbox((-BAG_A + 0.01, 0.47, -0.01), (0.05, 0.28, 0.085), 0.04)
    pr.shape("accent", union(stripe, trim, apparel), (-0.22, 0.05, -0.18), (0.2, 0.86, 0.22), 0.004, 4000)

    # The rubber foot, the cuff round the top, the dividers inside it, and
    # the strap and handle.
    foot = oval_column(BAG_A + 0.008, BAG_B + 0.008, 0.0, 0.085, 0.025)
    cuff_out = oval_column(BAG_A * (1 - BAG_TAPER) + 0.01, BAG_B * (1 - BAG_TAPER) + 0.01, 0.83, BAG_H, 0.012)
    cuff_in = oval_column(BAG_A * (1 - BAG_TAPER) - 0.012, BAG_B * (1 - BAG_TAPER) - 0.012, 0.86, 1.0, 0.0)
    cuff = cut(cuff_out, cuff_in)
    floor = box((-0.13, 0.86, -0.11), (0.13, 0.875, 0.11))
    divider = box((-0.13, 0.86, -0.004), (0.13, 0.90, 0.004))
    handle = capsule((BAG_A * 0.95 + 0.03, 0.70, -0.03), (BAG_A * 0.95 + 0.03, 0.80, -0.03), 0.013)
    handle_ends = union(capsule((BAG_A * 0.95 - 0.01, 0.68, -0.03), (BAG_A * 0.95 + 0.03, 0.70, -0.03), 0.011),
                        capsule((BAG_A * 0.95 - 0.01, 0.82, -0.03), (BAG_A * 0.95 + 0.03, 0.80, -0.03), 0.011))
    strap = union(capsule((-0.04, 0.80, -BAG_B * 0.94), (-0.03, 0.62, -BAG_B - 0.075), 0.012),
                  capsule((-0.03, 0.62, -BAG_B - 0.075), (0.01, 0.38, -BAG_B - 0.05), 0.012),
                  capsule((0.01, 0.38, -BAG_B - 0.05), (0.03, 0.30, -BAG_B), 0.012))
    black = union(foot, cuff, floor, divider, handle, handle_ends, strap)
    pr.shape("black", black, (-0.2, -0.01, -0.25), (0.22, 0.95, 0.2), 0.0045, 5000)

    # The woods, leaning back under their headcovers: (sock bottom, top
    # direction, head half sizes, material).
    woods = [((-0.06, 0.8, -0.06), (-0.22, 1.0, -0.26), (0.072, 0.1, 0.064), 0.47, "black"),  # driver
             ((0.01, 0.8, -0.07), (0.04, 1.0, -0.3), (0.066, 0.092, 0.058), 0.44, "accent"),  # 3 wood
             ((0.075, 0.8, -0.045), (0.26, 1.0, -0.16), (0.06, 0.082, 0.052), 0.4, "black")]  # hybrid
    for base, d, half, length, key in woods:
        base = np.array(base)
        d = np.array(d) / np.linalg.norm(d)
        top = base + d * length
        sock = smooth_union(0.03, capsule(base, top, 0.044), capsule(base, base + d * 0.15, 0.036))
        head = turned(ellipsoid(tuple(top + d * 0.04), half), tuple(top + d * 0.04), "y", 20)
        hc = smooth_union(0.02, sock, head)
        pr.shape(key, hc, tuple(np.minimum(base, top) - 0.1), tuple(np.maximum(base, top) + 0.12), 0.004, 1800)
        # A pom-pom-free tour cover has a white band near its mouth.
        band = inter(shell(hc, 0.001, 0.003), slab(base + d * (length - 0.15), d, 0.012))
        pr.shape("cloth", band, tuple(np.minimum(base, top) - 0.1), tuple(np.maximum(base, top) + 0.12), 0.003, 600)
    # The putter under a blade cover at the front left.
    putter = rbox((-0.085, 0.985, 0.065), (0.055, 0.03, 0.02), 0.018)
    pr.shape("black", turned(putter, (-0.085, 0.985, 0.065), "z", 8), (-0.18, 0.9, 0.0), (0.0, 1.06, 0.12), 0.003, 900)
    tube(pr.parts["chrome"], [(-0.085, 0.86, 0.065), (-0.085, 0.955, 0.065)], 0.006, segs=8)

    # Ten irons and wedges at the front, heads up, toes out.
    for row, z in ((0, 0.075), (1, 0.035)):
        for i in range(5):
            x = -0.035 + i * 0.03 + row * 0.012
            h = 0.94 + 0.012 * (4 - i) + 0.03 * row  # the long irons stand taller
            lean = np.array([0.015 * (i - 2), 0.0, 0.012])
            hosel = np.array([x, h, z]) + lean
            tube(pr.parts["chrome"], [(x, 0.86, z), tuple(hosel)], 0.0058, segs=7)
            yaw = -25 + 12 * i + 40 * row
            loft = 18 + 6 * (i + 5 * row)
            a = math.radians(yaw)
            dirx = np.array([math.cos(a), 0.0, math.sin(a)])
            basis = np.array([dirx, [0, 1, 0], np.cross(dirx, [0, 1, 0])]).T
            r = math.radians(loft)
            basis = basis @ np.array([[1, 0, 0], [0, math.cos(r), -math.sin(r)], [0, math.sin(r), math.cos(r)]])
            superquadric(pr.parts["chrome"], tuple(hosel + dirx * 0.032 + [0, 0.018, 0]), (0.036, 0.022, 0.008),
                         e=(0.35, 0.35), rows=6, cols=12, basis=basis)

    # The towel over the right side of the cuff.
    towel_base = oval_column(BAG_A * (1 - BAG_TAPER) + 0.02, BAG_B * (1 - BAG_TAPER) + 0.02, 0.6, BAG_H + 0.012, 0.012)
    towel = inter(shell(towel_base, 0.0, 0.007), box((0.07, 0.6, -0.085), (0.25, 1.0, 0.075)))
    pr.shape("cloth", towel, (0.0, 0.55, -0.12), (0.22, 0.97, 0.12), 0.0035, 1500)
    pr.save(out)


# --- Tee marker -----------------------------------------------------------------------
#
# A spherical plastic tee marker: a 5 in (127 mm) ball with a moulded band
# round it, set on a short spike so it sits a little into the turf.

MARKER_R = 0.0635


def build_tee_marker(out):
    pr = Prop("tee_marker")
    pr.material("plastic", (0.8, 0.1, 0.08, 1), 0.35, clearcoat=0.4)
    c = (0.0, MARKER_R - 0.012, 0.0)
    ball = cut(sphere(c, MARKER_R), box((-1, -1, -1), (1, 0.0, 1)))
    band = turned(torus_y(c, MARKER_R - 0.001, 0.0045), c, "x", 28)
    pr.shape("plastic", union(ball, band), (-0.08, -0.01, -0.08), (0.08, 0.14, 0.08), 0.003, 1400)
    pr.save(out)


# --- Ball washer ensemble -------------------------------------------------------------
#
# From the maker's photo of a tee ensemble: a ring base about 0.5 m across,
# a litter bin 0.33 m across with a black lid at about 0.62 m, a black post
# up through it, and on top a paddle ball washer: a body about 0.17 m across
# and 0.2 m tall with a domed lid, a black knob on the paddle shaft (its top
# about 1.27 m up) and towel clips either side. Its scale comes from the
# ball: the washer is sized to take a 42.7 mm ball in its slot.

def build_ball_washer(out):
    pr = Prop("ball_washer")
    pr.material("paint", (0.78, 0.07, 0.06, 1), 0.42, clearcoat=0.3)
    pr.material("black", (0.06, 0.06, 0.065, 1), 0.6)
    pr.material("steel", (0.85, 0.85, 0.87, 1), 0.3, metal=1.0)
    pr.material("cloth", (0.09, 0.09, 0.1, 1), 0.95)

    ring = torus_y((0, 0.022, 0), 0.235, 0.02)
    spokes = union(*[capsule((0, 0.03, 0), (0.235 * math.cos(a), 0.022, 0.235 * math.sin(a)), 0.014)
                     for a in (0.3, 0.3 + 2.094, 0.3 + 4.189)])
    bin_ = column(0.16, 0.172, 0.04, 0.58, 0.012)
    washer = smooth_union(0.01, column(0.08, 0.087, 0.98, 1.18, 0.01), ellipsoid((0, 1.18, 0), (0.087, 0.035, 0.087)),
                          column(0.03, 0.026, 0.9, 1.0, 0.004))
    slot = box((-0.03, 1.12, 0.05), (0.03, 1.17, 0.12), 0.01)
    flange = column(0.094, 0.094, 0.975, 0.99, 0.004)
    pr.shape("paint", union(ring, spokes), (-0.28, -0.01, -0.28), (0.28, 0.06, 0.28), 0.006, 2600)
    pr.shape("paint", bin_, (-0.2, 0.02, -0.2), (0.2, 0.6, 0.2), 0.006, 6000)
    pr.shape("paint", union(cut(washer, slot), flange), (-0.11, 0.88, -0.11), (0.11, 1.23, 0.11), 0.0035, 4000)

    band = cut(column(0.177, 0.177, 0.12, 0.165, 0.004), column(0.15, 0.15, 0.0, 1.0, 0.0))
    lid = cut(smooth_union(0.02, column(0.178, 0.17, 0.56, 0.63, 0.015), ellipsoid((0, 0.63, 0), (0.17, 0.035, 0.17))),
              rbox((0, 0.62, 0.17), (0.11, 0.035, 0.08), 0.02))
    post = column(0.024, 0.024, 0.6, 0.98, 0.003)
    knob = union(column(0.007, 0.007, 1.2, 1.24, 0.002), sphere((0, 1.255, 0), 0.026))
    slot_back = box((-0.028, 1.122, 0.03), (0.028, 1.168, 0.08), 0.008)
    pr.shape("black", union(band, lid, post, knob, slot_back), (-0.2, 0.08, -0.2), (0.2, 1.3, 0.2), 0.004, 5000)
    for s in (-1, 1):
        tube(pr.parts["steel"], [(s * 0.088, 0.995, 0.0), (s * 0.104, 0.985, 0.0), (s * 0.106, 0.95, 0.0),
                                  (s * 0.096, 0.94, 0.0)], 0.0028, segs=6)
    # A towel on one clip, hanging.
    # Towels on both clips, hanging down to the bin's lid.
    for s in (-1, 1):
        towel = turned(rbox((s * 0.112, 0.79, 0.0), (0.01, 0.15, 0.08), 0.008), (s * 0.106, 0.94, 0), "z", 6 * s)
        pr.shape("cloth", towel, (s * 0.112 - 0.06, 0.6, -0.1), (s * 0.112 + 0.06, 0.96, 0.1), 0.004, 900)
    pr.save(out)


# --- Tee sign ----------------------------------------------------------------------------
#
# From the maker's photo of a cast hole sign: a black square post with a
# round arm, and a panel hung from it with an arched top and a raised gold
# rim (the hole number, par and yardage go on in the game). Scaled from the
# post (about 75 mm square): the panel is about 0.46 by 0.72 m, its foot
# about 0.7 m off the ground. The panel faces +z; the arm reaches +x.

SIGN_PANEL = (0.325, 1.08)  # panel centre (x, y)
SIGN_HALF = (0.23, 0.36)
SIGN_T = 0.012  # half thickness


def sign_outline(grow=0.0):
    cx, cy = SIGN_PANEL
    hx, hy = SIGN_HALF[0] + grow, SIGN_HALF[1] + grow

    def f(x, y, z):
        u, v = np.abs(x - cx), y - cy
        top = hy - 0.05 + 0.05 * np.cos(np.clip(u / hx, 0, 1) * math.pi / 2) ** 0.6 - 0.02 * (u / hx) ** 6
        # The arch: shoulders at the corners rising to a crown in the middle.
        d1 = u - hx
        d2 = np.maximum(-hy - v, v - top)
        out = np.sqrt(np.maximum(d1, 0) ** 2 + np.maximum(d2, 0) ** 2)
        return out + np.minimum(np.maximum(d1, d2), 0)
    return f


def build_tee_sign(out):
    pr = Prop("tee_sign")
    pr.material("black", (0.05, 0.05, 0.052, 1), 0.55, metal=0.2)
    pr.material("gold", (0.86, 0.72, 0.45, 1), 0.38, metal=1.0)

    outline = sign_outline()

    def panel(x, y, z):
        d = outline(x, y, z)
        return np.sqrt(np.maximum(d + 0.006, 0) ** 2 + np.maximum(np.abs(z) - SIGN_T + 0.006, 0) ** 2) - 0.006 \
            + np.minimum(np.maximum(d + 0.006, np.abs(z) - SIGN_T + 0.006), 0)
    post = box((-0.0375, 0.0, -0.0375), (0.0375, 1.72, 0.0375), 0.004)
    cap = box((-0.043, 1.72, -0.043), (0.043, 1.745, 0.043), 0.006)
    arm = capsule((0.03, 1.58, 0.0), (0.63, 1.58, 0.0), 0.024)
    bracket = box((0.03, 1.545, -0.03), (0.06, 1.615, 0.03), 0.004)
    hangers = union(box((0.14, 1.44, -0.007), (0.175, 1.565, 0.007), 0.003),
                    box((0.475, 1.44, -0.007), (0.51, 1.565, 0.007), 0.003))
    pr.shape("black", union(panel, post, cap, arm, bracket, hangers), (-0.06, -0.01, -0.06), (0.68, 1.76, 0.06),
             0.005, 5000)

    # The raised rim round each face, and the end of the arm.
    def rim(x, y, z):
        d = outline(x, y, z)
        ring = np.maximum(d, -(d + 0.012))
        return np.maximum(ring, np.abs(np.abs(z) - SIGN_T) - 0.0025)
    pr.shape("gold", rim, (0.07, 0.69, -0.03), (0.58, 1.47, 0.03), 0.0025, 4000)
    disc = capsule((0.645, 1.58, 0.0), (0.652, 1.58, 0.0), 0.02)
    pr.shape("gold", disc, (0.6, 1.53, -0.05), (0.7, 1.63, 0.05), 0.003, 300)
    pr.save(out)


# --- Bench ----------------------------------------------------------------------------------
#
# A 5 ft (1.52 m) slatted bench with a back and arms, in brown recycled
# plastic lumber, from the maker's photo: seat 0.45 m up and 0.5 m deep,
# vertical back slats between two rails, the back's top at about 0.9 m, arms
# at about 0.65 m. The seat faces +z.

def build_bench(out):
    pr = Prop("tee_bench")
    pr.material("plastic", (0.40, 0.27, 0.18, 1), 0.75)
    L = 0.76  # half length
    parts = []
    for s in (-1, 1):
        x = s * (L - 0.035)
        parts.append(box((x - 0.035, 0.0, 0.19), (x + 0.035, 0.66, 0.26), 0.008))  # front leg, up into the arm
        back = box((x - 0.035, 0.0, -0.035), (x + 0.035, 0.94, 0.035), 0.008)
        parts.append(turned(back, (x, 0.0, -0.22), "x", -10))  # back leg, leaning back
        parts.append(box((x - 0.035, 0.36, -0.25), (x + 0.035, 0.42, 0.24), 0.006))  # seat rail
        parts.append(box((x - 0.045, 0.64, -0.27), (x + 0.045, 0.675, 0.31), 0.012))  # arm
        parts.append(box((x - 0.03, 0.14, -0.22), (x + 0.03, 0.19, 0.22), 0.006))  # stretcher
    for k in range(5):
        z = -0.21 + k * 0.107
        parts.append(box((-L + 0.005, 0.42, z - 0.045), (L - 0.005, 0.45, z + 0.045), 0.006))  # seat slats
    parts.append(box((-L + 0.07, 0.36, 0.2), (L - 0.07, 0.42, 0.24), 0.006))  # front apron
    rails = [box((-L + 0.06, 0.53, -0.255), (L - 0.06, 0.58, -0.225), 0.006),
             box((-L + 0.06, 0.85, -0.31), (L - 0.06, 0.92, -0.28), 0.008)]
    slats = []
    n = 15
    for k in range(n):
        x = -L + 0.12 + k * (2 * L - 0.24) / (n - 1)
        slats.append(box((x - 0.024, 0.55, -0.29), (x + 0.024, 0.87, -0.255), 0.005))
    back_parts = turned(union(*(rails + slats)), (0, 0.45, -0.22), "x", -2)
    pr.shape("plastic", union(*parts, back_parts), (-0.82, -0.01, -0.45), (0.82, 0.97, 0.36), 0.006, 9000)
    pr.save(out)


# --- Bunker rake ------------------------------------------------------------------------------
#
# A 25 in (64 cm) poly head with tapered ends and short teeth, on a 54 in
# (1.37 m) handle with a grip, lying in the sand: the head across x at the
# origin, the handle along +z.

def build_rake(out):
    pr = Prop("bunker_rake")
    pr.material("black", (0.06, 0.06, 0.065, 1), 0.55)
    pr.material("handle", (0.1, 0.3, 0.18, 1), 0.4, metal=0.4)
    head = rbox((0, 0.04, 0), (0.32, 0.024, 0.021), 0.018)
    ends = ellipsoid((0, 0.04, 0), (0.335, 0.07, 0.06))
    head = inter(head, ends)
    teeth = union(*[box((x - 0.004, 0.0, -0.006), (x + 0.004, 0.024, 0.006), 0.002)
                    for x in np.linspace(-0.28, 0.28, 24)])
    socket = capsule((0, 0.045, 0.0), (0, 0.045, 0.07), 0.017)
    grip = capsule((0, 0.022, 1.25), (0, 0.016, 1.39), 0.0155)
    pr.shape("black", union(head, teeth, socket, grip), (-0.35, -0.01, -0.03), (0.35, 0.06, 1.42), 0.004, 3500)
    tube(pr.parts["handle"], [(0, 0.045, 0.06), (0, 0.022, 1.26)], 0.0135, segs=10)
    pr.save(out)


BUILDERS = {"golf_bag": build_bag, "tee_marker": build_tee_marker, "ball_washer": build_ball_washer,
            "tee_sign": build_tee_sign, "tee_bench": build_bench, "bunker_rake": build_rake}

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else OUT
    only = sys.argv[2:] or list(BUILDERS)
    for name in only:
        BUILDERS[name](out)
