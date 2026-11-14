#!/usr/bin/env python3
"""A golf swing tracked from real footage, read like a mocap take.

The CMU mocap actor (take 64_01) is an amateur: his trail elbow flies out
behind him at the top and his arms hang slack at impact, and every
correction layered over that showed up somewhere else. This builds the
swing instead from a real golfer filmed in slow motion (Wikimedia Commons,
"Suvichaya Vinijchaitham Golf Swing Slow Mo 2026", CC0, the same footage as
the photo golfer), tracked frame by frame in 3D (track_footage.py, which
writes tools/golfer/footage/<take>.json).

FootageTake looks like mocap_swing.Bvh to the retarget: names and index
in the CMU skeleton's naming, and frame(f) giving every joint's world
rotation and position at 120 frames a second (MOCAP_FPS). The retarget only
uses each joint's turn from the address frame (R_f @ R_0.T), so each
segment's frame is built from the tracked points in any consistent way:
- pelvis from the hip line and the spine, chest from the shoulder line and
  the spine, the spine bones between them, the head from the ears;
- each limb bone along its two joints, twisted by its next bone (or for a
  straight arm, by the chest);
- the feet from heel to toe.
The tracker gives points about the hips; the feet are planted to put the
body back in the world (both feet to impact, the lead foot after).
The club and wrists are posed by the retarget (the swing-plane hinge), so
the hands just follow the forearms.
"""

import json
import math
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
FPS = 120.0
SHOULDER_SMOOTH = 4.0  # frames (at FPS) the shoulder depth is smoothed over
HIP_SHIFT = 0.10  # metres the hips move towards the target from the top to impact

# MediaPipe pose landmarks.
NOSE, L_EAR, R_EAR = 0, 7, 8
L_SH, R_SH, L_EL, R_EL, L_WR, R_WR = 11, 12, 13, 14, 15, 16
L_PINKY, R_PINKY, L_INDEX, R_INDEX = 17, 18, 19, 20
L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANK, R_ANK = 23, 24, 25, 26, 27, 28
L_HEEL, R_HEEL, L_TOE, R_TOE = 29, 30, 31, 32

