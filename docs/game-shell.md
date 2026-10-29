# Game shell

The playable round in `game/`: hole flow, the swing meter, ball physics,
scoring, and the interfaces that decoded original data plugs into. Until the
decoders land, everything runs on placeholders, so the game is playable in
the browser and on desktop today.

## Playing

| Input | Action |
| --- | --- |
| Left / Right | Aim (hold Shift for fine aim) |
| Up / Down | Change club (the game picks one for you each shot) |
| Space or left click | Swing meter: start, set power, set accuracy |
| Space or left click | Skip the ball flight, continue after a shot |
| Tab | Show or hide the scorecard |
| Esc | Settings: quality, fullscreen, v-sync, anti-aliasing, 3D resolution, field of view |
| F11 | Toggle fullscreen |
| C | Open the course viewer (courses made by `olcourse export`) |

The swing meter is the classic three-click Links arc. Click once to start the
backswing; the marker climbs the left side of the arc towards 100% at the
top. Click again to set power; the marker runs back down. Click a third time
as it crosses the white snap line at the bottom. Early (above the line) pulls
and hooks the ball left, late pushes and slices it right.

The yellow ring shows where a full swing would land (for putts, the hole
distance). Holes run tee to cup, then on to the next. Water costs a stroke
and a drop on the line of flight; out of bounds is stroke and distance. A
hole is picked up at 10 strokes.

## Code map

```
game/scripts/
  main.gd                       GolfRound: the round state machine, camera, HUD wiring
  scorecard.gd                  Scorecard (mirrors olcore/scoring)
  physics/
    shot_model.gd               ShotModel: the physics interface the round uses
    standard_shot_model.gd      StandardShotModel: the stand-in model below
    ball_physics.gd             BallPhysics: GDScript port of olcore ball_physics + shot
    swing.gd, club.gd           Swing-meter-to-launch mapping and the club table
    surface.gd                  Surface types and per-surface constants
    ball_state.gd, shot_result.gd, flat_terrain.gd
  course/
    course_loader.gd            CourseLoader: interface for the .CRZ decoder
    course_data.gd, hole_data.gd, placed_object.gd
    course_terrain.gd           CourseTerrain: height, surface and mesh for a hole
    placeholder_*.gd            The procedural nine-hole stand-in course
  assets/
    asset_providers.gd          AssetProviders: where real decoders get registered
    object_library.gd           ObjectLibrary: interface for OBJECT.LIB and friends
    golfer_assets.gd, golfer_rig.gd   interfaces for the golfer model and animation
    sound_bank.gd               SoundBank: interface for game audio
    placeholder_*.gd            Primitive trees, capsule golfer, synthesised sounds
  ui/
    swing_meter.gd, hud.gd, scorecard_panel.gd
game/tests/run_tests.gd         Headless tests, including an auto-played full round
```

## Game files and the boot screen

