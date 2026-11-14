"""Mixamo golf animations as takes for mocap_swing ("mx:<name>").

Mixamo's files may not be redistributed, so they never go in this repo:
export each FBX to JSON with tools/golfer/mixamo_dump.gd (Godot 4.4) into
the private folder MIXAMO_DIR (default ~/.cache/openlinks/mixamo) as
<name>.json. A take reads like mocap_swing.Bvh: names, index, frame(f)
-> world (rotations, positions), at mocap_swing's 120 frames a second.
"""

import json
import os

import numpy as np

FPS = 120.0
MIXAMO_DIR = os.environ.get("MIXAMO_DIR", os.path.join(os.path.expanduser("~"), ".cache", "openlinks", "mixamo"))

# Mixamo bone -> the CMU name mocap_swing.BONES maps from.
MAP = {
    "Hips": "Hips", "Spine": "LowerBack", "Spine1": "Spine", "Spine2": "Spine1", "Neck": "Neck1", "Head": "Head",
    "LeftShoulder": "LeftShoulder", "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
    "RightShoulder": "RightShoulder", "RightArm": "RightArm", "RightForeArm": "RightForeArm",
    "RightHand": "RightHand",
    "LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg", "LeftFoot": "LeftFoot", "LeftToeBase": "LeftToeBase",
    "RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg", "RightFoot": "RightFoot", "RightToeBase": "RightToeBase",
}


def _quat(m):
    w = np.sqrt(max(0.0, 1.0 + m[0, 0] + m[1, 1] + m[2, 2])) / 2
    x = np.sqrt(max(0.0, 1.0 + m[0, 0] - m[1, 1] - m[2, 2])) / 2
    y = np.sqrt(max(0.0, 1.0 - m[0, 0] + m[1, 1] - m[2, 2])) / 2
    z = np.sqrt(max(0.0, 1.0 - m[0, 0] - m[1, 1] + m[2, 2])) / 2
    x = np.copysign(x, m[2, 1] - m[1, 2])
    y = np.copysign(y, m[0, 2] - m[2, 0])
    z = np.copysign(z, m[1, 0] - m[0, 1])
    q = np.array([w, x, y, z])
    return q / np.linalg.norm(q)


def _mat(q):
    w, x, y, z = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def _slerp(a, b, t):
    if np.dot(a, b) < 0:
        b = -b
    d = float(np.clip(np.dot(a, b), -1.0, 1.0))
    if d > 0.9995:
        q = a + t * (b - a)
    else:
        th = np.arccos(d)
        q = (np.sin((1 - t) * th) * a + np.sin(t * th) * b) / np.sin(th)
    return q / np.linalg.norm(q)


class MixamoTake:
    def __init__(self, path):
        d = json.load(open(path))
        bones = [b.split("_", 1)[-1].split(":")[-1] for b in d["bones"]]
        cols = [bones.index(m) for m in MAP]
        raw = np.array(d["frames"], dtype=float)[:, cols]  # frames, joints, 12
        self.src_fps = d["fps"]
        n = len(raw)
        rots = raw[..., :9].reshape(n, len(cols), 3, 3).transpose(0, 1, 3, 2)  # basis columns
        poss = raw[..., 9:]
        self.names = list(MAP.values())
        self.index = {nm: k for k, nm in enumerate(self.names)}
        self.ends = {}
        quats = np.array([[_quat(r) for r in fr] for fr in rots])
        self.frames = int((n - 1) * FPS / self.src_fps) + 1
        self._q, self._p = quats, poss

    def frame(self, f):
        s = min(f * self.src_fps / FPS, len(self._q) - 1.0)
        a = int(s)
        b = min(a + 1, len(self._q) - 1)
        t = s - a
        rots = np.array([_mat(_slerp(self._q[a, j], self._q[b, j], t)) for j in range(len(self.names))])
        poss = (1 - t) * self._p[a] + t * self._p[b]
        return rots, poss


def load(name):
    return MixamoTake(os.path.join(MIXAMO_DIR, name + ".json"))
