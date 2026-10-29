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

Full file listings are in [../install-listing/](../install-listing/). To dig
into a file type, extract samples from your own discs with
`tools/cdimage/cdimage.py` and run `oldump --strings` against them.
