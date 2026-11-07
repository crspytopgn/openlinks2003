"""Checks the free golfer's clips against the human body's joint ranges.

Every pose a clip keys is measured joint by joint (spine segments, neck,
clavicles, shoulders' twist, elbows, forearm roll, wrists, hips, knees,
ankles) and compared with the ranges a healthy adult reaches, from the
clinical range-of-motion tables (AAOS, Norkin and White). A joint outside
its range by more than a few degrees is reported with the clip, the time
and the angle, so a bake that bends a body the way no body bends fails
here before anyone sees it.

The rig's bones all rest with the identity rotation, the golfer facing -z
with +y up, so each local rotation is read in the body's own axes: about x
is a forward or back bend, about z a side bend, and about the bone's own
length a twist. Measured from the bind pose, which stands with the arms
hanging slightly forward and the palms facing in (thumbs forward): the
forearm roll and wrist angles are zero there.

    python3 tools/golfer/anatomy.py [game/assets/golfer/free_golfer.glb] [--clip read] [--all]
"""

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_edit  # noqa: E402
import pose  # noqa: E402

# (low, high) degrees. Spine segments split the published lumbar and
# thoracic ranges over the rig's three spine joints.
RANGES = {
    # forward bend + / backward -, side bend either way, twist either way
    "lumbar_flex": (-15.0, 35.0), "lumbar_side": 15.0, "lumbar_twist": 8.0,
    "mid_flex": (-12.0, 30.0), "mid_side": 15.0, "mid_twist": 20.0,
    "upper_flex": (-12.0, 25.0), "upper_side": 12.0, "upper_twist": 20.0,
    # neck + head together, against the chest
    "neck_flex": (-60.0, 50.0), "neck_side": 40.0, "neck_twist": 75.0,
    "elbow_flex": (0.0, 150.0), "elbow_hyper": 8.0,
    # forearm roll from the palms-in rest: supination +, pronation -
    "forearm_roll": (-85.0, 90.0),
    "wrist_flex": (-70.0, 75.0),  # palm-ward +, back of the hand -
    "wrist_dev": (-35.0, 20.0),  # thumb-ward (radial) +, little finger -
    "wrist_twist": 25.0,  # skinned at the wrist alone: more wrings it
    "hip_flex": (-20.0, 125.0), "hip_abd": (-25.0, 45.0), "hip_twist": 45.0,
    "knee_flex": (-5.0, 150.0), "knee_side": 10.0, "knee_twist": 35.0,
    "ankle_flex": (-50.0, 35.0),  # toes down + (plantar), up - (dorsi)
    "ankle_side": 30.0,
    "clav_raise": (-10.0, 40.0), "clav_forward": 30.0,
}
SLACK = 3.0  # degrees past a range before it is reported

X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])


class Rig:
    def __init__(self, glb):
        doc = glb.doc
        self.joints = doc["skins"][0]["joints"]
        nodes = doc["nodes"]
        self.names = [nodes[j]["name"] for j in self.joints]
        self.index = {n: k for k, n in enumerate(self.names)}
        parent_of = {}
        for i, n in enumerate(nodes):
            for c in n.get("children", []):
                parent_of[c] = i
        pos = {j: k for k, j in enumerate(self.joints)}
        self.parents = [pos.get(parent_of.get(j), -1) for j in self.joints]
        self.offsets = [np.array(nodes[j].get("translation", [0, 0, 0]), dtype=float) for j in self.joints]
        self.rest = self.world([np.eye(3)] * len(self.joints), self.offsets[0])[1]

    def world(self, local, root):
        rots, poss = [], []
        for j, p in enumerate(self.parents):
            if p < 0:
                rots.append(local[j])
                poss.append(np.array(root, dtype=float))
            else:
                rots.append(rots[p] @ local[j])
                poss.append(poss[p] + rots[p] @ self.offsets[j])
        return rots, poss

    def rest_dir(self, a, b):
        return pose.unit(self.rest[self.index[b]] - self.rest[self.index[a]])


