#!/bin/bash
# Measures how MediaPipe's face landmarks relate to the golfer's, for the
# player creator's face from a photo (PlayerFaceFit's OFFSET, GAIN, WEIGHT and
# REGULARISE): renders golfers with known faces, finds their landmarks in
# headless Chromium, fits, and prints the constants. Rerun after changing the
# golfer's face shapes or PlayerFaceFit's landmarks or measurements.
#
# Needs Godot 4.4, xvfb-run, Node with Playwright and Chromium, and network
# access to jsDelivr and Google's model storage (MediaPipe's code and model).
# Usage: tools/golfer/face_calibration.sh [work folder]
set -euo pipefail
cd "$(dirname "$0")/../.."
work="${1:-$(mktemp -d)}"
mkdir -p "$work"
godot --headless --path game --import > /dev/null 2>&1 || true
xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-method gl_compatibility \
  --resolution 720x720 -s res://tests/face_calibration_render.gd -- "$work" 2>&1 | grep -E "rendered|ERROR"
NODE_PATH="$(npm root -g)" node tools/golfer/face_calibration.mjs "$work"
godot --headless --path game -s res://tests/face_calibration_fit.gd -- "$work" 2>&1 | grep -vE "^Godot Engine|^$"
