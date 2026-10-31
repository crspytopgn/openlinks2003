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
| Esc | Menu: resume, scorecard, settings (quality, fullscreen, v-sync, anti-aliasing, 3D resolution, field of view), restart, main menu |
| M | Back to the main menu once the round is over |
| F11 | Toggle fullscreen |
| C | Open the course viewer (courses made by `olcourse export`) |

The swing meter is the classic three-click Links arc. Click once to start the
backswing; the marker climbs the left side of the arc towards 100% at the
top. Click again to set power; the marker runs back down. Click a third time
as it crosses the white snap line at the bottom. Early (above the line) pulls
and hooks the ball left, late pushes and slices it right.

The yellow ring shows where a full swing would land (for putts, the hole
distance). Holes run tee to cup, then on to the next. Out of bounds is
stroke and distance. A hole is picked up at 10 strokes.

### Drops

Water costs a stroke and a drop. **D** while aiming declares the ball
unplayable (one stroke; not on the tee or the green), and on a cart path
**F** takes a free drop. The drop menu lists the options (keys 1 to 3), the
ball sits on the default spot, a white ring marks the zone, and the arrow
keys move the ball inside it (Up: towards the pin, Shift: fine, Page Down:
back 10 m). Space or a click drops; Backspace cancels a voluntary drop.
Computer golfers, and a player who just confirms, take the legal drop that
leaves the shortest way to the pin.

| Reason | Penalty | Options |
| --- | --- | --- |
| Water | 1 | Back on the line from the pin through where the ball last crossed into the water; within two club lengths of that point; replay from the last spot |
| Unplayable | 1 | Back on the line from the pin through the ball; within two club lengths of the ball; replay from the last spot. In a bunker the drop stays in the sand |
| Cart path | 0 | Within a club length of the nearest point off the path |

A drop may never be nearer the pin than its reference point, in water, out
of bounds or on the green. This is what Links 2003 enforces (its drop menu,
the free drop on paths, and the "you cannot drop..." refusals); the zone
shapes come from the Rules of Golf (rules 16, 17 and 19), since how Links
draws its own drop corridor isn't known. Courses don't mark water as yellow
or red, so every water hazard offers lateral relief (`LATERAL_WATER` in
`main.gd`). Not done: Links actually drops the ball and lets it roll (and
re-drops when it rolls out of the zone); here it is placed. Links 2003 has
no lost balls, and out of bounds is known at once, so there are no
provisional balls. The rules are `olcore/rules.cpp`, ported to
`game/scripts/rules/drop_rules.gd`.

## Menus and game modes

Once the game files are ready, the boot screen is the main menu: **Play a
round**, the game-file buttons, **Settings** and **Quit** (desktop). Play a
round opens the setup page (`ui/round_setup_panel.gd`): course, tees (back,
middle, forward; courses with one tee box play from it whatever is chosen),
holes (all, front nine, back nine), game mode and one to four players with
names. The choice is a `RoundSetup`, saved under `[round]` in
`user://settings.cfg` with the last course, and handed to the round through
`GolfRound.setup`.

Players share the round in turn (hot seat). On each hole everyone tees off
in order of the honour (the lowest score on the last hole goes first; ties
keep their order), then whoever is furthest from the hole plays. The other
balls stay on the ground where they lie. When the next swing is a different
person's from the last one, the screen dims and names who plays next, with
the hole, shot and distance (`ui/hand_over_panel.gd`); Space, Enter or a
click carries on, and Tab still shows the scorecard. Computer golfers'
turns skip it, so one person against the computer never sees it. Online
play is still a design: [online-play.md](online-play.md). The modes:

| Mode | Players | Scoring |
| --- | --- | --- |
| Stroke play | 1 to 4 | Lowest total |
| Match play | 2 | Hole by hole; ends once the leader can't be caught ("3 & 2") |
| Skins | 2 to 4 | One skin a hole for the outright lowest score; ties carry over |
| Best ball | 3 or 4, two teams | Each team counts its best score per hole |
| Stableford | 1 to 4 | 2 points for par, one more per stroke under, one fewer per stroke over |
| Scramble | 2 to 4, two teams | Everyone on the team hits; the team plays on from the best shot, one stroke per round of shots |
| Alternate shot | 2 to 4, two teams | One ball per team; partners take turns hitting it and take turns on the tee |

