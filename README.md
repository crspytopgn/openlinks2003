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
  - Ball physics: flight (drag, Magnus lift, spin), bounce and roll per
    surface, holing out; the club table, swing-to-launch mapping and
    scoring. All with tests.
- `tools/oldump`: a command-line inspector for unknown game files (hex dump,
  entropy, header fields, strings).
- `game/`: a Godot 4.4 project with a playable nine-hole round on a
  placeholder course: the classic three-click Links swing meter, auto club
  selection, putting, water and out-of-bounds penalties, and a scorecard.
  Real courses, objects, golfers and sounds plug in as the formats are
  decoded. See [docs/game-shell.md](docs/game-shell.md) for controls and
  how it fits together.

## Play in the browser

The latest `main` build is published to
**https://crspytopgn.github.io/openlinks2003/** (desktop Chrome, Firefox,
Edge or Safari; needs WebGL 2).

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

See [ROADMAP.md](ROADMAP.md).

## Licence

MIT. See [LICENSE](LICENSE). Links 2003 is a trademark of its respective
owners; this project is not affiliated with or endorsed by them.
