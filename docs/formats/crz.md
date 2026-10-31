# Course archive (`.CRZ`, also `.RNG` and `.CVT`)

Status: partial. The container, encryption, terrain mesh, holes, course text,
texture list and material table are decoded. Everything else is named and
listed, but its layout is still unknown.
Seen in: CD2 `GAME/COURSES/*.CRZ` (six courses), CD1 `GAME/COURSES/DRIVING.RNG`,
CD2 `CONVERT/*.CVT`

## Overview

A course is an [ARC0 archive](arc0.md) that has been locked. The 16-byte
header and the directory are encrypted, and so are a few entries, including
the terrain mesh. Once decrypted it is an ordinary ARC0: zlib streams back to
back from offset 0x10, then a directory of 64-byte records at the end. The
directory gives every entry a name, so nothing has to be guessed from the
order of the streams.

All six CD2 courses and the driving range open with the same keys.
`olcore::CrzArchive` reads them and `tools/olcourse` lists, extracts and
exports them.

## Encryption

### The cipher

The game has its own 64-bit block cipher. Its exported helper functions are
named `Bunky*`, so the code calls it Bunky. It has two constant tables:

- **P**: 32 words. Words 5 to 7 are the hexadecimal digits of pi, the same
  values that appear in Blowfish's P-array. The other words differ.
- **S**: 1,022 words, stored directly after P.

Neither table is copied into this repository. `olcore::find_bunky_tables`
finds them in the player's own executable by searching for the three pi
words.

**Key setup** (key of 1 to 7 bytes; longer keys are cut to 7. Rounds are
clamped to 4..32):

1. Start from copies of P and S.
2. For each word `P[i]` (i = 0..31), XOR in the 32-bit big-endian value made
   of key bytes `4i, 4i+1, 4i+2, 4i+3`, each taken modulo the key length.
3. Encrypt the P table in place, then the S table, with the cipher itself in
   chained mode (below, without the tail step). Each block is encrypted where
   it sits, so later lookups in the same pass already see the updated words.

**One block** is 8 bytes, read as four little-endian 16-bit halves h0..h3.
Four overlapping 32-bit views are used: *front* = bytes 0-3, *back* = bytes
4-7, *middle* = bytes 2-5, and *outer* = h0 as the high half with h3 as the
low half. `S(x)` means `S[x mod 1022]`. Additions wrap at 32 bits.

Encryption runs rounds r = 0..R-1, each with four steps:

1. front ^= S(back + r) ^ P[r]
2. outer ^= S(middle + r) ^ P[(r + 8) mod 32]
3. middle ^= S(outer + r) ^ P[(r + 16) mod 32]
4. back ^= S(front + r) ^ P[(r + 24) mod 32]

Decryption runs the rounds from R-1 down to 0, doing steps 4, 3, 2, 1.

**Buffers** use propagating CBC with no IV: before a block is encrypted it is
XORed with both the previous plaintext block and the previous ciphertext
block. That XOR is skipped for the first block. To cover a length that is not
a multiple of 8, encryption first encrypts the last 8 bytes on their own, then
runs the chain over the whole blocks. Decryption runs the chain first, then
decrypts the last 8 bytes. Buffers shorter than 8 bytes use a byte mode
instead. A single byte is XORed with the low bytes of `S[0]` and `P[0]`.
Longer buffers get 32 passes k = 0..31; in each pass every byte j becomes
`low byte of S[b[(j+1) mod n] + j] ^ b[j] ^ low byte of P[k]`. Encryption goes
forwards through the passes and bytes, decryption goes backwards.

### Keys

| What | Key | Key length used | Rounds |
|------|-----|-----------------|--------|
| Header (16 bytes) and directory | Archive key: a fixed 8-byte value built into the executable | 7 | 32 |
| `copyright` entry | Archive key | 7 | 4 |
| Other locked entries (`header`, `vertex`) | Course key: 8 bytes at offset 0x2C of the decrypted `copyright` entry | 7 | 4 |

The archive key is not in this repository either. The game passes it to its
archive reader as two 32-bit immediates, pushed high word first.
`olcore::find_game_keys` tries every such pair of pushes in the executable
and keeps the one that turns a course's first 16 bytes into a valid ARC0
header. This works with `LINKSM_1.EXE` from CD1. It should also work with the
installed or patched `LinksMMIII.exe`, but that is untested.

