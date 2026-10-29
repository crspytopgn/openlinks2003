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
| `Panorama.prv`, `Panorama` | Panoramic sky (`pan` / `tpme` / `desu` tags) | Not decoded |
| `Flag.tga`, `Logo.tga`, `Tee0..4.tga` | Flag, course logo and tee marker textures | Standard TGA |
| `Splash0.jpg`, `Splash1.jpg`, `Holprv00..17.jpg` | Loading screens and the 298 x 500 hole preview cards | Standard JPEG |
| `*.wav` | Ambient sound loops (ADPCM WAV) | Standard |
| `TerrainTypes` | Surface types with physics values and a map colour: Rough, Sand, Water, Concrete, Asphalt, Deep Grass, Running Water, Tee Area and course-specific ones | Names found; record layout not decoded |
| `LieIcons` | 4 bytes | |
| `Materials` | Terrain materials (below) | Decoded |
| `txtrdesc` | Terrain texture list (below) | Decoded |
| `*.tga` (about 37) | The course's own terrain textures, 32-bit TGA, 256 or 512 square | Standard TGA |
| `ttypetrans`, `textrans` | Small index lists (77 and 82 entries); probably map materials to terrain types and textures | Not decoded |
| `vertex` (encrypted) | Terrain mesh (below) | Decoded |
| `Water` | 104 bytes | Not decoded |
| `RayEngine` | Spatial index over the terrain for ray casts: a header, a bounding box, one min corner and one max corner per node (129,123 nodes), then node lists | Partly understood |
| `Mappings` | Texture projections (`Default Planar` and others, with scale values) | Not decoded |
| `Shapes` | The course's area outlines as closed cubic Bezier splines (below) | Decoded, not yet used |
| `HoleIDShapes` | One outline per hole: the hole's boundary | Same format as `Shapes` |
| `BugIDShapes` | A few outlines | Same format as `Shapes` |
| `EnvSound` | Ambient sound emitters and their WAV names | Not decoded |
| `MasterObj`, `MasterObj3D` | The course's billboard types and 3D object meshes | Decoded ([course-objects.md](course-objects.md)) |
| `*.maq` (stored) | Paletted textures with mip levels for 3D objects | Decoded ([course-objects.md](course-objects.md)) |
| `texture3dobj.t3l`, `ObjectCull.dat` | 3D object textures and visibility | `.t3l` decoded ([course-objects.md](course-objects.md)); `ObjectCull.dat` not |
| `2DPlant` (magic `2JBO`), `3DPlant`, `TrnyPlant` | Object placements: billboards, 3D objects, tournament extras | `2DPlant` and `3DPlant` decoded, `TrnyPlant` surveyed ([course-objects.md](course-objects.md)) |
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

Triangle: `u16 material` (index into `Materials`), `u32` (probably a
`Mappings` record), `u16` (unknown, usually 0), then three vertex indices.
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

`u32 version` (4) and `u32 count`, then 64-byte records: `u32 0`, `u32 1`,
twelve `i32` texture indices (-1 = unused), a `u32` whose bits seem to mark
which slots are detail variants of the slot before (`Dry Grass 02.tga`,
`... 32.tga`, `... 128.tga`), and `u32 0`. A material whose first texture is
a mask (`Fairway To Rough Alpha.tga`, `Cabo Bunker Alpha 512.tga`) blends
the textures after it. This is how the edges between fairway and rough are
drawn.

### `Shapes`: area outlines

A u32 version (1) and three f32 (the same three values in every outline
entry; meaning unknown). `HoleIDShapes` and `BugIDShapes` put a u32 count and
another u32 before them. Then outlines run to the end of the entry:
`u32 id`, `u32 segments`, `u8 closed`, `f32 min[3]`, `f32 max[3]`,
`u32 attributes`, then `3 x segments` points of `f32 x, y, z` (two control
points and an end point per cubic segment, z = 0). The low bits of
`attributes` look like a surface type, and 0x800000 is a flag.

## Open questions

- `RayEngine`, `Mappings`, `TerrainTypes`, `ttypetrans`, `textrans` and
  `Water` layouts.
- What the per-vertex and per-triangle unknown fields mean (likely lighting
  or shadow data and texture mapping).
- The 136-byte trailer of `header` and the 6 flag bytes of each hole.
- `.CVT` files hold only 13 entries (terrain types, textures, a locked
  `vertex` and `header`). The converter combines them with an original Links
  LS `.CRX` course, which we don't have.
- `.SHA` shadow files.
