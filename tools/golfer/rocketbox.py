"""Adds Microsoft Rocketbox people (MIT licence) to the free golfer's look pack.

    python3 tools/golfer/rocketbox.py [--pack game/assets/golfer/free_golfer_parts.olg]
        [--cache ~/.cache/rocketbox] [--godot godot] Male_Adult_14 ...

Rocketbox (github.com/microsoft/Microsoft-Rocketbox) is a library of rigged
people with photographed faces and clothes painted with real folds, far
more lifelike than the MakeHuman base the player creator sculpts. Each one
is moved onto the free golfer's own skeleton, so every mocap clip, the hand
and arm IK, the cloth and the head look work on them unchanged:

1. tools/golfer/rocketbox_dump.gd (Godot reads the FBX) writes its meshes in
   the rest pose and its 3ds Max Biped skeleton.
2. The person is turned to face the rig's way (-z, left at -x) and every
   Biped bone mapped to one of ours (face, eyes and the root go to the head
   and the pelvis).
3. Each bone is turned so it points the way ours does at rest (the rig's
   A-pose, the hands' frame from the knuckles), keeping the person's own
   bone lengths, and the mesh is skinned into that pose.
4. The person's joints become joint offsets from the rig's rest, as a body
   shape's are, and the meshes and textures go into the pack as parts
   "RB_<name>_<surface>" and info["people"][name].

The pack is grown in place; run it on a pack without people (rebuild with
upgrade_pack.py first if needed).
"""

import argparse
import io
import json
import os
import struct
import subprocess
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from golf_shoes import load, save  # noqa: E402
from look_pack import tangents  # noqa: E402
import person_cap  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = "https://cdn.jsdelivr.net/gh/microsoft/Microsoft-Rocketbox@master/Assets/Avatars/Adults/"
TEXTURE_SIZE = {"color": 2048, "normal": 1024}
HEAD_SIZE = 1536  # the face: plenty for a close-up, and 40% smaller
JPEG_QUALITY = 88

SIDES = {"L": "l", "R": "r"}
FINGERS = {"0": "thumb", "1": "index", "2": "middle", "3": "ring", "4": "pinky"}


def our_bone(name):
    """The rig bone a Biped bone's skinning goes to."""
    n = name.replace("Bip01", "").strip()
    simple = {"Pelvis": "pelvis", "Spine": "spine_01", "Spine1": "spine_02", "Spine2": "spine_03",
              "Neck": "neck_01", "Head": "head", "": "pelvis", "Footsteps": "pelvis"}
    if n in simple:
        return simple[n]
    parts = n.split(" ")
    if len(parts) == 2 and parts[0] in SIDES:
        side = SIDES[parts[0]]
        limb = {"Clavicle": "clavicle", "UpperArm": "upperarm", "Forearm": "lowerarm", "Hand": "hand",
                "Thigh": "thigh", "Calf": "calf", "Foot": "foot", "Toe0": "ball"}
        if parts[1] in limb:
            return "%s_%s" % (limb[parts[1]], side)
        if parts[1].startswith("Finger"):
            digits = parts[1][len("Finger"):]
            finger = FINGERS[digits[0]]
            joint = 1 + (int(digits[1]) if len(digits) > 1 else 0)
            return "%s_%02d_%s" % (finger, joint, side)
    return "head"  # the face's own bones, eyes and jaw


# Which way each rig bone points at rest: to this child.
POINTS_TO = {
    "pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01",
    "neck_01": "head",
}
for s in "lr":
    POINTS_TO.update({"clavicle_" + s: "upperarm_" + s, "upperarm_" + s: "lowerarm_" + s,
                      "lowerarm_" + s: "hand_" + s, "hand_" + s: "middle_01_" + s,
                      "thigh_" + s: "calf_" + s, "calf_" + s: "foot_" + s, "foot_" + s: "ball_" + s})
    for f in FINGERS.values():
        POINTS_TO["%s_01_%s" % (f, s)] = "%s_02_%s" % (f, s)
        POINTS_TO["%s_02_%s" % (f, s)] = "%s_03_%s" % (f, s)


