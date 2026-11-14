#!/usr/bin/env python3
"""Gives the free golfer's rig arms a real person's proportions.

    python3 tools/golfer/arm_length.py [--glb ...free_golfer.glb] [--pack ...free_golfer_parts.olg]

The rig's upper arm (shoulder joint to elbow) was 24.9 cm and its forearm
25.5 cm on a 1.75 m body. De Leva's (1996) adjusted segment lengths for an
adult man give 16.2% and 15.5% of height: 28.4 cm and 27.1 cm. With the
short arms a tour address can't be reached: bent forward from the hips
with a flat back and the arms hanging, the hands fall short of the grip,
so the golfer stood hunched (the bend in the upper back and neck) with
both elbows bent (swing_posture.py). The Rocketbox people's own arms
(about 14% longer, i.e. about right) were squashed to the rig's, which is
what made their arms look short and thick.

This lengthens both arm bones by F_UPPER and F_FORE:
- glb: the elbow and wrist joints move down the arm (rest rotations are
  the identity, so only node translations and the inverse bind matrices
  change); every single-key ref_* pose is re-solved so the hands (and the
  club) stay exactly where they were, the elbows bending to suit.
- look pack: every mesh's vertices are stretched with the arm bones they
  are skinned to (along each bone, between its joints; past the wrist they
  move with the hand), and the people's joint offsets follow, so a person's
  arms come back to their real length.

All clips must be rebaked afterwards (mocap_swing.py). Marks the .glb
(extras.arms_v2 on the club node) and the pack (info["arms_v2"]).
"""

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_edit  # noqa: E402
from golf_shoes import load, save  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
F_UPPER = 0.2837 / 0.2490  # de Leva upper arm at the rig's 1.753 m, over the rig's
F_FORE = 0.2709 / 0.2550  # forearm, elbow to wrist joint
FINGERS = ("thumb", "index", "middle", "ring", "pinky")


def _rest_world(offsets, parents):
    out = []
    for j, p in enumerate(parents):
        out.append(np.array(offsets[j], dtype=float) + (out[p] if p >= 0 else 0.0))
    return out


def _chain(names, s):
    """(upper, fore, hand-and-below) bone names of side s."""
    hand = [n for n in names if n == f"hand_{s}" or (n.split("_")[0] in FINGERS and n.endswith("_" + s))]
    if s == "l":
        hand.append("club")
    return f"upperarm_{s}", f"lowerarm_{s}", hand


def stretch(points, weights, bones, names, joints):
    """Each point moved with the arm bones it is skinned to. joints: name
    to the position the mesh was built round."""
    moved = np.array(points, dtype=float)
    disp = np.zeros_like(moved)
    for s in "lr":
        up, fore, hand = _chain(names, s)
        if up not in joints or fore not in joints or f"hand_{s}" not in joints:
            continue
        a_u = joints[fore] - joints[up]
        l_u = np.linalg.norm(a_u)
        a_u = a_u / l_u
        a_f = joints[f"hand_{s}"] - joints[fore]
        l_f = np.linalg.norm(a_f)
        a_f = a_f / l_f
        elbow_move = (F_UPPER - 1.0) * l_u * a_u
        wrist_move = elbow_move + (F_FORE - 1.0) * l_f * a_f
        per = {}
        t_u = np.clip((moved - joints[up]) @ a_u, 0.0, l_u)
        per[up] = (F_UPPER - 1.0) * t_u[:, None] * a_u
        t_f = np.clip((moved - joints[fore]) @ a_f, 0.0, l_f)
        per[fore] = elbow_move + (F_FORE - 1.0) * t_f[:, None] * a_f
        for n in hand:
            per[n] = np.broadcast_to(wrist_move, moved.shape)
        for name, d in per.items():
            if name not in names:
                continue
            k = names.index(name)
            w = np.where(bones == k, weights, 0.0).sum(axis=1)
            disp += w[:, None] * d
    return moved + disp


def new_joints(joints):
    """A person's (or the rig's) joints with the arms lengthened."""
    out = dict(joints)
    for s in "lr":
        up, fore, hand_s = f"upperarm_{s}", f"lowerarm_{s}", f"hand_{s}"
        if up not in joints or fore not in joints or hand_s not in joints:
            continue
        elbow = joints[up] + F_UPPER * (joints[fore] - joints[up])
        wrist = elbow + F_FORE * (joints[hand_s] - joints[fore])
        out[fore] = elbow
        move = wrist - joints[hand_s]
        for n in joints:
            if n == hand_s or (n.split("_")[0] in FINGERS and n.endswith("_" + s)) or (s == "l" and n == "club"):
                out[n] = joints[n] + move
    return out


