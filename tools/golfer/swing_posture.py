"""Re-poses the full-swing addresses (driver and iron) the way tour players
stand over the ball.

The addresses built by pose.Poser and fitted by grip.py bent the golfer
forward mostly through the upper back and neck: measured hips to neck the
trunk leaned only 25 deg (driver), with the lowest spine joint tipped 5 deg
BACK, the chest segment 35 deg forward and the neck 63 deg, so the back
curled into a C and the chin sat on the chest. The hands reached 13 cm out
past the shoulders and the lead elbow was bent 20 deg (more than the
trail's 10). Michael (2026-11-14): "hunched, odd arms... just not quite
natural".

Down-the-line and face-on photos of tour players at address show instead:
a hinge from the hips with a flat back, the trunk 35-40 deg forward with a
driver and a few degrees more with an iron, the seat out over the heels;
the arms hanging from the shoulders (the hands just outside a line down
from them); the lead arm nearly straight and the trail elbow a little
softer, pointing at the trail hip; the knees flexed 20-25 deg; the head in
line with the spine, the chin off the chest, the eyes down at the ball;
the trail shoulder a little lower (side bend away from the target).

The club and both hands stay exactly where they are (so the grip, the
strike and the swing's measurements against the club head don't change);
the body is solved round them as putt_posture does for the putter: the
hips' tilt, an even bend and side bend through the spine and where the
hips sit, with the legs and arms reaching their feet and hands by IK and
the elbows swivelled (anatomy.fit_arm) to keep the wrists in range. The
neck and head then turn the eyes to the ball. Marks the .glb
(extras.swing_posture).
"""

import math

import numpy as np

import anatomy
import collide
import pose

# Per address: (club, trunk lean hips to neck, unused, hands out past the
# shoulders (m), knee flex). Degrees unless noted.
TARGETS = {
    "ref_address": ("Driver", 37.0, 0.0, 0.08, 24.0),
    "ref_address_iron": ("Iron", 41.0, 0.0, 0.06, 26.0),
}
# The spine's bones and how far each leans from the trunk's line: the low
# back a little more upright (its natural curve), the chest on the line.
SPINE = (("pelvis", "spine_01"), ("spine_01", "spine_02"), ("spine_02", "spine_03"), ("spine_03", "neck_01"))
SPINE_SHAPE = (-12.0, -6.0, -3.0, 2.0)
MOVED = ("pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head")
LEAD_ELBOW = 6.0  # nearly straight
TRAIL_ELBOW = 14.0  # a little softer
ELBOW_WEIGHT = 2.0
FLAT_MAX = 8.0  # degrees the club (and hands) may be laid flatter about the sole
FLAT_COST = 0.02
DF_MAX = 0.10  # metres the feet may move back from the ball (a longer reach needs room)
HIPS_BEHIND = 0.14  # metres the hip joints sit behind the ankles
HANDS_GAP = 0.12  # metres from the front of the thighs to the hands, at least
THIGH_HALF = 0.075  # the thigh's half depth in front of its bone line
SIDE_BEND = -8.0  # the spine tilted away from the target (trail shoulder low)
NECK_FLEX = 12.0  # the neck's own bend past the spine before the eyes are aimed
NECK_SHARE = 0.35  # of the eyes' turn to the ball taken by the neck, the rest by the head
EYE = np.array([0.0, 0.09, -0.1])  # eyes from the head joint, rest frame


def _knee(rig, P, s):
    i = rig.index
    a = P[i[f"calf_{s}"]] - P[i[f"thigh_{s}"]]
    b = P[i[f"foot_{s}"]] - P[i[f"calf_{s}"]]
    return math.degrees(math.acos(np.clip(np.dot(pose.unit(a), pose.unit(b)), -1, 1)))


def _lean(P, i, a, b):
    v = pose.unit(P[i[b]] - P[i[a]])
    return math.degrees(math.atan2(-v[2], v[1]))