def rig_rest(glb):
    """The rig's bone names, parents and rest positions (every rest
    rotation is the identity, so they are sums of translations)."""
    raw = open(glb, "rb").read()
    n = struct.unpack("<I", raw[12:16])[0]
    g = json.loads(raw[20:20 + n])
    nodes = g["nodes"]
    parent = {}
    for i, nd in enumerate(nodes):
        for c in nd.get("children", []):
            parent[c] = i
    out = {}
    for j in g["skins"][0]["joints"]:
        p = np.zeros(3)
        i = j
        while i is not None:
            p += np.array(nodes[i].get("translation", [0, 0, 0]))
            i = parent.get(i)
        out[nodes[j]["name"]] = p
    return out


def rotation_between(a, b):
    """The smallest rotation (3x3) taking direction a to direction b."""
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c < -0.9999:
        axis = np.cross(a, [1, 0, 0])
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(a, [0, 1, 0])
        axis /= np.linalg.norm(axis)
        return 2 * np.outer(axis, axis) - np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k / (1 + c)


def aligned(a, a_side, b, b_side):
    """The rotation (3x3) taking direction a to b and the plane of a and
    a_side to the plane of b and b_side."""
    def frame(d, side):
        x = d / np.linalg.norm(d)
        z = np.cross(x, side)
        z /= np.linalg.norm(z)
        return np.stack([x, np.cross(z, x), z], 1)
    return frame(b, b_side) @ frame(a, a_side).T


def about(axis, angle):
    axis = axis / np.linalg.norm(axis)
    k = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + np.sin(angle) * k + (1 - np.cos(angle)) * k @ k


