#!/usr/bin/env python3
"""List or extract files from a raw CD image, such as a BlindWrite .b6i.

The Links 2003 discs store the game files uncompressed in an ISO 9660 data
track, so you can read them straight from your own disc images without
installing the game. Only the standard library is used.

    cdimage.py list    DISC.b6i                 # path<TAB>bytes for every file
    cdimage.py extract DISC.b6i OUTDIR [GLOB]   # copy files out (all by default)
    cdimage.py install DISC.b6i OUTDIR [SETUP.EXE]
        # copy the GAME folder out under the long names setup would give it.
        # The names come from the file table in SETUP.EXE, read from the same
        # disc by default; pass CD1's SETUP.EXE for CD2, which has none.
        # Run it once per disc with the same OUTDIR to build a full install.
    cdimage.py info    DISC.b6i                 # volume label and serial
    cdimage.py vcd     DISC.b6i OUTDIR
        # extract the whole disc and add the .windows-label and
        # .windows-serial files Wine reads, so OUTDIR works as a virtual CD
        # when mapped to a "cdrom" drive (tools/mac/links2003-mac.sh does this).

Sector size and the offset of the data track are detected automatically:
2048-byte (.iso) and 2352-byte raw Mode 1 sectors are both supported, with or
without the 150-sector pregap BlindWrite keeps at the start of the image.
"""

import fnmatch
import os
import re
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


def volume_info(img):
    """Return (label, serial) as Windows reports them for the disc.

    Windows uses the volume descriptor with the highest type (the Joliet one,
    when there is one). NT sums the descriptor's 2048 bytes column-wise into
    four bytes and reads them big-endian to get the serial, as Wine does.
    """
    best = None
    lba = 16
    while True:
        desc = img.sector(lba)
        if desc[1:6] != b"CD001" or desc[0] == 255:
            break
        if best is None or desc[0] > best[0]:
            best = desc
        lba += 1
    if best[0] == 2:
        label = best[40:72].decode("utf-16-be", "replace")
    else:
        label = best[40:72].decode("latin-1")
    sums = [sum(best[i::4]) & 0xFF for i in range(4)]
    serial = (sums[0] << 24) | (sums[1] << 16) | (sums[2] << 8) | sums[3]
    return label.rstrip(" \x00"), serial


def extract(img, outdir, pattern="*"):
    for path, lba, size in files(img):
        if not fnmatch.fnmatch(path.lower(), pattern.lower()):
            continue
        dest = os.path.join(outdir, *path.strip("/").split("/"))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as out:
            for chunk in img.chunks(lba, size):
                out.write(chunk)
        print(path)


def long_names(setup_exe):
    """Map disc paths under GAME/ (upper case, '/' separated) to install paths.

    Setup keeps a table of records: u32 0x50, u16 length, the disc path
    ("game\\OBJECT\\TALLTR_1\\TA406A_1.BTX") and the install path
    ("Object\\Tall Trees\\Tall Trees100.btx"), both NUL-terminated.
    See docs/formats/object-library.md.
    """
    names = {}
    for short, long in re.findall(rb"P\x00\x00\x00..(game\\[^\x00]+)\x00([^\x00]+)\x00", setup_exe, re.S):
        if long[0] < 32:
            continue
        key = short.decode("latin-1")[5:].replace("\\", "/").upper()
        names[key] = long.decode("latin-1").replace("\\", "/")
    return names


def install(img, outdir, setup_exe):
    names = long_names(setup_exe)
    print(f"{len(names)} long names from setup", file=sys.stderr)
    for path, lba, size in files(img):
        if not path.upper().startswith("/GAME/"):
            continue
        rel = names.get(path[6:].upper(), path[6:])
        dest = os.path.join(outdir, *rel.split("/"))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as out:
            for chunk in img.chunks(lba, size):
                out.write(chunk)
        print(f"{path}\t{rel}")


def read_file(img, wanted):
    for path, lba, size in files(img):
        if path.upper() == wanted.upper():
            return b"".join(img.chunks(lba, size))
    return None


def main(argv):
    if len(argv) >= 4 and argv[1] == "install":
        img = Image(argv[2])
        if len(argv) > 4:
            setup = open(argv[4], "rb").read()
        else:
            setup = read_file(img, "/SETUP.EXE")
            if setup is None:
                sys.exit("this disc has no SETUP.EXE; pass the one from disc 1")
        install(img, argv[3], setup)
        return
    if len(argv) < 3 or argv[1] not in ("list", "extract", "info", "vcd"):
        sys.exit(__doc__)
    img = Image(argv[2])
    if argv[1] == "list":
        for path, _, size in files(img):
            print(f"{path}\t{size}")
        return
    if argv[1] == "info":
        label, serial = volume_info(img)
        print(f"label\t{label}\nserial\t{serial:08X}")
        return
    if len(argv) < 4:
        sys.exit(__doc__)
    if argv[1] == "vcd":
        extract(img, argv[3])
        label, serial = volume_info(img)
        with open(os.path.join(argv[3], ".windows-label"), "w") as f:
            f.write(label + "\n")
        with open(os.path.join(argv[3], ".windows-serial"), "w") as f:
            f.write(f"{serial:08x}\n")
        return
    extract(img, argv[3], argv[4] if len(argv) > 4 else "*")


if __name__ == "__main__":
    main(sys.argv)
