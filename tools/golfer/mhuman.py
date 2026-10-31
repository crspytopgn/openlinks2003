"""Builds a dressed, rigged human from MakeHuman's CC0 data files.

Reads the hm08 base mesh, macro targets, proxy assets (.mhclo clothes, hair,
eyes, eyebrows, eyelashes), skins and the "game_engine" rig with its weights.
Only the data files are used; nothing from MakeHuman or MPFB is run. The
result is in metres in the GolferRig frame: +y up, facing -z, the golfer's
left at -x.
"""

import gzip
import json
import os

import numpy as np

DM_TO_M = 0.1


def read_obj(path):
    """Positions, uvs and faces (lists of (v, vt) pairs) with their groups."""
    verts, uvs, faces, groups = [], [], [], []
    group = ""
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            tag = parts[0]
            if tag == "v":
                verts.append([float(x) for x in parts[1:4]])
            elif tag == "vt":
                uvs.append([float(x) for x in parts[1:3]])
            elif tag == "g":
                group = parts[1] if len(parts) > 1 else ""
            elif tag == "f":
                face = []
                for p in parts[1:]:
                    ids = p.split("/")
                    face.append((int(ids[0]) - 1, int(ids[1]) - 1 if len(ids) > 1 and ids[1] else -1))
                faces.append(face)
                groups.append(group)
    return np.array(verts, dtype=np.float64), np.array(uvs, dtype=np.float64), faces, groups


def read_target(path):
    with gzip.open(path, "rt") as f:
        rows = [line.split() for line in f if line.strip() and not line.startswith("#")]
    idx = np.array([int(r[0]) for r in rows], dtype=np.int64)
    delta = np.array([[float(x) for x in r[1:4]] for r in rows], dtype=np.float64).reshape(-1, 3)
    return idx, delta


def macro_targets(gender, age, muscle, weight, height, proportions, race="caucasian"):
    """Target names and weights for MakeHuman's macro sliders (each 0..1)."""
    def split(value, parts):
        # parts: [(low value, high value, low name, high name)]
        for lo, hi, a, b in parts:
            if lo <= value <= hi:
                t = (value - lo) / (hi - lo)
                return {a: 1 - t, b: t}
        raise ValueError(value)

    g = split(gender, [(0, 1, "female", "male")])
    a = split(age, [(0, 0.1875, "baby", "child"), (0.1875, 0.5, "child", "young"), (0.5, 1, "young", "old")])
    m = split(muscle, [(0, 0.5, "minmuscle", "averagemuscle"), (0.5, 1, "averagemuscle", "maxmuscle")])
    w = split(weight, [(0, 0.5, "minweight", "averageweight"), (0.5, 1, "averageweight", "maxweight")])
    h = split(height, [(0, 0.5, "minheight", None), (0.5, 1, None, "maxheight")])
    p = split(proportions, [(0, 0.5, "uncommonproportions", None), (0.5, 1, None, "idealproportions")])
    out = {}
    for gn, gw in g.items():
        for an, aw in a.items():
            out[f"{race}-{gn}-{an}"] = out.get(f"{race}-{gn}-{an}", 0) + gw * aw
            for mn, mw in m.items():
                for wn, ww in w.items():
                    base = gw * aw * mw * ww
                    out[f"universal-{gn}-{an}-{mn}-{wn}"] = base
                    for hn, hw in h.items():
                        if hn:
                            out[f"height/{gn}-{an}-{mn}-{wn}-{hn}"] = base * hw
                    for pn, pw in p.items():
                        if pn:
                            out[f"proportions/{gn}-{an}-{mn}-{wn}-{pn}"] = base * pw
    return {k: v for k, v in out.items() if v > 1e-6}


