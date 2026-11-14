#!/usr/bin/env python3
"""Turns a Poly Haven photoscanned tree (glTF, CC0) into the compact
.oltree file that TreeFactory draws as a near tree and bakes its impostor
from.

    python3 tools/trees/scan_tree.py SPEC_NAME [--src DIR] [--out DIR]

The scans are far too heavy for a game (Poly Haven's fir_tree_01 is 7.8
million triangles for three trees), so each one is cut down:

- Every leaf or twig (a connected piece of the leaf material) becomes one
  quad: the affine map from its UVs to its 3D points is fitted by least
  squares and the quad spans the piece's UV box, so the texture's alpha
  draws the leaf exactly where the scan had it. A share of the pieces is
  kept (`cards`) and grown to hold the crown's cover.
- The bark is decimated (quadric) with fast_simplification.

Needs numpy, scipy and fast_simplification (pip). Only the result is
committed (game/assets/trees/*.oltree), with the textures fetched by
tools/fetch_free_assets.py. Format, little endian:

    "OLTREE1\\0", u32 raw size, zlib stream of:
    f32 crown centre xyz, f32 crown radii xyz,
    u32 bark vertex count, u32 bark index count,
      f16 xyz, i8 normal xyz + texture (0 trunk, 1 branch), f16 uv, u32 indices
    u32 card count,
      f16 centre xyz, f16 u axis xyz, f16 v axis xyz (half extents),
      u16 uv box x0 y0 x1 y1 (/65535), u8 random,
      u8 kind (0 scanned leaf, 1 needle sprig card, 2 needle core card),
    then the lite bark, laid out as the bark
"""

import argparse
import json
import os
import struct
import sys
import zlib

import numpy as np

# name: glTF asset, node, leaf materials {index: texture slot}, bark
# materials {index: texture slot}, and how many leaf cards to keep.
SPECS = {
    "fir_a": dict(asset="fir_tree_01", node=0, leaves={2: 0}, bark={0: 1, 1: 0, 3: 1}, cards=12000, needles=True),
    "fir_b": dict(asset="fir_tree_01", node=1, leaves={2: 0}, bark={0: 1, 4: 0, 3: 1}, cards=9000, needles=True),
    "fir_c": dict(asset="fir_tree_01", node=2, leaves={2: 0}, bark={0: 1, 5: 0, 3: 1}, cards=9000, needles=True),
    "jacaranda": dict(asset="jacaranda_tree", node=0, leaves={2: 0}, bark={1: 0, 0: 1}, cards=12000),
    "island_01": dict(asset="island_tree_01", node=0, leaves={1: 0}, bark={0: 0, 2: 1}, cards=6000),
    "island_02": dict(asset="island_tree_02", node=0, leaves={1: 0}, bark={0: 0, 2: 1}, cards=5000),
}
# Bark pieces (separate tubes) shorter than this (m) are dropped first.
MIN_PIECE = {"jacaranda": 3.0}
BARK_TRIANGLES = {"fir_a": 6000, "fir_b": 4500, "fir_c": 4500, "jacaranda": 7000, "island_01": 4000, "island_02": 3000}

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def load_gltf(path):
    g = json.load(open(path))
    d = os.path.dirname(path)
    bins = [np.memmap(os.path.join(d, b["uri"]), dtype=np.uint8, mode="r") for b in g["buffers"]]

    def acc(i):
        a = g["accessors"][i]
        v = g["bufferViews"][a["bufferView"]]
        dt, n = CT[a["componentType"]], NC[a["type"]]
        off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        isz = np.dtype(dt).itemsize * n
        stride = v.get("byteStride", 0)
        if stride and stride != isz:
            raw = np.lib.stride_tricks.as_strided(bins[v["buffer"]][off:], shape=(a["count"], isz), strides=(stride, 1))
            arr = np.ascontiguousarray(raw).view(dt).reshape(a["count"], n)
        else:
            arr = np.frombuffer(bins[v["buffer"]], dtype=dt, count=a["count"] * n, offset=off).reshape(a["count"], n)
        return np.array(arr)

    return g, acc