A locked entry is decrypted first and then inflated.

## Layout

### Header (16 bytes, encrypted)

Same as ARC0: `ARC0`, the file size, the entry count and the directory
offset. GEAGLES.CRZ has 1,013 entries.

### Directory record (64 bytes, encrypted)

Some converted `.CVT` courses (Sea Island, for one) have a plain `ARC0`
header but an encrypted directory. A reader tries the directory as plain
text first, and decrypts it with the archive key if the first record does
not parse. The key search then tests the first directory record instead of
the header.


The same as ARC0, plus a flags word:

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | u32 | reserved | 0 |
| 0x04 | char[32] | name | |
| 0x24 | u32 | offset | |
| 0x28 | u32 | packed_size | |
| 0x2C | u32 | size | |
| 0x30 | u32 | method | 2 = zlib, 0 = stored (the `*.maq` entries) |
| 0x34 | u32 | checksum | Adler-32 of the unpacked data, 0 for stored entries |
| 0x38 | u32 | flags | Bit 0: entry is encrypted |
| 0x3C | u32 | reserved | 0 |

## Entries

Names from GEAGLES.CRZ. Other courses have the same named entries, with
different textures and sounds.

| Entry | What it holds | Status |
|-------|---------------|--------|
| `newformat` | Text `V.2.0` | |
| `*.btc` (about 860) | `BTCV` billboard sprites for the course's objects, five sizes each | [btcv.md](btcv.md) |
| `Panorama.prv`, `Panorama` | The course's horizon panorama and a TGA preview of it | Decoded ([panorama.md](panorama.md)) |
| `Flag.tga`, `Logo.tga`, `Tee0..4.tga` | Flag, course logo and tee marker textures | Standard TGA |
| `Splash0.jpg`, `Splash1.jpg`, `Holprv00..17.jpg` | Loading screens and the 298 x 500 hole preview cards | Standard JPEG |
| `*.wav` | Ambient sounds (MS ADPCM WAV, 44.1 kHz stereo) | Standard |
| `TerrainTypes` | Surface types with physics values and a map colour: Rough, Sand, Water, Concrete, Asphalt, Deep Grass, Running Water, Tee Area and course-specific ones | Decoded, below |
| `LieIcons` | 4 bytes | |
| `Materials` | Terrain materials and their texture layers (below) | Decoded |
| `txtrdesc` | Terrain texture list (below) | Decoded |
| `*.tga` (about 37) | The course's own terrain textures, 32-bit TGA, 256 or 512 square | Standard TGA |
| `ttypetrans`, `textrans` | Small index lists (77 and 82 entries); probably map materials to terrain types and textures | Not decoded |
| `vertex` (encrypted) | Terrain mesh (below) | Decoded |
| `Water` | 104 bytes | Not decoded |
| `RayEngine` | Spatial index over the terrain for ray casts: a header, a bounding box, one min corner and one max corner per node (129,123 nodes), then node lists | Partly understood |
| `Mappings` | Texture projections: planar, cylindrical, per-corner strips (cart paths, blended edges) and blends | Decoded (below) |
| `Shapes` | The course's area outlines as closed cubic Bezier splines (below) | Decoded |
| `HoleIDShapes` | One outline per hole: the hole's boundary, which sets out of bounds | Decoded, used |
| `OBIDShapes` | Out-of-bounds areas (some courses) | Decoded, used |
| `BugIDShapes` | A few outlines | Same format as `Shapes` |
| `EnvSound` | Ambient sound kinds, their WAV names, and emitters placed round the course | Decoded (below) |
| `MasterObj`, `MasterObj3D` | The course's billboard types and 3D object meshes | Decoded ([course-objects.md](course-objects.md)) |
| `*.maq` (stored) | Paletted textures with mip levels for 3D objects | Decoded ([course-objects.md](course-objects.md)) |
| `texture3dobj.t3l`, `ObjectCull.dat` | 3D object textures and visibility | `.t3l` decoded ([course-objects.md](course-objects.md)); `ObjectCull.dat` not |
| `2DPlant` (magic `2JBO`), `3DPlant`, `TrnyPlant` | Object placements: billboards, 3D objects, tournament extras | Decoded ([course-objects.md](course-objects.md)) |
| `english.txt` | UTF-16 text: `CourseName = ...`, `HoleName1 = ...` | Decoded |
| `MergeInfo.DAT` | Text: designer build note | |
| `header` (encrypted) | The holes (below) | Decoded |
| `copyright` (encrypted) | `Links 2003`, version `1.0`, a date, and the course key at 0x2C | |

