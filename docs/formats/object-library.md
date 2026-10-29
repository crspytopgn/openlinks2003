# Course Designer object library (`OBJECT.LIB`, `.PST`, `.BTX`, `.TOP`)

Status: partial. The catalog and palette sets parse completely; the meaning
of some numeric fields is still a guess, and `MasterObj` is only sketched.
Seen in: CD3 `GAME/` (installed as the Course Designer's `Object` folder)

## Overview

The Arnold Palmer Course Designer ships 1,015 placeable objects in 27
categories: 968 billboards (trees, bushes, rocks, flowers, benches and so
on) and 47 textured 3D models (buildings, bridges, fences, tournament
structures). `OBJECT.LIB` is the catalog. Each billboard is a `.BTX`
archive with its pictures, and many have a `.TOP` top view for the course
map. 3D models are described in [model.md](model.md).

Every object has a 32-bit id (`0x8424....` on CD3). Palette sets (`.PST`)
refer to objects by id, and course files are expected to do the same when
they place objects.

All values are little-endian. A *counted string* is a u32 length that
includes the terminating NUL, then the bytes; length 0 means an empty
string with no bytes.

## `OBJECT.LIB`

| Type | Name | Notes |
|------|------|-------|
| u32 | counter | 2,227 on CD3. Larger than the number of objects; probably the next free id or record number |
| u32 | category_count | 27 |
| category[] | categories | |

### Category

| Type | Name | Notes |
|------|------|-------|
| counted string | name | `Bushes`, `Tall Trees`, `3D2K3Bridges`... `Default` and `Fountains` are empty |
| u32 | object_count | |
| object[] | objects | |

### Object

| Type | Name | Notes |
|------|------|-------|
| counted string | file | `Tall Trees100.btx`, `3D2K3Walls000.XYZ` |
| counted string | path | Relative to the `Object` folder, `\` separated: `Tall Trees\Tall Trees100.btx` |
| u32 | kind | 1 = billboard (`.btx`), 2 = 3D model (`.XYZ`) |
| f32[4] | params | Always 25 in the first; the next two look like a minimum and maximum size in feet for the object's size slider (`Tall Trees` 5 to 100, `Flowers` 1 to 7, `Rocks` 1 to 6); the fourth is 0. Unconfirmed |
| f32[3] | size | Billboards: height and width in pixels of the largest picture, then 0. Models: height, width (x) and depth (z) of the mesh's bounding box in inches |
| f32[2] | extra | Always 0.5 and 0 |
| u32 | id | Unique object id |
| counted string | top_view | `TopViews\maple18.top`, or empty |
| u32 | collision | 0 for trees and large plants, 1 for solid objects (rocks, benches, cacti), 2 for things a ball passes through (flowers, grasses, some bushes). A guess from which categories use which value |
| f32[6] | shape | With collision 0, the numbers vary per tree and look like fractions of the picture: canopy bottom and top heights, then a trunk rectangle. Otherwise usually `1 1 0 0 1 1` with the first value lowered for some categories. Unconfirmed |

A billboard's world size is not in the catalog. Courses presumably store a
size or scale per placed object; until the course format is decoded, the
viewer uses the height from `params` (the midpoint of the size range).

## Palette sets (`.PST`)

`DEFAULT.PST` and `SET1.PST` to `SET6.PST` are the Course Designer's object
palettes.

| Type | Name | Notes |
|------|------|-------|
| u32 | group_count | |
| group[] | groups | |

Each group is a u32 name length, the name with **no** terminating NUL
(`Bushes`), a u32 id count, and that many u32 object ids. Every id in the
seven files on CD3 is in `OBJECT.LIB`.

## Billboard archive (`.BTX`)

An [ARC0](arc0.md) archive with six entries:

| Entry | Holds |
|-------|-------|
| `<file>A.btc` to `<file>E.btc` | The picture at five sizes as [BTCV](btcv.md) textures, largest first. Each is about half the size of the one before |
| `MasterObj` | How to draw the object, see below |

The entries are named after the long file name (`Tall Trees100A.btc`),
which is how the files on the discs can be matched to the catalog without
the installer.

### `MasterObj`

A memory image of the game's object description: a u32 total size, then
structures that point at each other with offsets from the start of the
entry. What is clear so far:

- For each picture size it lists the BTCV tiles by id and a set of polygons
  (usually quads) that cover only the non-empty tiles, so the billboard
  draws little transparent area.
- Vertices are 32 bytes: x, y, z, w as f32 (x from -0.5 to 0.5, y always 0,
  z from 0 to 1, w = 1), a u32 colour (always `ffffffff`), a u32 0, then u
  and v as f32. In other words a unit-width, unit-height quad standing on
  the ground, scaled at draw time.
- Near the end it repeats the largest picture's size (467, 550) and stores
  width / height as an f32 (0.849).

A plain quad with the largest picture, width = height x (picture width /
picture height), standing on its bottom edge, looks the same, so the viewer
does that and does not need `MasterObj`.

### Top views (`.TOP`)

The same layout as `.BTX`: one to three BTCV sizes of the object seen from
above, then a `MasterObj`.

## File names on the discs

The discs store 8.3 names only (`TA406A_1.BTX` for `Tall Trees100.btx`).
Setup restores the long names from a table inside each disc's `SETUP.EXE`.
Records in that table look like this:

| Type | Name | Notes |
|------|------|-------|
| u32 | marker | `0x50` |
| u16 | length | Length of the short path, plus one |
| char[] | short | NUL-terminated path on the disc: `game\OBJECT\TALLTR_1\TA406A_1.BTX` |
| char[] | long | NUL-terminated path in the install folder: `Object\Tall Trees\Tall Trees100.btx` |

Other fields follow (flags, sizes, timestamps) that are not needed.
`tools/cdimage/cdimage.py install` uses the table to extract a disc into an
install-like folder with the long names.

## Open questions

- The exact meaning of `params`, `extra`, `collision` and `shape`. The
  course format and the Designer's object dialog should settle them.
- The first u32 of `OBJECT.LIB`.
- `MasterObj` in full, if it turns out to matter for lighting or wind.