def components(tri, nverts):
    """Connected pieces of a triangle list: a label per triangle."""
    lab = np.arange(nverts)
    e = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]])
    while True:
        m = np.minimum(lab[e[:, 0]], lab[e[:, 1]])
        new = lab.copy()
        np.minimum.at(new, e[:, 0], m)
        np.minimum.at(new, e[:, 1], m)
        new = new[new]
        if np.array_equal(new, lab):
            break
        lab = new
    return np.unique(lab[tri[:, 0]], return_inverse=True)[1]


def leaf_cards(pos, uv, tri, slot, rng):
    """One quad per connected leaf piece: (centre, u half axis, v half axis,
    uv box, slot)."""
    comp = components(tri, len(pos))
    n = comp.max() + 1
    corners = tri.reshape(-1)
    c = np.repeat(comp, 3)
    a = np.concatenate([uv[corners], np.ones((len(corners), 1))], axis=1)  # (k, 3)
    p = pos[corners]
    m = np.zeros((n, 3, 3))
    b = np.zeros((n, 3, 3))
    np.add.at(m, c, a[:, :, None] * a[:, None, :])
    np.add.at(b, c, a[:, :, None] * p[:, None, :])
    m += np.eye(3) * 1e-9
    lo = np.full((n, 2), np.inf)
    hi = np.full((n, 2), -np.inf)
    np.minimum.at(lo, c, uv[corners])
    np.maximum.at(hi, c, uv[corners])
    ok = np.all(hi - lo > 1e-4, axis=1) & (np.linalg.cond(m) < 1e9)
    m, b, lo, hi = m[ok], b[ok], lo[ok], hi[ok]
    aff = np.linalg.solve(m, b)  # rows: d/du, d/dv, offset
    mid = (lo + hi) * 0.5
    half = (hi - lo) * 0.5
    centre = mid[:, :1] * aff[:, 0] + mid[:, 1:] * aff[:, 1] + aff[:, 2]
    ua = aff[:, 0] * half[:, :1]
    va = aff[:, 1] * half[:, 1:]
    return dict(centre=centre, u=ua, v=va, lo=lo, hi=hi, slot=np.full(len(centre), slot, np.uint8))


def needle_cards(pos, tri, rng, cell=0.36):
    """For a conifer whose scan models every needle (Poly Haven's fir has
    millions of 1.5 cm needles): one sprig card per `cell` of needles,
    laid in the plane the needles there fill (PCA), its long side along
    the spray. The card's UV covers it whole, and the needle shader draws
    photo sprigs on it (TreeFactory's own conifer cards). No solid core
    cards (kind 2): between the scan's open branches they showed as flat
    discs."""
    p = pos[tri].mean(axis=1)
    out = []
    for size, slot in ((cell, 1),):
        key = np.floor(p / size).astype(np.int64)
        _, inv, counts = np.unique(key, axis=0, return_inverse=True, return_counts=True)
        inv = inv.reshape(-1)
        n = counts.size
        mean = np.zeros((n, 3))
        np.add.at(mean, inv, p)
        mean /= counts[:, None]
        d = p - mean[inv]
        cov = np.zeros((n, 3, 3))
        np.add.at(cov, inv, d[:, :, None] * d[:, None, :])
        cov /= counts[:, None, None]
        w, vec = np.linalg.eigh(cov)  # ascending
        w = np.maximum(w, 0.0)
        major = vec[:, :, 2]
        minor = vec[:, :, 1]
        ok = counts >= 10
        half_major = np.clip(np.sqrt(w[:, 2]) * 2.2, size * 0.45, size * 0.9)
        half_minor = np.clip(np.sqrt(w[:, 1]) * 2.2, size * 0.3, size * 0.7)
        u = minor * half_minor[:, None]
        v = major * half_major[:, None]
        k = ok.sum()
        out.append(dict(centre=mean[ok], u=u[ok], v=v[ok], lo=np.zeros((k, 2)), hi=np.ones((k, 2)),
                        slot=np.full(k, slot, np.uint8)))
    return {key: np.concatenate([o[key] for o in out]) for key in out[0]}


