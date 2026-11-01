#!/usr/bin/env python3
"""Gives the free golfer motion-captured animations (address, swing, putt,
walk and reactions) from the CMU Graphics Lab Motion Capture Database.

    python3 tools/golfer/mocap_swing.py [--glb game/assets/golfer/free_golfer.glb] [--cache DIR]

The BVH files (Bruce Hahne's conversion, mirrored on GitHub) are downloaded
into --cache. CMU's terms: "This data is free for use in research and
commercial projects worldwide." Nothing from Links 2003 is used.

Retargeting: each mapped bone turns in the world by the same rotation as the
actor's bone since the address frame, starting from the golfer's own
address pose in the glb (so the clip starts exactly where "address" is).
Then the feet are pinned with two-bone IK to where the actor's feet go
(scaled to the golfer), and the right hand is kept on the grip. The
downswing is retimed to a tour tempo, since the game launches the ball as
the swing clip starts.

Standing clips (walk, reactions) are measured from the actor's T pose
instead: each bone of the golfer's rest pose is first turned onto the
matching T-pose bone. The walk is played in place with the club carried.
"""

import argparse
import math
import os
import sys
import urllib.request

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_edit  # noqa: E402
import clubs  # noqa: E402
import grip  # noqa: E402
import iron  # noqa: E402
import pose  # noqa: E402

BVH_URL = "https://raw.githubusercontent.com/una-dinosauria/cmu-mocap/master/data/{:03d}/{}.bvh"
MOCAP_FPS = 120.0
STEP = 2  # keep every second mocap frame: 60 keys a second

# Golfer bone: the actor's joint whose world rotation it follows.
BONES = {
    "pelvis": "Hips", "spine_01": "LowerBack", "spine_02": "Spine", "spine_03": "Spine1",
    "neck_01": "Neck1", "head": "Head",
    "clavicle_l": "LeftShoulder", "upperarm_l": "LeftArm", "lowerarm_l": "LeftForeArm", "hand_l": "LeftHand",
    "clavicle_r": "RightShoulder", "upperarm_r": "RightArm", "lowerarm_r": "RightForeArm", "hand_r": "RightHand",
    "thigh_l": "LeftUpLeg", "calf_l": "LeftLeg", "foot_l": "LeftFoot", "ball_l": "LeftToeBase",
    "thigh_r": "RightUpLeg", "calf_r": "RightLeg", "foot_r": "RightFoot", "ball_r": "RightToeBase",
}

# Clips: take, the golfer's pose the take starts from, and mocap frames.
# address is the still frame the retarget is measured from; the clip runs
# from start to end, and the time from top to impact is squeezed to
# downswing seconds and start to top to back seconds (left out, they play in
# real time); after impact time runs at follow times real time. hold adds
# seconds of the last frame.
CLIPS = {
    # Address: the actor's own sway over the ball, back and forth so it
    # loops, with a look at the target.
    "address": dict(take="64_01", ref="address", address=150, putt=False, loop=0.3,
                    frames=list(range(150, 30, -1)) + list(range(30, 150)) + list(range(150, 30, -1)),
                    glance=(1.3, 0.4, 0.7, 70.0)),
    "address_putt": dict(take="64_13", ref="address_putt", club="Putter", address=95, putt=True, loop=0.3,
                         frames=(list(range(95, 15, -1)) + list(range(15, 95))) * 2,
                         glance=(0.9, 0.45, 0.8, 75.0)),
    "backswing": dict(take="64_01", ref="address", address=150, start=150, end=262, top=262, impact=327, putt=False),
    "swing": dict(take="64_01", ref="address", address=150, start=262, end=400, top=262, impact=327,
                  downswing=0.30, follow=0.7, hold=2.5, twirl=(0.9, 0.55), putt=False, strike=(0.0, 0.012, -0.755)),
    # The irons: the same takes from the iron's address (iron.py).
    "address_iron": dict(take="64_01", ref="address_iron", address=150, putt=False, loop=0.3,
                         frames=list(range(150, 30, -1)) + list(range(30, 150)) + list(range(150, 30, -1)),
                         glance=(1.3, 0.4, 0.7, 70.0), club="Iron"),
    "backswing_iron": dict(take="64_01", ref="address_iron", club="Iron", address=150, start=150, end=262, top=262, impact=327,
                           putt=False),
    "swing_iron": dict(take="64_01", ref="address_iron", club="Iron", address=150, start=262, end=400, top=262, impact=327,
                       downswing=0.30, follow=0.7, hold=2.5, twirl=(0.9, 0.55), putt=False),
    "putt": dict(take="64_13", ref="address_putt", club="Putter", address=95, start=95, end=330, top=183, impact=249,
                 back=0.45, downswing=0.3, hold=0.8, putt=True),
}


# The actor's hand markers don't record the wrists, so the club would stay
# in line with the forearm and point at the sky at the top. Instead the
# club turns round the swing plane (the plane of the shaft and the target
# line at address): its angle there is the left arm's angle plus a wrist
# hinge that grows with the arm's angle (degrees). In the downswing the
# wrists hold their angle (the lag) until the arm is nearly back down;
# after impact they hinge the other way, up to the finish.
HINGE_BACK = (135.0, 10.0, 115.0)  # most hinge, arm angle where it starts, where it is full
HINGE_DOWN = (135.0, 0.0, 85.0)
HINGE_FOLLOW = (95.0, 15.0, 120.0)
FINISH_LIMIT = -275.0  # club angle at the finish, behind the neck


# ---- BVH ----------------------------------------------------------------

def _axis_rot(axis, deg):
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    if axis == "X":
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    if axis == "Y":
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


