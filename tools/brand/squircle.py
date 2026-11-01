"""Apple-style continuous-corner squircle (superellipse) as an SVG path."""
import math


def squircle_path(size: float = 1024.0, inset: float = 0.0, n: float = 5.0, steps: int = 256) -> str:
	"""Superellipse |x|^n + |y|^n = 1 filling a size x size box, shrunk by inset."""
	r = size / 2 - inset
	c = size / 2
	pts = []
	for i in range(steps):
		t = 2 * math.pi * i / steps
		ct, st = math.cos(t), math.sin(t)
		x = c + r * math.copysign(abs(ct) ** (2 / n), ct)
		y = c + r * math.copysign(abs(st) ** (2 / n), st)
		pts.append(f"{x:.1f},{y:.1f}")
	return "M" + " L".join(pts) + " Z"
