# Course shadow file (`.SHA`)

Status: partial (header and tree shadow shapes)
Seen in: `COURSES/` on CD2, one beside each `.CRZ` (`GEAGLES.SHA` and so on)

## Overview

Shading the game works out ahead of time for a course's objects: light
maps for the 3D objects, a shade value per billboard, and, for each
billboard type (trees, bushes), the shadow it casts on the ground seen from
above. The file names the course it belongs to and that course file's size,
so a stale `.SHA` can be spotted.

## Layout

All numbers are little-endian. Offsets in hex.

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | char[14] | magic | `VER5JDHSHADOW` and a NUL |
| 0x0E | char[256] | course | The course file, e.g. `geagles.CRZ`, NUL-padded |
| 0x10E | u32 | course_size | Size of that course file in bytes (matches all six CD2 courses) |
| 0x112 | u64 | time | A Windows FILETIME in 2002, probably when it was built |
| 0x11A | u32 | | Not decoded (about the same in every file) |
| 0x11E | u32 | model_count | Meshes in the course's `MasterObj3D` |
| 0x122 | u32 | billboard_type_count | Types in `MasterObj` |
| 0x126 | u32 | model_placement_count | Records in `3DPlant` |
| 0x12A | u32 | billboard_count | Placements in `2DPlant` |
| 0x12E | u32 | light_map_width | 256 so far |
| 0x132 | u32 | light_map_height | 256 so far |
| 0x136 | | light maps | `model_count` 8-bit maps of width x height (0xFE lit, darker in shade, 0 unused). They look like the 3D objects' surfaces unwrapped: castle walls with their windows, a gazebo's octagon |
| | | | Not decoded: in some files a run of zeros and then one u32 count per model placement followed by that many u32 (multiples of 8, perhaps triangle or offset lists); then floats between 0 and 1, mostly 1.0, about one per billboard (exactly `billboard_count` at Gleneagles, Skeleton Coast and Tribute, fewer elsewhere), which look like how much light each billboard gets |
| | | shapes | `billboard_type_count` records: `u32 width`, `u32 height`, then width x height bytes. 0 x 0 for types that cast none (grasses, flowers); otherwise square, 128 or 64 so far. 0 is no shadow, 255 full shadow. They are round crowns seen from above, not stretched along a sun, so the game presumably projects them itself |
| | | | Not decoded: about 2 to 4 MB more, starting with small counts |

The shapes' start isn't stored. The readers (olcore::parse_shadow_file and
the GDScript `ShadowFile`) take it to be the first run of
`billboard_type_count` well-formed shape records after the light maps,
backing up over 0 x 0 records that come before the first real shape. That
finds them in all six CD2 courses.

## In the game

GroundShade stamps each tree's and bush's own shape (in place of a soft
ellipse) into the baked ground shade, stretched away from the sun.

## Open questions

- The section between the light maps and the per-billboard values, and the
  rule for how many values there are.
- How the light maps are laid on the 3D objects (they don't share the
  objects' texture coordinates).
- How the game sizes and places a shape under a billboard.
- The tail after the shapes.
