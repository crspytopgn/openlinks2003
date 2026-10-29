# Course Designer 3D model (`.XYZ`, `.CMF`, `.MAP`, `.PRV`)

Status: geometry and textures complete for all 47 models on CD3; a few
per-face flags unknown
Seen in: CD3 `GAME/OBJECT/3D2K3*/`

## Overview

Each 3D object (`3D2K3Walls000` and so on) comes as four files with the
same long name:

| File | Holds |
|------|-------|
| `.XYZ` | Mesh: positions, per-corner uvs, polygons |
| `.CMF` | Textures as DXT5 block runs, with mip levels |
| `.MAP` | The same textures as 8-bit paletted images. Probably for an older or software renderer; not needed |
| `.PRV` | A 128 x 128 24-bit TGA preview for the Designer |

Units are inches. +y is up, and models stand on y = 0. `OBJECT.LIB` lists
each model's bounding box (height, x width, z depth).

## `.XYZ`

A memory image with tables placed by offset. Little-endian throughout.

### Header

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | u32 | size | Size of the file |
| 0x04 | u32 | unknown | Always 1 |
| 0x08 | u32 | unknown | Always 1 |
| 0x0C | u32[3] | reserved | 0 |
| 0x18 | (u32 count, u32 offset)[5] | tables | Positions, uvs, faces, corners, material (see below) |
| 0x40 | u32 | texture_count | Number of textures the faces use, which is also the number of textures in the `.CMF` |
| 0x44 | u32 | unknown | Always 2 |
| 0x60 | u32 | | Repeats the position count |
| 0x70 | u32 | | Repeats the face count |

The tables follow from 0xA4, in this order:

| Table | Entry | Notes |
|-------|-------|-------|
| positions | f32 x, y, z | |
| uvs | f32 u, v | One per corner, not per position. v = 0 is the top of the texture |
| faces | 12 bytes, see below | |
| corners | u16 | Position index for each polygon corner |
| material | 16 bytes | One entry, always `cd` filler bytes |

### Face (12 bytes)

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | u16 | count | Corners in the polygon: 3 or 4 seen |
| 0x02 | u16 | first | First corner; the polygon uses corners `first` to `first + count - 1` and the same range of uvs |
| 0x04 | u16 | flags | 0, 2 or 3 seen; unknown |
| 0x06 | u16 | texture | Index into the `.CMF` textures |
| 0x08 | u32 | reserved | 0 |

Polygons are convex, so a triangle fan from the first corner works.

## `.CMF`

An [ARC0](arc0.md) archive with one entry, `Textures`:

| Type | Name | Notes |
|------|------|-------|
| u32 | reserved | 0 |
| level[] | levels | Until the end of the entry |

Each level is u32 width, u32 height, then [block runs](btcv.md#block-runs)
for `ceil(width/4) x ceil(height/4)` DXT5 blocks. Every texture has exactly
four levels, each half the size of the one before (256, 128, 64, 32 or
128, 64, 32, 16), so texture *i* is levels `4i` to `4i + 3`. Sizes are
powers of two and not always square.

Some textures are bright magenta in places; they look like colour-key
areas meant to be cut out, which still has to be confirmed.

## `.MAP`

A u32 size, a u32 1, a u32 count, then that many offsets to texture
records. Each record holds a width, a height, a bit depth of 8 and a
256-entry RGBX palette followed by indexed pixels and smaller levels. Not
used by the loader.

## Implementation

`olcore::read_model`, `olcore::read_model_textures` and
`olcore::triangulate` (`libs/olcore/include/olcore/model.hpp`).
`tools/olobj model <xyz> <cmf> <outdir>` writes a Wavefront OBJ with its
textures for checking in any 3D viewer.

## Open questions

- Face `flags`, and whether magenta marks transparency.
- The fields in the header between 0x44 and 0xA4.
