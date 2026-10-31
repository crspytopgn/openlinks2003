#!/usr/bin/env python3
"""Builds game/assets/golfer/free_golfer.glb, the golfer shown when the
original game files aren't loaded, and free_golfer_parts.olg, the body,
outfits and hair the player creator dresses it in, from MakeHuman's CC0
assets.

The glb holds the skeleton, the clubs and the animations. The look pack
(look_pack.py) holds every part with its blend shapes: MakeHuman's macro
targets (female, build, muscle, age) and face targets, measured from the
average man in MACROS, with how far each one moves every joint.

    python3 tools/golfer/build_free_golfer.py --mpfb-data DIR --assets DIR [--out FILE]

--mpfb-data is the data/ folder of the MPFB 2 add-on zip (the hm08 base
mesh, macro targets and the game_engine rig with its weights), from
https://extensions.blender.org/add-ons/mpfb/. --assets is the unzipped
MakeHuman system assets pack (skins, clothes, hair, eyes, eyebrows,
eyelashes), from
https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip.
Both are CC0; see game/assets/golfer/LICENSE.md. Only data files are read.

The swing, putt and celebration are keyed by hand in pose.py and SWINGS
below. Needs numpy and Pillow. Afterwards run mocap_swing.py, which replaces
the backswing, swing and putt with motion capture.
"""

import argparse
import io
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import face_landmarks  # noqa: E402
import gltf  # noqa: E402
import look_pack  # noqa: E402
import mhuman  # noqa: E402
import pose  # noqa: E402
from pose import Key  # noqa: E402

FPS = 30

# The body: a man of about 35, average build, 1.83 m.
MACROS = dict(gender=1.0, age=0.6, muscle=0.6, weight=0.55, height=0.5, proportions=0.75)
SKIN = "skins/middleage_caucasian_male/middleage_caucasian_male.mhmat"
SKIN_FEMALE = "skins/middleage_caucasian_female/middleage_caucasian_female.mhmat"
SHOES = "clothes/shoes05/shoes05.mhclo"
EYES = "eyes/high-poly/high-poly.mhclo"
EYE_MATERIAL = "eyes/materials/brown.mhmat"
# Other eye colours, written next to the glb as look/eyes_<name>.png.
EYE_COLOURS = {"blue": "blue", "green": "green", "grey": "grey", "hazel": "brownlight", "brown": "brown"}
EYEBROWS = "eyebrows/eyebrow001/eyebrow001.mhclo"
EYELASHES = "eyelashes/eyelashes01/eyelashes01.mhclo"
SHIRT = (0.11, 0.2, 0.38)  # navy polo
TROUSERS = (0.72, 0.64, 0.5)  # stone chinos

# Outfits: (name, mhclo, which texture pixels are mostly the trousers or
# shorts, as (top row, right column) fractions of the image, for evening out
# the texture; the mesh is split into shirt and trousers by its pieces).
OUTFITS = [
    ("polo", "clothes/male_casualsuit06/male_casualsuit06.mhclo", (0.44, 1.0)),
    ("sleeves", "clothes/male_casualsuit02/male_casualsuit02.mhclo", (0.42, 0.72)),
    ("shorts", "clothes/female_casualsuit02/female_casualsuit02.mhclo", (0.40, 0.68)),
]
# Hair styles (the first is the default) and their MakeHuman assets.
HAIR_STYLES = [
    ("short", "hair/short02/short02.mhclo"),
    ("crop", "hair/short04/short04.mhclo"),
    ("side_part", "hair/short03/short03.mhclo"),
    ("ponytail", "hair/ponytail01/ponytail01.mhclo"),
    ("bob", "hair/bob01/bob01.mhclo"),
    ("long", "hair/long01/long01.mhclo"),
    ("afro", "hair/afro01/afro01.mhclo"),
]
# The cap is sized to sit over these.
CAP_HAIR = ("short", "crop", "side_part", "ponytail")

# Tinted materials use a grey "detail" texture averaging DETAIL_MEAN; the
# game multiplies it by the player's colour (PlayerLook).
DETAIL_MEAN = 0.85

