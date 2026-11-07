"""Re-poses the putting address the way tour putters stand.

The putting address came from the full-swing address (pose.Poser) with a
putter in the hands: nearly upright (the trunk 18 deg forward), the right
shoulder dropped and pushed out as for a driver, the right arm locked
straight across the body and the left elbow bent 53 deg. The hands only
met the putter's grip by bending both wrists about 60 deg towards the
little finger, past the 35 deg a wrist can go (tools/golfer/anatomy.py),
which is what made the hands look broken in close-ups.

Photos and video of tour putters (down the line and face on) show
instead: bent from the hips with a flat back, the trunk about 40 deg
forward; the shoulders over the hands so the arms hang; both elbows
softly and evenly bent (about 20-30 deg) and close to the sides; the
forearms in line with the shaft; the shoulders nearly level, the right a
touch lower because the right hand is below the left; the knees a little
flexed; the eyes over the ball.

The putter and both hands stay exactly where they are (so the grip and
the strike don't change); the body is solved round them: the hips' tilt,
the bend and side bend through the spine and where the hips sit, with
the legs and arms reaching their feet and hands by IK and the elbows
turned (anatomy.fit_arm) to keep the wrists in their range. The neck then
tips the eyes down to the ball. Marks the .glb (extras.putt_posture).
"""

import math

import numpy as np
from scipy.optimize import minimize

import anatomy
import pose

ELBOW = 28.0  # degrees, both arms
KNEE = 18.0
SPINE_FLEX = 8.0  # each of the three spine joints, as a starting point
PELVIS_TILT = 10.0  # added to the address's hip tilt, a starting point
HANG = 0.0  # shoulders this far behind the hands (m, + = nearer the feet)
LEAN = 38.0  # the trunk (hips to the neck) from upright, degrees
HIPS_BEHIND = 0.0  # hip joints over the ankles (m): weight over the arches
EYES_INSIDE = 0.03  # the eyes this far inside the ball (towards the feet)
SOLE = 0.0066  # the putter's sole above the ground at address, metres
EYE = np.array([0.0, 0.09, -0.1])  # eyes from the head joint, rest frame


def _knee(rig, P, s):
    i = rig.index
    a = P[i[f"calf_{s}"]] - P[i[f"thigh_{s}"]]
    b = P[i[f"foot_{s}"]] - P[i[f"calf_{s}"]]
    return math.degrees(math.acos(np.clip(np.dot(pose.unit(a), pose.unit(b)), -1, 1)))