def thin(cards, count, rng):
    n = len(cards["centre"])
    keep = min(1.0, count / n)
    pick = rng.random(n) < keep
    # Cover held up to a point: grown much more, leaves turn into blobs.
    grow = min(1.0 / np.sqrt(keep), 2.0)
    out = {k: v[pick] for k, v in cards.items()}
    # Grown about each card's own middle, so the crown keeps its cover.
    out["u"] = out["u"] * grow
    out["v"] = out["v"] * grow
    return out


def decimate(pos, nrm, uv, tex, tri, target, min_piece=0.4):
    import fast_simplification
    from scipy.spatial import cKDTree

    if len(tri) <= target:
        return pos, nrm, uv, tex, tri
    # The finest twigs (thousands of loose little tubes) can't be reduced
    # below a few triangles each and vanish in the leaves anyway: drop the
    # short pieces (40 cm unless MIN_PIECE says otherwise). The jacaranda's
    # 33,000 twig tubes alone are a million triangles that no decimation
    # can bring down.
    comp = components(tri, len(pos))
    lo = np.full((comp.max() + 1, 3), np.inf)
    hi = np.full((comp.max() + 1, 3), -np.inf)
    np.minimum.at(lo, comp, pos[tri[:, 0]])
    np.maximum.at(hi, comp, pos[tri[:, 0]])
    tri = tri[np.linalg.norm(hi - lo, axis=1)[comp] >= min_piece]
    if len(tri) <= target:
        used, tri = np.unique(tri, return_inverse=True)
        return pos[used], nrm[used], uv[used], tex[used], tri.reshape(-1, 3)
    # Welded first: the scans split vertices along UV seams, and decimating
    # those as open borders tore holes in the trunks.
    welded, inv = np.unique(np.round(pos, 4), axis=0, return_inverse=True)
    wt = inv.reshape(-1)[tri]
    wt = wt[(wt[:, 0] != wt[:, 1]) & (wt[:, 1] != wt[:, 2]) & (wt[:, 0] != wt[:, 2])]
    p2, t2 = fast_simplification.simplify(welded.astype(np.float64), wt.astype(np.int32), target_count=target, agg=5.0)
    # Attributes from the nearest original vertex.
    _, near = cKDTree(pos).query(p2)
    return p2.astype(np.float32), nrm[near], uv[near], tex[near], t2


def cylinder_uv(pos):
    ang = np.arctan2(pos[:, 2], pos[:, 0]) / (2 * np.pi) + 0.5
    return np.stack([ang * 2.0, pos[:, 1] / 1.5], axis=1).astype(np.float32)


