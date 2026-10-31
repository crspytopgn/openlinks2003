#!/usr/bin/env python3
"""Packs a Radiance .hdr panorama into the compressed sky file the game loads
(FreeAssets.sky()), about half the size of Godot's own import of it, with the
same pixels.

    python3 tools/sky_pack.py sky_panorama.hdr sky_panorama.olsky

Godot imports an HDR losslessly as uncompressed RGB9E5 (4 bytes a pixel, 8 MB
for the 2048 x 1024 sky, and the pack doesn't compress it). This writes the
same RGB9E5 pixels, deflated:

    "OLSKY1\\0\\0", u32 width, u32 height, u32 raw size, zlib stream

and the game inflates them into an Image at load (all in the engine, a few
milliseconds). Pure Python, so CI needs nothing extra.
"""

import math
import struct
import sys
import zlib

MAGIC = b"OLSKY1\0\0"


def read_hdr(data):
    """(width, height, bytearray of R, G, B, E per pixel) from a Radiance file."""
    pos = 0
    while True:
        end = data.index(b"\n", pos)
        line = data[pos:end]
        pos = end + 1
        if line.startswith(b"-Y ") or line.startswith(b"+Y "):
            parts = line.split()
            if parts[0] != b"-Y" or parts[2] != b"+X":
                raise ValueError("only -Y H +X W panoramas are supported")
            height, width = int(parts[1]), int(parts[3])
            break
        if line.startswith(b"FORMAT=") and line != b"FORMAT=32-bit_rle_rgbe":
            raise ValueError("not an RGBE file")
    out = bytearray(width * height * 4)
    for y in range(height):
        row = out[y * width * 4:(y + 1) * width * 4]
        if data[pos] == 2 and data[pos + 1] == 2 and (data[pos + 2] << 8 | data[pos + 3]) == width and 8 <= width < 32768:
            pos += 4
            for ch in range(4):
                x = 0
                while x < width:
                    count = data[pos]
                    pos += 1
                    if count > 128:
                        count -= 128
                        row[ch + x * 4:ch + (x + count) * 4:4] = bytes([data[pos]]) * count
                        pos += 1
                    else:
                        row[ch + x * 4:ch + (x + count) * 4:4] = data[pos:pos + count]
                        pos += count
                    x += count
        else:  # flat (old-style runs are not used by any current tool)
            row[:] = data[pos:pos + width * 4]
            pos += width * 4
        out[y * width * 4:(y + 1) * width * 4] = row
    return width, height, out


def rgbe9995(r, g, b):
    """Godot's Color.to_rgbe9995()."""
    shared = 65408.0
    r = max(0.0, min(shared, r))
    g = max(0.0, min(shared, g))
    b = max(0.0, min(shared, b))
    cmax = max(r, g, b)
    expp = max(-16.0, math.floor(math.log(cmax) / math.log(2.0)) if cmax > 0 else -math.inf) + 16.0
    smax = math.floor(cmax / 2.0 ** (expp - 24.0) + 0.5)
    exps = expp if 0.0 <= smax < 512.0 else expp + 1.0
    scale = 2.0 ** (exps - 24.0)
    sr = int(math.floor(r / scale + 0.5))
    sg = int(math.floor(g / scale + 0.5))
    sb = int(math.floor(b / scale + 0.5))
    return (sr & 0x1FF) | (sg & 0x1FF) << 9 | (sb & 0x1FF) << 18 | (int(exps) & 0x1F) << 27


def to_rgb9e5(rgbe):
    """RGB9E5 bytes for Radiance RGBE pixels, cached per distinct pixel (a sky has few)."""
    out = bytearray(len(rgbe))
    cache = {}
    pack = struct.Struct("<I").pack_into
    for i in range(0, len(rgbe), 4):
        key = bytes(rgbe[i:i + 4])
        value = cache.get(key)
        if value is None:
            e = key[3]
            f = math.ldexp(1.0, e - 136) if e else 0.0
            value = rgbe9995(key[0] * f, key[1] * f, key[2] * f)
            cache[key] = value
        pack(out, i, value)
    return out


def pack(hdr_bytes):
    width, height, rgbe = read_hdr(hdr_bytes)
    raw = to_rgb9e5(rgbe)
    return MAGIC + struct.pack("<III", width, height, len(raw)) + zlib.compress(bytes(raw), 9), raw


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    with open(sys.argv[1], "rb") as f:
        packed, _raw = pack(f.read())
    with open(sys.argv[2], "wb") as f:
        f.write(packed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
