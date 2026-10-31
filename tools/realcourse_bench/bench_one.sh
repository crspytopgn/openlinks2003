#!/bin/bash
# Fetches one course for the benchmark into /tmp/bench: bench_one.sh slug "search words"
# OSM data comes from the OSM API (served locally as an Overpass answer), so
# a busy Overpass server doesn't matter. Dev tool only; nothing is committed.
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT=${GODOT:-godot}
slug=$1; q=$2
mkdir -p /tmp/bench
python3 -I "$HERE/bench_osm.py" "$slug" "$q" > /tmp/bench/$slug.log 2>&1 || { echo "$slug osm failed"; exit 1; }
port=$((8800 + RANDOM % 100))
python3 -I "$HERE/serve.py" /tmp/bench/${slug}_op.json $port & sp=$!
sleep 1
cd "$HERE/../.."
SLUG=$slug OVERPASS=http://127.0.0.1:$port timeout 600 "$GODOT" --headless --path game -s "$HERE/bench_fetch.gd" -- "$q" >> /tmp/bench/$slug.log 2>&1
kill $sp
grep -E "BUILT|FAILED" /tmp/bench/$slug.log | cut -c1-300 | sed "s/^/$slug: /"