def build(name, src, out_dir):
    spec = SPECS[name]
    g, acc = load_gltf(os.path.join(src, spec["asset"], spec["asset"] + ".gltf"))
    node = g["nodes"][spec["node"]]
    rng = np.random.default_rng(7)
    bark_parts, cards = [], []
    for prim in g["meshes"][node["mesh"]]["primitives"]:
        mat = prim["material"]
        at = prim["attributes"]
        pos = acc(at["POSITION"]).astype(np.float32)
        tri = acc(prim["indices"]).reshape(-1, 3).astype(np.int64)
        if mat in spec["leaves"] and spec.get("needles"):
            cards.append(needle_cards(pos.astype(np.float64), tri, rng))
        elif mat in spec["leaves"]:
            uv = acc(at["TEXCOORD_0"]).astype(np.float64)
            cards.append(leaf_cards(pos.astype(np.float64), uv, tri, spec["leaves"][mat], rng))
        elif mat in spec["bark"]:
            nrm = acc(at["NORMAL"]).astype(np.float32)
            uv = acc(at["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in at else cylinder_uv(pos)
            tex = np.full(len(pos), spec["bark"][mat], np.int8)
            bark_parts.append((pos, nrm, uv, tex, tri))
    cards = {k: np.concatenate([c[k] for c in cards]) for k in cards[0]}
    cards = thin(cards, spec["cards"], rng)
    # Bark: merged, then decimated.
    off = 0
    pos, nrm, uv, tex, tri = [], [], [], [], []
    for p, n_, u, t, f in bark_parts:
        pos.append(p); nrm.append(n_); uv.append(u); tex.append(t); tri.append(f + off)
        off += len(p)
    pos, nrm, uv, tex, tri = (np.concatenate(x) for x in (pos, nrm, uv, tex, tri))
    full_bark = (pos, nrm, uv, tex, tri)
    pos, nrm, uv, tex, tri = decimate(pos, nrm, uv, tex, tri, BARK_TRIANGLES[name], MIN_PIECE.get(name, 0.4))
    # The lite bark (the tree between TreeFactory's lite and impostor
    # distances, unshadowed): a tenth of the triangles, only the limbs.
    tall = float(np.ptp(full_bark[0][:, 1]))
    lite = decimate(*full_bark, BARK_TRIANGLES[name] // 10, min(MIN_PIECE.get(name, 0.4) * 6.0, 6.0, tall * 0.3))
    # The tree stands at the origin: its trunk foot (lowest bark) centred.
    foot = pos[pos[:, 1] < pos[:, 1].min() + 0.3]
    shift = np.array([foot[:, 0].mean(), pos[:, 1].min(), foot[:, 2].mean()], np.float32)
    pos = pos - shift
    cards["centre"] = cards["centre"] - shift
    cc = cards["centre"]
    crown_c = (np.percentile(cc, 2, axis=0) + np.percentile(cc, 98, axis=0)) * 0.5
    crown_r = (np.percentile(cc, 98, axis=0) - np.percentile(cc, 2, axis=0)) * 0.5
    raw = bytearray()
    raw += struct.pack("<6f", *crown_c, *crown_r)
    raw += struct.pack("<II", len(pos), tri.size)
    vert = np.zeros(len(pos), dtype=[("p", "<f2", 3), ("n", "i1", 3), ("t", "i1"), ("uv", "<f2", 2)])
    vert["p"] = pos
    nn = nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-6)
    vert["n"] = np.clip(np.round(nn * 127), -127, 127)
    vert["t"] = tex
    vert["uv"] = uv
    raw += vert.tobytes() + tri.astype("<u4").tobytes()
    n = len(cc)
    card = np.zeros(n, dtype=[("c", "<f2", 3), ("u", "<f2", 3), ("v", "<f2", 3), ("box", "<u2", 4), ("r", "u1"), ("s", "u1")])
    card["c"] = cc
    card["u"] = cards["u"]
    card["v"] = cards["v"]
    card["box"] = np.clip(np.round(np.concatenate([cards["lo"], cards["hi"]], axis=1) * 65535), 0, 65535)
    card["r"] = rng.integers(0, 256, n)
    card["s"] = cards["slot"]
    raw += struct.pack("<I", n) + card.tobytes()
    lp, ln_, lu, lt, ltri = lite
    raw += struct.pack("<II", len(lp), ltri.size)
    lvert = np.zeros(len(lp), dtype=vert.dtype)
    lvert["p"] = lp - shift
    lnn = ln_ / np.maximum(np.linalg.norm(ln_, axis=1, keepdims=True), 1e-6)
    lvert["n"] = np.clip(np.round(lnn * 127), -127, 127)
    lvert["t"] = lt
    lvert["uv"] = lu
    raw += lvert.tobytes() + ltri.astype("<u4").tobytes()
    data = b"OLTREE1\0" + struct.pack("<I", len(raw)) + zlib.compress(bytes(raw), 9)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, name + ".oltree")
    with open(path, "wb") as f:
        f.write(data)
    h = pos[:, 1].max()
    print(f"{name}: {len(tri)} bark triangles ({len(ltri)} lite), {n} leaf cards, height {h:.1f} m, {len(data) / 1e6:.2f} MB")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", default=list(SPECS))
    ap.add_argument("--src", required=True, help="folder of Poly Haven glTF downloads, one subfolder per asset")
    ap.add_argument("--out", default=os.path.join(here, "..", "..", "game", "assets", "trees"))
    args = ap.parse_args()
    for name in args.names:
        build(name, args.src, args.out)


if __name__ == "__main__":
    sys.exit(main())