def fit_glb(glb):
    """Lengthens the rig's arms in the .glb. Returns (old rest, new rest)
    by bone name, or None if already done."""
    from mocap_swing import Rig, write_clip, two_bone

    doc = glb.doc
    rig = Rig(glb)
    club_node = doc["nodes"][rig.joints[rig.index["club"]]]
    if club_node.get("extras", {}).get("arms_v2"):
        return None
    old_rest = _rest_world(rig.offsets, rig.parents)
    refs = [a["name"] for a in doc["animations"] if a["name"].startswith("ref_")]
    before = {ref: rig.world(*rig.sample(glb, ref)) for ref in refs}
    for s in "lr":
        for name, k in ((f"lowerarm_{s}", F_UPPER), (f"hand_{s}", F_FORE)):
            node = doc["nodes"][rig.joints[rig.index[name]]]
            node["translation"] = [float(v) * k for v in node["translation"]]
    rig = Rig(glb)
    new_rest = _rest_world(rig.offsets, rig.parents)
    skin = doc["skins"][0]
    ibm = glb.read(skin["inverseBindMatrices"]).copy()
    for k in range(len(rig.joints)):
        ibm[k, 12:15] = -new_rest[k]
    skin["inverseBindMatrices"] = glb.add(ibm)
    # The club meshes are skinned to the club joint, whose rest moved with
    # the left hand: move them with it.
    club_move = new_rest[rig.index["club"]] - old_rest[rig.index["club"]]
    for node in doc["nodes"]:
        name = node.get("name", "")
        if "mesh" not in node or name.split("_")[0] not in ("Driver", "Iron", "Putter"):
            continue
        for prim in doc["meshes"][node["mesh"]]["primitives"]:
            pos = glb.read(prim["attributes"]["POSITION"]) + club_move
            prim["attributes"]["POSITION"] = glb.add(pos.astype(np.float32), minmax=True)
            doc["bufferViews"][doc["accessors"][prim["attributes"]["POSITION"]]["bufferView"]]["target"] = 34962
    for ref in refs:
        R0, P0 = before[ref]
        local, root = rig.sample(glb, ref)
        R, P = rig.world(local, root)
        R = list(R)
        for s in "lr":
            two_bone(rig, R, list(P), f"upperarm_{s}", f"lowerarm_{s}", f"hand_{s}", P0[rig.index[f"hand_{s}"]])
            R[rig.index[f"hand_{s}"]] = R0[rig.index[f"hand_{s}"]]
        arm = [rig.index[f"{b}_{s}"] for s in "lr" for b in ("upperarm", "lowerarm", "hand")]
        solved = rig.locals(R)
        local = [solved[j] if j in arm else local[j] for j in range(len(local))]
        R1, P1 = rig.world(local, root)
        miss = max(np.linalg.norm(P1[rig.index[f"hand_{s}"]] - P0[rig.index[f"hand_{s}"]]) for s in "lr")
        write_clip(glb, rig, ref, np.zeros(1, np.float32), [local], np.array([root], np.float32), filtered=False)
        print(f"{ref}: hands kept within {miss * 1000:.1f} mm")
    # The putting address is solved again round the longer arms
    # (putt_posture), and the full-swing ones for the first time
    # (swing_posture), when the clips are next baked.
    club_node["extras"].pop("putt_posture", None)
    club_node["extras"].pop("swing_posture", None)
    club_node.setdefault("extras", {})["arms_v2"] = 1
    return ({n: old_rest[k] for k, n in enumerate(rig.names)}, {n: new_rest[k] for k, n in enumerate(rig.names)})


def fit_pack(info, blob, old_rest, new_rest):
    """Stretches every pack mesh's arms and moves the people's joints."""
    if info.get("arms_v2"):
        return False
    names = info["bones"]
    people = info.get("people", {})
    span = lambda s: bytes(blob[s[0]:s[0] + s[1]])  # noqa: E731
    for part, e in info["parts"].items():
        if "positions" not in e or "bones" not in e or "weights" not in e:
            continue
        who = next((p for p in people if part.startswith(f"RB_{p}_")), None)
        joints = dict(old_rest)
        if who:
            for b, d in people[who]["joints"].items():
                joints[b] = old_rest[b] + np.array(d, dtype=float)
        pos = np.frombuffer(span(e["positions"]), np.float32).reshape(-1, 3)
        bones = np.frombuffer(span(e["bones"]), np.int32).reshape(-1, 4)
        weights = np.frombuffer(span(e["weights"]), np.float32).reshape(-1, 4)
        out = stretch(pos, weights, bones, names, joints).astype(np.float32)
        off, size = e["positions"]
        assert out.nbytes == size
        blob[off:off + size] = out.tobytes()
    for who, p in people.items():
        joints = {b: old_rest[b] + np.array(d, dtype=float) for b, d in p["joints"].items()}
        for b in old_rest:
            joints.setdefault(b, old_rest[b].copy())
        moved = new_joints(joints)
        p["joints"] = {b: (moved[b] - new_rest[b]).tolist() for b in p["joints"]}
    info["arms_v2"] = True
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--glb", default=os.path.join(ROOT, "game/assets/golfer/free_golfer.glb"))
    ap.add_argument("--pack", default=os.path.join(ROOT, "game/assets/golfer/free_golfer_parts.olg"))
    args = ap.parse_args()
    glb = glb_edit.Glb(args.glb)
    rests = fit_glb(glb)
    if rests is None:
        print("arms already lengthened")
        return 0
    glb.save(args.glb)
    info, blob = load(args.pack)
    if fit_pack(info, blob, *rests):
        save(args.pack, info, blob)
        print("look pack: arms stretched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