Coordinates everywhere are **feet**, with **z up**. The yardages in `header`
match the tee-to-green distances measured along the aim path. The viewer
converts positions to Godot metres as (x, z, -y) x 0.3048. That mapping keeps
the layout unmirrored: bunkers come out on the same side as on the hole
preview cards.

### `vertex`: terrain mesh

| Type | Name | Notes |
|------|------|-------|
| u32 | version | 6 |
| u32 | vertex_count | 64,585 at Gleneagles |
| vertex[vertex_count] | vertices | 24 bytes each, below |
| u32 | triangle_count | 129,123 at Gleneagles |
| u32[3][triangle_count] | neighbours | Across each edge. The low 20 bits are the triangle index; bits 26-27 give the neighbour's edge; bit 30 set means a border edge (index 0xFFFFF) |
| triangle[triangle_count] | triangles | 14 bytes each, or 20 with wide indices (below) |

Vertex: `f32 x, y, z`, two f32 that are almost always 0, `u16` (unknown),
`u16` flags (unknown).

Triangle: `u16 material` (index into `Materials`), `u16 mapping` (index
into `Mappings`), `u16` and `u16` (unknown, mostly 0; a few triangles hold
leftover values here), then three vertex indices.
The indices are `u16` when the course has at most 65,535 vertices and `u32`
when it has more. The six CD2 courses use between 31,769 and 68,497
vertices, and four of them (Cabo, Cambrian, Kauri, Tribute) need the wide
form. The entry ends right after the last triangle, which confirms the size.

### `header`: holes

| Type | Name | Notes |
|------|------|-------|
| i32 | marker | -1 |
| u32 | version | 15 |
| 10 bytes | | zero |
| u32 | hole_count | 18 |
| hole[hole_count] | holes | 510 bytes each, below |
| 136 bytes | trailer | Not decoded |

Hole:

| Type | Name | Notes |
|------|------|-------|
| u32 | par | |
| u32 | handicap | Stroke index |
| u32 | ladies_par | Probably |
| u32 | ladies_handicap | Probably |
| tee[5] | tees | `f32 x, y, z`, `f32 heading` (radians), `u32 yards`, `u32 mask` (1, 2, 4, 8, 16 = back to forward); mask 0 means unused |
| pin[18] | pins | `f32 x, y, z`, `u32 group`: three sets of six positions (groups 0, 1, 2) |
| u32 | pin_count | 18 |
| u32 | aim_count | 5 |
| f32[5][3] | aim_path | Tee, layup points, then green; unused slots are zero |
| f32[3] | green | Centre of the green |
| 6 bytes | flags | Differ by par; not decoded |

### `txtrdesc`: texture list

A u32 count, then 64-byte records: `char name[32]`, `u32 width`,
`u32 height`, and 24 bytes the game fills in at run time. A name refers to an
entry in the course (`GE Green 1A 512.tga`) or, for the standard textures
(`Rough01.tga`, `Sand01.tga`), to an entry in `STDTER_1.LIB` on CD1.
Standard textures are 8-bit colour-mapped TGAs.

### `Materials`

`u32 version` (4) and `u32 count`, then 64-byte records: `u32 mode` (0
plain, 3 blended), `u32 layers` (1 plain, 3 blended), twelve `i32` texture
indices (-1 = unused), `u32 details` and `u32 0`.

The texture slots hold the layers in order. Each layer is a base texture
followed by its detail variants (`Dry Grass 02.tga`, `... 32.tga`,
`... 128.tga`): bits `2k` and `2k + 1` of `details` are set for each
variant that follows layer `k`'s base texture. The game presumably draws
the variants at other scales; they are skipped for now.

