# Course shadow file (`.SHA`)

Status: layout complete (every byte of the six CD2 files is accounted for);
the cell lists' meaning is only partly known
Seen in: `COURSES/` on CD2, one beside each `.CRZ` (`GEAGLES.SHA` and so on)

## Overview

Shading the game works out ahead of time for a course's objects. For each
3D object mesh and each billboard type (trees, bushes) the file holds its
shape seen from above, which the game uses for the shadow it casts on the
ground. For each billboard placement it holds how much light reaches that
billboard, which is lower for trees standing among other trees. The file
names the course it belongs to and that course file's size, so a stale
`.SHA` can be spotted.

## Layout

All numbers are little-endian. Offsets in hex. The file is read straight
through; nothing after the header has a fixed offset.

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | char[14] | magic | `VER5JDHSHADOW` and a NUL |
| 0x0E | char[256] | course | The course file, e.g. `geagles.CRZ`, NUL-padded |
| 0x10E | u32 | course_size | Size of that course file in bytes (matches all six CD2 courses) |
| 0x112 | u64 | time | A Windows FILETIME in 2002, probably when it was built |
| 0x11A | u32 | stamp | A Unix time, also in 2002 |
| 0x11E | u32 | model_count | Meshes in the course's `MasterObj3D` |
| 0x122 | u32 | billboard_type_count | Types in `MasterObj` |
| 0x126 | u32 | model_placement_count | Records in `3DPlant` |
| 0x12A | u32 | billboard_count | Placements in `2DPlant` |
| 0x12E | | object shapes | `model_count` shape records (below) |
| | | placement cells | `model_placement_count` cell lists (below) |
| | f32[billboard_count] | billboard light | Per `2DPlant` placement, in order |
| | | billboard shapes | `billboard_type_count` shape records |
| | | billboard cells | `billboard_count` cell lists |

The file ends right after the last cell list.

### Shape record

`u32 width`, `u32 height`, then `width x height` bytes, row by row. 0 x 0
for a mesh or type that casts nothing (grasses, flowers).

- **Billboard types**: square, 128 or 64 a side. 0 is no shadow, 255 full
  shadow. They are round crowns seen from above, not stretched along a sun,
  so the game projects them itself.
- **3D object meshes**: the mesh's footprint seen from straight above,
  covering the box of the mesh's own x and y (the game's models have z up),
  row 0 at the smallest y. Each byte is 0xFE where the object stands and 0
  elsewhere. Rasterising the meshes from above matches them closely (about
  97% overlap). Sizes vary with the object, up to 256.

### Cell lists

A run of `count` u32 list lengths, one per caster, followed by all the
lists, one after another. Each entry is a u32 byte offset into an 8-byte
entry table inside the game (so offset / 8 is an index into a table of 9128
entries, the same for every course), which belongs to the game's ray
tracing code. They are probably the cells of a spatial grid the caster
touches. They aren't needed to draw anything, so the readers skip them
unless asked.

### Billboard light

One float per billboard placement: 1.0 for a billboard in the open and
lower, down to nearly 0, the more it is surrounded by others. The values
follow the number of neighbouring billboards closely, so they are most
likely the share of the sky each billboard sees. Cabo San Lucas has one
NaN value; treat it as 1.

## In the game

- GroundShade stamps each tree's and bush's own shape (in place of a soft
  ellipse) into the baked ground shade, stretched away from the sun.
- 3D objects with a footprint stamp it (turned and scaled with the object)
  both as a shadow, shifted away from the sun by half the object's height,
  and as a soft darkening right underneath. Objects without one keep the
  box shadow.
- Billboards are darkened by their light value, from 1 in the open down to
  `CourseObjects.SHADE_FLOOR` (0.55) for none. The sprites are photographs
  lit already, so the floor is a guess at how far the game deepens them.

## Open questions

- What the 9128-entry table is, and so what the cell lists say exactly.
- How the game itself turns the light value into a sprite's brightness.
