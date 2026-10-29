# Roadmap

Ordered by dependency. Items marked **(needs data)** need sample files or
measurements from an installed copy of the original game; don't start them
on guesses, because the details come from the data.

## Current blocker

The owner's copy is a set of BlindWrite CD images (`.b6i`/`.b6t`). The plan
is to install the game on a Windows machine (or VM) and work from the install
folder, not the CD images. Waiting on a file listing of that folder.

## Phase 1: formats (see `docs/formats/`)

- [ ] Inventory the install folder: file types, counts, sizes **(needs data)**
- [ ] Archive/container format, if the game packs its files **(needs data)**
- [ ] Course format: terrain, surface types, holes, tees, pins, hazards, OB **(needs data)**
- [ ] Object format: trees, buildings, crowds and their placement **(needs data)**
- [ ] Course loader in `olcore` plus a fly-around course viewer in Godot

## Phase 2: a playable round

- [ ] Ball physics on real terrain: bounce and roll per surface, spin on greens, lie effects, trees and water **(needs data for tuning)**
- [ ] Wind
- [ ] Clubs and club selection **(needs data: club distances)**
- [ ] Swing controls: classic three-click power meter, then the real-time mouse swing
- [ ] Rules and scoring: penalties, drops, putting, scorecard
- [ ] Cameras: tee view, ball-follow, landing, green overview **(needs data for feel)**
- [ ] Wire `olcore` into Godot via GDExtension; drop the GDScript physics port (wasm build needed for Web)

## Phase 3: look and sound

- [ ] Textures and skies **(needs data)**
- [ ] Golfer models or animation frames **(needs data; probably the hardest format)**
- [ ] Audio: effects, ambient, commentary **(needs data)**

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
