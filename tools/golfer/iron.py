"""The iron the free golfer swings for every club but the woods: its mesh,
and the address pose it is measured from (ref_address_iron).

The golfer's hand-keyed address poses come from pose.Poser, which
build_free_golfer.py runs on the MakeHuman skeleton. The .glb holds that
skeleton's rest pose, so the Poser is rebuilt from it here and posed for a
shorter, more upright iron: the ball comes closer to the feet and the
knees flex a little. For both clubs the hands sit as far from the chest as
leaves the lead arm nearly straight (LEAD_BEND); the original driver
address had it bent 55 degrees, pulling the hands into the body.
"""

import numpy as np

import build_free_golfer
import pose

# A mid iron: grip point (left palm) to hosel, lie, head toe offset.
IRON = pose.Club("Iron", 0.84, 62.0, 0.04)
IRON_KEY = pose.Key(tilt=36.0, sink=0.01)
LEAD_BEND = 12.0  # degrees at the lead elbow at address: nearly straight
# The driver: more upright, the ball further away, the lead arm a little softer.
DRIVER_KEY = pose.Key(tilt=28.0)
DRIVER_LEAD_BEND = 30.0
FINGERS = ("thumb", "index", "middle", "ring", "pinky")


class _Human:
    """What pose.Poser reads from a MakeHuman skeleton, from the .glb rig."""

    def __init__(self, rig):
        _, rest = rig.world([np.eye(3)] * len(rig.names), rig.offsets[0])
        self.bones = [n for n in rig.names if n != "club"]
        self.parents = []
        for n in self.bones:
            p = rig.parents[rig.index[n]]
            self.parents.append(self.bones.index(rig.names[p]) if p >= 0 else -1)
        self.heads = np.array([rest[rig.index[n]] for n in self.bones])
        tails = []
        for i in range(len(self.bones)):
            kids = [j for j, p in enumerate(self.parents) if p == i]
            if kids:
                tails.append(self.heads[kids[0]])
            else:
                tails.append(self.heads[i] + 0.8 * (self.heads[i] - self.heads[self.parents[i]]))
        self.tails = np.array(tails)


def poser(rig):
    return pose.Poser(_Human(rig))


def stance(p, club, forward):
    """pose.Poser._stance with the hands `forward` metres further out from
    the chest, the body moved back so the club still meets the ball."""
    st = p._stance(club, 0.0)
    st["grip"] = st["grip"] + np.array([0.0, 0.0, -forward])
    hosel = st["grip"] + st["shaft"] * club.length
    toe = pose.Poser._toe(st["shaft"], -pose.X, club)
    ball_at = hosel + toe * club.head_toe * 0.8 - pose.X * 0.03
    shift = np.array([pose.BALL[0] - ball_at[0], 0.0, pose.BALL[2] - ball_at[2]])
    for k in ("grip", "offset", "centre"):
        st[k] = st[k] + shift
    return st


def lead_reach(rig, local, root):
    world, poss = rig.world(local, root)
    return np.linalg.norm(poss[rig.index["hand_l"]] - poss[rig.index["upperarm_l"]])


def address_locals(rig, p, club, key, forward=None, bend=None):
    """Joint-local rotation matrices and root translation of an address.
    Without `forward`, the hands go as far out as gives the lead arm
    `bend` degrees (LEAD_BEND by default) at the elbow."""
    if forward is None:
        l1, l2 = p.upper["l"], p.fore["l"]
        want = np.sqrt(l1 * l1 + l2 * l2 + 2 * l1 * l2 * np.cos(np.radians(LEAD_BEND if bend is None else bend)))
        lo, hi = -0.1, 0.3
        for _ in range(30):
            mid = (lo + hi) / 2
            if lead_reach(rig, *address_locals(rig, p, club, key, mid)) < want:
                lo = mid
            else:
                hi = mid
        forward = (lo + hi) / 2
    p.stances[0] = stance(p, club, forward)
    world, root, _ = p.pose(key)
    quats, club_local, root = p.locals(world, root)
    by_name = dict(zip(p.names, quats))
    by_name["club"] = club_local
    return [pose.matrix(by_name[n]) for n in rig.names], np.array(root, dtype=np.float32)


