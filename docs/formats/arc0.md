# ARC0 compressed archive (`.LIB`, `.BTX`, `.TOP`, `.CMF`, `.sky`)

Status: complete for every ARC0 file on CD3 (1,162 archives, 7,670 entries)
Seen in: CD1 `GAME/` (`STDTER_1.LIB`, `PANSKY.LIB`, `CROWDS.LIB`), CD3
`GAME/OBJECT/**`, the v1.07 patch `skies/*.sky`

## Overview

A named archive of zlib-compressed entries. The game uses it for texture
libraries and for each Course Designer object: a `.BTX` object holds five
billboard sizes plus a `MasterObj` description, a `.TOP` holds the course-map
top view, and a `.CMF` holds the texture set of a 3D object.

The data streams come first, then a directory at the end. Everything is
little-endian.

## Layout

### Header (16 bytes)

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | char[4] | magic | `ARC0` |
| 0x04 | u32 | file_size | Size of the whole file |
| 0x08 | u32 | count | Number of entries |
| 0x0C | u32 | dir_offset | Offset of the directory, which runs to the end of the file |

### Entry data

Each entry's data is a complete zlib stream (RFC 1950, `78 9c` header,
Adler-32 trailer). The streams sit back to back starting at offset 0x10, in
directory order, with nothing between them.

### Directory (`count` records of 64 bytes at `dir_offset`)

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | u32 | reserved | Always 0 |
| 0x04 | char[32] | name | NUL-padded, mixed case, may contain spaces (`Tall Trees100A.btc`, `MasterObj`, `Textures`) |
| 0x24 | u32 | offset | Absolute offset of the entry's zlib stream |
| 0x28 | u32 | packed_size | Length of the zlib stream |
| 0x2C | u32 | size | Unpacked length |
| 0x30 | u32 | method | 2 = zlib. No other value has been seen |
| 0x34 | u32 | checksum | Adler-32 of the unpacked data (the same value as the zlib trailer), or 0 when the tool that wrote the file left it out (30 entries in 11 `TOPVIEWS/*.TOP` files) |
| 0x38 | u32[2] | reserved | Always 0 |

Names are looked up case-insensitively: `CROWDS.LIB` spells its description
entry `masterobj`, object files spell it `MasterObj`.

## Contents seen on CD3

| File | Entries |
|------|---------|
| `OBJECT/**/*.BTX` | 5 `BTCV` textures (largest to smallest billboard, suffix `A` to `E`), then `MasterObj` |
| `OBJECT/TOPVIEWS/*.TOP` | 1 to 3 `BTCV` top views, then `MasterObj` |
| `OBJECT/3D2K3*/*.CMF` | One entry, `Textures` |
| `CROWDS.LIB` | 980 `BTCV` spectator sprites, then `masterobj` |

## Implementation

`olcore::Arc0Archive` (`libs/olcore/include/olcore/arc0.hpp`) reads the
format and checks sizes and checksums; `olcore::zlib_decompress` is a
dependency-free inflater. `tools/olarc` lists, verifies and unpacks archives:

```bash
olarc list    OBJECT/TALLTR_1/TA406A_1.BTX
olarc verify  $(find GAME -name '*.BTX')
olarc extract OBJECT/TALLTR_1/TA406A_1.BTX /tmp/ta406a
```

## Open questions

- Whether any archive uses a method other than 2 (none on CD3; CD1 and the
  patch skies still to be checked).
