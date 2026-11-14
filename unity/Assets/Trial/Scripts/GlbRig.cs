using System;
using System.Collections.Generic;
using System.Text;
using UnityEngine;

// The game's golfer rig and mocap clips (game/assets/golfer/free_golfer.glb),
// read straight from the .glb: the joints become Transforms, the clips are
// sampled by hand, and the driver's meshes ride on the club joint. glTF is
// right-handed, so x is mirrored into Unity's left-handed space.
public class GlbRig
{
    [Serializable] class GNode { public string name; public float[] translation; public float[] rotation; public float[] scale; public int[] children; public int mesh = -1; public int skin = -1; }
    [Serializable] class GAttr { public int POSITION = -1; public int NORMAL = -1; public int JOINTS_0 = -1; }
    [Serializable] class GPrim { public GAttr attributes; public int indices = -1; }
    [Serializable] class GMesh { public string name; public GPrim[] primitives; }
    [Serializable] class GAcc { public int bufferView; public int byteOffset; public int componentType; public int count; public string type; }
    [Serializable] class GView { public int byteOffset; public int byteLength; public int byteStride; }
    [Serializable] class GTarget { public int node; public string path; }
    [Serializable] class GChan { public int sampler; public GTarget target; }
    [Serializable] class GSamp { public int input; public int output; public string interpolation; }
    [Serializable] class GAnim { public string name; public GChan[] channels; public GSamp[] samplers; }
    [Serializable] class GSkin { public int inverseBindMatrices = -1; public int[] joints; }
    [Serializable] class GRoot { public GNode[] nodes; public GMesh[] meshes; public GAcc[] accessors; public GView[] bufferViews; public GAnim[] animations; public GSkin[] skins; }

    public class Channel { public Transform t; public int path; public float[] times; public float[] values; }
    public class Clip { public string name; public float length; public List<Channel> channels = new List<Channel>(); }

    public Transform root;  // the "Root" joint's parent
    public readonly Dictionary<string, Transform> bones = new Dictionary<string, Transform>();
    public readonly Dictionary<string, Clip> clips = new Dictionary<string, Clip>();
    readonly Dictionary<Transform, (Vector3, Quaternion, Vector3)> rest = new Dictionary<Transform, (Vector3, Quaternion, Vector3)>();

    GRoot g;
    byte[] bin;

    public static GlbRig Load(byte[] glb, Transform parent)
    {
        var r = new GlbRig();
        int jsonLen = BitConverter.ToInt32(glb, 12);
        r.g = JsonUtility.FromJson<GRoot>(Encoding.UTF8.GetString(glb, 20, jsonLen));
        int binAt = 20 + jsonLen;
        int binLen = BitConverter.ToInt32(glb, binAt);
        r.bin = new byte[binLen];
        Buffer.BlockCopy(glb, binAt + 8, r.bin, 0, binLen);

        r.root = new GameObject("GolferRig").transform;
        r.root.SetParent(parent, false);
        var made = new Transform[r.g.nodes.Length];
        var skinJoints = new HashSet<int>(r.g.skins[0].joints);
        for (int i = 0; i < r.g.nodes.Length; i++)
            if (skinJoints.Contains(i)) made[i] = new GameObject(r.g.nodes[i].name).transform;
        for (int i = 0; i < r.g.nodes.Length; i++)
        {
            if (made[i] == null) continue;
            var n = r.g.nodes[i];
            if (n.children != null) foreach (var c in n.children) if (made[c] != null) made[c].SetParent(made[i], false);
            var t = Arr(n.translation, 0, 0, 0);
            var q = Arr(n.rotation, 0, 0, 0, 1);
            var s = Arr(n.scale, 1, 1, 1);
            made[i].localPosition = new Vector3(-t[0], t[1], t[2]);
            made[i].localRotation = new Quaternion(q[0], -q[1], -q[2], q[3]);
            made[i].localScale = new Vector3(s[0], s[1], s[2]);
        }
        for (int i = 0; i < made.Length; i++)
        {
            if (made[i] == null) continue;
            if (made[i].parent == null) made[i].SetParent(r.root, false);
            r.bones[made[i].name] = made[i];
            r.rest[made[i]] = (made[i].localPosition, made[i].localRotation, made[i].localScale);
        }
        foreach (var a in r.g.animations) r.clips[a.name] = r.ReadClip(a, made);
        return r;
    }

    static float[] Arr(float[] a, params float[] def) => a != null && a.Length == def.Length ? a : def;

    Clip ReadClip(GAnim a, Transform[] made)
    {
        var c = new Clip { name = a.name };
        foreach (var ch in a.channels)
        {
            var t = made[ch.target.node];
            if (t == null) continue;
            var s = a.samplers[ch.sampler];
            int path = ch.target.path == "translation" ? 0 : ch.target.path == "rotation" ? 1 : 2;
            var k = new Channel { t = t, path = path, times = Floats(s.input), values = Floats(s.output) };
            if (k.times.Length > 0) c.length = Mathf.Max(c.length, k.times[k.times.Length - 1]);
            c.channels.Add(k);
        }
        return c;
    }