def club_mesh(p):
    """The iron's grip, shaft and blade in the rest frame."""
    parts = build_free_golfer.club_parts(p, IRON)
    grip = p.grip_rest["l"]
    a = p.club_dir_rest["l"]
    f = p.face_rest["l"]
    toe = pose.Poser._toe(a, f, IRON)
    up = pose.unit(np.cross(toe, f))
    if np.dot(up, a) > 0:
        up = -up
    hosel = grip + a * IRON.length
    # A cavity-back blade: 76 mm heel to toe, 46 mm tall, 14 mm thick.
    centre = hosel + toe * 0.042 + up * 0.019 - f * 0.004
    blade = build_free_golfer.box(centre, np.column_stack([toe, f, up]), np.array([0.038, 0.007, 0.023]))
    return [(n, m) for n, m in parts if n != "head"] + [("head", blade)]


def ensure_iron(glb, rig):
    """Adds the iron mesh and ref_address_iron if the .glb lacks them, and
    the driver's address with the lead arm nearly straight
    (ref_address, marked done by ref_address_v2)."""
    p = poser(rig)
    if not glb.animation("ref_address_v2"):
        from mocap_swing import write_clip
        old, _ = rig.sample(glb, "ref_address")
        local, root = address_locals(rig, p, pose.DRIVER, DRIVER_KEY, bend=DRIVER_LEAD_BEND)
        for j, name in enumerate(rig.names):
            if name.split("_")[0] in FINGERS:
                local[j] = old[j]
        for name in ("ref_address", "ref_address_v2"):
            write_clip(glb, rig, name, np.zeros(1, np.float32), [local], np.array([root]), filtered=False)
    if not glb.animation("ref_address_iron"):
        # Imported here: mocap_swing imports this module.
        from mocap_swing import write_clip
        local, root = address_locals(rig, p, IRON, IRON_KEY)
        # The fingers wrap the grip as they do on the driver: the rebuilt
        # Poser's curl axes are only estimates (the .glb has no bone tails).
        driver, _ = rig.sample(glb, "ref_address")
        for j, name in enumerate(rig.names):
            if name.split("_")[0] in FINGERS:
                local[j] = driver[j]
        write_clip(glb, rig, "ref_address_iron", np.zeros(1, np.float32), [local], np.array([root]),
                   filtered=False)
    doc = glb.doc
    if any(n.get("name") == "Iron_head" for n in doc["nodes"]):
        return
    mats = {m["name"]: i for i, m in enumerate(doc["materials"])}
    head_mat = dict(doc["materials"][mats["PutterHead"]], name="IronHead")
    doc["materials"].append(head_mat)
    material = {"grip": mats["Grip"], "shaft": mats["Shaft"], "head": len(doc["materials"]) - 1}
    skin = next(n["skin"] for n in doc["nodes"] if n.get("name") == "Driver_head")
    joint = doc["skins"][skin]["joints"].index(
        next(i for i, n in enumerate(doc["nodes"]) if n.get("name") == "club"))
    for piece, (pos, nrm, idx) in club_mesh(p):
        n = len(pos)
        prim = {"attributes": {
            "POSITION": glb.add(pos, minmax=True),
            "NORMAL": glb.add(nrm),
            "TEXCOORD_0": glb.add(np.zeros((n, 2))),
            "JOINTS_0": glb.add(np.tile([joint, 0, 0, 0], (n, 1)), component=5121),
            "WEIGHTS_0": glb.add(np.tile([1.0, 0, 0, 0], (n, 1)))},
            "indices": glb.add(np.asarray(idx).reshape(-1), component=5125),
            "material": material[piece]}
        for k in ("POSITION", "NORMAL", "TEXCOORD_0", "JOINTS_0", "WEIGHTS_0"):
            glb.doc["bufferViews"][glb.doc["accessors"][prim["attributes"][k]]["bufferView"]]["target"] = 34962
        glb.doc["bufferViews"][glb.doc["accessors"][prim["indices"]]["bufferView"]]["target"] = 34963
        doc["meshes"].append({"name": f"Iron_{piece}", "primitives": [prim]})
        doc["nodes"].append({"name": f"Iron_{piece}", "mesh": len(doc["meshes"]) - 1, "skin": skin})
        doc["scenes"][0]["nodes"].append(len(doc["nodes"]) - 1)
