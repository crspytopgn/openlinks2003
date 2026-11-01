"""Geometry helpers for the home course builder: the game's Catmull-Rom
outlines, point-in-polygon and distance fields on the 2 m height grid."""

import math

import numpy as np

SUBDIVISIONS = 6  # CourseShape.SUBDIVISIONS


def outline(points):
    """The closed Catmull-Rom curve the game draws through control points
    (CourseShape._rebuild), as an (n, 2) array."""
    p = np.asarray(points, dtype=np.float64)
    n = len(p)
    out = []
    for i in range(n):
        p0, p1, p2, p3 = p[(i - 1) % n], p[i], p[(i + 1) % n], p[(i + 2) % n]
        for k in range(SUBDIVISIONS):
            t = k / SUBDIVISIONS
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (3 * p1 - p0 - 3 * p2 + p3) * t3))
    return np.array(out)


def inside(poly, x, z):
    """Even-odd test of points (arrays x, z) against polygon `poly`."""
    res = np.zeros(x.shape, dtype=bool)
    n = len(poly)
    for i in range(n):
        ax, az = poly[i]
        bx, bz = poly[(i + 1) % n]
        cond = (az <= z) != (bz <= z)
        with np.errstate(divide="ignore", invalid="ignore"):
            xi = ax + (z - az) * (bx - ax) / (bz - az)
        res ^= cond & (x < xi)
    return res


def edge_distance(poly, x, z):
    """Distance from points to the polygon's outline."""
    best = np.full(x.shape, np.inf)
    n = len(poly)
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        ab = b - a
        l2 = max(ab @ ab, 1e-9)
        t = np.clip(((x - a[0]) * ab[0] + (z - a[1]) * ab[1]) / l2, 0.0, 1.0)
        dx = x - (a[0] + ab[0] * t)
        dz = z - (a[1] + ab[1] * t)
        best = np.minimum(best, dx * dx + dz * dz)
    return np.sqrt(best)


def signed_distance(poly, x, z):
    """Negative inside, positive outside (CourseShape.signed_distance)."""
    d = edge_distance(poly, x, z)
    return np.where(inside(poly, x, z), -d, d)


def polyline_distance(line, x, z):
    """Distance to an open polyline and how far along it the nearest point is."""
    line = np.asarray(line, dtype=np.float64)
    best = np.full(x.shape, np.inf)
    along = np.zeros(x.shape)
    run = 0.0
    for i in range(len(line) - 1):
        a, b = line[i], line[i + 1]
        ab = b - a
        seg = math.hypot(*ab)
        t = np.clip(((x - a[0]) * ab[0] + (z - a[1]) * ab[1]) / max(seg * seg, 1e-9), 0.0, 1.0)
        dx = x - (a[0] + ab[0] * t)
        dz = z - (a[1] + ab[1] * t)
        d = np.sqrt(dx * dx + dz * dz)
        better = d < best
        best = np.where(better, d, best)
        along = np.where(better, run + seg * t, along)
        run += seg
    return best, along


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def box_blur(a, r):
    """Mean over a (2r+1)^2 window, edges clamped."""
    if r <= 0:
        return a.copy()
    k = 2 * r + 1
    p = np.pad(a, r, mode="edge")
    c = np.cumsum(np.cumsum(p, 0), 1)
    c = np.pad(c, ((1, 0), (1, 0)))
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def gaussian(a, sigma_cells):
    """Three box blurs, close to a Gaussian of the given sigma (in cells)."""
    r = max(1, int(round(math.sqrt(12.0 * sigma_cells * sigma_cells / 3.0 + 1.0) / 2.0)))
    out = a
    for _ in range(3):
        out = box_blur(out, r)
    return out


def value_noise(x, z, scale, seed):
    """Smooth value noise in [-0.5, 0.5] at wavelength `scale` metres."""
    u = x / scale + seed * 17.13
    v = z / scale + seed * 31.71
    iu = np.floor(u)
    iv = np.floor(v)
    fu = u - iu
    fv = v - iv
    fu = fu * fu * (3 - 2 * fu)
    fv = fv * fv * (3 - 2 * fv)

    def h(a, b):
        n = np.sin(a * 127.1 + b * 311.7 + seed * 74.7) * 43758.5453
        return n - np.floor(n)

    a = h(iu, iv)
    b = h(iu + 1, iv)
    c = h(iu, iv + 1)
    d = h(iu + 1, iv + 1)
    return (a + (b - a) * fu) * (1 - fv) + (c + (d - c) * fu) * fv - 0.5


