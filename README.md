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
  - Readers for `LSls` archives (`.LS`, `.L3`) with their LZW compression,
    `.SSF` sound banks, WAV (PCM and MS ADPCM), and the object store behind
    golfer models and animation clips.
  - Ball physics: flight (drag, Magnus lift, spin), bounce and roll per
    surface, holing out; the club table, swing-to-launch mapping and
    scoring. All with tests.
- `tools/oldump`: a command-line inspector for game files (hex dump,
  entropy, strings) that also lists and extracts archives and sound banks.
- `tools/cdimage`, `tools/lsarchive`: Python scripts that read files straight
  from your disc images and unpack archives and sound banks.
- `game/`: a Godot 4.4 project with a playable nine-hole round on a
  placeholder course: the classic three-click Links swing meter, auto club
  selection, putting, water and out-of-bounds penalties, and a scorecard.
  Real courses, objects, golfers and sounds plug in as the formats are
  decoded. See [docs/game-shell.md](docs/game-shell.md) for controls and
  how it fits together.

## Using your game files

Point the game at your Links 2003 files (the install folder, the `GAME`
folder from CD 1, or a folder you extracted with `tools/cdimage`) with
`--links-dir=/path/to/folder` on the command line, the `LINKS2003_DIR`
environment variable, or `folder=` under `[game]` in `user://settings.cfg`.
The round then plays the original swing, landing, cup and splash sounds,
and your golfer (the first archive in `POLYANI`, or set `golfer=ERIC.L3`
under `[game]`) appears as the original textured model, holding the
driver or putter, and swings with the original animations. The browser
build can't read local folders yet.

## Play in the browser

The latest `main` build is published to
**https://crspytopgn.github.io/openlinks2003/** (desktop Chrome, Firefox,
Edge or Safari; needs WebGL 2).

It plays with placeholder content out of the box. To use the real courses,
textures, objects and sounds, choose **Load disc images** on the first screen
and pick your own Links 2003 disc images (`.b6i`, `.iso` and other formats,
from any drive), or **Load a game folder** for an installed copy. The files
are read where they are, on your own computer: nothing is copied or uploaded,
and the site itself hosts no game data. Chrome and Edge remember your choice
and only ask to allow access again next time; other browsers ask you to pick
the files again. **Forget my files** clears the remembered choice.

## Download a build

Every push to `main` builds the game for all three platforms and publishes
it as the **[latest release](https://github.com/crspytopgn/openlinks2003/releases/tag/latest)**
(macOS universal, Windows, Linux). The builds contain no game data.

**macOS:** the build is ad-hoc signed, not notarised. Unzip it, move
OpenLinks2003.app to Applications, then right-click it, choose **Open**, and
confirm. On macOS 15 or later, if it still won't open, go to **System
Settings > Privacy & Security** and click **Open Anyway**.

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
tools/cdimage/  Reads files from raw CD images (.b6i, .iso)
tools/mac/      Installs and wraps the original game for macOS under Wine
tools/lsarchive/ Lists and extracts LSls archives and .SSF sound banks
game/           Godot 4 project (scenes, scripts, export presets)
docs/           Clean-room rules and file-format notes
```

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## Supporting the project

OpenLinks2003 is free and always will be. If you enjoy it and want to chip in,
you can [sponsor it on GitHub](https://github.com/sponsors/crspytopgn).

## Licence

MIT. See [LICENSE](LICENSE). Links 2003 is a trademark of its respective
owners; this project is not affiliated with or endorsed by them.
