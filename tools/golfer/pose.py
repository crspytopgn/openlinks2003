"""Poses the MakeHuman game_engine skeleton for a golf swing.

Every bone's rest rotation is the identity, so a pose is a world rotation per
bone plus the root position. The swing is described by a handful of numbers
per key (see Key); the hands travel round a circle in the swing plane, the
club turns further round the same plane, and the arms and legs reach their
targets with two-bone IK. All of it is original to this project.
"""

import math
from dataclasses import dataclass, field, replace

import numpy as np

X = np.array([1.0, 0, 0])
Y = np.array([0, 1.0, 0])
Z = np.array([0, 0, 1.0])
FORWARD = -Z  # the golfer faces -z; the target is at -x
BALL = np.array([0.0, 0.0, -0.75])  # where GolferRig puts the ball


def unit(v):
    return v / max(np.linalg.norm(v), 1e-12)


def rot(axis, deg):
    a = unit(np.asarray(axis, dtype=float))
    t = math.radians(deg)
    k = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + math.sin(t) * k + (1 - math.cos(t)) * (k @ k)


def frame(d, n):
    """Orthonormal columns: d, n made perpendicular to d, and d x n."""
    d = unit(d)
    n = unit(n - d * np.dot(n, d))
    return np.column_stack([d, n, np.cross(d, n)])


def aim(d0, n0, d, n):
    """The rotation taking rest direction d0 (with side n0) to d (with n)."""
    return frame(d, n) @ frame(d0, n0).T


def quat(m):
    """Rotation matrix to a unit quaternion (x, y, z, w)."""
    t = np.trace(m)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    q = np.array(q)
    return q / np.linalg.norm(q)