NAMES = ["Hips", "LowerBack", "Spine", "Spine1", "Neck1", "Head",
         "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
         "RightShoulder", "RightArm", "RightForeArm", "RightHand",
         "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
         "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]


def _unit(v):
    return v / max(np.linalg.norm(v), 1e-9)


def _frame(primary, secondary):
    """Rotation whose x is along primary, with secondary in its xy plane."""
    x = _unit(primary)
    z = _unit(np.cross(x, secondary))
    y = np.cross(z, x)
    return np.column_stack([x, y, z])


def _slerp(a, b, t):
    r = a.T @ b
    c = np.clip((np.trace(r) - 1) / 2, -1, 1)
    ang = math.acos(c)
    if ang < 1e-6:
        return a
    axis = np.array([r[2, 1] - r[1, 2], r[0, 2] - r[2, 0], r[1, 0] - r[0, 1]]) / (2 * math.sin(ang))
    k = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    s = ang * t
    return a @ (np.eye(3) + math.sin(s) * k + (1 - math.cos(s)) * k @ k)


def _smooth(x, sigma):
    """Gaussian smoothing along axis 0, edges held."""
    if sigma <= 0:
        return x
    r = int(3 * sigma)
    w = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    w /= w.sum()
    pad = np.concatenate([np.repeat(x[:1], r, 0), x, np.repeat(x[-1:], r, 0)])
    out = np.zeros_like(x)
    for k, wk in enumerate(w):
        out += wk * pad[k:k + len(x)]
    return out


class FootageTake:
    def __init__(self, path):
        data = json.load(open(path))
        meta = data["meta"]
        pts = np.array([[p[:3] for p in fr] for fr in data["world"]], dtype=float)
        # Tracker axes: x right in the picture, y down, z towards the
        # camera's back. Turned 180 deg about x: y up, still right-handed.
        pts[..., 1] *= -1
        pts[..., 2] *= -1
        pts = _smooth(pts, meta.get("smooth", 1.5))
        self.src_fps = meta["fps"]  # tracked frames per real second
        n = len(pts)
        # Resample to FPS.
        t_src = np.arange(n) / self.src_fps
        t = np.arange(0.0, t_src[-1] + 1e-9, 1.0 / FPS)
        res = np.empty((len(t),) + pts.shape[1:])
        for j in range(pts.shape[1]):
            for a in range(3):
                res[:, j, a] = np.interp(t, t_src, pts[:, j, a])
        res = self._turn(res, meta)
        self.phase_src = meta["phases"]
        res = self._arms(res)
        self.pts = self._plant(res, meta)
        self.names = NAMES
        self.index = {nm: k for k, nm in enumerate(NAMES)}
        self.frames = len(t)
        # Phase frames at FPS (from the tracked frame numbers).
        k = FPS / self.src_fps
        self.phase = {key: int(round(v * k)) for key, v in meta["phases"].items()}

    def _turn(self, p, meta):
        """Scales the shoulder turn of the backswing to TURN_SCALE. From
        one camera the tracker overstates how far the shoulders turn away
        (130 deg at the top, against about 90 for a tour player, measured
        from 3D capture): the upper body's points turn back about the
        spine, fully to the top, easing out by impact."""
        k = meta.get("turn_scale", 1.0)
        if k == 1.0:
            return p
        top = meta["phases"]["top"] * FPS / self.src_fps
        impact = meta["phases"]["impact"] * FPS / self.src_fps
        sh = p[:, L_SH] - p[:, R_SH]
        yaw = np.unwrap(np.arctan2(sh[:, 2], sh[:, 0]))
        yaw -= yaw[0]
        out = p.copy()
        upper = [NOSE, L_EAR, R_EAR, L_SH, R_SH, L_EL, R_EL, L_WR, R_WR, L_PINKY, R_PINKY, L_INDEX, R_INDEX,
                 1, 2, 3, 4, 5, 6, 9, 10, 21, 22]
        for f in range(len(p)):
            if f <= top:
                w = 1.0
            else:
                u = min(1.0, (f - top) / max(1.0, impact - top))
                w = 1.0 - u * u * (3 - 2 * u)
            c = (k - 1.0) * yaw[f] * w
            hip = (p[f, L_HIP] + p[f, R_HIP]) / 2
            axis = _unit((p[f, L_SH] + p[f, R_SH]) / 2 - hip)
            kx = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
            # The yaw was measured about +y; turning about the spine by the
            # same angle with the right sign.
            r = np.eye(3) + math.sin(-c) * kx + (1 - math.cos(-c)) * kx @ kx
            if np.dot(axis, [0, 1, 0]) < 0:
                r = r.T
            out[f, upper] = hip + (p[f, upper] - hip) @ r.T
        return out

    def _arms(self, p):
        """Fixes the arms' depth. From down the line the camera sees each
        point's height and its distance from the ball (x and y here) well,
        but its place along the target line (z, the depth) is the
        tracker's guess, and at the top it put the hands behind the head.
        The lead arm stays nearly straight, so its wrist is the arm's
        length from the shoulder: z follows from x and y (the root nearer
        the guess). The trail wrist keeps its offset from the lead one
        on the grip, and each elbow is its upper arm's length from the
        shoulder."""
        out = p.copy()
        # The shoulders: their centre stays over the hips along the target
        # line as at address (the tracker drifted it 30 cm towards the
        # target at the top), and the line between them keeps its length,
        # its depth from its seen length (the sign as the tracker had it).
        width = float(np.median(np.linalg.norm(p[:, L_SH] - p[:, R_SH], axis=1)))
        hip_c = (p[:, L_HIP, 2] + p[:, R_HIP, 2]) / 2
        sh_c = (p[:, L_SH, 2] + p[:, R_SH, 2]) / 2
        off = sh_c[0] - hip_c[0]
        head_off = (p[0, L_EAR, 2] + p[0, R_EAR, 2]) / 2 - sh_c[0]
        # Near the top the shoulder line points almost at the camera, so
        # its seen length says little and the depth jumps by tens of
        # degrees of turn from frame to frame: smoothed over ~50 ms.
        dzs = np.empty(len(p))
        for f in range(len(p)):
            seen = out[f, L_SH, :2] - out[f, R_SH, :2]
            h = max(0.0, width * width - float(seen @ seen))
            dzs[f] = math.copysign(math.sqrt(h), out[f, L_SH, 2] - out[f, R_SH, 2])
        dzs = _smooth(dzs[:, None], SHOULDER_SMOOTH)[:, 0]
        for f in range(len(p)):
            q = out[f]
            dz = dzs[f]
            c = hip_c[f] + off
            moved = c - sh_c[f]
            q[L_SH, 2], q[R_SH, 2] = c + dz / 2, c - dz / 2
            for j in (NOSE, L_EAR, R_EAR, 1, 2, 3, 4, 5, 6, 9, 10):
                q[j, 2] += moved
            ears = (q[L_EAR, 2] + q[R_EAR, 2]) / 2
            for j in (NOSE, L_EAR, R_EAR, 1, 2, 3, 4, 5, 6, 9, 10):
                q[j, 2] += c + head_off - ears
            for j in (L_EL, R_EL, L_WR, R_WR, L_PINKY, R_PINKY, L_INDEX, R_INDEX, 21, 22):
                q[j, 2] += moved

        def length(a, b):
            return float(np.median(np.linalg.norm(p[:, a] - p[:, b], axis=1)))

        def solve(base, point, guess, d):
            flat = point[:2] - base[:2]
            h = d * d - float(flat @ flat)
            if h <= 0.0:
                return base[2]
            r = math.sqrt(h)
            a, b = base[2] + r, base[2] - r
            return a if abs(a - guess) < abs(b - guess) else b

        lead = 0.97 * (length(L_SH, L_EL) + length(L_EL, L_WR))
        up_l, up_r = length(L_SH, L_EL), length(R_SH, R_EL)
        impact = self.phase_src["impact"] * FPS / self.src_fps
        for f in range(len(p)):
            q = out[f]
            old_wr = q[L_WR].copy()
            # Which side of the lead shoulder the hands are: away from the
            # target (+z, towards the camera behind the trail side) until
            # impact, towards it after.
            side = 1.0 if f < impact else -1.0
            q[L_WR, 2] = solve(q[L_SH], q[L_WR], q[L_SH, 2] + side, lead)
            dz = q[L_WR, 2] - old_wr[2]
            for j in (L_PINKY, L_INDEX, 21):
                q[j, 2] += dz
            # Both hands on the grip: the trail hand at the lead one's depth.
            dzr = q[L_WR, 2] - q[R_WR, 2]
            for j in (R_WR, R_PINKY, R_INDEX, 22):
                q[j, 2] += dzr
            # The lead elbow on the straight arm's line; the trail one its
            # upper arm's length out, on the side nearer the hands.
            t = up_l / lead
            q[L_EL, 2] = q[L_SH, 2] + t * (q[L_WR, 2] - q[L_SH, 2])
            q[R_EL, 2] = solve(q[R_SH], q[R_EL], 0.5 * (q[R_SH, 2] + q[R_WR, 2]), up_r)
        arms = [L_EL, R_EL, L_WR, R_WR, L_PINKY, R_PINKY, L_INDEX, R_INDEX, 21, 22]
        out[:, arms, 2] = _smooth(out[:, arms, 2], 2.0)
        return out

    def _plant(self, p, meta):
        """Puts the tracked body (centred on its hips) back on its feet."""
        impact = meta["phases"]["impact"] * FPS / self.src_fps
        out = p.copy()
        n = len(p)
        for f in range(n):
            both = 0.5 * ((p[0, L_ANK] - p[f, L_ANK]) + (p[0, R_ANK] - p[f, R_ANK]))
            lead = p[0, L_ANK] - p[f, L_ANK]
            u = np.clip((f - impact) / (0.15 * FPS), 0.0, 1.0)
            out[f] += (1 - u) * both + u * lead
        # The hips along the target line: from one camera the tracker's
        # depth slid them 22 cm towards the target by the top. Tour hips
        # hold over the feet to the top, then shift about 10 cm towards
        # the target into impact (HIP_SHIFT).
        top = meta["phases"]["top"] * FPS / self.src_fps
        hz0 = (out[0, L_HIP, 2] + out[0, R_HIP, 2]) / 2
        feet = [L_ANK, R_ANK, L_HEEL, R_HEEL, L_TOE, R_TOE]
        for f in range(n):
            u = np.clip((f - top) / max(1.0, impact - top), 0.0, 1.0)
            want = hz0 - HIP_SHIFT * u * u * (3 - 2 * u)
            d = (out[f, L_HIP, 2] + out[f, R_HIP, 2]) / 2 - want
            for j in range(out.shape[1]):
                if j in feet:
                    continue
                out[f, j, 2] -= d * (0.5 if j in (L_KNEE, R_KNEE) else 1.0)
        return out

    def frame(self, f):
        """World rotations and positions of every joint at frame f. The
        head holds its address turn (eyes on the ball) to impact, then turns
        with the chest to watch the shot: the tracker's head (two ear
        points) wobbles by tens of degrees."""
        rots, poss = self._raw(f)
        a = self.phase["address"]
        if not hasattr(self, "_addr"):
            self._addr = self._raw(a)[0]
        r0 = self._addr
        h, n, c = self.index["Head"], self.index["Neck1"], self.index["Spine1"]
        u = np.clip((f - self.phase["impact"]) / (0.25 * FPS), 0.0, 1.0)
        follow = rots[c] @ r0[c].T @ r0[h]
        rots[h] = _slerp(r0[h], follow, 0.7 * u * u * (3 - 2 * u))
        rots[n] = _slerp(rots[c] @ r0[c].T @ r0[n], rots[h] @ r0[h].T @ r0[n], 0.5)
        return rots, poss

    def _raw(self, f):
        f = int(np.clip(f, 0, self.frames - 1))
        p = self.pts[f]
        up = (p[L_SH] + p[R_SH]) / 2 - (p[L_HIP] + p[R_HIP]) / 2
        hips = _frame(p[L_HIP] - p[R_HIP], up)
        chest = _frame(p[L_SH] - p[R_SH], up)
        ears = (p[L_EAR] + p[R_EAR]) / 2
        neck_pos = (p[L_SH] + p[R_SH]) / 2
        head = _frame(p[L_EAR] - p[R_EAR], ears - neck_pos)
        chest_fwd = np.cross(chest[:, 0], up)
        rots, poss = {}, {}
        hip_mid = (p[L_HIP] + p[R_HIP]) / 2
        rots["Hips"], poss["Hips"] = hips, hip_mid
        for nm, t in (("LowerBack", 1 / 3), ("Spine", 2 / 3)):
            rots[nm], poss[nm] = _slerp(hips, chest, t), hip_mid + t * up * 0.8
        rots["Spine1"], poss["Spine1"] = chest, hip_mid + 0.8 * up
        rots["Neck1"], poss["Neck1"] = _slerp(chest, head, 0.5), neck_pos
        rots["Head"], poss["Head"] = head, ears
        for side, sh, el, wr, idx, pk, hip, kn, an, he, to in (
                ("Left", L_SH, L_EL, L_WR, L_INDEX, L_PINKY, L_HIP, L_KNEE, L_ANK, L_HEEL, L_TOE),
                ("Right", R_SH, R_EL, R_WR, R_INDEX, R_PINKY, R_HIP, R_KNEE, R_ANK, R_HEEL, R_TOE)):
            upper, fore = p[el] - p[sh], p[wr] - p[el]
            bend = math.degrees(math.acos(np.clip(np.dot(_unit(upper), _unit(fore)), -1, 1)))
            w = np.clip((bend - 10.0) / 25.0, 0.0, 1.0)  # a straight arm's twist comes from the chest
            sec = w * _unit(fore) + (1 - w) * _unit(chest_fwd)
            rots[side + "Shoulder"], poss[side + "Shoulder"] = chest, p[sh]
            rots[side + "Arm"], poss[side + "Arm"] = _frame(upper, sec), p[sh]
            hand_dir = p[idx] - p[pk]
            rots[side + "ForeArm"], poss[side + "ForeArm"] = _frame(fore, hand_dir), p[el]
            rots[side + "Hand"], poss[side + "Hand"] = rots[side + "ForeArm"], p[wr]
            toe = p[to] - p[he]
            thigh, shin = p[kn] - p[hip], p[an] - p[kn]
            rots[side + "UpLeg"], poss[side + "UpLeg"] = _frame(thigh, toe), p[hip]
            rots[side + "Leg"], poss[side + "Leg"] = _frame(shin, toe), p[kn]
            rots[side + "Foot"], poss[side + "Foot"] = _frame(toe, p[an] - p[he]), p[an]
            rots[side + "ToeBase"], poss[side + "ToeBase"] = rots[side + "Foot"], p[to]
        return (np.array([rots[nm] for nm in NAMES]), np.array([poss[nm] for nm in NAMES]))


def load(name):
    return FootageTake(os.path.join(HERE, "footage", name + ".json"))
