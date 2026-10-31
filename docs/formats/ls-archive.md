# `LSls` indexed archive (`.LS`, `.L3`, `.TIP`)

Status: complete for reading (every entry of `SOUNDS.LS`, `GRAPHICS.LS`,
`SETUP.LS`, `CLUBS.L3`, `ANNIKA_1.L3` and `ERIC.L3` extracts to its stated
size)
Seen in: `GAME/*.LS`, `GAME/POLYANI/*.L3`, `GAME/MOPS.L3`, `COURSES/*.TIP`

## Overview

A flat archive of named files with an index up front. Most entries are
compressed with a variable-width LZW coder; some (already compressed WAVs,
small TGAs) are stored as is. The developers' makefile left in the golfer
archives calls the packing tool `ac2003`.

Implemented by `olcore::LsArchive` (`libs/olcore/include/olcore/ls_archive.hpp`)
and `olcore::lzw_decompress`.

## Layout

All numbers are little-endian. The file starts with a 0x37-byte (55-byte)
**block header**, followed by the index, followed by the entries. Every
entry starts with a block header of the same shape, so the same struct
describes both the archive and each file in it.

### Block header (0x37 bytes)

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | char[4] | tag | `LSls` on the archive header and on most entries. Entries in older archives (`SOUNDS.LS`) carry zeros or leftover bytes here; don't rely on it. |
| 0x04 | u16 | version | `0x020b` for `.LS` (8.3 names), `0x020c` for `.L3` (long names). Only meaningful on the archive header. |
| 0x06 | u16 | header_size | 0x37 on tagged headers. Untagged entries (the fonts and `.SHR` sprites in `GRAPHICS.LS`, most of `SOUNDS.LS`) hold zero or leftover bytes here, so readers ignore it: the data always starts 0x37 bytes after the header. |
| 0x08 | u16 | | 0 |
| 0x0a | u32 | count / id | Archive header: number of files in the index. Entry headers: a running number with no use to a reader. |
| 0x0e | 8 bytes | | 0 |
| 0x16 | u16 | capacity | Archive header: index slots allocated (count + 64 spare). |
| 0x18 | u8 | compressed | 1 = data is LZW-compressed, 0 = stored. |
| 0x19 | u32 | original_size | Entry: size after decompression. Archive header: bytes of unused index slots. |
| 0x1d | u32 | stored_size | Entry: bytes of data that follow the header. Archive header: size of the whole index (`capacity * slot_size`). |
| 0x21 | u16 | | 0 |
| 0x23 | u32 | timestamp | DOS date and time (time in the low word, date in the high word). |
| 0x27 | u16 | | 0 |
| 0x29 | u8 | name_length | Length of the name, which may be longer than the field below. |
| 0x2a | char[13] | name | Name, padded with spaces or NULs, truncated to 12 characters plus NUL. Use the index for the full name. |

For stored entries `original_size == stored_size`.

### Index

Starts at 0x37, right after the archive header, and holds `capacity`
slots. Only the first `count` slots are used; the rest are zero.

| Version | Slot size | Name field | Then |
|---------|-----------|------------|------|
| `0x020b` (`.LS`) | 17 bytes | 13 bytes, NUL-terminated (junk may follow the NUL) | u32 absolute file offset of the entry's block header |
| `0x020c` (`.L3`) | 68 bytes | 64 bytes, NUL-terminated | u32 absolute file offset of the entry's block header |

Names are upper case. The game looks them up case-insensitively, and `.L3`
references in scripts use the form `clubs.l3|driver.skl`.

The data of an entry is the `stored_size` bytes at `offset + 0x37`.

## Compression

Variable-width LZW, as in GIF or Unix `compress` with a clear code:

- Codes are packed least-significant bit first into the byte stream.
- Code 256 is **clear** (reset the dictionary and the width), code 257 is
  **end of data**. New dictionary entries start at 258.
- Codes start 9 bits wide. After adding an entry, if the next free code has
  reached `1 << width` and the width is below 13, the width grows by one.
  So codes are 9 bits until entry 511 is added, and at most 13 bits.
- The dictionary holds at most 8192 codes. When it is full, no more entries
  are added until the next clear code.
- The first code after a clear is a literal byte and adds no entry. For each
  later code the decoder adds `previous string + first byte of the current
  string`, including the usual case where the code is the one about to be
  added (`previous string + its own first byte`).
- Every stream seen so far starts with a clear code.

Decoding stops at the end code, at the end of the input, or once
`original_size` bytes are out.

The game's reader can also XOR every input byte with 5 before decoding.
In the file it's keyed to the byte at header offset 0x36 (the last byte of
the name field), which is NUL in every archive seen, so no shipped data uses
it. `lzw_decompress` takes it as an option anyway.

## What the archives hold

| Archive | Entries | Contents |
|---------|--------:|----------|
| `SOUNDS.LS` | 55 | Swing whiffs, ball and UI clicks, menu music, crowd walla (WAV; only `WALLA.WAV` is compressed) |
| `GRAPHICS.LS` | 275 | HUD TGAs, the game's fonts ([d3f.md](d3f.md)) and `.SHR` sprites (tag `SHR1`); `CLUBDIST` is a small binary table (club distances), not an archive |
| `SETUP.LS` | 99 | Menu TGAs |
| `POLYANI/<golfer>.L3` | 200 to 230 | `<NAME>_BOUND.SKL` and `<NAME>_LOW_BOUND.SKL` (high and low detail model), about 160 `.CLP` animation clips, clothing and skin TGAs, `SCRIPT.TXT` (animation state script), swing timing tables (`*SWING.TXT`), and build leftovers (`MAKEFILE.MAK`, `NMAKE.EXE`, SourceSafe files) |
| `POLYANI/CLUBS.L3` | 10 | `DRIVER.SKL`, `IRON.SKL`, `PUTTER.SKL` and their textures |

See [carrera-store.md](carrera-store.md) for `.SKL` and `.CLP`, and
[golfer-script.md](golfer-script.md) for `SCRIPT.TXT`.

## Open questions

- Whether the spare index slots and the archive header's `original_size`
  field matter to the game (they look like bookkeeping for in-place edits).
- The meaning of the first eight bytes of untagged entries.

Menu sounds in `SOUNDS.LS`: `BC_CLICK.WAV` (button click); `MUSIC1.WAV` and
`MUSIC2.WAV` (menu music, stereo MS ADPCM, 44.1 kHz, about 90 s), with the
`LO` versions at a lower quality.