class Bvh:
    def __init__(self, path):
        tok = open(path).read().split()
        self.names, self.parents, self.offsets, self.channels = [], [], [], []
        self.ends = {}
        i, stack, cur = 0, [], -1
        while tok[i] != "MOTION":
            t = tok[i]
            if t in ("ROOT", "JOINT"):
                self.names.append(tok[i + 1])
                self.parents.append(stack[-1] if stack else -1)
                cur = len(self.names) - 1
                i += 2
            elif t == "End":  # End Site { OFFSET x y z }
                self.ends[stack[-1]] = np.array([float(x) for x in tok[i + 4:i + 7]])
                i += 8
            elif t == "{":
                stack.append(cur)
                i += 1
            elif t == "}":
                stack.pop()
                i += 1
            elif t == "OFFSET":
                self.offsets.append(np.array([float(x) for x in tok[i + 1:i + 4]]))
                i += 4
            elif t == "CHANNELS":
                n = int(tok[i + 1])
                self.channels.append(tok[i + 2:i + 2 + n])
                i += 2 + n
            else:
                i += 1
        frames = int(tok[i + 2])
        i += 6
        width = sum(len(c) for c in self.channels)
        self.data = np.array(tok[i:i + frames * width], dtype=float).reshape(frames, width)
        self.index = {n: k for k, n in enumerate(self.names)}

    def frame(self, f):
        """World rotations and positions of every joint."""
        row, c = self.data[f], 0
        rots, poss = [], []
        for j in range(len(self.names)):
            local, pos = np.eye(3), self.offsets[j].copy()
            for ch in self.channels[j]:
                if ch.endswith("position"):
                    pos["XYZ".index(ch[0])] += row[c]
                else:
                    local = local @ _axis_rot(ch[0], row[c])
                c += 1
            p = self.parents[j]
            if p < 0:
                rots.append(local)
                poss.append(pos)
            else:
                rots.append(rots[p] @ local)
                poss.append(poss[p] + rots[p] @ pos)
        return np.array(rots), np.array(poss)


def load_take(name, cache):
    path = os.path.join(cache, name + ".bvh")
    if not os.path.exists(path):
        os.makedirs(cache, exist_ok=True)
        urllib.request.urlretrieve(BVH_URL.format(int(name.split("_")[0]), name), path)
    return Bvh(path)


# ---- the golfer's skeleton ----------------------------------------------

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

    def sample(self, glb, anim_name, t=0.0):
        """Local rotation matrices and the root translation of a clip at t."""
        anim = glb.animation(anim_name)
        local = [np.eye(3) for _ in self.joints]
        root = self.offsets[0].copy()
        pos = {j: k for k, j in enumerate(self.joints)}
        for ch in anim["channels"]:
            s = anim["samplers"][ch["sampler"]]
            times, values = glb.read(s["input"]), glb.read(s["output"])
            k = int(np.clip(np.searchsorted(times, t), 0, len(times) - 1))
            v = values[k].astype(float)
            j = pos[ch["target"]["node"]]
            if ch["target"]["path"] == "rotation":
                local[j] = pose.matrix(v / np.linalg.norm(v))
            elif j == 0:
                root = v
        return local, root

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

    def locals(self, rots):
        return [rots[j] if p < 0 else rots[p].T @ rots[j] for j, p in enumerate(self.parents)]


def between(a, b):
    """The smallest rotation taking direction a to direction b."""
    a, b = pose.unit(a), pose.unit(b)
    axis = np.cross(a, b)
    s, c = np.linalg.norm(axis), float(np.dot(a, b))
    if s < 1e-9:
        return np.eye(3)
    return pose.rot(axis, math.degrees(math.atan2(s, c)))


def two_bone(rig, rots, poss, upper, lower, end, target):
    """Bends upper-lower so end reaches target, keeping the bend's plane."""
    a, b, c = poss[rig.index[upper]], poss[rig.index[lower]], poss[rig.index[end]]
    l1, l2 = np.linalg.norm(b - a), np.linalg.norm(c - b)
    to = target - a
    dist = float(np.clip(np.linalg.norm(to), abs(l1 - l2) + 1e-4, l1 + l2 - 1e-4))
    d = pose.unit(to)
    pole = b - a
    bend = pose.unit(pole - d * np.dot(pole, d))
    cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    mid = a + d * l1 * cos_a + bend * l1 * math.sqrt(max(0.0, 1 - cos_a * cos_a))
    tip = a + d * dist
    du = between(b - a, mid - a)
    iu, il = rig.index[upper], rig.index[lower]
    rots[iu] = du @ rots[iu]
    dl = between(du @ (c - b), tip - mid)
    rots[il] = dl @ du @ rots[il]


# ---- retargeting --------------------------------------------------------

def facing_transform(bvh, f):
    """Rotation from the actor's frame into the golfer's: target at -x,
    facing -z, +y up."""
    _, p = bvh.frame(f)
    target = p[bvh.index["LeftFoot"]] - p[bvh.index["RightFoot"]]
    target[1] = 0
    target = pose.unit(target)
    up = np.array([0.0, 1.0, 0.0])
    facing = np.cross(target, up)
    src = np.column_stack([target, up, facing])
    dst = np.column_stack([[-1.0, 0, 0], up, [0, 0, -1.0]])
    return dst @ src.T


# Where the club head's centre (x, z) and its lowest point (y) should be at
# impact; the ball sits at (0, 0, -0.75). An iron bottoms out just under
# the turf.
IMPACT_AT = (0.0, -0.004, -0.755)
TWIRL_KEYS = 12
SHAFT_LENGTH = 1.0  # grip to club head, metres, near enough for both clubs
ADDRESS_CLEAR = 0.004  # the club head's lowest point at address, metres
IMPACT_WINDOW = 30  # mocap frames either side of impact the correction fades over


# The CMU actor is an amateur: against tour swings (pelvis ~45 deg and
# thorax ~90 deg turned at the top, pelvis moving a few cm away from the
# target, head height held) his backswing sways 14 cm, stands up 7 cm and
# turns the shoulders only ~70 deg. These take the backswing towards a
# tour player's, fading out by impact so the strike is unchanged.
SWAY_KEEP = 0.5  # of the actor's pelvis slide away from the target
HEAD_RISE_KEEP = 0.15  # of the actor's head rise
EXTRA_TURN = 0.22  # extra upper-body turn, as a share of the actor's


def backswing_weight(f, clip):
    """1 through the backswing, easing to 0 at impact; 0 after."""
    if "top" not in clip:
        return 1.0
    if f <= clip["top"]:
        return 1.0
    u = min(1.0, (f - clip["top"]) / max(1, clip["impact"] - clip["top"]))
    return 1.0 - u * u * (3 - 2 * u)


def descendants(rig, name):
    j = rig.index[name]
    out, stack = [], [j]
    while stack:
        k = stack.pop()
        out.append(k)
        stack.extend(c for c, p in enumerate(rig.parents) if p == k)
    return out


