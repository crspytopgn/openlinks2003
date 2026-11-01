#!/usr/bin/env python3
"""Writes the OpenLinks2003 logo SVGs into docs/brand/.

The icon is a studio-lit golf ball (rendered by ball.py) on a dark
backdrop with a glow of turf, in an iOS squircle; the
wordmark is set in Inter Display (SIL Open Font License) and converted to
outlines so it looks the same without the font installed. Run
tools/brand/render.js afterwards for the PNGs, banners and social card.

	python3 tools/brand/make_brand.py
"""
from __future__ import annotations

import pathlib
import sys

from squircle import squircle_path

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "brand"
FONTS = pathlib.Path("/usr/share/fonts/opentype/inter")
WORD_FONT = FONTS / "InterDisplay-SemiBold.otf"
YEAR_FONT = FONTS / "InterDisplay-Light.otf"

SIZE = 1024
SQUIRCLE = squircle_path(SIZE)
BALL_PNG = OUT / "ball.png"          # rendered by tools/brand/ball.py
BALL = (512, 480, 270)               # cx, cy, r of the ball in the icon


def ball_data_uri() -> str:
	"""The rendered ball as an embedded WebP, so the SVG stands alone."""
	import base64
	import io

	from PIL import Image

	buf = io.BytesIO()
	Image.open(BALL_PNG).save(buf, "WEBP", quality=92, method=6)
	return "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode()


def defs(uid: str) -> str:
	return f"""
	<defs>
		<clipPath id="{uid}-clip"><path d="{SQUIRCLE}"/></clipPath>
		<radialGradient id="{uid}-bg" cx="0.5" cy="0.3" r="0.85">
			<stop offset="0" stop-color="#2C2C30"/>
			<stop offset="0.6" stop-color="#121214"/>
			<stop offset="1" stop-color="#050506"/>
		</radialGradient>
		<radialGradient id="{uid}-turf" cx="0.5" cy="1.05" r="0.75">
			<stop offset="0" stop-color="#2FB15A" stop-opacity="0.75"/>
			<stop offset="0.45" stop-color="#14713A" stop-opacity="0.4"/>
			<stop offset="1" stop-color="#0A3D20" stop-opacity="0"/>
		</radialGradient>
		<radialGradient id="{uid}-shadow" cx="0.5" cy="0.5" r="0.5">
			<stop offset="0" stop-color="#000" stop-opacity="0.9"/>
			<stop offset="0.5" stop-color="#000" stop-opacity="0.45"/>
			<stop offset="1" stop-color="#000" stop-opacity="0"/>
		</radialGradient>
		<radialGradient id="{uid}-halo" cx="0.5" cy="0.5" r="0.5">
			<stop offset="0.55" stop-color="#fff" stop-opacity="0.07"/>
			<stop offset="1" stop-color="#fff" stop-opacity="0"/>
		</radialGradient>
	</defs>"""


def scene(uid: str, ball: str) -> str:
	"""Studio backdrop, turf glow, contact shadow and the ball."""
	cx, cy, r = BALL
	return f"""
		<rect width="{SIZE}" height="{SIZE}" fill="url(#{uid}-bg)"/>
		<rect width="{SIZE}" height="{SIZE}" fill="url(#{uid}-turf)"/>
		<circle cx="{cx}" cy="{cy}" r="{r * 1.45:.0f}" fill="url(#{uid}-halo)"/>
		<ellipse cx="{cx + 18}" cy="{cy + r + 22}" rx="{r * 0.92:.0f}" ry="40" fill="url(#{uid}-shadow)"/>
		<ellipse cx="{cx + 8}" cy="{cy + r + 6}" rx="{r * 0.45:.0f}" ry="14" fill="url(#{uid}-shadow)"/>
		<image href="{ball}" x="{cx - 315}" y="{cy - 315}" width="630" height="630"/>"""


def icon_svg(uid: str = "ol", rim: bool = True) -> str:
	"""The app icon: a studio-lit golf ball in an iOS-style squircle."""
	edge = (
		f'<path d="{SQUIRCLE}" fill="none" stroke="#fff" stroke-opacity="0.14" stroke-width="4"/>'
		if rim else ""
	)
	return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">
	<title>OpenLinks2003</title>{defs(uid)}
	<g clip-path="url(#{uid}-clip)">{scene(uid, ball_data_uri())}
	</g>
	{edge}
</svg>
"""


def text_outline(font_path: pathlib.Path, text: str, size: float, x: float, baseline: float, tracking: float = -0.02) -> tuple[str, float]:
	"""Returns (path data, advance width) for text set in an OpenType font."""
	from fontTools.pens.svgPathPen import SVGPathPen
	from fontTools.pens.transformPen import TransformPen
	from fontTools.ttLib import TTFont

	font = TTFont(str(font_path))
	glyphs = font.getGlyphSet()
	cmap = font.getBestCmap()
	scale = size / font["head"].unitsPerEm
	pen = SVGPathPen(glyphs)
	cursor = x
	for ch in text:
		name = cmap[ord(ch)]
		glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, cursor, baseline)))
		cursor += glyphs[name].width * scale + tracking * size
	return pen.getCommands(), cursor - x - tracking * size


def wordmark_svg(dark: bool) -> str:
	"""App icon beside the name, Apple-style: bold name, light year."""
	ink = "#F5F5F7" if dark else "#1D1D1F"
	year = "#A1A1A6" if dark else "#6E6E73"
	icon_px, gap, size = 200, 44, 132
	baseline = 100 + size * 0.36
	x0 = icon_px + gap
	word, w1 = text_outline(WORD_FONT, "OpenLinks", size, x0, baseline)
	yr, w2 = text_outline(YEAR_FONT, "2003", size, x0 + w1 + size * 0.06, baseline)
	width = int(x0 + w1 + size * 0.06 + w2 + 8)
	scale = icon_px / SIZE
	return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} 200" width="{width}" height="200">
	<title>OpenLinks2003</title>{defs("wm")}
	<g transform="scale({scale})">
		<g clip-path="url(#wm-clip)">{scene("wm", ball_data_uri())}</g>
	</g>
	<path d="{word}" fill="{ink}"/>
	<path d="{yr}" fill="{year}"/>
</svg>
"""


def main() -> int:
	OUT.mkdir(parents=True, exist_ok=True)
	(OUT / "app-icon.svg").write_text(icon_svg())
	(OUT / "wordmark-light.svg").write_text(wordmark_svg(dark=False))
	(OUT / "wordmark-dark.svg").write_text(wordmark_svg(dark=True))
	for name in ("app-icon.svg", "wordmark-light.svg", "wordmark-dark.svg"):
		print("wrote", OUT / name)
	return 0


if __name__ == "__main__":
	sys.exit(main())
