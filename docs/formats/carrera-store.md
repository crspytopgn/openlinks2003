# Carrera object store (`.SKL` models, `.CLP` animation clips)

Status: partial. The container (sections, allocation table, strings,
classes) is complete and implemented by `olcore::StoreFile`. Inside it, the
animation clip header, channel table and swing curve are understood; the
encoding of the per-frame samples and the layout of the model classes
(`Transform`, `Joint`, `Mesh`, `SkinCluster`) are not yet.
Seen in: `POLYANI/*.L3` (golfers and clubs)

## Overview

The golfer models and clips were exported from Maya (`.ma`/`.mb`) by a
tool the leftover makefile calls `exportSkeletonSA.exe`. The output is a
snapshot of the exporter's in-memory object graph for an engine whose
classes live in a `Carrera` namespace: every heap allocation is written out
with a table saying where it sits in the file, which class it is, and what
it is called. Pointers inside objects are rewritten as file offsets.

A `.SKL` holds a whole character: transforms and joints (68 joints for a
golfer, named `Root`, `LowerBack` ... `LeftPinkySecond`, plus locators such
as `clubJoint` and `crownLocator`), meshes with position, texture
coordinate and normal buffers, shaders and texture references, a skin
cluster, and lights. A `.CLP` holds one or two `Carrera::AnimClip` objects
and their sample buffers.

## Layout

