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
- [x] Course format: terrain, surface types, holes, tees, pins, hazards, OB. Terrain mesh, materials, textures and their mappings, holes, tees, pins, the full `TerrainTypes` records (surface physics values, hazard and free-drop flags), hole outlines and out-of-bounds areas (`HoleIDShapes`, `OBIDShapes`) ([crz.md](docs/formats/crz.md))
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

- [ ] Ball physics on real terrain: bounce and roll per surface, spin on greens, lie effects, trees and water **(needs data for tuning)**. Flight, launch, bounce and roll now use the game's own model ([physics.md](docs/formats/physics.md)): the coefficient and club tables are read from the player's executable, the launch matches the game's code on random strikes, and the bounce, skid, roll, rough hops and rock kicks match the game's code step for step. Lie effects (rough, deep grass, the sand contact model) and the human swing's miss model (PowerStroke misses becoming pulls, pushes, lost power and poor strikes per lie and skill level) the computer golfers' own miss generator and the game's green firmness and speed options are in too, and so are putts (the putter's own launch, starting on the ground, its PowerStroke miss and the computer golfers' putt misses). The PowerStroke mouse swing works as the game's does (the mouse drives a club with momentum up and down the game's meter, frame by frame; drift hooks, slices or misses), checked against the game's code in an emulator, putts and chips included. The three-click meter runs at the game's own positions and speeds, and chips are picked and played as the game does (its chip meter, chip power and chip misses). The cup (rim, lip-outs, the drop into the hole) and the flagstick match the game's code step for step. Trees, bushes, grasses and rocks (the course's billboards) stop, turn and slow the ball as the game's code does. 3D objects (walls, bridges, buildings) use the game's own face test, see-through textures and its roll along decks and bridges. The bounce and roll use each course's own `TerrainTypes` values, and out of bounds and hazards come from the course files
- [x] Wind: per-hole wind with a HUD arrow; the Links flight halves it ([physics.md](docs/formats/physics.md))
- [ ] Clubs and club selection **(needs data: club distances; `GRAPHICS.LS` has a `CLUBDIST` entry worth checking first)**
- [x] Game shell: hole flow, HUD, scorecard, placeholder course and loader interfaces ([docs/game-shell.md](docs/game-shell.md))
- [x] Stand-in ball physics: published flight, bounce and roll model behind a `ShotModel` interface
- [x] Swing controls: classic three-click power meter
- [x] Swing controls: real-time mouse swing (Links 2003's PowerStroke mouse swing, the default; irons, chips, putts and the swing help option as the game does them)
- [x] Scoring basics: stroke play, putting and holing out, water drop, out of bounds, scorecard
- [x] Rules: unplayable lies, lateral hazards, drop options, free drops from cart paths ([game-shell.md](docs/game-shell.md#drops)). No provisional balls: Links 2003 has no lost balls and out of bounds is known at once
  - [ ] Drop the ball and let it roll, re-dropping if it leaves the zone, as Links does
- [ ] Cameras: tee view, ball-follow, landing, green overview **(needs data for feel)**
  - [x] Broadcast presentation (Settings > Presentation): TV camera cuts, hole flyovers, shot tracer, replays, green slope grid, TV graphics, captions and crowd reactions ([game-shell.md](docs/game-shell.md#broadcast-presentation))
  - [x] Tour presentation (off by default): leaderboard rail, shot-data bar, driving zone, putt read, hole map with shots ([game-shell.md](docs/game-shell.md#tour))
- [ ] Wire `olcore` into Godot via GDExtension; drop the GDScript physics port (wasm build needed for Web)

## Phase 3: look and sound

- [ ] Textures and skies **(unblocked: `STDTER_1.LIB`, `PANSKY.LIB`, `BTCV` sprites, patch `.sky` files)**
  - [x] HD texture packs: `tools/oltex export` writes the textures as PNG for upscaling, and the game loads an upscaled pack in their place (`HdPack`, [hd-textures.md](docs/hd-textures.md)). Still to do: packs in the browser build, the HUD and menu art, the patch `.sky` skies
  - [x] Course horizon panoramas and `PANSKY.LIB` cloud skies ([panorama.md](docs/formats/panorama.md)), drawn behind the round
  - [x] Which sky and horizon each course uses (`header` trailer, [crz.md](docs/formats/crz.md#the-header-trailer-sky-and-horizon)), the patch's named `.sky` skies, and a sky setting (course's own, random or any sky); a picked sky sets the Photoreal light
  - [ ] Where exactly the game puts the horizon (eye-level row) and the sky band **(needs a screenshot of the running game)**
  - [x] Texture projections (`Mappings`) and blended edges (`... Alpha.tga` masks) ([crz.md](docs/formats/crz.md#mappings-texture-projections)); `.SHA` tree shadow shapes in the baked ground shade ([sha.md](docs/formats/sha.md))
  - [x] The rest of `.SHA` ([sha.md](docs/formats/sha.md)): 3D object footprints stamped as ground shadows, per-billboard light dimming trees among trees; detail texture variants (`... 32.tga`, `... 128.tga`) faded in with distance
  - [ ] The trailer's four floats (sun direction?), the `.SHA` cell lists, and the game's exact variant distances
- [ ] In-play interface from `GRAPHICS.LS`
  - [x] Chrome info bars (`CRSINFO.TGA`) and the classic swing bar (`RIND12.TGA`)
  - [x] Swing indicator gizmo (`SI*.TGA`), PowerStroke panel, wind, elevation and lie windows, the game's own fonts (`.D3F`, [d3f.md](docs/formats/d3f.md)) ([game-shell.md](docs/game-shell.md#the-original-interface))
  - [ ] Exact screen placement, the red and `HV`/`EZ` gizmo variants, shot-shape symbols (`SISYMB*`), club icons in the club list **(needs a screenshot of the running game)**
- [ ] Golfer models and animation **(unblocked: `POLYANI/*.L3` with `.CLP` clips; probably the hardest format)**
  - [x] Archive contents, animation state script, object store container ([golfer-script.md](docs/formats/golfer-script.md), [carrera-store.md](docs/formats/carrera-store.md))
  - [x] Clip samples and skeleton (`olcore::read_anim_clips`, `read_skeleton`); the real golfer swings as a stick figure in the round
  - [x] Mesh, textures and skinning (`olcore::read_meshes`, `skin_positions`); the round shows the textured golfer with the driver or putter
  - [x] Without the game files: a realistic CC0 golfer built from MakeHuman assets, moving with motion capture (CMU mocap, [mocap_swing.py](tools/golfer/mocap_swing.py)): address sway with a look at the target, swing, putt, a walk up to each ball, and reactions to holing out and penalties ([tools/golfer](tools/golfer/build_free_golfer.py), [licence](game/assets/golfer/LICENSE.md))
  - [x] Club and shot clips: the driver, iron and putter models; the `[Driver]`, `[Iron]`, `[Chip]` and `[Putter]` clips by club and distance, half swings for weak swings, long, medium and short putts; the low-detail model (`golfer_detail=low`, the browser default); shirt and pants choices (`shirts=`, `pants=`). The scripts have no lie-specific clips (sand, rough) to use.
- [ ] Audio: effects, ambient, commentary **(unblocked: plain WAVs, `SOUNDS.LS`, `.SSF` sound scripts, `.TIP` hole previews)**
  - [x] `.SSF` banks and MS ADPCM voices ([ssf.md](docs/formats/ssf.md), `olcore::SsfFile`, `olcore::decode_pcm16`); swing, landing, cup and splash sounds play in the round
  - [x] Course ambient sounds (`EnvSound` and the course's WAVs) and the ball landing sound
  - [x] Tournament crowd reactions from `TOURNA_1.SSF` in the Broadcast presentation ([ssf.md](docs/formats/ssf.md#the-tournament-bank))
  - [x] Golfer voice reactions (`POLYANI/*.SSF`, chosen by shot outcome) and menu clicks and music (`SOUNDS.LS`)
  - [x] Without the game files: real recordings (CC0 and CC BY, from freesound.org) for club strikes by club and lie, putts, landings by surface, the cup, water, crowd reactions, footsteps, the bag and menu clicks, and looping course ambience by kind of course, with wind and water layers ([tools/audio](tools/audio/build_free_sounds.py), [credits](game/assets/sounds/CREDITS.md))
  - [x] Voice lines at impact, in flight and on landing (best-guess timing); the disc sounds in the browser as an opt-in setting
  - [ ] Voice event conditions (the condition block) read from the banks instead of our own rules
  - [x] Landings, the cup and splashes heard from where the camera stands: late by the speed of sound and fainter with distance (`SoundBank.heard_from`)

## Phase 4: the full game

- [ ] Game modes: stroke, match, skins, best ball and others
  - [x] Stroke play, match play, skins, best ball and Stableford for 1 to 4 players, with tee and nine-hole choices ([game-shell.md](docs/game-shell.md#menus-and-game-modes))
  - [x] Handicaps: player profiles with their rounds, a WHS-style index, and net scoring in every mode ([game-shell.md](docs/game-shell.md#handicaps-and-player-profiles))
  - [x] Scramble and alternate shot, with people and computer golfers on either team ([game-shell.md](docs/game-shell.md#menus-and-game-modes))
  - [ ] The other original modes
- [x] AI opponents: computer golfers at four levels (weekend, club, scratch, tour pro) that plan through the real physics and play every mode ([game-shell.md](docs/game-shell.md#computer-opponents))
- [ ] Menus and HUD: setup, club picker, wind and lie display, aim line
  - [x] Main menu, round setup (course, tees, holes, mode, players), pause menu, multi-player scorecard
- [ ] Course designer
  - [x] In-game designer that works in the browser: sculpt the ground, paint fairways, greens, tees, bunkers, ponds and rough, plant trees, lay out holes, play the course, save, export and import `.olc` files ([course-designer.md](docs/course-designer.md))
  - [x] Objects from the player's own object library with measured collision sizes, cart paths (free drop) and bridges, per-hole flyover, shareable single-file courses
  - [x] Real courses by name: OpenStreetMap holes and areas plus open lidar and elevation heights, in the browser too ([real-courses.md](docs/real-courses.md))
  - [x] Real courses: national lidar (England, Netherlands, France, US), trees from the lidar canopy or aerial photos, the photo under the designer, clubs with several courses
  - [x] Real courses: lidar and photos for Flanders, North Rhine-Westphalia, Norway, Austria (photos) and Japan, falling back between services near borders; ground colours from the aerial photo
  - [x] Real courses: worldwide 10 m land cover for trees the map lacks and ground colours where there is no open photo
  - [x] Real courses: greens, tees, fairways and bunkers the map lacks drawn at typical sizes along each hole (marked as guessed)
  - [x] Real courses: find missing greens and bunkers in the photos (and bunkers in the lidar) before guessing
  - [x] Real courses: find missing fairways in the photos (clear photos; low-contrast ones fall back)
  - [ ] Real courses: greens in the lidar where there is no photo
  - [ ] Real courses: Scotland, Wales, Ireland, Denmark, Canada and the rest (need a key or reprojection from national grids), buildings
  - [ ] Crisp surface edges (splat map), free built-in bushes and buildings, hazard stakes, per-course skies
- [ ] Community add-on courses
  - [x] Suggest popular free courses with links to Links Corner, and add them from a downloaded `.zip` in the browser ([community-courses.md](docs/community-courses.md))
- [ ] Game-folder picker on each platform, including the browser file picker

## Phase 5: later

- [ ] Optional extras, off by default so Classic Links plays as the original ([caddie-and-buggy.md](docs/caddie-and-buggy.md))
  - [x] Caddie (Settings > Caddie): yardage, plays-like, club, line and green reads planned through the real physics, saying less at the harder swing skill levels
  - [x] Drivable golf buggy between shots (Settings > Golf buggy), with a skip
  - [ ] Caddie animations (walking, handing over the club)
- [ ] Hot-seat multiplayer, then online
  - [x] Hot seat: up to four players in one round, honour and furthest-away order
  - [x] Hand-over screen between people at one keyboard, skipped for computer golfers
  - [ ] Online play, leaderboards and fair play ([online-play.md](docs/online-play.md))
    - [x] Phase 1: replayable rounds (round seed, shot records, replay checker in CI), challenge and result codes
    - [ ] Phase 2: server (Cloudflare Worker), rooms by code over WebSocket, every client checks every shot, rounds in your own time
    - [ ] Phase 3: olcore in wasm, server-checked leaderboards on open courses, daily and weekly challenges, replays and ghosts
    - [ ] Phase 4: simultaneous play, GitHub or Discord sign-in, handicap boards, swing plausibility checks, reports
- [ ] Player profiles and saves (original format optional)
  - [x] Profiles by name with their finished rounds and handicap index (`user://profiles.cfg`)
  - [x] A players page to view and delete profiles; saving a round in progress and resuming it ([game-shell.md](docs/game-shell.md#saved-rounds))
  - [x] Career stats (fairways, greens in regulation, putts) and handicaps for the computer golfers
  - [x] Player creator: body, height, skin, face, hair, clothes and equipment looks, saved with the profile and played in rounds ([game-shell.md](docs/game-shell.md#player-creator))
  - [ ] Face from a photo, processed on the player's own device
- [ ] Settings, controller support, performance
  - [x] Graphics looks (Photoreal, Natural, Cinematic, Classic Links, Performance) picked per device, ReShade-style effects (sharpen, grading, vignette, grain, bloom, SSAO, depth of field), FSR upscaling, dynamic resolution, 3D grass in the rough and trees in the wind ([graphics.md](docs/graphics.md))
  - [x] Photo-textured 3D trees with impostors, also in place of the disc courses' tree billboards, baked tree shadows and AO per hole, and a performance budget in CI ([graphics.md](docs/graphics.md))
  - [x] Cloud shadows (Settings > Graphics, on in the Photoreal, Natural and Cinematic looks)
  - [ ] Texture compression tiers per device, the HD pack in the browser