def solve(glb, rig, ref):
    """The new (local rotations, root) for one full-swing address."""
    from mocap_swing import club_head_verts, knee_pole, reach_pole

    club, lean_want, tilt_want, hang, knee_want = TARGETS[ref]
    i = rig.index
    local0, root0 = rig.sample(glb, ref)
    R0, P0 = rig.world(local0, root0)
    _, rest = rig.world([np.eye(3)] * len(rig.names), rig.offsets[0])
    cj = i["club"]
    verts = club_head_verts(glb, club)
    head_verts = (R0[cj] @ (verts - rest[cj]).T).T + P0[cj]
    ball = np.array([head_verts.mean(axis=0)[0], 0.02, head_verts.mean(axis=0)[2]])
    hands = {s: (R0[i[f"hand_{s}"]].copy(), P0[i[f"hand_{s}"]].copy()) for s in "lr"}
    sole = np.array([head_verts.mean(axis=0)[0], head_verts[:, 1].min(), head_verts.mean(axis=0)[2]])
    # Flatter: the club and both hands turned together about the sole, so
    # the hands come down (a tour address hangs them lower than the poser's).
    flat_axis = np.array([1.0, 0.0, 0.0])
    if (pose.rot(flat_axis, 1.0) @ (hands["l"][1] - sole))[1] > (hands["l"][1] - sole)[1]:
        flat_axis = -flat_axis

    def grip_at(flat):
        q = pose.rot(flat_axis, flat)
        return {s: (q @ hands[s][0], sole + q @ (hands[s][1] - sole)) for s in "lr"}, q @ R0[cj]
    fwd_axis = np.array([-1.0, 0.0, 0.0])  # turning about -x tips +y towards -z
    side_axis = np.array([0.0, 0.0, -1.0])  # about -z tips +y towards +x (his right)
    pel = i["pelvis"]
    guard = collide.Guard(glb)

    up = np.array([0.0, 1.0, 0.0])
    lateral = np.array([1.0, 0.0, 0.0])

    def seg_dir(lean, side):
        return pose.rot(side_axis, side) @ pose.rot(fwd_axis, lean) @ up

    def build(x):
        lean, side, df, dy, dz, flat = x  # df: the feet (and body) nearer the ball (-) or further (+)
        hx, club_r = grip_at(flat)
        root = np.array(root0, dtype=float) + [0.0, dy, dz + df]
        R = [m.copy() for m in R0]
        # The back straight from the hips: each spine bone aimed along the
        # trunk's line (the lower ones a little more upright, the low back's
        # natural curve), square to the target line.
        for (a, b), off in zip(SPINE, SPINE_SHAPE):
            d0 = rest[i[b]] - rest[i[a]]
            R[i[a]] = pose.aim(d0, lateral, seg_dir(lean + off, side * (1.0 if a != "pelvis" else 0.5)), lateral)
        R[i["neck_01"]] = pose.aim(rest[i["head"]] - rest[i["neck_01"]], lateral, seg_dir(lean + NECK_FLEX, side), lateral)
        R[i["head"]] = R[i["neck_01"]].copy()
        # Bones hanging off the spine keep their address pose relative to
        # their parents (clavicles, legs before IK).
        loc0 = local0
        for j, p in enumerate(rig.parents):
            if rig.names[j] in MOVED or p < 0:
                continue
            R[j] = R[p] @ loc0[j]
        _, P = rig.world(rig.locals(R), root)
        R = list(R)
        for s in "lr":
            foot = R0[i[f"foot_{s}"]]
            reach_pole(rig, R, list(P), f"thigh_{s}", f"calf_{s}", f"foot_{s}", P0[i[f"foot_{s}"]] + [0.0, 0.0, df], knee_pole(rig, R))
            R[i[f"foot_{s}"]] = foot
        R, P = rig.world(rig.locals(R), root)
        R = list(R)
        for s in "lr":
            sh = P[i[f"upperarm_{s}"]]
            # Elbows down towards the hips: the trail elbow at the trail
            # hip, the lead one a little out.
            out = R[i["spine_03"]] @ np.array([-1.0 if s == "l" else 1.0, 0.0, 0.0])
            pole = pose.unit(P[pel] - sh) + (0.6 if s == "l" else 0.3) * out
            reach_pole(rig, R, list(P), f"upperarm_{s}", f"lowerarm_{s}", f"hand_{s}", hx[s][1], pole)
        R, P = rig.world(rig.locals(R), root)
        R = list(R)
        for s in "lr":
            h = i[f"hand_{s}"]
            turn = hx[s][0] @ R[h].T
            for k in anatomy.descendants(rig, h):
                R[k] = turn @ R[k]
        R[cj] = club_r
        R, P = rig.world(rig.locals(R), root)
        return R, P, root, hx

    def cost(x, report=False):
        R, P, root, hx = build(x)
        side = x[1]
        hands_mid = (hx["l"][1] + hx["r"][1]) / 2
        sh_mid = (P[i["upperarm_l"]] + P[i["upperarm_r"]]) / 2
        lean = _lean(P, i, "pelvis", "neck_01")
        pel_tilt = math.degrees(math.atan2(-(R[pel] @ [0, 1, 0])[2], (R[pel] @ [0, 1, 0])[1]))
        ankles = (P0[i["foot_l"]] + P0[i["foot_r"]]) / 2
        hips_behind0 = P0[pel][2] - ankles[2]
        terms = {
            "lean": (lean - lean_want) ** 2,
            "balance": ((P[pel][2] - ankles[2] - hips_behind0) * 100) ** 2 * 0.3,
            "hang": ((sh_mid[2] - hands_mid[2] - hang) * 100) ** 2,
            "knees": sum((_knee(rig, P, s) - knee_want) ** 2 for s in "lr") * 0.5,
            "side": (side - SIDE_BEND) ** 2 * 0.05,
            "flat": x[5] ** 2 * FLAT_COST,
            "reach": 0.0, "wrists": 0.0, "clear": 0.0,
        }
        R = list(R)
        body = guard.frame(R, root)
        for s in "lr":
            anatomy.fit_arm(rig, R, P, s, body=body)
            Rn, _ = rig.world(rig.locals(R), root)
            terms["clear"] += anatomy.CLEAR_COST * (100.0 * guard.frame(Rn, root).arm_depth(s)) ** 2
            a = anatomy.arm_angles(rig, s, R[i[f"upperarm_{s}"]], R[i[f"lowerarm_{s}"]], R[i[f"hand_{s}"]])
            terms["reach"] += (a["elbow_flex"] - (LEAD_ELBOW if s == "l" else TRAIL_ELBOW)) ** 2 * ELBOW_WEIGHT
            for k in ("wrist_flex", "wrist_dev", "forearm_roll"):
                lo, hi = anatomy.limit_of(k)
                terms["wrists"] += max(0.0, lo + 5 - a[k], a[k] - hi + 5) ** 2
            terms["reach"] += (np.linalg.norm(P[i[f"hand_{s}"]] - hx[s][1]) * 1000) ** 2
        if report:
            return dict(terms, lean_deg=lean, pelvis_tilt=pel_tilt)
        return sum(terms.values())

    # Structured search, not a free fit (a free fit traded straight legs
    # and the hips far back for the arms): the trunk's lean and side bend
    # are set; for each place of the hips (how far back) and how flat the
    # club lies, the hips drop until the knees flex knee_want; the pair
    # that best lets the arms hang straight wins.
    lean, side = lean_want, SIDE_BEND

    def at(df, dz, flat):
        lo, hi = -0.15, 0.08
        for _ in range(18):
            dy = (lo + hi) / 2
            _, P, _, _ = build([lean, side, df, dy, dz, flat])
            if sum(_knee(rig, P, s) for s in "lr") / 2 > knee_want:
                lo = dy
            else:
                hi = dy
        return np.array([lean, side, df, (lo + hi) / 2, dz, flat])

    def score(x):
        R, P, root, hx = build(x)
        sh_mid = (P[i["upperarm_l"]] + P[i["upperarm_r"]]) / 2
        hands_mid = (hx["l"][1] + hx["r"][1]) / 2
        out = ((sh_mid[2] - hands_mid[2] - hang) * 100) ** 2 + x[5] ** 2 * FLAT_COST
        # A hand's width and more between the hands and the thighs.
        thigh = max((P[i[f"thigh_{s}"]][2] + P[i[f"calf_{s}"]][2]) / 2 for s in "lr")
        gap = thigh - THIGH_HALF - hands_mid[2]
        out += (max(0.0, HANDS_GAP - gap) * 100) ** 2 * 2.0
        # The seat out over the heels.
        ankles_z = (P[i["foot_l"]][2] + P[i["foot_r"]][2]) / 2
        out += ((P[pel][2] - ankles_z - HIPS_BEHIND) * 100) ** 2 * 0.5
        for s in "lr":
            a = anatomy.arm_angles(rig, s, R[i[f"upperarm_{s}"]], R[i[f"lowerarm_{s}"]], R[i[f"hand_{s}"]])
            out += (a["elbow_flex"] - (LEAD_ELBOW if s == "l" else TRAIL_ELBOW)) ** 2 * ELBOW_WEIGHT
            out += (np.linalg.norm(P[i[f"hand_{s}"]] - hx[s][1]) * 1000) ** 2
        return out

    best = None
    for df in np.arange(-0.04, DF_MAX + 0.001, 0.02):
        for dz in np.arange(-0.04, 0.201, 0.02):
            for flat in np.arange(0.0, FLAT_MAX + 0.01, 1.0):
                x = at(df, dz, flat)
                sc = score(x)
                if best is None or sc < best[0]:
                    best = (sc, x)
    res = type("Res", (), {"x": best[1]})
    R, P, root, _ = build(res.x)
    body = guard.frame(R, root)
    for s in "lr":
        anatomy.fit_arm(rig, R, P, s, body=body)
    R, P = rig.world(rig.locals(R), root)
    # Eyes down at the ball: mostly the head nodding, a little the neck.
    R = list(R)
    hd = i["head"]
    eyes = P[hd] + R[hd] @ EYE
    look = R[hd] @ pose.unit(np.array([0.0, -0.35, -1.0]))
    turn = anatomy.between(look, pose.unit(ball - eyes))
    for n, share in (("neck_01", NECK_SHARE), ("head", 1.0 - NECK_SHARE)):
        t = pose.slerp(np.eye(3), turn, share)
        for k in anatomy.descendants(rig, i[n]):
            R[k] = t @ R[k]
    info = {k: round(float(v), 2) for k, v in cost(res.x, True).items()}
    info["params"] = np.round(res.x, 3).tolist()
    return rig.locals(R), root, info


def fit(glb, rig):
    """Re-poses ref_address and ref_address_iron. Returns False if already done."""
    from mocap_swing import write_clip

    cj = rig.index["club"]
    club_node = glb.doc["nodes"][rig.joints[cj]]
    if club_node.get("extras", {}).get("swing_posture"):
        return False
    for ref in TARGETS:
        if not glb.animation(ref):
            continue
        local, root, info = solve(glb, rig, ref)
        write_clip(glb, rig, ref, np.zeros(1, np.float32), [local], np.array([root], np.float32), filtered=False)
        print(f"{ref}:", info)
    club_node.setdefault("extras", {})["swing_posture"] = 1
    return True
