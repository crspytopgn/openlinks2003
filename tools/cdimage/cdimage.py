#!/usr/bin/env python3
"""List or extract files from a raw CD image, such as a BlindWrite .b6i.

The Links 2003 discs store the game files uncompressed in an ISO 9660 data
track, so you can read them straight from your own disc images without
installing the game. Only the standard library is used.

    cdimage.py list    DISC.b6i                 # path<TAB>bytes for every file
    cdimage.py extract DISC.b6i OUTDIR [GLOB]   # copy files out (all by default)

Sector size and the offset of the data track are detected automatically:
2048-byte (.iso) and 2352-byte raw Mode 1 sectors are both supported, with or
without the 150-sector pregap BlindWrite keeps at the start of the image.
"""

import fnmatch
import os
import struct
import sys

LAYOUTS = [  # (sector size, header bytes before user data)
    (2048, 0),
    (2352, 16),
    (2352, 24),
]
PREGAPS = [0, 150]


class Image:
    def __init__(self, path):
        self.f = open(path, "rb")
        for size, header in LAYOUTS:
            for pregap in PREGAPS:
                self.size, self.header, self.pregap = size, header, pregap
                if self.sector(16)[1:6] == b"CD001":
                    return
        raise ValueError(f"{path}: no ISO 9660 volume found")

    def sector(self, lba):
        self.f.seek((lba + self.pregap) * self.size + self.header)
        return self.f.read(2048)

    def read(self, lba, length):
        out = bytearray()
        while len(out) < length:
            out += self.sector(lba)
            lba += 1
        return bytes(out[:length])

    def chunks(self, lba, length):
        while length > 0:
            data = self.sector(lba)[: min(2048, length)]
            yield data
            length -= len(data)
            lba += 1


def root_record(img):
    """Return (root directory record, is_joliet), preferring Joliet names."""
    primary = None
    lba = 16
    while True:
        desc = img.sector(lba)
        if desc[1:6] != b"CD001" or desc[0] == 255:
            break
        if desc[0] == 1 and primary is None:
            primary = desc
        if desc[0] == 2 and desc[88:91] in (b"%/@", b"%/C", b"%/E"):
            return desc[156:190], True
        lba += 1
    return primary[156:190], False


def walk(img, record, joliet, prefix=""):
    lba, length = struct.unpack_from("<I", record, 2)[0], struct.unpack_from("<I", record, 10)[0]
    data = img.read(lba, length)
    pos = 0
    while pos < len(data):
        rec_len = data[pos]
        if rec_len == 0:  # records never cross a sector; skip the padding
            pos = (pos // 2048 + 1) * 2048
            continue
        rec = data[pos : pos + rec_len]
        pos += rec_len
        name = rec[33 : 33 + rec[32]]
        if name in (b"\x00", b"\x01"):
            continue
        name = (name.decode("utf-16-be") if joliet else name.decode("latin-1")).split(";")[0]
        path = f"{prefix}/{name}"
        if rec[25] & 2:
            yield from walk(img, rec, joliet, path)
        else:
            yield path, struct.unpack_from("<I", rec, 2)[0], struct.unpack_from("<I", rec, 10)[0]


def files(img):
    record, joliet = root_record(img)
    return walk(img, record, joliet)


def main(argv):
    if len(argv) < 3 or argv[1] not in ("list", "extract"):
        sys.exit(__doc__)
    img = Image(argv[2])
    if argv[1] == "list":
        for path, _, size in files(img):
            print(f"{path}\t{size}")
        return
    if len(argv) < 4:
        sys.exit(__doc__)
    outdir, pattern = argv[3], argv[4] if len(argv) > 4 else "*"
    for path, lba, size in files(img):
        if not fnmatch.fnmatch(path.lower(), pattern.lower()):
            continue
        dest = os.path.join(outdir, *path.strip("/").split("/"))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as out:
            for chunk in img.chunks(lba, size):
                out.write(chunk)
        print(path)


if __name__ == "__main__":
    main(sys.argv)