def tour_backswing(rig, rots, root, ref_root, ref_local, ref_rots, ref_poss, w):
    """Less sway, posture held and a fuller shoulder turn (see SWAY_KEEP)."""
    if w <= 0.0:
        return rots, root
    root = np.array(root, dtype=float)
    slide = root[0] - ref_root[0]
    if slide > 0.0:  # +x is away from the target
        root[0] -= w * (1.0 - SWAY_KEEP) * slide
    upper = descendants(rig, "spine_02")
    # The thorax's turn from address, about the vertical.
    sp = rig.index["spine_03"]
    fwd0 = ref_rots[sp] @ np.array([0.0, 0.0, -1.0])
    fwd = rots[sp] @ np.array([0.0, 0.0, -1.0])
    turn = math.degrees(math.atan2(fwd0[2] * fwd[0] - fwd0[0] * fwd[2], fwd0[0] * fwd[0] + fwd0[2] * fwd[2]))
    if turn < 0.0:  # turning away from the target (the backswing)
        spin = pose.rot([0.0, 1.0, 0.0], w * EXTRA_TURN * turn)
        for j in upper:
            if rots[j] is not None:
                rots[j] = spin @ rots[j]
    # Posture: bend forward over the ball by what the head rose.
    full = fill(rig, rots, ref_local)
    _, poss = rig.world(rig.locals(full), root)
    head, pelvis = poss[rig.index["head"]], poss[rig.index["pelvis"]]
    keep = HEAD_RISE_KEEP * max(0.0, head[1] - ref_poss[rig.index["head"]][1])
    for _ in range(3):
        excess = head[1] - ref_poss[rig.index["head"]][1] - keep
        if excess <= 1e-4:
            break
        bend = pose.rot([1.0, 0.0, 0.0], -w * math.degrees(math.atan2(excess, np.linalg.norm(head - pelvis))))
        for j in descendants(rig, "spine_01"):
            if rots[j] is not None:
                rots[j] = bend @ rots[j]
        _, poss = rig.world(rig.locals(fill(rig, rots, ref_local)), root)
        head, pelvis = poss[rig.index["head"]], poss[rig.index["pelvis"]]
    return rots, root


IMPACT_OPEN = 15.0  # degrees more shoulder turn toward the target at impact
# Forward shaft lean at impact, degrees (hands ahead of the club head along
# the target line): tour irons strike with ~8-10 deg, the driver about level
# (the ball is forward in the stance). The actor flips the wrists (head past
# the hands); the lead wrist bows to fix it.
SHAFT_LEAN = {"Driver": 1.0, "Iron": 8.0}
RELEASE_SHARE = 0.7  # of the drop to the ball at impact taken by a steeper shaft
ROOT_SHARE = 0.6  # of the drop to the ball at impact taken through the knees
BEND_LEVER = 0.8  # metres: club head drop per radian of bending over the ball


TRAIL_KNEE = 18.0  # degrees: the least the trail knee bends in a full swing


def too_long(hip, ankle, lengths):
    """How far `ankle` is beyond the leg's reach with the knee bent
    TRAIL_KNEE degrees."""
    l1, l2 = lengths
    d = math.sqrt(l1 * l1 + l2 * l2 + 2 * l1 * l2 * math.cos(math.radians(TRAIL_KNEE)))
    return max(0.0, float(np.linalg.norm(hip - ankle)) - d)


def reach_drop(hip, ankle, lengths):
    """How far the hip must come down for the leg to reach `ankle` with
    the knee bent TRAIL_KNEE degrees (0 if it already bends that much)."""
    l1, l2 = lengths
    d = math.sqrt(l1 * l1 + l2 * l2 + 2 * l1 * l2 * math.cos(math.radians(TRAIL_KNEE)))
    v = hip - ankle
    h = math.hypot(v[0], v[2])
    if np.linalg.norm(v) <= d or h >= d:
        return 0.0
    return v[1] - math.sqrt(d * d - h * h)


def impact_weight(f, impact):
    u = max(0.0, 1.0 - abs(f - impact) / IMPACT_WINDOW)
    return u * u * (3 - 2 * u)


def club_head_verts(glb, club):
    doc = glb.doc
    for n in doc["nodes"]:
        if n.get("name") == club + "_head":
            return np.array(glb.read(doc["meshes"][n["mesh"]]["primitives"][0]["attributes"]["POSITION"]), dtype=float)
    raise KeyError(club + "_head")