    float[] Floats(int accessor)
    {
        var a = g.accessors[accessor];
        var v = g.bufferViews[a.bufferView];
        int comps = a.type == "SCALAR" ? 1 : a.type == "VEC2" ? 2 : a.type == "VEC3" ? 3 : a.type == "VEC4" ? 4 : 16;
        int stride = v.byteStride > 0 ? v.byteStride : comps * 4;
        var o = new float[a.count * comps];
        for (int i = 0; i < a.count; i++)
            for (int k = 0; k < comps; k++)
                o[i * comps + k] = BitConverter.ToSingle(bin, v.byteOffset + a.byteOffset + i * stride + k * 4);
        return o;
    }

    int[] Ints(int accessor)
    {
        var a = g.accessors[accessor];
        var v = g.bufferViews[a.bufferView];
        int comps = a.type == "SCALAR" ? 1 : 4;
        int size = a.componentType == 5125 ? 4 : a.componentType == 5123 ? 2 : 1;
        int stride = v.byteStride > 0 ? v.byteStride : comps * size;
        var o = new int[a.count * comps];
        for (int i = 0; i < a.count; i++)
            for (int k = 0; k < comps; k++)
            {
                int at = v.byteOffset + a.byteOffset + i * stride + k * size;
                o[i * comps + k] = size == 4 ? BitConverter.ToInt32(bin, at) : size == 2 ? BitConverter.ToUInt16(bin, at) : bin[at];
            }
        return o;
    }

    public void ResetPose()
    {
        foreach (var kv in rest) { kv.Key.localPosition = kv.Value.Item1; kv.Key.localRotation = kv.Value.Item2; kv.Key.localScale = kv.Value.Item3; }
    }

    public void Sample(Clip c, float time)
    {
        foreach (var ch in c.channels)
        {
            var ts = ch.times;
            int i = 0;
            if (ts.Length > 1)
            {
                int lo = 0, hi = ts.Length - 1;
                if (time <= ts[0]) hi = 0;
                else if (time >= ts[hi]) lo = hi;
                else while (hi - lo > 1) { int m = (lo + hi) / 2; if (ts[m] <= time) lo = m; else hi = m; }
                i = lo;
            }
            int j = Mathf.Min(i + 1, ts.Length - 1);
            float f = j == i ? 0 : Mathf.Clamp01((time - ts[i]) / (ts[j] - ts[i]));
            var v = ch.values;
            if (ch.path == 1)
            {
                var a = new Quaternion(v[i * 4], -v[i * 4 + 1], -v[i * 4 + 2], v[i * 4 + 3]);
                var b = new Quaternion(v[j * 4], -v[j * 4 + 1], -v[j * 4 + 2], v[j * 4 + 3]);
                ch.t.localRotation = Quaternion.Slerp(a, b, f);
            }
            else
            {
                var a = new Vector3(v[i * 3], v[i * 3 + 1], v[i * 3 + 2]);
                var b = new Vector3(v[j * 3], v[j * 3 + 1], v[j * 3 + 2]);
                var p = Vector3.Lerp(a, b, f);
                if (ch.path == 0) ch.t.localPosition = new Vector3(-p.x, p.y, p.z);
                else ch.t.localScale = p;
            }
        }
    }