def solve(glb, rig, ref="ref_address_putt", club="Putter"):
    """The new (local rotations, root) for the putting address."""
    from mocap_swing import club_direction as club_dir
    from mocap_swing import club_head_verts, knee_pole, reach_pole

    i = rig.index
    local0, root0 = rig.sample(glb, ref)
    R0, P0 = rig.world(local0, root0)
    _, rest = rig.world([np.eye(3)] * len(rig.names), rig.offsets[0])
    cj = i["club"]
    verts = club_head_verts(glb, club)
    head = (R0[cj] @ (verts - rest[cj]).T).T + P0[cj]
    # The putter may be shorter than the one the address was built with
    # (pose.PUTTER): the hands and putter slide down the shaft's line until
    # the sole rests on the green again.
    shaft = R0[cj] @ club_dir(glb, rig)
    slide = shaft * (head[:, 1].min() - SOLE) / -shaft[1]
    ball = head.mean(axis=0) + slide
    hands = {s: (R0[i[f"hand_{s}"]], P0[i[f"hand_{s}"]] + slide) for s in "lr"}
    hands_mid = (hands["l"][1] + hands["r"][1]) / 2
    fwd_axis = np.array([-1.0, 0.0, 0.0])  # turning about -x tips +y towards -z
    side_axis = np.array([0.0, 0.0, -1.0])  # about -z tips +y towards +x (his right)

    def build(x):
        tilt, flex, side, dx, dy, dz = x
        local = [m.copy() for m in local0]
        root = np.array(root0, dtype=float) + [dx, dy, dz]
        pel = i["pelvis"]
        local[pel] = pose.rot(fwd_axis, tilt) @ local0[pel]
        for n in ("spine_01", "spine_02", "spine_03"):
            local[i[n]] = pose.rot(side_axis, side) @ pose.rot(fwd_axis, flex)
        R, P = rig.world(local, root)
        R = list(R)
        for s in "lr":
            foot = R0[i[f"foot_{s}"]]
            reach_pole(rig, R, list(P), f"thigh_{s}", f"calf_{s}", f"foot_{s}", P0[i[f"foot_{s}"]], knee_pole(rig, R))
            R[i[f"foot_{s}"]] = foot
        R, P = rig.world(rig.locals(R), root)
        R = list(R)
        for s in "lr":
            sh = P[i[f"upperarm_{s}"]]
            # Elbows in towards the hips and back.
            pole = pose.unit(P[i["pelvis"]] - sh) + np.array([0.0, 0.0, 0.6])
            reach_pole(rig, R, list(P), f"upperarm_{s}", f"lowerarm_{s}", f"hand_{s}", hands[s][1], pole)
        for s in "lr":
            R[i[f"hand_{s}"]] = hands[s][0]
        R, P = rig.world(rig.locals(R), root)
        return R, P, root

    def cost(x, report=False):
        R, P, _ = build(x)
        tilt, flex, side = x[:3]
        sh_mid = (P[i["upperarm_l"]] + P[i["upperarm_r"]]) / 2
        trunk = pose.unit(P[i["neck_01"]] - P[i["pelvis"]])
        lean = math.degrees(math.acos(np.clip(trunk[1], -1, 1)))
        ankles = (P0[i["foot_l"]] + P0[i["foot_r"]]) / 2
        terms = {
            "lean": (lean - LEAN) ** 2 * 0.2,
            "balance": ((P[i["pelvis"]][2] - ankles[2] - HIPS_BEHIND) * 100) ** 2,
            "hang": ((sh_mid[2] - hands_mid[2] - HANG) * 100) ** 2,
            "centre": ((sh_mid[0] - hands_mid[0]) * 100) ** 2,
            "knees": sum((_knee(rig, P, s) - KNEE) ** 2 for s in "lr") * 0.5,
            "spine": (flex - SPINE_FLEX) ** 2 * 0.05 + side ** 2 * 0.05,
            "reach": 0.0,
        }
        R = list(R)
        terms["wrists"] = 0.0
        for s in "lr":
            anatomy.fit_arm(rig, R, P, s)
            a = anatomy.arm_angles(rig, s, R[i[f"upperarm_{s}"]], R[i[f"lowerarm_{s}"]], R[i[f"hand_{s}"]])
            terms["reach"] += (a["elbow_flex"] - ELBOW) ** 2 * 0.05
            for k in ("wrist_flex", "wrist_dev", "forearm_roll"):
                lo, hi = anatomy.limit_of(k)
                terms["wrists"] += max(0.0, lo + 5 - a[k], a[k] - hi + 5) ** 2
            # Hands must actually be reached.
            terms["reach"] += (np.linalg.norm(P[i[f"hand_{s}"]] - hands[s][1]) * 1000) ** 2
        if report:
            return terms
        return sum(terms.values())

    x0 = np.array([PELVIS_TILT, SPINE_FLEX, 0.0, 0.0, 0.0, 0.0])
    bounds = [(-10.0, 40.0), (2.0, 14.0), (-6.0, 6.0), (-0.1, 0.1), (-0.15, 0.08), (-0.2, 0.2)]
    res = minimize(cost, x0, method="Powell", bounds=bounds, options=dict(maxiter=6000, xtol=1e-3, ftol=1e-5))
    R, P, root = build(res.x)
    # Elbow swivel and forearm roll inside the joints' ranges.
    for s in "lr":
        anatomy.fit_arm(rig, R, P, s)
    R, P = rig.world(rig.locals(R), root)
    # Eyes down at the ball, the head tipped by the neck and head joints.
    R = list(R)
    head = i["head"]
    eyes = P[head] + R[head] @ EYE
    look = R[head] @ pose.unit(np.array([0.0, -0.35, -1.0]))  # the eyes' line, rest frame
    want = pose.unit(ball + np.array([0.0, 0.0, EYES_INSIDE]) - eyes)
    turn = anatomy.between(look, want)
    for n, share in (("neck_01", 0.5), ("head", 0.5)):
        t = pose.slerp(np.eye(3), turn, share)
        for k in anatomy.descendants(rig, i[n]):
            R[k] = t @ R[k]
    info = dict(params=np.round(res.x, 3).tolist(), **{k: round(v, 2) for k, v in cost(res.x, True).items()})
    return rig.locals(R), root, info


def fit(glb, rig):
    """Re-poses ref_address_putt. Returns False if already done."""
    from mocap_swing import write_clip

    cj = rig.index["club"]
    club_node = glb.doc["nodes"][rig.joints[cj]]
    if club_node.get("extras", {}).get("putt_posture") or not glb.animation("ref_address_putt"):
        return False
    local, root, info = solve(glb, rig)
    write_clip(glb, rig, "ref_address_putt", np.zeros(1, np.float32), [local], np.array([root], np.float32), filtered=False)
    print("ref_address_putt:", info)
    club_node.setdefault("extras", {})["putt_posture"] = 1
    return True
