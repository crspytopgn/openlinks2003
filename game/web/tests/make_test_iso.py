#!/usr/bin/env python3
"""Writes a tiny ISO 9660 image laid out like a Links 2003 disc, for testing
the disc readers without real game data.

    make_test_iso.py OUT.iso [--raw]

--raw writes 2352-byte Mode 1 sectors behind a 150-sector pregap, as
BlindWrite .b6i images have. The files and their contents are listed in
FILES below; SETUP.EXE holds one long-name record.
"""

import struct
import sys

SETUP = b"MZ junk " + b"P\x00\x00\x00\x40\x00" + b"game\\OBJECT\\TA1.BTX\x00Object\\Tall Trees\\Tall Trees100.btx\x00" + b" tail"
FILES = {
    "SETUP.EXE": SETUP,
    "GAME/OBJECT.LIB": b"catalog" * 10,
    "GAME/OBJECT/TA1.BTX": bytes(range(256)) * 3,
    "GAME/COURSES/TEST.CRZ": bytes((i * 7) & 0xFF for i in range(5000)),
    "GAME/INTRO.WMV": b"video" * 100,
}


def both16(v):
    return struct.pack("<H", v) + struct.pack(">H", v)


def both32(v):
    return struct.pack("<I", v) + struct.pack(">I", v)


def record(name, lba, size, is_dir):
    rec = bytearray()  # everything after the length byte
    rec += b"\x00" + both32(lba) + both32(size) + bytes(7)
    rec += bytes([2 if is_dir else 0, 0, 0]) + both16(1) + bytes([len(name)]) + name
    if len(rec) % 2 == 0:  # pad so the total (with the length byte) is even
        rec += b"\x00"
    return bytes([len(rec) + 1]) + bytes(rec)


def build():
    # Directory tree: {dir path: {name: (is_dir, data or None)}}
    tree = {"": {}}
    for path, data in FILES.items():
        parts = path.split("/")
        for i in range(len(parts) - 1):
            parent, d = "/".join(parts[:i]), "/".join(parts[: i + 1])
            tree.setdefault(d, {})
            tree[parent][parts[i]] = (True, None)
        tree["/".join(parts[:-1])][parts[-1]] = (False, data)

    dirs = sorted(tree, key=lambda d: (d.count("/"), d))
    lba = 20
    dir_lba = {}
    for d in dirs:
        dir_lba[d] = lba
        lba += 1
    file_lba = {}
    for path, data in FILES.items():
        file_lba[path] = lba
        lba += (len(data) + 2047) // 2048
    total = lba

    sectors = [bytes(2048)] * total
    for d in dirs:
        parent = d.rsplit("/", 1)[0] if "/" in d else ""
        body = record(b"\x00", dir_lba[d], 2048, True) + record(b"\x01", dir_lba[parent], 2048, True)
        for name in sorted(tree[d]):
            is_dir, data = tree[d][name]
            full = f"{d}/{name}" if d else name
            if is_dir:
                body += record(name.encode(), dir_lba[full], 2048, True)
            else:
                body += record((name + ";1").encode(), file_lba[full], len(data), False)
        sectors[dir_lba[d]] = body.ljust(2048, b"\x00")
    for path, data in FILES.items():
        for i in range(0, len(data), 2048):
            sectors[file_lba[path] + i // 2048] = data[i : i + 2048].ljust(2048, b"\x00")

    pvd = bytearray(2048)
    pvd[0:7] = b"\x01CD001\x01"
    pvd[80:88] = both32(total)
    pvd[156:190] = record(b"\x00", dir_lba[""], 2048, True)
    sectors[16] = bytes(pvd)
    sectors[17] = b"\xffCD001\x01".ljust(2048, b"\x00")
    return sectors


def main():
    out, raw = sys.argv[1], "--raw" in sys.argv
    sectors = build()
    with open(out, "wb") as f:
        if raw:
            f.write(bytes(2352) * 150)
            for lba, s in enumerate(sectors):
                header = b"\x00" + b"\xff" * 10 + b"\x00" + struct.pack(">I", lba)[1:] + b"\x01"
                f.write(header + s + bytes(288))
        else:
            for s in sectors:
                f.write(s)


if __name__ == "__main__":
    main()