def blob(centre, length, width, angle, seed, count=14, wobble=0.12, lobes=None):
    """An organic closed shape: an ellipse (half sizes length/2 along
    `angle`, width/2 across) whose radius wanders with a few low harmonics,
    so no two greens, tees or bunkers share a template outline."""
    rng = np.random.default_rng(seed)
    harmonics = lobes if lobes is not None else [(k, rng.uniform(-wobble, wobble), rng.uniform(0, math.tau))
                                                 for k in (2, 3, 4)]
    pts = []
    ca, sa = math.cos(angle), math.sin(angle)
    for i in range(count):
        t = math.tau * i / count
        r = 1.0
        for k, amp, ph in harmonics:
            r += amp * math.cos(k * t + ph)
        lx = math.cos(t) * length * 0.5 * r
        lz = math.sin(t) * width * 0.5 * r
        pts.append((centre[0] + lx * ca - lz * sa, centre[1] + lx * sa + lz * ca))
    return pts


def rounded_rect(centre, length, width, angle, seed, count=12, power=4.0):
    """A tee pad: a superellipse (rounded rectangle) with slightly uneven
    sides, as mown tee boxes are."""
    rng = np.random.default_rng(seed)
    pts = []
    ca, sa = math.cos(angle), math.sin(angle)
    for i in range(count):
        t = math.tau * i / count + math.pi / count
        c, s = math.cos(t), math.sin(t)
        lx = math.copysign(abs(c) ** (2.0 / power), c) * length * 0.5 * (1 + rng.uniform(-0.03, 0.03))
        lz = math.copysign(abs(s) ** (2.0 / power), s) * width * 0.5 * (1 + rng.uniform(-0.04, 0.04))
        pts.append((centre[0] + lx * ca - lz * sa, centre[1] + lx * sa + lz * ca))
    return pts


def ribbon(line, widths, seed, spacing=14.0, wander=0.1, cap=0.9):
    """A fairway-like strip along `line` (polyline) with a width per input
    point (interpolated), edges that wander independently, and rounded ends.
    Returns control points (left side out, round the far end, right side
    back, round the near end)."""
    line = np.asarray(line, dtype=np.float64)
    seg = np.hypot(*(line[1:] - line[:-1]).T)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    total = cum[-1]
    n = max(3, int(total / spacing) + 1)
    s = np.linspace(0.0, total, n)
    pts = np.stack([np.interp(s, cum, line[:, 0]), np.interp(s, cum, line[:, 1])], 1)
    w = np.interp(s, cum, widths)
    d = np.gradient(pts, axis=0)
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    side = np.stack([-d[:, 1], d[:, 0]], 1)
    rng = np.random.default_rng(seed)
    ph = rng.uniform(0, math.tau, 4)

    def wav(k):
        return (np.sin(s / 61.0 + ph[k]) * 0.6 + np.sin(s / 23.0 + ph[k + 2]) * 0.4) * wander

    left = pts + side * (w * 0.5 * (1 + wav(0)))[:, None]
    right = pts - side * (w * 0.5 * (1 + wav(1)))[:, None]
    out = [tuple(p) for p in left]
    # Far end: a rounded nose.
    end, dend = pts[-1], d[-1]
    for a in (0.6, 1.2):
        r = w[-1] * 0.5
        c = (math.cos(a), math.sin(a))
        out.append(tuple(end + dend * r * cap * math.sin(a) + side[-1] * r * math.cos(a)))
    out.append(tuple(end + dend * w[-1] * 0.5 * cap))
    for a in (1.2, 0.6):
        r = w[-1] * 0.5
        out.append(tuple(end + dend * r * cap * math.sin(a) - side[-1] * r * math.cos(a)))
    out.extend(tuple(p) for p in right[::-1])
    start, dst = pts[0], d[0]
    for a in (0.6, 1.2):
        r = w[0] * 0.5
        out.append(tuple(start - dst * r * cap * math.sin(a) - side[0] * r * math.cos(a)))
    out.append(tuple(start - dst * w[0] * 0.5 * cap))
    for a in (1.2, 0.6):
        r = w[0] * 0.5
        out.append(tuple(start - dst * r * cap * math.sin(a) + side[0] * r * math.cos(a)))
    return out
