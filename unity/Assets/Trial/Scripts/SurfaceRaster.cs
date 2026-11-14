using System.Collections.Generic;
using UnityEngine;

// Paints a course's surface shapes into a grid, as DesignedTerrain._raster
// does in the game: rough first, then the layers in LAYERS order, cart paths
// as fairway, and a 1.8 m fringe round every green. Codes are olcore's
// Surface values, plus CartPath for the look (it plays as fairway).
public class SurfaceRaster
{
    public const byte CartPath = 9;
    const float FringeWidth = 1.8f;
    static readonly byte[] Layers = {
        OlcCourse.DeepRough, OlcCourse.OutOfBounds, OlcCourse.Rough, OlcCourse.Fairway, OlcCourse.Fringe,
        OlcCourse.Tee, OlcCourse.Green, OlcCourse.Sand, OlcCourse.Water,
    };

    public float x0, z0, cell;
    public int cols, rows;
    public byte[] codes;

    public SurfaceRaster(OlcCourse c, float x0, float z0, int cols, int rows, float cell)
    {
        this.x0 = x0; this.z0 = z0; this.cols = cols; this.rows = rows; this.cell = cell;
        codes = new byte[cols * rows];
        for (int i = 0; i < codes.Length; i++) codes[i] = OlcCourse.Rough;
        foreach (var layer in Layers)
        {
            if (layer == OlcCourse.Fringe)
            {
                Fringe(c);
                continue;
            }
            foreach (var s in c.shapes)
                if (OlcCourse.SurfaceCode(s.surface) == layer) Fill(OlcCourse.Outline(s.points), layer);
            if (layer == OlcCourse.Fairway)
                foreach (var p in c.paths)
                    if (!p.bridge) Stroke(p.points, p.width * 0.5f, CartPath);
        }
    }

    public byte At(int col, int row) => codes[row * cols + col];

    // The codes the physics sees: cart paths play as fairway.
    public byte[] PhysicsCodes()
    {
        var o = (byte[])codes.Clone();
        for (int i = 0; i < o.Length; i++) if (o[i] == CartPath) o[i] = OlcCourse.Fairway;
        return o;
    }

    void Fill(List<Vector2> poly, byte code)
    {
        if (poly.Count < 3) return;
        var xs = new List<float>();
        for (int r = 0; r < rows; r++)
        {
            float z = z0 + (r + 0.5f) * cell;
            xs.Clear();
            for (int i = 0; i < poly.Count; i++)
            {
                Vector2 a = poly[i], b = poly[(i + 1) % poly.Count];
                if ((a.y <= z) != (b.y <= z)) xs.Add(a.x + (z - a.y) / (b.y - a.y) * (b.x - a.x));
            }
            if (xs.Count < 2) continue;
            xs.Sort();
            for (int k = 0; k + 1 < xs.Count; k += 2)
            {
                int c0 = Mathf.Max(0, Mathf.CeilToInt((xs[k] - x0) / cell - 0.5f));
                int c1 = Mathf.Min(cols - 1, Mathf.FloorToInt((xs[k + 1] - x0) / cell - 0.5f));
                for (int col = c0; col <= c1; col++) codes[r * cols + col] = code;
            }
        }
    }

    void Stroke(float[] pts, float half, byte code)
    {
        for (int i = 0; i + 3 < pts.Length; i += 2)
        {
            Vector2 a = new Vector2(pts[i], pts[i + 1]), b = new Vector2(pts[i + 2], pts[i + 3]);
            int c0 = Mathf.Max(0, (int)((Mathf.Min(a.x, b.x) - half - x0) / cell)), c1 = Mathf.Min(cols - 1, (int)((Mathf.Max(a.x, b.x) + half - x0) / cell));
            int r0 = Mathf.Max(0, (int)((Mathf.Min(a.y, b.y) - half - z0) / cell)), r1 = Mathf.Min(rows - 1, (int)((Mathf.Max(a.y, b.y) + half - z0) / cell));
            for (int r = r0; r <= r1; r++)
                for (int col = c0; col <= c1; col++)
                {
                    var p = new Vector2(x0 + (col + 0.5f) * cell, z0 + (r + 0.5f) * cell);
                    var ab = b - a;
                    float t = Mathf.Clamp01(Vector2.Dot(p - a, ab) / Mathf.Max(ab.sqrMagnitude, 1e-6f));
                    if ((a + ab * t - p).sqrMagnitude <= half * half) codes[r * cols + col] = code;
                }
        }
    }

    // Every cell within FringeWidth of a green, drawn under the greens.
    void Fringe(OlcCourse c)
    {
        var green = new bool[codes.Length];
        var tmp = new SurfaceRaster(this);
        foreach (var s in c.shapes)
            if (OlcCourse.SurfaceCode(s.surface) == OlcCourse.Green) tmp.Fill(OlcCourse.Outline(s.points), OlcCourse.Green);
        for (int i = 0; i < codes.Length; i++) green[i] = tmp.codes[i] == OlcCourse.Green;
        int k = Mathf.CeilToInt(FringeWidth / cell);
        float r2 = (FringeWidth / cell) * (FringeWidth / cell);
        for (int r = 0; r < rows; r++)
            for (int col = 0; col < cols; col++)
            {
                if (!green[r * cols + col]) continue;
                for (int dr = -k; dr <= k; dr++)
                    for (int dc = -k; dc <= k; dc++)
                    {
                        int rr = r + dr, cc = col + dc;
                        if (rr < 0 || cc < 0 || rr >= rows || cc >= cols || dr * dr + dc * dc > r2) continue;
                        codes[rr * cols + cc] = OlcCourse.Fringe;
                    }
            }
    }

    SurfaceRaster(SurfaceRaster like)
    {
        x0 = like.x0; z0 = like.z0; cols = like.cols; rows = like.rows; cell = like.cell;
        codes = new byte[cols * rows];
    }
}
