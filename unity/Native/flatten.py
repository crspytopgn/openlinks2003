#!/usr/bin/env python3
"""Copies libs/olcore and olcore_unity.cpp into one flat folder, with every
`#include "olcore/x.hpp"` rewritten to `#include "x.hpp"`, so Unity's Web
build can compile the sources with no include paths, and the desktop
library builds from the same files. Usage: flatten.py OUT_DIR"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.join(HERE, "..", "..", "libs", "olcore")
# What a shot needs (olcore's decoders stay out of the game build).
SOURCES = ["ball_physics", "shot", "swing", "obstacles", "links_flight", "links_ground", "links_launch",
           "links_objects"]


def copy(src, dst):
    text = open(src, encoding="utf-8").read()
    text = re.sub(r'#include "olcore/([^"]+)"', r'#include "\1"', text)
    with open(dst, "w", encoding="utf-8") as f:
        f.write(text)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    inc = os.path.join(CORE, "include", "olcore")
    for h in os.listdir(inc):
        copy(os.path.join(inc, h), os.path.join(out, h))
    for s in SOURCES:
        copy(os.path.join(CORE, "src", s + ".cpp"), os.path.join(out, "olcore_" + s + ".cpp"))
    copy(os.path.join(HERE, "olcore_unity.cpp"), os.path.join(out, "olcore_unity.cpp"))


if __name__ == "__main__":
    main()