# Body shapes (blend shapes) from MakeHuman's macro sliders: the macros
# they change from MACROS.
BODY_SHAPES = {
    "female": dict(gender=0.0),
    "thin": dict(weight=0.1), "heavy": dict(weight=1.0),
    "slight": dict(muscle=0.25), "muscular": dict(muscle=1.0),
    "young": dict(age=0.5), "old": dict(age=0.9),
}
# Face shapes: slider -> (targets for -1, targets for +1), paths under
# MPFB's data/targets/.
FACE_SHAPES = {
    "face_width": (["head/head-scale-horiz-decr"], ["head/head-scale-horiz-incr"]),
    "face_length": (["head/head-scale-vert-decr"], ["head/head-scale-vert-incr"]),
    "face_full": (["head/head-fat-decr"], ["head/head-fat-incr"]),
    "jaw": (["chin/chin-width-decr"], ["chin/chin-width-incr"]),
    "chin": (["chin/chin-prominent-decr"], ["chin/chin-prominent-incr"]),
    "chin_height": (["chin/chin-height-decr"], ["chin/chin-height-incr"]),
    "cheekbones": (["cheek/l-cheek-bones-decr", "cheek/r-cheek-bones-decr"],
                   ["cheek/l-cheek-bones-incr", "cheek/r-cheek-bones-incr"]),
    "nose_width": (["nose/nose-scale-horiz-decr"], ["nose/nose-scale-horiz-incr"]),
    "nose_length": (["nose/nose-scale-vert-decr"], ["nose/nose-scale-vert-incr"]),
    "nose_bridge": (["nose/nose-hump-decr"], ["nose/nose-hump-incr"]),
    "eye_size": (["eyes/l-eye-scale-decr", "eyes/r-eye-scale-decr"], ["eyes/l-eye-scale-incr", "eyes/r-eye-scale-incr"]),
    "eye_spacing": (["eyes/l-eye-trans-in", "eyes/r-eye-trans-in"], ["eyes/l-eye-trans-out", "eyes/r-eye-trans-out"]),
    "mouth_width": (["mouth/mouth-scale-horiz-decr"], ["mouth/mouth-scale-horiz-incr"]),
    "lips": (["mouth/mouth-upperlip-volume-decr", "mouth/mouth-lowerlip-volume-decr"],
             ["mouth/mouth-upperlip-volume-incr", "mouth/mouth-lowerlip-volume-incr"]),
    "brows": (["eyebrows/eyebrows-trans-down"], ["eyebrows/eyebrows-trans-up"]),
    "ears": (["ears/l-ear-scale-decr", "ears/r-ear-scale-decr"], ["ears/l-ear-scale-incr", "ears/r-ear-scale-incr"]),
}

TOP = Key(hands=148, hinge=112, turn=92, hips=42, tilt=37, bend=2, shift=0.03, sink=0.0, lheel=4, face=8)
FINISH = Key(hands=-138, hinge=-112, turn=-108, hips=-90, tilt=12, bend=-6, shift=-0.09, head=1, heel=55, face=-20)

SWINGS = {
    "address": [Key(t=0), Key(t=1.0, tilt=36.4), Key(t=2.0)],
    "address_putt": [Key(t=0, putt=1), Key(t=1.0, putt=1, tilt=36.4 + 6), Key(t=2.0, putt=1)],
    "backswing": [
        Key(t=0),
        Key(t=0.3, hands=35, hinge=4, turn=30, hips=12, tilt=36, bend=9, shift=0.01),
        Key(t=0.6, hands=95, hinge=55, turn=70, hips=30, tilt=36.5, bend=5, shift=0.025, face=4),
        Key(t=0.9, **{k: getattr(TOP, k) for k in Key.__dataclass_fields__ if k != "t"}),
    ],
    "swing": [
        Key(t=0, **{k: getattr(TOP, k) for k in Key.__dataclass_fields__ if k != "t"}),
        Key(t=0.08, hands=128, hinge=118, turn=78, hips=20, tilt=37, bend=6, shift=0.0, lheel=1, face=8),
        Key(t=0.15, hands=70, hinge=95, turn=40, hips=-12, tilt=36, bend=14, shift=-0.05, face=4),
        Key(t=0.2, hands=0, hinge=0, turn=-12, hips=-38, tilt=34, bend=17, shift=-0.07, heel=8),
        Key(t=0.27, hands=-55, hinge=-45, turn=-45, hips=-55, tilt=31, bend=13, shift=-0.08, head=0.2, heel=20, face=-10),
        Key(t=0.4, hands=-112, hinge=-85, turn=-85, hips=-78, tilt=22, bend=3, shift=-0.09, head=0.7, heel=40, face=-18),
        Key(t=0.6, **{k: getattr(FINISH, k) for k in Key.__dataclass_fields__ if k != "t"}),
        Key(t=1.6, **{k: getattr(FINISH, k) for k in Key.__dataclass_fields__ if k != "t"}),
    ],
    "putt": [
        Key(t=0),
        Key(t=0.25, putt=1),
        Key(t=0.6, putt=1, hands=10, hinge=-1, turn=5, bend=4),
        Key(t=0.85, putt=1, hands=0, turn=0, bend=4),
        Key(t=1.05, putt=1, hands=-14, hinge=1, turn=-6, bend=4, head=0.15),
        Key(t=1.8, putt=1, hands=-14, hinge=1, turn=-6, bend=4, head=0.5),
    ],
    "celebrate": [
        Key(t=0, putt=1, hands=-14, turn=-6, bend=4, head=0.5),
        Key(t=0.3, putt=1, hands=-5, turn=-10, tilt=20, bend=0, head=0.9, cheer=1.0),
        Key(t=0.5, putt=1, hands=-5, turn=-10, tilt=18, bend=0, head=0.9, cheer=0.75),
        Key(t=0.7, putt=1, hands=-5, turn=-10, tilt=18, bend=0, head=0.9, cheer=1.0),
        Key(t=1.5, putt=1, hands=-5, turn=-8, tilt=14, bend=0, head=0.8, cheer=0.0),
    ],
}


