#!/usr/bin/env python3
"""Writes the OpenLinks2003 logo SVGs into docs/brand/.

The mark is drawn here in code so it stays exact and easy to tweak; the
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
# The pennant: a soft, wind-filled triangle off the top of the pin.
FLAG = "M 548 236 C 640 252 724 282 790 318 C 800 324 800 336 790 342 C 724 378 640 404 548 420 Z"
POLE_X, POLE_TOP, POLE_BOTTOM, POLE_W = 524, 214, 744, 24
CUP = (536, 748, 84, 22)  # cx, cy, rx, ry
BALL = (362, 712, 62)  # cx, cy, r


def defs(uid: str) -> str:
	return f"""
	<defs>
		<clipPath id="{uid}-clip"><path d="{SQUIRCLE}"/></clipPath>
		<linearGradient id="{uid}-sky" x1="0" y1="0" x2="0.35" y2="1">
			<stop offset="0" stop-color="#2E7CF6"/>
			<stop offset="0.55" stop-color="#5FB4FF"/>
			<stop offset="1" stop-color="#B9E2FF"/>
		</linearGradient>
		<linearGradient id="{uid}-turf" x1="0" y1="0" x2="0.25" y2="1">
			<stop offset="0" stop-color="#5CD16F"/>
			<stop offset="0.45" stop-color="#22A851"/>
			<stop offset="1" stop-color="#0A6E3A"/>
		</linearGradient>
		<radialGradient id="{uid}-sheen" cx="0.3" cy="0.05" r="0.9">
			<stop offset="0" stop-color="#fff" stop-opacity="0.35"/>
			<stop offset="0.6" stop-color="#fff" stop-opacity="0"/>
		</radialGradient>
		<linearGradient id="{uid}-glass" x1="0" y1="0" x2="0.6" y2="1">
			<stop offset="0" stop-color="#FF6B5E" stop-opacity="0.96"/>
			<stop offset="0.55" stop-color="#FF3B30" stop-opacity="0.9"/>
			<stop offset="1" stop-color="#D70015" stop-opacity="0.95"/>
		</linearGradient>
		<linearGradient id="{uid}-gloss" x1="0" y1="0" x2="0" y2="1">
			<stop offset="0" stop-color="#fff" stop-opacity="0.55"/>
			<stop offset="0.45" stop-color="#fff" stop-opacity="0.08"/>
			<stop offset="1" stop-color="#fff" stop-opacity="0"/>
		</linearGradient>
		<radialGradient id="{uid}-sun" cx="0.82" cy="0.12" r="0.5">
			<stop offset="0" stop-color="#fff" stop-opacity="0.7"/>
			<stop offset="0.35" stop-color="#fff" stop-opacity="0.18"/>
			<stop offset="1" stop-color="#fff" stop-opacity="0"/>
		</radialGradient>
		<pattern id="{uid}-mow" width="120" height="1024" patternUnits="userSpaceOnUse" patternTransform="rotate(-24)">
			<rect width="60" height="1024" fill="#fff" opacity="0.04"/>
		</pattern>
		<linearGradient id="{uid}-rim" x1="0" y1="0" x2="1" y2="1">
			<stop offset="0" stop-color="#fff" stop-opacity="1"/>
			<stop offset="0.45" stop-color="#fff" stop-opacity="0.25"/>
			<stop offset="1" stop-color="#fff" stop-opacity="0.85"/>
		</linearGradient>
		<linearGradient id="{uid}-pole" x1="0" y1="0" x2="1" y2="0">
			<stop offset="0" stop-color="#fff"/>
			<stop offset="0.6" stop-color="#F2F5F7"/>
			<stop offset="1" stop-color="#C9D2D9"/>
		</linearGradient>
		<radialGradient id="{uid}-ball" cx="0.36" cy="0.3" r="0.75">
			<stop offset="0" stop-color="#fff"/>
			<stop offset="0.55" stop-color="#F1F4F6"/>
			<stop offset="1" stop-color="#B7C3CC"/>
		</radialGradient>
		<radialGradient id="{uid}-cup" cx="0.5" cy="0.35" r="0.6">
			<stop offset="0" stop-color="#03321A"/>
			<stop offset="1" stop-color="#075A2E"/>
		</radialGradient>
		<filter id="{uid}-frost" x="-20%" y="-20%" width="140%" height="140%">
			<feGaussianBlur stdDeviation="18"/>
		</filter>
		<filter id="{uid}-soft" x="-50%" y="-50%" width="200%" height="200%">
			<feGaussianBlur stdDeviation="14"/>
		</filter>
		<clipPath id="{uid}-flag"><path d="{FLAG}"/></clipPath>
	</defs>"""


def scene(uid: str) -> str:
	"""The background: sky over a rolling green, clipped to the squircle."""
	return f"""
		<rect width="{SIZE}" height="{SIZE}" fill="url(#{uid}-sky)"/>
		<rect width="{SIZE}" height="{SIZE}" fill="url(#{uid}-sun)"/>
		<path d="M0 640 C 220 560 520 548 1024 610 L1024 1024 L0 1024 Z" fill="url(#{uid}-turf)"/>
		<path d="M0 640 C 220 560 520 548 1024 610 L1024 1024 L0 1024 Z" fill="url(#{uid}-mow)"/>
		<path d="M0 640 C 220 560 520 548 1024 610" fill="none" stroke="#B8F5B0" stroke-opacity="0.55" stroke-width="5"/>"""


def glyph(uid: str) -> str:
	cx, cy, rx, ry = CUP
	bx, by, br = BALL
	px = POLE_X
	return f"""
		<!-- shadows -->
		<ellipse cx="{px + 140}" cy="{POLE_BOTTOM + 4}" rx="150" ry="16" fill="#03321A" opacity="0.28" filter="url(#{uid}-soft)"/>
		<ellipse cx="{bx + 22}" cy="{by + br - 6}" rx="{br * 0.95:.0f}" ry="16" fill="#03321A" opacity="0.4" filter="url(#{uid}-soft)"/>
		<!-- cup -->
		<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="url(#{uid}-cup)"/>
		<path d="M{cx - rx} {cy} A {rx} {ry} 0 0 0 {cx + rx} {cy}" fill="none" stroke="#fff" stroke-opacity="0.35" stroke-width="4"/>
		<!-- pin -->
		<rect x="{px}" y="{POLE_TOP}" width="{POLE_W}" height="{POLE_BOTTOM - POLE_TOP}" rx="{POLE_W / 2}" fill="url(#{uid}-pole)"/>
		<path d="{FLAG}" fill="#0B3D91" opacity="0.28" filter="url(#{uid}-soft)" transform="translate(10 22)"/>
		<!-- liquid-glass pennant: the scene behind it, frosted and tinted -->
		<g clip-path="url(#{uid}-flag)">
			<g filter="url(#{uid}-frost)">{scene(uid)}</g>
			<path d="{FLAG}" fill="url(#{uid}-glass)"/>
			<path d="{FLAG}" fill="url(#{uid}-gloss)"/>
			<path d="{FLAG}" fill="none" stroke="#7A0010" stroke-opacity="0.35" stroke-width="18" transform="translate(4 8)"/>
		</g>
		<path d="{FLAG}" fill="none" stroke="url(#{uid}-rim)" stroke-width="5" stroke-linejoin="round"/>
		<!-- ball -->
		<circle cx="{bx}" cy="{by}" r="{br}" fill="url(#{uid}-ball)"/>
		<ellipse cx="{bx - 20}" cy="{by - 26}" rx="20" ry="13" fill="#fff" opacity="0.9" transform="rotate(-30 {bx - 20} {by - 26})"/>"""


def icon_svg(uid: str = "ol", rim: bool = True) -> str:
	"""The app icon: the full scene in an iOS-style squircle."""
	edge = (
		f'<path d="{SQUIRCLE}" fill="none" stroke="#fff" stroke-opacity="0.35" stroke-width="6"/>'
		if rim else ""
	)
	return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">
	<title>OpenLinks2003</title>{defs(uid)}
	<g clip-path="url(#{uid}-clip)">{scene(uid)}
		<rect width="{SIZE}" height="{SIZE}" fill="url(#{uid}-sheen)"/>{glyph(uid)}
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
		<g clip-path="url(#wm-clip)">{scene("wm")}
			<rect width="{SIZE}" height="{SIZE}" fill="url(#wm-sheen)"/>{glyph("wm")}
		</g>
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