All numbers are little-endian. The file is seven **sections** followed by
the **heap** (the allocations' bytes).

### Section header (16 bytes)

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | u32 | magic | `0xDEADBEEF` |
| 0x04 | u32 | count | Number of elements |
| 0x08 | u32 | version | 0x100 mostly; 0x200 or other values on some tables |
| 0x0c | u32 | element_size | Bytes per element |

The body (`count * element_size` bytes) follows. After some sections (the
byte-sized ones and the string table) there are one to three bytes of
padding before the next magic, with no rule found yet; a reader should look
for the next `0xDEADBEEF` within three bytes.

### The seven sections, in order

| # | Element size | Holds |
|---|-------------:|-------|
| 0 | 4 | File header: 6 values (`0x00010001`, 16, 4, 16, heap start offset, -1) |
| 1 | 44 | Allocation table, one record per allocation (below) |
| 2 | 8 | Pairs of (count, first index); purpose unknown, their counts add up to the count of section 3 |
| 3 | 1 | Flag bytes; purpose unknown |
| 4 | 8 | String table: (length including NUL, offset into section 5) |
| 5 | 1 | String pool: NUL-terminated strings |
| 6 | 20 | Class table: (string index of the class name, instance size, 0, 0, leftover pointer) |

### Allocation record (44 bytes)

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | u32 | address | Address in the exporting process (meaningless now) |
| 0x04 | u32 | offset | Absolute file offset of the allocation's bytes |
| 0x08 | u32 | size | Bytes |
| 0x0c | i32 | class | Index into the class table, -1 for plain data |
| 0x10 | i32 | name | String index of the object's name, -1 if none |
| 0x14 | i32 | | 0 or 1 |
| 0x18 | i32 | | 1 |
| 0x1c | i32 | | 0 |
| 0x20 | i32 | | -1 or a small number, increasing through the file |
| 0x24 | i32 | tag | String index describing a plain buffer (`clip samples`, `Mesh Position Buffer`, `Store::strdup string`), -1 if none |
| 0x28 | i32 | alignment | 4, or 1 for strings |

Pointer fields inside an allocation hold the absolute file offset of the
target (inside another allocation) or 0.

Every store starts with two small named allocations: `Version` (a float,
3.8) and `CoordinateSystemType` (0).

## Animation clips (`.CLP`)

Classes: only `class Carrera::AnimClip` (352 bytes). Allocations in a swing
clip, for example `DRIVERSWING.CLP`:

| Name or tag | Size | Holds |
|-------------|-----:|-------|
| `DriverSwing` (AnimClip) | 352 | The clip |
| `GlobalTime` (AnimClip) | 352 | A second, empty clip, apparently a time base |
| `EntryPoints` | 4 | -1 |
| `swingmap` | 200 | Swing timing header (swing clips only) |
| `fullswing curve` | 36 per row | Swing timing table (swing clips only) |
| (untagged) | 20 per channel | Channel table |
| (untagged) | 4 per channel | Channel order (a permutation of 0..channels-1) |
| `clip samples` | varies | Animation data |
| `Store::strdup string` | | The clip names |

### `Carrera::AnimClip` (352 bytes, partial)

| Offset | Type | Notes |
|--------|------|-------|
| 0x00 | u32 | Class identifier left by the exporter |
| 0x04 | u32 | 7 |
| 0x0c | u32 | Looks like a hash of the clip name |
| 0x10 | ptr | Clip name |
| 0x1c | f32 | 1.0 |
| 0x20 | f32 | Last frame (147.0 for a 148-frame clip) |
| 0x24, 0x28 | f32 | 1.0, 1.0 |
| 0x2c | u32 | Frame count (148). Clips run at 30 frames per second. |
| 0x30 | u32 | Channel count (408 in `DRIVERSWING.CLP`) |
| 0x34 | u32 | 74 in the same clip; possibly the number of animated nodes |
| 0x38 | ptr | Channel table |
| 0x3c | ptr | `clip samples` |
| 0x44 | u32 | 1 |
| 0x48 | ptr | `swingmap`, or 0 |
| 0x4c | u32 | 2 |
| 0x54 | i32 | -2 |
| 0x5c | i32 | -1 |
| 0x158 | i32 | -1 |
| 0x15c | ptr | Channel order table |

### Channel record (20 bytes)

| Offset | Type | Notes |
|--------|------|-------|
| 0x00 | u32 | 0 or 1 |
| 0x04 | u32 | Hash of the target node's name; consecutive channels of one node share it |
| 0x08 | u32 | Byte offset of the animated value inside the target `Transform`: 280, 284, 288 for one vector (translation, most likely) and 292, 296, 300 for the next (rotation, most likely) |
| 0x0c | u32 | Bit mask with the top bit set: `0x80000010`, `0x80000020`, `0x80000040`, `0x80000080` ... one bit per animated value, in step with the offset |
| 0x10 | u32 | Varies per channel; probably where the channel's data starts in `clip samples` or how it is scaled |

### `clip samples`

Mostly small signed 16-bit numbers with runs of zeros, so the curves are
stored as quantized deltas or keys, not as plain floats. The decoding is the
next thing to work out.

### Swing timing (`swingmap` and `fullswing curve`)

`fullswing curve` is the binary form of the "Equidistant Frames" table in
`DRIVERSWING.TXT` (see [golfer-script.md](golfer-script.md)): one row per
resampled frame (2,106 rows for Annika's driver swing), each nine f32:
time, club head x, y, z, distance, speed, acceleration, transition time,
transition index. `swingmap` starts with a pointer to that table and the row
count, then a handful of frame indices and the total distance (2105.1),
and ends with a pointer back to the clip.

## Models (`.SKL`)

Classes in `ANNIKA_BOUND.SKL` (instance size in bytes): `Texture` 44,
`Transform` 440, `TransformEx` 504, `Mesh` 280, `Shader` 108, `Joint` 504,
`Locator` 212, `Light` 272, `SkinCluster` 220, `Shape` 52. The plain
buffers carry tags such as `Mesh Position Buffer`, `Mesh TexCoord Buffer`,
`Mesh Normal Buffer` and `SkinCluster Influence Pool`, and texture objects
point at file names like `L_A01_face.tga` (found in the same archive).

## Open questions

- The `clip samples` encoding and the meaning of the last channel field.
- The name hash function, needed to bind channels to joints by name.
- Field layouts of `Transform`/`Joint` (rest pose, parent links) and `Mesh`
  (vertex format, index buffer, skin weights).
- Sections 2 and 3, and the padding rule between sections.
