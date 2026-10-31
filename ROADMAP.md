# Roadmap

Ordered by dependency. Items marked **(needs data)** need sample files or
measurements from an installed copy of the original game; don't start them
on guesses, because the details come from the data.

## Data available

The owner's English discs (three BlindWrite `.b6i` images) and the v1.07
patch have been surveyed. No install is needed: `tools/cdimage/cdimage.py`
reads files straight from the images. See
[docs/formats/inventory.md](docs/formats/inventory.md) for what each file
type holds. Items below that only need files from the discs are now
unblocked; items that need measurements from the running game (tuning,
feel) still need a working install.

## Phase 1: formats (see `docs/formats/`)

- [x] Inventory the install folder: file types, counts, sizes (`docs/install-listing/`, `docs/formats/inventory.md`)
- [ ] Container formats: `LSls` archives, `ARC0` zlib archives, chained-zlib `.CRZ` courses **(unblocked: samples on CD1 to CD3)**. `ARC0` and `.CRZ` are done; `.CRZ` turned out to be an encrypted ARC0 ([crz.md](docs/formats/crz.md))
  - [x] `LSls` archives and their LZW compression ([ls-archive.md](docs/formats/ls-archive.md), `olcore::LsArchive`)
- [ ] Course format: terrain, surface types, holes, tees, pins, hazards, OB **(unblocked: six `.CRZ` courses on CD2, 39 `.CVT`)**. Done: terrain mesh, materials, textures, holes, tees, pins, ground classes (`TerrainTypes`). Still to do: the surface physics values, hazards and OB (`Shapes`), texture mappings
  - [x] The 39 converted Links LS courses (`.CVT`): holes, terrain and surface types, exported with the standard textures ([cvt.md](docs/formats/cvt.md)). Objects and skies for them would need the player's own Links LS `.CRX` files
- [ ] Object format: trees, buildings, crowds and their placement **(unblocked: CD3 `OBJECT/`, `OBJECT.LIB`, `CROWDS.LIB`; placement comes with the course format)**
  - [x] Library objects: `OBJECT.LIB`, `BTCV` billboards, `.XYZ`/`.CMF` models ([object-library.md](docs/formats/object-library.md), [model.md](docs/formats/model.md))
  - [x] Course billboards and their placement (`MasterObj`, `2DPlant`), drawn in the course viewer ([course-objects.md](docs/formats/course-objects.md))
  - [x] Course 3D objects (`MasterObj3D`, `3DPlant`, `.t3l`, `.maq` textures), drawn in the course viewer
  - [x] Tournament spectators (`TrnyPlant`, `CROWDS.LIB` sprites; which sprite each kind uses is a guess)
  - [x] Objects in the playable round: `CourseObjects` reads them from the `.CRZ`, draws them with one atlas and chunked MultiMeshes, and trees, rocks and 3D objects stop the ball (trunk, canopy and box sizes are guesses)
  - [ ] Object culling (`ObjectCull.dat`)
- [x] Course loader in `olcore` plus a fly-around course viewer in Godot (`tools/olcourse export`, then press C in the game)
- [x] Real courses in the round: `CrzCourseLoader` reads `.CRZ`/`.RNG` straight from the player's files in GDScript (works in the web build)

## Phase 2: a playable round