def fetch(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 1000:
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for attempt in range(4):
        try:
            data = urllib.request.urlopen(url, timeout=120).read()
            if len(data) > 1000:
                open(path, "wb").write(data)
                return path
        except Exception as e:  # jsDelivr refuses now and then
            print("  retry", url, e)
    return None


def dump(fbx, godot, out):
    subprocess.run([godot, "--headless", "--path", os.path.join(ROOT, "game"), "-s",
                    os.path.join(ROOT, "tools", "golfer", "rocketbox_dump.gd"), "--", fbx, out],
                   check=True, capture_output=True)
    d = json.load(open(out + ".json"))
    blob = open(out + ".bin", "rb").read()

    def arr(e, k, dt, cols):
        o, n = e[k]
        return np.frombuffer(blob[o:o + n], dt).reshape(-1, cols) if cols else np.frombuffer(blob[o:o + n], dt)
    for s in d["surfaces"]:
        s["positions"] = arr(s, "positions", np.float32, 3).astype(np.float64)
        s["normals"] = arr(s, "normals", np.float32, 3).astype(np.float64)
        s["uvs"] = arr(s, "uvs", np.float32, 2)
        s["bones"] = arr(s, "bones", np.int32, s["per"])
        s["weights"] = arr(s, "weights", np.float32, s["per"])
        s["indices"] = arr(s, "indices", np.int32, 3)
    return d


def person(d, rig):
    """Moves dump `d` onto the rig: returns (surfaces, joint offsets,
    height). Surfaces carry rig bone indices and weights (4 each)."""
    names = list(rig.keys())
    turn = np.diag([-1.0, 1.0, -1.0])  # face -z, left at -x, as the rig
    rb = {}  # rig bone -> the Biped joint it starts at (the first mapped)
    for b in d["bones"]:
        mine = our_bone(b["name"])
        n = b["name"].replace("Bip01", "").strip()
        if mine == "head" and n != "Head":
            continue
        if mine == "pelvis" and n != "Pelvis":
            continue
        rb.setdefault(mine, turn @ np.array(b["origin"]))
    # Absolute turn per rig bone: its Biped direction onto the rig's.
    rot = {}
    scale = {}  # hands and fingers: their size laid onto the rig's; arms: their length
    for bone, child in POINTS_TO.items():
        if bone in rb and child in rb:
            rot[bone] = rotation_between(rb[child] - rb[bone], rig[child] - rig[bone])
    for s in "lr":
        # The arm bones keep the elbow's hinge: each is turned by its
        # direction and the plane the upper arm and forearm make, so the
        # elbow folds the way the rig's (and the mocap's) does rather than
        # sideways or backwards.
        u, lo, h = "upperarm_" + s, "lowerarm_" + s, "hand_" + s
        if all(k in rb for k in (u, lo, h)):
            have = np.cross(rb[lo] - rb[u], rb[h] - rb[lo])
            want = np.cross(rig[lo] - rig[u], rig[h] - rig[lo])
            rot[u] = aligned(rb[lo] - rb[u], have, rig[lo] - rig[u], want)
            rot[lo] = aligned(rb[h] - rb[lo], have, rig[h] - rig[lo], want)
        # The hand is laid over the rig's: turned and scaled so its finger
        # joints fall where the rig's are (Kabsch), so the grip's finger
        # turns, made for the rig's hand, wrap these fingers round the
        # grip and the palm sits on it.
        joints = [b for b in rb if b.endswith("_" + s) and b.split("_")[0] in FINGERS.values() and b in rig]
        if h in rb and len(joints) >= 5:
            a = np.array([rb[b] - rb[h] for b in joints])
            b = np.array([rig[j] - rig[h] for j in joints])
            u_, sv, vt = np.linalg.svd(b.T @ a)
            fix = np.diag([1.0, 1.0, np.sign(np.linalg.det(u_ @ vt))])
            rot[h] = u_ @ fix @ vt
            scale[h] = float(np.trace(np.diag(sv) @ fix) / (a * a).sum())
            print("  hand_%s scale %.3f, fit %.1f mm" % (s, scale[h], 1000 * np.sqrt(
                ((scale[h] * a @ rot[h].T - b) ** 2).sum(1).mean())))
        # Fingers and thumb move with the hand: their own curl stays, and
        # the grip's finger turns bend them about the person's knuckles.
        for b in list(rot):
            if b.endswith("_" + s) and b.split("_")[0] in FINGERS.values():
                rot[b] = rot[h]
                scale[b] = scale.get(h, 1.0)
        # Feet stay flat: only turned about the vertical to point the
        # rig's way, never pitched (that tipped the toes up).
        f = "foot_" + s
        if f in rot and "ball_" + s in rb:
            a = rb["ball_" + s] - rb[f]
            b = rig["ball_" + s] - rig[f]
            rot[f] = rotation_between(np.array([a[0], 0.0, a[2]]), np.array([b[0], 0.0, b[2]]))
            rot["ball_" + s] = rot[f]
    # Bones that point nowhere (fingertips, head, ball) turn as their parent.
    parent_of = {}
    for bone, child in POINTS_TO.items():
        parent_of[child] = bone
    for bone in rb:
        if bone not in rot:
            p = parent_of.get(bone)
            rot[bone] = rot.get(p, np.eye(3))
            if p in scale:
                scale[bone] = scale[p]
    # Arms the rig's length for the person's size: the mocap's hands meet
    # the grip with the rig's arms, so Rocketbox's longer arms (about 14%)
    # had to bend at the elbow to get there. Each arm bone is stretched
    # along its length only, so the arms keep their thickness.
    size = (rb["neck_01"][1] - rb["foot_l"][1]) / (rig["neck_01"][1] - rig["foot_l"][1])
    for s in "lr":
        for b, c in (("upperarm_" + s, "lowerarm_" + s), ("lowerarm_" + s, "hand_" + s)):
            if b in rb and c in rb:
                a = rb[c] - rb[b]
                k = size * np.linalg.norm(rig[c] - rig[b]) / np.linalg.norm(a)
                a = a / np.linalg.norm(a)
                scale[b] = np.eye(3) + (k - 1.0) * np.outer(a, a)
                if os.environ.get("RB_DEBUG"):
                    print("  %s length x%.3f" % (b, k))

    def lin(b):
        k = scale.get(b, 1.0)
        return rot[b] @ k if isinstance(k, np.ndarray) else rot[b] * k

    # New joints: the person's bone lengths, laid the rig's way.
    order = ["pelvis"] + [b for b in names if b in rb and b != "pelvis"]
    rig_parent = {}
    for b in rb:
        p = parent_of.get(b)
        if b.startswith(("clavicle_",)):
            p = "spine_03"
        if b.startswith("thigh_"):
            p = "pelvis"
        if b.startswith(("thumb_01", "index_01", "middle_01", "ring_01", "pinky_01")):
            p = "hand_" + b[-1]
        rig_parent[b] = p
    new = {"pelvis": rb["pelvis"]}
    pending = [b for b in order if b != "pelvis"]
    while pending:
        rest = []
        for b in pending:
            p = rig_parent.get(b)
            if p is None or p not in new:
                if p is None:
                    new[b] = rb[b]
                else:
                    rest.append(b)
                continue
            new[b] = new[p] + lin(p) @ (rb[b] - rb[p])
        if len(rest) == len(pending):
            for b in rest:
                new[b] = rb[b]
            break
        pending = rest
    if os.environ.get("RB_DEBUG"):
        for b in ("spine_03", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "thigh_l", "calf_l", "foot_l"):
            print("  %s turn %.1f deg" % (b, np.degrees(np.arccos(np.clip((np.trace(rot[b]) - 1) / 2, -1, 1)))))
    # The shoulders forward to where the rig's are: the Biped's shoulder
    # joints sit behind the neck (the rig's just in front), so the mocap's
    # arms hung from the shoulder blades and bent forward at the elbow to
    # reach the grip. The arms, mesh and joints, move forward together.
    forward = {}
    for s in "lr":
        u = "upperarm_" + s
        want = rig[u][2] - rig["neck_01"][2]
        have = new[u][2] - new["neck_01"][2]
        forward[s] = np.array([0.0, 0.0, (want - have) * float(os.environ.get("RB_SHOULDER", "1"))])
        if os.environ.get("RB_DEBUG"):
            print("  shoulder_%s forward %.1f cm" % (s, -100 * forward[s][2]))
        for b in new:
            if b.endswith("_" + s) and not b.startswith(("clavicle_", "thigh_", "calf_", "foot_", "ball_")):
                new[b] = new[b] + forward[s]
    surfaces = []
    index = {n: i for i, n in enumerate(names)}
    for s in d["surfaces"]:
        pos = s["positions"] @ turn.T
        nrm = s["normals"] @ turn.T
        mapped = np.array([index[our_bone(b["name"])] for b in d["bones"]])
        target = [names[i] for i in mapped]
        out_p = np.zeros_like(pos)
        out_n = np.zeros_like(nrm)
        for k in range(s["per"]):
            w = s["weights"][:, k:k + 1].astype(np.float64)
            bones = s["bones"][:, k]
            for bi in np.unique(bones):
                sel = bones == bi
                if not np.any(w[sel] > 0):
                    continue
                t = target[bi]
                r = rot.get(t, np.eye(3))
                j0 = rb.get(t, np.zeros(3))
                j1 = new.get(t, j0)
                out_p[sel] += w[sel] * ((pos[sel] - j0) @ lin(t).T + j1)
                out_n[sel] += w[sel] * (nrm[sel] @ r.T)
        wsum = s["weights"].sum(1, keepdims=True)
        out_p /= np.maximum(wsum, 1e-6)
        out_n /= np.maximum(np.linalg.norm(out_n, axis=1, keepdims=True), 1e-9)
        # Rig bones and weights, merged where two Biped bones map to one.
        rows = len(pos)
        merged = np.zeros((rows, len(names)), np.float32)
        for k in range(s["per"]):
            np.add.at(merged, (np.arange(rows), mapped[s["bones"][:, k]]), s["weights"][:, k])
        top = np.argsort(-merged, axis=1)[:, :4]
        tw = np.take_along_axis(merged, top, 1)
        tw /= np.maximum(tw.sum(1, keepdims=True), 1e-6)
        surfaces.append({"material": s["material"], "positions": out_p.astype(np.float32),
                         "normals": out_n.astype(np.float32), "uvs": s["uvs"], "joints": top.astype(np.int32),
                         "weights": tw.astype(np.float32), "indices": s["indices"]})
    # The spine bends where the rig's does: the Biped's chest joint sits a
    # hand higher than the rig's spine_03, so the mocap's back bend rounded
    # the shoulders forward and down. The mesh stays; only the pivots move,
    # to the rig's heights stretched to the person's back.
    stretch = (new["neck_01"][1] - new["pelvis"][1]) / (rig["neck_01"][1] - rig["pelvis"][1])
    for b in ("spine_01", "spine_02", "spine_03"):
        new[b] = new["pelvis"] + (rig[b] - rig["pelvis"]) * stretch
    offsets = {b: (new[b] - rig[b]).tolist() for b in new if b in rig}
    height = float(max(s["positions"][:, 1].max() for s in surfaces))
    return surfaces, offsets, height


MASK_SIZE = 512
UNLIKE = 0.25  # colour distance past which a texel is no garment's
SHIRT = ("spine_", "clavicle_", "upperarm_", "lowerarm_")
TROUSERS = ("pelvis", "thigh_", "calf_")
SHOES = ("foot_", "ball_")


def linear(c):
    c = np.asarray(c, np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def regions(surface, colour, skin, names):
    """The body texture's clothing as a mask image (R shirt, G trousers,
    B shoes) and each one's mean linear luminance, for recolouring to the
    player's colours. A texel's region is the body part its triangle moves
    with; skin showing there (short sleeves, the neck) and dark details
    (belt, buttons) are left out by colour."""
    size = MASK_SIZE
    tex = linear(np.asarray(colour.convert("RGB").resize((size, size), Image.BILINEAR)) / 255.0)
    label = np.zeros((size, size), np.int8)  # 0 none, 1 shirt, 2 trousers, 3 shoes
    vert = np.zeros(len(surface["positions"]), np.int8)
    for i in range(len(vert)):
        bone = names[surface["joints"][i, 0]]
        vert[i] = 1 if bone.startswith(SHIRT) else 2 if bone.startswith(TROUSERS) else 3 if bone.startswith(SHOES) else 0
    uv = surface["uvs"] * size
    for tri in surface["indices"]:
        lab = np.bincount(vert[tri], minlength=4).argmax()
        if lab == 0:
            continue
        q = uv[tri]
        x0, y0 = np.maximum(np.floor(q.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(q.max(0)).astype(int) + 1, size)
        if x1 <= x0 or y1 <= y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1), np.arange(y0, y1))
        pts = np.stack([xs + 0.5, ys + 0.5], -1).reshape(-1, 2)
        a, b, c = q
        v0, v1 = b - a, c - a
        d = v0[0] * v1[1] - v0[1] * v1[0]
        if abs(d) < 1e-9:
            continue
        w1 = ((pts[:, 0] - a[0]) * v1[1] - (pts[:, 1] - a[1]) * v1[0]) / d
        w2 = (v0[0] * (pts[:, 1] - a[1]) - v0[1] * (pts[:, 0] - a[0])) / d
        inside = (w1 >= -0.05) & (w2 >= -0.05) & (w1 + w2 <= 1.1)
        label[pts[inside, 1].astype(int), pts[inside, 0].astype(int)] = lab
    lum = tex @ np.array([0.2126, 0.7152, 0.0722])
    # Skin: near the face's own colour (in chromaticity and brightness).
    chroma = tex / np.maximum(tex.sum(-1, keepdims=True), 1e-6)
    sk = skin / max(skin.sum(), 1e-6)
    is_skin = (np.linalg.norm(chroma - sk, axis=-1) < 0.05) & (np.abs(lum - skin @ [0.2126, 0.7152, 0.0722]) < 0.2)
    is_skin &= label != 3  # no skin on the feet: brown leather is still shoe
    # Where a tucked-in shirt or a trouser hem moves with the next body
    # part, the cloth's own colour says which garment it is: each texel goes
    # to the garment whose typical colour it is closest to.
    cloth = (label > 0) & ~is_skin
    feat = np.concatenate([chroma * 3.0, np.sqrt(np.maximum(lum, 0))[..., None]], -1)
    refs = []
    for k in (1, 2, 3):
        sel = (label == k) & ~is_skin
        refs.append(np.median(feat[sel], axis=0) if sel.sum() > 50 else None)
    dist = np.stack([np.linalg.norm(feat - r, axis=-1) if r is not None else np.full(lum.shape, 9.0) for r in refs], -1)
    dist[..., 2] = np.where(label == 3, dist[..., 2], 9.0)  # shoes only on the feet
    dist[..., 0] = np.where(label == 3, 9.0, dist[..., 0])  # and no shirt there
    # Far from every garment's colour (a T-shirt under a jacket, a print):
    # left as it is.
    best = dist.argmin(-1)
    label = np.where(cloth & ((dist.min(-1) < UNLIKE) | (best == 2)), best + 1, 0).astype(np.int8)
    mask = np.zeros((size, size, 3), np.float64)
    means = []
    for k in (1, 2, 3):
        sel = (label == k) & ~is_skin
        m = float(np.median(lum[sel])) if sel.any() else 0.2
        # Belts and buttons keep their colour; a shoe's creases and seams
        # are dyed with it (left, they read as brown smudges on white).
        sel &= lum > m * (0.12 if k == 3 else 0.35)
        mask[..., k - 1] = sel
        means.append(m)
    img = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue(), means


def encode(img, size, quality=JPEG_QUALITY):
    img = img.convert("RGB")
    if img.size[0] > size:
        img = img.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=quality, optimize=True)
    return buf.getvalue()


