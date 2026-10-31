# File format notes

One document per format, written in our own words (see
[../clean-room.md](../clean-room.md)). Suggested template:

```markdown
# <Format name> (`.ext`)

Status: unknown | partial | complete
Seen in: <folder in the original install>

## Overview
What the file holds and when the game loads it.

## Layout
| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00   | u32  | magic | ... |

## Open questions
```

## Formats

- [inventory.md](inventory.md): what is on each disc, how to read the disc
  images, and a first-pass survey of every file type and container.
- [arc0.md](arc0.md): `ARC0` compressed archives (`.LIB`, `.BTX`, `.TOP`,
  `.CMF`, `.sky`).
- [crz.md](crz.md): locked course archives (`.CRZ`, `.RNG`, `.CVT`): the
  encryption, terrain mesh, holes, textures and materials.
- [course-objects.md](course-objects.md): the objects placed on a course:
  billboards (`MasterObj`, `2DPlant`) and 3D objects (`MasterObj3D`,
  `3DPlant`, `.t3l`, `.maq`) and tournament spectators (`TrnyPlant`).
- [btcv.md](btcv.md): `BTCV` textures and DXT5 block runs.
- [sha.md](sha.md): course shadow files (`.SHA`): tree shadow shapes and
  what else is known.
- [panorama.md](panorama.md): course horizons and cloud skies (`Panorama`, `PANSKY.LIB`).
- [object-library.md](object-library.md): the Course Designer catalog
  (`OBJECT.LIB`), palette sets, billboards and the setup file-name table.
- [model.md](model.md): 3D objects (`.XYZ` meshes, `.CMF` textures).
- [ls-archive.md](ls-archive.md): `LSls` archives (`.LS`, `.L3`, `.TIP`) and
  their LZW compression. Complete.
- [d3f.md](d3f.md): the game's bitmap fonts (`.D3F`). Complete.
- [ssf.md](ssf.md): `.SSF` sound banks. Partial (voice conditions open).
- [physics.md](physics.md): the ball physics in the executable: units, the
  flight model and its coefficient tables, per-surface values, launch
  tables. Partial (flight complete).
- [golfer-script.md](golfer-script.md): `SCRIPT.TXT` in golfer archives, the
  animation state script. Complete.
- [carrera-store.md](carrera-store.md): the object store behind `.SKL`
  models and `.CLP` clips. Container, clips and skeleton complete; meshes open.
- [cvt.md](cvt.md): the 39 converted Links LS courses (`.CVT`): older hole
  and terrain versions and the terrain types.
- [green-reading.md](green-reading.md): the game's green-reading aids (grid,
  breakline indicator, putting assistant, Green Analyzer) by skill level, and
  its practice options, from the help text.

Full file listings are in [../install-listing/](../install-listing/). To dig
into a file type, extract samples from your own discs with
`tools/cdimage/cdimage.py` and run `oldump --strings` against them.
`tools/lsarchive/lsarchive.py` (or `oldump ls` / `oldump ssf`) unpacks
archives and sound banks; `oldump font` reads a `.D3F` font; `oldump store` lists what is in a `.SKL` or
`.CLP`.