def clip_frames(glb, rig, name):
    """(times, local rotations per time, root per time) of every key."""
    anim = glb.animation(name)
    pos = {j: k for k, j in enumerate(rig.joints)}
    chans = []
    times = set()
    for ch in anim["channels"]:
        s = anim["samplers"][ch["sampler"]]
        t, v = glb.read(s["input"]), glb.read(s["output"])
        chans.append((pos[ch["target"]["node"]], ch["target"]["path"], np.asarray(t), np.asarray(v, dtype=float)))
        times.update(np.round(t, 4).tolist())
    out = []
    for t in sorted(times):
        local = [np.eye(3) for _ in rig.joints]
        root = rig.offsets[0].copy()
        for j, path, ts, vs in chans:
            k = int(np.clip(np.searchsorted(ts, t - 1e-5), 0, len(ts) - 1))
            if path == "rotation":
                q = vs[k]
                local[j] = pose.matrix(q / np.linalg.norm(q))
            elif path == "translation" and j == 0:
                root = vs[k]
        out.append((t, local, root))
    return out


def swing_twist(m, axis):
    """Twist degrees about axis and the swing rotation left after it."""
    tw = pose.twist_angle(m, axis)
    swing = m @ pose.rot(axis, -tw)
    return tw, swing


def bend_parts(swing, along, forward, side):
    """A swing's tilt of `along` toward `forward` and toward `side`, degrees."""
    d = swing @ along
    return (math.degrees(math.atan2(np.dot(d, forward), np.dot(d, along))),
            math.degrees(math.atan2(np.dot(d, side), np.dot(d, along))))


def wrap(a):
    return (a + 180.0) % 360.0 - 180.0


class ArmRest:
    """One arm's rest directions, for arm_angles."""

    def __init__(self, rig, s):
        i = rig.index
        r = rig.world([np.eye(3)] * len(rig.parents), rig.offsets[0])[1]

        def d(a, b):
            return pose.unit(r[i[b]] - r[i[a]])

        self.up = d(f"upperarm_{s}", f"lowerarm_{s}")
        self.fore = d(f"lowerarm_{s}", f"hand_{s}")
        self.hinge = pose.unit(np.cross(self.up, self.fore))
        self.hand = d(f"hand_{s}", f"middle_01_{s}")
        across = r[i[f"index_01_{s}"]] - r[i[f"pinky_01_{s}"]]
        self.across = pose.unit(across - self.hand * np.dot(across, self.hand))
        palm = pose.unit(np.cross(self.hand, self.across))
        curl = r[i[f"middle_03_{s}"]] - r[i[f"middle_01_{s}"]]
        self.palm = palm if np.dot(curl, palm) > 0 else -palm
        self.sign = 1.0 if s == "l" else -1.0  # + forearm roll = supination


_ARM_REST = {}


def arm_angles(rig, s, upper, lower, hand):
    """Elbow, forearm roll and wrist angles from the three bones' world
    rotations: {elbow_flex, elbow_hyper, forearm_roll, wrist_twist,
    wrist_flex, wrist_dev}."""
    key = (len(rig.parents), s)
    if key not in _ARM_REST:
        _ARM_REST[key] = ArmRest(rig, s)
    a = _ARM_REST[key]
    m = {}
    up, fo = upper @ a.up, lower @ a.fore
    m["elbow_flex"] = math.degrees(math.acos(np.clip(np.dot(up, fo), -1, 1)))
    # Folding the wrong way round the hinge is hyperextension.
    side = np.dot(np.cross(up, fo), upper @ a.hinge)
    m["elbow_hyper"] = math.degrees(math.asin(np.clip(-side, -1, 1))) if side < 0 else 0.0
    # Forearm roll: the radius turning round the ulna. The rig has no twist
    # bone, so the roll is the forearm's twist against the upper arm plus
    # whatever twist the hand carries against the forearm; the hand's own
    # share is skinned at the wrist alone and wrings it past a little.
    tw_fore = pose.twist_angle(upper.T @ lower, a.fore)
    hl = lower.T @ hand
    tw_hand = pose.twist_angle(hl, a.fore)
    m["forearm_roll"] = wrap(a.sign * (tw_fore + tw_hand))
    m["wrist_twist"] = wrap(tw_hand)
    # Wrist bend in the forearm's frame rolled with the hand: toward the
    # palm (flexion) and toward the thumb (radial deviation).
    d = pose.rot(a.fore, -tw_hand) @ hl @ a.hand
    m["wrist_flex"] = math.degrees(math.atan2(np.dot(d, a.palm), np.dot(d, a.hand)))
    m["wrist_dev"] = math.degrees(math.asin(np.clip(np.dot(d, a.across), -1, 1)))
    return m


