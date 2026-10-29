#!/usr/bin/env python3
"""List or extract Links 2003 LSls archives (.LS, .L3, .TIP) and .SSF sound banks.

Formats: docs/formats/ls-archive.md and docs/formats/ssf.md. Only the standard
library is used, so this runs anywhere Python 3 does; `oldump` (C++) does the
same faster.

    lsarchive.py list    FILE                # name, size, stored size, method
    lsarchive.py extract FILE OUTDIR [GLOB]  # every entry, or those matching GLOB

For .SSF banks, `extract` writes each wave as a plain 16-bit PCM WAV
(golfer voices and commentary are stored as Microsoft ADPCM).
"""

import fnmatch
import os
import struct
import sys

BLOCK_HEADER = 0x37


def lzw_decompress(src, max_out, xor5=False):
    """Variable-width LZW: LSB-first codes, 9 to 13 bits, 256 clear, 257 end."""
    if xor5:
        src = bytes(b ^ 5 for b in src)
    prefix = [0] * 8192
    suffix = [0] * 8192
    out = bytearray()
    bit, width, next_free, prev, first = 0, 9, 258, -1, 0
    total = len(src) * 8
    while len(out) < max_out and bit + width <= total:
        i = bit >> 3
        code = (int.from_bytes(src[i:i + 3].ljust(3, b"\0"), "little") >> (bit & 7)) & ((1 << width) - 1)
        bit += width
        if code == 256:
            width, next_free, prev = 9, 258, -1
            continue
        if code == 257:
            break
        if prev < 0:
            out.append(code)
            prev = first = code
            continue
        if code > next_free:
            raise ValueError("bad LZW code %d" % code)
        stack = bytearray()
        cur = code
        if code == next_free:
            stack.append(first)
            cur = prev
        while cur >= 258:
            stack.append(suffix[cur])
            cur = prefix[cur]
        first = cur
        stack.append(cur)
        stack.reverse()
        out += stack
        if next_free < 8192:
            prefix[next_free], suffix[next_free] = prev, first
            next_free += 1
            if next_free >= (1 << width) and width < 13:
                width += 1
        prev = code
    return bytes(out[:max_out])


def ls_entries(data):
    """Yields (name, original_size, stored_size, compressed, reader) per entry."""
    if data[:4] != b"LSls":
        raise ValueError("not an LSls archive")
    version, header_size = struct.unpack_from("<HH", data, 4)
    count = struct.unpack_from("<I", data, 0x0A)[0]
    name_width = {0x020B: 13, 0x020C: 64}.get(version)
    if name_width is None:
        raise ValueError("unknown LSls version 0x%04x" % version)
    slot = name_width + 4
    for i in range(count):
        base = header_size + i * slot
        name = data[base:base + name_width].split(b"\0")[0].decode("latin-1")
        off = struct.unpack_from("<I", data, base + name_width)[0]
        hdr = data[off:off + BLOCK_HEADER]
        compressed = hdr[0x18] == 1
        original, stored = struct.unpack_from("<II", hdr, 0x19)
        start = off + struct.unpack_from("<H", hdr, 6)[0]
        raw = data[start:start + stored]

        def read(raw=raw, compressed=compressed, original=original, xor5=hdr[0x36] != 0):
            return lzw_decompress(raw, original, xor5) if compressed else bytes(raw)

        yield name, original, stored, compressed, read


def ssf_waves(data):
    """Yields (index, name, riff_bytes) for every wave in an SSF bank."""
    if data[:4] != b"SSF\0":
        raise ValueError("not an SSF bank")
    pos, names, waves = 0x1C, [], []
    while pos + 16 <= len(data):
        tag, size = struct.unpack_from("<4sI", data, pos)
        body = data[pos + 16:pos + 16 + size]
        if tag == b"WND\0":
            names = body.decode("utf-16-le").split("\0")
        elif tag[:1] == b"W" and tag not in (b"WST\0",):
            waves.append((tag[1] | (tag[2] << 8), body))
        pos += 16 + size
    for index, riff in waves:
        yield index, names[index] if index < len(names) else "", riff


