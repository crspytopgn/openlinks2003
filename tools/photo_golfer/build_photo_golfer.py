#!/usr/bin/env python3
"""Builds the photo golfer: frames of a real person filmed swinging, cut out
of the background, for the "Photo golfer" option (PhotoGolfer in the game).

    python3 tools/photo_golfer/build_photo_golfer.py [--take NAME] [--cache DIR]

Each take in takes.json names a freely licensed video (CC0 or CC BY, never
broadcast footage or anything from the Links discs), the frames used for each
clip and where the ball is in the picture. The script

1. downloads the video into --cache (Wikimedia rate-limits some networks;
   put the file in the cache by hand if the download fails),
2. pulls the frames with ffmpeg,
3. cuts the golfer out with BiRefNet through rembg (pip install rembg
   onnxruntime pillow numpy) and keeps only the golfer, the club and the
   club head (stray range balls and specks are dropped),
4. crops each frame to its cut-out, scales it and stores it as a WebP in
   game/assets/photo_golfer/<take>/frames.olp (the four bytes OLPG, then
   the frames back to back), and
5. writes take.json beside it: per frame its offset and length in the
   pack, its size and where the ball is, and per clip the time of each
   frame and of impact.

The matting is slow on a CPU (about 10 to 30 s a frame), so cut-outs are
cached in --cache and only new frames are matted on a rerun.
"""

import argparse
import io
import json
import os
import subprocess
import sys
import urllib.request

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "game", "assets", "photo_golfer")
MODEL = "birefnet-general-lite"
# Output pixels per metre: close to the source's own (470 at the ball), so a
# 1.6 m golfer is about 640 px tall, sharp in close-ups and replays.
OUT_PX_PER_M = 400.0
PACK = "frames.olp"
MAGIC = b"OLPG"
QUALITY = 92
# Cut-out pieces smaller than this (in source pixels) are dropped unless they
# touch the golfer: range balls, divots, specks of sky.
MIN_PIECE = 400


def download(take, cache):
    path = os.path.join(cache, os.path.basename(take["url"]))
    if os.path.exists(path) and os.path.getsize(path) > 100000:
        return path
    req = urllib.request.Request(take["url"], headers={"User-Agent": "OpenLinks2003/0.1 (https://github.com/crspytopgn/openlinks2003)"})
    with urllib.request.urlopen(req, timeout=300) as r, open(path, "wb") as f:
        f.write(r.read())
    return path


def frame_numbers(take):
    wanted = set()
    for clip in take["clips"].values():
        for seg in clip["segments"]:
            wanted.update(range(seg["from"], seg["to"] + 1, seg["step"]))
    return sorted(wanted)


def extract(video, numbers, folder):
    os.makedirs(folder, exist_ok=True)
    missing = [n for n in numbers if not os.path.exists(os.path.join(folder, "%05d.png" % n))]
    if not missing:
        return
    last = max(missing)
    tmp = os.path.join(folder, "all")
    os.makedirs(tmp, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", video, "-frames:v", str(last + 1),
                    "-start_number", "0", os.path.join(tmp, "%05d.png")], check=True)
    for n in numbers:
        os.replace(os.path.join(tmp, "%05d.png" % n), os.path.join(folder, "%05d.png" % n))
    for f in os.listdir(tmp):
        os.remove(os.path.join(tmp, f))
    os.rmdir(tmp)


def matte(numbers, frames, mattes, box, limit=0):
    """Mattes the frames not in the cache yet. Returns False if `limit`
    frames were done and more are left (onnxruntime's memory grows frame by
    frame, so long runs are split into fresh processes)."""
    from rembg import new_session, remove
    os.makedirs(mattes, exist_ok=True)
    todo = [n for n in numbers if not os.path.exists(os.path.join(mattes, "%05d.png" % n))]
    if not todo:
        return True
    more = limit > 0 and len(todo) > limit
    if more:
        todo = todo[:limit]
    session = new_session(MODEL)
    for i, n in enumerate(todo):
        im = Image.open(os.path.join(frames, "%05d.png" % n)).convert("RGB").crop(box)
        alpha = remove(im, session=session, only_mask=True)
        alpha.save(os.path.join(mattes, "%05d.png" % n))
        print("matted %d (%d of %d)" % (n, i + 1, len(todo)), flush=True)
    return not more


def clean(alpha):
    """Keeps the golfer: the biggest piece and every piece near it that is
    big enough (the club head can come apart from a blurred shaft)."""
    from scipy import ndimage
    solid = alpha > 24
    labels, count = ndimage.label(solid, structure=np.ones((3, 3)))
    if count <= 1:
        return alpha
    sizes = ndimage.sum(solid, labels, range(1, count + 1))
    main = int(np.argmax(sizes)) + 1
    near = ndimage.binary_dilation(labels == main, iterations=12)
    keep = np.zeros(count + 1, bool)
    keep[main] = True
    for i in range(1, count + 1):
        if i != main and sizes[i - 1] >= MIN_PIECE and near[labels == i].any():
            keep[i] = True
    mask = keep[labels]
    # Keep the soft edge around the kept pieces only.
    grown = ndimage.binary_dilation(mask, iterations=3)
    return np.where(grown, alpha, 0).astype(np.uint8)


