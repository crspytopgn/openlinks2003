# BTCV texture (`.btc` entries) and block runs

Status: complete for every BTCV texture and `.CMF` texture set on CD3
(6,508 textures, 47 texture sets)
Seen in: entries of `.BTX` and `.TOP` objects, `CROWDS.LIB` and
`TRNYCRWD.LIB`, `.CMF` texture sets (as bare block runs)

## Overview

The game's own texture format. Pixels are DXT5 (BC3) blocks, but the blocks
are stored as *runs* so that empty, opaque and flat areas take less space.
A BTCV image is cut into square tiles of 64, 128 or 256 pixels; tiles that
would be fully transparent are left out.

Everything is little-endian.

## Header

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | char[4] | magic | `BTCV` |
| 0x04 | u16 | width | Pixels |
| 0x06 | u16 | height | Pixels |
| 0x08 | u16 | unknown | Always 1 |
| 0x0A | u16 | format | Always 11 (0x0B); presumably "DXT5 runs" |
| 0x0C | u32 | reserved | Always 0 |
| 0x10 | u32 | tile_count | |
| 0x14 | tile[tile_count] | tiles | 16 bytes each, see below |

### Tile record (16 bytes)

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | u16 | id | Tile number in a grid of the tile size; only used to find a tile |
| 0x02 | u16 | size | Tile edge in pixels: 64, 128 or 256 |
| 0x04 | u16 | x | Left edge of the tile, in pixels from the left of the image |
| 0x06 | u16 | y | **Bottom** edge of the tile, in pixels from the **bottom** of the image |
| 0x08 | u32 | offset | Start of the tile's block runs, from the start of the BTCV data |
| 0x0C | u32 | length | Length of the block runs in bytes |

Tile pixel rows run top to bottom, but tiles are positioned from the bottom
left. A tile's top row therefore lands on image row `height - y - size`
(counting rows from the top); rows above the image top and columns past its
right edge are cropped. Pixels not covered by any tile are transparent black.

Because `x`, `y` and `size` are multiples of four, a decoder can assemble a
DXT5 canvas whose height is `height` rounded up to a multiple of four, place
every tile at block row `(padded_height - y - size) / 4`, and crop the top
`padded_height - height` rows at the end.

## Block runs

A tile (and each texture in a `.CMF`) is a sequence of runs that together
produce `(size / 4)²` DXT5 blocks in raster order: left to right, then top
to bottom. Each run starts with a u16:

| Bits | Meaning |
|------|---------|
| 0-11 | Number of blocks in the run; 0 means 4,096 |
| 12-15 | Mode |

| Mode | Bytes per block | Block contents |
|------|----------------:|----------------|
| 1 | 0 | Fully transparent black block; no data follows |
| 2 | 8 | A DXT1 colour block (two RGB565 colours, 32 bits of 2-bit indices). Alpha is fully opaque |
| 3 | 16 | A complete DXT5 block: 8 bytes of alpha (two 8-bit endpoints, 48 bits of 3-bit indices), then 8 bytes of colour |
| 4 | 4 | One flat colour for the whole block, as bytes blue, green, red, alpha. When the game converts to DXT5 it rounds the colour to RGB565 and makes the block opaque |

Colour blocks in modes 2 and 3 follow normal DXT5 rules (the 4-colour
palette is always used, whatever the order of the two endpoints). Runs never
straddle tiles; a tile's runs end exactly at its `length`.

## Contents seen

- Object billboards (`.BTX`): five sizes `A` to `E`, each about half of the
  one before. For `Tall Trees100`: 467 x 550, 234 x 275, 117 x 138, 59 x 69,
  30 x 35.
- Top views (`.TOP`): one to three sizes.
- Crowd sprites (`CROWDS.LIB`): 980 small images.

## Implementation

`olcore::decode_btcv` (`libs/olcore/include/olcore/btcv.hpp`) returns an
RGBA8 image; `olcore::decode_block_runs` expands runs into DXT5 blocks and
`olcore::decode_dxt5` turns blocks into pixels. The Godot side
(`game/scripts/formats/btcv.gd`) builds a DXT5 canvas the same way and lets
`Image.decompress()` do the pixel work.