def encode(g, im, size, mime="image/jpeg"):
    im = im.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    if mime == "image/png":
        im.save(buf, "PNG", optimize=True)
    else:
        im.save(buf, "JPEG", quality=88)
    return buf.getvalue() if g is None else g.image(buf.getvalue(), mime)


def _median_filter(lum, size):
    img = Image.fromarray((np.clip(lum, 0, 1) * 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.MedianFilter(size)), dtype=np.float64) / 255


def skin_detail(path, head_uvs):
    """The skin as grey detail (each channel over its mean) and its mean
    colour, so detail * mean / DETAIL_MEAN gives the texture back. The head
    (the texture's face and scalp, drawn from the uv triangles in head_uvs)
    is evened out separately, so it matches the neck whatever the tint."""
    im = Image.open(path).convert("RGB")
    a = np.asarray(im, dtype=np.float64) / 255
    w, h = im.size
    mask = Image.new("L", im.size, 0)
    draw = ImageDraw.Draw(mask)
    for tri in head_uvs:
        draw.polygon([(u * w, v * h) for u, v in tri], fill=255)
    head = np.asarray(mask.filter(ImageFilter.MaxFilter(5))) > 0
    # The face and body, not the dark unused corners of the atlas.
    used = a.max(axis=2) > 0.15
    mean = a[used & ~head].mean(axis=0)
    out = a / mean * DETAIL_MEAN
    head_mean = a[used & head].mean(axis=0)
    out[head] = (a / head_mean * DETAIL_MEAN)[head]
    out = np.clip(out, 0, 1)
    return Image.fromarray((out * 255).astype(np.uint8)), mean