ADAPT = [230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230]


def wav_to_pcm16(riff):
    """Returns a plain PCM WAV: MS ADPCM is decoded, PCM is passed through."""
    fmt = data = None
    pos = 12
    while pos + 8 <= len(riff):
        cid, size = struct.unpack_from("<4sI", riff, pos)
        if cid == b"fmt ":
            fmt = riff[pos + 8:pos + 8 + size]
        elif cid == b"data":
            data = riff[pos + 8:pos + 8 + size]
        pos += 8 + size + (size & 1)
    tag, ch, rate, _, align, bits = struct.unpack_from("<HHIIHH", fmt, 0)
    if tag == 1:
        return riff
    if tag != 2:
        raise ValueError("unsupported WAVE format %d" % tag)
    spb, ncoef = struct.unpack_from("<HH", fmt, 18)
    coefs = struct.unpack_from("<%dh" % (ncoef * 2), fmt, 22)
    out = []
    for blk in range(0, len(data) - 7 * ch + 1, align):
        b = data[blk:blk + align]
        pred = [b[c] if b[c] < ncoef else 0 for c in range(ch)]
        c1 = [coefs[p * 2] for p in pred]
        c2 = [coefs[p * 2 + 1] for p in pred]
        delta = list(struct.unpack_from("<%dh" % ch, b, ch))
        s1 = list(struct.unpack_from("<%dh" % ch, b, 3 * ch))
        s2 = list(struct.unpack_from("<%dh" % ch, b, 5 * ch))
        out += s2 + s1
        limit, n = (spb - 2) * ch, 0
        for byte in b[7 * ch:]:
            for half, nib in enumerate((byte >> 4, byte & 15)):
                if n >= limit:
                    break
                c = half if ch == 2 else 0
                p = int((s1[c] * c1[c] + s2[c] * c2[c]) / 256)  # truncate toward zero
                v = max(-32768, min(32767, p + (nib - 16 if nib >= 8 else nib) * delta[c]))
                s2[c], s1[c] = s1[c], v
                delta[c] = max(16, (ADAPT[nib] * delta[c]) >> 8)
                out.append(v)
                n += 1
    pcm = struct.pack("<%dh" % len(out), *out)
    head = struct.pack("<4sI4s4sIHHIIHH4sI", b"RIFF", 36 + len(pcm), b"WAVE", b"fmt ", 16, 1, ch, rate,
                       rate * ch * 2, ch * 2, 16, b"data", len(pcm))
    return head + pcm


def main(argv):
    if len(argv) < 3 or argv[1] not in ("list", "extract") or (argv[1] == "extract" and len(argv) < 4):
        print(__doc__.strip())
        return 2
    data = open(argv[2], "rb").read()
    pattern = argv[4] if len(argv) > 4 else "*"
    if data[:4] == b"SSF\0":
        for index, name, riff in ssf_waves(data):
            name = name or "wave%d.wav" % index
            print("%4d  %-28s %10d" % (index, name, len(riff)))
            if argv[1] == "extract" and fnmatch.fnmatch(name.upper(), pattern.upper()):
                os.makedirs(argv[3], exist_ok=True)
                with open(os.path.join(argv[3], "%d_%s" % (index, name)), "wb") as f:
                    f.write(wav_to_pcm16(riff))
        return 0
    for name, original, stored, compressed, read in ls_entries(data):
        print("%-40s %10d %10d %s" % (name, original, stored, "lzw" if compressed else "stored"))
        if argv[1] == "extract" and fnmatch.fnmatch(name.upper(), pattern.upper()):
            os.makedirs(argv[3], exist_ok=True)
            with open(os.path.join(argv[3], name), "wb") as f:
                f.write(read())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
