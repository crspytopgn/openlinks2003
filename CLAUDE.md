# OpenLinks2003: instructions for Claude

Open-source, cross-platform reimplementation of Links 2003 (Godot 4.4 plus a
C++17 core). The owner works mostly through cloud sessions, so keep `main`
buildable and CI green.

## Hard rules

- Follow `docs/clean-room.md`. Never commit original game files, decompiled
  code, or large dumps of original data. If the owner shares original files
  in a session, use them only for analysis and write findings into
  `docs/formats/` in your own words.
- Keep `libs/olcore` engine-independent: no Godot headers there.
- Until GDExtension lands, `game/scripts/main.gd` holds a GDScript port of
  `libs/olcore/src/ball_physics.cpp`. Change both together.

## Checks before pushing

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --parallel && ctest --test-dir build --output-on-failure
```

Godot is not installed in the cloud container. Godot changes are validated by
the `export` job in `.github/workflows/ci.yml`, so check that job after
pushing.

## Conventions

- Coordinates: +y up, +z downrange, +x to the golfer's left. SI units.
- C++17, warnings enabled (`-Wall -Wextra -Wpedantic`, `/W4`); keep it
  warning-free.
- GDScript uses tabs and static typing (`:=`, typed parameters).