    // The meshes skinned to `joint` whose names start with `prefix` (the
    // driver: "Driver_grip", "Driver_shaft", "Driver_head"), in that joint's
    // own space, as one mesh. Also returns the club head's centre.
    public Mesh JointMesh(string prefix, string joint, out Vector3 headCentre)
    {
        var skin = g.skins[0];
        int jointIndex = Array.FindIndex(skin.joints, k => g.nodes[k].name == joint);
        var ibm = Floats(skin.inverseBindMatrices);
        var m = new Matrix4x4();
        for (int k = 0; k < 16; k++) m[k % 4, k / 4] = ibm[jointIndex * 16 + k];
        var verts = new List<Vector3>();
        var norms = new List<Vector3>();
        var tris = new List<int>();
        headCentre = Vector3.zero;
        foreach (var n in g.nodes)
        {
            if (n.mesh < 0 || !n.name.StartsWith(prefix)) continue;
            var headStart = verts.Count;
            foreach (var p in g.meshes[n.mesh].primitives)
            {
                int start = verts.Count;
                var pos = Floats(p.attributes.POSITION);
                var nor = p.attributes.NORMAL >= 0 ? Floats(p.attributes.NORMAL) : null;
                for (int i = 0; i < pos.Length / 3; i++)
                {
                    var v = m.MultiplyPoint3x4(new Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]));
                    verts.Add(new Vector3(-v.x, v.y, v.z));
                    if (nor != null)
                    {
                        var w = m.MultiplyVector(new Vector3(nor[i * 3], nor[i * 3 + 1], nor[i * 3 + 2])).normalized;
                        norms.Add(new Vector3(-w.x, w.y, w.z));
                    }
                    else norms.Add(Vector3.up);
                }
                var idx = p.indices >= 0 ? Ints(p.indices) : null;
                int count = idx != null ? idx.Length : pos.Length / 3;
                for (int i = 0; i + 2 < count; i += 3)
                {
                    int a = idx != null ? idx[i] : i, b = idx != null ? idx[i + 1] : i + 1, c = idx != null ? idx[i + 2] : i + 2;
                    tris.Add(start + a); tris.Add(start + c); tris.Add(start + b);  // the mirror flips the winding
                }
            }
            if (n.name.EndsWith("_head"))
            {
                var bounds = new Bounds(verts[headStart], Vector3.zero);
                for (int i = headStart; i < verts.Count; i++) bounds.Encapsulate(verts[i]);
                headCentre = bounds.center;
            }
        }
        var mesh = new Mesh { name = prefix + "club" };
        if (verts.Count > 65000) mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
        mesh.SetVertices(verts);
        mesh.SetNormals(norms);
        mesh.SetTriangles(tris, 0);
        mesh.RecalculateBounds();
        return mesh;
    }

    // A humanoid Avatar for the rig, with its rest pose turned into the T
    // pose Unity's retargeting expects (arms out sideways, legs straight
    // down, facing +z), so its clips can drive any humanoid person.
    public Avatar BuildAvatar()
    {
        ResetPose();
        var left = (bones["thigh_l"].position - bones["thigh_r"].position).normalized;
        left.y = 0;
        left.Normalize();
        // Unity is left-handed: forward = right x up.
        var forward = Vector3.Cross(-left, Vector3.up);
        var top = bones["Root"];
        top.rotation = Quaternion.FromToRotation(forward, Vector3.forward) * top.rotation;
        var side = (bones["thigh_l"].position - bones["thigh_r"].position).normalized;
        foreach (var s in new[] { ("_l", 1f), ("_r", -1f) })
        {
            var d = side * s.Item2;
            Aim("upperarm" + s.Item1, "lowerarm" + s.Item1, d);
            Aim("lowerarm" + s.Item1, "hand" + s.Item1, d);
            Aim("hand" + s.Item1, "middle_01" + s.Item1, d);
            Aim("thigh" + s.Item1, "calf" + s.Item1, Vector3.down);
            Aim("calf" + s.Item1, "foot" + s.Item1, Vector3.down);
        }
        var map = new List<HumanBone>();
        void H(string human, string bone) { if (bones.ContainsKey(bone)) map.Add(new HumanBone { humanName = human, boneName = bone, limit = new HumanLimit { useDefaultValues = true } }); }
        H("Hips", "pelvis"); H("Spine", "spine_01"); H("Chest", "spine_02"); H("UpperChest", "spine_03");
        H("Neck", "neck_01"); H("Head", "head");
        foreach (var s in new[] { ("Left", "_l"), ("Right", "_r") })
        {
            string L = s.Item1, x = s.Item2;
            H(L + "UpperLeg", "thigh" + x); H(L + "LowerLeg", "calf" + x); H(L + "Foot", "foot" + x); H(L + "Toes", "ball" + x);
            H(L + "Shoulder", "clavicle" + x); H(L + "UpperArm", "upperarm" + x); H(L + "LowerArm", "lowerarm" + x); H(L + "Hand", "hand" + x);
            foreach (var f in new[] { ("Thumb", "thumb"), ("Index", "index"), ("Middle", "middle"), ("Ring", "ring"), ("Little", "pinky") })
            {
                H(L + " " + f.Item1 + " Proximal", f.Item2 + "_01" + x);
                H(L + " " + f.Item1 + " Intermediate", f.Item2 + "_02" + x);
                H(L + " " + f.Item1 + " Distal", f.Item2 + "_03" + x);
            }
        }
        var skel = new List<SkeletonBone>();
        foreach (var t in root.GetComponentsInChildren<Transform>())
            skel.Add(new SkeletonBone { name = t.name, position = t.localPosition, rotation = t.localRotation, scale = t.localScale });
        var desc = new HumanDescription
        {
            human = map.ToArray(), skeleton = skel.ToArray(),
            upperArmTwist = 0.5f, lowerArmTwist = 0.5f, upperLegTwist = 0.5f, lowerLegTwist = 0.5f,
            armStretch = 0.05f, legStretch = 0.05f, feetSpacing = 0, hasTranslationDoF = false,
        };
        var avatar = AvatarBuilder.BuildHumanAvatar(root.gameObject, desc);
        avatar.name = "GolferRigAvatar";
        ResetPose();
        if (!avatar.isValid || !avatar.isHuman) Debug.LogError("Golfer rig avatar is not a valid humanoid");
        return avatar;
    }

    void Aim(string bone, string child, Vector3 dir)
    {
        if (!bones.ContainsKey(bone) || !bones.ContainsKey(child)) return;
        var b = bones[bone];
        var cur = (bones[child].position - b.position).normalized;
        b.rotation = Quaternion.FromToRotation(cur, dir) * b.rotation;
    }
}
