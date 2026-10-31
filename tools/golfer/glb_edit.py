"""Reads a .glb, lets animations be replaced, and writes it back compacted
(only the buffer data still referenced is kept)."""

import json
import struct

import numpy as np

_DTYPES = {5126: np.float32, 5121: np.uint8, 5123: np.uint16, 5125: np.uint32}
_WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
_TYPES = {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4", 16: "MAT4"}


class Glb:
    def __init__(self, path):
        raw = open(path, "rb").read()
        length = struct.unpack("<I", raw[12:16])[0]
        self.doc = json.loads(raw[20:20 + length])
        start = 20 + length
        size = struct.unpack("<I", raw[start:start + 4])[0]
        self.blob = bytearray(raw[start + 8:start + 8 + size])

    def read(self, index):
        a = self.doc["accessors"][index]
        view = self.doc["bufferViews"][a["bufferView"]]
        width = _WIDTH[a["type"]]
        offset = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        arr = np.frombuffer(self.blob, _DTYPES[a["componentType"]], a["count"] * width, offset)
        return arr.reshape(a["count"], width) if width > 1 else arr

    def add(self, array, minmax=False, component=5126):
        a = np.ascontiguousarray(array, dtype=_DTYPES[component])
        while len(self.blob) % 4:
            self.blob.append(0)
        self.doc["bufferViews"].append({"buffer": 0, "byteOffset": len(self.blob), "byteLength": a.nbytes})
        self.blob.extend(a.tobytes())
        width = 1 if a.ndim == 1 else int(np.prod(a.shape[1:]))
        acc = {"bufferView": len(self.doc["bufferViews"]) - 1, "componentType": component,
               "count": int(a.shape[0]), "type": _TYPES[width]}
        if minmax:
            flat = a.reshape(a.shape[0], -1)
            acc["min"] = [float(x) for x in flat.min(axis=0)]
            acc["max"] = [float(x) for x in flat.max(axis=0)]
        self.doc["accessors"].append(acc)
        return len(self.doc["accessors"]) - 1

    def animation(self, name):
        for a in self.doc["animations"]:
            if a["name"] == name:
                return a
        return None

    def set_animation(self, anim):
        anims = self.doc["animations"]
        for i, a in enumerate(anims):
            if a["name"] == anim["name"]:
                anims[i] = anim
                return
        anims.append(anim)

    def save(self, path):
        doc = self.doc
        # Accessors and buffer views still in use.
        used_acc = set()
        for mesh in doc["meshes"]:
            for prim in mesh["primitives"]:
                used_acc.update(prim["attributes"].values())
                for target in prim.get("targets", []):
                    used_acc.update(target.values())
                if "indices" in prim:
                    used_acc.add(prim["indices"])
        for skin in doc.get("skins", []):
            if "inverseBindMatrices" in skin:
                used_acc.add(skin["inverseBindMatrices"])
        for anim in doc.get("animations", []):
            for s in anim["samplers"]:
                used_acc.update((s["input"], s["output"]))
        used_views = {doc["accessors"][i]["bufferView"] for i in used_acc if "bufferView" in doc["accessors"][i]}
        for i in used_acc:
            sparse = doc["accessors"][i].get("sparse")
            if sparse:
                used_views.update((sparse["indices"]["bufferView"], sparse["values"]["bufferView"]))
        used_views.update(img["bufferView"] for img in doc.get("images", []) if "bufferView" in img)
        view_map, acc_map, blob, views, accs = {}, {}, bytearray(), [], []
        for i in sorted(used_views):
            v = dict(doc["bufferViews"][i])
            while len(blob) % 4:
                blob.append(0)
            start = v.get("byteOffset", 0)
            data = self.blob[start:start + v["byteLength"]]
            v["byteOffset"] = len(blob)
            blob.extend(data)
            view_map[i] = len(views)
            views.append(v)
        for i in sorted(used_acc):
            a = dict(doc["accessors"][i])
            if "bufferView" in a:
                a["bufferView"] = view_map[a["bufferView"]]
            if "sparse" in a:
                sp = a["sparse"]
                a["sparse"] = {"count": sp["count"],
                               "indices": dict(sp["indices"], bufferView=view_map[sp["indices"]["bufferView"]]),
                               "values": dict(sp["values"], bufferView=view_map[sp["values"]["bufferView"]])}
            acc_map[i] = len(accs)
            accs.append(a)
        for mesh in doc["meshes"]:
            for prim in mesh["primitives"]:
                prim["attributes"] = {k: acc_map[v] for k, v in prim["attributes"].items()}
                if "targets" in prim:
                    prim["targets"] = [{k: acc_map[v] for k, v in t.items()} for t in prim["targets"]]
                if "indices" in prim:
                    prim["indices"] = acc_map[prim["indices"]]
        for skin in doc.get("skins", []):
            if "inverseBindMatrices" in skin:
                skin["inverseBindMatrices"] = acc_map[skin["inverseBindMatrices"]]
        for anim in doc.get("animations", []):
            for s in anim["samplers"]:
                s["input"], s["output"] = acc_map[s["input"]], acc_map[s["output"]]
        for img in doc.get("images", []):
            if "bufferView" in img:
                img["bufferView"] = view_map[img["bufferView"]]
        doc["bufferViews"], doc["accessors"] = views, accs
        while len(blob) % 4:
            blob.append(0)
        doc["buffers"] = [{"byteLength": len(blob)}]
        self.blob = blob
        text = json.dumps(doc, separators=(",", ":")).encode()
        while len(text) % 4:
            text += b" "
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(text) + 8 + len(blob)))
            f.write(struct.pack("<II", len(text), 0x4E4F534A))
            f.write(text)
            f.write(struct.pack("<II", len(blob), 0x004E4942))
            f.write(blob)