class Proxy:
    """A fitted .mhclo asset: its own mesh placed on the base mesh."""

    def __init__(self, path):
        self.folder = os.path.dirname(path)
        self.refs, self.weights, self.offsets = [], [], []
        self.scales = {}
        self.deleted = set()
        self.material = None
        self.obj = None
        mode = None
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if not line:
                    continue
                parts = line.split()
                key = parts[0]
                if key in ("x_scale", "y_scale", "z_scale"):
                    self.scales[key[0]] = (int(parts[1]), int(parts[2]), float(parts[3]))
                elif key == "obj_file":
                    self.obj = parts[1]
                elif key == "material":
                    self.material = parts[1]
                elif key == "verts":
                    mode = "verts"
                elif key == "delete_verts":
                    mode = "delete"
                elif mode == "verts" and _is_number(key):
                    if len(parts) == 1:
                        self.refs.append([int(parts[0])] * 3)
                        self.weights.append([1.0, 0.0, 0.0])
                        self.offsets.append([0.0, 0.0, 0.0])
                    else:
                        self.refs.append([int(x) for x in parts[0:3]])
                        self.weights.append([float(x) for x in parts[3:6]])
                        self.offsets.append([float(x) for x in parts[6:9]])
                elif mode == "delete" and _is_number(key):
                    i = 0
                    while i < len(parts):
                        if i + 2 < len(parts) and parts[i + 1] == "-":
                            self.deleted.update(range(int(parts[i]), int(parts[i + 2]) + 1))
                            i += 3
                        else:
                            self.deleted.add(int(parts[i]))
                            i += 1
        self.refs = np.array(self.refs)
        self.weights = np.array(self.weights)
        self.offsets = np.array(self.offsets)

    def fit(self, base):
        """Proxy vertex positions on the (morphed, MakeHuman-unit) base mesh."""
        scale = np.ones(3)
        for axis, i in (("x", 0), ("y", 1), ("z", 2)):
            if axis in self.scales:
                a, b, den = self.scales[axis]
                scale[i] = abs(base[a, i] - base[b, i]) / den
        pos = (base[self.refs] * self.weights[:, :, None]).sum(axis=1)
        return pos + self.offsets * scale

    def bone_weights(self, base_weights):
        return (base_weights[self.refs] * self.weights[:, :, None]).sum(axis=1)


