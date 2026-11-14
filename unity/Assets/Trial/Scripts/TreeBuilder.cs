using System.Collections.Generic;
using UnityEngine;

// Seeded trees in the manner of the game's TreeFactory: tapered limbs with
// the bark photo, and leaf cards (the leaf spray atlas, or the fir twig
// photo for pines) whose normals point out from the middle of the crown, so
// a crown shades as one soft mass. Submesh 0 is bark, 1 is leaves.
public static class TreeBuilder
{
    public enum Species { Broadleaf, Pine, Bush }

    class B
    {
        public List<Vector3> v = new List<Vector3>(), n = new List<Vector3>();
        public List<Vector2> uv = new List<Vector2>();
        public List<int> bark = new List<int>(), leaf = new List<int>();
    }

    public static Mesh Build(Species sp, int seed)
    {
        var rng = new System.Random(seed);
        float R() => (float)rng.NextDouble();
        var b = new B();
        switch (sp)
        {
            case Species.Broadleaf:
            {
                float h = 13f + 4f * R();
                Limb(b, Vector3.zero, Vector3.up, h * 0.55f, 0.32f, 0.2f);
                var crown = new Vector3(0, h * 0.64f, 0);
                var size = new Vector3(h * 0.33f, h * 0.27f, h * 0.33f);
                int limbs = 6 + rng.Next(3);
                for (int i = 0; i < limbs; i++)
                {
                    float a = (i + 0.4f * R()) / limbs * Mathf.PI * 2f;
                    var d = new Vector3(Mathf.Cos(a), 0.9f + 0.5f * R(), Mathf.Sin(a)).normalized;
                    var from = new Vector3(0, h * (0.4f + 0.12f * R()), 0);
                    Limb(b, from, d, h * 0.38f, 0.14f, 0.05f);
                }
                for (int i = 0; i < 230; i++)
                {
                    var dir = Random3(rng);
                    float shell = 0.72f + 0.28f * Mathf.Sqrt(R());
                    var p = crown + Vector3.Scale(dir, size) * shell;
                    Card(b, p, (p - crown).normalized, 2.0f, crown, rng.Next(4), 2, R() * 360f);
                }
                break;
            }
            case Species.Pine:
            {
                float h = 17f + 6f * R();
                Limb(b, Vector3.zero, Vector3.up, h, 0.3f, 0.03f);
                float bottom = h * 0.28f;
                int whorls = 14;
                for (int w = 0; w < whorls; w++)
                {
                    float t = w / (float)(whorls - 1);
                    float y = Mathf.Lerp(bottom, h * 0.97f, t);
                    float reach = Mathf.Lerp(h * 0.22f, 0.4f, t);
                    int arms = 5 + rng.Next(2);
                    for (int k = 0; k < arms; k++)
                    {
                        float a = (k + R()) / arms * Mathf.PI * 2f + w;
                        var d = new Vector3(Mathf.Cos(a), -0.15f + 0.2f * R(), Mathf.Sin(a)).normalized;
                        var from = new Vector3(0, y, 0);
                        if (t < 0.8f) Limb(b, from, d, reach, 0.06f, 0.02f);
                        int cards = Mathf.Max(2, Mathf.RoundToInt(reach / 0.9f));
                        for (int c = 0; c < cards; c++)
                        {
                            var p = from + d * reach * ((c + 0.6f) / cards) + Vector3.down * 0.15f * c;
                            var axis = new Vector3(0, y - h * 0.15f, 0);
                            Card(b, p, (p - axis).normalized, 1.6f, axis, 0, 1, R() * 360f);
                        }
                    }
                }
                break;
            }
            default:
            {
                var centre = new Vector3(0, 0.9f, 0);
                for (int i = 0; i < 26; i++)
                {
                    var dir = Random3(rng);
                    if (dir.y < -0.3f) dir.y = -dir.y * 0.3f;
                    var p = centre + Vector3.Scale(dir, new Vector3(1.4f, 0.9f, 1.4f));
                    Card(b, p, (p - centre).normalized, 1.4f, centre, rng.Next(4), 2, R() * 360f);
                }
                break;
            }
        }
        var m = new Mesh { name = sp + "_" + seed };
        m.SetVertices(b.v);
        m.SetNormals(b.n);
        m.SetUVs(0, b.uv);
        m.subMeshCount = 2;
        m.SetTriangles(b.bark, 0);
        m.SetTriangles(b.leaf, 1);
        m.RecalculateBounds();
        m.RecalculateTangents();
        return m;
    }

    static Vector3 Random3(System.Random rng)
    {
        while (true)
        {
            var p = new Vector3((float)rng.NextDouble() * 2 - 1, (float)rng.NextDouble() * 2 - 1, (float)rng.NextDouble() * 2 - 1);
            float l = p.magnitude;
            if (l > 0.2f && l <= 1f) return p / l;
        }
    }

    // A tapered 7-sided cylinder.
    static void Limb(B b, Vector3 from, Vector3 dir, float len, float r0, float r1)
    {
        const int sides = 7, rings = 4;
        var side = Vector3.Cross(dir, Mathf.Abs(dir.y) > 0.9f ? Vector3.right : Vector3.up).normalized;
        var up = Vector3.Cross(side, dir);
        int start = b.v.Count;
        for (int r = 0; r <= rings; r++)
        {
            float t = r / (float)rings;
            var c = from + dir * len * t;
            float rad = Mathf.Lerp(r0, r1, t);
            for (int s = 0; s <= sides; s++)
            {
                float a = s / (float)sides * Mathf.PI * 2f;
                var n = side * Mathf.Cos(a) + up * Mathf.Sin(a);
                b.v.Add(c + n * rad);
                b.n.Add(n);
                b.uv.Add(new Vector2(s / (float)sides * Mathf.Max(1f, r0 * 6f), t * len / 1.5f));
            }
        }
        for (int r = 0; r < rings; r++)
            for (int s = 0; s < sides; s++)
            {
                int i = start + r * (sides + 1) + s, j = i + sides + 1;
                b.bark.AddRange(new[] { i, j, i + 1, i + 1, j, j + 1 });
            }
    }

    // A square card facing roughly along `out`, its normal blended towards
    // the crown's radial direction; `cell` picks a quarter of a 2x2 atlas.
    static void Card(B b, Vector3 p, Vector3 outward, float size, Vector3 centre, int cell, int grid, float roll)
    {
        var face = Quaternion.LookRotation(-outward) * Quaternion.Euler(0, 0, roll);
        var right = face * Vector3.right * size * 0.5f;
        var up = face * Vector3.up * size * 0.5f;
        int start = b.v.Count;
        float u0 = (cell % grid) / (float)grid, v0 = (cell / grid) / (float)grid, du = 1f / grid;
        Vector3[] corners = { p - right - up, p + right - up, p + right + up, p - right + up };
        Vector2[] uvs = { new Vector2(u0, v0), new Vector2(u0 + du, v0), new Vector2(u0 + du, v0 + du), new Vector2(u0, v0 + du) };
        for (int i = 0; i < 4; i++)
        {
            b.v.Add(corners[i]);
            b.n.Add(Vector3.Lerp((corners[i] - centre).normalized, outward, 0.4f).normalized);
            b.uv.Add(uvs[i]);
        }
        b.leaf.AddRange(new[] { start, start + 2, start + 1, start, start + 3, start + 2 });
    }
}
