"""Signed distance shapes and meshing for the cart's moulded panels.

Each shape is a function of x, y, z arrays (any matching shapes) giving the
distance to its surface, negative inside. Smooth unions and cuts give the
rounded, moulded look of plastic body panels; marching cubes turns a shape
into triangles, which are then simplified, with normals taken from the
shape itself so the shading stays smooth.
"""

import math

import numpy as np


def rbox(c, h, r):
    """A box with rounded edges: centre, half sizes, edge radius."""
    def f(x, y, z):
        qx = np.abs(x - c[0]) - (h[0] - r)
        qy = np.abs(y - c[1]) - (h[1] - r)
        qz = np.abs(z - c[2]) - (h[2] - r)
        out = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2 + np.maximum(qz, 0) ** 2)
        return out + np.minimum(np.maximum(np.maximum(qx, qy), qz), 0) - r
    return f


def rotated_x(shape, c, deg):
    """The shape turned about an x axis through c (positive tips +y to +z)."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)

    def f(x, y, z):
        dy, dz = y - c[1], z - c[2]
        return shape(x, c[1] + ca * dy + sa * dz, c[2] - sa * dy + ca * dz)
    return f


def cyl_x(cy, cz, r, x0, x1, mirror=False):
    """A cylinder along x between x0 and x1 (both sides if mirrored)."""
    def f(x, y, z):
        xx = np.abs(x) if mirror else x
        d = np.sqrt((y - cy) ** 2 + (z - cz) ** 2) - r
        dx = np.maximum(x0 - xx, xx - x1)
        out = np.sqrt(np.maximum(d, 0) ** 2 + np.maximum(dx, 0) ** 2)
        return out + np.minimum(np.maximum(d, dx), 0)
    return f


def sphere(c, r):
    def f(x, y, z):
        return np.sqrt((x - c[0]) ** 2 + (y - c[1]) ** 2 + (z - c[2]) ** 2) - r
    return f


def plane(n, d):
    """Inside below the plane n . p = d."""
    n = np.asarray(n, dtype=np.float64)
    n = n / np.linalg.norm(n)

    def f(x, y, z):
        return n[0] * x + n[1] * y + n[2] * z - d
    return f


def plan_round(cz, a, b, power=3.0, zmax=None):
    """Rounds a shape in plan (seen from above): a superellipse in x and z
    centred at z = cz, applied only in front of cz."""
    def f(x, y, z):
        dz = np.maximum(cz - z, 0.0)
        return ((np.abs(x) / a) ** power + (dz / b) ** power) ** (1.0 / power) * min(a, b) - min(a, b)
    return f


def union(*shapes):
    def f(x, y, z):
        d = shapes[0](x, y, z)
        for s in shapes[1:]:
            d = np.minimum(d, s(x, y, z))
        return d
    return f


def _smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smooth_union(k, *shapes):
    def f(x, y, z):
        d = shapes[0](x, y, z)
        for s in shapes[1:]:
            d = _smin(d, s(x, y, z), k)
        return d
    return f


def smooth_intersect(k, a, b):
    def f(x, y, z):
        return -_smin(-a(x, y, z), -b(x, y, z), k)
    return f


def smooth_cut(k, a, b):
    """a with b taken away."""
    def f(x, y, z):
        return -_smin(-a(x, y, z), b(x, y, z), k)
    return f


def mesh(shape, lo, hi, step, faces):
    """Triangles for the shape's surface inside the box lo..hi, simplified to
    about `faces` triangles. Returns positions, normals and indices."""
    from skimage import measure
    import fast_simplification

    lo = np.asarray(lo, dtype=np.float64)
    n = np.ceil((np.asarray(hi) - lo) / step).astype(int) + 1
    xs, ys, zs = (lo[k] + step * np.arange(n[k]) for k in range(3))
    vol = np.empty(tuple(n), dtype=np.float32)
    Y, Z = np.meshgrid(ys, zs, indexing="ij")
    for i, x in enumerate(xs):
        vol[i] = shape(np.full_like(Y, x), Y, Z)
    # Keep the surface closed where it meets the edge of the box.
    vol[0, :, :] = vol[-1, :, :] = vol[:, 0, :] = vol[:, -1, :] = vol[:, :, 0] = vol[:, :, -1] = 1.0
    verts, tris, _, _ = measure.marching_cubes(vol, 0.0, spacing=(step, step, step))
    verts = verts + lo
    if faces and len(tris) > faces:
        verts, tris = fast_simplification.simplify(verts.astype(np.float32), tris.astype(np.int64),
                                                   target_reduction=1.0 - faces / len(tris), agg=3)
        verts = verts.astype(np.float64)
        # Put the vertices back on the surface, which simplifying moves them off.
        for _ in range(4):
            d = shape(verts[:, 0], verts[:, 1], verts[:, 2])
            verts = verts - gradient(shape, verts) * d[:, None]
    # Drop slivers with no area.
    f = np.cross(verts[tris[:, 1]] - verts[tris[:, 0]], verts[tris[:, 2]] - verts[tris[:, 0]])
    tris = tris[np.linalg.norm(f, axis=1) > 1e-10]
    nor = gradient(shape, verts)
    # Wind the triangles so they face outwards, as glTF expects.
    f = np.cross(verts[tris[:, 1]] - verts[tris[:, 0]], verts[tris[:, 2]] - verts[tris[:, 0]])
    if np.sum(f * nor[tris[:, 0]]) < 0:
        tris = tris[:, [0, 2, 1]]
    return verts, nor, tris


def gradient(shape, p, eps=1e-3):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    g = np.stack([shape(x + eps, y, z) - shape(x - eps, y, z),
                  shape(x, y + eps, z) - shape(x, y - eps, z),
                  shape(x, y, z + eps) - shape(x, y, z - eps)], axis=1)
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-12)


def ambient_occlusion(scene, p, n, step=0.035, samples=5, strength=3.2):
    """How open each point is to the sky and its surroundings, 0 to 1:
    steps out along the normal and sees how close other surfaces come."""
    occ = np.zeros(len(p))
    w = 1.0
    for k in range(1, samples + 1):
        d = step * k
        q = p + n * d
        occ += w * np.maximum(d - scene(q[:, 0], q[:, 1], q[:, 2]), 0.0) / d
        w *= 0.6
    # And from above: surfaces under the roof or the body see less sky.
    sky = np.zeros(len(p))
    for d in (0.15, 0.35, 0.6):
        q = p + np.array([0.0, d, 0.0]) + n * 0.02
        sky += (scene(q[:, 0], q[:, 1], q[:, 2]) < 0.02).astype(np.float64)
    ao = 1.0 - strength * occ / 2.5 - 0.12 * sky
    return np.clip(ao, 0.3, 1.0)


def poly2d(points):
    """Signed distance to a closed outline in a plane, for u, v arrays."""
    P = np.asarray(points, dtype=np.float64)

    def f(u, v):
        d = np.full(np.shape(u), np.inf)
        inside = np.zeros(np.shape(u), dtype=bool)
        for k in range(len(P)):
            a, b = P[k], P[(k + 1) % len(P)]
            e = b - a
            wu, wv = u - a[0], v - a[1]
            t = np.clip((wu * e[0] + wv * e[1]) / (e @ e), 0.0, 1.0)
            d = np.minimum(d, (wu - e[0] * t) ** 2 + (wv - e[1] * t) ** 2)
            cross = (a[1] > v) != (b[1] > v)
            with np.errstate(divide="ignore", invalid="ignore"):
                xi = a[0] + (v - a[1]) * e[0] / e[1]
            inside ^= cross & (u < xi)
        d = np.sqrt(d)
        return np.where(inside, -d, d)
    return f


def side_plan(side, plan, k, width_cut=None):
    """A panel shaped by two drawings: its outline seen from the side (z, y)
    and from above (x, z), with the edges between rounded by k."""
    fs, fp = poly2d(side), poly2d(plan)

    def a(x, y, z):
        return fs(z, y)

    def b(x, y, z):
        return fp(x, z)
    return smooth_intersect(k, a, b)


def front_section(section):
    """An outline seen from the front (x, y), extruded along z."""
    f = poly2d(section)

    def g(x, y, z):
        return f(x, y)
    return g


def warped(shape, dy):
    """The shape moved up by dy(x, z) (a crown on a roof, say)."""
    def f(x, y, z):
        return shape(x, y - dy(x, z), z)
    return f


def cyl_y(cx, cz, r, y0, y1):
    """An upright cylinder."""
    def f(x, y, z):
        d = np.sqrt((x - cx) ** 2 + (z - cz) ** 2) - r
        dy = np.maximum(y0 - y, y - y1)
        out = np.sqrt(np.maximum(d, 0) ** 2 + np.maximum(dy, 0) ** 2)
        return out + np.minimum(np.maximum(d, dy), 0)
    return f


def mirrored_x(shape):
    def f(x, y, z):
        return shape(np.abs(x), y, z)
    return f
