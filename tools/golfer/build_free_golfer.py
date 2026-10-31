#!/usr/bin/env python3
"""Builds game/assets/golfer/free_golfer.glb, the golfer shown when the
original game files aren't loaded, from MakeHuman's CC0 assets.

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
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltf  # noqa: E402
import mhuman  # noqa: E402
import pose  # noqa: E402
from pose import Key  # noqa: E402

FPS = 30

# The body: a man of about 35, average build, 1.83 m.
MACROS = dict(gender=1.0, age=0.6, muscle=0.6, weight=0.55, height=0.5, proportions=0.75)
SKIN = "skins/middleage_caucasian_male/middleage_caucasian_male.mhmat"
OUTFIT = "clothes/male_casualsuit06/male_casualsuit06.mhclo"
SHOES = "clothes/shoes05/shoes05.mhclo"
HAIR = "hair/short02/short02.mhclo"
EYES = "eyes/high-poly/high-poly.mhclo"
EYE_MATERIAL = "eyes/materials/brown.mhmat"
EYEBROWS = "eyebrows/eyebrow001/eyebrow001.mhclo"
EYELASHES = "eyelashes/eyelashes01/eyelashes01.mhclo"
SHIRT = (0.11, 0.2, 0.38)  # navy polo
TROUSERS = (0.72, 0.64, 0.5)  # stone chinos

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


def texture(g, path, size, mime="image/jpeg", recolour=None, keep_alpha=False):
    im = Image.open(path)
    im = im.convert("RGBA" if keep_alpha else "RGB")
    if recolour:
        im = recolour(im)
    im = im.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    if mime == "image/png":
        im.save(buf, "PNG", optimize=True)
    else:
        im.save(buf, "JPEG", quality=88)
    return g.image(buf.getvalue(), mime)


def dress_outfit(im):
    """Turns the T-shirt and jeans into a plain polo and chinos."""
    a = np.asarray(im, dtype=np.float64) / 255
    h = a.shape[0]
    lum = a @ np.array([0.3, 0.59, 0.11])
    sat = a.max(axis=2) - a.min(axis=2)
    top = np.zeros(lum.shape, bool)
    top[: int(h * 0.44)] = True
    # The shirt's printed logo: anything coloured or darker than the cloth.
    smooth = np.asarray(Image.fromarray((lum * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(31)),
                        dtype=np.float64) / 255
    logo = top & ((sat > 0.08) | (lum < smooth - 0.06))
    logo = np.asarray(Image.fromarray((logo * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9))) > 0
    lum = np.where(logo, smooth, lum)
    out = np.empty_like(a)
    shirt_mean = np.median(lum[top])
    shirt = np.clip(lum / shirt_mean, 0, 1.3)[..., None] * np.array(SHIRT)
    pants_mean = np.median(lum[~top])
    flat = pants_mean + 0.35 * (lum - pants_mean)
    pants = np.clip(flat / pants_mean, 0, 1.3)[..., None] * np.array(TROUSERS)
    out = np.where(top[..., None], shirt, pants)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


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


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--mpfb-data", required=True)
    ap.add_argument("--assets", required=True)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "..", "game", "assets",
                                                   "golfer", "free_golfer.glb"))
    args = ap.parse_args()
    A = lambda rel: os.path.join(args.assets, rel)

    human = mhuman.Human(args.mpfb_data, args.assets)
    human.morph(**MACROS)
    human.build_rig()
    names = human.bones
    poser = pose.Poser(human)

    g = gltf.Gltf()
    skin_dir = os.path.dirname(A(SKIN))
    skin_tex = texture(g, os.path.join(skin_dir, mhuman.read_mhmat(A(SKIN))["diffuseTexture"]), 1024)
    m_skin = g.material("Skin", skin_tex, roughness=0.62)

    outfit_dir = os.path.dirname(A(OUTFIT))
    outfit_mat = mhuman.read_mhmat(os.path.join(outfit_dir, "male_casualsuit06.mhmat"))
    m_outfit = g.material("Clothes", texture(g, os.path.join(outfit_dir, outfit_mat["diffuseTexture"]), 1024,
                                              recolour=dress_outfit),
                          texture(g, os.path.join(outfit_dir, outfit_mat["normalmapTexture"]), 1024), roughness=0.9)
    shoes_dir = os.path.dirname(A(SHOES))
    m_shoes = g.material("Shoes", texture(g, os.path.join(shoes_dir, mhuman.read_mhmat(
        os.path.join(shoes_dir, "shoes05.mhmat"))["diffuseTexture"]), 512), roughness=0.55)
    hair_dir = os.path.dirname(A(HAIR))
    m_hair = g.material("Hair", texture(g, os.path.join(hair_dir, "short02_diffuse.png"), 1024, "image/png",
                                         keep_alpha=True), roughness=0.7, alpha_mask=True, double_sided=True)
    eye_mat = mhuman.read_mhmat(A(EYE_MATERIAL))
    m_eyes = g.material("Eyes", texture(g, os.path.join(os.path.dirname(A(EYE_MATERIAL)), eye_mat["diffuseTexture"]),
                                         512, "image/png", keep_alpha=True), roughness=0.15, alpha_mask=True)
    brow_dir = os.path.dirname(A(EYEBROWS))
    m_brows = g.material("Eyebrows", texture(g, os.path.join(brow_dir, "eyebrow001.png"), 256, "image/png",
                                              keep_alpha=True), roughness=0.8, alpha_mask=True, double_sided=True, cutoff=0.12)
    lash_dir = os.path.dirname(A(EYELASHES))
    m_lashes = g.material("Eyelashes", texture(g, os.path.join(lash_dir, "eyelashes01.png"), 256, "image/png",
                                                keep_alpha=True), roughness=0.8, alpha_mask=True, double_sided=True,
                          cutoff=0.25)
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

    def emit(part):
        g.skinned_mesh(part.name, part.positions.astype(np.float32), part.normals.astype(np.float32),
                       part.uvs.astype(np.float32), part.joints, part.joint_weights, part.indices, part.material, skin)

    outfit, outfit_proxy = human.proxy_part("Clothes", A(OUTFIT), m_outfit)
    shoes, shoes_proxy = human.proxy_part("Shoes", A(SHOES), m_shoes)
    emit(human.body_part(m_skin, outfit_proxy.deleted | shoes_proxy.deleted))
    emit(outfit)
    emit(shoes)
    for name, path, mat in (("Hair", HAIR, m_hair), ("Eyes", EYES, m_eyes), ("Eyebrows", EYEBROWS, m_brows),
                            ("Eyelashes", EYELASHES, m_lashes)):
        emit(human.proxy_part(name, A(path), mat)[0])
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


if __name__ == "__main__":
    main()
