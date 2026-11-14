#!/usr/bin/env python3
"""Tracks a filmed golf swing in 3D for footage_take.py.

    pip install mediapipe   (and libegl1 on Linux)
    python3 tools/golfer/track_footage.py VIDEO --name suvichaya_iron \
        --fps 82.5 --phases address=3,start=21,top=93,impact=127,end=195

Runs MediaPipe's pose landmarker (heavy model, downloaded to --cache) on
every frame and writes tools/golfer/footage/<name>.json: per frame the 33
landmarks in metres about the hips. --fps is real-time frames per second
of the video (slow motion counted), --phases the frame numbers of address,
takeaway, top, impact and the end of the finish.

The take in the repo is from "Suvichaya Vinijchaitham Golf Swing Slow Mo
2026" (Wikimedia Commons, CC0): source frames 24 to 411, every second
frame (the photo golfer's clip.mp4), filmed from the golfer's trail side.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

MODEL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("video")
    ap.add_argument("--name", required=True)
    ap.add_argument("--fps", type=float, required=True)
    ap.add_argument("--phases", required=True)
    ap.add_argument("--cache", default="/tmp/footage")
    a = ap.parse_args()
    import mediapipe as mp
    from mediapipe.tasks import python as mpt
    from mediapipe.tasks.python import vision

    os.makedirs(a.cache, exist_ok=True)
    model = os.path.join(a.cache, "pose_landmarker_heavy.task")
    if not os.path.exists(model):
        urllib.request.urlretrieve(MODEL, model)
    tmp = tempfile.mkdtemp(dir=a.cache)
    subprocess.run(["ffmpeg", "-v", "error", "-i", a.video, "-q:v", "2", os.path.join(tmp, "f_%04d.jpg")], check=True)
    opts = vision.PoseLandmarkerOptions(base_options=mpt.BaseOptions(model_asset_path=model),
                                        running_mode=vision.RunningMode.VIDEO, num_poses=1)
    lm = vision.PoseLandmarker.create_from_options(opts)
    world = []
    for k, f in enumerate(sorted(os.listdir(tmp))):
        r = lm.detect_for_video(mp.Image.create_from_file(os.path.join(tmp, f)), int(k * 1000 / 30))
        if not r.pose_world_landmarks:
            world.append(world[-1] if world else None)
            continue
        world.append([[round(p.x, 4), round(p.y, 4), round(p.z, 4), round(p.visibility, 2)]
                      for p in r.pose_world_landmarks[0]])
    phases = {kv.split("=")[0]: int(kv.split("=")[1]) for kv in a.phases.split(",")}
    out = {"meta": {"source": "Suvichaya Vinijchaitham Golf Swing Slow Mo 2026 (Wikimedia Commons, CC0)",
                    "fps": a.fps, "phases": phases, "smooth": 1.5},
           "world": world}
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "footage", a.name + ".json")
    with open(path, "w") as fh:
        json.dump(out, fh, separators=(",", ":"))
    print(path, len(world), "frames")
    os._exit(0)  # mediapipe's shutdown can raise


if __name__ == "__main__":
    sys.exit(main())
