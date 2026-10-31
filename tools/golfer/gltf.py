"""A small glTF 2.0 binary (.glb) writer for skinned, animated meshes."""

import json
import struct

import numpy as np

FLOAT, UBYTE, USHORT, UINT = 5126, 5121, 5123, 5125
_TYPES = {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4", 16: "MAT4"}
_DTYPES = {FLOAT: np.float32, UBYTE: np.uint8, USHORT: np.uint16, UINT: np.uint32}


class Gltf:
    def __init__(self):
        self.doc = {"asset": {"version": "2.0", "generator": "OpenLinks2003 tools/golfer"},
                    "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "materials": [],
                    "textures": [], "images": [], "samplers": [{"magFilter": 9729, "minFilter": 9987}],
                    "accessors": [], "bufferViews": [], "buffers": []}
        self.blob = bytearray()

    def _view(self, data, target=None):
        while len(self.blob) % 4:
            self.blob.append(0)
        view = {"buffer": 0, "byteOffset": len(self.blob), "byteLength": len(data)}
        if target:
            view["target"] = target
        self.blob.extend(data)
        self.doc["bufferViews"].append(view)
        return len(self.doc["bufferViews"]) - 1

    def accessor(self, array, ctype=FLOAT, target=None, minmax=False):
        a = np.ascontiguousarray(array, dtype=_DTYPES[ctype])
        width = 1 if a.ndim == 1 else int(np.prod(a.shape[1:]))
        acc = {"bufferView": self._view(a.tobytes(), target), "componentType": ctype,
               "count": int(a.shape[0]), "type": _TYPES[width]}
        if minmax:
            flat = a.reshape(a.shape[0], -1)
            acc["min"] = [float(x) for x in flat.min(axis=0)]
            acc["max"] = [float(x) for x in flat.max(axis=0)]
        self.doc["accessors"].append(acc)
        return len(self.doc["accessors"]) - 1

    def sparse_accessor(self, array, tolerance=0.0):
        """A float VEC3 accessor of mostly zero rows (morph target offsets),
        stored sparse: only the rows above `tolerance`. None if none are."""
        a = np.ascontiguousarray(array, dtype=np.float32)
        rows = np.nonzero(np.abs(a).max(axis=1) > tolerance)[0].astype(np.uint32)
        if len(rows) == 0:
            return None
        values = a[rows]
        index_type = USHORT if a.shape[0] < 65536 else UINT
        acc = {"componentType": FLOAT, "count": int(a.shape[0]), "type": "VEC3",
               "min": [float(x) for x in np.minimum(values.min(axis=0), 0)],
               "max": [float(x) for x in np.maximum(values.max(axis=0), 0)],
               "sparse": {"count": int(len(rows)),
                          "indices": {"bufferView": self._view(rows.astype(_DTYPES[index_type]).tobytes()),
                                      "componentType": index_type},
                          "values": {"bufferView": self._view(values.tobytes())}}}
        self.doc["accessors"].append(acc)
        return len(self.doc["accessors"]) - 1

    def image(self, data, mime):
        self.doc["images"].append({"bufferView": self._view(data), "mimeType": mime})
        self.doc["textures"].append({"source": len(self.doc["images"]) - 1, "sampler": 0})
        return len(self.doc["textures"]) - 1

    def material(self, name, base_texture=None, normal_texture=None, colour=(1, 1, 1, 1), roughness=0.85,
                 metallic=0.0, alpha_mask=False, double_sided=False, cutoff=0.5):
        pbr = {"baseColorFactor": list(colour), "metallicFactor": metallic, "roughnessFactor": roughness}
        if base_texture is not None:
            pbr["baseColorTexture"] = {"index": base_texture}
        mat = {"name": name, "pbrMetallicRoughness": pbr}
        if normal_texture is not None:
            mat["normalTexture"] = {"index": normal_texture}
        if alpha_mask:
            mat["alphaMode"] = "MASK"
            mat["alphaCutoff"] = cutoff
        if double_sided:
            mat["doubleSided"] = True
        self.doc["materials"].append(mat)
        return len(self.doc["materials"]) - 1

    def node(self, **fields):
        self.doc["nodes"].append(fields)
        return len(self.doc["nodes"]) - 1

    def skinned_mesh(self, name, positions, normals, uvs, joints, weights, indices, material, skin, targets=()):
        """targets: [(name, position offsets, normal offsets)], morph targets
        (Godot blend shapes), left out where they don't move this mesh."""
        index_type = USHORT if len(positions) < 65536 else UINT
        prim = {"attributes": {
            "POSITION": self.accessor(positions, FLOAT, 34962, minmax=True),
            "NORMAL": self.accessor(normals, FLOAT, 34962),
            "TEXCOORD_0": self.accessor(uvs, FLOAT, 34962),
            "JOINTS_0": self.accessor(joints, UBYTE, 34962),
            "WEIGHTS_0": self.accessor(weights, FLOAT, 34962)},
            "indices": self.accessor(indices.reshape(-1), index_type, 34963),
            "material": material}
        mesh = {"name": name, "primitives": [prim]}
        names = []
        for target, dpos, dnrm in targets:
            acc = self.sparse_accessor(dpos, 2e-4)
            if acc is None:
                continue
            entry = {"POSITION": acc}
            nacc = self.sparse_accessor(dnrm, 0.03)
            if nacc is not None:
                entry["NORMAL"] = nacc
            prim.setdefault("targets", []).append(entry)
            names.append(target)
        if names:
            mesh["weights"] = [0.0] * len(names)
            mesh["extras"] = {"targetNames": names}
        self.doc["meshes"].append(mesh)
        n = self.node(name=name, mesh=len(self.doc["meshes"]) - 1, skin=skin)
        self.doc["scenes"][0]["nodes"].append(n)
        return n

    def save(self, path):
        doc = {k: v for k, v in self.doc.items() if v != []}
        while len(self.blob) % 4:
            self.blob.append(0)
        doc["buffers"] = [{"byteLength": len(self.blob)}]
        text = json.dumps(doc, separators=(",", ":")).encode()
        while len(text) % 4:
            text += b" "
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(text) + 8 + len(self.blob)))
            f.write(struct.pack("<II", len(text), 0x4E4F534A))
            f.write(text)
            f.write(struct.pack("<II", len(self.blob), 0x004E4942))
            f.write(self.blob)
