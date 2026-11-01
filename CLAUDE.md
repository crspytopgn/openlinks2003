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
  `obstacles.cpp`, `links_aero.gd` ports `links_flight.cpp` and
  `links_ground.gd` ports `links_ground.cpp`, `links_launch.gd` ports
  `links_launch.cpp` the same way, `links_mouse.gd` ports `links_mouse.cpp`, `links_objects.gd` ports
  `links_objects.cpp`, and
  `game/scripts/game_modes.gd` ports the game-mode half of `scoring.cpp`
  and `game/scripts/handicap.gd` its handicap functions.
  `game/scripts/ai/opponent_skill.gd` ports `opponent.cpp`, and
  `game/scripts/rules/drop_rules.gd` ports `rules.cpp`.
  `game/scripts/course/terrain_mappings.gd` ports `terrain_mapping.cpp`
  and `game/scripts/course/shadow_file.gd` ports `shadow_file.cpp`.
- Decoders plug into the game through the interfaces in `docs/game-shell.md`
  (`CourseLoader`, `ObjectLibrary`, `GolferAssets`, `SoundBank`,
  `ShotModel`), registered with `AssetProviders`.
- `game/scripts/audio/ssf_bank.gd` (`ssf.cpp`, `wav.cpp`) and
  `game/scripts/data/` (`ls_archive.cpp`, `lzw.cpp`, `carrera_store.cpp`,
  `golfer_anim.cpp`, `golfer_mesh.cpp`, `d3f.cpp`) are GDScript ports; change both sides
  together. So are the parsers in `game/scripts/course/course_objects.gd`
  (`course_objects.cpp`) and `game/scripts/course/course_areas.gd`
  (`course_areas.cpp`).

- `launcher/` is a separate small Godot project: the desktop launcher
  (docs/launcher.md). It writes the game's `user://settings.cfg` keys, so
  keep `launcher/scripts/game_config.gd` in step with
  `game/scripts/graphics/graphics_settings.gd` (look and quality go through
  `[launcher]`, see `apply_launcher_requests`). Its tests are
  `launcher/tests/run_tests.gd`, run by the CI `export` job.

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
