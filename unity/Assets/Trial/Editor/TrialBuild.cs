using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// Builds the whole trial from code, so the repository holds scripts only:
// the URP pipeline, the hole (terrain, surfaces, trees), the sky, the
// golfer and the scene, saved as text. Inputs come from prepare.sh
// (Assets/Trial/Fetched). Menu: OpenLinks > Build trial scene; CI calls
// TrialBuild.BuildFromCI through GameCI.
public static class TrialBuild
{
    const string Fetched = "Assets/Trial/Fetched";
    const string Gen = "Assets/Trial/Generated";
    const string ScenePath = Gen + "/Trial.unity";
    const float Region = 512f;      // metres square round hole 1
    const float RasterCell = 0.5f;  // as the game's surface raster
    const string Person = "Male_Adult_14";

    [MenuItem("OpenLinks/Build trial scene")]
    public static void Setup()
    {
        EditorSettings.serializationMode = SerializationMode.ForceText;
        if (AssetDatabase.IsValidFolder(Gen)) AssetDatabase.DeleteAsset(Gen);
        AssetDatabase.CreateFolder("Assets/Trial", "Generated");
        AssetDatabase.CreateFolder(Gen, "Trees");
        AssetDatabase.Refresh();

        Pipeline();
        ImportSettings();
        Players();

        var course = OlcCourse.Load(File.ReadAllBytes(Fetched + "/home.olc.bytes"));
        var hole = course.holes[0];
        var tee = new Vector2(hole.tees[0], hole.tees[1]);
        var pin = new Vector2(hole.pin[0], hole.pin[1]);
        var aim = hole.route != null && hole.route.Length >= 2 ? new Vector2(hole.route[0], hole.route[1]) : pin;
        var mid = (tee + pin) * 0.5f;
        var rx0 = Mathf.Round(mid.x - Region * 0.5f);
        var rz0 = Mathf.Round(mid.y - Region * 0.5f);
        int cells = Mathf.RoundToInt(Region / RasterCell);
        var raster = new SurfaceRaster(course, rx0, rz0, cells, cells, RasterCell);
        File.WriteAllBytes(Gen + "/raster.bytes", raster.PhysicsCodes());
        AssetDatabase.ImportAsset(Gen + "/raster.bytes");

        EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var sun = Sky(tee, aim);
        var terrain = TerrainFor(course, raster, rx0, rz0, tee, pin);
        Trees(course, rx0, rz0, tee, pin);
        Flag(course, pin);

        var camGo = new GameObject("Camera") { tag = "MainCamera" };
        var cam = camGo.AddComponent<Camera>();
        cam.nearClipPlane = 0.05f;
        cam.farClipPlane = 4000f;
        cam.allowHDR = true;
        var camData = camGo.AddComponent<UniversalAdditionalCameraData>();
        camData.renderPostProcessing = true;
        camData.antialiasing = AntialiasingMode.SubpixelMorphologicalAntiAliasing;
        camData.antialiasingQuality = AntialiasingQuality.High;
        Volume();

        var probeGo = new GameObject("Reflections");
        probeGo.transform.position = OlCore.ToUnity(tee.x, course.Height(tee.x, tee.y) + 3f, tee.y);
        var probe = probeGo.AddComponent<ReflectionProbe>();
        probe.mode = ReflectionProbeMode.Realtime;
        probe.refreshMode = ReflectionProbeRefreshMode.ViaScripting;
        probe.size = new Vector3(3000, 1000, 3000);
        probe.resolution = 128;

        var ball = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        ball.name = "Ball";
        UnityEngine.Object.DestroyImmediate(ball.GetComponent<Collider>());
        ball.transform.localScale = Vector3.one * 0.04267f;
        ball.GetComponent<MeshRenderer>().sharedMaterial = Lit("Ball", null, null, Color.white, 0.55f);

        var tracerGo = new GameObject("Tracer");
        var tracer = tracerGo.AddComponent<LineRenderer>();
        tracer.widthMultiplier = 0.3f;
        tracer.numCapVertices = 4;
        tracer.shadowCastingMode = ShadowCastingMode.Off;
        var tracerMat = new Material(Shader.Find("Universal Render Pipeline/Unlit")) { name = "Tracer" };
        tracerMat.SetColor("_BaseColor", new Color(2.2f, 0.55f, 0.3f));
        AssetDatabase.CreateAsset(tracerMat, Gen + "/Tracer.mat");
        tracer.sharedMaterial = tracerMat;
        tracer.positionCount = 0;

        var person = PersonInScene();

        var main = new GameObject("Trial").AddComponent<TrialMain>();
        main.course = AssetDatabase.LoadAssetAtPath<TextAsset>(Fetched + "/home.olc.bytes");
        main.rig = AssetDatabase.LoadAssetAtPath<TextAsset>(Fetched + "/free_golfer.glb.bytes");
        main.raster = AssetDatabase.LoadAssetAtPath<TextAsset>(Gen + "/raster.bytes");
        main.rasterOrigin = new Vector2(rx0, rz0);
        main.rasterCols = cells;
        main.rasterRows = cells;
        main.rasterCell = RasterCell;
        main.tee = tee;
        main.aim = aim;
        main.pin = pin;
        main.ball = ball.transform;
        main.tracer = tracer;
        main.cam = cam;
        main.person = person;
        main.clubMaterial = Lit("Club", null, null, new Color(0.78f, 0.79f, 0.8f), 0.85f, 1f);
        main.probe = probe;

        EditorSceneManager.SaveScene(EditorSceneManager.GetActiveScene(), ScenePath);
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
        AssetDatabase.SaveAssets();
        Debug.Log("TRIAL SETUP DONE " + terrain.name + " " + sun.name);
    }

