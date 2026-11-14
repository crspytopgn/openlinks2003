"""Mixamo golf animations played on our golfer as recorded ("direct").

No swing corrections: at the take's first frame every mapped bone is aimed
along the Mixamo bone (so the golfer takes the recorded pose), then each
bone turns exactly as the recorded one does. Fingers and the club keep
their address pose in the hand.

    python3 tools/golfer/mixamo_direct.py --glb game/assets/golfer/free_golfer.glb \\
        --clip swing=golf_drive:24:270 [--clip ...] [--ref address]
"""

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import glb_edit  # noqa: E402
import mixamo_take  # noqa: E402
import mocap_swing as M  # noqa: E402
import pose  # noqa: E402

CHILD = {"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01",
         "neck_01": "head", "clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l",
         "clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r",
         "thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l",
         "thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r"}


def bake(glb, rig, name, take, start, end, ref="address"):
    t = mixamo_take.load(take)
    ref_local, ref_root = rig.sample(glb, "ref_" + ref)
    ref_rots, ref_poss = rig.world(ref_local, ref_root)
    g = M.facing_transform(t, start)
    m_rots0, m_poss0 = t.frame(start)
    # Our pose at the first frame: each bone aimed along the Mixamo bone.
    aligned = list(ref_rots)
    for ours, theirs in M.BONES.items():
        j = rig.index[ours]
        if ours not in CHILD:
            continue
        mine = ref_poss[rig.index[CHILD[ours]]] - ref_poss[j]
        theirs_c = M.BONES[CHILD[ours]]
        d = g @ (m_poss0[t.index[theirs_c]] - m_poss0[t.index[theirs]])
        aligned[j] = M.between(pose.unit(mine), pose.unit(d)) @ ref_rots[j]
    golfer_hip = ref_poss[rig.index["pelvis"]][1] - ref_poss[rig.index["foot_l"]][1]
    actor_hip = m_poss0[t.index["Hips"]][1] - m_poss0[t.index["LeftFoot"]][1]
    scale = golfer_hip / actor_hip
    out, roots = [], []
    for f in range(start, end + 1):
        m_rots, m_poss = t.frame(f)
        rots = [None] * len(rig.names)
        for ours, theirs in M.BONES.items():
            k = t.index[theirs]
            rots[rig.index[ours]] = g @ m_rots[k] @ m_rots0[k].T @ g.T @ aligned[rig.index[ours]]
        rots = M.fill(rig, rots, ref_local)
        root = ref_root + scale * (g @ (m_poss[t.index["Hips"]] - m_poss0[t.index["Hips"]]))
        out.append(rig.locals(rots))
        roots.append(root)
    times = [i / mixamo_take.FPS for i in range(len(out))]
    keep = list(range(0, len(out), 4)) + ([len(out) - 1] if (len(out) - 1) % 4 else [])
    M.write_clip(glb, rig, name, [times[i] for i in keep], [out[i] for i in keep], [roots[i] for i in keep])
    print(f"{name}: {take} {start}-{end}, {times[-1]:.2f} s")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--out")
    ap.add_argument("--clip", action="append", default=[], help="name=take:start:end[:ref]")
    args = ap.parse_args()
    glb = glb_edit.Glb(args.glb)
    rig = M.Rig(glb)
    for c in args.clip:
        name, spec = c.split("=")
        parts = spec.split(":")
        bake(glb, rig, name, parts[0], int(parts[1]), int(parts[2]), parts[3] if len(parts) > 3 else "address")
    glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
