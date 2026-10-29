# OpenLinks2003

An open-source, cross-platform (Windows, macOS, Linux) reimplementation of
**Links 2003**, built with Godot 4 and a portable C++ core.

> **You need your own copy of the original game.** This project contains no
> code, art, audio, course or other data from Links 2003. The engine loads
> assets at runtime from your installed copy. See
> [docs/clean-room.md](docs/clean-room.md).

## Status

Very early. What exists so far:

- `libs/olcore`: a C++17 core library with no dependencies.
  - `BinaryReader`: a little-endian reader for the original file formats.
  - Ball flight physics (gravity, drag, Magnus lift, spin decay) with tests.
- `tools/oldump`: a command-line inspector for unknown game files (hex dump,
  entropy, header fields, strings).
- `game/`: a Godot 4.4 project with a prototype driving range. Press Space to
  hit a drive.

## Download a build

Every push to `main` builds the game for all three platforms. Open the
**Actions** tab, pick the latest successful **CI** run, and download the
artifact for your platform from the bottom of the page.

**macOS:** the build is ad-hoc signed, not notarised. The first time,
right-click the app, choose **Open**, then confirm.

## Building locally

The core library and tools:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

The game: open `game/project.godot` in Godot 4.4 and press F5.

## Layout

```
libs/olcore/    Portable C++ core: file formats, physics (engine-independent)
tools/oldump/   File inspection tool for format reverse engineering
game/           Godot 4 project (scenes, scripts, export presets)
docs/           Clean-room rules and file-format notes
```

## Roadmap

1. Document the original archive and course formats in `docs/formats/`.
2. Course loader in `olcore`, plus a heightmap and surface viewer in Godot.
3. Wire `olcore` into Godot through GDExtension, replacing the GDScript
   physics port.
4. Bounce and roll per surface; tune the physics to match the original.
5. Swing meter, scoring, game modes, golfer animations.

## Licence

MIT. See [LICENSE](LICENSE). Links 2003 is a trademark of its respective
owners; this project is not affiliated with or endorsed by them.
