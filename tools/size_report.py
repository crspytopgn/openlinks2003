#!/usr/bin/env python3
"""Reports what the exported builds weigh and fails when one goes over its
budget in tools/size_budget.json.

    python3 tools/size_report.py [--export game/export] [--budget tools/size_budget.json]
                                 [--summary FILE] [--top 15]

For each build it prints the download size (gzip, roughly what a zip, a
tar.gz or GitHub Pages sends), the size of the game data pack (the .pck,
standalone for the Web, appended to the executable on Linux and Windows) and
the biggest files in that pack, so a budget failure says what grew.
--summary appends the same report as Markdown (CI passes
$GITHUB_STEP_SUMMARY). Exits 1 when a build is over budget.
"""

import argparse
import gzip
import json
import os
import re
import struct
import sys
import zipfile

MB = 1024 * 1024


def pck_entries(path):
    """[(name, size)] of a Godot 4 .pck, standalone or appended to an executable."""
    if os.path.getsize(path) < 128:
        return None
    with open(path, "rb") as f:
        start = 0
        if f.read(4) != b"GDPC":
            f.seek(-12, os.SEEK_END)
            size, magic = struct.unpack("<Q4s", f.read(12))
            if magic != b"GDPC":
                return None
            start = os.path.getsize(path) - 12 - size
            f.seek(start)
            if f.read(4) != b"GDPC":
                return None
        version, _major, _minor, _patch, flags = struct.unpack("<5I", f.read(20))
        if version != 2 or flags & 1:  # format 2 is Godot 4.0 to 4.4; 1 = encrypted directory
            return None
        f.read(8 + 16 * 4)  # file base, reserved
        (count,) = struct.unpack("<I", f.read(4))
        entries = []
        for _ in range(count):
            (name_len,) = struct.unpack("<I", f.read(4))
            name = f.read(name_len).rstrip(b"\0").decode("utf-8", "replace")
            _offset, size = struct.unpack("<QQ", f.read(16))
            f.read(16 + 4)  # md5, flags
            entries.append((name, size))
        return entries


def source_name(name):
    """res://.godot/imported/sky_panorama.hdr-<hash>.s3tc.ctex -> sky_panorama.hdr (s3tc)."""
    m = re.match(r"(?:res://)?\.godot/imported/(.+)-[0-9a-f]{32}(?:\.(\w+))?\.\w+$", name)
    if m:
        return m.group(1) + (f" ({m.group(2)})" if m.group(2) else "")
    return name.replace("res://", "")


def gzip_size(path):
    total = 0
    with open(path, "rb") as f, gzip.GzipFile(fileobj=_Counter(), mode="wb", compresslevel=6) as g:
        while chunk := f.read(4 * MB):
            g.write(chunk)
        total = g.fileobj.count
    return total


class _Counter:
    """A write-only file that only counts bytes."""

    def __init__(self):
        self.count = 0

    def write(self, data):
        self.count += len(data)
        return len(data)

    def flush(self):
        pass


def build_files(folder):
    """Every file of a build; a zip (the macOS app) counts as its members, compressed."""
    out = []
    for root, _dirs, files in os.walk(folder):
        for name in files:
            out.append(os.path.join(root, name))
    return sorted(out)


def report_build(name, folder, top):
    files = build_files(folder)
    if not files:
        return None
    download, pck = 0, None
    for path in files:
        if path.endswith(".zip"):
            download += os.path.getsize(path)  # already compressed
            with zipfile.ZipFile(path) as z:
                for info in z.infolist():
                    if info.filename.endswith(".pck"):
                        pck = pck or ("zip", info.file_size)
        else:
            download += gzip_size(path)
            entries = pck_entries(path)
            if entries is not None and (pck is None or pck[0] == "zip"):
                pck = (path, entries)
    lines = [f"### {name}", "", f"- download (compressed): **{download / MB:.1f} MB**"]
    for path in files:
        lines.append(f"- `{os.path.relpath(path, folder)}`: {os.path.getsize(path) / MB:.1f} MB")
    pack_mb = None
    if pck and pck[0] != "zip":
        entries = pck[1]
        pack_mb = sum(size for _n, size in entries) / MB
        lines.append(f"- game data in the pack: **{pack_mb:.1f} MB** in {len(entries)} files")
        lines += ["", "| biggest files in the pack | MB |", "|---|---:|"]
        for entry_name, size in sorted(entries, key=lambda e: -e[1])[:top]:
            lines.append(f"| {source_name(entry_name)} | {size / MB:.2f} |")
    elif pck:
        pack_mb = pck[1] / MB
        lines.append(f"- game data in the pack: **{pack_mb:.1f} MB**")
    return {"download_mb": download / MB, "pack_mb": pack_mb, "lines": lines}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--export", default=os.path.join(here, "..", "game", "export"))
    ap.add_argument("--budget", default=os.path.join(here, "size_budget.json"))
    ap.add_argument("--summary")
    ap.add_argument("--top", type=int, default=15)
    args = ap.parse_args()

    with open(args.budget) as f:
        budget = json.load(f)
    md, failures = ["## Build sizes", ""], []
    for name, spec in budget["builds"].items():
        result = report_build(name, os.path.join(args.export, spec["folder"]), args.top)
        if result is None:
            failures.append(f"{name}: no build in {spec['folder']}")
            continue
        md += result["lines"]
        for key, label in (("download_mb", "download"), ("pack_mb", "game data")):
            limit = spec.get("max_" + key)
            value = result[key]
            if limit is not None and value is not None:
                status = "ok" if value <= limit else "OVER BUDGET"
                md.append(f"- budget {label}: {value:.1f} / {limit} MB {status}")
                if value > limit:
                    failures.append(f"{name} {label} is {value:.1f} MB, budget {limit} MB")
        md.append("")
    text = "\n".join(md)
    print(text)
    if args.summary:
        with open(args.summary, "a") as f:
            f.write(text + "\n")
    if failures:
        print("SIZE BUDGET FAILED:\n  " + "\n  ".join(failures))
        print("Shrink what grew (see the tables above), or raise the budget in tools/size_budget.json with a reason in the commit.")
        return 1
    print("SIZE BUDGET OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
