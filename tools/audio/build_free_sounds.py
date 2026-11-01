#!/usr/bin/env python3
"""Builds the free game sounds in game/assets/sounds/ from Freesound recordings.

The sounds the game plays without the original Links 2003 files are real
recordings released under CC0 or CC BY on freesound.org. free_sounds.json
lists every source (with its licence) and how each game sound is cut, layered
and mixed from them. This script downloads the sources' high-quality OGG
previews into a cache, renders each sound with ffmpeg and numpy, encodes it as
Ogg Vorbis and writes CREDITS.md next to the sounds.

    python3 tools/audio/build_free_sounds.py [--cache DIR] [--only NAME ...]

Needs ffmpeg (with libvorbis), curl and numpy.
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "game", "assets", "sounds")
SR = 44100
PRE = 0.015

LICENCES = {
    "cc0": ("CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"),
    "by3": ("CC BY 3.0", "https://creativecommons.org/licenses/by/3.0/"),
    "by4": ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"),
}


# Only the start of each preview is fetched: every cut lies in the first
# minute or so, and some sources are an hour long.
FETCH_BYTES = 3_000_000


def fetch(sid, src, cache):
    path = os.path.join(cache, f"{sid}.ogg")
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        tmp = path + ".part"
        subprocess.run(["curl", "-sSfL", "--retry", "3", "-m", "300", "-r", f"0-{FETCH_BYTES - 1}",
                        "-o", tmp, src["preview"]], check=True)
        os.replace(tmp, path)
    return path


def decode(path, ss, t, channels, af):
    filters = [f for f in [af] if f]
    cmd = ["ffmpeg", "-v", "error", "-ss", str(ss)]
    if t:
        cmd += ["-t", str(t)]
    cmd += ["-i", path]
    if filters:
        cmd += ["-af", ",".join(filters)]
    cmd += ["-ac", str(channels), "-ar", str(SR), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, channels).copy()


def fade(x, fin, fout):
    n = len(x)
    a = min(n, int(fin * SR))
    b = min(n, int(fout * SR))
    if a > 0:
        x[:a] *= np.linspace(0.0, 1.0, a)[:, None]
    if b > 0:
        x[n - b:] *= np.linspace(1.0, 0.0, b)[:, None] ** 2
    return x


def render(spec, sources, cache):
    ch = 2 if spec.get("stereo") else 1
    parts = []
    for layer in spec["layers"]:
        sid = str(layer["src"])
        src = sources[sid]
        ss = layer.get("ss", 0)
        if "onset" in layer:
            # Line the layer's transient up PRE seconds (plus "at") into the sound.
            ss = max(0.0, layer["onset"] - PRE)
        x = decode(fetch(sid, src, cache), ss, layer.get("t"), ch, layer.get("af", ""))
        rate = layer.get("rate", 1.0)
        if rate != 1.0:
            # Re-pitch by playing faster or slower (tape style).
            pos = np.arange(0, len(x) - 1, rate)
            x = np.stack([np.interp(pos, np.arange(len(x)), x[:, c]) for c in range(ch)], 1).astype(np.float32)
        x = fade(x, layer.get("fade_in", 0.003), layer.get("fade_out", 0.02))
        x *= 10 ** (layer.get("db", 0.0) / 20)
        parts.append((int(layer.get("at", 0.0) * SR), x))
    n = max(start + len(x) for start, x in parts)
    mix = np.zeros((n, ch), np.float32)
    for start, x in parts:
        mix[start:start + len(x)] += x
    if spec.get("loop"):
        # Crossfade the tail into the head so the file loops without a seam.
        xf = int(spec["loop"] * SR)
        body = mix[: n - xf].copy()
        ramp = np.linspace(0.0, 1.0, xf)[:, None]
        body[:xf] = body[:xf] * np.sqrt(ramp) + mix[n - xf:] * np.sqrt(1.0 - ramp)
        mix = body
    else:
        mix = fade(mix, 0.0, spec.get("fade_out", 0.05))
    if "rms" in spec:
        rms = np.sqrt((mix ** 2).mean()) + 1e-9
        mix *= 10 ** (spec["rms"] / 20) / rms
    peak_target = 10 ** (spec.get("peak", -1.0) / 20)
    peak = np.abs(mix).max() + 1e-9
    if "rms" not in spec or peak > peak_target:
        mix *= peak_target / peak
    return mix


def encode(mix, path, quality):
    ch = mix.shape[1]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", str(ch), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", path],
                   input=mix.astype(np.float32).tobytes(), check=True)


def credits(data):
    used = {}
    for spec in data["sounds"]:
        for layer in spec["layers"]:
            used.setdefault(str(layer["src"]), set()).add(spec["name"])
    lines = [
        "# Free game sounds",
        "",
        "The sounds the game plays when the original Links 2003 files are not",
        "loaded. None of them comes from Links 2003: they are cut and mixed from",
        "these field recordings on [freesound.org](https://freesound.org), by",
        "`tools/audio/build_free_sounds.py` from `tools/audio/free_sounds.json`.",
        "`amb_traffic`, `amb_mower` and `amb_murmur` are not recordings: they are",
        "synthesised from noise by `tools/audio/synth_ambience.py`.",
        "",
        "CC0 recordings need no credit, but every recording is credited anyway.",
        "Those under CC BY are used under that licence; the files here are",
        "edited versions of them (trimmed, layered, filtered, re-pitched, mixed",
        "and re-encoded).",
        "",
        "| Recording | Author | Licence | Used in |",
        "| --- | --- | --- | --- |",
    ]
    for sid, src in sorted(data["sources"].items(), key=lambda kv: (kv[1]["license"] != "cc0", kv[1]["user"].lower())):
        if sid not in used:
            continue
        name, url = LICENCES[src["license"]]
        title = src["title"].replace("|", "/")
        lines.append(f"| [{title}]({src['url']}) | {src['user']} | [{name}]({url}) | "
                     f"{', '.join(sorted(used[sid]))} |")
    lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.join(HERE, ".cache"))
    ap.add_argument("--only", nargs="*")
    args = ap.parse_args()
    data = json.load(open(os.path.join(HERE, "free_sounds.json")))
    os.makedirs(args.cache, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    for spec in data["sounds"]:
        if args.only and spec["name"] not in args.only:
            continue
        mix = render(spec, data["sources"], args.cache)
        path = os.path.join(OUT, spec["name"] + ".ogg")
        encode(mix, path, spec.get("q", 3))
        print(f"{spec['name']:24s} {len(mix) / SR:6.2f} s {os.path.getsize(path) / 1024:7.1f} KB", flush=True)
    with open(os.path.join(OUT, "CREDITS.md"), "w") as f:
        f.write(credits(data))


if __name__ == "__main__":
    sys.exit(main())
