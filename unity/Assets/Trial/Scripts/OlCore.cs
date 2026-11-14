using System.Runtime.InteropServices;

// libs/olcore through unity/Native/olcore_unity.cpp: the same C++ physics the
// Godot game is checked against, so shots stay Links 2003-exact with no C#
// copy to keep in step. Desktop loads the shared library; the Web build
// compiles the sources in (Assets/Plugins/WebGL/olcore, from prepare.sh).
// Course coordinates: +y up, +z downrange, +x to the golfer's left. Unity
// is left-handed, so a course point (x, y, z) is Unity (-x, y, z).
public static class OlCore
{
#if UNITY_WEBGL && !UNITY_EDITOR
    const string Lib = "__Internal";
#else
    const string Lib = "olcore_unity";
#endif

    public enum Outcome { Rest, Holed, Water, OutOfBounds, TimedOut }

    [DllImport(Lib)] public static extern int ol_version();
    [DllImport(Lib)] public static extern void ol_set_heights(float[] heights, int cols, int rows, double x0, double z0, double cell);
    [DllImport(Lib)] public static extern void ol_set_surfaces(byte[] codes, int cols, int rows, double x0, double z0, double cell);
    [DllImport(Lib)] public static extern double ol_height(double x, double z);
    [DllImport(Lib)] public static extern int ol_surface(double x, double z);
    [DllImport(Lib)] public static extern int ol_load_links_exe(byte[] bytes, int size);
    [DllImport(Lib)] public static extern int ol_shot(int club, double power, double accuracy, double aimDeg,
        double fx, double fy, double fz, double heading, double windX, double windZ,
        int hasCup, double cx, double cy, double cz, double[] path, int maxSamples, double[] info);

    public struct Shot
    {
        public UnityEngine.Vector3[] path;  // Unity space
        public float[] times;
        public double carry, total, apex, time;
        public Outcome outcome;
        public int bounces, restSurface;
    }

    public static UnityEngine.Vector3 ToUnity(double x, double y, double z) => new UnityEngine.Vector3((float)-x, (float)y, (float)z);

    // A full swing with a standard club (0 = driver) from a course point.
    public static Shot Hit(int club, double power, double accuracy, double cx, double cy, double cz, double heading,
        double windX, double windZ, double pinX, double pinY, double pinZ)
    {
        const int max = 2048;
        var path = new double[max * 4];
        var info = new double[13];
        int n = ol_shot(club, power, accuracy, 0, cx, cy, cz, heading, windX, windZ, 1, pinX, pinY, pinZ, path, max, info);
        var s = new Shot { path = new UnityEngine.Vector3[n], times = new float[n] };
        for (int i = 0; i < n; i++)
        {
            s.path[i] = ToUnity(path[i * 4], path[i * 4 + 1], path[i * 4 + 2]);
            s.times[i] = (float)path[i * 4 + 3];
        }
        s.carry = info[6]; s.total = info[7]; s.apex = info[8]; s.time = info[9];
        s.outcome = (Outcome)(int)info[10]; s.bounces = (int)info[11]; s.restSurface = (int)info[12];
        return s;
    }
}