def retarget(glb, rig, clip, cache):
    bvh = load_take(clip["take"], cache)
    address = clip["address"]
    frames = clip.get("frames") or list(range(clip["start"], clip["end"] + 1))
    g = facing_transform(bvh, address)
    ref_local, ref_root = rig.sample(glb, "ref_" + clip["ref"])
    ref_rots, ref_poss = rig.world(ref_local, ref_root)
    m_rots0, m_poss0 = bvh.frame(address)
    # Scale: the golfer's hip height over the actor's.
    golfer_hip = ref_poss[rig.index["pelvis"]][1] - ref_poss[rig.index["foot_l"]][1]
    actor_hip = m_poss0[bvh.index["Hips"]][1] - m_poss0[bvh.index["LeftFoot"]][1]
    scale = golfer_hip / actor_hip
    hands_l = rig.index["hand_l"]
    club_dir = club_direction(glb, rig)
    club_j = rig.index["club"]
    shaft0 = ref_rots[club_j] @ club_dir  # the club turns in the hand (grip.py)
    plane = pose.unit(np.cross([-1.0, 0.0, 0.0], shaft0))  # + turns the club head away from the target
    arm0 = plane_dir(ref_poss[hands_l] - ref_poss[rig.index["upperarm_l"]], plane)
    arm_angle = 0.0
    grip_r = ref_rots[hands_l].T @ (ref_poss[rig.index["hand_r"]] - ref_poss[hands_l])
    hand_r_in_l = ref_rots[hands_l].T @ ref_rots[rig.index["hand_r"]]

    head_verts = club_head_verts(glb, clip.get("club", "Driver"))
    legs = {s: (np.linalg.norm(ref_poss[rig.index[f"calf_{s}"]] - ref_poss[rig.index[f"thigh_{s}"]]),
                np.linalg.norm(ref_poss[rig.index[f"foot_{s}"]] - ref_poss[rig.index[f"calf_{s}"]])) for s in "lr"}
    _, rest = rig.world([np.eye(3)] * len(rig.names), rig.offsets[0])

    def club_head(rots, poss):
        w = (rots[club_j] @ (head_verts - rest[club_j]).T).T + poss[club_j]
        return np.array([*w.mean(axis=0)[[0]], w[:, 1].min(), w.mean(axis=0)[2]])

    lean_fix, impact_lean = [0.0], [0.0]  # degrees added at impact, refined pass by pass

    def lean_of(rots):
        shaft = rots[club_j] @ club_dir
        return math.degrees(math.atan2(shaft[0], -shaft[1]))

    def run(correct):
        nonlocal arm_angle
        arm_angle = 0.0
        impact_head = np.zeros(3)
        impact_lean[0] = 0.0
        out_rots, out_root = [], []
        for i, f in enumerate(frames):
            m_rots, m_poss = bvh.frame(f)
            rots = [None] * len(rig.names)
            for j, name in enumerate(rig.names):
                src = BONES.get(name)
                if src:
                    k = bvh.index[src]
                    rots[j] = g @ m_rots[k] @ m_rots0[k].T @ g.T @ ref_rots[j]
            if clip.get("glance"):
                glance(rig, rots, i / MOCAP_FPS, clip["glance"])
            root = ref_root + scale * (g @ (m_poss[bvh.index["Hips"]] - m_poss0[bvh.index["Hips"]]))
            if not clip["putt"]:
                rots, root = tour_backswing(rig, rots, root, ref_root, ref_local, ref_rots, ref_poss,
                                            backswing_weight(f, clip))
            if "impact" in clip:
                # Down into the shot at impact: a little through the knees
                # (the feet are pinned below), the rest bending over the ball,
                # so the lead leg can still straighten into impact. The hips
                # stay back from the ball (the actor's thrust towards it).
                w = impact_weight(f, clip["impact"])
                body = (1.0 - RELEASE_SHARE) * correct[1]
                root = root + w * np.array([0.0, ROOT_SHARE * body, correct[2]])
                if body != 0.0:
                    bend = pose.rot([1.0, 0.0, 0.0], math.degrees(w * (1.0 - ROOT_SHARE) * body / BEND_LEVER))
                    for j in descendants(rig, "spine_01"):
                        if rots[j] is not None:
                            rots[j] = bend @ rots[j]
            rots = fill(rig, rots, ref_local)
            _, poss = rig.world(rig.locals(rots), root)
            # Feet go where the actor's feet go.
            targets = {}
            for s, actor in (("l", "LeftFoot"), ("r", "RightFoot")):
                k = bvh.index[actor]
                target = ref_poss[rig.index[f"foot_{s}"]] + scale * (g @ (m_poss[k] - m_poss0[k]))
                foot = rots[rig.index[f"foot_{s}"]]
                # Up on the toes, not through the ground.
                toe = target + foot @ (rest[rig.index[f"ball_{s}"]] - rest[rig.index[f"foot_{s}"]])
                target = target + np.array([0.0, max(0.0, ref_poss[rig.index[f"ball_{s}"]][1] - toe[1],
                                                     ref_poss[rig.index[f"foot_{s}"]][1] - target[1]), 0.0])
                targets[s] = [target, foot]
            if not clip["putt"] and "impact" in clip:
                # The trail knee stays flexed (the actor's locks straight):
                # to the top and down to impact the hips sink a little; after
                # impact the trail heel comes up, pivoting on the toe.
                tgt, foot = targets["r"]
                hip = poss[rig.index["thigh_r"]]
                if f <= clip["impact"]:
                    drop = reach_drop(hip, tgt, legs["r"])
                    if drop > 0.0:
                        root = root - np.array([0.0, drop, 0.0])
                        _, poss = rig.world(rig.locals(rots), root)
                else:
                    ball = tgt + foot @ (rest[rig.index["ball_r"]] - rest[rig.index["foot_r"]])
                    side = pose.unit(np.cross(ball - tgt, [0.0, 1.0, 0.0]))
                    for _ in range(12):
                        if too_long(hip, tgt, legs["r"]) <= 1e-4:
                            break
                        lift = pose.rot(side, 4.0)
                        if (ball + lift @ (tgt - ball))[1] < tgt[1]:
                            lift = lift.T
                        tgt, foot = ball + lift @ (tgt - ball), lift @ foot
                    # Still out of reach: the toe drags round towards the hips.
                    for _ in range(6):
                        excess = too_long(hip, tgt, legs["r"])
                        if excess <= 1e-4:
                            break
                        pull = np.array([hip[0] - tgt[0], 0.0, hip[2] - tgt[2]])
                        tgt = tgt + pose.unit(pull) * min(2.0 * excess, np.linalg.norm(pull))
                    targets["r"] = [tgt, foot]
            for s in "lr":
                target, foot = targets[s]
                two_bone(rig, rots, poss, f"thigh_{s}", f"calf_{s}", f"foot_{s}", target)
                rots[rig.index[f"foot_{s}"]] = foot
            rots = fill(rig, rots, ref_local, keep=True)
            rots, poss = rig.world(rig.locals(rots), root)
            if not clip["putt"] and "top" in clip:
                arm = plane_dir(poss[hands_l] - poss[rig.index["upperarm_l"]], plane)
                step = math.degrees(math.atan2(np.dot(np.cross(arm0, arm), plane), np.dot(arm0, arm))) - arm_angle
                arm_angle += (step + 180.0) % 360.0 - 180.0  # unwrapped
                if f <= clip["top"]:
                    club = arm_angle + ramp(arm_angle, HINGE_BACK)
                elif f <= clip["impact"]:
                    club = arm_angle + ramp(arm_angle, HINGE_DOWN)
                else:
                    club = max(arm_angle - ramp(-arm_angle, HINGE_FOLLOW), FINISH_LIMIT)
                want = pose.rot(plane, club) @ shaft0
                rots[hands_l] = between(rots[club_j] @ club_dir, want) @ rots[hands_l]
                rots = fill(rig, rots, ref_local, keep=True)
                rots, poss = rig.world(rig.locals(rots), root)
            if not clip["putt"] and "impact" in clip:
                # Shoulders open to the target at impact (the actor's are
                # nearly square): the chest turns under the arms, the hands
                # and club staying where they were, the head on the ball.
                w = impact_weight(f, clip["impact"]) * IMPACT_OPEN
                if w > 0.0:
                    hand_p, hand_r = poss[hands_l].copy(), rots[hands_l].copy()
                    # About the spine, so the head stays put.
                    axis = poss[rig.index["neck_01"]] - poss[rig.index["spine_02"]]
                    spin, back = pose.rot(axis, w), pose.rot(axis, -w)
                    neck = set(descendants(rig, "neck_01"))
                    for j in descendants(rig, "spine_02"):
                        if rots[j] is not None:
                            rots[j] = (back @ spin if j in neck else spin) @ rots[j]
                    rots = fill(rig, rots, ref_local, keep=True)
                    rots, poss = rig.world(rig.locals(rots), root)
                    two_bone(rig, rots, poss, "upperarm_l", "lowerarm_l", "hand_l", hand_p)
                    rots[hands_l] = hand_r
                    rots = fill(rig, rots, ref_local, keep=True)
                    rots, poss = rig.world(rig.locals(rots), root)
            if correct is not None and not clip["putt"] and "impact" in clip:
                w = impact_weight(f, clip["impact"])
                if w > 0.0 and lean_fix[0] != 0.0:
                    # The hands ahead of the head at impact: the lead wrist
                    # bows, laying the head back about the hands (the arm
                    # then swings the hands forward to the ball, below).
                    rots[hands_l] = pose.rot([0.0, 0.0, 1.0], w * lean_fix[0]) @ rots[hands_l]
                    rots = fill(rig, rots, ref_local, keep=True)
                    rots, poss = rig.world(rig.locals(rots), root)
                if w > 0.0 and correct[1] != 0.0:
                    # Most of the way down to the ball: the shaft comes up
                    # steeper at impact than at address (the hands higher,
                    # as tour players' are), lowering the head.
                    shaft = rots[club_j] @ club_dir
                    flat = math.hypot(shaft[0], shaft[2])
                    axis = pose.unit(np.cross([shaft[0], 0.0, shaft[2]], [0.0, 1.0, 0.0]))
                    if (pose.rot(axis, 1.0) @ shaft)[1] > shaft[1]:
                        axis = -axis
                    steepen = math.degrees(-w * RELEASE_SHARE * correct[1] / (SHAFT_LENGTH * max(flat, 0.3)))
                    rots[hands_l] = pose.rot(axis, steepen) @ rots[hands_l]
                    rots = fill(rig, rots, ref_local, keep=True)
                    rots, poss = rig.world(rig.locals(rots), root)
                if w > 0.0 and np.any(correct):
                    # Brings the club head in to the ball at impact: the lead
                    # arm swings in (its length kept), the club turning with it.
                    shoulder = poss[rig.index["upperarm_l"]]
                    reach = poss[hands_l] + w * correct * np.array([1.0, 0.0, 0.0]) - shoulder
                    two_bone(rig, rots, poss, "upperarm_l", "lowerarm_l", "hand_l",
                             shoulder + pose.unit(reach) * np.linalg.norm(poss[hands_l] - shoulder))
                    rots = fill(rig, rots, ref_local, keep=True)
                    rots, poss = rig.world(rig.locals(rots), root)
                if f == clip["impact"]:
                    impact_head[:] = club_head(rots, poss)
                    impact_lean[0] = lean_of(rots)
            if "impact" not in clip:
                # Waggling over the ball, the club head stays above the
                # ground: the wrists lift it a few degrees round the grip.
                for _ in range(3):
                    low = club_head(rots, poss)[1]
                    if low >= ADDRESS_CLEAR:
                        break
                    shaft = rots[club_j] @ club_dir
                    axis = pose.unit(np.cross(shaft, [0.0, 1.0, 0.0]))
                    reach = SHAFT_LENGTH * math.sqrt(max(1e-4, 1.0 - shaft[1] ** 2))
                    lift = math.degrees((ADDRESS_CLEAR - low) / reach)
                    rots[hands_l] = pose.rot(axis, lift) @ rots[hands_l]
                    rots = fill(rig, rots, ref_local, keep=True)
                    rots, poss = rig.world(rig.locals(rots), root)
            # The right hand stays on the grip.
            target = poss[hands_l] + rots[hands_l] @ grip_r
            hand = rots[hands_l] @ hand_r_in_l
            two_bone(rig, rots, poss, "upperarm_r", "lowerarm_r", "hand_r", target)
            rots[rig.index["hand_r"]] = hand
            rots = fill(rig, rots, ref_local, keep=True)
            out_rots.append(rig.locals(rots))
            out_root.append(root)
        return out_rots, out_root, impact_head

    correct = np.zeros(3)
    out_rots, out_root, head = run(correct)
    if not clip["putt"] and "impact" in clip and clip["impact"] in frames:
        # The lowest point of the head on the ball at impact, the shaft
        # leaning forward; the bend, the wrist and the arm move the head in
        # each other's way, so a few passes.
        target = np.array(clip.get("strike", IMPACT_AT))
        lean = SHAFT_LEAN[clip.get("club", "Driver")]
        for _ in range(8):
            if np.linalg.norm(target - head) < 0.002 and abs(lean - impact_lean[0]) < 0.5:
                break
            correct = correct + (target - head)
            lean_fix[0] += lean - impact_lean[0]
            out_rots, out_root, head = run(correct)

    if clip.get("loop"):
        loop_blend(out_rots, out_root, clip["loop"])
    times = retime(clip, frames)
    keep = list(range(0, len(frames), STEP))
    if keep[-1] != len(frames) - 1:
        keep.append(len(frames) - 1)
    if clip.get("impact") in frames:
        # A key on the strike itself, so the head meets the ball.
        keep = sorted(set(keep) | {frames.index(clip["impact"])})
    times = [times[i] for i in keep]
    out_rots = [out_rots[i] for i in keep]
    out_root = [out_root[i] for i in keep]
    if clip.get("hold"):
        end, last, last_root = times[-1], out_rots[-1], out_root[-1]
        if clip.get("twirl"):
            # Held at the finish, then the club spun once in the fingers.
            start, seconds = clip["twirl"]
            club_j = rig.index["club"]
            shaft = club_dir  # the spin axis, along the shaft
            for k in range(TWIRL_KEYS + 1):
                u = k / TWIRL_KEYS
                key = list(last)
                key[club_j] = last[club_j] @ pose.rot(shaft, 360.0 * u * u * (3 - 2 * u))
                times.append(end + start + seconds * u)
                out_rots.append(key)
                out_root.append(last_root)
        times.append(end + clip["hold"])
        out_rots.append(last)
        out_root.append(last_root)
    return np.array(times, dtype=np.float32), out_rots, np.array(out_root, dtype=np.float32)