A plain material has one layer. A blended material has three: a mask
(`Fairway To Rough Alpha.tga`, `Cabo Bunker Alpha 512.tga`), then two
ground textures. Black in the mask is the first texture and white the
second. This is how the edges between fairway and rough, round bunkers and
round tees are drawn: the strip of triangles along an edge uses a blended
material, and the mask (128 x 256, a ragged grass edge running down the
middle) is laid across the strip by a `Mappings` strip (below). At
Gleneagles 40 of the 77 materials are blended.

### `Mappings`: texture projections

A u32 version (5), a u32 record count, then 40 bytes not decoded (a second
count and small numbers), so the records start at offset 48. Triangles
refer to a record by its position in the list.

Each record: `u32 kind`, `u32 id` (0x8000 plus a number, not always the
position), `u32 name_length`, the name (`Default Planar`, `Hole 2 FW
planar`, `hole18 tee1 path`, `hole18 tee1 mult`), then by kind:

| Kind | Name | Then |
|------|------|------|
| 0 | Planar | `f32 scale_u, scale_v`, then 16 f32: four rows of four, the u, v and w axes (feet per texture repeat) and the origin. A course point is origin + u * row0 + v * row1 + w * row2, and (u, v) times the scales are the texture coordinates. `Default Planar` is 12 feet a repeat; the per-hole fairway planars are rotated to line up with the hole; walls and bridges use upright frames |
| 1 | Cylindrical | The same fields. The texture wraps round the w axis: u from the angle round it (a full turn is `scale_u` repeats), v from the height along it. Rock walls and pools |
| 3 | Strip | `f32 scale_u, scale_v` (1 and 12, or 8 or 10), `u32 triangle_count`, then per triangle `u32` (its index in an older build of the mesh), `u32 triangle` (index into `vertex`) and three `u32` corner indices; then `u32 corner_count` and per corner `u32` (old vertex index), `u32 vertex`, `f32 u`, `f32 v`. u runs across the strip from 0 to 1, v along it in texture repeats |
| 4 | Blend | Five `u32`: the strip that lays the mask, the mapping of the first layer, the mapping of the second (planar so far), then two zeros |

Plain cart paths use strips directly, so their texture runs along the path.
A blended triangle's mapping is a blend record; corner u is 0 on the side of
the blend's first texture and 1 on the side of its second. A few strip
entries are stale (their triangle has since changed); the triangle's own
mapping index is the one to trust.

olcore::parse_mappings() and its GDScript port
`TerrainMappings` read this; CrzTerrain lays each triangle's textures by
its mapping and blends the edges.

### `Shapes`: area outlines

