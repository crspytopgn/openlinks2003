# Converted course (`.CVT`)

Status: partial. Holes, terrain mesh and terrain types are decoded, which is
enough to show and play the 39 courses with the standard textures. Outlines
(hazards, out of bounds) are named but not decoded.
Seen in: CD2 `CONVERT/*.CVT` (39 files), next to `CRX2CRZ.EXE`

## Overview

Links 2003 shipped a converter for courses from Links LS 1997 to 2000. The
player points it at an old `.CRX` course from their own Links LS discs, and it
writes a Links 2003 `.CRZ`. The `.CVT` files carry the parts of each course
that were rebuilt for Links 2003: a new terrain mesh, the holes, and the
surface types. The `.CRX` would add the rest: the object placements, the sky
panorama, splash screens and sounds. We don't have any `.CRX` files, and we
don't need them to play: a `.CVT` on its own gives a complete, playable
layout drawn with the standard textures from `STDTER_1.LIB`.

A `.CVT` is a [locked course archive](crz.md), opened with the same keys as
the `.CRZ` courses. Every file has the same 13 entries (DEVILSIS has no
`OBIDShapes`):

| Entry | Holds | Status |
|-------|-------|--------|
| `newformat` | Text `V.2.0` | |
| `TerrainTypes` | Surface types (below) | Decoded |
| `txtrdesc` | Texture list, same layout as in a `.CRZ`. All names are standard textures (`Rough01.tga`, `Fairw01.tga`, `Ocean02.tga`) found in `STDTER_1.LIB` | Decoded |
| `ttypetrans`, `textrans` | Lists of small increasing integers (one per terrain type, one per texture); probably maps to the matching tables of the `.CRX` | Not decoded |
| `vertex` (locked) | Terrain mesh, version 5 (below) | Decoded |
| `Water` | 16 to 56 bytes | Not decoded |
| `Mappings` | One `Default Planar` texture projection | Not decoded |
| `header` (locked) | Holes, version 14 (below) | Decoded |
| `Shapes` | Empty (16 zero bytes) | |
| `HoleIDShapes` | One outline per hole. Starts with a u32 count (18) | Not decoded: not the `.CRZ` outline layout |
| `OBIDShapes` | Out-of-bounds outlines. Starts with a u32 count | Not decoded |
| `copyright` (locked) | `Links 2001`, `1.0`, a date in 2001, and the course key at 0x2C | Same as `.CRZ` |

Coordinates are feet with z up, as in a `.CRZ`.

## `header`, version 14

| Type | Name | Notes |
|------|------|-------|
| u32 | version | 14 |
| char[9] | short_name | The old course's internal name cut to 8 characters, NUL-terminated: `Pebble_B`, `Kapalua_` |
| u32 | hole_count | 18 |
| hole[hole_count] | holes | 510 bytes each, the same layout as version 15 |
| 136 bytes | trailer | Not decoded |

Only the start differs from version 15, which has an i32 -1, the version and
10 zero bytes before the hole count. `parse_converted_holes` rewrites the
start and hands the rest to the version 15 parser. Converted courses use up
to 6 pin positions per hole where the Links 2003 courses use 18.

## `vertex`, version 5

The same as version 6 (see [crz.md](crz.md)) with two differences:

- A vertex is 16 bytes: `f32 x, y, z`, `u16` (unknown), `u16` flags. Version
  6 adds two floats after the position.
- When the mesh has more than 65,535 vertices, the three vertex indices of a
  triangle are u32, so a triangle record is 20 bytes instead of 14.
  CASTLEPI (65,873 vertices) is the only one of the 39 that needs this.

A triangle's `material` field is an index into `TerrainTypes`. The `mapping`
and unknown fields are always 0.

## `TerrainTypes`

A u32 count, then one 432-byte record per surface:

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | u32 | | A pointer value left in the file; ignore |
| 0x04 | i32[3] | textures | Indices into `txtrdesc`: the base texture, then up to two detail variants (`Rough01`, `Rough02`, `Rough03`); -1 = unused |
| 0x10 | f32[14] | physics | Bounce, roll and lie values, most between 0 and 5. Not decoded yet; useful for ball physics on these courses |
| 0x60 | | | Two small u32 values, then fill bytes |
| 0x6C | u8 | | Always 1 |
| 0x6D | u8[3] | map_colour | RGB for the overhead map: fairway `00 BF 00`, green `33 FF 33`, sand `99 99 33`, water `33 33 CC` |
| 0x70 | UTF-16[32] | name | `Rough`, `Fairway`, `Sand`, `Water`, `Tee Area`, `Pine Needles` |
| 0xB0 | UTF-16[32] x 3 | texture_names | The names of the three textures, repeating `txtrdesc` |
| 0x170 | UTF-16[32] | display_name | Usually the same as `name` (`Asphault` is shown as `Asphalt`) |

Unused bytes are filled with `0xCD`, and strings may have leftover characters
after their terminating NUL.

The loader turns each terrain type into one material whose textures are the
type's base texture and variants, so the viewer draws converted courses with
the same code as Links 2003 courses.

## Exporting

```bash
for f in CONVERT/*.CVT; do
  olcourse export --exe LINKSM_1.EXE --lib STDTER_1.LIB "$f" "courses/$(basename "$f" .CVT)"
done
```

The archives only carry the 8-character short name, so `olcourse` takes the
full course name from a table keyed by file name (`converted_course_title`).
The names come from the converter's read-me on CD2. Where several files share
a short name they were told apart by their holes: PINEHNEW plays to par 70
where PINEHUR2 plays to par 72, so it is probably the later No. 2, and
PINEHURS has exactly the holes of PINEHUR8 (No. 8).

## Open questions

- `SEA_ISLA.CVT` has a plain `ARC0` header but an encrypted directory, so the
  archive reader has to try the archive key on the directory even when the
  header is plain. Which Sea Island release it matches (SEAISLAN is the
  other) is a guess.
- The `TerrainTypes` physics values, `ttypetrans`, `textrans`, `Water`,
  `Mappings`, and the outline entries.
- Reading the objects and sky from a player's own `.CRX`, for players who
  still have their Links LS discs.