def measure(rig, local, root):
    """Every joint's angles for one pose: {name: degrees}."""
    i = rig.index
    rots, poss = rig.world(local, root)
    m = {}
    fwd = -Z
    # Spine: each segment's local rotation in the parent's (rest = body) axes.
    for joint, key in (("spine_01", "lumbar"), ("spine_02", "mid"), ("spine_03", "upper")):
        tw, sw = swing_twist(local[i[joint]], Y)
        flex, side = bend_parts(sw, Y, fwd, X)
        m[f"{key}_flex"], m[f"{key}_side"], m[f"{key}_twist"] = flex, side, tw
    neck = local[i["neck_01"]] @ local[i["head"]]
    tw, sw = swing_twist(neck, Y)
    flex, side = bend_parts(sw, Y, fwd, X)
    m["neck_flex"], m["neck_side"], m["neck_twist"] = flex, side, tw
    for s, out in (("l", -X), ("r", X)):
        # Clavicle: the shoulder raised or carried forward.
        c = rig.rest_dir(f"clavicle_{s}", f"upperarm_{s}")
        d = local[i[f"clavicle_{s}"]] @ c
        m[f"clav_raise_{s}"] = math.degrees(math.asin(np.clip(d[1], -1, 1))) - math.degrees(math.asin(np.clip(c[1], -1, 1)))
        m[f"clav_forward_{s}"] = math.degrees(math.atan2(np.dot(d, fwd), np.dot(d, out))) - \
            math.degrees(math.atan2(np.dot(c, fwd), np.dot(c, out)))
        m.update({f"{k}_{s}": v for k, v in arm_angles(
            rig, s, rots[i[f"upperarm_{s}"]], rots[i[f"lowerarm_{s}"]], rots[i[f"hand_{s}"]]).items()})
        # Hip: the thigh against the pelvis (rest = body axes).
        th_rest = rig.rest_dir(f"thigh_{s}", f"calf_{s}")
        tw, sw = swing_twist(local[i[f"thigh_{s}"]], th_rest)
        d = sw @ th_rest
        m[f"hip_flex_{s}"] = math.degrees(math.atan2(np.dot(d, fwd), -d[1])) - \
            math.degrees(math.atan2(np.dot(th_rest, fwd), -th_rest[1]))
        m[f"hip_abd_{s}"] = math.degrees(math.asin(np.clip(np.dot(d, out), -1, 1))) - \
            math.degrees(math.asin(np.clip(np.dot(th_rest, out), -1, 1)))
        m[f"hip_twist_{s}"] = wrap(tw)
        # Knee: the shin against the thigh.
        sh_rest = rig.rest_dir(f"calf_{s}", f"foot_{s}")
        tw, sw = swing_twist(local[i[f"calf_{s}"]], sh_rest)
        d = sw @ sh_rest
        # The shin swings back (+z) for a bend.
        m[f"knee_flex_{s}"] = math.degrees(math.atan2(np.dot(d, -fwd), -d[1])) - \
            math.degrees(math.atan2(np.dot(sh_rest, -fwd), -sh_rest[1]))
        m[f"knee_side_{s}"] = math.degrees(math.asin(np.clip(np.dot(d, out), -1, 1))) - \
            math.degrees(math.asin(np.clip(np.dot(sh_rest, out), -1, 1)))
        m[f"knee_twist_{s}"] = wrap(tw)
        # Ankle: the foot against the shin.
        ft_rest = rig.rest_dir(f"foot_{s}", f"ball_{s}")
        d = local[i[f"foot_{s}"]] @ ft_rest
        m[f"ankle_flex_{s}"] = -(math.degrees(math.atan2(d[1], -d[2])) - math.degrees(math.atan2(ft_rest[1], -ft_rest[2])))
        m[f"ankle_side_{s}"] = math.degrees(math.atan2(d[0], -d[2])) - math.degrees(math.atan2(ft_rest[0], -ft_rest[2]))
    return m