def plane_dir(v, normal):
    return pose.unit(v - normal * np.dot(normal, v))


def ramp(angle, hinge):
    most, lo, hi = hinge
    u = float(np.clip((angle - lo) / (hi - lo), 0.0, 1.0))
    return most * u * u * (3 - 2 * u)


def club_direction(glb, rig):
    """The shaft's direction (grip to head) in the rest frame: towards the
    middle of the driver's shaft, which lies on its axis (the head's middle
    is off the axis, in front of the hosel and towards the toe)."""
    doc = glb.doc
    mid = None
    for n in doc["nodes"]:
        if n.get("name") == "Driver_shaft":
            mid = glb.read(doc["meshes"][n["mesh"]]["primitives"][0]["attributes"]["POSITION"]).mean(axis=0)
    _, rest = rig.world([np.eye(3)] * len(rig.names), rig.offsets[0])
    return pose.unit(mid - rest[rig.index["club"]])


def fill(rig, rots, ref_local, keep=False):
    """Bones without a mapping keep their address pose relative to their
    parent (fingers, the club, the root)."""
    out = list(rots)
    world = []
    for j, p in enumerate(rig.parents):
        if out[j] is None or (keep and rig.names[j] not in BONES):
            out[j] = (world[p] if p >= 0 else np.eye(3)) @ ref_local[j]
        world.append(out[j])
    return out


