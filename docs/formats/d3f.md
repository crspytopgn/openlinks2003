# Bitmap fonts (`.D3F`)

Status: complete for the fonts in `GRAPHICS.LS` (all 48 read with
`oldump font`). The two in `GAME/ASSETS/FONTS` are an older layout (see Open
questions).
Seen in: `GAME/GRAPHICS.LS` (48 fonts), `GAME/ASSETS/FONTS/*.D3F`

## Overview

A Windows font rendered ahead of time at one size into square texture
pages, with a table saying where each of the 256 character codes sits. The
game draws all its text from these. Codes are Windows-1252.

`RESOURCE.DLL` names the sets the game picks by screen size. The in-play
set is `small.d3f`, `spbt10/12/14.d3f` and `sc8/10/12.d3f` (the number
follows the 800, 1024 and 1280-wide interface sizes, like the `08`/`12`
suffixes on the HUD sheets). Menus use `mm800`/`mm1024`/`mm1280` (Verdana)
with `mms*`, `egypt*`, `lrgcap*`, `menuhead` and `menu12`.

Implemented by `olcore::read_d3f` (`libs/olcore/include/olcore/d3f.hpp`)
and `D3fFont` (`game/scripts/data/d3f_font.gd`), which also builds a Godot
`FontFile` from it.

## Layout

All numbers are little-endian.

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | char[3] | magic | `D3F` |
| 0x03 | u8 | kind | `0xb4`: pages hold 8-bit coverage. `0xd4`: pages hold 32-bit BGRA (shaded or coloured lettering: `ARBLCK*`, `ARBL62`, `LRGCAP*`, `ANBI17`) |
| 0x04 | char[64] | face | Windows face name, NUL-padded (`Arial`, `Arial Narrow`, `Verdana`, `Trebuchet MS`, ...) |
| 0x44 | s32 | height | Negative: the em height in pixels the font was rendered at |
| 0x48 | u8 | italic | 1 for italic faces (`ABI*`, `ANBI*`, `MM*`) |
| 0x49 | s32 | weight | 400 normal, 700 bold |
| 0x4d | s32 | page_count | 1 to 14 |
| 0x51 | s32 | line_height | Height of every glyph cell, in pixels |
| 0x55 | u8[256] | page | Page of each code |
| 0x155 | u8[256] | x | Left edge of each cell in its page |
| 0x255 | u8[256] | y | Top edge |
| 0x355 | u8[256] | width | Cell width; 0 means the font has no such character |
| 0x455 | s8[256] | left | Space before the cell (negative overhangs) |
| 0x555 | s8[256] | right | Space after the cell |
| 0x655 | s32[page_count] | page_offset | Absolute offset of each page |

The pen advances `left + width + right` per character. A cell is drawn
`left` pixels after the pen, from the top of the line. Codes below 0x20
usually hold an empty box.

### Page

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | s32 | side | Negative: the page is `-side` pixels square (128 or 256) |
| 0x04 | s32 | packed_size | Bytes of LZW data that follow |
| 0x08 | u8[] | data | The page's pixels, rows top to bottom, compressed with the archive LZW ([ls-archive.md](ls-archive.md#compression)) |

Coverage pages are one byte a pixel (0 empty, 255 solid; anti-aliased
edges in between). Colour pages are B, G, R, A. Some streams end before the
page is full; the rest is empty.

The files store no ascent. The readers take it from the bitmap: the row
under the lowest visible pixel of `H` is the baseline.

## Open questions

- `ASSETS/FONTS/ARIAL12.D3F` and `COMICS_1.D3F` have kind `0x34` and a
  different table layout; nothing in the in-play interface uses them.
- Whether the game ever reads the `left` bearing of the first character on
  a line (it would shift text left by a pixel for some letters).