# ---- fitting the arms ---------------------------------------------------

SWIVELS = np.radians(np.arange(-90.0, 91.0, 3.0))
HAND_TWIST_SHARE = 0.35  # of the roll left at the wrist, at most HAND_TWIST
HAND_TWIST = 18.0
SWIVEL_COST = 0.004  # per degree squared of swivel from the given elbow
STEADY_COST = 0.02  # per degree squared of change from the last frame's
TORSO_CLEAR = 0.16  # elbow to the spine's line, metres


def _excess(v, lim):
    return max(0.0, lim[0] - v, v - lim[1])


def _seg_dist(p, a, b):
    ab = b - a
    t = float(np.clip(np.dot(p - a, ab) / max(np.dot(ab, ab), 1e-12), 0.0, 1.0))
    return float(np.linalg.norm(p - (a + ab * t)))


def unhinge(rig, rots, s):
    """An elbow bent the wrong way round its hinge (IK that turns the arm
    by the shortest way leaves the upper arm's own twist anywhere): the
    upper arm turned about its length so the hinge matches the bend, the
    forearm and hand staying where they are."""
    i = rig.index
    a = _ARM_REST.setdefault((len(rig.parents), s), ArmRest(rig, s))
    iu = i[f"upperarm_{s}"]
    U, L = rots[iu], rots[i[f"lowerarm_{s}"]]
    up, fo = U @ a.up, L @ a.fore
    bend = np.cross(up, fo)
    if np.linalg.norm(bend) < math.sin(math.radians(10.0)):
        return
    hinge = U @ a.hinge
    # Turn about the upper arm's length taking the hinge onto the bend.
    h = pose.unit(hinge - up * np.dot(hinge, up))
    b = pose.unit(bend - up * np.dot(bend, up))
    ang = math.degrees(math.atan2(np.dot(np.cross(h, b), up), np.dot(h, b)))
    if np.dot(hinge, bend) >= -math.sin(math.radians(8.0)) * np.linalg.norm(bend):
        return  # bends the right way; leave the actor's shoulder turn
    rots[iu] = pose.rot(up, ang) @ U


CLEAR_COST = 40.0  # per cm squared of arm inside the torso (collide.Guard)


def fit_arm(rig, rots, poss, s, last=None, body=None):
    """Turns the arm round the shoulder-to-wrist line (the elbow's swivel)
    so the wrist stays inside its range, then rolls the forearm so the hand
    keeps at most HAND_TWIST of twist. The hand's world pose, and so the
    club and the grip, are left exactly as they were. With `body` (a
    collide.Guard frame of this pose) each swivel is tested against the
    real torso, so the upper arm can't pass into the chest; without it
    the elbow is only kept TORSO_CLEAR off the spine's line. Returns the
    swivel, in degrees, for the next frame's `last`."""
    i = rig.index
    iu, il, ih = i[f"upperarm_{s}"], i[f"lowerarm_{s}"], i[f"hand_{s}"]
    S, W, E = poss[iu], poss[ih], poss[il]
    unhinge(rig, rots, s)
    axis = pose.unit(W - S)
    U, L, H = rots[iu], rots[il], rots[ih]
    spine_a, spine_b = poss[i["pelvis"]], poss[i["neck_01"]]
    lim = {k: limit_of(k) for k in ("wrist_flex", "wrist_dev", "forearm_roll")}
    best, best_cost = 0.0, None
    for phi in SWIVELS:
        deg = math.degrees(phi)
        R = pose.rot(axis, deg)
        a = arm_angles(rig, s, R @ U, R @ L, H)
        cost = sum(_excess(a[k], lim[k]) ** 2 for k in lim)
        cost += SWIVEL_COST * deg * deg
        if last is not None:
            cost += STEADY_COST * (deg - last) ** 2
        if body is not None:
            pivot = body.P[i[f"upperarm_{s}"]]
            cost += CLEAR_COST * (100.0 * body.arm_depth(s, R, pivot)) ** 2
        else:
            clear = _seg_dist(S + R @ (E - S), spine_a, spine_b)
            cost += (max(0.0, TORSO_CLEAR - clear) * 400.0) ** 2
        if best_cost is None or cost < best_cost:
            best, best_cost = deg, cost
    R = pose.rot(axis, best)
    rots[iu], rots[il] = R @ U, R @ L
    rest = _ARM_REST[(len(rig.parents), s)]
    tw = pose.twist_angle(rots[il].T @ H, rest.fore)
    keep = float(np.clip(tw * HAND_TWIST_SHARE, -HAND_TWIST, HAND_TWIST))
    rots[il] = rots[il] @ pose.rot(rest.fore, tw - keep)
    return best