def _is_number(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


def read_mhmat(path):
    mat = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("//"):
                continue
            parts = line.split(None, 1)
            if len(parts) == 2:
                mat[parts[0]] = parts[1].strip()
    return mat


class Part:
    """A mesh ready for glTF: unique (position, uv) vertices, triangles."""

    def __init__(self, name, positions, uvs, faces, weights, material, keep=None):
        self.name = name
        self.material = material
        tris = []
        for face in faces:
            if keep is not None and not keep(face):
                continue
            for k in range(1, len(face) - 1):
                tris.append((face[0], face[k], face[k + 1]))
        pairs = {}
        index = []
        for tri in tris:
            for v, t in tri:
                key = (v, t)
                if key not in pairs:
                    pairs[key] = len(pairs)
                index.append(pairs[key])
        keys = np.array(list(pairs.keys()))
        self.vertex_ids = keys[:, 0]
        self.positions = positions[keys[:, 0]]
        uv = uvs[np.maximum(keys[:, 1], 0)] if len(uvs) else np.zeros((len(keys), 2))
        self.uvs = np.column_stack([uv[:, 0], 1.0 - uv[:, 1]])
        self.indices = np.array(index, dtype=np.uint32).reshape(-1, 3)
        # Smooth normals per original position, so uv seams don't show.
        normals = np.zeros_like(positions)
        tri_v = np.array([[v for v, _ in tri] for tri in tris])
        p0, p1, p2 = positions[tri_v[:, 0]], positions[tri_v[:, 1]], positions[tri_v[:, 2]]
        fn = np.cross(p1 - p0, p2 - p0)
        for c in range(3):
            np.add.at(normals, tri_v[:, c], fn)
        n = normals[keys[:, 0]]
        self.normals = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        self.joints, self.joint_weights = _top4(weights[keys[:, 0]])


def _top4(w):
    order = np.argsort(-w, axis=1)[:, :4]
    top = np.take_along_axis(w, order, axis=1)
    top = np.maximum(top, 0)
    total = top.sum(axis=1, keepdims=True)
    top = np.where(total > 0, top / np.maximum(total, 1e-12), np.array([1.0, 0, 0, 0]))
    order = np.where(total > 0, order, 0)
    return order.astype(np.uint8), top.astype(np.float32)


class Human:
    def __init__(self, mpfb_data, assets):
        self.data = mpfb_data
        self.assets = assets
        obj = os.path.join(mpfb_data, "3dobjs", "base.obj")
        self.base, self.base_uvs, self.base_faces, self.base_groups = read_obj(obj)
        self.coords = self.base.copy()

    def morph(self, **macros):
        root = os.path.join(self.data, "targets", "macrodetails")
        for name, w in macro_targets(**macros).items():
            idx, delta = read_target(os.path.join(root, name + ".target.gz"))
            self.coords[idx] += w * delta

    def cube_centre(self, group):
        ids = {v for face, g in zip(self.base_faces, self.base_groups) if g == group for v, _ in face}
        if not ids:
            raise KeyError(group)
        return self.coords[sorted(ids)].mean(axis=0)

    def to_rig(self, p):
        """MakeHuman decimetres (facing +z) to metres in the GolferRig frame."""
        p = np.asarray(p, dtype=np.float64) * DM_TO_M
        out = p.copy()
        out[..., 0] = -p[..., 0]
        out[..., 2] = -p[..., 2]
        return out - self.ground

    def build_rig(self, rig_name="game_engine"):
        rig = json.load(open(os.path.join(self.data, "rigs", "standard", f"rig.{rig_name}.json")))
        self.ground = np.zeros(3)
        self.ground = self.to_rig(self.cube_centre("joint-ground"))
        names = []

        def add(name):
            if name in names:
                return
            parent = rig[name]["parent"]
            if parent:
                add(parent)
            names.append(name)

        for name in sorted(rig):
            add(name)
        self.bones = names
        self.parents = [names.index(rig[n]["parent"]) if rig[n]["parent"] else -1 for n in names]

        def point(spec):
            if spec["strategy"] == "CUBE":
                return self.cube_centre(spec["cube_name"])
            if spec["strategy"] == "MEAN":
                return self.coords[spec["vertex_indices"]].mean(axis=0)
            if spec["strategy"] == "VERTEX":
                return self.coords[spec["vertex_index"]]
            raise ValueError(spec["strategy"])

        self.heads = np.array([self.to_rig(point(rig[n]["head"])) for n in names])
        self.tails = np.array([self.to_rig(point(rig[n]["tail"])) for n in names])
        weights = json.load(open(os.path.join(self.data, "rigs", "standard", f"weights.{rig_name}.json")))["weights"]
        self.base_weights = np.zeros((len(self.base), len(names) + 2))  # + club joints
        for b, rows in weights.items():
            j = names.index(b)
            for v, w in rows:
                self.base_weights[int(v), j] = w

    def body_part(self, skin_material, deleted):
        coords = self.to_rig(self.coords)
        keep = lambda face: all(v not in deleted for v, _ in face)
        faces = [f for f, g in zip(self.base_faces, self.base_groups) if g == "body"]
        return Part("Body", coords, self.base_uvs, faces, self.base_weights, skin_material, keep)

    def proxy_part(self, name, mhclo, material):
        proxy = Proxy(mhclo)
        verts, uvs, faces, _ = read_obj(os.path.join(proxy.folder, proxy.obj))
        fitted = proxy.fit(self.coords)
        assert len(fitted) == len(verts), (mhclo, len(fitted), len(verts))
        part = Part(name, self.to_rig(fitted), uvs, faces, proxy.bone_weights(self.base_weights), material)
        return part, proxy