    public static void BuildFromCI()
    {
        try
        {
            Setup();
            var target = EditorUserBuildSettings.activeBuildTarget;
            NativePlugins(target);
            var path = Arg("-customBuildPath") ?? ("Builds/" + target);
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { ScenePath }, locationPathName = path, target = target, options = BuildOptions.None,
            });
            Debug.Log("TRIAL BUILD " + report.summary.result + " " + report.summary.totalSize + " bytes");
            if (report.summary.result != BuildResult.Succeeded) EditorApplication.Exit(1);
        }
        catch (Exception e)
        {
            Debug.LogException(e);
            EditorApplication.Exit(1);
        }
    }

    static string Arg(string name)
    {
        var a = Environment.GetCommandLineArgs();
        for (int i = 0; i + 1 < a.Length; i++) if (a[i] == name) return a[i + 1];
        return null;
    }

    // --- Pipeline and player ------------------------------------------------

    static void Pipeline()
    {
        var data = ScriptableObject.CreateInstance<UniversalRendererData>();
        var post = AssetDatabase.LoadAssetAtPath<PostProcessData>("Packages/com.unity.render-pipelines.universal/Runtime/Data/PostProcessData.asset");
        if (post != null && data.postProcessData == null) data.postProcessData = post;
        AssetDatabase.CreateAsset(data, Gen + "/Renderer.asset");
        try
        {
            var t = typeof(UniversalRendererData).Assembly.GetType("UnityEngine.Rendering.Universal.ScreenSpaceAmbientOcclusion");
            if (t != null)
            {
                var f = (ScriptableRendererFeature)ScriptableObject.CreateInstance(t);
                f.name = "SSAO";
                AssetDatabase.AddObjectToAsset(f, data);
                data.rendererFeatures.Add(f);
                var so = new SerializedObject(data);
                var map = so.FindProperty("m_RendererFeatureMap");
                if (map != null && AssetDatabase.TryGetGUIDAndLocalFileIdentifier(f, out string _, out long id))
                {
                    map.arraySize++;
                    map.GetArrayElementAtIndex(map.arraySize - 1).longValue = id;
                    so.ApplyModifiedPropertiesWithoutUndo();
                }
                EditorUtility.SetDirty(data);
            }
        }
        catch (Exception e) { Debug.LogWarning("SSAO not added: " + e.Message); }

        var urp = UniversalRenderPipelineAsset.Create(data);
        urp.supportsHDR = true;
        urp.msaaSampleCount = 4;
        urp.shadowDistance = 350f;
        urp.shadowCascadeCount = 4;
        urp.supportsCameraDepthTexture = true;
        AssetDatabase.CreateAsset(urp, Gen + "/URP.asset");
        var s = new SerializedObject(urp);
        SetInt(s, "m_MainLightShadowmapResolution", 4096);
        SetBool(s, "m_SoftShadowsSupported", true);
        s.ApplyModifiedPropertiesWithoutUndo();
        GraphicsSettings.defaultRenderPipeline = urp;
        int level = QualitySettings.GetQualityLevel();
        for (int i = 0; i < QualitySettings.names.Length; i++)
        {
            QualitySettings.SetQualityLevel(i, false);
            QualitySettings.renderPipeline = null;
        }
        QualitySettings.SetQualityLevel(level, false);
    }

    static void SetInt(SerializedObject s, string name, int v) { var p = s.FindProperty(name); if (p != null) p.intValue = v; else Debug.LogWarning("no " + name); }
    static void SetBool(SerializedObject s, string name, bool v) { var p = s.FindProperty(name); if (p != null) p.boolValue = v; else Debug.LogWarning("no " + name); }

    static void Players()
    {
        PlayerSettings.colorSpace = ColorSpace.Linear;
        PlayerSettings.companyName = "OpenLinks2003";
        PlayerSettings.productName = "OpenLinks Unity trial";
        PlayerSettings.fullScreenMode = FullScreenMode.Windowed;
        PlayerSettings.defaultScreenWidth = 1920;
        PlayerSettings.defaultScreenHeight = 1080;
        PlayerSettings.resizableWindow = true;
        PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.StandaloneLinux64, false);
        PlayerSettings.SetGraphicsAPIs(BuildTarget.StandaloneLinux64, new[] { GraphicsDeviceType.OpenGLCore });
        PlayerSettings.WebGL.compressionFormat = WebGLCompressionFormat.Gzip;
        PlayerSettings.WebGL.decompressionFallback = true;
    }

    // Desktop: the prebuilt library for the target. Web: the flattened
    // sources, compiled in by Unity's Emscripten.
    static void NativePlugins(BuildTarget target)
    {
        foreach (var guid in AssetDatabase.FindAssets("", new[] { "Assets/Plugins" }))
        {
            var path = AssetDatabase.GUIDToAssetPath(guid);
            var imp = AssetImporter.GetAtPath(path) as PluginImporter;
            if (imp == null) continue;
            imp.SetCompatibleWithAnyPlatform(false);
            imp.SetCompatibleWithEditor(false);
            if (path.EndsWith(".cpp")) imp.SetCompatibleWithPlatform(BuildTarget.WebGL, true);
            else if (path.EndsWith(".so")) imp.SetCompatibleWithPlatform(BuildTarget.StandaloneLinux64, true);
            else if (path.EndsWith(".dll")) imp.SetCompatibleWithPlatform(BuildTarget.StandaloneWindows64, true);
            imp.SaveAndReimport();
        }
    }

    // --- Textures and materials ----------------------------------------------

    static void ImportSettings()
    {
        foreach (var guid in AssetDatabase.FindAssets("t:Texture2D", new[] { Fetched }))
        {
            var path = AssetDatabase.GUIDToAssetPath(guid);
            var imp = AssetImporter.GetAtPath(path) as TextureImporter;
            if (imp == null) continue;
            var file = Path.GetFileNameWithoutExtension(path);
            imp.maxTextureSize = 2048;
            if (file.EndsWith("_normal")) imp.textureType = TextureImporterType.NormalMap;
            if (file.EndsWith("_roughness") || file.EndsWith("_height") || file.EndsWith("_specular") || file.EndsWith("_opacity")) imp.sRGBTexture = false;
            if (file == "leaf_spray" || file == "twig") imp.alphaIsTransparency = true;
            if (path.EndsWith(".hdr"))
            {
                imp.isReadable = true;
                imp.mipmapEnabled = false;
                imp.textureCompression = TextureImporterCompression.Uncompressed;
                imp.wrapModeU = TextureWrapMode.Repeat;
                imp.wrapModeV = TextureWrapMode.Clamp;
            }
            imp.SaveAndReimport();
        }
    }

    static Texture2D Tex(string name) => AssetDatabase.LoadAssetAtPath<Texture2D>(Fetched + "/free/" + name);

    static Material Lit(string name, Texture2D albedo, Texture2D normal, Color tint, float smooth, float metal = 0f)
    {
        var m = new Material(Shader.Find("Universal Render Pipeline/Lit")) { name = name };
        if (albedo != null) m.SetTexture("_BaseMap", albedo);
        m.SetColor("_BaseColor", tint);
        if (normal != null)
        {
            m.SetTexture("_BumpMap", normal);
            m.EnableKeyword("_NORMALMAP");
        }
        m.SetFloat("_Smoothness", smooth);
        m.SetFloat("_Metallic", metal);
        m.enableInstancing = true;
        AssetDatabase.CreateAsset(m, Gen + "/" + name + ".mat");
        return m;
    }

    static void Cutout(Material m, float cutoff)
    {
        m.SetFloat("_AlphaClip", 1);
        m.SetFloat("_Cutoff", cutoff);
        m.EnableKeyword("_ALPHATEST_ON");
        m.SetFloat("_Cull", 0);
        m.SetOverrideTag("RenderType", "TransparentCutout");
        m.renderQueue = (int)RenderQueue.AlphaTest;
        EditorUtility.SetDirty(m);
    }

    // --- Sky, sun and post ----------------------------------------------------

    // The free HDR sky, turned so its sun sits behind the camera's right
    // shoulder (the golfer front-lit, as TV crews set up), and a sun light
    // matching it.
    static Light Sky(Vector2 tee, Vector2 aim)
    {
        var hdr = AssetDatabase.LoadAssetAtPath<Texture2D>(Fetched + "/free/sky_panorama.hdr");
        var sky = new Material(Shader.Find("Skybox/Panoramic")) { name = "Sky" };
        sky.SetTexture("_MainTex", hdr);
        sky.SetFloat("_Exposure", 1f);
        var sunDir = new Vector3(0.3f, 0.7f, -0.6f).normalized;
        if (hdr != null)
        {
            var px = hdr.GetPixels();
            int best = 0;
            float lum = -1;
            for (int i = 0; i < px.Length; i++)
            {
                float l = px[i].r * 0.2126f + px[i].g * 0.7152f + px[i].b * 0.0722f;
                if (l > lum) { lum = l; best = i; }
            }
            float u = (best % hdr.width + 0.5f) / hdr.width, v = (best / hdr.width + 0.5f) / hdr.height;
            float lon = (0.5f - u) * 2f * Mathf.PI, lat = (1f - v) * Mathf.PI;
            var texDir = new Vector3(Mathf.Sin(lat) * Mathf.Cos(lon), Mathf.Cos(lat), Mathf.Sin(lat) * Mathf.Sin(lon));
            var target = OlCore.ToUnity(aim.x, 0, aim.y) - OlCore.ToUnity(tee.x, 0, tee.y);
            target.y = 0;
            target.Normalize();
            var right = Vector3.Cross(Vector3.up, target);
            var want = (right * 0.8f - target * 0.6f).normalized;
            float bestRot = 0, bestDot = -2;
            for (int deg = 0; deg < 360; deg++)
            {
                float a = deg * Mathf.Deg2Rad, ca = Mathf.Cos(a), sa = Mathf.Sin(a);
                var w = new Vector3(ca * texDir.x + sa * texDir.z, texDir.y, -sa * texDir.x + ca * texDir.z);
                var flat = new Vector3(w.x, 0, w.z).normalized;
                float d = Vector3.Dot(flat, want);
                if (d > bestDot) { bestDot = d; bestRot = deg; sunDir = w; }
            }
            sky.SetFloat("_Rotation", bestRot);
            Debug.Log("TRIAL SUN elevation " + (90f - lat * Mathf.Rad2Deg) + " sky rotation " + bestRot);
        }
        AssetDatabase.CreateAsset(sky, Gen + "/Sky.mat");
        RenderSettings.skybox = sky;
        RenderSettings.ambientMode = AmbientMode.Trilight;
        RenderSettings.ambientSkyColor = new Color(0.62f, 0.72f, 0.88f);
        RenderSettings.ambientEquatorColor = new Color(0.55f, 0.6f, 0.58f);
        RenderSettings.ambientGroundColor = new Color(0.24f, 0.27f, 0.19f);
        RenderSettings.defaultReflectionMode = DefaultReflectionMode.Skybox;
        RenderSettings.fog = true;
        RenderSettings.fogMode = FogMode.Exponential;
        RenderSettings.fogDensity = 0.0006f;
        RenderSettings.fogColor = new Color(0.74f, 0.8f, 0.87f);

        var go = new GameObject("Sun");
        var light = go.AddComponent<Light>();
        light.type = LightType.Directional;
        light.intensity = 2.4f;
        light.color = new Color(1f, 0.95f, 0.88f);
        light.shadows = LightShadows.Soft;
        light.shadowStrength = 0.92f;
        go.transform.rotation = Quaternion.LookRotation(-sunDir);
        RenderSettings.sun = light;
        return light;
    }

    static void Volume()
    {
        var profile = ScriptableObject.CreateInstance<VolumeProfile>();
        AssetDatabase.CreateAsset(profile, Gen + "/Post.asset");
        var tone = profile.Add<Tonemapping>(true);
        tone.mode.Override(TonemappingMode.ACES);
        var bloom = profile.Add<Bloom>(true);
        bloom.threshold.Override(1.1f);
        bloom.intensity.Override(0.25f);
        var grade = profile.Add<ColorAdjustments>(true);
        grade.postExposure.Override(0.15f);
        grade.contrast.Override(6f);
        grade.saturation.Override(4f);
        var vig = profile.Add<Vignette>(true);
        vig.intensity.Override(0.16f);
        foreach (var c in profile.components) AssetDatabase.AddObjectToAsset(c, profile);
        EditorUtility.SetDirty(profile);
        var go = new GameObject("Post");
        var vol = go.AddComponent<Volume>();
        vol.isGlobal = true;
        vol.sharedProfile = profile;
    }

    // --- The hole ---------------------------------------------------------------

    enum L { Rough, FairwayLight, FairwayDark, Green, Fringe, Sand, DeepRough, Path, Dirt, Tee, Count }

    static Terrain TerrainFor(OlcCourse c, SurfaceRaster raster, float rx0, float rz0, Vector2 tee, Vector2 pin)
    {
        const int res = 513;
        float rx1 = rx0 + Region;
        var h = new float[res, res];
        float lo = float.MaxValue, hi = float.MinValue;
        for (int j = 0; j < res; j++)
            for (int i = 0; i < res; i++)
            {
                float x = rx1 - i * Region / (res - 1), z = rz0 + j * Region / (res - 1);
                float y = c.Height(x, z);
                h[j, i] = y;
                lo = Mathf.Min(lo, y);
                hi = Mathf.Max(hi, y);
            }
        float range = Mathf.Max(hi - lo, 1f) + 2f;
        for (int j = 0; j < res; j++)
            for (int i = 0; i < res; i++) h[j, i] = (h[j, i] - lo) / range;

        var td = new TerrainData { heightmapResolution = res };
        td.size = new Vector3(Region, range, Region);
        td.SetHeights(0, 0, h);
        td.alphamapResolution = raster.cols;
        td.baseMapResolution = 1024;
        var layers = new TerrainLayer[(int)L.Count];
        TerrainLayer Layer(string name, string tex, float tile, Color tint, float smooth)
        {
            var t = new TerrainLayer
            {
                name = name, diffuseTexture = Tex(tex + "_albedo.jpg"), normalMapTexture = Tex(tex + "_normal.jpg"),
                tileSize = new Vector2(tile, tile), diffuseRemapMax = tint, smoothness = smooth, normalScale = 1f,
            };
            AssetDatabase.CreateAsset(t, Gen + "/" + name + ".terrainlayer");
            return t;
        }
        layers[(int)L.Rough] = Layer("Rough", "rough", 3.5f, new Color(0.9f, 0.95f, 0.85f, 1), 0.05f);
        layers[(int)L.FairwayLight] = Layer("FairwayLight", "grass", 2.5f, new Color(1.08f, 1.12f, 0.95f, 1), 0.1f);
        layers[(int)L.FairwayDark] = Layer("FairwayDark", "grass", 2.5f, new Color(0.86f, 0.92f, 0.8f, 1), 0.1f);
        layers[(int)L.Green] = Layer("Green", "grass", 1.2f, new Color(1.0f, 1.12f, 0.9f, 1), 0.15f);
        layers[(int)L.Fringe] = Layer("Fringe", "grass", 1.8f, new Color(0.95f, 1.05f, 0.86f, 1), 0.12f);
        layers[(int)L.Sand] = Layer("Sand", "sand", 2.5f, new Color(1.05f, 1.02f, 0.95f, 1), 0.05f);
        layers[(int)L.DeepRough] = Layer("DeepRough", "rough", 4f, new Color(0.82f, 0.84f, 0.7f, 1), 0.03f);
        layers[(int)L.Path] = Layer("Path", "path", 3f, new Color(0.95f, 0.93f, 0.88f, 1), 0.1f);
        layers[(int)L.Dirt] = Layer("Dirt", "dirt", 3f, Color.white, 0.05f);
        layers[(int)L.Tee] = Layer("Tee", "grass", 1.5f, new Color(1.02f, 1.1f, 0.92f, 1), 0.1f);
        td.terrainLayers = layers;

        // Hard surface codes to layer weights, with mown stripes 3 m wide
        // across the fairways, then a light blur so edges aren't stair-stepped.
        int n = raster.cols, nl = (int)L.Count;
        var hard = new int[n, n];
        var dir = (pin - tee).normalized;
        for (int j = 0; j < n; j++)
            for (int i = 0; i < n; i++)
            {
                int col = n - 1 - i;  // Unity x runs against course x
                float x = rx0 + (col + 0.5f) * RasterCell, z = rz0 + (j + 0.5f) * RasterCell;
                L l;
                switch (raster.At(col, j))
                {
                    case OlcCourse.Fairway:
                        l = (Mathf.FloorToInt(Vector2.Dot(new Vector2(x, z), dir) / 3f) & 1) == 0 ? L.FairwayLight : L.FairwayDark;
                        break;
                    case OlcCourse.Tee: l = L.Tee; break;
                    case OlcCourse.Green: l = L.Green; break;
                    case OlcCourse.Fringe: l = L.Fringe; break;
                    case OlcCourse.Sand: l = L.Sand; break;
                    case OlcCourse.DeepRough: l = L.DeepRough; break;
                    case SurfaceRaster.CartPath: l = L.Path; break;
                    case OlcCourse.Water: case OlcCourse.OutOfBounds: l = L.Dirt; break;
                    default: l = L.Rough; break;
                }
                hard[j, i] = (int)l;
            }
        var a = new float[n, n, nl];
        for (int j = 0; j < n; j++)
            for (int i = 0; i < n; i++)
            {
                int count = 0;
                for (int dj = -1; dj <= 1; dj++)
                    for (int di = -1; di <= 1; di++)
                    {
                        int jj = Mathf.Clamp(j + dj, 0, n - 1), ii = Mathf.Clamp(i + di, 0, n - 1);
                        a[j, i, hard[jj, ii]] += 1f;
                        count++;
                    }
                for (int k = 0; k < nl; k++) a[j, i, k] /= count;
            }
        td.SetAlphamaps(0, 0, a);
        AssetDatabase.CreateAsset(td, Gen + "/Terrain.asset");

        var go = Terrain.CreateTerrainGameObject(td);
        go.name = "Hole";
        go.transform.position = new Vector3(-rx1, lo, rz0);
        var t2 = go.GetComponent<Terrain>();
        var mat = new Material(Shader.Find("Universal Render Pipeline/Terrain/Lit")) { name = "TerrainLit" };
        AssetDatabase.CreateAsset(mat, Gen + "/TerrainLit.mat");
        t2.materialTemplate = mat;
        t2.heightmapPixelError = 2f;
        t2.basemapDistance = 1500f;
        t2.drawInstanced = true;
        t2.shadowCastingMode = ShadowCastingMode.On;
        return t2;
    }

    static void Trees(OlcCourse c, float rx0, float rz0, Vector2 tee, Vector2 pin)
    {
        var bark = Lit("Bark", Tex("bark_albedo.jpg"), Tex("bark_normal.jpg"), Color.white, 0.1f);
        var leaves = Lit("Leaves", Tex("leaf_spray.png"), null, new Color(0.86f, 0.92f, 0.8f), 0.18f);
        Cutout(leaves, 0.42f);
        var needles = Lit("Needles", Tex("twig.png"), null, new Color(0.8f, 0.86f, 0.78f), 0.15f);
        Cutout(needles, 0.45f);
        var kinds = new Dictionary<string, (TreeBuilder.Species, int[], Material)>
        {
            { "tree_broadleaf", (TreeBuilder.Species.Broadleaf, new[] { 11, 23, 37 }, leaves) },
            { "tree_pine", (TreeBuilder.Species.Pine, new[] { 5, 19 }, needles) },
            { "bush", (TreeBuilder.Species.Bush, new[] { 3, 29 }, leaves) },
        };
        var meshes = new Dictionary<string, Mesh[]>();
        foreach (var k in kinds)
        {
            var arr = new Mesh[k.Value.Item2.Length];
            for (int i = 0; i < arr.Length; i++)
            {
                arr[i] = TreeBuilder.Build(k.Value.Item1, k.Value.Item2[i]);
                AssetDatabase.CreateAsset(arr[i], Gen + "/Trees/" + arr[i].name + ".asset");
            }
            meshes[k.Key] = arr;
        }
        var parent = new GameObject("Trees").transform;
        int made = 0;
        foreach (var o in c.objects)
        {
            if (!kinds.ContainsKey(o.id)) continue;
            if (o.x < rx0 || o.x > rx0 + Region || o.z < rz0 || o.z > rz0 + Region) continue;
            if (SegmentDistance(new Vector2(o.x, o.z), tee, pin) > 230f) continue;
            var set = meshes[o.id];
            var go = new GameObject(o.id);
            go.transform.SetParent(parent, false);
            go.transform.position = OlCore.ToUnity(o.x, c.Height(o.x, o.z) - 0.1f, o.z);
            go.transform.rotation = Quaternion.Euler(0, -o.yaw, 0);
            go.transform.localScale = Vector3.one * (o.scale > 0 ? o.scale : 1f);
            go.AddComponent<MeshFilter>().sharedMesh = set[Mathf.Abs((int)(o.x * 7 + o.z * 13)) % set.Length];
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterials = new[] { bark, kinds[o.id].Item3 };
            var lod = go.AddComponent<LODGroup>();
            lod.SetLODs(new[] { new LOD(0.006f, new Renderer[] { r }) });
            made++;
        }
        Debug.Log("TRIAL TREES " + made);
    }

    static float SegmentDistance(Vector2 p, Vector2 a, Vector2 b)
    {
        var ab = b - a;
        float t = Mathf.Clamp01(Vector2.Dot(p - a, ab) / ab.sqrMagnitude);
        return (a + ab * t - p).magnitude;
    }

    static void Flag(OlcCourse c, Vector2 pin)
    {
        var y = c.Height(pin.x, pin.y);
        var pole = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        pole.name = "Flagstick";
        UnityEngine.Object.DestroyImmediate(pole.GetComponent<Collider>());
        pole.transform.position = OlCore.ToUnity(pin.x, y + 1.07f, pin.y);
        pole.transform.localScale = new Vector3(0.0127f, 1.07f, 0.0127f);
        pole.GetComponent<MeshRenderer>().sharedMaterial = Lit("Pole", null, null, Color.white, 0.6f);
        var flag = GameObject.CreatePrimitive(PrimitiveType.Cube);
        flag.name = "Flag";
        UnityEngine.Object.DestroyImmediate(flag.GetComponent<Collider>());
        flag.transform.position = OlCore.ToUnity(pin.x, y + 1.95f, pin.y) + new Vector3(0.26f, 0, 0);
        flag.transform.localScale = new Vector3(0.5f, 0.33f, 0.004f);
        flag.GetComponent<MeshRenderer>().sharedMaterial = Lit("Flag", null, null, new Color(0.95f, 0.8f, 0.1f), 0.2f);
    }

    // --- The golfer -----------------------------------------------------------

    // A Rocketbox person (MIT, scanned) as a humanoid, with URP materials
    // made from its own textures.
    static Animator PersonInScene()
    {
        var fbx = Fetched + "/Rocketbox/" + Person + "/Export/" + Person + ".fbx";
        var mi = (ModelImporter)AssetImporter.GetAtPath(fbx);
        mi.animationType = ModelImporterAnimationType.Human;
        mi.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
        mi.importAnimation = false;
        mi.SaveAndReimport();
        var model = AssetDatabase.LoadAssetAtPath<GameObject>(fbx);
        var go = (GameObject)PrefabUtility.InstantiatePrefab(model);
        go.name = "Golfer";
        var tex = Fetched + "/Rocketbox/" + Person + "/Textures/";
        var made = new Dictionary<string, Material>();
        foreach (var r in go.GetComponentsInChildren<Renderer>())
        {
            var mats = r.sharedMaterials;
            for (int i = 0; i < mats.Length; i++)
            {
                var old = mats[i] != null ? mats[i].name : "body";
                if (made.TryGetValue(old, out var done)) { mats[i] = done; continue; }
                var parts = old.Split('_');
                string code = parts[0], kind = parts[parts.Length - 1];
                var colour = AssetDatabase.LoadAssetAtPath<Texture2D>(tex + code + "_" + kind + "_color.tga");
                var normal = AssetDatabase.LoadAssetAtPath<Texture2D>(tex + code + "_" + kind + "_normal.tga");
                var m = Lit("Person_" + old, colour, normal, Color.white, kind == "head" ? 0.42f : 0.3f);
                if (kind == "opacity") Cutout(m, 0.5f);
                made[old] = m;
                mats[i] = m;
            }
            r.sharedMaterials = mats;
            if (r is SkinnedMeshRenderer s) s.updateWhenOffscreen = true;
        }
        var anim = go.GetComponent<Animator>();
        anim.runtimeAnimatorController = null;
        anim.applyRootMotion = false;
        anim.cullingMode = AnimatorCullingMode.AlwaysAnimate;
        if (anim.avatar == null || !anim.avatar.isHuman) Debug.LogError("Rocketbox person has no humanoid avatar");
        return anim;
    }
}
