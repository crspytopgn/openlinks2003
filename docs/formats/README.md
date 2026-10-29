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
- [btcv.md](btcv.md): `BTCV` textures and DXT5 block runs.
- [object-library.md](object-library.md): the Course Designer catalog
  (`OBJECT.LIB`), palette sets, billboards and the setup file-name table.
- [model.md](model.md): 3D objects (`.XYZ` meshes, `.CMF` textures).
- [ls-archive.md](ls-archive.md): `LSls` archives (`.LS`, `.L3`, `.TIP`) and
  their LZW compression. Complete.
- [ssf.md](ssf.md): `.SSF` sound banks. Partial (voice conditions open).
- [golfer-script.md](golfer-script.md): `SCRIPT.TXT` in golfer archives, the
  animation state script. Complete.
- [carrera-store.md](carrera-store.md): the object store behind `.SKL`
  models and `.CLP` clips. Container complete, contents partial.

Full file listings are in [../install-listing/](../install-listing/). To dig
into a file type, extract samples from your own discs with
`tools/cdimage/cdimage.py` and run `oldump --strings` against them.
`tools/lsarchive/lsarchive.py` (or `oldump ls` / `oldump ssf`) unpacks
archives and sound banks; `oldump store` lists what is in a `.SKL` or
`.CLP`.
