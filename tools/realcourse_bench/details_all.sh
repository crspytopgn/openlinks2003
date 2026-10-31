#!/bin/bash
# Close-up photos round every pin of each benchmark course.
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT=${GODOT:-godot}
cd "$HERE/../.."
for f in /tmp/bench/*.olc; do
  s=$(basename $f .olc)
  [ -f /tmp/bench/$s.details.json ] && continue
  timeout 600 "$GODOT" --headless --path game -s "$HERE/bench_details.gd" -- $s 2>&1 | grep -E "details|no detail"
done