In scramble and alternate shot each team plays one ball (its first member's;
the partners' own balls sit out), and every member's card carries the team's
score, so the team rows of the scorecard show it. In a scramble the team
plays on from the shot that leaves the fewest expected strokes
(`OpponentSkill.expected_strokes`), so a person doesn't have to pick; a holed
shot ends the hole at once. Alternate shot counts swings, not penalty
strokes, when deciding whose turn it is. Team rounds don't go on the players'
handicap records. With handicaps, scramble uses 25% and alternate shot 50% of
each player's handicap, off the low, and the team counts its better net
score (a simplification of the WHS team allowances). Computer golfers play
both, taking their turns like anyone else.

`GameModes` (`game_modes.gd`) does the scoring and mirrors the game-mode
functions in `libs/olcore/src/scoring.cpp`. `RoundScoring` holds everyone's
cards and turns them into the HUD status line, the end-of-hole result and the
final standings. The scorecard shows a row per player plus the mode's rows
(points, skin winners, match holes, team best balls).

### Computer opponents

Any seat can be a computer golfer instead of a person ("Who" on the setup
page), so one person can play a match, skins or best ball against the
computer, or watch four computer golfers play. A computer golfer plays through
exactly the same physics as everyone else:

1. **Plan** (`ai/computer_golfer.gd`, `ComputerGolfer`). It tries clubs, aims
   and power through the round's own `ShotModel`, on the real hole, with the
   wind of that shot. Full shots aim at the pin when it is in range (with the
   power to get there) or down the hole's route, then correct twice for wind
   and curve. Putts aim at the hole, paced to finish 35 cm past, and read the
   green from where each try stops (up to eight tries). Where a try ends is
   scored by the strokes still to play from there (`expected_strokes`, rounded
   from published tour "strokes gained" baselines), with a stroke added for
   water and stroke and distance for out of bounds. Golfers with course
   management re-try their three best plans pulled and hooked, pushed and
   sliced, long and short, and take the best average, so they play away from
   water and bunkers. The weekend golfer just goes for the best-looking shot.
2. **Swing** (`ai/opponent_skill.gd`, `OpponentSkill`, ported from
   `libs/olcore/src/opponent.cpp`). The plan becomes swing-meter inputs, and
   the level's mistakes go on those inputs, never on the ball: power, timing
   (hook and slice), line-up, putt pace and putt line errors, the odd duff or
   top, and a strength cap on how hard it can swing. With the Links 2003
   physics, full swings instead get the game's own computer misses
   (`LinksLaunch.computer_miss`, see
   [physics.md](formats/physics.md#computer-golfers-misses)) from the level's
   steadiness rating; putts keep the errors here.

| Level | Driver spread (sd) | 7 iron spread | 8 ft putts holed | Duffs |
| --- | --- | --- | --- | --- |
| Weekend golfer | about 30 m, 80% strength | 12 m | about 35% | 6% |
| Club golfer | 24 m, 88% | 10 m | 47% | 2.5% |
| Scratch golfer | 17 m, 95% | 8 m | 59% | 0.8% |
| Tour pro | 14 m, full | 5 m | 74% | 0.2% |

The spreads are from the stand-in physics on flat ground. The numbers are our
own, set so the levels score roughly like their names; the original game's
computer golfers haven't been measured.

Planning runs as small jobs over a few frames (about 6 ms of work a frame),
so the browser build doesn't stall. The computer spends at least 0.8 s
"thinking", shows its club and line for 1.2 s, then swings; a click hurries it
up. When every seat is a computer, holes move on by themselves after 4 s.
Seeded rounds (`GolfRound.wind_seed`) seed the computer golfers too, so the
tests play the same way every run.
### Handicaps and player profiles

Every finished round of nine holes or more goes on the player's profile,
matched by name (`PlayerProfiles`, saved in `user://profiles.cfg`; the
browser keeps it in IndexedDB). After three rounds the profile gives a
handicap index; until then the player can type a starting index on the setup
page ("12.3", or "+1.4" for a plus handicap). Rounds that stop early, such as
a match won 3 & 2, don't count.

The index follows the World Handicap System, simplified because Links
courses have a stroke index per hole but no course or slope rating: par
stands in for the course rating and every course has the standard slope.

- Each hole is capped at net double bogey (par + 2 + strokes received; par + 5
  without an index) to give the adjusted gross score.
- Score differential = adjusted gross - par, doubled for a nine.
- Index = the lowest 1 to 8 of the most recent 20 differentials, averaged,
  with the WHS adjustment of up to -2.0 for three to six rounds. Between +10.0
  and 54.0.

With "Handicaps: On" in the round setup, each player's playing handicap is
their index scaled to the holes played at the mode's allowance: 95% for
stroke play and Stableford, 100% for match play and skins, 90% for best
ball. Match play, skins and best ball play off the lowest handicap. Strokes
go on the hardest holes first, by the course's stroke index (a nine keeps
the order of the 18). Net scores then decide every mode, and the scorecard
adds a net row under each player, whose label shows their playing handicap.

Computer golfers keep no profile and play off a fixed index for their level
(`RoundSetup.computer_index`): weekend golfer 24.0, club golfer 12.0,
scratch golfer 0.0, tour pro +4.0. The setup page shows it in the player's
index box, so net and Stableford games against them work.

Each round also counts every player's fairways hit (tee shots on par 4s and
5s that finish on the fairway), greens in regulation (on the green, or in
the hole, with two strokes to spare for par) and putts (strokes played from
the green). They go on the round's record and into career totals that keep
counting after old rounds drop off the list.

The main menu's **Players** page (`PlayersPanel`) lists every profile with
its index, rounds and last date. Picking a player shows their career line
(scoring average per 18, fairways, greens in regulation, putts per 18) and
their recent rounds with each round's stats, and stars the rounds the index
counts. Delete asks once more, then removes
the profile.

### Saved rounds

The round in progress is saved before every shot and at the end of each hole
(`SavedRound`, `user://saved_round.cfg`): the setup, everyone's card, the
hole, the honour, whose turn it is and where each ball lies. After quitting
(or closing the game, or the browser tab), the main menu offers **Resume
round** while the saved round's course is among the player's files, and the
round carries on from that shot. The wind is drawn again. Finishing the round
clears the save, and starting a new round replaces it.

`Handicap` (`handicap.gd`) mirrors the handicap functions in
`libs/olcore/src/scoring.cpp`; indexes and differentials are in tenths of a
stroke so both sides round the same way.

## Code map

```
game/scripts/
  boot.gd                       Game files, main menu and round setup
  main.gd                       GolfRound: the round state machine, turns, camera, HUD wiring
  scorecard.gd                  Scorecard (mirrors olcore/scoring)
  game_modes.gd                 GameModes: match, skins, best ball, Stableford (mirrors olcore/scoring)
  round_setup.gd                RoundSetup: course, tees, holes, mode and players for a round
  round_scoring.gd              RoundScoring: everyone's cards read in the chosen mode
  ai/
    computer_golfer.gd          ComputerGolfer: plans a computer opponent's shots through the ShotModel
    opponent_skill.gd           OpponentSkill: skill levels and swing mistakes (port of olcore/opponent)
  round_scoring.gd              RoundScoring: everyone's cards read in the chosen mode, gross or net
  handicap.gd                   Handicap: strokes per hole, net scores, the index (mirrors olcore/scoring)
  player_profiles.gd            PlayerProfiles: each player's rounds and handicap index
  saved_round.gd                SavedRound: the round in progress, for Resume round
  physics/
    shot_model.gd               ShotModel: the physics interface the round uses
    standard_shot_model.gd      StandardShotModel: the stand-in model below
    links_shot_model.gd         LinksShotModel: the stand-in with the game's own flight, bounce and roll
    links_aero.gd               LinksAero: that flight model (port of olcore/links_flight)
    links_ground.gd             LinksGround: its bounce and roll (port of olcore/links_ground)
    wind.gd                     Wind: conditions for the round, hole and shot
    ball_physics.gd             BallPhysics: GDScript port of olcore ball_physics + shot
    swing.gd, club.gd           Swing-meter-to-launch mapping and the club table
    surface.gd                  Surface types and per-surface constants
    obstacle_field.gd           ObstacleField: trunks, canopies and walls (port of olcore/obstacles)
    ball_state.gd, shot_result.gd, flat_terrain.gd
  course/
    course_loader.gd            CourseLoader: interface for the .CRZ decoder
    course_data.gd, hole_data.gd, placed_object.gd
    course_terrain.gd           CourseTerrain: height, surface and mesh for a hole
    course_objects.gd           CourseObjects: a .CRZ's plants, 3D objects and spectators,
                                drawn per hole and turned into obstacles
    placeholder_*.gd            The procedural nine-hole stand-in course
  assets/
    asset_providers.gd          AssetProviders: where real decoders get registered
    object_library.gd           ObjectLibrary: interface for OBJECT.LIB and friends
    golfer_assets.gd, golfer_rig.gd   interfaces for the golfer model and animation
    sound_bank.gd               SoundBank: interface for game audio
    free_golfer.gd              FreeGolfer: the CC0 MakeHuman golfer (assets/golfer/free_golfer.glb)
    placeholder_*.gd            Primitive trees, a hand-animated figure golfer
  ui/
    swing_meter.gd, hud.gd, scorecard_panel.gd, wind_indicator.gd
    hud_art.gd, info_bar.gd, shot_panel.gd, shot_windows.gd   the original interface (below)
    round_setup_panel.gd, players_panel.gd, pause_menu.gd, settings_panel.gd, menu_style.gd
    hand_over_panel.gd          HandOverPanel: the hot-seat "pass the controls" screen
  designer/                     The course designer (docs/course-designer.md)
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
other descriptor files aren't needed) and indexes the GAME files under
Setup's long names without copying anything. Reads come straight from the
picked images. Where the File System Access API exists (Chrome, Edge), the
file handles and index are kept in IndexedDB so the next visit only needs the
player's OK. `WebGameFiles.copy_startup_files()` copies the few files read
before a round (`startup_files()`: object catalog, sound effects, course key,
standard ground textures, one golfer, plus the objects standing in for the
placeholder trees) into the in-memory filesystem at `/tmp/links2003`, which
becomes `GameFolder.override_path`. Courses (about 100 MB each) are copied
only when chosen. `node game/web/tests/test_game_files.mjs` tests the script against
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

## The original interface

With the player's own `GRAPHICS.LS`, the Classic Links presentation draws
its interface from the game's art (`HudArt` in `game/scripts/ui/hud_art.gd`
loads it; without the file the HUD keeps its plain look):

- Top left, one chrome info bar per line of shot information
  (`CRSINFO.TGA`, `InfoBar`), lettered in the game's font (`SPBT14.D3F`,
  [d3f.md](formats/d3f.md)).
- Bottom centre, the classic swing bar (`RIND12.TGA`, `SwingMeter`).
- Bottom left (`ShotPanel`), the PowerStroke title bar and the row for the
  club's kind (`PSTROKE1.TGA`), the club's name and reach in a stone window
  (`LIEBOX.TGA`), and under them the swing indicator gizmo with the club at
  the ball (`SIGRDR12`, `SIGRIR12`, `SIGRPT12.TGA` for woods, irons and the
  putter).
- Top right (`ShotWindows`), the wind window with the game's arrow
  (`WINDDIR.TGA`) turned to the wind, the elevation window with the
  `ELEV00` to `ELEV12` picture for the aim point's height above the ball,
  and the lie window with the lie and how much distance it allows.

What's measured and what's guessed: the pieces' rectangles in their sheets
are measured from the sheets' alpha, and the fonts and their metrics come
straight from the files. Where the game places each piece on screen, the
feet per elevation picture (5 here) and what the red-ringed gizmo variants
(`SIRD*`), the `HV*` and `EZ*` sheets, `SISYMB*` (shot-shape arrows and
tempo lights) and the `SI*.SHR` sprites are for aren't in the files; a
screenshot of the running game would settle them. `CLUBICNS.TGA` is loaded
but not placed yet.

## Broadcast presentation

Settings > Presentation switches between **Classic Links**, which frames
and dresses the round like Links 2003, and **Broadcast** (the default),
which presents it like a TV golf broadcast. Only the presentation changes:
the physics, the swing and the scoring are the same in both.

- `scripts/broadcast/shot_director.gd`: the camera director. It plans the
  cuts for each shot (behind the player, then a chase or side-on camera,
  then a landing camera or a camera behind the green looking back at the
  ball) and `RoundCamera` follows it. Putts get a low tracking camera.
- `RoundCamera.start_flyover()`: each hole opens with a flight from behind
  the tee, along the hole's route, down to the green. A click skips it.
- `scripts/broadcast/ball_tracer.gd`: the shot tracer, a camera-facing
  glowing ribbon.
- Replays: R between shots (and automatically after a holed approach, a
  long holed putt or a shot to tap-in range) plays the shot again from new
  camera angles, in slow motion round the landing and the cup.
- `scripts/broadcast/green_grid.gd`: on the green, a grid draped over the
  real terrain, coloured by slope, with downhill ticks. G hides it. It
  shows the slopes, not the putt's line.
- `scripts/broadcast/broadcast_overlay.gd`: the TV graphics, drawn from
  plain shapes: the score bug, the shot panel, a lower third as each player
  steps up, the shot card (carry, roll, total, height, lie, to the pin), the
  hole card with a map (`hole_map.gd`), the LIVE and REPLAY bugs, camera
  tags, captions, the scrolling ticker (the leaderboard with more than one
  player), wipes, and a pin-camera picture on approach shots (Medium quality
  and up, since it draws the scene twice).
- `scripts/broadcast/commentary.gd`: caption lines and the crowd reaction
  for each shot. The crowd sounds are `crowd_cheer`, `crowd_roar`,
  `crowd_groan` and `crowd_ooh` (the tournament bank with the game files,
  recorded crowds from `FreeSoundBank` without them).

In both presentations, scene changes fade through black and menu panels fade
in (`scripts/ui/scene_fade.gd`).

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
  `LinksGolferAssets` (`scripts/golfer/`) is used automatically when a game
  folder is configured: the original skinned, textured golfer and clubs as a
  `Skeleton3D`, driven by the original clips. Without a game folder,
  `PlaceholderGolferAssets` gives `FreeGolfer`: a realistic man built from
  MakeHuman's CC0 assets by `tools/golfer/build_free_golfer.py`, with the
  swing, putt and celebration keyed by hand and baked into
  `game/assets/golfer/free_golfer.glb` (licence in `LICENSE.md` next to it).
  If that file is missing it falls back to `PlaceholderGolfer`, the figure
  built from primitives.
- **Audio:** subclass `SoundBank` (`play(event)`, and optionally
  `play_detail(event, detail)`) and set
  `AssetProviders.sound_bank_factory` to a callable that builds it. Events:
  `&"hit"` (with the club, lie and power), `&"putt"`, `&"land"` (with the
  surface and speed), `&"cup"`, `&"splash"`, `&"applause"`, `&"footsteps"`,
  `&"club"` and the crowd reactions (see `sound_bank.gd`).
  `LinksSoundBank` (`scripts/audio/`) is used automatically when a game
  folder is configured (see `scripts/game_folder.gd`); it plays the
  original effects from `predefined.ssf`. Without the game files
  `FreeSoundBank` plays real recordings from `game/assets/sounds/` (CC0
  and CC BY field recordings from freesound.org, cut and mixed by
  `tools/audio/build_free_sounds.py` from `tools/audio/free_sounds.json`;
  credits in `game/assets/sounds/CREDITS.md`): a strike per club kind
  (driver, fairway wood or hybrid, iron, wedge) with turf, grass or sand
  layered in by lie, landings by surface and the crowd takes, each played
  with a little random pitch and level. Courses with no ambient sounds of
  their own get `FreeAmbience`: a looping bed picked from the course name
  (parkland, woodland, seaside, desert), wind in the trees that follows the
  wind, and running water on holes with water near the tee. Menu buttons
  click with `ui_click.ogg`.
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
- **Obstacles:** `CourseTerrain.obstacle_hit()` (`Terrain::obstacle_hit` in
  C++) reports the first trunk, canopy or wall a flight or roll step enters.
  A solid keeps 35% of the speed into its face and 75% along it; a canopy
  keeps 20% and drops the ball; a ball that settles on a flat top (a wall,
  a bridge) stays there. Rolling balls ignore canopies.
- **Wind:** drag and lift use the ball's velocity through the air, so a
  uniform wind (`BallParams::wind`, the `wind` argument in GDScript) slows,
  carries or pushes the ball sideways. It does not act on a rolling ball.
  `Wind` (`scripts/physics/wind.gd`) picks the conditions: a prevailing
  direction for the round, a speed and a shift for each hole, and a small
  change between shots, scaled by the Wind setting (Off, Light, Moderate,
  Strong).
- **Clubs:** tour-average launch monitor data (ball speed, launch angle,
  spin) for driver to pitching wedge; wedges and putter are estimates.

When the game folder has the executable, `LinksShotModel` replaces
`StandardShotModel` and plays the whole shot with the game's own model:
flight (`LinksAero`, `olcore/links_flight.hpp`) and bounce and roll
(`LinksGround`, `olcore/links_ground.hpp`); see
[formats/physics.md](formats/physics.md). The launch stays as above, and
trees, the cup, water and out of bounds use our own handling.

Apart from that model, none of these constants come from Links 2003. Tuning them against the
original game is the "(needs data)" item in the roadmap. `run_tests.gd` checks
the GDScript port against numbers from the C++ tests, so change both
together.

## Not done yet

Gusts during a flight, wind that changes with height, lie-specific animations,
camera styles from the original, computer opponents, and the real-time mouse swing.
