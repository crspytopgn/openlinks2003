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
import putt_posture  # noqa: E402
import swing_posture  # noqa: E402
import anatomy  # noqa: E402
import collide  # noqa: E402

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

CLUB_ROLL = 120  # most degrees the club rolls about its shaft to spare the wrists (footage)
TRAIL_ELBOW_DOWN = 1.0  # pull of the trail elbow's pole towards the ground (footage)
AIM_ABSOLUTE = 60.0  # degrees from its address direction by which a tracked limb points itself
# Bones aimed along the tracked limbs for takes from footage (retarget).
AIM_BONES = {"upperarm_l": ("LeftArm", "LeftForeArm"), "lowerarm_l": ("LeftForeArm", "LeftHand"),
             "upperarm_r": ("RightArm", "RightForeArm"), "lowerarm_r": ("RightForeArm", "RightHand")}
AIM_CHILD = {"upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r"}

# Clips: take, the golfer's pose the take starts from, and mocap frames.
# address is the still frame the retarget is measured from; the clip runs
# from start to end, and the time from top to impact is squeezed to
# downswing seconds and start to top to back seconds (left out, they play in
# real time); after impact time runs at follow times real time. hold adds
# seconds of the last frame.
CLIPS = {
    # Address: held still over the ball, with a look at the target. (The
    # actor's frames before 150 have the club 30 cm or more off the ball
    # while he sets up, which looked like the clubhead wandering.)
    "address": dict(take="64_01", ref="address", address=150, putt=False, loop=0.3,
                    frames=[150] * 360,
                    glance=(1.3, 0.4, 0.7, 70.0)),
    "address_putt": dict(take="64_13", ref="address_putt", club="Putter", address=95, putt=True, loop=0.3,
                         frames=(list(range(95, 15, -1)) + list(range(15, 95))) * 2,
                         glance=(0.9, 0.45, 0.8, 75.0)),
    # Full swings: a real golfer filmed in slow motion, tracked in 3D
    # (footage_take.py). The CMU actor (take 64_01, an amateur) flew his
    # trail elbow at the top and let his arms hang slack at impact.
    "backswing": dict(take="ft:suvichaya_iron", ref="address", address=4, start=31, end=150, top=150, impact=187,
                      putt=False, tour=False),
    "swing": dict(take="ft:suvichaya_iron", ref="address", address=4, start=150, end=284, top=150, impact=187,
                  downswing=0.30, follow=0.7, hold=2.5, twirl=(0.9, 0.55), putt=False, strike=(0.0, 0.012, -0.755),
                  tour=False),
    # The irons: the same takes from the iron's address (iron.py).
    "address_iron": dict(take="64_01", ref="address_iron", address=150, putt=False, loop=0.3,
                         frames=[150] * 360,
                         glance=(1.3, 0.4, 0.7, 70.0), club="Iron"),
    "backswing_iron": dict(take="ft:suvichaya_iron", ref="address_iron", club="Iron", address=4, start=31, end=150, top=150,
                           impact=187, putt=False, tour=False),
    "swing_iron": dict(take="ft:suvichaya_iron", ref="address_iron", club="Iron", address=4, start=150, end=284, top=150,
                       impact=187, downswing=0.30, follow=0.7, hold=2.5, twirl=(0.9, 0.55), putt=False, tour=False),
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
    if name.startswith("ft:"):  # tracked from real footage (footage_take.py)
        import footage_take
        return footage_take.load(name[3:])
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
SWAY_KEEP = 0.25  # of the actor's pelvis slide away from the target
HEAD_RISE_KEEP = 0.15  # of the actor's head rise
EXTRA_TURN = 0.22  # extra upper-body turn, as a share of the actor's


# Tour putters keep the lower body and the head still; the shoulders rock
# the arms and putter like a pendulum. The actor's hips turn ~15 deg and his
# head drifts 12 cm towards the hole through the stroke. These keep a share
# of that: the legs and pelvis hold the address, and the upper body leans
# back about the base of the spine so the head stays over the ball.
LEAD_HEEL = 0.2  # of the actor's lead heel lift kept in full swings
PUTT_STILL = 0.1  # of the actor's hip slide, foot moves and head drift kept
LOWER_BODY = ("pelvis", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r")


def still_putt(rig, rots, root, ref_root, ref_local, ref_rots, ref_poss):
    root = ref_root + PUTT_STILL * (root - ref_root)
    for name in LOWER_BODY:
        j = rig.index.get(name)
        if j is not None:
            rots[j] = ref_rots[j]
    rots = fill(rig, rots, ref_local)
    _, poss = rig.world(rig.locals(rots), root)
    # Leaning back over the ball sideways (about the line to the ball) and
    # then fore and aft (about the target line), so the shoulders don't turn.
    for axis, (u, v) in (([0.0, 0.0, 1.0], (0, 1)), ([1.0, 0.0, 0.0], (2, 1))):
        _, poss = rig.world(rig.locals(rots), root)
        pivot = poss[rig.index["spine_01"]]
        head = poss[rig.index["head"]] - pivot
        want = ref_poss[rig.index["head"]] + PUTT_STILL * (poss[rig.index["head"]] - ref_poss[rig.index["head"]]) - pivot
        turn = math.degrees(math.atan2(head[u], head[v]) - math.atan2(want[u], want[v]))
        sign = 1.0 if axis[2] else -1.0  # right-handed: +z turns +x into +y, +x turns +y into +z
        back = pose.rot(axis, sign * turn)
        for j in descendants(rig, "spine_01"):
            if rots[j] is not None:
                rots[j] = back @ rots[j]
        rots = fill(rig, rots, ref_local, keep=True)
    return rots, root


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


def too_long(hip, ankle, lengths, knee=TRAIL_KNEE):
    """How far `ankle` is beyond the leg's reach with the knee bent
    `knee` degrees."""
    l1, l2 = lengths
    d = math.sqrt(l1 * l1 + l2 * l2 + 2 * l1 * l2 * math.cos(math.radians(knee)))
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


# The trail foot through the finish, as tour players finish: up on the toe
# with the sole facing away from the target, the laces turned to face it and
# the trail knee driving through beside the lead knee (the actor kept his
# trail leg nearly straight, stretched back, the foot still flat-ish).
FINISH_FRAMES = (6, 70)  # mocap frames after impact: the foot starts up, it is fully up
FINISH_YAW = 70.0  # degrees the toe turns from the ball towards the target
FINISH_PITCH = 64.0  # degrees the foot stands up on its toe (90 is vertical)
FINISH_TOE_IN = 0.12  # metres the toe slides in towards the lead foot
FINISH_KNEE = 42.0  # degrees: the least the trail knee bends at the finish
FINISH_TOE_UP = 0.015  # metres the ball of the foot rises as the toes bend


def finish_weight(f, impact):
    a, b = FINISH_FRAMES
    u = min(1.0, max(0.0, (f - impact - a) / (b - a)))
    return u * u * (3 - 2 * u)


def finish_trail_foot(rig, rest, ref_poss, ref_rots, tgt, foot, u, yaw_deg=FINISH_YAW):
    """Blends the trail ankle target and foot turn towards the finish (u 0
    to 1): the foot turns on the ball of the foot, which stays near where it
    was at address."""
    i_foot, i_ball = rig.index["foot_r"], rig.index["ball_r"]
    to_ball = rest[i_ball] - rest[i_foot]
    up = np.array([0.0, 1.0, 0.0])
    # Turn the toe towards the target about the vertical, then stand the
    # foot up about the horizontal line across it.
    yaw = pose.rot(up, yaw_deg)
    toe = yaw @ (ref_rots[i_foot] @ to_ball)
    across = pose.unit(np.cross(np.array([toe[0], 0.0, toe[2]]), up))
    fin = pose.rot(across, -FINISH_PITCH) @ yaw @ ref_rots[i_foot]
    if (fin @ to_ball)[1] > 0.0:  # stood the wrong way: toe up
        fin = pose.rot(across, FINISH_PITCH) @ yaw @ ref_rots[i_foot]
    ball = ref_poss[i_ball] + np.array([-FINISH_TOE_IN, FINISH_TOE_UP, 0.0])
    fin_tgt = ball - fin @ to_ball
    return (1.0 - u) * tgt + u * fin_tgt, pose.slerp(foot, fin, u)


def finish_trail_toe(rig, ref_rots, toe, u):
    """The trail toes laid back towards flat on the ground (turned with the
    foot) as the heel comes up; toe_limit caps the crease."""
    flat = pose.rot([0.0, 1.0, 0.0], FINISH_YAW) @ ref_rots[rig.index["ball_r"]]
    return pose.slerp(toe, flat, u)


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
    # The actor stands more upright over the ball than the golfer (tour
    # posture, swing_posture.py): his trunk turns about his own spine, so
    # applied as they are they would turn the golfer's trunk about a line
    # off his spine and swing the head 20-27 cm away from the target at the
    # top. The upper body's turns are carried onto the golfer's spine line.
    actor_spine = g @ (m_poss0[bvh.index["Neck1"]] - m_poss0[bvh.index["Hips"]])
    our_spine = ref_poss[rig.index["neck_01"]] - ref_poss[rig.index["pelvis"]]
    onto = between(pose.unit(actor_spine), pose.unit(our_spine))
    upper_body = set(descendants(rig, "spine_01"))
    # Scale: the golfer's hip height over the actor's.
    golfer_hip = ref_poss[rig.index["pelvis"]][1] - ref_poss[rig.index["foot_l"]][1]
    actor_hip = m_poss0[bvh.index["Hips"]][1] - m_poss0[bvh.index["LeftFoot"]][1]
    scale = golfer_hip / actor_hip
    hands_l = rig.index["hand_l"]
    aim = clip["take"].startswith("ft:")
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
    # The lead arm's swing-plane angle at impact (in use, measured): a
    # tracked golfer's arm needn't come back to exactly our address angle,
    # and the club's hinge reads the angle from address, so it is offset
    # from the top on (else the club releases early, then jerks back).
    arm_bias = [0.0, 0.0]
    club_roll = [None]  # the club's roll about its shaft, last frame (footage)

    def lean_of(rots):
        shaft = rots[club_j] @ club_dir
        return math.degrees(math.atan2(shaft[0], -shaft[1]))

    def run(correct):
        nonlocal arm_angle
        arm_angle = 0.0
        impact_head = np.zeros(3)
        impact_lean[0] = 0.0
        club_roll[0] = None
        out_rots, out_root = [], []
        for i, f in enumerate(frames):
            m_rots, m_poss = bvh.frame(f)
            rots = [None] * len(rig.names)
            for j, name in enumerate(rig.names):
                src = BONES.get(name)
                if src:
                    k = bvh.index[src]
                    delta = g @ m_rots[k] @ m_rots0[k].T @ g.T
                    if j in upper_body:
                        delta = onto @ delta @ onto.T
                    rots[j] = delta @ ref_rots[j]
            aim_w = backswing_weight(f, clip) if aim else 0.0
            if aim:
                # Tracked footage: the limbs point where the golfer's do
                # (a turn from address carried over would point them off by
                # however differently our golfer's arms hang at address).
                # Each limb turns from its address direction as the tracked
                # one does (the shortest turn, so the tracker's guess at the
                # limb's twist doesn't swing it about).
                for bone, (a, b) in AIM_BONES.items():
                    j = rig.index[bone]
                    d0 = g @ (m_poss0[bvh.index[b]] - m_poss0[bvh.index[a]])
                    d = g @ (m_poss[bvh.index[b]] - m_poss[bvh.index[a]])
                    if j in upper_body:
                        d0, d = onto @ d0, onto @ d
                    ours0 = ref_rots[j] @ rig.offsets[rig.index[AIM_CHILD[bone]]]
                    want = between(pose.unit(d0), pose.unit(d)) @ ours0
                    # Far from address, where the limb points itself.
                    away = math.degrees(math.acos(np.clip(np.dot(pose.unit(d0), pose.unit(d)), -1.0, 1.0)))
                    u = min(1.0, away / AIM_ABSOLUTE)
                    want = pose.unit((1.0 - u) * pose.unit(want) + u * pose.unit(d))
                    off = rig.offsets[rig.index[AIM_CHILD[bone]]]
                    have = pose.unit(rots[j] @ off)
                    want = pose.unit((1.0 - aim_w) * have + aim_w * pose.unit(want))
                    # The tracker's twist of each limb is noise (the hand's
                    # points are a few pixels apart): each bone keeps its
                    # address twist against its parent, turned the shortest
                    # way onto its direction.
                    parent = rig.parents[j]
                    base = rots[parent] @ ref_rots[parent].T @ ref_rots[j]
                    rots[j] = between(pose.unit(base @ off), want) @ base
                for s_ in "lr":
                    h, fa = rig.index[f"hand_{s_}"], rig.index[f"lowerarm_{s_}"]
                    rots[h] = rots[fa] @ ref_rots[fa].T @ ref_rots[h]
                # (The hands first, so the club keeps its turn about the
                # shaft.) The lead arm is all but straight, so which way the tracked
                # elbow bends is noise (often backwards): it bends the way
                # it does at address, carried round with the chest.
                rots = fill(rig, rots, ref_local, keep=True)
                _, p_ = rig.world(rig.locals(rots), ref_root)
                iu, il, ih = (rig.index[n] for n in ("upperarm_l", "lowerarm_l", "hand_l"))
                line = pose.unit(ref_poss[ih] - ref_poss[iu])
                e0 = ref_poss[il] - ref_poss[iu]
                e0 = e0 - line * np.dot(e0, line)
                ch = rig.index["spine_03"]
                reach_pole(rig, rots, p_, "upperarm_l", "lowerarm_l", "hand_l", p_[ih], rots[ch] @ ref_rots[ch].T @ e0)
            if clip.get("glance"):
                glance(rig, rots, i / MOCAP_FPS, clip["glance"])
            root = ref_root + scale * (g @ (m_poss[bvh.index["Hips"]] - m_poss0[bvh.index["Hips"]]))
            if not clip["putt"]:
                if clip.get("tour", True):
                    rots, root = tour_backswing(rig, rots, root, ref_root, ref_local, ref_rots, ref_poss,
                                                backswing_weight(f, clip))
            elif "impact" in clip:
                rots, root = still_putt(rig, rots, root, ref_root, ref_local, ref_rots, ref_poss)
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
                keep = PUTT_STILL if clip["putt"] and "impact" in clip else 1.0
                if aim:
                    keep = 0.0  # tracked feet slide about; they stay planted (the finish turns the trail one)
                target = ref_poss[rig.index[f"foot_{s}"]] + keep * scale * (g @ (m_poss[k] - m_poss0[k]))
                foot = ref_rots[rig.index[f"foot_{s}"]] if aim else rots[rig.index[f"foot_{s}"]]
                if s == "l" and not clip["putt"] and "impact" in clip:
                    # The lead foot stays planted (the actor's heel comes up
                    # 7 cm at the top and 5 cm at the finish): only a little
                    # of its rise is kept, and the sole lies flat as at
                    # address, still turning as the actor's does.
                    rise = target[1] - ref_poss[rig.index["foot_l"]][1]
                    target[1] = ref_poss[rig.index["foot_l"]][1] + LEAD_HEEL * rise
                    to_toe = rest[rig.index["ball_l"]] - rest[rig.index["foot_l"]]
                    v, v0 = foot @ to_toe, ref_rots[rig.index["foot_l"]] @ to_toe
                    flat = np.array([v[0], 0.0, v[2]])
                    if np.linalg.norm(flat) > 1e-6:
                        want = pose.unit(flat) * math.hypot(v0[0], v0[2]) + np.array([0.0, v0[1], 0.0])
                        foot = between(v, want) @ foot
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
                    u = finish_weight(f, clip["impact"])
                    knee = TRAIL_KNEE + u * (FINISH_KNEE - TRAIL_KNEE)
                    if u > 0.0:
                        yaw_deg = FINISH_YAW
                        if aim:
                            # The foot turns with a tracked golfer's hips.
                            pel = rig.index["pelvis"]
                            fwd = rots[pel] @ ref_rots[pel].T @ np.array([0.0, 0.0, -1.0])
                            hip_yaw = math.degrees(math.atan2(-fwd[0], -fwd[2]))
                            yaw_deg = max(FINISH_YAW, min(100.0, hip_yaw))
                        tgt, foot = finish_trail_foot(rig, rest, ref_poss, ref_rots, tgt, foot, u, yaw_deg)
                    ball = tgt + foot @ (rest[rig.index["ball_r"]] - rest[rig.index["foot_r"]])
                    side = pose.unit(np.cross(ball - tgt, [0.0, 1.0, 0.0]))
                    for _ in range(12):
                        if too_long(hip, tgt, legs["r"], knee) <= 1e-4:
                            break
                        lift = pose.rot(side, 4.0)
                        if (ball + lift @ (tgt - ball))[1] < tgt[1]:
                            lift = lift.T
                        tgt, foot = ball + lift @ (tgt - ball), lift @ foot
                    # Still out of reach: the toe drags round towards the hips.
                    for _ in range(6):
                        excess = too_long(hip, tgt, legs["r"], knee)
                        if excess <= 1e-4:
                            break
                        pull = np.array([hip[0] - tgt[0], 0.0, hip[2] - tgt[2]])
                        tgt = tgt + pose.unit(pull) * min(2.0 * excess, np.linalg.norm(pull))
                    targets["r"] = [tgt, foot]
            for s in "lr":
                target, foot = targets[s]
                if s == "r" and not clip["putt"] and "impact" in clip and f > clip["impact"]:
                    # Through the finish the trail knee drives at the target,
                    # not out to the side as the actor's bend plane has it.
                    u = finish_weight(f, clip["impact"])
                    a, b = poss[rig.index["thigh_r"]], poss[rig.index["calf_r"]]
                    own = pose.unit(b - a - pose.unit(target - a) * np.dot(b - a, pose.unit(target - a)))
                    drive = np.array([-1.0, 0.0, -0.35])
                    if aim:
                        # A tracked golfer's hips turn further than the
                        # actor's: the knee drives where the hips face.
                        pel = rig.index["pelvis"]
                        drive = rots[pel] @ ref_rots[pel].T @ np.array([0.0, 0.0, -1.0])
                        drive = np.array([drive[0], 0.0, drive[2]])
                    pole = pose.unit((1.0 - u) * own + u * pose.unit(drive))
                    reach_pole(rig, rots, poss, "thigh_r", "calf_r", "foot_r", target, pole)
                    rots[rig.index["ball_r"]] = finish_trail_toe(rig, ref_rots, rots[rig.index["ball_r"]], u)
                else:
                    two_bone(rig, rots, poss, f"thigh_{s}", f"calf_{s}", f"foot_{s}", target)
                rots[rig.index[f"foot_{s}"]] = foot
            rots = fill(rig, rots, ref_local, keep=True)
            rots, poss = rig.world(rig.locals(rots), root)
            if not clip["putt"] and "top" in clip:
                arm = plane_dir(poss[hands_l] - poss[rig.index["upperarm_l"]], plane)
                step = math.degrees(math.atan2(np.dot(np.cross(arm0, arm), plane), np.dot(arm0, arm))) - arm_angle
                arm_angle += (step + 180.0) % 360.0 - 180.0  # unwrapped
                if f == clip.get("impact"):
                    arm_bias[1] = arm_angle
                u = 0.0 if f <= clip["top"] else min(1.0, (f - clip["top"]) / max(1, clip["impact"] - clip["top"]))
                a = arm_angle - arm_bias[0] * u * u * (3 - 2 * u)
                if f <= clip["top"]:
                    club = a + ramp(a, HINGE_BACK)
                elif f <= clip["impact"]:
                    club = a + ramp(a, HINGE_DOWN)
                else:
                    club = max(a - ramp(-a, HINGE_FOLLOW), FINISH_LIMIT)
                want = pose.rot(plane, club) @ shaft0
                rots[hands_l] = between(rots[club_j] @ club_dir, want) @ rots[hands_l]
                rots = fill(rig, rots, ref_local, keep=True)
                rots, poss = rig.world(rig.locals(rots), root)
            if not clip["putt"] and "impact" in clip:
                # Shoulders open to the target at impact (the actor's are
                # nearly square): the chest turns under the arms, the hands
                # and club staying where they were, the head on the ball.
                w = impact_weight(f, clip["impact"]) * IMPACT_OPEN * (0.0 if aim else 1.0)
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
            if aim:
                # The trail elbow stays where the tracked arm put it (two_bone
                # could fold it the other way, up over the head at the top)...
                elbow = poss[rig.index["lowerarm_r"]] - poss[rig.index["upperarm_r"]]
                # ...but kept pointing down, as a tour trail elbow does (the
                # tracker's elbow depth is a guess; up, the wrist breaks).
                elbow = pose.unit(elbow) + np.array([0.0, -TRAIL_ELBOW_DOWN, 0.0])
                # The tracker can't see the forearms roll the club about its
                # shaft: the roll that keeps both wrists in their range,
                # moving smoothly from frame to frame.
                shaft = rots[club_j] @ club_dir
                best = None
                for deg in range(-CLUB_ROLL, CLUB_ROLL + 1, 5):
                    last = deg if club_roll[0] is None else club_roll[0]
                    if abs(deg - last) > 15:
                        continue
                    R = pose.rot(shaft, deg)
                    trial = list(rots)
                    trial[hands_l] = R @ rots[hands_l]
                    reach_pole(rig, trial, poss, "upperarm_r", "lowerarm_r", "hand_r",
                               poss[hands_l] + trial[hands_l] @ grip_r, elbow)
                    trial[rig.index["hand_r"]] = trial[hands_l] @ hand_r_in_l
                    cost = 0.02 * (deg - last) ** 2 + 0.0005 * deg * deg
                    for sd in "lr":
                        m = anatomy.arm_angles(rig, sd, trial[rig.index[f"upperarm_{sd}"]],
                                               trial[rig.index[f"lowerarm_{sd}"]], trial[rig.index[f"hand_{sd}"]])
                        for k in ("wrist_flex", "wrist_dev"):
                            cost += anatomy._excess(m[k], anatomy.limit_of(k)) ** 2
                    if best is None or cost < best[0]:
                        best = (cost, deg)
                club_roll[0] = best[1]
                rots[hands_l] = pose.rot(shaft, best[1]) @ rots[hands_l]
            target = poss[hands_l] + rots[hands_l] @ grip_r
            hand = rots[hands_l] @ hand_r_in_l
            if aim:
                reach_pole(rig, rots, poss, "upperarm_r", "lowerarm_r", "hand_r", target, elbow)
            else:
                two_bone(rig, rots, poss, "upperarm_r", "lowerarm_r", "hand_r", target)
            rots[rig.index["hand_r"]] = hand
            rots = fill(rig, rots, ref_local, keep=True)
            out_rots.append(rig.locals(rots))
            out_root.append(root)
        return out_rots, out_root, impact_head

    correct = np.zeros(3)
    out_rots, out_root, head = run(correct)
    if aim and "impact" in clip:
        arm_bias[0] = arm_bias[1]
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


# The toes bend at the ball of the foot at most this far: a golf shoe's
# sole creases there by 40 to 50 degrees, up on the toes at the finish or
# down in the read. The actor's toe bones reached 102 degrees at the
# finish and 55 in the read, and the shoe crumpled.
TOE_MAX = 45.0


def toe_limit(m):
    a = math.degrees(math.acos(float(np.clip((np.trace(m) - 1.0) / 2.0, -1.0, 1.0))))
    return m if a <= TOE_MAX else pose.slerp(np.eye(3), m, TOE_MAX / a)


def write_clip(glb, rig, name, times, rots, root, filtered=True, moves=None):
    """`moves`: joint index to its translations, for joints that move in
    their parent (the club drawn from the bag in the right hand)."""
    t_acc = glb.add(times, minmax=True)
    t_one = None
    samplers, channels = [], []
    toes = {rig.index[f"ball_{s}"] for s in "lr"}
    for j, node in enumerate(rig.joints):
        q = np.array([pose.quat(toe_limit(r[j]) if j in toes else r[j]) for r in rots])
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
    for j, values in (moves or {}).items():
        samplers.append({"input": t_acc, "output": glb.add(np.asarray(values, np.float32)), "interpolation": "LINEAR"})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": rig.joints[j], "path": "translation"}})
    glb.set_animation({"name": name, "samplers": samplers, "channels": channels})


def club_still(glb, rig):
    """Every clip but the ones that move the club in the hand (pull_club)
    holds it at its rest offset with a one-key translation channel: Godot
    keeps a track's last value in clips without that track, so a pull cut
    short would leave the club out of the hand."""
    node = rig.joints[rig.index["club"]]
    rest = np.asarray([rig.offsets[rig.index["club"]]], np.float32)
    for anim in glb.doc["animations"]:
        if any(ch["target"]["node"] == node and ch["target"]["path"] == "translation" for ch in anim["channels"]):
            continue
        t = glb.add(np.zeros(1, np.float32), minmax=True)
        anim["samplers"].append({"input": t, "output": glb.add(rest), "interpolation": "LINEAR"})
        anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": node, "path": "translation"}})


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
# The spine joints all take the trunk's direction (spine_01 to the neck,
# the actor's LowerBack to Neck1): the golfer's three short segments rest
# tilted 8 deg forward, 12 deg back and 7 deg forward, and aiming each one
# at the actor's straight spine bent them the other way, a zigzag of
# about 20 deg a joint (the lower back arched, the chest folded forward
# and the upper chest bent back) in every standing clip.
TRUNK = ("spine_01", "neck_01", "LowerBack", "Neck1")
BONE_DIRS = {
    "pelvis": (None, None), "spine_01": "trunk", "spine_02": "trunk",
    "spine_03": "trunk", "neck_01": ("head", "Head"), "head": (None, None),
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
    "walk": dict(take="69_01", start=205, end=355, facing=(0.0, 0.0, -1.0), in_place=True, carry=True, loop=0.25,
                 carry_head=0.42),  # CARRY_WALK_HEIGHT
    # An eagle: both arms up to the crowd, club raised, and back down. The
    # actor went on to lean far back with a hand on his hip and swing an arm
    # across his chest, which read as theatre, not golf, so only his arms-up
    # part is kept (frames lists the mocap frames played).
    "celebrate": dict(take="79_69", start=80, end=175, facing=(-0.7, 0.0, -0.7), carry=True,
                      frames=(list(range(80, 176)) + list(range(175, 150, -1)) + list(range(150, 176))
                              + list(range(175, 79, -1)))),
    "upset": dict(take="79_74", start=450, end=760, facing=(-0.7, 0.0, -0.7), carry=True),  # hands on head
    # A birdie: the actor's happy bounce at the knees, with the right fist
    # pumped twice in front of the chest (PUMP_KEYS) and the club held low.
    "fist_pump": dict(take="79_69", start=552, end=700, facing=(-0.7, 0.0, -0.7), carry=True, pump=True),
    # A short putt missed: the head drops and a hand goes to the face.
    "slump": dict(take="79_71", start=80, end=470, facing=(-0.7, 0.0, -0.7), carry=True),
    # Standing at ease: weight shifts and breathing (the caddie, the
    # waiting golfers, the gallery). Upright (STAND_UPRIGHT).
    "idle": dict(take="77_02", start=100, end=740, facing=(0.0, 0.0, -1.0), loop=0.5, upright=True),
    # Standing behind the ball looking down the target line before a full
    # shot, club in hand, as tour players do before walking in.
    "survey": dict(take="77_02", start=100, end=400, facing=(0.0, 0.0, -1.0), upright=True, carry=True),
    # Taking the club out of the stand bag at his right front (PULL_KEYS),
    # standing at ease, before walking round behind the ball.
    "pull_club": dict(take="77_02", start=420, end=720, facing=(0.0, 0.0, -1.0), upright=True, carry=True,
                      pull=True),
    # "Fore!": a full shot heading well offline. The free (right) arm points
    # after the ball, the head turned with it, the club low in the left
    # hand (POINT_KEYS), as tour players do while the ball is in the air.
    "fore_right": dict(take="77_02", start=100, end=400, facing=(-0.7, 0.0, -0.7), upright=True, carry=True,
                       point=(-0.55, 0.3, -0.78)),
    "fore_left": dict(take="77_02", start=100, end=400, facing=(-0.95, 0.0, 0.3), upright=True, carry=True,
                      point=(-0.6, 0.3, 0.74)),
    # Crouching behind the ball to read a putt, putter in hand.
    # The take is the actor bending to the floor (back ~70 deg forward,
    # head at the ground); read_crouch turns it into a golfer's read.
    "read": dict(take="77_08", start=150, end=460, facing=(0.0, 0.0, -1.0), carry=True, read=True),
}
# Standing upright, as photos of people waiting on a tee show: the actor's
# feet come out 2.6 cm above the ground (his ankle joints sit higher than
# the golfer's) and 30 cm apart, which bent the golfer's knees 22-28 deg and
# splayed them. An upright stand keeps the soles on the ground, the ankles
# a little wider than the hips (STAND_GAP between ankle joints), the
# knees almost straight (the leg at STAND_REACH of its full length, about
# 8 deg) and the eyes level, a touch down (STAND_GAZE).
STAND_GAP = 0.24
STAND_REACH = 0.9975
STAND_GAZE = -6.0
# Reading a putt, as photos of tour players crouched behind the ball show:
# a deep squat on the balls of the feet (the heels up READ_HEEL), the hip
# joints READ_HIP above the ankles and READ_BACK behind them (over the
# heels, not sat back on a chair), the knees forward over the toes and a
# touch apart (READ_KNEE_OUT), the pelvis tipped READ_PELVIS and the back
# rounded evenly, READ_SPINE at each spine joint (no hollow in the lower
# back), the forearms by the knees with both hands on the putter's grip
# and its head resting on the green in front, and the eyes down the line
# to the hole (READ_GAZE). READ_SWAY keeps that share of the actor's bob
# and lean so the hold breathes.
READ_HIP = 0.30
READ_BACK = 0.07
READ_KNEE_OUT = 0.3
READ_PELVIS = 24.0
READ_SPINE = 8.0
READ_HEEL = 22.0
READ_GAZE = -14.0
READ_HANDS_AHEAD = 0.03
READ_SOLE_REACH = 0.795  # club joint to the putter's sole along the shaft
READ_SWAY = 0.3
READ_ACTOR_LEAN = 72.0  # the actor's mean lean while down, degrees
CARRY_HEAD_HEIGHT = 0.15  # the club head's height when carried, metres
# Walking, tour players hold the club clear of the turf, the shaft nearly
# level out in front of them, rather than letting the head trail low as a
# walking stick (which read as dragging it along the ground).
CARRY_WALK_HEIGHT = 0.42  # the walk clip's carry_head
CARRY_REACH = 1.16  # left hand joint to the driver's sole (the rebuilt clubs, PR #164)


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


# (seconds, share of the way to the point): up quickly, held while the
# ball flies, then down.
POINT_KEYS = [(0.0, 0.0), (0.35, 1.0), (1.6, 1.0), (2.2, 0.0)]
POINT_REACH = 0.97  # of the arm's length: nearly straight


def fore_point(rig, rots, poss, t, direction, local0):
    """The right arm pointing along `direction` (POINT_KEYS), the head
    turned to look the same way."""
    for (t0, a), (t1, b) in zip(POINT_KEYS, POINT_KEYS[1:]):
        if t <= t1:
            u = float(np.clip((t - t0) / (t1 - t0), 0.0, 1.0))
            w = a + (b - a) * u * u * (3 - 2 * u)
            break
    else:
        w = POINT_KEYS[-1][1]
    if w <= 0.0:
        return rots
    up = np.array([0.0, 1.0, 0.0])
    shoulder, elbow, hand = (poss[rig.index[n]] for n in ("upperarm_r", "lowerarm_r", "hand_r"))
    arm = np.linalg.norm(elbow - shoulder) + np.linalg.norm(hand - elbow)
    target = hand * (1 - w) + (shoulder + direction * arm * POINT_REACH) * w
    reach_pole(rig, rots, poss, "upperarm_r", "lowerarm_r", "hand_r", target, -up)
    rots[rig.index["hand_r"]] = rots[rig.index["lowerarm_r"]]
    # The head after the ball: half the turn in the neck, half in the head.
    face = rots[rig.index["head"]] @ np.array([0.0, 0.0, -1.0])
    turn = math.degrees(math.atan2(face[2], face[0]) - math.atan2(direction[2], direction[0]))
    turn = (turn + 180.0) % 360.0 - 180.0
    for name in ("neck_01", "head"):
        spin = pose.rot(up, 0.5 * w * turn)
        for j in descendants(rig, name):
            if rots[j] is not None:
                rots[j] = spin @ rots[j]
    return fill(rig, rots, local0, keep=True)


# Taking a club from the stand bag, as tour footage shows: the clubs stand
# heads up, so the golfer steps up to the bag (at his right front, facing
# the way it leans), takes a club by the shaft under its head with the right
# hand, draws it up along the bag until the grip clears the cuff, swings the
# grip across to the left hand, which takes it, and lets go with the right;
# the club then drops head down into the carry. Golfer frame: the bag's foot
# at PULL_BAG_FOOT, its top leaning forward (StandBag.MOUTH: 0.82 m up,
# 0.30 m back on its legs). The game stands the golfer there
# (FreeGolfer.PULL_BAG_FOOT and PULL_GRAB, kept equal).
PULL_BAG_FOOT = np.array([0.40, 0.0, 0.06])
PULL_BAG_TOP = np.array([0.0, 0.82, -0.30])
PULL_HOLD_ABOVE = 0.10  # the right hand on the shafts this far above the cuff
PULL_HOLD_NEAR = 0.05  # a club in the top's near side, towards the golfer
PULL_HOLD = 0.62  # the right hand this far up the shaft from the left's grip
# Where the left hand takes the grip, the club across the body (grip low
# at the left, head up to the right), in the golfer frame.
PULL_CATCH_AT = np.array([-0.08, 0.98, -0.28])
PULL_CATCH_DIR = np.array([0.6, 0.6, -0.35])
# Then the head comes round in front of him (clear of the bag at his right)
# before it drops into the carry: (seconds, share of the turn to the front).
PULL_FRONT_DIR = np.array([0.05, 0.25, -1.0])
PULL_TURN = [(1.9, 0.0), (2.2, 1.0)]
# (seconds, metres drawn up the bag, share of the swing across to the catch)
PULL_KEYS = [(0.62, 0.0, 0.0), (0.75, 0.0, 0.0), (1.35, 0.72, 0.0), (1.55, 0.80, 0.25), (1.75, 0.80, 1.0)]
PULL_GRAB = 0.62  # the right hand closes on the shaft: the club shows from here
PULL_CATCH = 1.75  # the left hand closes on the grip
# (seconds, weight) of the right hand on the club, the left hand reaching
# for the grip (then carrying it, easing into the carry pose by the end).
PULL_RIGHT = [(0.0, 0.0), (0.5, 1.0), (1.9, 1.0), (2.3, 0.0)]
PULL_LEFT = [(0.0, 0.0), (1.45, 0.0), (1.75, 1.0), (2.2, 1.0), (2.5, 0.0)]
PULL_LEAN = 18.0  # degrees the trunk bends to the bag while the hand is down
PULL_LOOK = 0.8  # share of the head's turn to the hands


def smooth_keys(keys, t):
    """Values at t through (time, *values) keys, eased in and out."""
    if t <= keys[0][0]:
        return keys[0][1:]
    if t >= keys[-1][0]:
        return keys[-1][1:]
    i = max(j for j in range(len(keys) - 1) if keys[j][0] <= t)
    u = (t - keys[i][0]) / (keys[i + 1][0] - keys[i][0])
    u = u * u * (3 - 2 * u)
    return tuple(a + (b - a) * u for a, b in zip(keys[i][1:], keys[i + 1][1:]))


def pull_club_at(t):
    """The club joint (the left hand's grip) and the shaft's direction (grip
    to head) while the right hand has it, in the golfer frame."""
    axis = pose.unit(PULL_BAG_TOP)
    hold0 = PULL_BAG_FOOT + PULL_BAG_TOP + axis * PULL_HOLD_ABOVE + np.array([-PULL_HOLD_NEAR, 0.0, 0.0])
    lift, swing = smooth_keys(PULL_KEYS, t)
    in_bag = hold0 + axis * lift - axis * PULL_HOLD
    across = pose.unit(PULL_CATCH_DIR)
    shaft = pose.unit(axis * (1 - swing) + across * swing)
    grip = in_bag * (1 - swing) + PULL_CATCH_AT * swing
    return grip, shaft


def pull_club(rig, rots, root, t, club_dir, local0, grip_local, right_rel):
    """Takes the club from the bag (PULL_KEYS) over the carry pose `rots`.
    Returns the world rotations and the club joint's translation in the
    left hand (its rest offset once the left hand holds it)."""
    up = np.array([0.0, 1.0, 0.0])
    c, hl, hr = rig.index["club"], rig.index["hand_l"], rig.index["hand_r"]
    (wr,) = smooth_keys(PULL_RIGHT, t)
    (wl,) = smooth_keys(PULL_LEFT, t)
    held = t < PULL_CATCH
    # Fingers: the right closed on the shaft while it holds, the left open
    # until it takes the grip.
    local = list(local0)
    for j, name in enumerate(rig.names):
        if name.split("_")[0] in ("index", "middle", "ring", "pinky", "thumb"):
            if name.endswith("_r"):
                local[j] = pose.slerp(np.eye(3), grip_local[j], 0.35 + 0.65 * wr)
            elif held:
                local[j] = pose.slerp(np.eye(3), grip_local[j], 0.35 + 0.65 * wl)
    base = fill(rig, list(rots), local, keep=True)
    pose_ = list(base)
    # Bend at the waist towards the bag while the hand is down at its top.
    lift = smooth_keys(PULL_KEYS, t)[0]
    down = float(np.clip(1.0 - lift / 0.45, 0.0, 1.0)) * wr * (1.0 if held else 0.0)
    hold0 = PULL_BAG_FOOT + PULL_BAG_TOP
    lean_axis = pose.unit(np.cross(up, pose.unit(hold0 * np.array([1.0, 0.0, 1.0]))))
    bend = pose.rot(lean_axis, PULL_LEAN * down)
    for j in descendants(rig, "spine_01"):
        pose_[j] = bend @ pose_[j]
    _, poss = rig.world(rig.locals(pose_), root)
    # The club: where the right hand has it, or in the left hand; turned
    # from its rest (identity) so it doesn't roll with the actor.
    if held:
        grip_at, shaft = pull_club_at(max(t, PULL_GRAB))
    else:
        grip_at, shaft = PULL_CATCH_AT, pose.unit(PULL_CATCH_DIR)
    club_rot = between(club_dir, shaft)
    catch_rot = between(club_dir, pose.unit(PULL_CATCH_DIR))
    (turn,) = smooth_keys(PULL_TURN, t)
    if turn > 0.0:
        catch_rot = pose.slerp(catch_rot, between(club_dir, pose.unit(PULL_FRONT_DIR)), turn)
    arms = list(pose_)
    if wr > 1e-4:
        rel_p, rel_r = right_rel
        # Letting go, the hand stays by where it held the club.
        g, cr = (grip_at, club_rot) if held else (PULL_CATCH_AT, catch_rot)
        arms[hr] = cr @ rel_r
        want = g + cr @ rel_p
        for _ in range(3):
            _, poss = rig.world(rig.locals(arms), root)
            keep = arms[hr]
            reach_pole(rig, arms, poss, "upperarm_r", "lowerarm_r", "hand_r", want, np.array([1.0, -0.6, 0.4]))
            arms[hr] = keep
            arms = fill(rig, arms, local, keep=True)
            arms[hr] = keep
    if wl > 1e-4:
        g, cr = PULL_CATCH_AT, catch_rot
        arms[hl] = cr @ grip_local[c].T
        want = g - arms[hl] @ rig.offsets[c]
        for _ in range(3):
            _, poss = rig.world(rig.locals(arms), root)
            keep = arms[hl]
            reach_pole(rig, arms, poss, "upperarm_l", "lowerarm_l", "hand_l", want, np.array([-1.0, -0.6, 0.4]))
            arms[hl] = keep
            arms = fill(rig, arms, local, keep=True)
            arms[hl] = keep
    out = list(pose_)
    for s_, w in (("r", wr), ("l", wl)):
        for name in (f"upperarm_{s_}", f"lowerarm_{s_}", f"hand_{s_}"):
            j = rig.index[name]
            out[j] = pose.slerp(pose_[j], arms[j], w)
    out = fill(rig, out, local, keep=True)
    # Eyes on the work: the right hand, then the grip coming to the left.
    _, poss = rig.world(rig.locals(out), root)
    focus = poss[hr] if t < 1.5 else grip_at
    look_w = PULL_LOOK * float(np.clip((2.3 - t) / 0.4, 0.0, 1.0)) * float(np.clip(t / 0.3, 0.0, 1.0))
    eye = poss[rig.index["head"]]
    look = pose.unit(focus - eye)
    for name, share in (("neck_01", 0.45), ("head", 1.0)):
        face = out[rig.index["head"]] @ np.array([0.0, 0.0, -1.0])
        angle = math.degrees(math.acos(float(np.clip(np.dot(face, look), -1.0, 1.0))))
        if angle < 1e-3:
            continue
        turn = pose.rot(pose.unit(np.cross(face, look)), angle * share * look_w)
        for k in descendants(rig, name):
            out[k] = turn @ out[k]
    out = fill(rig, out, local, keep=True)
    # The club where the right hand holds it; its own joint moves in the
    # left hand's frame for that (a translation channel).
    if held:
        _, poss = rig.world(rig.locals(out), root)
        out[c] = club_rot
        return out, out[hl].T @ (grip_at - poss[hl])
    return out, rig.offsets[c].copy()


def knee_pole(rig, rots):
    """Where a knee bends: forward from the hips. Keeping the actor's bend
    plane (two_bone) let a nearly straight knee flip and bend backwards,
    up to 30 deg in the idle and celebrate clips."""
    fwd = rots[rig.index["pelvis"]] @ np.array([0.0, 0.0, -1.0])
    fwd[1] = 0.0
    return pose.unit(fwd)


def stand_upright(rig, poss, root, targets, narrow, lift, ankle_rest):
    """Feet on the ground STAND_GAP apart and the hips at the height that
    leaves the straighter leg at STAND_REACH of its length (STAND_GAP)."""
    mid = (targets["l"] + targets["r"]) / 2
    out = {}
    for s, t in targets.items():
        t = t.copy()
        t[[0, 2]] = mid[[0, 2]] + (t[[0, 2]] - mid[[0, 2]]) * narrow
        t[1] = max(ankle_rest, t[1] - lift)
        out[s] = t
    drop = -1e9
    for s in ("l", "r"):
        hip, knee, ankle = (poss[rig.index[n]] for n in (f"thigh_{s}", f"calf_{s}", f"foot_{s}"))
        reach = STAND_REACH * (np.linalg.norm(knee - hip) + np.linalg.norm(ankle - knee))
        d = hip - out[s]
        flat = d[0] ** 2 + d[2] ** 2
        drop = max(drop, d[1] - math.sqrt(max(reach * reach - flat, 0.0)))
    root = np.array(root, dtype=float)
    root[1] -= drop
    return out, root


def level_gaze(rig, rots, local0, gaze=STAND_GAZE):
    """Turns the neck and head so the face looks `gaze` degrees below
    level: the neck takes half, the head the rest."""
    rots = list(rots)
    for name, share in (("neck_01", 0.5), ("head", 1.0)):
        fwd = rots[rig.index["head"]] @ np.array([0.0, 0.0, -1.0])
        pitch = math.degrees(math.atan2(fwd[1], math.hypot(fwd[0], fwd[2])))
        turn = pose.rot(np.cross(fwd, [0.0, 1.0, 0.0]), (gaze - pitch) * share)
        rots[rig.index[name]] = turn @ rots[rig.index[name]]
        if name == "neck_01":
            rots[rig.index["head"]] = turn @ rots[rig.index["head"]]
    return fill(rig, rots, local0, keep=True)


def crouch_weight(hip_drop):
    """0 standing to 1 down in the read, from how far the actor's hips have
    dropped (in units of his standing hip height)."""
    w = float(np.clip((hip_drop - 0.05) / 0.2, 0.0, 1.0))
    return w * w * (3 - 2 * w)


def read_crouch(rig, rots, root, targets, facing, w, actor_lean):
    """The actor's bend to the floor reshaped into a golfer reading a putt
    (READ_*), by w: the pelvis and spine set to the read's even curve (a
    READ_SWAY share of the actor's own lean kept, so the hold breathes)
    and the hips over the heels at READ_HIP; the legs are bent to the feet
    afterwards (read_legs)."""
    up = np.array([0.0, 1.0, 0.0])
    side = pose.unit(np.cross(up, facing))  # rot(side, +a) tips up towards facing
    local = rig.locals(rots)
    sway = READ_SWAY * (actor_lean - READ_ACTOR_LEAN) / 4.0
    yaw = between(np.array([0.0, 0.0, -1.0]), facing)
    pel = rig.index["pelvis"]
    want = pose.rot(side, READ_PELVIS + sway) @ yaw
    local[pel] = pose.slerp(local[pel], want, w)
    bend = pose.rot([-1.0, 0.0, 0.0], READ_SPINE + sway)  # in the body's own axes
    for name in ("spine_01", "spine_02", "spine_03"):
        local[rig.index[name]] = pose.slerp(local[rig.index[name]], bend, w)
    rots, poss = rig.world(local, root)
    rots = list(rots)
    mid = (targets["l"] + targets["r"]) / 2
    want_root = mid - facing * READ_BACK
    want_root[1] = min(targets["l"][1], targets["r"][1]) + READ_HIP
    hip = (poss[rig.index["thigh_l"]] + poss[rig.index["thigh_r"]]) / 2
    root = np.array(root, dtype=float)
    return rots, root + (want_root - hip) * w


def read_legs(rig, rots, root, targets, facing, w=1.0):
    """Knees forward over the toes, a touch apart (READ_KNEE_OUT), and
    the heels lifted READ_HEEL by w about the balls of the feet."""
    _, poss = rig.world(rig.locals(rots), root)
    up = np.array([0.0, 1.0, 0.0])
    side = pose.unit(np.cross(up, facing))
    mid = (poss[rig.index["thigh_l"]] + poss[rig.index["thigh_r"]]) / 2
    for s in ("l", "r"):
        out = poss[rig.index[f"thigh_{s}"]] - mid
        out[1] = 0.0
        out = pose.unit(out)
        foot = rots[rig.index[f"foot_{s}"]]
        ball = targets[s] + foot @ rig.offsets[rig.index[f"ball_{s}"]]
        tip = pose.rot(side, READ_HEEL * w)
        ankle = ball - tip @ (ball - targets[s])
        reach_pole(rig, rots, poss, f"thigh_{s}", f"calf_{s}", f"foot_{s}", ankle, facing + out * READ_KNEE_OUT)
        rots[rig.index[f"foot_{s}"]] = tip @ foot
        # The toes stay flat on the green.
        b = rig.index[f"ball_{s}"]
        rots[b] = tip.T @ rots[b] if rots[b] is not None else None
    return rots


def read_hands(rig, rots, root, facing, club_dir, ground, putt_grip):
    """The left hand on the putter's grip just in front of the knees, its
    head resting on the green ahead (READ_SOLE_REACH from the club joint
    down the shaft), and the right hand below it on the grip as at the
    putting address (putt_grip: the right hand in the club's frame)."""
    rots = list(rots)
    up = np.array([0.0, 1.0, 0.0])
    _, poss = rig.world(rig.locals(rots), root)
    knees = (poss[rig.index["calf_l"]] + poss[rig.index["calf_r"]]) / 2
    side = pose.unit(np.cross(up, facing))

    def reach(s, at):
        out = side if np.dot(side, poss[rig.index[f"upperarm_{s}"]] - poss[rig.index["spine_03"]]) > 0 else -side
        reach_pole(rig, rots, poss, f"upperarm_{s}", f"lowerarm_{s}", f"hand_{s}", at, out - up * 0.5)
        return rig.world(rig.locals(rots), root)[1]

    poss = reach("l", knees + facing * READ_HANDS_AHEAD + up * 0.02)
    c = rig.index["club"]
    drop = float(np.clip((poss[c][1] - ground) / READ_SOLE_REACH, 0.2, 1.0))
    shaft = facing * math.sqrt(1 - drop * drop) - up * drop
    turn = between(rots[c] @ club_dir, shaft)
    for k in descendants(rig, "hand_l"):
        rots[k] = turn @ rots[k]
    _, poss = rig.world(rig.locals(rots), root)
    offset, rel = putt_grip
    poss = reach("r", poss[c] + rots[c] @ offset)
    rots[rig.index["hand_r"]] = rots[c] @ rel
    return rots


def retarget_stand(glb, rig, clip, cache):
    bvh = load_take(clip["take"], cache)
    fps = MOCAP_FPS
    start, end = clip["start"], clip["end"]
    frames = clip.get("frames") or list(range(start, end + 1))
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
    for name, dirs in BONE_DIRS.items():
        j, k = rig.index[name], bvh.index[BONES[name]]
        child, actor_child = (None, None) if dirs == "trunk" else dirs
        if dirs == "trunk":
            d0 = rest[rig.index[TRUNK[1]]] - rest[rig.index[TRUNK[0]]]
            d1 = g @ (m_poss0[bvh.index[TRUNK[3]]] - m_poss0[bvh.index[TRUNK[2]]])
        elif child is None:
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
            if clip.get("point") and name.endswith("_r"):
                # The index finger out, the others curled in.
                curl = {"index": 0.0, "thumb": 1.0}.get(name.split("_")[0], 2.6)
            relaxed[j] = pose.slerp(np.eye(3), grip_local[j], curl)
    relaxed[rig.index["club"]] = grip_local[rig.index["club"]]  # how it sits in the hand
    club_dir = club_direction(glb, rig)
    facing = pose.unit(np.array(clip["facing"], dtype=float))
    if clip.get("read"):
        # The right hand on the putter as at the putting address.
        p_local, p_root = rig.sample(glb, "ref_address_putt")
        p_rots, p_poss = rig.world(p_local, p_root)
        c, hr = rig.index["club"], rig.index["hand_r"]
        read_held = [c] + [j for j, n in enumerate(rig.names) if n.split("_")[0] in ("index", "middle", "ring", "pinky", "thumb")]
        putt_grip = (p_rots[c].T @ (p_poss[hr] - p_poss[c]), p_rots[c].T @ p_rots[hr])

    out_rots, out_root = [], []
    club_moves = []
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
        targets = {s: place(m_poss[bvh.index[actor]]) for s, actor in (("l", "LeftFoot"), ("r", "RightFoot"))}
        if clip.get("upright"):
            if i == 0:
                gap0 = np.linalg.norm((targets["l"] - targets["r"])[[0, 2]])
                lift0 = min(targets["l"][1], targets["r"][1]) - ankle_rest
            targets, root = stand_upright(rig, poss, root, targets, STAND_GAP / gap0, lift0, ankle_rest)
            _, poss = rig.world(rig.locals(rots), root)
        if clip.get("read"):
            trunk = m_poss[bvh.index["Neck"]] - m_poss[bvh.index["Hips"]]
            actor_lean = math.degrees(math.acos(float(np.clip(pose.unit(trunk)[1], -1.0, 1.0))))
            foot0 = m_poss0[bvh.index["LeftFoot"]][1]
            crouch = crouch_weight((hips0[1] - m_poss[bvh.index["Hips"]][1]) / (hips0[1] - foot0))
            rots, root = read_crouch(rig, rots, root, targets, facing, crouch, actor_lean)
            _, poss = rig.world(rig.locals(rots), root)
            rots = read_legs(rig, rots, root, targets, facing, crouch)
        else:
            for s in ("l", "r"):
                foot = rots[rig.index[f"foot_{s}"]]
                reach_pole(rig, rots, poss, f"thigh_{s}", f"calf_{s}", f"foot_{s}", targets[s], knee_pole(rig, rots))
                rots[rig.index[f"foot_{s}"]] = foot
        rots = fill(rig, rots, local0, keep=True)
        if clip.get("upright"):
            rots = level_gaze(rig, rots, local0)
        if clip.get("read"):
            rots = level_gaze(rig, rots, local0, STAND_GAZE + (READ_GAZE - STAND_GAZE) * crouch)
            ground = min(targets["l"][1], targets["r"][1]) - ankle_rest
            # Down in the crouch he holds the putter as at the putting
            # address: the grip up the left palm (the club joint's turn in
            # that hand) and both hands' fingers closed round it. (The
            # carry's driver turn and loose curls left the putter hanging
            # from the fingertips and the fingers open beside it.)
            putt_local = list(local0)
            for k in read_held:
                putt_local[k] = p_local[k]
            loc = rig.locals(rots)
            for k in read_held:
                loc[k] = p_local[k]
            putt_rots = rig.world(loc, root)[0]
            held = fill(rig, read_hands(rig, putt_rots, root, facing, club_dir, ground, putt_grip), putt_local, keep=True)
        if clip.get("pump"):
            rots, poss = rig.world(rig.locals(rots), root)
            if i == 0:
                pel = rig.index["pelvis"]
                hold_l = (rots[pel].T @ (poss[rig.index["hand_l"]] - poss[pel]), rots[pel].T @ rots[rig.index["hand_l"]])
            rots = fist_pump(rig, rots, poss, root, i / fps, hold_l, local0)
        if clip.get("point"):
            rots, poss = rig.world(rig.locals(rots), root)
            rots = fore_point(rig, rots, poss, i / fps, pose.unit(np.array(clip["point"], dtype=float)), local0)
        if clip.get("carry"):
            # The club in the left hand: head low in front, or held up
            # when the hand is raised above the shoulder.
            rots, poss = rig.world(rig.locals(rots), root)
            h = rig.index["hand_l"]
            drop = float(np.clip((poss[h][1] - clip.get("carry_head", CARRY_HEAD_HEIGHT)) / CARRY_REACH, 0.3, 0.95))
            low = facing * math.sqrt(1 - drop * drop) - up * drop
            raised = (poss[h][1] - poss[rig.index["upperarm_l"]][1] + 0.1) / 0.3
            w = float(np.clip(raised, 0, 1))
            want = pose.unit(low * (1 - w * w * (3 - 2 * w)) + pose.unit(up + 0.5 * facing) * w * w * (3 - 2 * w))
            rots[h] = between(rots[rig.index["club"]] @ club_dir, want) @ rots[h]
            rots = fill(rig, rots, local0, keep=True)
        if clip.get("pull"):
            if i == 0:
                a_local, a_root = rig.sample(glb, "ref_address")
                a_rots, a_poss = rig.world(a_local, a_root)
                ac = rig.index["club"]
                ahr = rig.index["hand_r"]
                along = float(np.dot(a_rots[ac].T @ (a_poss[ahr] - a_poss[ac]), club_dir))
                # The right hand as it holds the grip at address, moved up
                # the shaft to PULL_HOLD.
                right_rel = (a_rots[ac].T @ (a_poss[ahr] - a_poss[ac]) + club_dir * (PULL_HOLD - along),
                             a_rots[ac].T @ a_rots[ahr])
            rots, club_t = pull_club(rig, rots, root, i / fps, club_dir, local0, grip_local, right_rel)
            club_moves.append(club_t)
        if clip.get("read"):
            # Down in the read the hands are on the putter (read_hands).
            for s in ("l", "r"):
                for k in [rig.index[f"upperarm_{s}"], rig.index[f"lowerarm_{s}"]] + descendants(rig, f"hand_{s}"):
                    rots[k] = pose.slerp(rots[k], held[k], crouch)
        out_rots.append(rig.locals(rots))
        out_root.append(root)
    if clip.get("loop"):
        loop_blend(out_rots, out_root, clip["loop"])
    times = [i / fps for i in range(len(frames))]
    step = max(1, int(round(fps / 60.0)))
    keep = list(range(0, len(frames), step))
    if keep[-1] != len(frames) - 1:
        keep.append(len(frames) - 1)
    moved = {}
    if club_moves:
        moved[rig.index["club"]] = np.array([club_moves[i] for i in keep], np.float32)
    return (np.array([times[i] for i in keep], np.float32), [out_rots[i] for i in keep],
            np.array([out_root[i] for i in keep], np.float32), moved)


def free_hands(name):
    """The hands that hold nothing fixed in a clip: a club only carried
    may turn a little with the wrist; a hand on the grip may not."""
    clip = STAND_CLIPS.get(name)
    if clip is None or clip.get("pull"):
        return ()
    if clip.get("read"):
        return ("r",)
    return ("l", "r")


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
    grip.narrow(glb, rig)
    grip.overlap(glb, rig, club_direction(glb, rig))
    grip.rewrap(glb, rig, club_direction(glb, rig))
    # The clubs modelled from real ones, before the swings are measured
    # against their heads.
    clubs.swap(glb, rig)
    # The putting address re-posed round the (now 34.5 inch) putter.
    putt_posture.fit(glb, rig)
    # The full-swing addresses re-posed as tour players stand (flat back
    # from the hips, arms hanging), round the real-length arms (arm_length.py).
    swing_posture.fit(glb, rig)
    # The real body (the default person's mesh), so the arms are placed
    # outside the chest (collide.py).
    guard = collide.Guard(glb)
    for name in args.clips.split(","):
        if name in STAND_CLIPS:
            times, rots, root, moved = retarget_stand(glb, rig, STAND_CLIPS[name], args.cache)
        else:
            times, rots, root = retarget(glb, rig, CLIPS[name], args.cache)
            moved = {}
        # Elbows swivelled and forearms rolled so the wrists stay in their
        # range, the hands (and club) left exactly where they are.
        rots = anatomy.fit_arms(rig, list(zip(rots, root)), free_hands(name), club_direction(glb, rig), guard)
        write_clip(glb, rig, name, times, rots, root, moves=moved)
        print(f"{name}: {len(times)} keys, {times[-1]:.2f} s")
    club_still(glb, rig)
    glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
