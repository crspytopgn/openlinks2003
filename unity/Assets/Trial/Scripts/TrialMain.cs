using System;
using System.IO;
using UnityEngine;

// The Unity 6 trial: one Kettle Hollow tee shot, over and over. The golfer
// swings the game's own mocap (GlbRig) retargeted onto a Rocketbox person,
// the ball flies with olcore (OlCore), and a broadcast camera follows it.
// Run with "-trialShots DIR" to save screenshots and quit (CI does this).
public class TrialMain : MonoBehaviour
{
    public TextAsset course, rig, raster;
    public Vector2 rasterOrigin;
    public int rasterCols, rasterRows;
    public float rasterCell;
    public Vector2 tee, aim, pin;  // course x, z
    public Transform ball;
    public LineRenderer tracer;
    public Camera cam;
    public Animator person;
    public Material clubMaterial;
    public ReflectionProbe probe;

    const float BallRadius = 0.021335f, TeeHeight = 0.03f, AddressTime = 2.5f;

    OlcCourse c;
    GlbRig src;
    HumanPoseHandler srcPose, dstPose;
    HumanPose pose;
    Transform club;
    Vector3 headCentre, ballStart, targetDir, rightDir;
    GlbRig.Clip address, swing;
    float impact, t, landedAt = -1;
    bool flying;
    OlCore.Shot shot;
    double heading;
    bool linksModel;
    string shotsDir;
    int shotStep;
    float fps = 60;

    void Start()
    {
        var args = Environment.GetCommandLineArgs();
        for (int i = 0; i + 1 < args.Length; i++)
        {
            if (args[i] == "-trialShots") shotsDir = args[i + 1];
            if (args[i] == "-linksExe" && File.Exists(args[i + 1]))
            {
                var exe = File.ReadAllBytes(args[i + 1]);
                linksModel = OlCore.ol_load_links_exe(exe, exe.Length) == 1;
            }
        }
        DynamicGI.UpdateEnvironment();
        if (probe != null) probe.RenderProbe();

        c = OlcCourse.Load(course.bytes);
        OlCore.ol_set_heights(c.heights, c.cols, c.rows, c.x0, c.z0, c.cell);
        OlCore.ol_set_surfaces(raster.bytes, rasterCols, rasterRows, rasterOrigin.x, rasterOrigin.y, rasterCell);

        float gy = (float)OlCore.ol_height(tee.x, tee.y);
        ballStart = OlCore.ToUnity(tee.x, gy + TeeHeight, tee.y);
        var aimU = OlCore.ToUnity(aim.x, 0, aim.y);
        targetDir = aimU - ballStart;
        targetDir.y = 0;
        targetDir.Normalize();
        rightDir = Vector3.Cross(Vector3.up, targetDir);
        heading = Math.Atan2(aim.x - tee.x, aim.y - tee.y);

        src = GlbRig.Load(rig.bytes, transform);
        address = src.clips["address"];
        swing = src.clips["swing"];
        var avatar = src.BuildAvatar();
        srcPose = new HumanPoseHandler(avatar, src.root);
        dstPose = new HumanPoseHandler(person.avatar, person.transform);

        club = new GameObject("Driver").transform;
        club.gameObject.AddComponent<MeshFilter>().sharedMesh = src.JointMesh("Driver_", "club", out headCentre);
        club.gameObject.AddComponent<MeshRenderer>().sharedMaterial = clubMaterial;

        Place();
        impact = FindImpact();
        ResetShot();
    }

    // Turns the rig so its stance runs along the target line and moves it
    // so the club head sits at the ball at address.
    void Place()
    {
        src.root.position = Vector3.zero;
        src.root.rotation = Quaternion.identity;
        src.Sample(address, 0);
        var stance = src.bones["foot_l"].position - src.bones["foot_r"].position;
        stance.y = 0;
        src.root.rotation = Quaternion.FromToRotation(stance.normalized, targetDir);
        src.Sample(address, 0);
        var head = src.bones["club"].TransformPoint(headCentre);
        var ground = ballStart.y - TeeHeight;
        src.root.position = new Vector3(ballStart.x - head.x, ground, ballStart.z - head.z);
        person.transform.SetPositionAndRotation(src.root.position, src.root.rotation);
    }

    float FindImpact()
    {
        float best = 0, at = swing.length * 0.5f;
        Vector3 last = Vector3.zero;
        for (int i = 0; i <= 480; i++)
        {
            float time = swing.length * i / 480f;
            src.Sample(swing, time);
            var p = src.bones["club"].TransformPoint(headCentre);
            if (i > 0 && (p - last).magnitude > best) { best = (p - last).magnitude; at = time; }
            last = p;
        }
        return at;
    }

    void ResetShot()
    {
        t = 0;
        flying = false;
        landedAt = -1;
        ball.position = ballStart + Vector3.up * BallRadius;
        tracer.positionCount = 0;
    }

