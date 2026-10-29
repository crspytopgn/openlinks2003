# Carrera object store (`.SKL` models, `.CLP` animation clips)

Status: partial. The container (sections, allocation table, strings,
classes) is complete (`olcore::StoreFile`). Animation clips and the
skeleton (`Transform`/`Joint` hierarchy and rest pose) are complete
(`olcore::read_anim_clips`, `olcore::read_skeleton`) and checked by posing
Annika's driver swing: the feet stay on the ground for all 148 frames, the
hands are highest at the "top of backswing" frame and back at address height
on the "launch" frame named in `SCRIPT.TXT`. Meshes, shaders and skinning
are not decoded yet.
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

### `Carrera::AnimClip` (352 bytes)

The game's own debug print labels some of these fields (Start, Duration,
Num Samples, Num Connections, Num Dynamic).

| Offset | Type | Notes |
|--------|------|-------|
| 0x00 | u32 | Class identifier left by the exporter |
| 0x04 | u32 | 7 |
| 0x0c | u32 | Name hash of the clip (see "Name hash" below) |
| 0x10 | ptr | Clip name |
| 0x1c | f32 | Start (1.0) |
| 0x20 | f32 | Duration in frames (147.0 for a 148-frame clip) |
| 0x24, 0x28 | f32 | 1.0, 1.0 |
| 0x2c | u32 | Number of samples per channel, that is frames (148). Clips run at 30 frames per second. |
| 0x30 | u32 | Number of connections: channels (408 in `DRIVERSWING.CLP`: 68 nodes, six channels each) |
| 0x34 | u32 | Number of dynamic channels, the ones that change over time (74) |
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
| 0x00 | u32 | 1 for rotation channels, 0 for translation |
| 0x04 | u32 | Name hash of the target node (`Root`, `LeftKnee`) |
| 0x08 | u32 | Byte offset of the animated value inside the target `Transform`: 280, 284, 288 for translate x, y, z and 292, 296, 300 for rotate x, y, z |
| 0x0c | u32 | Attribute bit with the top bit set: `0x80000010`, `0x20`, `0x40` for rotate x, y, z and `0x80`, `0x100`, `0x200` for translate x, y, z |
| 0x10 | u32 | Name hash of node name and attribute name run together (`RootrotateX`) |

The dynamic channels come first in the table. The table after it (4 bytes
per channel) is a permutation of the channel indices whose use is unknown;
reading the clip doesn't need it.

### `clip samples`

Signed 16-bit values with 11 fractional bits: divide by 2048 to get feet
(translation) or radians (rotation). The first `channels` values are frame 0
of every channel, in channel order. Then come frames 1 to `frames - 1`, each
holding one value per dynamic channel. So the buffer holds
`channels + (frames - 1) * dynamic` values; that holds for all 337 clips of
Annika and Eric. Channels that aren't dynamic keep their frame 0 value
throughout.

### Name hash

Nodes and channels are matched by the standard CRC-32 (the zlib and PNG one,
check value `0xCBF43926` for "123456789") of the name's bytes:
CRC-32("Root") = `0xB6C65665`, CRC-32("DriverSwing") is the clip's hash.

### Swing timing (`swingmap` and `fullswing curve`)

`fullswing curve` is the binary form of the "Equidistant Frames" table in
`DRIVERSWING.TXT` (see [golfer-script.md](golfer-script.md)): one row per
resampled frame (2,106 rows for Annika's driver swing), each nine f32:
time, club head x, y, z, distance, speed, acceleration, transition time,
transition index. `swingmap` starts with a pointer to that table and the row
count, then a handful of frame indices and the total distance (2105.1),
and ends with a pointer back to the clip.

## Models (`.SKL`)

### Transforms and joints

`Carrera::Transform` (440 bytes) and `Carrera::Joint` (504 bytes, a
Transform plus a joint orient) form the hierarchy. A golfer has 68 joints
(`Root`, `LowerBack` ... `LeftPinkySecond`, `clubJoint`) under a transform
called `Player`, plus locator transforms.

| Offset | Type | Notes |
|--------|------|-------|
| 0x0c | u32 | Name hash |
| 0x10 | ptr | Name |
| 0x1c | ptr | Parent transform, 0 for the top |
| 0x20 | u32 | Number of children |
| 0x24 | ptr | Array of child pointers |
| 0x30 | f32[16] | Rest world matrix |
| 0x70 | f32[16] | Another 4x4 matrix (rotation part transposed); probably the inverse used for skinning |
| 0xb8 | f32[6] | Bounding box, min x/y/z then max x/y/z |
| 0xd8 | f32[16] | Rest local matrix |
| 0x118 | f32[3] | Translate (feet) |
| 0x124 | f32[3] | Rotate (radians) |
| 0x1b8 | f32[4] | Joint only: joint orient quaternion (x, y, z, w) |

Matrices are row-major for row vectors (`p' = p * M`), translation in the
last row. A node's local matrix is the rotation about X, then Y, then Z
(`rotate`), then the joint orient, then the translation; its world matrix is
local times the parent's world. This reproduces the stored local and world
matrices of all 68 joints in `ANNIKA_BOUND.SKL` to within 1e-6.

Units are feet with +y up. A posed clip puts the ball at the origin, the
golfer about 2.5 ft back along -x facing +x, and the target towards -z.
The club head is the locator `clubJoint|locator1` under `clubJoint`.

### Other classes

Classes in `ANNIKA_BOUND.SKL` (instance size in bytes): `Texture` 44,
`Transform` 440, `TransformEx` 504, `Mesh` 280, `Shader` 108, `Joint` 504,
`Locator` 212, `Light` 272, `SkinCluster` 220, `Shape` 52. The plain
buffers carry tags such as `Mesh Position Buffer`, `Mesh TexCoord Buffer`,
`Mesh Normal Buffer` and `SkinCluster Influence Pool`, and texture objects
point at file names like `L_A01_face.tga` (found in the same archive).

## Open questions

- `Mesh`, `Shape`, `Shader` and `SkinCluster` layouts: vertex format,
  index buffer, skin weights, texture binding.
- The channel permutation table, and the `AnimClip` fields not listed.
- Sections 2 and 3, and the padding rule between sections.
