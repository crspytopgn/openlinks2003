#!/bin/bash
# Fetches every course in bench_list.txt not fetched yet, then their close-ups.
HERE="$(cd "$(dirname "$0")" && pwd)"
while IFS='|' read slug q; do
  [ -f /tmp/bench/$slug.olc ] && continue
  "$HERE/bench_one.sh" "$slug" "$q"
  sleep 2
done < "$HERE/bench_list.txt"
"$HERE/details_all.sh"
