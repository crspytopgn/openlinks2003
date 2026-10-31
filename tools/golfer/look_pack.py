"""Writes the free golfer's look pack (game/assets/golfer/free_golfer_parts.olg):
every body part, outfit and hair style the player creator can choose, with
their blend shapes and textures, read by game/scripts/assets/golfer_parts.gd.

The game builds these meshes itself (instead of importing them from the
glTF) so that it can bake a player's shape into plain meshes once: no blend
shapes on the GPU, and a small file.

Layout: b"OLGL", u32 version, u32 size of the data once inflated, then the
data gzip-compressed: u32 header length, the header (UTF-8 JSON), then the
arrays the header points to (byte offsets into what follows the header).
Arrays are little-endian: f32 positions, uvs and weights, i32 bone indices
and triangles, f16 normals, tangents and blend shape offsets.
"""

import gzip
import json
import struct

import numpy as np

VERSION = 1


def tangents(positions, normals, uvs, indices):
    """Per-vertex tangents (xyz, w = bitangent sign) from the uvs."""
    p0, p1, p2 = (positions[indices[:, k]] for k in range(3))
    t0, t1, t2 = (uvs[indices[:, k]] for k in range(3))
    e1, e2 = p1 - p0, p2 - p0
    d1, d2 = t1 - t0, t2 - t0
    r = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
    r = np.where(np.abs(r) < 1e-12, 1e-12, r)
    sdir = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) / r[:, None]
    tdir = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) / r[:, None]
    tan = np.zeros_like(positions)
    bit = np.zeros_like(positions)
    for k in range(3):
        np.add.at(tan, indices[:, k], sdir)
        np.add.at(bit, indices[:, k], tdir)
    tan = tan - normals * (tan * normals).sum(axis=1, keepdims=True)
    tan /= np.maximum(np.linalg.norm(tan, axis=1, keepdims=True), 1e-12)
    w = np.where((np.cross(normals, tan) * bit).sum(axis=1) < 0, -1.0, 1.0)
    return np.column_stack([tan, w])


class Pack:
    def __init__(self):
        self.blob = bytearray()
        self.header = {"images": [], "materials": {}, "parts": {}}

    def _add(self, array, dtype):
        a = np.ascontiguousarray(array, dtype=dtype)
        while len(self.blob) % 4:
            self.blob.append(0)
        offset = len(self.blob)
        self.blob.extend(a.tobytes())
        return [offset, a.nbytes]

    def image(self, data, kind):
        """data: encoded jpg or png bytes. Returns the image's index."""
        self.header["images"].append({"kind": kind, "data": self._add(np.frombuffer(data, np.uint8), np.uint8)})
        return len(self.header["images"]) - 1

    def material(self, name, texture=-1, normal=-1, roughness=0.85, cutoff=0.0, double_sided=False, tint="",
                 colour=(1, 1, 1)):
        """cutoff > 0 makes it alpha-scissored; tint names the PlayerLook
        colour it is multiplied by."""
        self.header["materials"][name] = {"texture": texture, "normal": normal, "roughness": roughness,
                                          "cutoff": cutoff, "double_sided": double_sided, "tint": tint,
                                          "colour": [float(c) for c in colour]}

    def part(self, name, material, positions, normals, uvs, joints, weights, indices, targets, with_tangents=False,
             tolerance=2e-4):
        """targets: [(shape name, position offsets, normal offsets)]; only
        the rows moved more than `tolerance` (metres) are kept, and shapes
        that move nothing are left out."""
        entry = {
            "material": material, "count": int(len(positions)),
            "positions": self._add(positions, "<f4"),
            "normals": self._add(normals, "<f2"),
            "uvs": self._add(uvs, "<f4"),
            "bones": self._add(joints.astype(np.int32), "<i4"),
            "weights": self._add(weights, "<f4"),
            # Godot's front faces wind clockwise, glTF's (and MakeHuman's)
            # anticlockwise.
            "indices": self._add(indices[:, ::-1].reshape(-1).astype(np.int32), "<i4"),
            "shapes": {},
        }
        if with_tangents:
            entry["tangents"] = self._add(tangents(positions, normals, uvs, indices), "<f2")
        for shape, dpos, dnrm in targets:
            rows = np.nonzero(np.abs(dpos).max(axis=1) > tolerance)[0]
            if len(rows) == 0:
                continue
            s = {"rows": self._add(rows.astype(np.int32), "<i4"), "positions": self._add(dpos[rows], "<f2")}
            if np.abs(dnrm[rows]).max() > 0.03:
                s["normals"] = self._add(dnrm[rows], "<f2")
            entry["shapes"][shape] = s
        self.header["parts"][name] = entry

    def save(self, path, **extra):
        self.header.update(extra)
        head = json.dumps(self.header, separators=(",", ":"), sort_keys=True).encode()
        while len(head) % 4:
            head += b" "
        data = struct.pack("<I", len(head)) + head + bytes(self.blob)
        with open(path, "wb") as f:
            f.write(b"OLGL" + struct.pack("<II", VERSION, len(data)))
            f.write(gzip.compress(data, 9, mtime=0))
