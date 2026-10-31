# Panoramas: course horizons and cloud skies

Status: complete for reading (the six CD2 course `Panorama` entries and all
25 images in `PANSKY.LIB` decode, and every tile's runs end exactly at its
length)
Seen in: the `Panorama` entry of each `.CRZ` course; `PanNN.btc` (13
horizons) and `skyNN.btc` (12 skies) in CD1 `GAME/PANSKY.LIB` (an ARC0
archive)

## Overview

Links draws two photographic bands behind a course. The **sky** is a cloud
panorama; sky01 is clear and sky12 overcast, so the twelve form a weather
scale. In front of it, the **horizon** shows the land round the course
(hills, tree lines, fields) with the sky part transparent. A course ships
its own horizon in `Panorama`; the `PanNN.btc` horizons are stock ones for
courses that have none. Which sky and horizon a course uses is stored in
its `header` entry ([crz.md](crz.md#the-header-trailer-sky-and-horizon)).

Both use the same container: a small header, then square tiles of DXT5
block runs, the same runs as [BTCV textures](btcv.md). Unlike BTCV, tiles
carry no position; they are stored in order, row by row from the top.

`Panorama.prv` (in the course) and `*.prv` (in `PANSKY.LIB`) are small
previews of the same images as plain 32-bit TGA files (1280 x 120 for a
horizon, 512 x 35 for the sky previews).

Implemented by `olcore::decode_panorama`
(`libs/olcore/include/olcore/panorama.hpp`) and, for the game,
`LinksPanorama` (`game/scripts/formats/panorama.gd`). `oldump pano FILE
--tga out.tga` writes one out.

## Header (20 bytes)

All numbers are little-endian.

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | char[4] | tag | `nap\0` for a horizon, `yks\0` for a sky ("pan" and "sky" backwards) |
| 0x04 | u32 | width | Pixels: 7680 for horizons, 4800 for skies. The image wraps once round the viewer |
| 0x08 | u32 | height | Pixels: 720 for horizons, 320 for skies |
| 0x0C | u32 | columns | Tiles across the first tile row (30 and 19) |
| 0x10 | u32 | rows | Tile rows (3 and 2) |

## Tiles

Tile rows run top to bottom. Each row uses one tile edge: 256 while at
least 256 pixel rows are left, then the smallest power of two (at least 4)
that covers the rest. So a 720-pixel horizon has three rows of 256-pixel
tiles (the last 48 rows past the image bottom are padding), and a
320-pixel sky has a row of 256-pixel tiles and a row of 64-pixel ones (75
across). A row holds `ceil(width / edge)` tiles; the last column is cropped
at the image's right edge.

Each tile starts with a four-byte tag:

| Tag | Meaning | Then |
|-----|---------|------|
| `tpme` ("empt") | Nothing drawn here: fully transparent | Nothing |
| `desu` ("used") | A tile | u32 length, then `length` bytes of block runs that make `(edge / 4)^2` DXT5 blocks in raster order |

The file ends right after the last tile.

## Contents seen

- Course horizons: the top tile row is all `tpme` (sky). The land sits in
  the lower part, with alpha cut round tree lines and hills.
- Skies: fully opaque, haze at the bottom edge, clouds above.

## Custom skies in the 1.07 patch

The 1.07 patch installs a `skies` folder of `.sky` files named after the
weather (`Clear.sky`, `Mostly Sunny 1.sky`, ..., `Overcast.sky`, plus
`Mojave_Sunset`, `Mostly Cloudy`, `Ominous`, `Stormy` and `Sunrise`) and
lets the player pick one or a random one instead of the course's own. A
`.sky` file is an [ARC0](arc0.md) archive of the sky as 94 TGA tiles
(`_s_k_y_1.tga` to `_s_k_y_94.tga`: 19 of 256 pixels across the top, then
75 of 64 pixels, 4800 x 320 in all, the same grid as the `skyNN.btc`
tiles) and a `sky.prv` preview. The first twelve, in the order above, are
the same pictures as `sky01` to `sky12`, which gives the disc skies their
names: Clear, Mostly Sunny 1 to 3, Scattered Clouds 1 to 3, Partly Cloudy 1
and 2, Broken Clouds, Cloudy and Overcast.

Implemented by `olcore::decode_sky_archive` and
`LinksPanorama.decode_sky_archive`; `oldump pano` reads `.sky` files too.

## How the game shows them

Not yet measured from the running game; the game's code that draws them
wasn't worked out. `CourseBackdrop`
(`game/scripts/graphics/course_backdrop.gd`) draws each image on a cylinder
round the camera with square pixels, so a horizon spans 33.75 degrees and a
sky 24 degrees. Column 0 faces north (course +y) and columns run clockwise
seen from above. The sky's bottom row sits at eye level; for the horizon,
row 450 of 720 (where distant land meets the sky in the six courses) is
put at eye level. Both of those are guesses to check against the game.

OpenLinks2003 shows the course's own sky by default. The settings offer
the twelve disc skies, random, and any of the patch's `.sky` files found in
the player's `skies` folder. In the Photoreal look a picked sky also sets
the light: the sun dims and its shadows soften under cloud, and Sunrise and
Mojave Sunset warm it. Left on the course's own, Photoreal keeps its
photographed sky.