    void Update()
    {
        fps = Mathf.Lerp(fps, 1f / Mathf.Max(Time.unscaledDeltaTime, 1e-4f), 0.05f);
        t += Time.deltaTime;
        float st = t - AddressTime;
        if (st < 0) src.Sample(address, Mathf.Repeat(t, Mathf.Max(address.length, 0.01f)));
        else src.Sample(swing, Mathf.Min(st, swing.length));

        if (!flying && st >= impact)
        {
            var pinH = OlCore.ol_height(pin.x, pin.y);
            shot = OlCore.Hit(0, 1.0, 0.0, tee.x, ballStart.y, tee.y, heading, 0, 0, pin.x, pinH, pin.y);
            flying = true;
        }
        if (flying)
        {
            float ft = st - impact;
            ball.position = PathAt(ft) + Vector3.up * BallRadius;
            int n = 0;
            while (n < shot.times.Length && shot.times[n] <= ft) n++;
            tracer.positionCount = n;
            for (int i = 0; i < n; i++) tracer.SetPosition(i, shot.path[i] + Vector3.up * BallRadius);
            if (landedAt < 0 && ft >= shot.time) landedAt = t;
            if (landedAt >= 0 && t - landedAt > 3f && shotsDir == null) ResetShot();
        }
        Shots(st);
    }

    Vector3 PathAt(float time)
    {
        var ts = shot.times;
        if (ts.Length == 0) return ballStart;
        if (time <= ts[0]) return shot.path[0];
        for (int i = 1; i < ts.Length; i++)
            if (ts[i] >= time) return Vector3.Lerp(shot.path[i - 1], shot.path[i], (time - ts[i - 1]) / Mathf.Max(ts[i] - ts[i - 1], 1e-5f));
        return shot.path[ts.Length - 1];
    }

    void LateUpdate()
    {
        srcPose.GetHumanPose(ref pose);
        dstPose.SetHumanPose(ref pose);
        // The club keeps the mocap's angle, moved with the person's hands.
        var srcHands = (src.bones["hand_l"].position + src.bones["hand_r"].position) * 0.5f;
        var dstHands = (person.GetBoneTransform(HumanBodyBones.LeftHand).position + person.GetBoneTransform(HumanBodyBones.RightHand).position) * 0.5f;
        var sc = src.bones["club"];
        club.SetPositionAndRotation(sc.position + (dstHands - srcHands), sc.rotation);
        Frame();
    }

    // Broadcast framing: low behind the ball with the golfer large in frame,
    // following the ball up, then a cut to a view of the landing.
    void Frame()
    {
        float st = t - AddressTime;
        if (shotsDir != null && st < -1.0f)
        {
            // Close-up of the golfer at address, for full-size checks.
            var g = person.GetBoneTransform(HumanBodyBones.Chest).position;
            var face = Vector3.Cross(targetDir, Vector3.up);
            cam.transform.position = g - face * 2.6f + Vector3.up * 0.1f + targetDir * 0.4f;
            cam.transform.LookAt(g + Vector3.down * 0.35f);
            cam.fieldOfView = 38;
            return;
        }
        if (!flying || st - impact < shot.time * 0.62f)
        {
            cam.transform.position = ballStart - targetDir * 4.6f - rightDir * 0.9f + Vector3.up * 1.45f;
            var look = ballStart + targetDir * 40f + Vector3.up * 2.5f;
            float fov = 36;
            if (flying)
            {
                var b = ball.position;
                float k = Mathf.Clamp01((st - impact) / 1.2f);
                look = Vector3.Lerp(look, b, k);
                fov = Mathf.Lerp(36, 16, Mathf.Clamp01((b - cam.transform.position).magnitude / 220f));
            }
            cam.transform.rotation = Quaternion.Slerp(cam.transform.rotation, Quaternion.LookRotation(look - cam.transform.position), flying ? 0.25f : 1f);
            cam.fieldOfView = fov;
        }
        else
        {
            var land = shot.path[shot.path.Length - 1];
            var p = land + targetDir * 30f + rightDir * 14f;
            p.y = (float)OlCore.ol_height(-p.x, p.z) + 4f;
            cam.transform.position = p;
            cam.transform.LookAt(ball.position);
            cam.fieldOfView = 30;
        }
    }

    void Shots(float st)
    {
        if (shotsDir == null) return;
        string[] names = { "unity-golfer.png", "unity-address.png", "unity-flight.png", "unity-landing.png" };
        float[] at = { -1.6f, -0.3f, impact + 1.4f, impact + (float)shot.time + 1.5f };
        if (shotStep < names.Length && st >= at[shotStep] && (shotStep < 3 || flying))
        {
            Directory.CreateDirectory(shotsDir);
            ScreenCapture.CaptureScreenshot(Path.Combine(shotsDir, names[shotStep]));
            Debug.Log("TRIAL SHOT " + names[shotStep]);
            shotStep++;
        }
        else if (shotStep == names.Length && st > at[3] + 1f)
        {
            Debug.Log(string.Format("TRIAL DONE carry {0:F1} m total {1:F1} m apex {2:F1} m model {3}", shot.carry, shot.total, shot.apex, linksModel ? "links" : "standard"));
            Application.Quit();
        }
    }

    void OnGUI()
    {
        const float yd = 1.0936133f;
        var s = "Unity 6 trial  ·  " + (c != null ? c.name : "") + " hole 1  ·  " + Mathf.RoundToInt(fps) + " fps\n" +
                "Ball flight: " + (linksModel ? "Links 2003 (your game's tables)" : "olcore standard model");
        if (flying) s += string.Format("\nCarry {0:F0} yd  ·  Total {1:F0} yd  ·  Apex {2:F0} ft", shot.carry * yd, shot.total * yd, shot.apex * 3.28084);
        GUI.Label(new Rect(16, 12, 900, 80), s);
    }
}
