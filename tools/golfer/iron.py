"""The iron the free golfer swings for every club but the woods: its mesh,
and the address pose it is measured from (ref_address_iron).

The golfer's hand-keyed address poses come from pose.Poser, which
build_free_golfer.py runs on the MakeHuman skeleton. The .glb holds that
skeleton's rest pose, so the Poser is rebuilt from it here and posed for a
shorter, more upright iron: the ball comes closer to the feet, the chest
bends a little more and the knees flex, and the arms hang instead of
reaching (they are straight at the driver's address).
"""

import numpy as np

import build_free_golfer
import pose

# A mid iron: grip point (left palm) to hosel, lie, head toe offset.
IRON = pose.Club("Iron", 0.84, 62.0, 0.04)
IRON_KEY = pose.Key(tilt=40.0, sink=0.02)


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


def address_locals(rig, p, club, key):
    """Joint-local rotation matrices and root translation of an address."""
    p.stances[0] = p._stance(club, 0.0)
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
    """Adds the iron mesh and ref_address_iron if the .glb lacks them."""
    p = poser(rig)
    if not glb.animation("ref_address_iron"):
        # Imported here: mocap_swing imports this module.
        from mocap_swing import write_clip
        local, root = address_locals(rig, p, IRON, IRON_KEY)
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
