#!/usr/bin/env python3
"""Renders the studio golf ball for the app icon (docs/brand/ball.png).

A real ball's dimple layout comes from a subdivided icosahedron; here
frequency 6 gives 362 dimples (real balls have 300 to 400). Each pixel of
the sphere finds its nearest dimple, and inside it the surface is a
shallow spherical dish, which bends the normal and darkens the bottom
(ambient occlusion). Lighting is a studio set-up: a large soft key light
top left, a cool fill, a green bounce from the turf below, a rim light,
and a glossy clear coat that reflects a softbox.

	python3 tools/brand/ball.py
"""
import pathlib

import numpy as np
from PIL import Image

OUT = pathlib.Path(__file__).resolve().parents[2] / "docs" / "brand" / "ball.png"
SIZE = 700          # output px; the ball radius is RADIUS of that
RADIUS = 300
SS = 3              # supersampling


def icosphere(freq: int) -> np.ndarray:
	t = (1 + 5 ** 0.5) / 2
	v = np.array([[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t],
		[0, -1, -t], [0, 1, -t], [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]], float)
	f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4),
		(11, 10, 2), (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8),
		(3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
	pts = []
	for a, b, c in f:
		A, B, C = v[a], v[b], v[c]
		for i in range(freq + 1):
			for j in range(freq + 1 - i):
				k = freq - i - j
				pts.append((A * i + B * j + C * k) / freq)
	p = np.array(pts)
	p /= np.linalg.norm(p, axis=1, keepdims=True)
	p = np.unique(np.round(p, 6), axis=0)
	return p


def rot(p: np.ndarray, ax: float, ay: float) -> np.ndarray:
	cx, sx, cy, sy = np.cos(ax), np.sin(ax), np.cos(ay), np.sin(ay)
	rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
	ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
	return p @ (ry @ rx).T


def norm(v):
	return v / np.linalg.norm(v, axis=-1, keepdims=True)


def main() -> None:
	n = SIZE * SS
	r = RADIUS * SS
	c = n / 2
	yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
	x = (xx + 0.5 - c) / r
	y = -(yy + 0.5 - c) / r          # +y up
	d2 = x * x + y * y
	inside = d2 < 1.0
	z = np.sqrt(np.clip(1 - d2, 0, 1))
	N = np.stack([x, y, z], -1)[inside]          # sphere normals, view along -z

	dimples = rot(icosphere(6), 0.42, 0.31).astype(np.float32)
	# Nearest dimple per pixel (by largest dot product), in chunks.
	best = np.empty(len(N), np.int32)
	bdot = np.empty(len(N), np.float32)
	for s in range(0, len(N), 400000):
		dots = N[s:s + 400000] @ dimples.T
		best[s:s + 400000] = dots.argmax(1)
		bdot[s:s + 400000] = dots.max(1)
	centre = dimples[best]
	# Angular distance to the dimple centre, against the dimple's angular radius.
	ang = np.arccos(np.clip(bdot, -1, 1))
	spacing = 0.205                  # ~ angle between neighbours at freq 6
	rim = spacing * 0.47
	u = np.clip(ang / rim, 0, 1)     # 0 centre, 1 dimple edge
	inside_d = u < 1
	# Dish: tilt the normal toward the dimple centre, most near the wall.
	tangent = norm(centre - N * bdot[:, None] + 1e-9)
	tilt = np.where(inside_d, 0.55 * u ** 1.4, 0)[:, None]
	Nd = norm(N + tangent * tilt)
	depth = np.where(inside_d, 1 - u * u, 0)       # 1 at the dimple bottom
	ao = 1 - 0.20 * depth

	V = np.array([0, 0, 1], np.float32)
	key = norm(np.array([-0.55, 0.65, 0.55], np.float32))
	fill = norm(np.array([0.8, 0.1, 0.6], np.float32))
	bounce = norm(np.array([0.0, -1.0, 0.25], np.float32))
	rimL = norm(np.array([0.6, 0.5, -0.6], np.float32))

	def wrap(L, w):          # soft, wrapped diffuse for big light sources
		return np.clip((Nd @ L + w) / (1 + w), 0, 1)

	white = np.array([0.95, 0.955, 0.96], np.float32)
	col = (
		white * (1.05 * wrap(key, 0.35))[:, None] * np.array([1.0, 0.99, 0.97])
		+ white * (0.22 * wrap(fill, 0.5))[:, None] * np.array([0.85, 0.92, 1.0])
		+ white * (0.30 * wrap(bounce, 0.2))[:, None] * np.array([0.35, 0.75, 0.45])
		+ 0.06
	) * ao[:, None]
	# Fresnel rim and back light.
	fres = (1 - np.clip(N @ V, 0, 1)) ** 3
	col += (0.35 * fres * np.clip(N @ rimL + 0.6, 0, 1))[:, None] * np.array([0.8, 0.9, 1.0])
	# Clear coat: a soft rectangular softbox highlight and a broad sheen.
	H = norm(key + V)
	spec = np.clip(Nd @ H, 0, 1) ** 90 * 1.1 + np.clip(Nd @ H, 0, 1) ** 12 * 0.12
	col += spec[:, None]
	col = 1 - np.exp(-col * 1.25)            # filmic shoulder
	col = np.clip(col / (1 - np.exp(-1.25 * 1.05)), 0, 1)

	img = np.zeros((n, n, 4), np.float32)
	img[inside, :3] = col
	# Anti-aliased edge.
	edge = np.clip((1 - np.sqrt(d2)) * r, 0, 1)
	img[..., 3] = edge
	out = Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").resize((SIZE, SIZE), Image.LANCZOS)
	out.save(OUT, optimize=True)
	print("wrote", OUT, len(dimples), "dimples")


if __name__ == "__main__":
	main()
