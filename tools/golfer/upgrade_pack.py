"""Upgrades the free golfer's look pack in place with the realism passes,
in order, then drops the bytes they replaced.

    python3 tools/golfer/upgrade_pack.py [--pack game/assets/golfer/free_golfer_parts.olg]

Run it on a pack straight from build_free_golfer.py (and golf_shoes.py):
- cap.py: the structured six-panel tour cap;
- skin_regions.py: the face's region map for the skin shader;
- collar.py: polo collars, plackets and buttons;
- tailored.py: tailored trousers instead of jeans.
Each step refuses a pack it has already been run on.
"""

import argparse
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import golf_shoes  # noqa: E402

STEPS = ["cap.py", "skin_regions.py", "collar.py", "tailored.py"]
SPAN_KEYS = {"positions", "normals", "uvs", "bones", "weights", "indices", "tangents", "rows", "normals_u8", "data",
             "golf_source"}


def compact(info, blob):
    """Rewrites the blob with only the spans the header points to."""
    out = bytearray()
    moved = {}

    def visit(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in SPAN_KEYS and isinstance(v, list) and len(v) == 2 and all(isinstance(x, int) for x in v):
                    key = (v[0], v[1])
                    if key not in moved:
                        while len(out) % 4:
                            out.append(0)
                        moved[key] = len(out)
                        out.extend(blob[v[0]:v[0] + v[1]])
                    node[k] = [moved[key], v[1]]
                else:
                    visit(v)
        elif isinstance(node, list):
            for v in node:
                visit(v)

    visit(info)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default="game/assets/golfer/free_golfer_parts.olg")
    args = ap.parse_args()
    here = os.path.dirname(os.path.abspath(__file__))
    for step in STEPS:
        subprocess.run([sys.executable, os.path.join(here, step), "--pack", args.pack], check=True)
    info, blob = golf_shoes.load(args.pack)
    before = len(blob)
    blob = compact(info, blob)
    golf_shoes.save(args.pack, info, blob)
    print(f"compacted {before} -> {len(blob)} bytes; pack {os.path.getsize(args.pack)} bytes")


if __name__ == "__main__":
    np.seterr(all="ignore")
    main()