def decontaminate(rgb, alpha):
    """Pulls the background colour out of the soft edge (the grey sky would
    otherwise leave a light fringe on grass): edge pixels take the colour of
    the nearest solid pixel, blended by how solid they are."""
    from scipy import ndimage
    solid = alpha >= 230
    if not solid.any():
        return rgb
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    inner = rgb[iy, ix].astype(np.float32)
    a = (alpha.astype(np.float32) / 255.0)[..., None]
    mix = np.clip((a - 0.1) / 0.8, 0.0, 1.0)
    return (rgb * mix + inner * (1.0 - mix)).astype(np.uint8)


def build(name, take, cache, limit=0):
    video = download(take, cache)
    numbers = frame_numbers(take)
    frames = os.path.join(cache, name, "frames")
    mattes = os.path.join(cache, name, "mattes_" + MODEL)
    extract(video, numbers, frames)
    box = tuple(take["keep_box"])
    if not matte(numbers, frames, mattes, box, limit):
        print("%s: more frames to matte, run again" % name)
        return

    scale = OUT_PX_PER_M / take["px_per_m"]
    ball = (np.array(take["ball_px"], float) - np.array(box[:2], float)) * scale
    cutouts = {}
    for n in numbers:
        rgb = np.asarray(Image.open(os.path.join(frames, "%05d.png" % n)).convert("RGB").crop(box))
        alpha = clean(np.asarray(Image.open(os.path.join(mattes, "%05d.png" % n)).convert("L")))
        rgb = decontaminate(rgb, alpha)
        im = Image.fromarray(np.dstack([rgb, alpha]), "RGBA")
        size = (round(im.width * scale), round(im.height * scale))
        im = im.resize(size, Image.LANCZOS)
        bb = im.getbbox()
        cutouts[n] = (im.crop(bb), bb)

    # Each frame is its own WebP in one pack file (frames.olp): the game
    # decodes only the frame on screen into one small texture, so the photo
    # golfer costs about a megabyte of video memory whatever the frame count.
    folder = os.path.join(OUT, name)
    os.makedirs(folder, exist_ok=True)
    for f in os.listdir(folder):
        if f.startswith("sheet_") or f == PACK:
            os.remove(os.path.join(folder, f))
    out_frames = {}
    blob = bytearray(MAGIC)
    for n in numbers:
        im, bb = cutouts[n]
        buf = io.BytesIO()
        im.save(buf, "WEBP", quality=QUALITY, method=6, exact=False)
        data = buf.getvalue()
        # The ball's position relative to the frame's top left corner.
        out_frames[str(n)] = {"offset": len(blob), "bytes": len(data), "size": [im.width, im.height],
                              "ball": [round(ball[0] - bb[0], 1), round(ball[1] - bb[1], 1)]}
        blob += data
    with open(os.path.join(folder, PACK), "wb") as f:
        f.write(blob)
    clips = {}
    for clip_name, clip in take["clips"].items():
        frames_out, times = [], []
        t0 = 0.0
        for seg in clip["segments"]:
            seq = list(range(seg["from"], seg["to"] + 1, seg["step"]))
            for i, n in enumerate(seq):
                frames_out.append(n)
                times.append(round(t0 + seg["seconds"] * i / len(seq), 4))
            t0 += seg["seconds"]
        clips[clip_name] = {"frames": frames_out, "times": times, "loop": clip.get("loop", False)}
        if "impact_frame" in clip:
            # When the club meets the ball, in seconds into the clip: the
            # round holds the ball until then (GolferRig.impact_delay).
            clips[clip_name]["impact"] = times[frames_out.index(clip["impact_frame"])]
    meta = {
        "source": {k: take[k] for k in ("title", "page", "author", "license", "view", "club")},
        "px_per_m": OUT_PX_PER_M,
        "golfer_height_m": take["golfer_height_m"],
        "pack": PACK,
        "frames": out_frames,
        "clips": clips,
    }
    with open(os.path.join(folder, "take.json"), "w") as f:
        json.dump(meta, f, indent=1)
        f.write("\n")
    print("%s: %d frames in %s, %.1f MB" % (name, len(numbers), PACK, len(blob) / 1e6))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--take", help="one take from takes.json (default: all)")
    ap.add_argument("--cache", default="/tmp/photo_golfer")
    ap.add_argument("--max-matte", type=int, default=0,
                    help="matte at most this many frames, then stop (run again to go on)")
    args = ap.parse_args()
    os.makedirs(args.cache, exist_ok=True)
    with open(os.path.join(HERE, "takes.json")) as f:
        takes = json.load(f)
    for name, take in takes.items():
        if args.take and name != args.take:
            continue
        build(name, take, args.cache, args.max_matte)


if __name__ == "__main__":
    sys.exit(main())
