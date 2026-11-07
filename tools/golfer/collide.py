"""Checks the golfer's clips for one body part passing through another,
using the real skinned body, not joint angles.

    python3 tools/golfer/collide.py [glb] [--person Male_Adult_14] [--clip X] [--step 0.1]

anatomy.py measures joint angles against the body's range of motion. A pose
can pass every angle and still be impossible: an upper arm turned in at the
shoulder runs through the chest (Michael, 2026-11-07: "an arm literally
coming out the center of his chest"). Here the person's body mesh from the
look pack is skinned onto the rig in each clip (linear blend skinning, as
Godot does), split into parts by the bone that carries each vertex
(torso, head, each arm, each leg), and every vertex of one part is tested
against the surface of the other: it is inside when it lies behind the
nearest surface point of the other part (against that point's normal).

Pairs checked: each arm against the torso, the head and each leg; the legs
against each other; the arms against each other above the wrists (the
hands share the grip). Vertices near a joint the two parts share (the
armpit, the crotch) blend between them and are skipped.

Reported per clip: the deepest point, how far in (cm), how many vertices
and when. Exit status 1 if anything is in deeper than --limit cm.
"""

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import glb_edit  # noqa: E402
from golf_shoes import load  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
GLB = os.path.join(ROOT, "game/assets/golfer/free_golfer.glb")
PACK = os.path.join(ROOT, "game/assets/golfer/free_golfer_parts.olg")
DEPTH = 0.012  # metres behind the other part's surface before it counts (skin and cloth slide)
LIMIT = 1.5  # cm, the depth that fails the check
JOINT_SKIP = 0.10  # metres round a joint the two parts meet at

FINGERS = ("thumb", "index", "middle", "ring", "pinky")


def part_of(name):
    """The body part a bone belongs to."""
    side = name[-1] if name[-2:] in ("_l", "_r") else ""
    base = name.split("_")[0]
    if base in ("upperarm", "lowerarm"):
        return "arm_" + side
    if base == "hand" or base in FINGERS:
        return "hand_" + side
    if base in ("thigh", "calf", "foot", "ball"):
        return "leg_" + side
    if base in ("neck", "head"):
        return "head"
    if base == "club":
        return None
    return "torso"  # Root, pelvis, spine, clavicles


# Pairs (a, b): a's vertices against b's surface, and the joints near which
# they blend into each other.
PAIRS = []
for _s in "lr":
    _o = "r" if _s == "l" else "l"
    PAIRS += [
        (f"arm_{_s}", "torso", [f"upperarm_{_s}", f"clavicle_{_s}"]),
        (f"hand_{_s}", "torso", []),
        (f"arm_{_s}", "head", []),
        (f"hand_{_s}", "head", []),
        (f"arm_{_s}", f"leg_{_s}", []),
        (f"arm_{_s}", f"leg_{_o}", []),
        (f"hand_{_s}", f"leg_{_s}", []),
        (f"hand_{_s}", f"leg_{_o}", []),
        (f"arm_{_s}", f"arm_{_o}", []),
    ]
PAIRS += [("leg_l", "leg_r", ["thigh_l", "thigh_r"])]  # head-torso: the collar and neck blend


class Body:
    """A person's body mesh, bound to the rig at the person's joints."""

    def __init__(self, glb, pack, person):
        import mocap_swing

        self.rig = mocap_swing.Rig(glb)
        info, blob = load(pack)
        assert info["bones"] == self.rig.names, "pack bones differ from the rig's"
        p = info["people"][person]

        def arr(ref, dtype, cols):
            off, n = ref
            return np.frombuffer(bytes(blob[off:off + n]), dtype).reshape(-1, cols).astype(np.float64 if dtype != np.int32 else np.int32)

        pos, nrm, bones, weights, tris = [], [], [], [], []
        base = 0
        for name in p["parts"]:
            part = info["parts"][name]
            pos.append(arr(part["positions"], np.float32, 3))
            tris.append(arr(part["indices"], np.int32, 3) + base)
            base += len(pos[-1])
            nrm.append(arr(part["normals"], np.float16, 3))
            bones.append(arr(part["bones"], np.int32, 4))
            weights.append(arr(part["weights"], np.float32, 4))
        self.pos, self.nrm = np.concatenate(pos), np.concatenate(nrm)
        self.bones, self.weights = np.concatenate(bones), np.concatenate(weights)
        self.tris = np.concatenate(tris)
        rig = self.rig
        _, rest = rig.world([np.eye(3)] * len(rig.names), rig.offsets[0])
        joints = p["joints"]
        self.rest = np.array([rest[j] + np.array(joints.get(n, [0.0, 0.0, 0.0])) for j, n in enumerate(rig.names)])
        self.offsets = [self.rest[j] - (self.rest[q] if q >= 0 else 0.0) for j, q in enumerate(rig.parents)]
        top = self.bones[np.arange(len(self.bones)), np.argmax(self.weights, axis=1)]
        self.part = np.array([part_of(rig.names[b]) for b in top], dtype=object)
        # A triangle belongs to a part when all three corners do.
        tp = self.part[self.tris]
        self.tri_part = np.where((tp[:, 0] == tp[:, 1]) & (tp[:, 1] == tp[:, 2]), tp[:, 0], None)

    def pose(self, local, root):
        """Posed vertices and normals."""
        rig = self.rig
        R, P = [], []
        for j, q in enumerate(rig.parents):
            if q < 0:
                R.append(local[j])
                P.append(np.array(root, dtype=float) - rig.offsets[0] + self.offsets[j])
            else:
                R.append(R[q] @ local[j])
                P.append(P[q] + R[q] @ self.offsets[j])
        R, P = np.array(R), np.array(P)
        v = np.zeros_like(self.pos)
        n = np.zeros_like(self.nrm)
        for k in range(4):
            b, w = self.bones[:, k], self.weights[:, k][:, None]
            v += w * (np.einsum("nij,nj->ni", R[b], self.pos - self.rest[b]) + P[b])
            n += w * np.einsum("nij,nj->ni", R[b], self.nrm)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        return v, n, P, R


