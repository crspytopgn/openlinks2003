# OpenLinks2003: instructions for Claude

Open-source, cross-platform reimplementation of Links 2003 (Godot 4.4 plus a
C++17 core). The owner works mostly through cloud sessions, so keep `main`
buildable and CI green.

Work items and their order live in `ROADMAP.md`. Tick items off as they land,
and don't start a "(needs data)" item on guesses.

## Hard rules

- Follow `docs/clean-room.md`. Never commit original game files, decompiled
  code, or large dumps of original data. If the owner shares original files
  in a session, use them only for analysis and write findings into
  `docs/formats/` in your own words.
- Keep `libs/olcore` engine-independent: no Godot headers there.
- Until GDExtension lands, `game/scripts/physics/` holds a GDScript port of
  `libs/olcore` (`ball_physics.cpp`, `shot.cpp`, `swing.cpp`, `scoring.cpp`).
  Change both together; `game/tests/run_tests.gd` checks the port against
  numbers printed by the C++ tests. `obstacle_field.gd` ports
  `obstacles.cpp` the same way.
- Decoders plug into the game through the interfaces in `docs/game-shell.md`
  (`CourseLoader`, `ObjectLibrary`, `GolferAssets`, `SoundBank`,
  `ShotModel`), registered with `AssetProviders`.
- `game/scripts/audio/ssf_bank.gd` (`ssf.cpp`, `wav.cpp`) and
  `game/scripts/data/` (`ls_archive.cpp`, `lzw.cpp`, `carrera_store.cpp`,
  `golfer_anim.cpp`, `golfer_mesh.cpp`) are GDScript ports; change both sides
  together. So are the parsers in `game/scripts/course/course_objects.gd`
  (`course_objects.cpp`).

## Checks before pushing

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --parallel && ctest --test-dir build --output-on-failure
```

Godot is not installed in the cloud container. Godot changes are validated by
the `export` job in `.github/workflows/ci.yml` (headless GDScript tests, then
the exports), so check that job after pushing. Locally:
`godot --headless --path game --import` then
`godot --headless --path game -s res://tests/run_tests.gd`.

## Web build

The Web export runs single-threaded (no SharedArrayBuffer, so it works on
GitHub Pages) with the Compatibility renderer. Anything used in `game/` must
work in both Forward+ and Compatibility. GDExtension is off for Web until
olcore is also built for wasm.

## Conventions

- Coordinates: +y up, +z downrange, +x to the golfer's left. SI units.
- C++17, warnings enabled (`-Wall -Wextra -Wpedantic`, `/W4`); keep it
  warning-free.
- GDScript uses tabs and static typing (`:=`, typed parameters).
