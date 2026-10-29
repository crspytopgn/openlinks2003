# Course objects (`MasterObj`, `2DPlant`, `3DPlant`, `TrnyPlant`)

Status: partial. Billboard types (`MasterObj`) and billboard placements
(`2DPlant`) are decoded and drawn by the course viewer. `3DPlant`,
`MasterObj3D` and `TrnyPlant` are only surveyed.
Seen in: entries of every course archive ([crz.md](crz.md)); checked on
Gleneagles (399,306 billboards) and Kauri (643,211)

## Overview

A course carries its own copy of every object it uses. Billboards (trees,
bushes, grass, small props) are flat sprites that turn to face the camera.
Their sprites are stored in the course as `<name>A.btc` to `<name>E.btc`
([BTCV](btcv.md), five sizes, each about half the one before), with the same
names as the Course Designer library objects. `MasterObj` lists the
billboard types and `2DPlant` places them. 3D objects (bridges, walls,
buildings) are listed in `MasterObj3D` and placed by `3DPlant`.

Units are the course's own: feet, z up (see [crz.md](crz.md)).

## `MasterObj`: billboard types

A saved memory image: every offset in it is from the start of the entry.
Only the parts needed to name each type are described here.

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | u32 | size | Entry size in bytes |
| 0x04 | u32 | | 0x80, where the sprite tile records start |
| 0x08 | u32 | type_count | 126 at Gleneagles, 181 at Kauri |
| 0x0C | u32 | type_table | Offset of `type_count` u32 offsets, one per type record |
| 0x18 | u32 | | Count of a second table (1,115 at Gleneagles) |
| 0x1C | u32 | | Offset of that table: u32 offsets pointing into the sprite descriptors; not decoded |

The rest of the 0x80-byte header holds further counts and offsets that are
not decoded (one of them, 630 at Gleneagles, equals the number of sprites).

From 0x80 the entry holds, for each sprite size of each type, the sprite's
**tile records** followed by its **sprite descriptor**:

- Tile record (64 bytes): `char name[32]` (the `.btc` entry, e.g.
  `Bushes156A.btc`), `u32 width`, `u32 height` (the tile, 64 or 128),
  `u32` 0xC0000001, then fields filled in at run time and a tile number.
- Sprite descriptor: a u32, two zero u32, then `u32 width`, `u32 height`
  (the sprite in pixels), `u32 tile_count`, `u32 first_tile` and
  `u32 end_tile` (offsets of its tile records).

Type record, at the offset given by the type table:

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | u32 | width | Pixels of the largest sprite |
| 0x04 | u32 | height | |
| 0x08 | u32 | level_count | 5 (sizes A to E) |
| 0x0C | u32 | levels | Offset of `level_count` 20-byte level records |
| 0x18 | f32 | aspect | width / height |
| 0x34 | u32 | id | Object id; Course Designer ids look the same (0x84......) but these course-local ones differ |

Level record (20 bytes): `u32` (number of tiles), `u32` (polygon or
vertex count), `u32 sprite` (offset of the sprite descriptor *width* field,
so the descriptor's `first_tile` is at `sprite + 12`), and two more offsets.

To name a type: take its first level, follow `sprite + 12` to the first tile
record, read the name, and drop the trailing `A.btc` to get the object name
(`Tall Trees212`).

## `2DPlant`: billboard placements

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | char[4] | magic | `2JBO` |
| 0x04 | u32 | version | 2 |
| 0x08 | u32 | count | Number of placements |
| 0x0C | | | Zero up to 0x40 |
| 0x40 | | stream | Cell markers and placements to the end of the entry |

The ground is cut into **64-foot cells**. Each cell's placements are
preceded by a cell marker:

| Type | Name | Notes |
|------|------|-------|
| u16 | marker | 0xFFFF |
| f32 | x | Cell corner (minimum x), a multiple of 64 |
| f32 | y | Cell corner (minimum y), a multiple of 64 |
| f32 | z | Base height of the cell |

Then placements until the next marker:

| Type | Name | Notes |
|------|------|-------|
| u16 | type | Index into the `MasterObj` types |
| u32 | instance | Low 29 bits: a number unique to the placement. Bit 29: an extra byte follows. Bit 30: an extra word follows |
| u8 | extra_byte | Only with bit 29. Signed, between about -55 and 56; meaning unknown (rotation or tint are candidates) |
| u16 | extra_word | Only with bit 30. 1 to 235; meaning unknown |
| u16 | x | Offset from the cell corner, in 1/16 ft (0 to 1023) |
| u16 | y | Offset from the cell corner, in 1/16 ft |
| i16 | z | Offset from the cell's base height, in 1/16 ft |
| u16 | height | Billboard height, in 1/16 ft (0.5 to 115 ft seen) |

So a placement stands at `(cell.x + x/16, cell.y + y/16, cell.z + z/16)`.
The billboard's width is `height * aspect` from its type. These heights
match the terrain mesh to within a foot or so, and the placements leave the
fairways and greens clear. About 80% of placements carry both extra fields.

## `3DPlant`: 3D object placements (surveyed)

No header: a sequence of 88-byte records (163 at Gleneagles). Each starts
with a u32 that is unique per record and a u32 that is 0 or 1, followed by
20 f32. The first three are a position (feet). The next six look like the two
corners of a bounding box, then 0.5, then values that look like a rotation
and scale. They are not decoded yet, and neither is `MasterObj3D`, which
holds the 3D object meshes (as a memory image, like `MasterObj`). The
`<course> 3DNNN.maq` and `Tourney 3DNNN.maq` entries are their paletted
textures.

## `TrnyPlant`: tournament extras (surveyed)

`u32 2`, `u32 count`, zero up to 0x40, then a stream like `2DPlant` with
narrower records: cells start with a 0xFF byte and three f32, and
placements are 11 bytes (`u8`, `u32`, `u16 x`, `u16 y`, `i16 z` in the same
units). These are presumably the crowds and tents shown in tournament mode.
Not decoded further.

## Implementation

- `olcore::parse_billboard_types` and `olcore::parse_billboard_placements`
  (`libs/olcore/include/olcore/course_objects.hpp`).
- `olcourse export` writes `objects.bin` (placements in Godot metres,
  grouped by type), one TGA per type under `textures/objects/`, and a
  `billboards` list in `course.json`.
- The course viewer draws them with `CourseBillboards`
  (`game/scripts/course/course_billboards.gd`): one MultiMesh per type per
  100 m chunk; small plants are hidden beyond 150 to 700 m.

## Open questions

- The meanings of `extra_byte` and `extra_word` (probably per-instance
  variation such as a turn, a mirror or a shade).
- The rest of `MasterObj`: per-level polygon data (the same structure as the
  `MasterObj` entry of a library `.BTX`) and the remaining header tables.
- `3DPlant`, `MasterObj3D`, `TrnyPlant` and `ObjectCull.dat`.