def add(info, blob, name, surfaces, textures, offsets, height, sex, mask=None):
    def put(array, dtype):
        a = np.ascontiguousarray(array, dtype=dtype)
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(a.tobytes())
        return [off, a.nbytes]

    def image(data):
        kind = "png" if data[:4] == b"\x89PNG" else "jpg"
        info["images"].append({"kind": kind, "data": put(np.frombuffer(data, np.uint8), np.uint8)})
        return len(info["images"]) - 1
    parts = []
    for s in surfaces:
        kind = s["material"].split("_")[-1]  # body, head or opacity
        tex = textures.get(kind, {})
        mat = "RB_%s_%s" % (name, kind)
        colour = image(tex["color"]) if "color" in tex else -1
        normal = image(tex["normal"]) if "normal" in tex else -1
        hair = kind == "opacity"
        info["materials"][mat] = {"texture": colour, "normal": normal, "roughness": 0.75 if hair else 0.85,
                                  "cutoff": 0.35 if hair else 0.0, "double_sided": hair,
                                  "tint": "person_hair" if hair else "person", "colour": [1.0, 1.0, 1.0]}
        if kind == "body" and mask is not None:
            info["materials"][mat]["regions"] = image(mask[0])
            info["materials"][mat]["region_means"] = mask[1]
        pos, nrm, uvs, idx = s["positions"], s["normals"], s["uvs"], s["indices"]
        entry = {"material": mat, "count": int(len(pos)), "positions": put(pos, np.float32),
                 "normals": put(nrm.astype(np.float16), np.float16), "uvs": put(uvs, np.float32),
                 "bones": put(s["joints"], np.int32), "weights": put(s["weights"], np.float32),
                 "indices": put(idx, np.int32), "shapes": {}}
        if normal >= 0:
            entry["tangents"] = put(tangents(pos.astype(np.float64), nrm.astype(np.float64), uvs.astype(np.float64),
                                             idx).astype(np.float16), np.float16)
        part = "RB_%s_%s" % (name, kind)
        info["parts"][part] = entry
        parts.append(part)
    # Their own cap, built on their head (person_cap.py).
    if "RB_%s_head" % name in info["parts"]:
        person_cap.add(info, blob, name)
    info.setdefault("people", {})[name] = {"parts": parts, "joints": offsets, "height": height, "sex": sex}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("people", nargs="+")
    ap.add_argument("--pack", default=os.path.join(ROOT, "game/assets/golfer/free_golfer_parts.olg"))
    ap.add_argument("--glb", default=os.path.join(ROOT, "game/assets/golfer/free_golfer.glb"))
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/rocketbox"))
    ap.add_argument("--godot", default="godot")
    args = ap.parse_args()
    info, blob = load(args.pack)
    rig = rig_rest(args.glb)
    for name in args.people:
        if name in info.get("people", {}):
            sys.exit("%s is already in the pack: rebuild it first" % name)
        base = os.path.join(args.cache, name)
        fbx = fetch(SOURCE + "%s/Export/%s.fbx" % (name, name), os.path.join(base, name + ".fbx"))
        d = dump(fbx, args.godot, os.path.join(base, "dump"))
        surfaces, offsets, height = person(d, rig)
        # Texture names come from the FBX ("m012_body_color.tga" ...).
        raw = open(fbx, "rb").read()
        code = None
        for s in d["surfaces"]:
            code = s["material"].split("_")[0]
        textures = {}
        raw_colour = {}
        for s in d["surfaces"]:
            kind = s["material"].split("_")[-1]
            for channel in ("color", "normal"):
                fname = "%s_%s_%s.tga" % (code, kind, channel)
                if fname.encode() not in raw and kind != "opacity":
                    continue
                p = fetch(SOURCE + "%s/Textures/%s" % (name, fname), os.path.join(base, fname))
                if p is None:
                    print("  no", fname)
                    continue
                img = Image.open(p)
                if kind == "opacity" and channel == "color":
                    # Hair: colour with the alpha kept, as PNG.
                    buf = io.BytesIO()
                    img.convert("RGBA").resize((1024, 1024), Image.LANCZOS).save(buf, "PNG", optimize=True)
                    textures.setdefault(kind, {})[channel] = buf.getvalue()
                    continue
                if kind == "opacity":
                    continue
                if channel == "color":
                    raw_colour[kind] = img
                size = HEAD_SIZE if kind == "head" and channel == "color" else TEXTURE_SIZE[channel]
                textures.setdefault(kind, {})[channel] = encode(img, size)
        sex = 1.0 if name.startswith("Female") else 0.0
        mask = None
        body = [s for s in surfaces if s["material"].endswith("_body")]
        if body and "body" in raw_colour and "head" in raw_colour:
            head = linear(np.asarray(raw_colour["head"].convert("RGB").resize((512, 512))) / 255.0)
            skin = np.median(head[200:300, 200:310].reshape(-1, 3), axis=0)  # the cheeks and nose
            mask = regions(body[0], raw_colour["body"], skin, list(rig.keys()))
        add(info, blob, name, surfaces, textures, offsets, height, sex, mask)
        print("%s: %d surfaces, %.2f m, %d joints moved" % (name, len(surfaces), height, len(offsets)))
    save(args.pack, info, blob)


if __name__ == "__main__":
    main()