def retime(clip, frames):
    """Seconds from the clip's start for each mocap frame."""
    if "top" not in clip:
        return [i / MOCAP_FPS for i in range(len(frames))]
    start, top, impact = frames[0], clip["top"], clip["impact"]
    back = 1.0
    if clip.get("back"):
        back = clip["back"] / ((top - start) / MOCAP_FPS)
    down = 1.0
    if clip.get("downswing"):
        down = clip["downswing"] / ((impact - top) / MOCAP_FPS)
    follow = clip.get("follow", 1.0)
    t, times = 0.0, []
    for f in frames:
        if f > start:
            scale = back if f <= top else (down if f <= impact else follow)
            t += scale / MOCAP_FPS
        times.append(t)
    return times


def smooth(quats):
    """A light [1 2 1] filter over time against marker jitter."""
    q = quats.copy()
    for f in range(1, len(q)):
        if np.dot(q[f], q[f - 1]) < 0:
            q[f] = -q[f]
    out = q.copy()
    out[1:-1] = (q[:-2] + 2 * q[1:-1] + q[2:]) / 4
    return out / np.linalg.norm(out, axis=1, keepdims=True)


def write_clip(glb, rig, name, times, rots, root, filtered=True):
    t_acc = glb.add(times, minmax=True)
    t_one = None
    samplers, channels = [], []
    for j, node in enumerate(rig.joints):
        q = np.array([pose.quat(r[j]) for r in rots])
        q = (smooth(q) if filtered and len(q) > 2 else q).astype(np.float32)
        if len(q) > 1 and np.max(1.0 - np.abs(q @ q[0])) < 1e-7:
            # Still all clip long (the fingers round the grip): one key.
            if t_one is None:
                t_one = glb.add(np.asarray(times[:1], np.float32), minmax=True)
            samplers.append({"input": t_one, "output": glb.add(q[:1]), "interpolation": "LINEAR"})
        else:
            samplers.append({"input": t_acc, "output": glb.add(q), "interpolation": "LINEAR"})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": node, "path": "rotation"}})
    samplers.append({"input": t_acc, "output": glb.add(root), "interpolation": "LINEAR"})
    channels.append({"sampler": len(samplers) - 1, "target": {"node": rig.joints[0], "path": "translation"}})
    glb.set_animation({"name": name, "samplers": samplers, "channels": channels})


def glance(rig, rots, t, at):
    """Turns the head and neck towards the target (-x) and back: at is
    (start, seconds turning, seconds held, degrees)."""
    start, turn, hold, degrees = at
    if t < start + turn:
        u = (t - start) / turn
    else:
        u = 1 - (t - start - turn - hold) / turn
    u = float(np.clip(u, 0, 1))
    a = degrees * u * u * (3 - 2 * u)
    for name, share in (("neck_01", 0.4), ("head", 0.6)):
        j = rig.index[name]
        # About the bone's own axis, so a golfer bent over the ball turns
        # his head along his spine rather than round the vertical.
        axis = rots[j] @ np.array([0.0, 1.0, 0.0])
        rots[j] = pose.rot(axis, a * share) @ rots[j]


def loop_blend(rots, roots, seconds):
    """Eases the last seconds of a clip into its first frame so it loops."""
    n = min(int(seconds * MOCAP_FPS), len(rots) - 1)
    for k in range(n):
        i = len(rots) - n + k
        w = (k + 1) / n
        w = w * w * (3 - 2 * w)
        rots[i] = [pose.slerp(a, b, w) for a, b in zip(rots[i], rots[0])]
        roots[i] = roots[i] * (1 - w) + roots[0] * w


def ensure_refs(glb, rig):
    """Keeps the hand-keyed address poses the golf clips are measured from,
    as one-key clips, before "address" itself is replaced."""
    for name in ("address", "address_putt"):
        if glb.animation("ref_" + name):
            continue
        local, root = rig.sample(glb, name)
        write_clip(glb, rig, "ref_" + name, np.zeros(1, np.float32), [local], np.array([root], np.float32),
                   filtered=False)


# ---- standing clips -----------------------------------------------------

# Direction of each mapped bone: (golfer child, actor child). None means up;
# "forward" and "end" use the golfer's facing and the actor's end site.
BONE_DIRS = {
    "pelvis": (None, None), "spine_01": ("spine_02", "Spine"), "spine_02": ("spine_03", "Spine1"),
    "spine_03": ("neck_01", "Neck1"), "neck_01": ("head", "Head"), "head": (None, None),
    "foot_l": ("ball_l", "LeftToeBase"), "foot_r": ("ball_r", "RightToeBase"),
    "ball_l": ("forward", "end"), "ball_r": ("forward", "end"),
}
for _s, _a in (("l", "Left"), ("r", "Right")):
    BONE_DIRS.update({
        f"clavicle_{_s}": (f"upperarm_{_s}", f"{_a}Arm"), f"upperarm_{_s}": (f"lowerarm_{_s}", f"{_a}ForeArm"),
        f"lowerarm_{_s}": (f"hand_{_s}", f"{_a}Hand"), f"hand_{_s}": (f"middle_01_{_s}", f"{_a}HandIndex1"),
        f"thigh_{_s}": (f"calf_{_s}", f"{_a}Leg"), f"calf_{_s}": (f"foot_{_s}", f"{_a}Foot"),
    })

