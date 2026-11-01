"""Fits the free golfer's hands to the club: where the grip lies in each
palm, and fingers that close round it.

The address poses from pose.Poser put the club in the left hand along a
line estimated from the rest hand, and curl every finger by fixed angles.
Measured on the baked rig that left the shaft 30 mm from the index
knuckle but 70 mm from the little finger's, so the fingers closed on air
and the grip floated in front of the hand.

Here the grip is laid where a golfer holds it, from the hand's own joints:

- Left hand: diagonally from the middle of the index finger's first bone
  to just under the heel pad below the little finger, with the butt a
  little past the heel of the hand.
- Right hand: lower down, more in the fingers (index finger's first bone
  to just below the base of the little finger), its palm held off the
  grip by the left thumb underneath, its little finger over the left
  index finger, and its palm facing the left palm.
- Both hands turned a little strong for full shots and square for putts.

The club stays exactly where the address pose has it; the hands move to
it and the arms follow with two-bone IK. The club joint turns in the left
hand (a constant rotation every clip keeps) and moves to the new grip
point, with its bind matrix and the club meshes moved by the same amount.

Then each finger bone, from straight, bends towards the shaft until its
far end touches the grip's surface plus the finger's thickness, so the
fingers wrap the grip whatever the hand's proportions.
"""

import numpy as np

import pose

FINGERS = ("thumb", "index", "middle", "ring", "pinky")
# The grip's radius from the butt (along -0.085 m from the grip point) to
# 0.185 m, as build_free_golfer.club_parts makes it.
GRIP_BUTT, GRIP_END = -0.085, 0.185
GRIP_R0, GRIP_R1 = 0.0135, 0.0105
# Joint lines sit about mid-thickness of the hand and fingers: how far a
# bone's line is from the skin that touches the grip.
PALM_HALF = 0.010
FINGER_HALF = {1: 0.0095, 2: 0.0085, 3: 0.0075}
THUMB_HALF = 0.0105
# The butt sticks out this far past the heel of the left hand.
BUTT_PAST_HEEL = 0.015
# The right little finger rides over the gap between the left index and
# middle fingers (an overlapping grip), this far along the shaft from
# the left index finger's middle joint.
RIGHT_OVERLAP = -0.004
# How far the left thumb holds the right palm off the grip.
RIGHT_THUMB_PAD = 0.012
MAX_BEND = {1: 95.0, 2: 105.0, 3: 80.0}
# How far both hands turn round the grip from neutral (the back of the
# left hand to the target): a little strong for full shots, square for
# putts. The golfer faces -z, the target is to his left (-x).
STRONG = {"ref_address": 15.0, "ref_address_iron": 15.0, "ref_address_putt": 0.0}
AWAY_FROM_TARGET = np.array([1.0, 0.0, 0.0])
REFS = ("ref_address", "ref_address_iron", "ref_address_putt")


def grip_radius(t):
    u = np.clip((t - GRIP_BUTT) / (GRIP_END - GRIP_BUTT), 0.0, 1.0)
    return GRIP_R0 + (GRIP_R1 - GRIP_R0) * u


class _Hand:
    """One hand's rest geometry, in the rig's rest frame."""

    def __init__(self, rig, rest, s, address_world):
        x = lambda n: rest[rig.index[f"{n}_{s}"]]  # noqa: E731
        self.s = s
        self.wrist = x("hand")
        i1, i2, p1 = x("index_01"), x("index_02"), x("pinky_01")
        n = pose.unit(np.cross(i1 - self.wrist, p1 - self.wrist))
        # The palm is the side the fingers curl to.
        R, P = address_world
        h = rig.index[f"hand_{s}"]
        tip = R[h].T @ (P[rig.index[f"middle_03_{s}"]] - P[h]) + self.wrist
        if np.dot(tip - x("middle_01"), n) < 0:
            n = -n
        self.palm = n
        off = n * (PALM_HALF + GRIP_R0)
        if s == "l":
            front = (i1 + i2) / 2 + off
            back = p1 + 0.3 * (self.wrist - p1) + off
        else:
            # The right palm closes over the left thumb, so it sits off
            # the grip by the thumb's thickness at the heel.
            front = i1 + 0.5 * (i2 - i1) + off
            back = p1 + 0.25 * (self.wrist - p1) + off + n * RIGHT_THUMB_PAD
        self.axis = pose.unit(front - back)  # towards the club head
        self.palm = pose.unit(n - self.axis * np.dot(n, self.axis))
        self.point = back
        heel = self.wrist + 0.35 * (p1 - self.wrist)  # the heel pad's far edge
        self.heel_t = float(np.dot(heel - back, self.axis))

    def frame(self):
        """Rest-frame basis: shaft axis, palm normal and their cross."""
        return np.column_stack([self.axis, self.palm, np.cross(self.axis, self.palm)])