def between(a, b):
    """The smallest rotation taking direction a to direction b."""
    a, b = pose.unit(a), pose.unit(b)
    axis = np.cross(a, b)
    s, c = np.linalg.norm(axis), float(np.dot(a, b))
    if s < 1e-9:
        return np.eye(3)
    return pose.rot(axis, math.degrees(math.atan2(s, c)))


def descendants(rig, j):
    out, stack = [], [j]
    while stack:
        k = stack.pop()
        out.append(k)
        stack.extend(c for c, p in enumerate(rig.parents) if p == k)
    return out


def clamp_wrist(rig, rots, s):
    """For a hand that holds nothing fixed (a club carried in the left
    hand, a fist, a hand on the head): the forearm's roll clamped into its
    range and the wrist's bend into its own, the hand's children
    following the hand."""
    i = rig.index
    a = _ARM_REST[(len(rig.parents), s)]
    il, ih = i[f"lowerarm_{s}"], i[f"hand_{s}"]
    U, L, H0 = rots[i[f"upperarm_{s}"]], rots[il], rots[ih]
    hl = L.T @ H0
    tw_h = pose.twist_angle(hl, a.fore)
    tw_f = pose.twist_angle(U.T @ L, a.fore)
    bent = pose.rot(a.fore, -tw_h) @ hl
    roll = wrap(a.sign * (tw_f + tw_h))
    keep = float(np.clip(roll, *limit_of("forearm_roll")))
    total = tw_f + tw_h - a.sign * (roll - keep)
    hand_tw = float(np.clip(total - tw_f, -HAND_TWIST, HAND_TWIST))
    L2 = L @ pose.rot(a.fore, total - hand_tw - tw_f)
    d = bent @ a.hand
    flex = math.degrees(math.atan2(np.dot(d, a.palm), np.dot(d, a.hand)))
    dev = math.degrees(math.asin(np.clip(np.dot(d, a.across), -1, 1)))
    f2 = math.radians(float(np.clip(flex, *limit_of("wrist_flex"))))
    d2 = math.radians(float(np.clip(dev, *limit_of("wrist_dev"))))
    want = a.hand * math.cos(f2) + a.palm * math.sin(f2)
    want = pose.unit(pose.unit(want) * math.cos(d2) + a.across * math.sin(d2))
    bent = between(d, want) @ bent
    H = L2 @ pose.rot(a.fore, hand_tw) @ bent
    turn = H @ H0.T
    rots[il] = L2
    for k in descendants(rig, ih):
        rots[k] = turn @ rots[k]


SPINE_TWIST = (0.15, 0.4, 0.45)  # lumbar, mid, upper share of the trunk's twist


def even_spine(rig, local):
    """Spreads the trunk's twist over the spine as a body turns: the lumbar
    joints barely turn (SPINE_TWIST), the chest ends exactly where it
    was."""
    i = rig.index
    ids = [i["spine_01"], i["spine_02"], i["spine_03"]]
    total = local[ids[0]] @ local[ids[1]] @ local[ids[2]]
    tws = [pose.twist_angle(local[k], Y) for k in ids]
    t = sum(tws)
    local = list(local)
    for k, tw, share in zip(ids[:2], tws[:2], SPINE_TWIST[:2]):
        local[k] = local[k] @ pose.rot(Y, -tw) @ pose.rot(Y, t * share)
    local[ids[2]] = (local[ids[0]] @ local[ids[1]]).T @ total
    return local