# Each part a tube round a line of joints: its surface's distance from the
# line by height along it and direction round it, read from the posed mesh.
AXES = {
    "torso": ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01"],
    "head": ["neck_01", "head"],
    "leg_l": ["thigh_l", "calf_l", "foot_l"],
    "leg_r": ["thigh_r", "calf_r", "foot_r"],
    "arm_l": ["upperarm_l", "lowerarm_l", "hand_l"],
    "arm_r": ["upperarm_r", "lowerarm_r", "hand_r"],
}
STEP = 0.03  # metres along the line per cross-section
SECTORS = 24  # directions round it


def _on_line(pts, line):
    """Each point's distance along the polyline (m), its nearest point on
    it and the index of the segment."""
    best = np.full(len(pts), np.inf)
    s_out = np.zeros(len(pts))
    foot = np.zeros_like(pts)
    seg = np.zeros(len(pts), int)
    run = 0.0
    for k in range(len(line) - 1):
        a, b = line[k], line[k + 1]
        d = b - a
        L = float(np.linalg.norm(d))
        t = np.clip((pts - a) @ d / (L * L), 0.0, 1.0)
        q = a + t[:, None] * d
        dist = np.linalg.norm(pts - q, axis=1)
        better = dist < best
        best = np.where(better, dist, best)
        s_out = np.where(better, run + t * L, s_out)
        foot = np.where(better[:, None], q, foot)
        seg = np.where(better, k, seg)
        run += L
    return s_out, foot, seg, run


def _sector(radial, frames, seg):
    """Direction round the line, 0..SECTORS-1, in each segment's frame."""
    x = np.einsum("ni,ni->n", radial, frames[seg, :, 0])
    z = np.einsum("ni,ni->n", radial, frames[seg, :, 2])
    ang = np.arctan2(z, x)
    return ((ang + np.pi) / (2 * np.pi) * SECTORS).astype(int) % SECTORS


class Tube:
    def __init__(self, body, v, R, P, part):
        rig = body.rig
        names = AXES[part]
        self.line = np.array([P[rig.index[n]] for n in names])
        self.frames = np.array([R[rig.index[n]] for n in names[:-1]])
        # The part's surface, densified with its triangles' centres and edge
        # middles (the mesh is coarse).
        m = body.part == part
        tri = body.tris[body.tri_part == part]
        pts = np.concatenate([v[m], v[tri].mean(axis=1), (v[tri[:, 0]] + v[tri[:, 1]]) / 2,
                              (v[tri[:, 1]] + v[tri[:, 2]]) / 2, (v[tri[:, 2]] + v[tri[:, 0]]) / 2])
        s, foot, seg, self.length = _on_line(pts, self.line)
        rad = pts - foot
        r = np.linalg.norm(rad, axis=1)
        sec = _sector(rad, self.frames, seg)
        rows = int(np.ceil(self.length / STEP)) + 1
        grid = np.zeros((rows, SECTORS))
        np.maximum.at(grid, (np.clip((s / STEP).astype(int), 0, rows - 1), sec), r)
        # Fill gaps from the neighbours round the line and along it.
        for _ in range(3):
            empty = grid == 0.0
            if not empty.any():
                break
            nb = np.maximum.reduce([np.roll(grid, 1, 1), np.roll(grid, -1, 1),
                                    np.vstack([grid[1:], grid[-1:]]), np.vstack([grid[:1], grid[:-1]])])
            grid = np.where(empty, nb, grid)
        self.grid = grid

    def depth(self, pts):
        """How far each point is inside the tube (m, 0 if outside or beyond
        its ends)."""
        s, foot, seg, _ = _on_line(pts, self.line)
        rad = pts - foot
        r = np.linalg.norm(rad, axis=1)
        sec = _sector(rad, self.frames, seg)
        row = np.clip((s / STEP).astype(int), 0, len(self.grid) - 1)
        surf = self.grid[row, sec]
        inside_ends = (s > STEP) & (s < self.length - STEP)
        return np.where(inside_ends & (surf > 0.0), np.maximum(0.0, surf - r), 0.0)