def cloth_detail(path, bottom_rect):
    """An outfit's texture as grey detail, logos and trim removed: the shirt
    and the trousers (pixels in bottom_rect, (top row, right column) as
    fractions) each average DETAIL_MEAN. The trousers keep only the weave:
    their denim fading is flattened away."""
    im = Image.open(path).convert("RGB")
    if im.size[0] > 1024:
        im = im.resize((1024, 1024), Image.LANCZOS)
    a = np.asarray(im, dtype=np.float64) / 255
    h, w = a.shape[:2]
    lum = a @ np.array([0.3, 0.59, 0.11])
    chroma = a / np.maximum(lum, 0.02)[..., None]
    bottom = np.zeros(lum.shape, bool)
    bottom[int(h * bottom_rect[0]):, : int(w * bottom_rect[1])] = True
    smooth = _median_filter(lum, 31)
    blur = lambda x, r: np.asarray(Image.fromarray((np.clip(x, 0, 1) * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(r)), dtype=np.float64) / 255
    out = np.zeros_like(lum)
    for region, is_bottom in ((~bottom, False), (bottom, True)):
        typical = np.median(chroma[region], axis=0)
        # Printed logos and coloured trim on the shirt: off the cloth's
        # colour, or darker. (Denim varies too much to tell.)
        odd = region & ((np.abs(chroma - typical).max(axis=2) > 0.18) | (lum < smooth - 0.06))
        odd = np.asarray(Image.fromarray((odd * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(15))) > 0
        if is_bottom:
            odd[:] = False
        med = np.median(lum[region & ~odd])
        clean = np.where(odd, med, lum)
        if is_bottom:
            weave = clean / np.maximum(blur(clean, 12), 0.02)
            detail = DETAIL_MEAN * np.power(np.clip(weave, 0.05, 3), 0.7)
        else:
            detail = DETAIL_MEAN * np.clip(clean / med, 0.05, 3)
        out[region] = detail[region]
    out = np.clip(out, 0, 1)
    return Image.fromarray((np.repeat(out[..., None], 3, axis=2) * 255).astype(np.uint8))


def alpha_detail(path, size):
    """Hair or eyebrows (with alpha) as grey detail, and the mean colour."""
    im = Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)
    a = np.asarray(im, dtype=np.float64) / 255
    solid = a[..., 3] > 0.5
    mean = a[..., :3][solid].mean(axis=0)
    lum = a[..., :3] @ np.array([0.3, 0.59, 0.11])
    mean_lum = float(mean @ np.array([0.3, 0.59, 0.11]))
    detail = np.clip(DETAIL_MEAN * np.power(np.maximum(lum, 1e-3) / mean_lum, 0.9), 0, 1)
    # Drawn with an alpha cutoff and tinted, so 64 grey levels and 16 alpha
    # levels look the same and compress far better.
    detail = np.round(detail * 63) / 63
    alpha = np.round(a[..., 3:] * 15) / 15
    out = np.concatenate([np.repeat(detail[..., None], 3, axis=2), alpha], axis=2)
    return Image.fromarray(np.round(out * 255).astype(np.uint8), "RGBA"), mean


def lathe(profile, axis, side, segments=12):
    """A surface of revolution: profile is [(distance along axis, radius)]."""
    a = pose.unit(axis)
    u = pose.unit(side - a * np.dot(side, a))
    v = np.cross(a, u)
    pos, nrm, idx = [], [], []
    for d, r in profile:
        for s in range(segments):
            th = 2 * math.pi * s / segments
            radial = math.cos(th) * u + math.sin(th) * v
            pos.append(a * d + radial * r)
            nrm.append(radial)
    for i in range(len(profile) - 1):
        for s in range(segments):
            a0 = i * segments + s
            a1 = i * segments + (s + 1) % segments
            b0, b1 = a0 + segments, a1 + segments
            idx += [(a0, b0, a1), (a1, b0, b1)]
    return np.array(pos), np.array(nrm), np.array(idx)


def ellipsoid(centre, axes, radii, rings=10, segments=16, flat_front=None):
    pos, nrm, idx = [], [], []
    for i in range(rings + 1):
        phi = math.pi * i / rings - math.pi / 2
        for s in range(segments):
            th = 2 * math.pi * s / segments
            unit_p = np.array([math.cos(phi) * math.cos(th), math.cos(phi) * math.sin(th), math.sin(phi)])
            local = unit_p * radii
            if flat_front is not None and local[1] > flat_front:
                local[1] = flat_front
            p = centre + axes @ local
            n = axes @ pose.unit(unit_p / np.maximum(radii, 1e-6))
            pos.append(p)
            nrm.append(n)
    for i in range(rings):
        for s in range(segments):
            a0 = i * segments + s
            a1 = i * segments + (s + 1) % segments
            b0, b1 = a0 + segments, a1 + segments
            idx += [(a0, a1, b0), (a1, b1, b0)]
    return np.array(pos), np.array(nrm), np.array(idx)


def box(centre, axes, half):
    pos, nrm, idx = [], [], []
    for axis in range(3):
        for sign in (-1, 1):
            n = np.zeros(3)
            n[axis] = sign
            u, v = [i for i in range(3) if i != axis]
            base = len(pos)
            for du, dv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                p = np.zeros(3)
                p[axis] = sign * half[axis]
                p[u] = du * half[u]
                p[v] = dv * half[v]
                pos.append(centre + axes @ p)
                nrm.append(axes @ n)
            quad = [(base, base + 1, base + 2), (base, base + 2, base + 3)]
            if sign * (1 if (u, v) in ((1, 2), (2, 0), (0, 1)) else -1) < 0:
                quad = [(a, c, b) for a, b, c in quad]
            idx += quad
    return np.array(pos), np.array(nrm), np.array(idx)


def club_parts(poser, club):
    """The club's pieces in the rest frame, held in the left hand."""
    grip = poser.grip_rest["l"]
    a = poser.club_dir_rest["l"]
    f = poser.face_rest["l"]
    b = np.cross(a, f)
    toe = pose.Poser._toe(a, f, club)
    up = pose.unit(np.cross(toe, f))
    if np.dot(up, a) > 0:
        up = -up
    hosel = grip + a * club.length
    parts = []
    grip_len = 0.27
    parts.append(("grip", lathe([(-0.085, 0.0), (-0.085, 0.0135), (grip_len - 0.085, 0.0105), (grip_len - 0.08, 0.0)],
                                a, b)))
    parts.append(("shaft", lathe([(grip_len - 0.09, 0.0075), (club.length, 0.0045), (club.length + 0.02, 0.006)], a, b)))
    for name, part in parts:
        part[0][:] += grip
    axes = np.column_stack([toe, f, up])
    if club.name == "Driver":
        centre = hosel + toe * 0.052 - f * 0.038 + up * 0.012
        parts.append(("head", ellipsoid(centre, axes, np.array([0.058, 0.05, 0.029]), flat_front=0.036)))
    else:
        centre = hosel + toe * 0.045 + up * 0.012
        parts.append(("head", box(centre, axes, np.array([0.055, 0.012, 0.012]))))
    return parts


def add_club(g, poser, club, skin, materials):
    joint = poser.club_joint
    for piece, (pos, nrm, idx) in club_parts(poser, club):
        n = len(pos)
        g.skinned_mesh(f"{club.name}_{piece}", pos.astype(np.float32), nrm.astype(np.float32),
                       np.zeros((n, 2), np.float32), np.tile([joint, 0, 0, 0], (n, 1)).astype(np.uint8),
                       np.tile([1.0, 0, 0, 0], (n, 1)).astype(np.float32), idx.astype(np.uint32),
                       materials[piece if piece != "head" else club.name], skin)


def covered_vertices(body, cloth, max_gap=0.03, opening=0.012):
    """Body vertices hidden under a garment, beyond the ones its .mhclo
    deletes: those just inside the cloth, away from its openings (collar,
    cuffs, hems), so skin can't poke through when the body changes shape.
    body: positions; cloth: a fitted Part. Returns a set of indices."""
    pos, nrm = cloth.positions, cloth.normals
    # Openings: vertices on edges only one triangle uses.
    edges = {}
    for tri in cloth.indices:
        for a, b in ((tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0])):
            key = (min(a, b), max(a, b))
            edges[key] = edges.get(key, 0) + 1
    rim = np.array(sorted({v for e, n in edges.items() if n == 1 for v in e}), dtype=np.int64)
    near_rim = np.zeros(len(pos), bool)
    if len(rim):
        for start in range(0, len(pos), 2048):
            d = np.linalg.norm(pos[start:start + 2048, None] - pos[rim][None], axis=2).min(axis=1)
            near_rim[start:start + 2048] = d < opening
    out = set()
    for start in range(0, len(body), 1024):
        chunk = body[start:start + 1024]
        d = np.linalg.norm(chunk[:, None] - pos[None], axis=2)
        j = d.argmin(axis=1)
        gap = d[np.arange(len(chunk)), j]
        inside = ((pos[j] - chunk) * nrm[j]).sum(axis=1) > -0.002
        hit = (gap < max_gap) & inside & ~near_rim[j]
        out.update((start + np.nonzero(hit)[0]).tolist())
    return out