def matrix(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def slerp(a, b, t):
    qa, qb = quat(a), quat(b)
    if np.dot(qa, qb) < 0:
        qb = -qb
    d = np.clip(np.dot(qa, qb), -1, 1)
    if d > 0.9995:
        q = qa + t * (qb - qa)
    else:
        th = math.acos(d)
        q = (math.sin((1 - t) * th) * qa + math.sin(t * th) * qb) / math.sin(th)
    return matrix(q / np.linalg.norm(q))


def twist_angle(m, axis):
    """Degrees of m's twist about axis (swing-twist decomposition)."""
    q = quat(m)
    return math.degrees(2 * math.atan2(np.dot(q[:3], unit(axis)), q[3]))


@dataclass
class Key:
    """One key of a swing. Angles in degrees, distances in metres."""
    t: float = 0.0  ## time of the key, seconds
    hands: float = 0.0  ## hands round the swing circle, + away from the target
    hinge: float = 0.0  ## club angle past the hands, in the swing plane
    turn: float = 0.0  ## shoulder turn, + away from the target
    hips: float = 0.0  ## hip turn, + away from the target
    tilt: float = 36.0  ## forward bend of the chest
    bend: float = 12.0  ## side bend, right shoulder lowered
    shift: float = 0.0  ## pelvis sideways, + away from the target
    sink: float = 0.0  ## pelvis lowered (knee flex)
    head: float = 0.0  ## 0 eyes on the ball, 1 watching the shot
    heel: float = 0.0  ## right heel lift (pivot onto the toe)
    lheel: float = 0.0  ## left heel lift
    face: float = 0.0  ## club face roll, + opens
    cheer: float = 0.0  ## 0..1, right fist raised
    putt: float = 0.0  ## 0 full-swing stance, 1 putting stance


class Club:
    def __init__(self, name, length, lie, head_toe, loft_face=0.0):
        self.name = name
        self.length = length  ## grip point (left palm) to hosel
        self.lie = lie
        self.head_toe = head_toe


DRIVER = Club("Driver", 1.04, 51.0, 0.06)
PUTTER = Club("Putter", 0.80, 70.0, 0.05)


class Poser:
    def __init__(self, human):
        self.h = human
        self.names = human.bones
        self.parents = human.parents
        self.rest = human.heads
        self.b = {n: i for i, n in enumerate(self.names)}
        self.club_joint = len(self.names)  # added by the builder, child of hand_l
        h = self._rest
        self.upper = {s: np.linalg.norm(h(f"lowerarm_{s}") - h(f"upperarm_{s}")) for s in "lr"}
        self.fore = {s: np.linalg.norm(h(f"hand_{s}") - h(f"lowerarm_{s}")) for s in "lr"}
        self.thigh = {s: np.linalg.norm(h(f"calf_{s}") - h(f"thigh_{s}")) for s in "lr"}
        self.shin = {s: np.linalg.norm(h(f"foot_{s}") - h(f"calf_{s}")) for s in "lr"}
        # Each hand's grip point, the club's rest direction (towards the
        # head) and face normal, from the rest hand.
        self.palm_normal = {"l": X.copy(), "r": -X.copy()}
        self.grip_rest, self.club_dir_rest, self.face_rest = {}, {}, {}
        for s in "lr":
            wrist = h(f"hand_{s}")
            heel = wrist + 0.55 * (h(f"pinky_01_{s}") - wrist)
            index = h(f"index_02_{s}")
            d = unit(index - heel)
            palm = self.palm_normal[s]
            knuckles = (h(f"index_01_{s}") + h(f"middle_01_{s}") + h(f"ring_01_{s}") + h(f"pinky_01_{s}")) / 4
            self.grip_rest[s] = 0.45 * wrist + 0.55 * knuckles + palm * 0.025
            self.club_dir_rest[s] = d
            # Face normal: the back of the left hand, the palm of the right.
            f = -palm if s == "l" else palm
            self.face_rest[s] = unit(f - d * np.dot(f, d))
        self.curl_axes = {}
        for s in "lr":
            for finger in ("index", "middle", "ring", "pinky", "thumb"):
                d1 = unit(human.tails[self.b[f"{finger}_01_{s}"]] - h(f"{finger}_01_{s}"))
                d3 = unit(human.tails[self.b[f"{finger}_03_{s}"]] - h(f"{finger}_03_{s}"))
                axis = np.cross(d1, d3)
                if np.linalg.norm(axis) < 1e-3:
                    axis = np.cross(d1, self.palm_normal[s])
                self.curl_axes[(s, finger)] = unit(axis)
        self.stances = {0: self._stance(DRIVER, 0.0), 1: self._stance(PUTTER, 1.0)}

    def _rest(self, name):
        return self.rest[self.b[name]]

    # ---- stance -------------------------------------------------------

    def _stance(self, club, putt):
        """Address geometry for a club: grip, shaft, and the body offset that
        puts the club face on the ball."""
        key = Key(tilt=36 + 6 * putt, bend=12 - 8 * putt, putt=putt)
        offset = np.zeros(3)
        world = self._torso(key, offset)
        sl, sr = world["upperarm_l"][1], world["upperarm_r"][1]
        mid = (sl + sr) / 2
        lie = math.radians(club.lie)
        grip_y = 0.012 + club.length * math.sin(lie)
        grip = np.array([mid[0] - 0.04 + 0.03 * putt, grip_y, mid[2] - 0.02 - 0.03 * putt])
        shaft = unit(np.array([0.0, -math.sin(lie), -math.cos(lie)]))
        hosel = grip + shaft * club.length
        toe = self._toe(shaft, -X, club)
        ball_at = hosel + toe * club.head_toe * 0.8 - X * 0.03
        offset = np.array([BALL[0] - ball_at[0], 0.0, BALL[2] - ball_at[2]])
        centre = mid + offset
        return {"grip": grip + offset, "shaft": shaft, "offset": offset, "centre": centre, "club": club}

    @staticmethod
    def _toe(shaft, face, club):
        b = np.cross(shaft, face)
        if b[2] > 0:
            b = -b
        lie = math.radians(club.lie)
        return unit(math.cos(lie) * shaft + math.sin(lie) * unit(b))

    def _blend_stance(self, putt):
        a, b = self.stances[0], self.stances[1]
        out = {}
        for k in ("grip", "offset", "centre"):
            out[k] = a[k] * (1 - putt) + b[k] * putt
        out["shaft"] = unit(a["shaft"] * (1 - putt) + b["shaft"] * putt)
        out["club"] = b["club"] if putt > 0.5 else a["club"]
        return out

    # ---- skeleton -----------------------------------------------------

    def _torso(self, k, offset):
        """World (rotation, position) of the pelvis, spine, neck and arms'
        roots for a key. Returns {bone: (R, p)} for the bones it set."""
        out = {}
        # Hinging at the hips moves the pelvis back over the heels.
        back = 0.10 * math.sin(math.radians(k.tilt)) / math.sin(math.radians(36))
        root_p = offset + np.array([k.shift, -(0.035 + 0.02 * (1 - k.putt)) - k.sink, back])
        out["Root"] = (np.eye(3), root_p)
        hip_tilt = 0.55 * k.tilt
        pelvis = rot(Y, -k.hips) @ rot(X, -hip_tilt)
        p_pelvis = root_p + self._rest("pelvis")
        out["pelvis"] = (pelvis, p_pelvis)
        torso = rot(Y, -k.turn * 0.35) @ rot(X, -k.tilt) @ rot(Y, -k.turn * 0.65) @ rot(Z, -k.bend)
        parent_r, parent_p, parent_name = pelvis, p_pelvis, "pelvis"
        for name, w in (("spine_01", 0.35), ("spine_02", 0.7), ("spine_03", 1.0)):
            r = slerp(pelvis, torso, w)
            p = parent_p + parent_r @ (self._rest(name) - self._rest(parent_name))
            out[name] = (r, p)
            parent_r, parent_p, parent_name = r, p, name
        for s in "lr":
            c = f"clavicle_{s}"
            pc = parent_p + parent_r @ (self._rest(c) - self._rest("spine_03"))
            out[c] = (parent_r, pc)
            out[f"upperarm_{s}"] = (None, pc + parent_r @ (self._rest(f"upperarm_{s}") - self._rest(c)))
        return out

    def _two_bone(self, root, target, l1, l2, pole):
        to = target - root
        dist = np.clip(np.linalg.norm(to), 0.05, l1 + l2 - 1e-4)
        d = unit(to)
        cos_a = np.clip((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist), -1, 1)
        bend = unit(pole - d * np.dot(pole, d))
        mid = root + d * l1 * cos_a + bend * l1 * math.sqrt(max(0.0, 1 - cos_a * cos_a))
        end = root + d * dist
        return mid, end, bend, d

    def pose(self, k):
        """World rotation per bone and the root position for a key."""
        st = self._blend_stance(k.putt)
        club = st["club"]
        world = self._torso(k, st["offset"])
        R = {n: v[0] for n, v in world.items() if v[0] is not None}
        P = {n: v[1] for n, v in world.items()}

        # Head and neck: eyes on the ball, then after the shot.
        sp3 = R["spine_03"]
        head_p = P["spine_03"] + sp3 @ (self._rest("head") - self._rest("spine_03"))
        look_ball = unit(BALL + np.array([0.0, 0.02, 0.0]) - head_p)
        look_shot = unit(np.array([-1.0, 0.25, -0.15]))
        look = unit(look_ball * (1 - k.head) + look_shot * k.head)
        up = sp3 @ Y
        head_r = aim(FORWARD, Y, look, up)
        R["head"] = head_r
        R["neck_01"] = slerp(sp3, head_r, 0.45)

        # The club: hands round the circle, the club further round the plane.
        centre = st["centre"] + np.array([k.shift * 0.5, 0, 0])
        grip0, shaft0 = st["grip"], st["shaft"]
        a_h = unit(grip0 - centre)
        x_h = unit(X - a_h * np.dot(X, a_h))
        radius = np.linalg.norm(grip0 - st["centre"])
        th = math.radians(k.hands)
        grip = centre + radius * (math.cos(th) * a_h + math.sin(th) * x_h)
        x_d = unit(X - shaft0 * np.dot(X, shaft0))
        c = math.radians(k.hands + k.hinge)
        along = math.cos(c) * shaft0 + math.sin(c) * x_d
        face = math.sin(c) * shaft0 - math.cos(c) * x_d
        face = rot(along, k.face) @ face

        # Left hand holds the club; the arm reaches as far as it can and the
        # club follows the hand.
        r_club = aim(self.club_dir_rest["l"], self.face_rest["l"], along, face)
        hand_l = r_club
        wrist_l = grip - hand_l @ (self.grip_rest["l"] - self._rest("hand_l"))
        pole_l = sp3 @ np.array([-0.2, -1.0, 0.6]) if k.putt < 0.5 else sp3 @ np.array([-0.8, -0.6, 0.5])
        self._arm("l", R, P, wrist_l, pole_l, hand_l)
        grip_actual = P["hand_l"] + R["hand_l"] @ (self.grip_rest["l"] - self._rest("hand_l"))
        P["club"] = grip_actual
        R["club"] = R["hand_l"]

        hand_r = aim(self.club_dir_rest["r"], self.face_rest["r"], along, face)
        grip_r = grip_actual + along * 0.095
        wrist_r = grip_r - hand_r @ (self.grip_rest["r"] - self._rest("hand_r"))
        if k.cheer > 0:
            fist = P["upperarm_r"] + np.array([0.12, 0.62, -0.05])
            wrist_r = wrist_r * (1 - k.cheer) + fist * k.cheer
            hand_r = slerp(hand_r, rot(Z, 160) @ rot(Y, 90), k.cheer)
        pole_r = sp3 @ np.array([0.5, -1.0, 0.5])
        if k.cheer > 0:
            pole_r = unit(pole_r * (1 - k.cheer) + np.array([1.0, -0.6, 0.3]) * k.cheer)
        self._arm("r", R, P, wrist_r, pole_r, hand_r)

        # Fingers wrap the grip.
        curl = {"index": 38, "middle": 42, "ring": 44, "pinky": 46, "thumb": 14}
        for s in "lr":
            for finger, deg in curl.items():
                if s == "r" and k.cheer > 0:
                    deg = deg * (1 + 0.5 * k.cheer)
                for seg in "123":
                    name = f"{finger}_0{seg}_{s}"
                    parent = self.names[self.parents[self.b[name]]]
                    R[name] = R[parent] @ rot(self.curl_axes[(s, finger)], deg)

        # Legs: feet planted on a shoulder-width stance.
        self._legs(k, R, P, st)
        return R, P["Root"], {"grip": grip_actual, "along": along, "face": face, "club": club}

    def _arm(self, s, R, P, wrist, pole, hand_r):
        shoulder = P[f"upperarm_{s}"]
        l1, l2 = self.upper[s], self.fore[s]
        elbow, end, bend, d = self._two_bone(shoulder, wrist, l1, l2, pole)
        n = unit(np.cross(bend, d))
        e0 = self._rest(f"lowerarm_{s}") - self._rest(f"upperarm_{s}")
        f0 = self._rest(f"hand_{s}") - self._rest(f"lowerarm_{s}")
        n0u = unit(np.cross(unit(e0), FORWARD))
        n0f = unit(np.cross(unit(f0), FORWARD))
        r_up = aim(e0, n0u, elbow - shoulder, n)
        r_fore = aim(f0, n0f, end - elbow, n)
        # Share the hand's roll with the forearm so the wrist doesn't pinch.
        twist = twist_angle(r_fore.T @ hand_r, f0)
        r_fore = r_fore @ rot(f0, 0.6 * twist)
        R[f"upperarm_{s}"] = r_up
        R[f"lowerarm_{s}"] = r_fore
        R[f"hand_{s}"] = hand_r
        P[f"lowerarm_{s}"] = elbow
        P[f"hand_{s}"] = end

    def _legs(self, k, R, P, st):
        pelvis_r, pelvis_p = R["pelvis"], P["pelvis"]
        width = 0.055 * (1 - k.putt) + 0.01 * k.putt
        for s, side in (("l", -1.0), ("r", 1.0)):
            hip = pelvis_p + pelvis_r @ (self._rest(f"thigh_{s}") - self._rest("pelvis"))
            rest_ankle = self._rest(f"foot_{s}")
            ankle = rest_ankle + np.array([side * width, 0.0, 0.0]) + st["offset"]
            foot_r = rot(Y, side * -8.0)
            lift = k.heel if s == "r" else k.lheel
            if lift:
                # Pivot round the ball of the foot, turning towards the target.
                ball = self._rest(f"ball_{s}") + np.array([side * width, 0, 0]) + st["offset"]
                spin = rot(Y, -0.6 * lift if s == "r" else 0.2 * lift)
                foot_r = spin @ rot(X, lift) @ foot_r
                ankle = ball + foot_r @ (rest_ankle - self._rest(f"ball_{s}"))
            pole = unit(np.array([side * 0.25, 0.0, -1.0]) + (k.hips / 90.0) * np.array([-0.6, 0, 0]))
            knee, end, bend, d = self._two_bone(hip, ankle, self.thigh[s], self.shin[s], pole)
            n = unit(np.cross(bend, d))
            t0 = self._rest(f"calf_{s}") - self._rest(f"thigh_{s}")
            c0 = self._rest(f"foot_{s}") - self._rest(f"calf_{s}")
            R[f"thigh_{s}"] = aim(t0, unit(np.cross(unit(t0), Z)), knee - hip, n)
            R[f"calf_{s}"] = aim(c0, unit(np.cross(unit(c0), Z)), end - knee, n)
            R[f"foot_{s}"] = foot_r
            R[f"ball_{s}"] = rot(X, -lift) @ foot_r if lift else foot_r

    # ---- to joint-local --------------------------------------------------

    def locals(self, R, root_p):
        """Joint-local rotations (quaternions) and the root translation."""
        world = {}
        out = []
        for i, name in enumerate(self.names):
            p = self.parents[i]
            parent_world = world[self.names[p]] if p >= 0 else np.eye(3)
            r = R.get(name, parent_world)
            world[name] = r
            out.append(quat(parent_world.T @ r))
        club_local = quat(world["hand_l"].T @ R.get("club", world["hand_l"]))
        return out, club_local, root_p


def interpolate(keys, t):
    """Smooth (Catmull-Rom) interpolation of every Key field at time t."""
    times = [k.t for k in keys]
    if t <= times[0]:
        return replace(keys[0], t=t)
    if t >= times[-1]:
        return replace(keys[-1], t=t)
    i = max(j for j in range(len(keys) - 1) if times[j] <= t)
    k0, k1 = keys[max(i - 1, 0)], keys[i]
    k2, k3 = keys[i + 1], keys[min(i + 2, len(keys) - 1)]
    u = (t - k1.t) / (k2.t - k1.t)
    out = {}
    for name in Key.__dataclass_fields__:
        if name == "t":
            continue
        p0, p1, p2, p3 = (getattr(k, name) for k in (k0, k1, k2, k3))
        # Tangents scaled by the key spacing so uneven keys don't overshoot.
        d1 = (p2 - p0) / max(k2.t - k0.t, 1e-6) * (k2.t - k1.t)
        d2 = (p3 - p1) / max(k3.t - k1.t, 1e-6) * (k2.t - k1.t)
        h00 = 2 * u ** 3 - 3 * u ** 2 + 1
        h10 = u ** 3 - 2 * u ** 2 + u
        h01 = -2 * u ** 3 + 3 * u ** 2
        h11 = u ** 3 - u ** 2
        out[name] = h00 * p1 + h10 * d1 + h01 * p2 + h11 * d2
    return Key(t=t, **out)