def _hand_world(hand, shaft, palm):
    """World rotation taking the hand's rest axis/palm to shaft/palm."""
    palm = pose.unit(palm - shaft * np.dot(palm, shaft))
    world = np.column_stack([shaft, palm, np.cross(shaft, palm)])
    return world @ hand.frame().T


def club_offsets(left):
    """The grip point in the left hand (rest frame)."""
    # The butt a little past the heel of the hand.
    t = left.heel_t - BUTT_PAST_HEEL - GRIP_BUTT
    return left.point + left.axis * t


def fit(glb, rig, club_dir):
    """Re-fits the hands of every ref_ address clip, moves the club joint
    and its meshes, and marks the .glb. Returns False if already fitted."""
    from mocap_swing import two_bone, write_clip

    doc = glb.doc
    skin = doc["skins"][0]
    cj = rig.index["club"]
    club_node = doc["nodes"][rig.joints[cj]]
    if club_node.get("extras", {}).get("grip_fit"):
        return False
    _, rest = rig.world([np.eye(3)] * len(rig.names), rig.offsets[0])
    base_local, base_root = rig.sample(glb, "ref_address")
    base_world = rig.world(base_local, base_root)
    left = _Hand(rig, rest, "l", base_world)
    right = _Hand(rig, rest, "r", base_world)
    grip0 = rest[cj].copy()
    grip1 = club_offsets(left)

    for ref in REFS:
        anim = glb.animation(ref)
        if not anim:
            continue
        local, root = rig.sample(glb, ref)
        R, P = rig.world(local, root)
        club_r, club_p = R[cj], P[cj]
        shaft = club_r @ club_dir
        R = list(R)
        # Left hand onto the club.
        hl = rig.index["hand_l"]
        away = pose.unit(AWAY_FROM_TARGET - shaft * np.dot(AWAY_FROM_TARGET, shaft))
        up = pose.unit(np.cross(away, shaft))
        if up[1] < 0:
            up = -up
        a = np.radians(STRONG[ref])
        hand_l = _hand_world(left, shaft, np.cos(a) * away - np.sin(a) * up)
        turn = hand_l.T @ club_r  # the club in the left hand
        wrist_l = club_p - hand_l @ (grip1 - rest[hl])
        poss = list(P)
        two_bone(rig, R, poss, "upperarm_l", "lowerarm_l", "hand_l", wrist_l)
        R[hl] = hand_l
        R, poss = rig.world(rig.locals(R), root)
        R = list(R)
        reach_l = np.linalg.norm(poss[hl] - wrist_l)
        # Right hand: palm facing the left palm, little finger over the
        # left index finger.
        hr = rig.index["hand_r"]
        palm_l = hand_l @ left.palm
        hand_r = _hand_world(right, shaft, -palm_l)
        li = float(np.dot(poss[rig.index["index_02_l"]] - club_p, shaft))
        rp = float(np.dot(right.point - rest[rig.index["pinky_01_r"]], right.axis))
        at = li + RIGHT_OVERLAP + rp
        target_r = club_p + shaft * at - hand_r @ (right.point - rest[hr])
        two_bone(rig, R, poss, "upperarm_r", "lowerarm_r", "hand_r", target_r)
        R[hr] = hand_r
        R, poss = rig.world(rig.locals(R), root)
        R = list(R)
        reach_r = np.linalg.norm(poss[hr] - target_r)
        # Club joint: the turn in the left hand.
        R[cj] = hand_l @ turn
        # Fingers.
        R = wrap_fingers(rig, R, root, club_p, shaft)
        local = rig.locals(R)
        write_clip(glb, rig, ref, np.zeros(1, np.float32), [local], np.array([root], np.float32), filtered=False)
        print(f"{ref}: hands re-gripped (left wrist {reach_l * 1000:.0f} mm, right {reach_r * 1000:.0f} mm short)")

    # Move the club joint, its bind matrix and the club meshes.
    delta = grip1 - grip0
    club_node["translation"] = [float(v) for v in (np.array(club_node["translation"]) + delta)]
    club_node.setdefault("extras", {})["grip_fit"] = 1
    ibm = glb.read(skin["inverseBindMatrices"]).copy()
    k = skin["joints"].index(rig.joints[cj])
    ibm[k, 12:15] = -grip1
    skin["inverseBindMatrices"] = glb.add(ibm)
    for node in doc["nodes"]:
        name = node.get("name", "")
        if "mesh" not in node or not name.split("_")[0] in ("Driver", "Iron", "Putter"):
            continue
        for prim in doc["meshes"][node["mesh"]]["primitives"]:
            pos = glb.read(prim["attributes"]["POSITION"]) + delta
            prim["attributes"]["POSITION"] = glb.add(pos.astype(np.float32), minmax=True)
            doc["bufferViews"][doc["accessors"][prim["attributes"]["POSITION"]]["bufferView"]]["target"] = 34962
    rig.offsets[cj] = np.array(club_node["translation"], dtype=float)
    return True


