using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using UnityEngine;

// Reads an OpenLinks course file (.olc, docs/course-designer.md): gzipped
// JSON with a height grid and painted surface shapes. Course coordinates
// (see OlCore).
public class OlcCourse
{
    [Serializable] public class Heights { public string encoding; public int count; public string data; }
    [Serializable] public class Shape { public string surface; public float[] points; }
    [Serializable] public class Hole { public int par; public float[] tees; public float[] pin; public float[] route; }
    [Serializable] public class Obj { public string id; public float x; public float z; public float yaw; public float scale = 1; }
    [Serializable] public class Path { public float[] points; public float width; public bool bridge; }
    [Serializable] class File
    {
        public string format; public int version; public string name;
        public float[] area; public float cell; public Heights heights;
        public Shape[] shapes; public Hole[] holes; public Obj[] objects; public Path[] paths;
    }

    // Surface codes, as olcore's Surface enum.
    public const byte Tee = 0, Fairway = 1, Fringe = 2, Green = 3, Rough = 4, DeepRough = 5, Sand = 6, Water = 7, OutOfBounds = 8;
    public static readonly string[] SurfaceNames = { "Tee", "Fairway", "Fringe", "Green", "Rough", "Deep rough", "Sand", "Water", "Out of bounds" };

    public string name;
    public float x0, z0, width, depth, cell;
    public int cols, rows;
    public float[] heights;  // metres, row by row (z then x)
    public Shape[] shapes;
    public Hole[] holes;
    public Obj[] objects;
    public Path[] paths;

    public static OlcCourse Load(byte[] gz)
    {
        string json;
        using (var g = new GZipStream(new MemoryStream(gz), CompressionMode.Decompress))
        using (var r = new StreamReader(g)) json = r.ReadToEnd();
        var f = JsonUtility.FromJson<File>(json);
        if (f.format != "openlinks-course") throw new InvalidDataException("not an OpenLinks course");
        var c = new OlcCourse
        {
            name = f.name, x0 = f.area[0], z0 = f.area[1], width = f.area[2], depth = f.area[3], cell = f.cell,
            shapes = f.shapes, holes = f.holes, objects = f.objects ?? new Obj[0], paths = f.paths ?? new Path[0],
        };
        c.cols = Mathf.RoundToInt(c.width / c.cell) + 1;
        c.rows = Mathf.RoundToInt(c.depth / c.cell) + 1;
        c.heights = DecodeHeights(f.heights, c.cols * c.rows);
        return c;
    }

    // "cm-delta-s16-deflate-base64": int16 centimetre deltas, zlib-wrapped.
    static float[] DecodeHeights(Heights h, int n)
    {
        var z = Convert.FromBase64String(h.data);
        var raw = new byte[n * 2];
        using (var d = new DeflateStream(new MemoryStream(z, 2, z.Length - 2), CompressionMode.Decompress))
        {
            int got = 0;
            while (got < raw.Length)
            {
                int k = d.Read(raw, got, raw.Length - got);
                if (k <= 0) throw new InvalidDataException("short height grid");
                got += k;
            }
        }
        var o = new float[n];
        int cm = 0;
        for (int i = 0; i < n; i++)
        {
            cm += (short)(raw[i * 2] | (raw[i * 2 + 1] << 8));
            o[i] = cm * 0.01f;
        }
        return o;
    }

    public float Height(float x, float z)
    {
        float fx = Mathf.Clamp((x - x0) / cell, 0, cols - 1.0001f), fz = Mathf.Clamp((z - z0) / cell, 0, rows - 1.0001f);
        int c = (int)fx, r = (int)fz;
        float tx = fx - c, tz = fz - r;
        int i = r * cols + c;
        float top = Mathf.Lerp(heights[i], heights[i + 1], tx), bot = Mathf.Lerp(heights[i + cols], heights[i + cols + 1], tx);
        return Mathf.Lerp(top, bot, tz);
    }

    public static int SurfaceCode(string name) => Array.IndexOf(SurfaceNames, name);

    // The smoothed outline of a shape, as CourseShape.outline() in the game
    // (closed Catmull-Rom, 6 points a segment).
    public static List<Vector2> Outline(float[] pts)
    {
        var o = new List<Vector2>();
        int n = pts.Length / 2;
        if (n < 3) return o;
        Vector2 P(int i) { i = ((i % n) + n) % n; return new Vector2(pts[i * 2], pts[i * 2 + 1]); }
        for (int i = 0; i < n; i++)
        {
            Vector2 p0 = P(i - 1), p1 = P(i), p2 = P(i + 1), p3 = P(i + 2);
            for (int k = 0; k < 6; k++)
            {
                float t = k / 6f, t2 = t * t, t3 = t2 * t;
                o.Add(0.5f * (2f * p1 + (p2 - p0) * t + (2f * p0 - 5f * p1 + 4f * p2 - p3) * t2 + (3f * p1 - p0 - 3f * p2 + p3) * t3));
            }
        }
        return o;
    }
}
