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
    "backswing": dict(take="64_01", ref="address", address=150, start=150, end=262, top=262, impact=329, putt=False),
    "swing": dict(take="64_01", ref="address", address=150, start=262, end=400, top=262, impact=329,
                  downswing=0.30, follow=0.7, hold=2.5, twirl=(0.9, 0.55), putt=False, strike=(0.0, 0.012, -0.755)),
    # The irons: the same takes from the iron's address (iron.py).
    "address_iron": dict(take="64_01", ref="address_iron", address=150, putt=False, loop=0.3,
                         frames=list(range(150, 30, -1)) + list(range(30, 150)) + list(range(150, 30, -1)),
                         glance=(1.3, 0.4, 0.7, 70.0), club="Iron"),
    "backswing_iron": dict(take="64_01", ref="address_iron", club="Iron", address=150, start=150, end=262, top=262, impact=329,
                           putt=False),
    "swing_iron": dict(take="64_01", ref="address_iron", club="Iron", address=150, start=262, end=400, top=262, impact=329,
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
ADDRESS_CLEAR = 0.004  # the club head's lowest point at address, metres
IMPACT_WINDOW = 30  # mocap frames either side of impact the correction fades over


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
    shaft0 = ref_rots[hands_l] @ club_dir
    plane = pose.unit(np.cross([-1.0, 0.0, 0.0], shaft0))  # + turns the club head away from the target
    arm0 = plane_dir(ref_poss[hands_l] - ref_poss[rig.index["upperarm_l"]], plane)
    arm_angle = 0.0
    grip_r = ref_rots[hands_l].T @ (ref_poss[rig.index["hand_r"]] - ref_poss[hands_l])
    hand_r_in_l = ref_rots[hands_l].T @ ref_rots[rig.index["hand_r"]]

    head_verts = club_head_verts(glb, clip.get("club", "Driver"))
    _, rest = rig.world([np.eye(3)] * len(rig.names), rig.offsets[0])
    club_j = rig.index["club"]

    def club_head(rots, poss):
        w = (rots[club_j] @ (head_verts - rest[club_j]).T).T + poss[club_j]
        return np.array([*w.mean(axis=0)[[0]], w[:, 1].min(), w.mean(axis=0)[2]])

    def run(correct):
        nonlocal arm_angle
        arm_angle = 0.0
        impact_head = np.zeros(3)
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
            if "impact" in clip:
                # Down into the shot at impact: the knees flex (the feet are pinned below).
                root = root + impact_weight(f, clip["impact"]) * np.array([0.0, correct[1], 0.0])
            rots = fill(rig, rots, ref_local)
            _, poss = rig.world(rig.locals(rots), root)
            # Feet go where the actor's feet go.
            for s, actor in (("l", "LeftFoot"), ("r", "RightFoot")):
                k = bvh.index[actor]
                target = ref_poss[rig.index[f"foot_{s}"]] + scale * (g @ (m_poss[k] - m_poss0[k]))
                foot = rots[rig.index[f"foot_{s}"]]
                # Up on the toes, not through the ground.
                toe = target + foot @ (rest[rig.index[f"ball_{s}"]] - rest[rig.index[f"foot_{s}"]])
                target = target + np.array([0.0, max(0.0, ref_poss[rig.index[f"ball_{s}"]][1] - toe[1],
                                                     ref_poss[rig.index[f"foot_{s}"]][1] - target[1]), 0.0])
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
                rots[hands_l] = between(rots[hands_l] @ club_dir, want) @ rots[hands_l]
                rots = fill(rig, rots, ref_local, keep=True)
                rots, poss = rig.world(rig.locals(rots), root)
            if correct is not None and not clip["putt"] and "impact" in clip:
                head = club_head(rots, poss)
                if f == clip["impact"]:
                    impact_head[:] = head
                w = impact_weight(f, clip["impact"])
                if w > 0.0 and np.any(correct):
                    # Brings the club head in to the ball at impact: the lead
                    # arm swings in (its length kept), the club turning with it.
                    two_bone(rig, rots, poss, "upperarm_l", "lowerarm_l", "hand_l",
                             poss[hands_l] + w * correct * np.array([1.0, 0.0, 1.0]))
                    rots = fill(rig, rots, ref_local, keep=True)
                    rots, poss = rig.world(rig.locals(rots), root)
            if "impact" not in clip:
                # Waggling over the ball, the club head stays above the ground.
                low = club_head(rots, poss)[1]
                if low < ADDRESS_CLEAR:
                    two_bone(rig, rots, poss, "upperarm_l", "lowerarm_l", "hand_l",
                             poss[hands_l] + np.array([0.0, ADDRESS_CLEAR - low, 0.0]))
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

    out_rots, out_root, head = run(np.zeros(3))
    if not clip["putt"] and "impact" in clip and clip["impact"] in frames:
        # The lowest point of the head on the ball at impact.
        out_rots, out_root, _ = run(np.array(clip.get("strike", IMPACT_AT)) - head)

    if clip.get("loop"):
        loop_blend(out_rots, out_root, clip["loop"])
    times = retime(clip, frames)
    keep = list(range(0, len(frames), STEP))
    if keep[-1] != len(frames) - 1:
        keep.append(len(frames) - 1)
    times = [times[i] for i in keep]
    out_rots = [out_rots[i] for i in keep]
    out_root = [out_root[i] for i in keep]
    if clip.get("hold"):
        end, last, last_root = times[-1], out_rots[-1], out_root[-1]
        if clip.get("twirl"):
            # Held at the finish, then the club spun once in the fingers.
            start, seconds = clip["twirl"]
            club_j = rig.index["club"]
            shaft = iron.poser(rig).club_dir_rest["l"]  # the spin axis, along the shaft
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
    """The shaft's direction (grip to head) in the rest frame."""
    doc = glb.doc
    head = None
    for n in doc["nodes"]:
        if n.get("name") == "Driver_head":
            head = glb.read(doc["meshes"][n["mesh"]]["primitives"][0]["attributes"]["POSITION"]).mean(axis=0)
    _, rest = rig.world([np.eye(3)] * len(rig.names), rig.offsets[0])
    return pose.unit(head - rest[rig.index["club"]])


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
            relaxed[j] = pose.slerp(np.eye(3), grip_local[j], curl)
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
            rots[h] = between(rots[h] @ club_dir, want) @ rots[h]
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