def spin_carry(rig, rots, poss, shaft, last=None):
    """A club only carried in the left hand: the hand spun round the
    shaft's line (through the wrist), so the club points the same way, to
    the turn that keeps the forearm's roll and the wrist in their ranges.
    Returns the spin, degrees, for the next frame's `last`."""
    i = rig.index
    ih = i["hand_l"]
    U, L, H = rots[i["upperarm_l"]], rots[i["lowerarm_l"]], rots[ih]
    lim = {k: limit_of(k) for k in ("wrist_flex", "wrist_dev", "forearm_roll")}
    best, best_cost = 0.0, None
    for deg in range(-180, 180, 6):
        a = arm_angles(rig, "l", U, L, pose.rot(shaft, deg) @ H)
        cost = sum(_excess(a[k], lim[k]) ** 2 for k in lim) + 0.002 * deg * deg
        if last is not None:
            cost += 0.01 * wrap(deg - last) ** 2
        if best_cost is None or cost < best_cost:
            best, best_cost = float(deg), cost
    turn = pose.rot(shaft, best)
    for k in descendants(rig, ih):
        rots[k] = turn @ rots[k]
    return best


def fit_arms(rig, frames, free=(), club_dir=None, guard=None):
    """fit_arm on both arms through a clip's poses (lists of local
    rotations, and roots), in order so the swivel moves smoothly; the
    hands in `free` ("l", "r") hold nothing fixed and have their wrists
    clamped too, a club carried in a free left hand first spun round its
    shaft (spin_carry; club_dir is the shaft in the club joint's frame). The spine's twist is spread first (even_spine).
    `guard` (collide.Guard) keeps the upper arms out of the chest."""
    last = {"l": None, "r": None, "spin": None}
    out = []
    for local, root in frames:
        rots, poss = rig.world(even_spine(rig, local), root)
        rots = list(rots)
        if "l" in free and club_dir is not None:
            last["spin"] = spin_carry(rig, rots, poss, rots[rig.index["club"]] @ club_dir, last["spin"])
        body = guard.frame(rots, root) if guard is not None else None
        for s in ("l", "r"):
            last[s] = fit_arm(rig, rots, poss, s, last[s], body)
            if s in free:
                clamp_wrist(rig, rots, s)
        out.append([rots[j] if p < 0 else rots[p].T @ rots[j] for j, p in enumerate(rig.parents)])
    return out


def limit_of(key):
    base = key[:-2] if key[-2:] in ("_l", "_r") else key
    r = RANGES.get(base)
    if r is None:
        return None
    return (-r, r) if isinstance(r, float) else r


def audit(glb, rig, clips, slack=SLACK):
    """{clip: {joint: (worst excess, time, angle)}} past their ranges."""
    report = {}
    for name in clips:
        worst = {}
        for t, local, root in clip_frames(glb, rig, name):
            for key, a in measure(rig, local, root).items():
                lim = limit_of(key)
                if lim is None:
                    continue
                over = max(lim[0] - a, a - lim[1])
                if over > slack and over > worst.get(key, (0.0,))[0]:
                    worst[key] = (over, t, a)
        report[name] = worst
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("glb", nargs="?", default=os.path.join(os.path.dirname(__file__), "../../game/assets/golfer/free_golfer.glb"))
    ap.add_argument("--clip", action="append")
    ap.add_argument("--dump", help="print every angle of this clip at --at seconds")
    ap.add_argument("--at", type=float, default=0.0)
    args = ap.parse_args()
    glb = glb_edit.Glb(args.glb)
    rig = Rig(glb)
    if args.dump:
        frames = clip_frames(glb, rig, args.dump)
        t, local, root = min(frames, key=lambda f: abs(f[0] - args.at))
        for k, v in measure(rig, local, root).items():
            lim = limit_of(k)
            flag = "" if lim is None or lim[0] - SLACK <= v <= lim[1] + SLACK else "  <-- outside %s" % (lim,)
            print(f"{args.dump}@{t:.2f} {k:16s} {v:7.1f}{flag}")
        return 0
    clips = args.clip or [a["name"] for a in glb.doc["animations"] if not a["name"].startswith("ref_")]
    bad = 0
    for name, worst in audit(glb, rig, clips).items():
        if not worst:
            print(f"{name}: ok")
            continue
        bad += 1
        print(f"{name}:")
        for key, (over, t, a) in sorted(worst.items(), key=lambda kv: -kv[1][0]):
            print(f"  {key:16s} {a:7.1f} deg at {t:5.2f}s  ({over:.0f} past {limit_of(key)})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