`scenes/boot.tscn` is the first scene. On desktop it asks once for the
player's Links 2003 folder (saved as `[game] folder` in `user://settings.cfg`)
and offers the courses found in it. In the browser, `WebGameFiles`
(`game/scripts/web/`) drives `game/web/game_files.js`: the player picks disc
images or a folder, the script walks the ISO 9660 tracks itself (cooked,
raw or raw-plus-subchannel sectors, as `tools/cdimage/cdimage.py` does, and
scans for the volume when the pregap is unusual, so BlindWrite .b6t and
other descriptor files aren't needed), stores the GAME files in
IndexedDB under Setup's long names, and on later visits copies them into the
in-memory filesystem at `/tmp/links2003`, which becomes
`GameFolder.override_path`. Courses (about 100 MB each) are copied only when
chosen. `node game/web/tests/test_game_files.mjs` tests the script against
synthetic disc images made by `game/web/tests/make_test_iso.py`.

The chosen course path is passed to the round through
`GolfRound.chosen_course`; any `CourseLoader` registered with `AssetProviders`
that accepts the path loads it.

## Graphics

`Scenery` (`game/scripts/graphics/scenery.gd`) owns the sky, sun, fog and
post-processing; `GraphicsSettings` holds the quality options and saves them
to `user://settings.cfg` under `[graphics]`. Shadows (cascade count, distance,
atlas size, softness), glow, SSAO and SSIL follow the quality level. The
screen-space effects only run on Forward+; the web build (Compatibility)
starts at Medium with FXAA.

The public build looks better with free photographic art: CI runs
`tools/fetch_free_assets.py`, which downloads CC0 ground textures (grass,
rough, sand; 1K albedo and normal maps) and a 2K HDR sky from
[Poly Haven](https://polyhaven.com) into `game/free_assets/`. They aren't
committed. `FreeAssets` loads them, `Materials.terrain()` blends them by the
rough and sand weights in the mesh's UV2 (`Materials.terrain_weights()`), and
`Scenery` uses the sky as a panorama. Without them the game falls back to the
procedural sky and shading. `game/free_assets/CREDITS.md` names the assets
used. Run the script once locally to see the same look on desktop.

Course meshes should use `Materials.terrain()` (vertex colour for the surface,
plus noise variation and close-up detail) and `Materials.water_disc()` for
ponds, so decoded courses match the placeholder. CI renders real frames with
Mesa on both renderers (`game/tests/render_check.gd`) to catch shader errors,
and uploads the screenshots as the `render-check` artifact.

## Plugging in decoded data

Each decoder implements one small interface and registers it with
`AssetProviders` before the round starts (for example from an autoload).
Nothing in the round needs to change.

- **Courses (.CRZ):** subclass `CourseLoader` (`can_load(path)`,
  `load_course(path) -> CourseData`) and call
  `AssetProviders.register_course_loader(...)`. A course is a list of
  `HoleData` (par, tee, pin, route, placed objects) whose `terrain` is a
  `CourseTerrain`: `height_at(x, z)`, `surface_at(x, z)` returning a
  `Surface.Type`, and `build_visual()` for the mesh. Set
  `GolfRound.course_path` to the course file. `CrzCourseLoader`
  (`course/crz_course_loader.gd`, registered by default) does this for the
  game's own `.CRZ` and `.RNG` courses: it finds the cipher key in
  `LINKSM_1.EXE` through `GameFolder`, keeps it in `user://crz_keys.cfg`,
  and caches decoded terrain in `user://course_cache/`. Its `CrzTerrain`
  takes heights from the course mesh and surfaces from the ground classes in
  `TerrainTypes`; anywhere off the mesh is out of bounds. Hazard and OB
  outlines (`Shapes`) and objects are not wired in yet.
- **Objects:** subclass `ObjectLibrary` (`instantiate(id) -> Node3D`) and
  set `AssetProviders.object_library`. `PlacedObject.id` is whatever key the
  library understands. `DecodedObjectLibrary.open(game_folder)` (in
  `assets/decoded_object_library.gd`) already does this for the real
  Course Designer objects; it accepts an OBJECT.LIB id as a decimal string or
  a catalog file name. It is not registered by default yet, because the
  placeholder course uses its own ids; the course decoder should register it
  together with real placements.
- **Golfer:** subclass `GolferAssets` (`create_golfer() -> GolferRig`) and
  set `AssetProviders.golfer_assets`. `GolferRig.play()` receives
  `&"address"`, `&"backswing"`, `&"swing"`, `&"putt"` and `&"celebrate"`.
- **Audio:** subclass `SoundBank` (`play(event)`) and set
  `AssetProviders.sound_bank_factory` to a callable that builds it. Events:
  `&"hit"`, `&"putt"`, `&"land"`, `&"cup"`, `&"splash"`, `&"applause"`.
  `LinksSoundBank` (`scripts/audio/`) is used automatically when a game
  folder is configured (see `scripts/game_folder.gd`); it plays the
  original effects from `predefined.ssf`.
- **Physics:** subclass `ShotModel` (`launch(...)`, `simulate(...)`) and set
  `AssetProviders.shot_model`. This is where a model tuned against the
  original game, or the C++ core through GDExtension, replaces the stand-in.

Coordinates everywhere: +y up, +z downrange, +x to the golfer's left, metres.

## The stand-in physics

Published real-world golf ball physics, implemented in
`libs/olcore` (`ball_physics.cpp`, `shot.cpp`, `swing.cpp`) and ported to
GDScript in `game/scripts/physics/ball_physics.gd`:

- **Flight:** gravity, drag with Cd = 0.24 + 0.18 S and Magnus lift with
  CL = -0.05 + sqrt(0.0025 + 0.36 S) (capped at 0.35), where S is the spin
  ratio r|w|/|v| (Smits and Smith's fits), RK4 at 4 ms.
- **Bounce:** a rigid-sphere impulse model. Turf restitution follows Penner's
  fit e = 0.510 - 0.0375 v + 0.000903 v^2 (0.12 above 20 m/s), and the ball
  meets a crater wall tilted back by Penner's 15.4 deg x (v/18.6) x
  (angle/44.4). Coulomb friction pushes the contact point towards rolling
  without slipping, which is what checks a wedge on the green.
- **Roll:** 5/7 g along the slope for a rolling solid sphere, plus rolling
  resistance per surface. Green resistance gives roughly a Stimp 10 green.
- **Clubs:** tour-average launch monitor data (ball speed, launch angle,
  spin) for driver to pitching wedge; wedges and putter are estimates.

None of these constants come from Links 2003. Tuning them against the
original game is the "(needs data)" item in the roadmap. `run_tests.gd` checks
the GDScript port against numbers from the C++ tests, so change both
together.

## Not done yet

Wind, trees and other objects the ball can hit, lie-specific animations,
camera styles from the original, menus, and the real-time mouse swing.
