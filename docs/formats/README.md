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

None documented yet. Start by running `oldump --strings` against files from
your own install and noting what each file type appears to contain.