# Standing clips: take, frames, where the golfer faces (golfer frame), and
# options. walk is played in place (the game moves the golfer) with the
# club carried; loop eases the end into the start.
STAND_CLIPS = {
    "walk": dict(take="69_01", start=205, end=355, facing=(0.0, 0.0, -1.0), in_place=True, carry=True, loop=0.25),
    "celebrate": dict(take="79_69", start=40, end=330, facing=(-0.7, 0.0, -0.7), carry=True),  # arms up
    "upset": dict(take="79_74", start=450, end=760, facing=(-0.7, 0.0, -0.7), carry=True),  # hands on head
    # A birdie: the actor's happy bounce at the knees, with the right fist
    # pumped twice in front of the chest (PUMP_KEYS) and the club held low.
    "fist_pump": dict(take="79_69", start=552, end=700, facing=(-0.7, 0.0, -0.7), carry=True, pump=True),
    # A short putt missed: the head drops and a hand goes to the face.
    "slump": dict(take="79_71", start=80, end=470, facing=(-0.7, 0.0, -0.7), carry=True),
    # Standing at ease: weight shifts and breathing (the caddie).
    "idle": dict(take="77_02", start=100, end=740, facing=(0.0, 0.0, -1.0), loop=0.5),
    # Crouching behind the ball to read a putt, putter in hand.
    "read": dict(take="77_08", start=150, end=460, facing=(0.0, 0.0, -1.0), carry=True),
}
CARRY_HEAD_HEIGHT = 0.12  # the club head's height when carried, metres


def actor_facing(bvh, f):
    _, p = bvh.frame(f)
    side = p[bvh.index["LeftArm"]] - p[bvh.index["RightArm"]]
    facing = np.cross(side, [0.0, 1.0, 0.0])
    facing[1] = 0
    return pose.unit(facing)


def yaw_between(a, b):
    a, b = pose.unit(np.array([a[0], 0, a[2]])), pose.unit(np.array([b[0], 0, b[2]]))
    return pose.rot([0, 1, 0], math.degrees(math.atan2(np.cross(a, b)[1], np.dot(a, b))))


# The fist pump's right hand, from the right shoulder in the chest's frame
# (metres: forward, up, in across the body): fist up in front of the
# shoulder, then pulled down to the hip, the elbow driven back past it.
PUMP_HELD = ("spine_01", "spine_02", "spine_03", "neck_01", "head")
PUMP_UP = np.array([0.22, -0.10, 0.10])
PUMP_DOWN = np.array([0.10, -0.40, 0.02])
# (seconds, how far up: 0 the actor's own hand, 1 PUMP_UP, 2 PUMP_DOWN)
PUMP_KEYS = [(0.0, 0.0), (0.24, 1.0), (0.38, 2.0), (0.5, 1.0), (0.64, 2.0), (0.9, 2.0), (1.23, 0.0)]


def pump_target(t, actor, up, down):
    for (t0, a), (t1, b) in zip(PUMP_KEYS, PUMP_KEYS[1:]):
        if t <= t1:
            u = float(np.clip((t - t0) / (t1 - t0), 0.0, 1.0))
            u = u * u * (3 - 2 * u)
            break
    else:
        a, b, u = PUMP_KEYS[-1][1], PUMP_KEYS[-1][1], 1.0

    def at(k):
        return actor if k == 0.0 else (up if k == 1.0 else down)
    return at(a) * (1 - u) + at(b) * u


def reach_pole(rig, rots, poss, upper, lower, end, target, pole):
    """two_bone with the elbow pointed towards `pole`."""
    a, b, c = poss[rig.index[upper]], poss[rig.index[lower]], poss[rig.index[end]]
    l1, l2 = np.linalg.norm(b - a), np.linalg.norm(c - b)
    to = target - a
    dist = float(np.clip(np.linalg.norm(to), abs(l1 - l2) + 1e-4, l1 + l2 - 1e-4))
    d = pose.unit(to)
    bend = pose.unit(pole - d * np.dot(pole, d))
    cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    mid = a + d * l1 * cos_a + bend * l1 * math.sqrt(max(0.0, 1 - cos_a * cos_a))
    du = between(b - a, mid - a)
    iu, il = rig.index[upper], rig.index[lower]
    rots[iu] = du @ rots[iu]
    rots[il] = between(du @ (c - b), a + d * dist - mid) @ du @ rots[il]


def fist_pump(rig, rots, poss, root, t, hold_l, local0):
    """The right fist pumped (PUMP_KEYS), the left hand and club held where
    they started against the hips."""
    chest = rots[rig.index["spine_03"]]
    fwd, up, inward = chest @ np.array([0.0, 0.0, -1.0]), chest @ np.array([0.0, 1.0, 0.0]), chest @ np.array([-1.0, 0.0, 0.0])
    shoulder = poss[rig.index["upperarm_r"]]
    axes = np.stack([fwd, up, inward], axis=1)
    target = pump_target(t, poss[rig.index["hand_r"]], shoulder + axes @ PUMP_UP, shoulder + axes @ PUMP_DOWN)
    reach_pole(rig, rots, poss, "upperarm_r", "lowerarm_r", "hand_r", target, -up - 0.8 * fwd - 0.3 * inward)
    rots[rig.index["hand_r"]] = rots[rig.index["lowerarm_r"]]
    pel = rig.index["pelvis"]
    rel_p, rel_r = hold_l
    left = rots[rig.index["hand_l"]]
    two_bone(rig, rots, poss, "upperarm_l", "lowerarm_l", "hand_l", poss[pel] + rots[pel] @ rel_p)
    rots[rig.index["hand_l"]] = rots[pel] @ rel_r if left is not None else left
    rots = fill(rig, rots, local0, keep=True)
    return rots


