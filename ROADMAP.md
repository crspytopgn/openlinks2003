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
- [ ] Course format: terrain, surface types, holes, tees, pins, hazards, OB **(unblocked: six `.CRZ` courses on CD2, 39 `.CVT`)**. Done: terrain mesh, materials, textures, holes, tees, pins. Still to do: surface physics (`TerrainTypes`), hazards and OB (`Shapes`), texture mappings
- [ ] Object format: trees, buildings, crowds and their placement **(unblocked: CD3 `OBJECT/`, `OBJECT.LIB`, `CROWDS.LIB`; placement comes with the course format)**
- [x] Course loader in `olcore` plus a fly-around course viewer in Godot (`tools/olcourse export`, then press C in the game)

## Phase 2: a playable round

- [ ] Ball physics on real terrain: bounce and roll per surface, spin on greens, lie effects, trees and water **(needs data for tuning)**
- [ ] Wind
- [ ] Clubs and club selection **(needs data: club distances; `GRAPHICS.LS` has a `CLUBDIST` entry worth checking first)**
- [x] Game shell: hole flow, HUD, scorecard, placeholder course and loader interfaces ([docs/game-shell.md](docs/game-shell.md))
- [x] Stand-in ball physics: published flight, bounce and roll model behind a `ShotModel` interface
- [x] Swing controls: classic three-click power meter
- [ ] Swing controls: real-time mouse swing
- [x] Scoring basics: stroke play, putting and holing out, water drop, out of bounds, scorecard
- [ ] Rules: unplayable lies, lateral hazards, provisional balls, drop options
- [ ] Cameras: tee view, ball-follow, landing, green overview **(needs data for feel)**
- [ ] Wire `olcore` into Godot via GDExtension; drop the GDScript physics port (wasm build needed for Web)

## Phase 3: look and sound

- [ ] Textures and skies **(unblocked: `STDTER_1.LIB`, `PANSKY.LIB`, `BTCV` sprites, patch `.sky` files)**
- [ ] Golfer models and animation **(unblocked: `POLYANI/*.L3` with `.CLP` clips; probably the hardest format)**
  - [x] Archive contents, animation state script, object store container ([golfer-script.md](docs/formats/golfer-script.md), [carrera-store.md](docs/formats/carrera-store.md))
  - [x] Clip samples and skeleton (`olcore::read_anim_clips`, `read_skeleton`); the real golfer swings as a stick figure in the round
  - [x] Mesh, textures and skinning (`olcore::read_meshes`, `skin_positions`); the round shows the textured golfer with the driver or putter
  - [ ] Iron and wedge clubs, lie-specific clips, the low-detail model, shirt and pants choices
- [ ] Audio: effects, ambient, commentary **(unblocked: plain WAVs, `SOUNDS.LS`, `.SSF` sound scripts, `.TIP` hole previews)**
  - [x] `.SSF` banks and MS ADPCM voices ([ssf.md](docs/formats/ssf.md), `olcore::SsfFile`, `olcore::decode_pcm16`); swing, landing, cup and splash sounds play in the round
  - [ ] Voice event conditions, commentary, ambient and menu sounds wired into the game

## Phase 4: the full game

- [ ] Game modes: stroke, match, skins, best ball and others
- [ ] AI opponents
- [ ] Menus and HUD: setup, club picker, wind and lie display, aim line
- [ ] Community add-on courses
- [ ] Game-folder picker on each platform, including the browser file picker

## Phase 5: later

- [ ] Hot-seat multiplayer, then online
- [ ] Player profiles and saves (original format optional)
- [ ] Settings, controller support, performance