def inside(body, v, n, P, a, b, near, R=None, tubes=None):
    """Depth (m) of each of a's vertices inside part b (0 if outside),
    less DEPTH for skin and cloth that give."""
    rig = body.rig
    ia = np.where(body.part == a)[0]
    if not len(ia) or b not in AXES:
        return ia, np.zeros(0)
    va = v[ia]
    keep = np.ones(len(ia), bool)
    for j in near:
        keep &= np.linalg.norm(va - P[rig.index[j]], axis=1) > JOINT_SKIP
    tube = tubes[b] if tubes and b in tubes else Tube(body, v, R, P, b)
    d = tube.depth(va)
    d = np.where(keep & (d > DEPTH), d - DEPTH, 0.0)
    return ia, d


def check(body, glb, clip, step):
    import anatomy

    rig = body.rig
    frames = anatomy.clip_frames(glb, rig, clip)
    worst = {}
    picked, last = [], None
    for f in frames:
        if last is None or f[0] - last >= step - 1e-6 or f is frames[-1]:
            picked.append(f)
            last = f[0]
    for t, local, root in picked:
        v, n, P, R = body.pose(local, root)
        tubes = {k: Tube(body, v, R, P, k) for k in AXES}
        for a, b, near in PAIRS:
            _, d = inside(body, v, n, P, a, b, near, tubes=tubes)
            if len(d) and d.max() > 0.0:
                key = f"{a} in {b}"
                if key not in worst or d.max() > worst[key][0]:
                    worst[key] = (float(d.max()), int((d > 0).sum()), float(t))
    return worst


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("glb", nargs="?", default=GLB)
    ap.add_argument("--pack", default=PACK)
    ap.add_argument("--person", default="Male_Adult_14")
    ap.add_argument("--clip", action="append")
    ap.add_argument("--step", type=float, default=0.1, help="seconds between checked keys")
    ap.add_argument("--limit", type=float, default=LIMIT)
    args = ap.parse_args()
    glb = glb_edit.Glb(args.glb)
    body = Body(glb, args.pack, args.person)
    clips = args.clip or [a["name"] for a in glb.doc["animations"] if not a["name"].startswith("ref_")]
    bad = False
    for clip in clips:
        worst = check(body, glb, clip, args.step)
        lines = [f"  {k:24s} {d * 100:4.1f} cm deep, {c} verts, at {t:.2f}s"
                 for k, (d, c, t) in sorted(worst.items(), key=lambda kv: -kv[1][0]) if d * 100 >= 0.5]
        print(f"{clip}:" + (" ok" if not lines else ""))
        for line in lines:
            print(line)
        bad |= any(d * 100 > args.limit for d, _, _ in worst.values())
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()


class Guard:
    """Keeps the arms out of the body while solvers place them: built once
    per person, then `frame(rots, root)` for a pose (world rotations from
    the rig, its root) gives the torso to test against and the arm's own
    vertices, so a solver can try elbow positions against the real body."""

    def __init__(self, glb, pack=PACK, person="Male_Adult_14"):
        self.body = Body(glb, pack, person)
        b = self.body
        self.arm = {s: np.where(b.part == f"arm_{s}")[0] for s in "lr"}
        self.torso = np.where(b.part == "torso")[0]

    def frame(self, rots, root):
        b, rig = self.body, self.body.rig
        R = np.array(rots)
        P = []
        for j, q in enumerate(rig.parents):
            P.append(np.array(root, dtype=float) - rig.offsets[0] + b.offsets[j] if q < 0 else P[q] + R[q] @ b.offsets[j])
        P = np.array(P)
        v = np.zeros_like(b.pos)
        for k in range(4):
            bk, w = b.bones[:, k], b.weights[:, k][:, None]
            v += w * (np.einsum("nij,nj->ni", R[bk], b.pos - b.rest[bk]) + P[bk])
        return _Frame(self, v, R, P)


class _Frame:
    def __init__(self, guard, v, R, P):
        self.guard, self.v, self.P = guard, v, P
        self.tube = Tube(guard.body, v, R, P, "torso")

    def arm_depth(self, s, turn=None, pivot=None):
        """Deepest point (m) of arm `s` inside the torso, the arm turned by
        `turn` about `pivot` (an elbow swivel) first; points within
        JOINT_SKIP of the shoulder and collarbone blend into the torso and
        don't count."""
        rig = self.guard.body.rig
        pts = self.v[self.guard.arm[s]]
        if turn is not None:
            pts = pivot + (pts - pivot) @ turn.T
        keep = np.ones(len(pts), bool)
        for j in (f"upperarm_{s}", f"clavicle_{s}"):
            keep &= np.linalg.norm(pts - self.P[rig.index[j]], axis=1) > JOINT_SKIP
        if not keep.any():
            return 0.0
        d = self.tube.depth(pts[keep])
        return float(max(0.0, d.max() - DEPTH)) if len(d) else 0.0