def lower_faces(verts, faces):
    """The faces of an outfit's trousers or shorts: the pieces of the mesh
    (connected parts) that sit below the waist."""
    parent = list(range(len(verts)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for face in faces:
        root = find(face[0][0])
        for v, _ in face[1:]:
            parent[find(v)] = root
    pieces = {}
    for face in faces:
        pieces.setdefault(find(face[0][0]), []).append(face)
    lower = set()
    for piece in pieces.values():
        # MakeHuman units: the hips are at about 0, the waist at about 1.
        if np.mean([verts[f[0][0]][1] for f in piece]) < 1.0:
            lower.update(tuple(f) for f in piece)
    return lower


def cap_mesh(points, brow_y, hair=0.014, segments=40, rings=10):
    """A golf cap over `points` (the head, in the rig frame), with room for
    `hair` (metres) of short hair: a crown shrink-wrapped to the skull that
    sits on the brow at the front and lower at the back, and a curved peak
    at the front (-z). Returns positions, normals and triangles."""
    p = points[points[:, 1] > brow_y - 0.06]
    top = p[p[:, 1] > brow_y]
    lo, hi = top.min(axis=0), top.max(axis=0)
    centre = np.array([(lo[0] + hi[0]) / 2, brow_y, (lo[2] + hi[2]) / 2])
    rel = p - centre
    dist = np.linalg.norm(rel, axis=1)
    dirs = rel / dist[:, None]

    def reach(u):
        """How far the head goes from the centre along u, plus the hair."""
        near = dirs @ u > math.cos(math.radians(9))
        return (dist[near].max() if near.any() else 0.09) + hair

    grid = []
    for i in range(rings + 1):
        phi = math.pi / 2 * i / rings
        row = []
        for k in range(segments):
            th = 2 * math.pi * k / segments
            back = max(0.0, math.cos(th))  # +z is the back of the head
            # The band drops behind the ears.
            phi_eff = phi - (1 - i / rings) * math.radians(22) * back
            u = np.array([math.cos(phi_eff) * math.sin(th), math.sin(phi_eff), math.cos(phi_eff) * math.cos(th)])
            row.append(reach(u) * u)
        grid.append(row)
    grid = np.array(grid)
    # Smooth the crown so it reads as cloth, not a scan of the skull.
    for _ in range(3):
        r = np.linalg.norm(grid, axis=2)
        r = (r + np.roll(r, 1, axis=1) + np.roll(r, -1, axis=1)) / 3
        r[1:-1] = (r[1:-1] * 2 + r[:-2] + r[2:]) / 4
        grid = grid / np.linalg.norm(grid, axis=2, keepdims=True) * r[..., None]
    pos = list((grid + centre).reshape(-1, 3))
    nrm = list(grid.reshape(-1, 3) / np.linalg.norm(grid.reshape(-1, 3), axis=1, keepdims=True))
    tris = []
    for i in range(rings):
        for k in range(segments):
            a0, a1 = i * segments + k, i * segments + (k + 1) % segments
            b0, b1 = a0 + segments, a1 + segments
            tris += [(a0, a1, b0), (a1, b1, b0)]
    # The peak: from the front of the band, about 7 cm out, curving down
    # towards its sides and dipping a little at the tip.
    band = grid[0] + centre
    base = len(pos)
    steps, depth = 22, 5
    span = math.radians(62)
    for k in range(steps + 1):
        a = -1.0 + 2.0 * k / steps
        th = math.pi + a * span
        k_f = (th / (2 * math.pi)) * segments
        k0 = int(math.floor(k_f)) % segments
        t_k = k_f - math.floor(k_f)
        edge = band[k0] * (1 - t_k) + band[(k0 + 1) % segments] * t_k
        out = pose.unit(np.array([math.sin(th), 0.0, math.cos(th)]))
        length = 0.072 * math.sqrt(max(0.0, 1 - a * a)) ** 0.8
        for d in range(depth + 1):
            t = d / depth
            q = edge + out * (length * t + 0.001)
            q[1] -= 0.003 + length * t * 0.15 + 0.018 * a * a * t
            pos.append(q)
            nrm.append(pose.unit(np.array([0, 1.0, 0]) + out * 0.2))
    for k in range(steps):
        for d in range(depth):
            a0 = base + k * (depth + 1) + d
            a1 = a0 + 1
            b0 = a0 + depth + 1
            b1 = b0 + 1
            tris += [(a0, b0, a1), (a1, b0, b1)]
    return np.array(pos), np.array(nrm), np.array(tris, dtype=np.uint32)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--mpfb-data", required=True)
    ap.add_argument("--assets", required=True)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "..", "game", "assets",
                                                   "golfer", "free_golfer.glb"))
    args = ap.parse_args()
    A = lambda rel: os.path.join(args.assets, rel)
    mhmat = lambda mhclo: mhuman.read_mhmat(mhclo.replace(".mhclo", ".mhmat"))

    human = mhuman.Human(args.mpfb_data, args.assets)
    human.morph(**MACROS)
    human.build_rig()
    names = human.bones
    poser = pose.Poser(human)
    defaults = {}
    pack = look_pack.Pack()

    # Textures and materials. Tinted ones are grey detail (see DETAIL_MEAN).
    head_j = names.index("head")
    head_uvs = []
    for face in human.body_faces():
        if human.base_weights[[v for v, _ in face], head_j].mean() > 0.9:
            uv = human.base_uvs[[t for _, t in face]]
            head_uvs.append([(u, 1.0 - v) for u, v in uv])
    skin_dir = os.path.dirname(A(SKIN))
    img, mean = skin_detail(os.path.join(skin_dir, mhuman.read_mhmat(A(SKIN))["diffuseTexture"]), head_uvs)
    defaults["skin"] = mean / DETAIL_MEAN
    pack.material("Skin", pack.image(encode(None, img, 1024), "jpg"), roughness=0.62, tint="skin")
    female_dir = os.path.dirname(A(SKIN_FEMALE))
    img, mean = skin_detail(os.path.join(female_dir, mhuman.read_mhmat(A(SKIN_FEMALE))["diffuseTexture"]), head_uvs)
    defaults["skin_female"] = mean / DETAIL_MEAN
    female_skin = pack.image(encode(None, img, 1024), "jpg")
    for name, mhclo, rect in OUTFITS:
        folder = os.path.dirname(A(mhclo))
        mat = mhmat(A(mhclo))
        tex = pack.image(encode(None, cloth_detail(os.path.join(folder, mat["diffuseTexture"]), rect), 1024), "jpg")
        normal = pack.image(encode(None, Image.open(os.path.join(folder, mat["normalmapTexture"])).convert("RGB"),
                                   512), "jpg")
        pack.material(f"Top_{name}", tex, normal, roughness=0.9, tint="top")
        pack.material(f"Bottom_{name}", tex, normal, roughness=0.9, tint="bottom")
    defaults["top"] = np.array(SHIRT) / DETAIL_MEAN
    defaults["bottom"] = np.array(TROUSERS) / DETAIL_MEAN
    shoes_dir = os.path.dirname(A(SHOES))
    shoes_img = Image.open(os.path.join(shoes_dir, mhmat(A(SHOES))["diffuseTexture"])).convert("RGB")
    pack.material("Shoes", pack.image(encode(None, shoes_img, 512), "jpg"), roughness=0.55, tint="shoes")
    defaults["shoes"] = np.ones(3)
    for name, mhclo in HAIR_STYLES:
        folder = os.path.dirname(A(mhclo))
        img, mean = alpha_detail(os.path.join(folder, mhmat(A(mhclo))["diffuseTexture"]), 512)
        if name == HAIR_STYLES[0][0]:
            defaults["hair"] = mean / DETAIL_MEAN
        pack.material(f"Hair_{name}", pack.image(encode(None, img.convert("LA"), 512, "image/png"), "png"), roughness=0.7,
                      cutoff=0.5, double_sided=True, tint="hair")
    eye_dir = os.path.dirname(A(EYE_MATERIAL))
    eye_images = {}
    for colour, source in EYE_COLOURS.items():
        img = Image.open(os.path.join(eye_dir, mhuman.read_mhmat(os.path.join(eye_dir, source + ".mhmat"))[
            "diffuseTexture"])).convert("RGBA")
        eye_images[colour] = pack.image(encode(None, img, 256, "image/png"), "png")
    pack.material("Eyes", eye_images["brown"], roughness=0.15, cutoff=0.5)
    brow_dir = os.path.dirname(A(EYEBROWS))
    img, _ = alpha_detail(os.path.join(brow_dir, "eyebrow001.png"), 256)
    pack.material("Eyebrows", pack.image(encode(None, img.convert("LA"), 256, "image/png"), "png"), roughness=0.8, cutoff=0.12,
                  double_sided=True, tint="brows")
    lash_dir = os.path.dirname(A(EYELASHES))
    img = Image.open(os.path.join(lash_dir, "eyelashes01.png")).convert("RGBA")
    pack.material("Eyelashes", pack.image(encode(None, img, 256, "image/png"), "png"), roughness=0.8, cutoff=0.25,
                  double_sided=True)
    pack.material("Cap", roughness=0.85, double_sided=True, tint="cap")

    g = gltf.Gltf()
    club_materials = {
        "grip": g.material("Grip", colour=(0.05, 0.05, 0.055, 1), roughness=0.9),
        "shaft": g.material("Shaft", colour=(0.75, 0.76, 0.78, 1), roughness=0.25, metallic=1.0),
        "Driver": g.material("DriverHead", colour=(0.06, 0.06, 0.07, 1), roughness=0.3, metallic=0.5),
        "Putter": g.material("PutterHead", colour=(0.7, 0.71, 0.73, 1), roughness=0.3, metallic=1.0),
    }

    # Skeleton nodes, parents first; every rest rotation is the identity.
    joint_nodes = []
    for i, name in enumerate(names):
        p = human.parents[i]
        offset = human.heads[i] - (human.heads[p] if p >= 0 else 0)
        joint_nodes.append(g.node(name=name, translation=[float(x) for x in offset]))
    club_node = g.node(name="club", translation=[float(x) for x in poser.grip_rest["l"] - human.heads[names.index("hand_l")]])
    joint_nodes.append(club_node)
    for i, name in enumerate(names):
        children = [joint_nodes[j] for j in range(len(names)) if human.parents[j] == i]
        if name == "hand_l":
            children.append(club_node)
        if children:
            g.doc["nodes"][joint_nodes[i]]["children"] = children
    g.doc["scenes"][0]["nodes"].append(joint_nodes[0])
    positions = np.vstack([human.heads, poser.grip_rest["l"][None]])
    ibm = np.tile(np.eye(4), (len(positions), 1, 1))
    ibm[:, 3, :3] = -positions  # column-major: translation in the last column
    g.doc.setdefault("skins", []).append({"name": "Golfer", "joints": joint_nodes, "skeleton": joint_nodes[0],
                                          "inverseBindMatrices": g.accessor(ibm.reshape(-1, 16).astype(np.float32))})
    skin = 0

    # The meshes. The body is split by which outfits cover it, so skin
    # hidden under trousers (say) isn't drawn, but shows with shorts.
    parts = []
    shoes, shoes_proxy = human.proxy_part("Shoes", A(SHOES), "Shoes")
    outfit_proxies = [mhuman.Proxy(A(mhclo)) for _, mhclo, _ in OUTFITS]
    body_rig = human.to_rig(human.coords)
    under = [covered_vertices(body_rig, human.proxy_part("", pr, "")[0]) for pr in outfit_proxies]
    chunks = {}
    for face in human.body_faces():
        vs = [v for v, _ in face]
        if any(v in shoes_proxy.deleted for v in vs):
            continue
        covered = tuple(i for i, pr in enumerate(outfit_proxies)
                        if any(v in pr.deleted for v in vs) or all(v in under[i] for v in vs))
        if len(covered) == len(OUTFITS):
            continue
        chunks.setdefault(covered, []).append(face)
    body_chunks = {}
    for n, covered in enumerate(sorted(chunks, key=lambda c: (len(c), c))):
        name = "Body" if not covered else f"Body_{n}"
        mine = {tuple(f) for f in chunks[covered]}
        parts.append(human.body_part("Skin", name=name, keep=lambda f, mine=mine: tuple(f) in mine))
        if covered:
            body_chunks[name] = [OUTFITS[i][0] for i in covered]
    for (name, _, _), proxy in zip(OUTFITS, outfit_proxies):
        verts, _, faces, _ = mhuman.read_obj(os.path.join(proxy.folder, proxy.obj))
        lower = lower_faces(verts, faces)
        parts.append(human.proxy_part(f"Top_{name}", proxy, f"Top_{name}",
                                      keep=lambda f, lower=lower: tuple(f) not in lower)[0])
        parts.append(human.proxy_part(f"Bottom_{name}", proxy, f"Bottom_{name}",
                                      keep=lambda f, lower=lower: tuple(f) in lower)[0])
    parts.append(shoes)
    hair_parts = {}
    for name, mhclo in HAIR_STYLES:
        hair_parts[name] = human.proxy_part(f"Hair_{name}", A(mhclo), f"Hair_{name}")[0]
        parts.append(hair_parts[name])
    for name, path in (("Eyes", EYES), ("Eyebrows", EYEBROWS), ("Eyelashes", EYELASHES)):
        parts.append(human.proxy_part(name, A(path), name)[0])
    brows = parts[-2]

    # The cap, on the head bone, over the head and the shorter hair styles.
    head_j = names.index("head")
    body_rig = human.to_rig(human.coords)
    on_head = human.base_weights[:, head_j] > 0.5
    brow_y = float(brows.positions[:, 1].mean() + 0.022)
    cap_pos, cap_nrm, cap_idx = cap_mesh(body_rig[on_head], brow_y)
    head_ids = np.nonzero(on_head)[0]
    nearest = head_ids[np.argmin(((cap_pos[:, None, :] - body_rig[head_ids][None]) ** 2).sum(axis=2), axis=1)]

    # Blend shapes: each shape's offsets for every part, and how far it
    # moves each joint and the top of the head.
    base_heads = human.heads.copy()
    base_coords = human.coords.copy()
    top_y = float(body_rig[:, 1].max())
    shape_offsets = {}
    for name, macros in BODY_SHAPES.items():
        shape_offsets[name] = human.macro_offsets(**dict(MACROS, **macros)) - (base_coords - human.base)
    for slider, (minus, plus) in FACE_SHAPES.items():
        shape_offsets[slider + "_minus"] = human.target_offsets(minus)
        shape_offsets[slider + "_plus"] = human.target_offsets(plus)
    # The face landmarks a photo is fitted to, seen from the front (x to
    # the person's left, y up, metres), and how each shape moves them.
    marks = [v for v in face_landmarks.find(human, A(EYEBROWS)).values()]
    face_fit = {
        "points": face_landmarks.POINTS,
        "base": [[round(float(x) * mhuman.DM_TO_M, 5) for x in base_coords[v, :2]] for v in marks],
        "shapes": {name: [[round(float(x) * mhuman.DM_TO_M, 5) for x in off[v, :2]] for v in marks]
                   for name, off in shape_offsets.items()},
    }
    targets = {part.name: [] for part in parts}
    targets["Cap"] = []
    shapes = {}
    for name, offset in shape_offsets.items():
        human.coords = base_coords + offset
        human.measure()
        moved = human.to_rig(human.coords)
        for part in parts:
            pos, nrm = part.at(human.source_positions(part))
            targets[part.name].append((name, pos - part.positions, nrm - part.normals))
        d_body = moved - body_rig
        targets["Cap"].append((name, d_body[nearest], np.zeros_like(cap_nrm)))
        joints = {}
        for i, bone in enumerate(names):
            d = human.heads[i] - base_heads[i]
            if np.abs(d).max() > 1e-5:
                joints[bone] = [round(float(x), 5) for x in d]
        shapes[name] = {"joints": joints, "height": round(float(moved[:, 1].max() - top_y), 5)}
    human.coords = base_coords
    human.measure()

    for part in parts:
        pack.part(part.name, part.material, part.positions, part.normals, part.uvs, part.joints, part.joint_weights,
                  part.indices, targets[part.name], with_tangents=part.name.startswith(("Top_", "Bottom_")),
                  tolerance=5e-4 if part.name.startswith(("Body", "Eye")) else 1.5e-3)
    n = len(cap_pos)
    pack.part("Cap", "Cap", cap_pos, cap_nrm, np.zeros((n, 2)), np.tile([head_j, 0, 0, 0], (n, 1)),
              np.tile([1.0, 0, 0, 0], (n, 1)), cap_idx, targets["Cap"])
    add_club(g, poser, pose.DRIVER, skin, club_materials)
    add_club(g, poser, pose.PUTTER, skin, club_materials)

    # Animations.
    animations = []
    for clip, keys in SWINGS.items():
        frames = int(round(keys[-1].t * FPS)) + 1
        times = np.arange(frames, dtype=np.float32) / FPS
        rots = np.zeros((len(names), frames, 4), np.float32)
        root = np.zeros((frames, 3), np.float32)
        for f, t in enumerate(times):
            R, root_p, _ = poser.pose(pose.interpolate(keys, float(t)))
            local, _, root_p = poser.locals(R, root_p)
            for j, q in enumerate(local):
                rots[j, f] = q
            root[f] = root_p
        # Keep quaternions in one hemisphere so playback doesn't flip.
        for j in range(len(names)):
            for f in range(1, frames):
                if np.dot(rots[j, f], rots[j, f - 1]) < 0:
                    rots[j, f] = -rots[j, f]
        t_acc = g.accessor(times, minmax=True)
        samplers, channels = [], []
        for j in range(len(names)):
            samplers.append({"input": t_acc, "output": g.accessor(rots[j]), "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": joint_nodes[j], "path": "rotation"}})
        samplers.append({"input": t_acc, "output": g.accessor(root), "interpolation": "LINEAR"})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": joint_nodes[0], "path": "translation"}})
        animations.append({"name": clip, "samplers": samplers, "channels": channels})
    g.doc["animations"] = animations

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    g.save(args.out)
    print(f"wrote {args.out} ({os.path.getsize(args.out) / 1e6:.1f} MB)")
    parts_path = os.path.splitext(args.out)[0] + "_parts.olg"
    pack.save(parts_path,
              bones=names + ["club"],
              detail_mean=DETAIL_MEAN,
              height=round(top_y, 4),
              outfits=[name for name, _, _ in OUTFITS],
              hair=[name for name, _ in HAIR_STYLES],
              cap_hair=list(CAP_HAIR),
              eyes=eye_images,
              skin_female=female_skin,
              body_chunks=body_chunks,
              defaults={k: [round(float(x), 4) for x in v] for k, v in defaults.items()},
              shapes=shapes,
              face_fit=face_fit)
    print(f"wrote {parts_path} ({os.path.getsize(parts_path) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