A u32 version (1) and three f32 (the same three values in every outline
entry; meaning unknown). `HoleIDShapes`, `OBIDShapes` and `BugIDShapes` put a
u32 count before the version. Then outlines run to the end of the entry:
`u32 id`, `u32 nodes`, `u8 closed`, `f32 min[3]`, `f32 max[3]` (a box round
every point, handles included), `u32 attributes`, then per node three points
of `f32 x, y, z`: the handle coming in, the node itself and the handle going
out. Consecutive nodes make a cubic Bezier segment (node, its out handle, the
next node's in handle, the next node); a closed outline also joins the last
node to the first. The z values are heights and play no part in the tests
below.

The game tests a point against an outline in two dimensions. It first turns
the curve into a polygon: starting from the last node of a closed outline
(the first of an open one), it emits each node and then cuts the segment to
the next node in half three times (de Casteljau), emitting the seven
in-between points in order, and ends with the final node again. An outline
with more than 624 nodes is cut fewer times so the polygon stays under 5,000
points. A point is inside when a ray towards +x crosses the polygon an odd
number of times (edges count when one end is at or above the point's y and
the other below it). Ported as `olcore::shape_outline` and
`outline_contains` (`CourseAreas` in the game).

- `HoleIDShapes`: one outline per hole, the hole's boundary. The hole number
  is `attributes >> 27`. A ball that stops outside its hole's outline is out
  of bounds.
- `OBIDShapes` (only on some courses, such as Cabo and Cambrian): areas that
  are out of bounds. Bits 0 to 17 of `attributes` say which holes (bit 0 for
  the first); every area on the disc courses applies to all 18.
- `BugIDShapes`: not used here.
- `Shapes`: the designer's area outlines. The low bits of `attributes` look
  like a terrain type and 0x800000 is a flag; the game does not read them
  during play.

On all six disc courses every tee and pin lies inside its own hole's outline
and outside the next hole's.

### `TerrainTypes`: ground classes

A u32 version (4 in `.CRZ`; `.CVT` files use 13, not decoded) and a u32
count, which equals the number of `Materials`. Then one 243-byte record per
material, in the same order. Records are not aligned: they hold a run of
f32 physics values, UTF-16 display and type names (for example "GE_Fairway"
and "Fairway") and unused bytes filled with 0xCD.

The byte at offset 0x54 of a record is its ground class, which says how the
ball plays off it:

| Class | Ground |
|-------|--------|
| 1 | Green |
| 2 | Fairway, fringe, tee area |
| 3 | Rough |
| 4 | Sand |
| 5 | Water, ocean, running water |
| 6 | Cart path, concrete, asphalt |
| 7 | Dirt |
| 8 | Bushes |
| 9 | Rocks, lava |
| 10 | Deep grass, dry grass, tall grass |
| 0 | A few records with no type name |

These were matched against the type names in all six CD2 courses.

The whole record, as the game reads it:

| Offset | Type | Field |
|--------|------|-------|
| 0x00 | u32 | index |
| 0x04 | f32[20] | values: the 14 named in [physics.md](physics.md#per-surface-values-terraintypes), then six the game never reads |
| 0x54 | u32 | ground class (above) |
| 0x58 | u32 | terrain category, as scripts see it (`Course_GetTerrainFromPos`) |
| 0x5C | u32 | flags; the game reads bit 0 (hazard: "In Hazard", no drops) and bit 3 (free drop: "In Free Drop Zone"). The upper bytes often hold leftover memory |
| 0x60 | u8[3] | map colour |
| 0x63 | u8[3] | |
| 0x66 | u8 | |
| 0x67 | char16[32] | display name ("GE_Fairway") |
| 0xA7 | char16[32] | type name ("Fairway") |
| 0xE7 | u32[3] | a zero, then for blended edges the two records being blended (by index) |

Water and running water are flagged as hazards, and so are a few others
(Auburn mud, Aviara dry red grass). Concrete, asphalt, cart paths and wood
walls are flagged as free drops. `olcore::parse_crz_terrain_types` reads the
records (`CourseAreas.parse_terrain_types` in the game), and a course's own
values now drive the bounce and roll instead of the class defaults.

### `EnvSound`: ambient sounds

A u32 count of sound kinds. Each kind: a u32 length and that many bytes of
NUL-terminated name (`GE Amb01`), a u32 (the kind's own index), a u32 file
count, then for each file a u32 length and a NUL-terminated WAV name, an
entry in the same course.

Then a u32 emitter count and 36 bytes per emitter: `u32 kind`, `f32 x, y, z`
(feet), an f32 that is 29997 for the long ambient loops and 29994 for the
short one-off sounds (so it seems to mark looping), `f32 radius` (75 or 90
feet), `f32 volume` (0.2 or 0.3) and two f32 zeros. Gleneagles has 27 kinds
(14 ambient loops, 11 short sounds, a distant train and gunshots) and 48
emitters, two or three round each hole. Four bytes follow the last emitter.

`CourseAmbience` (`game/scripts/audio/course_ambience.gd`) plays the
nearest loop for each hole.

## Open questions

- `RayEngine`, `ttypetrans`, `textrans` and `Water` layouts, the 40 bytes
  after the `Mappings` count, and how the game uses the detail variants.
- What the per-vertex and per-triangle unknown fields mean (likely lighting
  or shadow data and texture mapping).
- The 136-byte trailer of `header` and the 6 flag bytes of each hole.
- `.CVT` files hold only 13 entries (terrain types, textures, a locked
  `vertex` and `header`). The converter combines them with an original Links
  LS `.CRX` course, which we don't have.
- The rest of the `.SHA` shadow files ([sha.md](sha.md)).