def retarget_stand(glb, rig, clip, cache):
    bvh = load_take(clip["take"], cache)
    fps = MOCAP_FPS
    start, end = clip["start"], clip["end"]
    frames = list(range(start, end + 1))
    m_rots0, m_poss0 = bvh.frame(0)  # the T pose
    up = np.array([0.0, 1.0, 0.0])
    if clip.get("in_place"):
        _, pa = bvh.frame(start)
        _, pb = bvh.frame(end)
        heading = pb[bvh.index["Hips"]] - pa[bvh.index["Hips"]]
    else:
        heading = actor_facing(bvh, start)
    g = yaw_between(heading, clip["facing"])
    # The golfer's rest pose turned to the actor's T pose, bone by bone.
    rest_rots, rest = rig.world([np.eye(3)] * len(rig.names), rig.offsets[0])
    rest_facing = np.array([0.0, 0.0, -1.0])
    t_facing = g @ actor_facing(bvh, 0)
    ref = {}
    for name, (child, actor_child) in BONE_DIRS.items():
        j, k = rig.index[name], bvh.index[BONES[name]]
        if child is None:
            d0, d1 = up, up
        elif child == "forward":
            d0 = rest_facing
            d1 = g @ m_rots0[k] @ bvh.ends[k]
        else:
            d0 = rest[rig.index[child]] - rest[j]
            d1 = g @ (m_poss0[bvh.index[actor_child]] - m_poss0[k])
        n0, n1 = (rest_facing, t_facing) if abs(np.dot(pose.unit(d0), rest_facing)) < 0.7 else (up, up)
        ref[name] = pose.aim(d0, n0, d1, n1)
    # Scale and the point the actor's positions are measured from.
    pelvis_rest = rest[rig.index["pelvis"]]
    ankle_rest = rest[rig.index["foot_l"]][1]
    hips0 = m_poss0[bvh.index["Hips"]]
    scale = (pelvis_rest[1] - ankle_rest) / (hips0[1] - m_poss0[bvh.index["LeftFoot"]][1])
    _, ps = bvh.frame(start)
    origin0 = np.array([ps[bvh.index["Hips"]][0], hips0[1], ps[bvh.index["Hips"]][2]])
    drift = np.zeros(3)
    if clip.get("in_place"):
        drift = heading / (end - start)
        drift[1] = 0
    relaxed = {}
    grip_local, _ = rig.sample(glb, "ref_address")
    for j, name in enumerate(rig.names):
        if name.split("_")[0] in ("index", "middle", "ring", "pinky", "thumb"):
            curl = 1.0 if (clip.get("carry") and name.endswith("_l")) else 0.35
            if clip.get("pump") and name.endswith("_r"):
                curl = 1.7  # a fist: tighter than round the grip
            relaxed[j] = pose.slerp(np.eye(3), grip_local[j], curl)
    relaxed[rig.index["club"]] = grip_local[rig.index["club"]]  # how it sits in the hand
    club_dir = club_direction(glb, rig)
    facing = pose.unit(np.array(clip["facing"], dtype=float))

    out_rots, out_root = [], []
    for i, f in enumerate(frames):
        m_rots, m_poss = bvh.frame(f)
        origin = origin0 + drift * i
        rots = [None] * len(rig.names)
        for j, name in enumerate(rig.names):
            if name in ref:
                k = bvh.index[BONES[name]]
                rots[j] = g @ m_rots[k] @ m_rots0[k].T @ g.T @ ref[name]
        # The actor's collarbones come out raised (the shoulders ~10 cm
        # high, a shrug); the golfer's stay at rest on the chest.
        for name in ("clavicle_l", "clavicle_r"):
            rots[rig.index[name]] = None
        if clip.get("pump"):
            # Chest held as at the start and the head looking ahead (the
            # actor leans back to look at the sky); the legs still bounce.
            if i == 0:
                held = {n: rots[rig.parents[rig.index[n]]].T @ rots[rig.index[n]] for n in PUMP_HELD}
                held.update(neck_01=np.eye(3), head=pose.rot([1.0, 0.0, 0.0], -8.0))  # eyes ahead, a little down
            for n in PUMP_HELD:
                rots[rig.index[n]] = rots[rig.parents[rig.index[n]]] @ held[n]
        local0 = [relaxed.get(j, np.eye(3)) for j in range(len(rig.names))]

        def place(x):
            return pelvis_rest + scale * (g @ (x - origin))

        root = place(m_poss[bvh.index["Hips"]]) - rig.offsets[rig.index["pelvis"]]
        rots = fill(rig, rots, local0)
        _, poss = rig.world(rig.locals(rots), root)
        for s, actor in (("l", "LeftFoot"), ("r", "RightFoot")):
            foot = rots[rig.index[f"foot_{s}"]]
            two_bone(rig, rots, poss, f"thigh_{s}", f"calf_{s}", f"foot_{s}", place(m_poss[bvh.index[actor]]))
            rots[rig.index[f"foot_{s}"]] = foot
        rots = fill(rig, rots, local0, keep=True)
        if clip.get("pump"):
            rots, poss = rig.world(rig.locals(rots), root)
            if i == 0:
                pel = rig.index["pelvis"]
                hold_l = (rots[pel].T @ (poss[rig.index["hand_l"]] - poss[pel]), rots[pel].T @ rots[rig.index["hand_l"]])
            rots = fist_pump(rig, rots, poss, root, i / fps, hold_l, local0)
        if clip.get("carry"):
            # The club in the left hand: head low in front, or held up
            # when the hand is raised above the shoulder.
            rots, poss = rig.world(rig.locals(rots), root)
            h = rig.index["hand_l"]
            drop = float(np.clip((poss[h][1] - CARRY_HEAD_HEIGHT) / 1.07, 0.3, 0.95))
            low = facing * math.sqrt(1 - drop * drop) - up * drop
            raised = (poss[h][1] - poss[rig.index["upperarm_l"]][1] + 0.1) / 0.3
            w = float(np.clip(raised, 0, 1))
            want = pose.unit(low * (1 - w * w * (3 - 2 * w)) + pose.unit(up + 0.5 * facing) * w * w * (3 - 2 * w))
            rots[h] = between(rots[rig.index["club"]] @ club_dir, want) @ rots[h]
            rots = fill(rig, rots, local0, keep=True)
        out_rots.append(rig.locals(rots))
        out_root.append(root)
    if clip.get("loop"):
        loop_blend(out_rots, out_root, clip["loop"])
    times = [i / fps for i in range(len(frames))]
    step = max(1, int(round(fps / 60.0)))
    keep = list(range(0, len(frames), step))
    if keep[-1] != len(frames) - 1:
        keep.append(len(frames) - 1)
    return (np.array([times[i] for i in keep], np.float32), [out_rots[i] for i in keep],
            np.array([out_root[i] for i in keep], np.float32))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--glb", default=os.path.join(os.path.dirname(__file__), "../../game/assets/golfer/free_golfer.glb"))
    ap.add_argument("--cache", default=os.path.join(os.path.expanduser("~"), ".cache", "cmu-mocap"))
    ap.add_argument("--out", default=None)
    ap.add_argument("--clips", default=",".join(list(CLIPS) + list(STAND_CLIPS)))
    args = ap.parse_args()
    glb = glb_edit.Glb(args.glb)
    rig = Rig(glb)
    ensure_refs(glb, rig)
    iron.ensure_iron(glb, rig)
    grip.fit(glb, rig, club_direction(glb, rig))
    grip.straighten(glb, rig)
    # The clubs modelled from real ones, before the swings are measured
    # against their heads.
    clubs.swap(glb, rig)
    for name in args.clips.split(","):
        if name in STAND_CLIPS:
            times, rots, root = retarget_stand(glb, rig, STAND_CLIPS[name], args.cache)
        else:
            times, rots, root = retarget(glb, rig, CLIPS[name], args.cache)
        write_clip(glb, rig, name, times, rots, root)
        print(f"{name}: {len(times)} keys, {times[-1]:.2f} s")
    glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
