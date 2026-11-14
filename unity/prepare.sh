#!/usr/bin/env bash
# Gathers the trial's inputs into Assets/Trial/Fetched (none are committed):
# the free textures and sky (tools/fetch_free_assets.py), the course and the
# golfer's mocap from game/assets, a Rocketbox person (MIT), and olcore for
# the target: Linux64 or Win64 (a shared library) or WebGL (sources).
#   unity/prepare.sh Linux64|Win64|WebGL
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root="$here/.."
target=${1:-Linux64}
f="$here/Assets/Trial/Fetched"
mkdir -p "$f/free"

if [ ! -f "$f/free/grass_albedo.jpg" ]; then
  python3 "$root/tools/fetch_free_assets.py" --out "$f/free"
fi
rm -f "$f/free/"*.import "$f/free/"*.olsky
python3 - "$f/free" <<'PY'
import os, sys
from PIL import Image
d = sys.argv[1]
rgb = Image.open(os.path.join(d, "twig_albedo.jpg")).convert("RGB")
a = Image.open(os.path.join(d, "twig_opacity.png")).convert("L").resize(rgb.size)
rgb.putalpha(a)
rgb.save(os.path.join(d, "twig.png"))
PY

cp "$root/game/assets/courses/home.olc" "$f/home.olc.bytes"
cp "$root/game/assets/golfer/free_golfer.glb" "$f/free_golfer.glb.bytes"

person=Male_Adult_14
rb="$f/Rocketbox/$person"
src="https://cdn.jsdelivr.net/gh/microsoft/Microsoft-Rocketbox@master/Assets/Avatars/Adults/$person"
get() {
  for i in 1 2 3 4 5; do
    curl -sSfL -o "$2" "$1" && return 0
    sleep $((i * 3))
  done
  echo "could not fetch $1" >&2
  return 1
}
mkdir -p "$rb/Export" "$rb/Textures"
[ -f "$rb/Export/$person.fbx" ] || get "$src/Export/$person.fbx" "$rb/Export/$person.fbx"
for t in $(grep -aoE '[A-Za-z0-9_]+\.tga' "$rb/Export/$person.fbx" | sort -u); do
  [ -f "$rb/Textures/$t" ] || get "$src/Textures/$t" "$rb/Textures/$t"
done

rm -rf "$here/Assets/Plugins"
case "$target" in
  WebGL)
    python3 "$here/Native/flatten.py" "$here/Assets/Plugins/WebGL/olcore"
    ;;
  Linux64|Win64)
    tmp=$(mktemp -d)
    python3 "$here/Native/flatten.py" "$tmp"
    mkdir -p "$here/Assets/Plugins/x86_64"
    if [ "$target" = Linux64 ]; then
      g++ -std=c++17 -O2 -Wall -Wextra -Wpedantic -shared -fPIC -fvisibility=hidden \
        -o "$here/Assets/Plugins/x86_64/libolcore_unity.so" "$tmp"/*.cpp
    else
      x86_64-w64-mingw32-g++ -std=c++17 -O2 -Wall -Wextra -shared -static -static-libgcc -static-libstdc++ \
        -o "$here/Assets/Plugins/x86_64/olcore_unity.dll" "$tmp"/*.cpp
    fi
    rm -rf "$tmp"
    ;;
  *) echo "unknown target $target" >&2; exit 1 ;;
esac
echo "prepared for $target"