# Address posture, from tour players: the lead arm hangs nearly straight
# (iron.LEAD_BEND, iron.DRIVER_LEAD_BEND) and the knees are flexed ~22
# degrees. Fitting the grip into the palm raised the wrists ~6 cm against
# the club, which bent the lead elbow to 54-62 degrees (and ~70 at the
# top). straighten() takes it out round the club head and the feet: the
# hands go lower (the shaft a few degrees flatter, as with tour players'
# low hands), the hips a little back and the knees to KNEE_FLEX.
POSTURE = {"ref_address": ("Driver", 20.0), "ref_address_iron": ("Iron", 12.0)}  # club, lead elbow
KNEE_FLEX = 22.0
HIPS_BACK = 0.04  # metres
MAX_LIE = 8.0  # degrees


def _angle(a, b):
    return np.degrees(np.arccos(np.clip(np.dot(a, b) / np.linalg.norm(a) / np.linalg.norm(b), -1.0, 1.0)))


def lead_bend(rig, P):
    i = rig.index
    return _angle(P[i["lowerarm_l"]] - P[i["upperarm_l"]], P[i["hand_l"]] - P[i["lowerarm_l"]])


def knee_flex(rig, P):
    i = rig.index
    return _angle(P[i["calf_l"]] - P[i["thigh_l"]], P[i["foot_l"]] - P[i["calf_l"]])