- [ ] Ball physics on real terrain: bounce and roll per surface, spin on greens, lie effects, trees and water **(needs data for tuning)**. Flight, launch, bounce and roll now use the game's own model ([physics.md](docs/formats/physics.md)): the coefficient and club tables are read from the player's executable, the launch matches the game's code on random strikes, and the bounce, skid, roll, rough hops and rock kicks match the game's code step for step. Lie effects (rough, deep grass, the sand contact model) are in too. Still to do: the swing meters' accuracy windows, the game's own cup, tree and object collisions, and per-course surface values from `TerrainTypes` instead of the class defaults
- [x] Wind: per-hole wind with a HUD arrow; the Links flight halves it ([physics.md](docs/formats/physics.md))
- [ ] Clubs and club selection **(needs data: club distances; `GRAPHICS.LS` has a `CLUBDIST` entry worth checking first)**
- [x] Game shell: hole flow, HUD, scorecard, placeholder course and loader interfaces ([docs/game-shell.md](docs/game-shell.md))
- [x] Stand-in ball physics: published flight, bounce and roll model behind a `ShotModel` interface
- [x] Swing controls: classic three-click power meter
- [ ] Swing controls: real-time mouse swing
- [x] Scoring basics: stroke play, putting and holing out, water drop, out of bounds, scorecard
- [ ] Rules: unplayable lies, lateral hazards, provisional balls, drop options
- [ ] Cameras: tee view, ball-follow, landing, green overview **(needs data for feel)**
  - [x] Broadcast presentation (Settings > Presentation): TV camera cuts, hole flyovers, shot tracer, replays, green slope grid, TV graphics, captions and crowd reactions ([game-shell.md](docs/game-shell.md#broadcast-presentation))
- [ ] Wire `olcore` into Godot via GDExtension; drop the GDScript physics port (wasm build needed for Web)

## Phase 3: look and sound

- [ ] Textures and skies **(unblocked: `STDTER_1.LIB`, `PANSKY.LIB`, `BTCV` sprites, patch `.sky` files)**
  - [x] HD texture packs: `tools/oltex export` writes the textures as PNG for upscaling, and the game loads an upscaled pack in their place (`HdPack`, [hd-textures.md](docs/hd-textures.md)). Still to do: packs in the browser build, the HUD and menu art, the patch `.sky` skies
  - [x] Course horizon panoramas and `PANSKY.LIB` cloud skies ([panorama.md](docs/formats/panorama.md)), drawn behind the round
  - [ ] Where exactly the game puts the horizon (eye-level row) and which sky each course uses
  - [ ] Texture projections (`Mappings`) and blended edges (`... Alpha.tga` masks); `.SHA` shadow maps
- [ ] In-play interface from `GRAPHICS.LS`
  - [x] Chrome info bars (`CRSINFO.TGA`) and the classic swing bar (`RIND12.TGA`)
  - [ ] Swing indicator gizmo (`SI*.TGA`), PowerStroke panel, club icons, wind and lie windows, the game's own fonts (`.D3F`)
- [ ] Golfer models and animation **(unblocked: `POLYANI/*.L3` with `.CLP` clips; probably the hardest format)**
  - [x] Archive contents, animation state script, object store container ([golfer-script.md](docs/formats/golfer-script.md), [carrera-store.md](docs/formats/carrera-store.md))
  - [x] Clip samples and skeleton (`olcore::read_anim_clips`, `read_skeleton`); the real golfer swings as a stick figure in the round
  - [x] Mesh, textures and skinning (`olcore::read_meshes`, `skin_positions`); the round shows the textured golfer with the driver or putter
  - [x] Without the game files: a realistic CC0 golfer built from MakeHuman assets with a hand-keyed swing, putt and celebration ([tools/golfer](tools/golfer/build_free_golfer.py), [licence](game/assets/golfer/LICENSE.md))
  - [x] Club and shot clips: the driver, iron and putter models; the `[Driver]`, `[Iron]`, `[Chip]` and `[Putter]` clips by club and distance, half swings for weak swings, long, medium and short putts; the low-detail model (`golfer_detail=low`, the browser default); shirt and pants choices (`shirts=`, `pants=`). The scripts have no lie-specific clips (sand, rough) to use.
- [ ] Audio: effects, ambient, commentary **(unblocked: plain WAVs, `SOUNDS.LS`, `.SSF` sound scripts, `.TIP` hole previews)**
  - [x] `.SSF` banks and MS ADPCM voices ([ssf.md](docs/formats/ssf.md), `olcore::SsfFile`, `olcore::decode_pcm16`); swing, landing, cup and splash sounds play in the round
  - [x] Course ambient sounds (`EnvSound` and the course's WAVs) and the ball landing sound
  - [ ] Voice event conditions, commentary and menu sounds wired into the game

## Phase 4: the full game

- [ ] Game modes: stroke, match, skins, best ball and others
  - [x] Stroke play, match play, skins, best ball and Stableford for 1 to 4 players, with tee and nine-hole choices ([game-shell.md](docs/game-shell.md#menus-and-game-modes))
  - [x] Handicaps: player profiles with their rounds, a WHS-style index, and net scoring in every mode ([game-shell.md](docs/game-shell.md#handicaps-and-player-profiles))
  - [ ] Alternate shot, scramble and the other original modes
- [ ] AI opponents
- [ ] Menus and HUD: setup, club picker, wind and lie display, aim line
  - [x] Main menu, round setup (course, tees, holes, mode, players), pause menu, multi-player scorecard
- [ ] Course designer
  - [x] In-game designer that works in the browser: sculpt the ground, paint fairways, greens, tees, bunkers, ponds and rough, plant trees, lay out holes, play the course, save, export and import `.olc` files ([course-designer.md](docs/course-designer.md))
  - [ ] Crisp surface edges (splat map), more object kinds, cart paths and bridges, hazard stakes, per-course skies
- [ ] Community add-on courses
  - [x] Suggest popular free courses with links to Links Corner, and add them from a downloaded `.zip` in the browser ([community-courses.md](docs/community-courses.md))
- [ ] Game-folder picker on each platform, including the browser file picker

## Phase 5: later

- [ ] Hot-seat multiplayer, then online
  - [x] Hot seat: up to four players in one round, honour and furthest-away order
- [ ] Player profiles and saves (original format optional)
  - [x] Profiles by name with their finished rounds and handicap index (`user://profiles.cfg`)
  - [ ] A players page to view and delete profiles; saving a round in progress
- [ ] Settings, controller support, performance
  - [x] Graphics looks (Photoreal, Natural, Cinematic, Classic Links, Performance) picked per device, ReShade-style effects (sharpen, grading, vignette, grain, bloom, SSAO, depth of field), FSR upscaling, dynamic resolution, 3D grass in the rough and trees in the wind ([graphics.md](docs/graphics.md))
  - [ ] Photoscanned 3D trees with impostors, baked shadows and AO per hole, texture compression tiers, a performance budget in CI