def _search(f, lo, hi, want):
    """x in [lo, hi] where the increasing f(x) reaches want."""
    for _ in range(24):
        mid = (lo + hi) / 2
        if f(mid) < want:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def straighten(glb, rig):
    """Re-poses the full-swing addresses to POSTURE. Marks the .glb;
    returns False if already done."""
    from mocap_swing import club_head_verts, two_bone, write_clip

    cj = rig.index["club"]
    club_node = glb.doc["nodes"][rig.joints[cj]]
    if club_node.get("extras", {}).get("arm_fit"):
        return False
    _, rest = rig.world([np.eye(3)] * len(rig.names), rig.offsets[0])
    for ref, (club, elbow) in POSTURE.items():
        if not glb.animation(ref):
            continue
        local, root = rig.sample(glb, ref)
        R0, P0 = rig.world(local, root)
        verts = club_head_verts(glb, club)
        head = ((R0[cj] @ (verts - rest[cj]).T).T + P0[cj]).mean(axis=0)
        shaft = P0[cj] - head
        axis = pose.unit(np.cross([shaft[0], 0.0, shaft[2]], [0.0, 1.0, 0.0]))
        if (pose.rot(axis, 1.0) @ shaft)[1] > shaft[1]:
            axis = -axis  # + flattens the shaft (the hands go down)

        def stand(lie, rise):
            flat = pose.rot(axis, lie)
            r2 = np.array(root, dtype=float) + np.array([0.0, rise, HIPS_BACK])
            R, P = rig.world(local, r2)
            R = list(R)
            for s in "lr":
                foot = R0[rig.index[f"foot_{s}"]]
                two_bone(rig, R, list(P), f"thigh_{s}", f"calf_{s}", f"foot_{s}", P0[rig.index[f"foot_{s}"]])
                R[rig.index[f"foot_{s}"]] = foot
            R, P = rig.world(rig.locals(R), r2)
            R = list(R)
            for s in "lr":
                h = rig.index[f"hand_{s}"]
                two_bone(rig, R, list(P), f"upperarm_{s}", f"lowerarm_{s}", f"hand_{s}", head + flat @ (P0[h] - head))
                R[h] = flat @ R0[h]
            R[cj] = flat @ R0[cj]
            R, P = rig.world(rig.locals(R), r2)
            return R, P, r2

        # Taller straightens the knees; flatter (hands lower) the lead arm.
        rise = _search(lambda y: -knee_flex(rig, stand(0.0, y)[1]), -0.1, 0.1, -KNEE_FLEX)
        lie = _search(lambda a: -lead_bend(rig, stand(a, rise)[1]), 0.0, MAX_LIE, -elbow)
        R, P, r2 = stand(lie, rise)
        write_clip(glb, rig, ref, np.zeros(1, np.float32), [rig.locals(R)], np.array([r2], np.float32), filtered=False)
        print(f"{ref}: hands {(P0[rig.index['hand_l']][1] - P[rig.index['hand_l']][1]) * 100:.1f} cm lower (shaft {lie:.1f} deg flatter), "
              f"lead elbow {lead_bend(rig, P0):.0f} -> {lead_bend(rig, P):.0f}, knees {knee_flex(rig, P0):.0f} -> {knee_flex(rig, P):.0f}")
    club_node.setdefault("extras", {})["arm_fit"] = 1
    return True


# Ankle to ankle at address, metres: a mid iron is played from about
# shoulder width, narrower than the driver's (whose stance the iron's
# address was built from).
IRON_STANCE = 0.41


def narrow(glb, rig):
    """Brings the iron address's feet in to IRON_STANCE, the hips and the
    hands where they were (the knees flex a touch more). Marks the .glb;
    returns False if already done."""
    from mocap_swing import two_bone, write_clip

    cj = rig.index["club"]
    club_node = glb.doc["nodes"][rig.joints[cj]]
    if club_node.get("extras", {}).get("iron_stance") or not glb.animation("ref_address_iron"):
        return False
    local, root = rig.sample(glb, "ref_address_iron")
    R0, P0 = rig.world(local, root)
    fl, fr = P0[rig.index["foot_l"]], P0[rig.index["foot_r"]]
    centre, half = (fl + fr) / 2, (fr - fl) / np.linalg.norm(fr - fl) * IRON_STANCE / 2
    R, P = list(R0), list(P0)
    for s, target in (("l", centre - half), ("r", centre + half)):
        foot = R0[rig.index[f"foot_{s}"]]
        two_bone(rig, R, P, f"thigh_{s}", f"calf_{s}", f"foot_{s}", np.array([target[0], P0[rig.index[f"foot_{s}"]][1], target[2]]))
        R[rig.index[f"foot_{s}"]] = foot
    R, P = rig.world(rig.locals(R), root)
    write_clip(glb, rig, "ref_address_iron", np.zeros(1, np.float32), [rig.locals(R)], np.array([root], np.float32),
               filtered=False)
    print(f"ref_address_iron: stance {np.linalg.norm(fr - fl) * 100:.0f} -> "
          f"{np.linalg.norm(P[rig.index['foot_r']] - P[rig.index['foot_l']]) * 100:.0f} cm, "
          f"knees {knee_flex(rig, P0):.0f} -> {knee_flex(rig, P):.0f}")
    club_node.setdefault("extras", {})["iron_stance"] = 1
    return True


def between(a, b):
    a, b = pose.unit(a), pose.unit(b)
    axis = np.cross(a, b)
    s, c = np.linalg.norm(axis), float(np.dot(a, b))
    if s < 1e-9:
        return np.eye(3)
    return pose.rot(axis, np.degrees(np.arctan2(s, c)))


def wrap_fingers(rig, R, root, origin, shaft):
    """World rotations with every finger bent round the grip."""
    R = list(R)
    loc = rig.locals(R)
    for s in "lr":
        for finger in FINGERS:
            for seg in (1, 2, 3):
                loc[rig.index[f"{finger}_0{seg}_{s}"]] = np.eye(3)
    R, P = rig.world(loc, root)
    R = list(R)
    for s in "lr":
        R = _aim_thumb(rig, R, root, origin, shaft, s)
        for finger in FINGERS:
            for seg in (1, 2, 3):
                if finger == "thumb" and seg == 1:
                    continue  # aimed by _aim_thumb
                j = rig.index[f"{finger}_0{seg}_{s}"]
                R, P = rig.world(rig.locals(R), root)
                R = list(R)
                head = P[j]
                if seg < 3:
                    offset = rig.offsets[rig.index[f"{finger}_0{seg + 1}_{s}"]]
                else:
                    offset = 0.8 * rig.offsets[j]
                vec = R[j] @ offset
                rel = head - origin
                rho = rel - shaft * np.dot(rel, shaft)
                if np.linalg.norm(rho) < 1e-6:
                    continue
                hinge = np.cross(pose.unit(vec), -pose.unit(rho))
                if np.linalg.norm(hinge) < 1e-6:
                    continue
                hinge = pose.unit(hinge)
                half = THUMB_HALF if finger == "thumb" else FINGER_HALF[seg]

                def gap(deg):
                    tail = head + pose.rot(hinge, deg) @ vec - origin
                    t = float(np.dot(tail, shaft))
                    return np.linalg.norm(tail - shaft * t) - grip_radius(t) - half

                best = 0.0
                if gap(0.0) < 0.0:
                    # Already into the grip: straighten until it isn't.
                    for deg in np.arange(0.0, -45.1, -0.5):
                        best = deg
                        if gap(deg) >= 0.0:
                            break
                else:
                    best_gap = None
                    for deg in np.arange(0.0, MAX_BEND[seg] + 0.1, 0.5):
                        g = gap(deg)
                        if best_gap is None or g < best_gap:
                            best, best_gap = deg, g
                        if g <= 0.0:
                            best = deg
                            break
                if best:
                    turn = pose.rot(hinge, best)
                    R[j] = turn @ R[j]
                    R = _carry(rig, R, j, turn)
    return R


def _aim_thumb(rig, R, root, origin, shaft, s):
    """Lays the thumb down the grip: its straight tip aimed at the grip's
    surface level with the index finger's middle joint, on the thumb's side."""
    R, P = rig.world(rig.locals(R), root)
    R = list(R)
    j = rig.index[f"thumb_01_{s}"]
    head = P[j]
    tip = P[rig.index[f"thumb_03_{s}"]] + R[rig.index[f"thumb_03_{s}"]] @ (0.8 * rig.offsets[rig.index[f"thumb_03_{s}"]])
    rel = head - origin
    radial = pose.unit(rel - shaft * np.dot(rel, shaft))
    t = float(np.dot(P[rig.index[f"index_02_{s}"]] - origin, shaft)) - 0.005
    target = origin + shaft * t + radial * (grip_radius(t) + THUMB_HALF)
    turn = between(tip - head, target - head)
    R[j] = turn @ R[j]
    return _carry(rig, R, j, turn)


def _carry(rig, R, j, turn):
    """Turns the descendants of j by turn too (world rotations)."""
    R = list(R)
    stack = [c for c, p in enumerate(rig.parents) if p == j]
    while stack:
        c = stack.pop()
        R[c] = turn @ R[c]
        stack.extend(k for k, p in enumerate(rig.parents) if p == c)
    return R
