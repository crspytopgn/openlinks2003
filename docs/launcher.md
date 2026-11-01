# Desktop launcher

`launcher/` is a small Godot project (Compatibility renderer, about the size
of a Godot runtime) that installs, updates and starts the game on macOS,
Windows and Linux. CI builds it with the game and publishes it in the
[latest release](https://github.com/crspytopgn/openlinks2003/releases/tag/latest)
as `OpenLinks2003-Launcher-macOS.zip`, `-Windows.zip` and `-Linux.tar.gz`.

It contains nothing from Links 2003, and it never downloads anything from
the original game: the player's own files are read from their own discs,
images or install, on their own computer.

## What it does

- **Play / Install / Update.** Reads the `latest` release from the GitHub
  API, compares its commit with the installed build, downloads this
  platform's build, checks it against GitHub's SHA-256 digest, unpacks it
  next to the installed one and swaps them, so a failed update leaves the old
  build playable. With *Update automatically* on (the default) this happens
  as soon as the launcher opens.
- **What's New.** The last 40 commits on `main`, one per merged pull request,
  with the squashed commit titles as points and a green dot on the changes
  since the installed build. Cached for offline starts.
- **Settings** before launch, written to the game's own `user://settings.cfg`:
  look preset and quality, 3D resolution, renderer (Forward+ or
  Compatibility, passed as `--rendering-method`), window or fullscreen mode
  (borderless or exclusive), window size, vertical sync, interface size,
  volume and menu music, swing method, skill, swing help, launch monitor,
  and the presentation.
- **Game Files.** Finds Links 2003 CDs and mounted images (`/Volumes`,
  `/media`, `/run/media`, drive letters) and installed copies (Program Files,
  the Wine prefixes of `tools/mac/links2003-mac.sh`). An installed copy is
  used where it is. From disc images (`.b6i`, `.iso`, `.bin`, `.nrg`, `.mdf`
  and more, raw or cooked) or CDs, the GAME folder's files are copied into
  the launcher's library folder under the names Setup gives them, skipping
  videos and programs, as the web build and `tools/cdimage/cdimage.py
  install` do. Images and folders can also be dropped on the window.
- **Course builder** starts the game with `-- --designer`, which opens the
  course designer from the main menu (`game/scripts/boot.gd`).

## Where things are

| | |
| --- | --- |
| The launcher's folder | Godot's `app_userdata/OpenLinks2003 Launcher` |
| Installed game | `game/current` in it, `game/installed.json` says which build |
| Copied Links 2003 files | `links2003/` in it |
| Game settings | Godot's `app_userdata/OpenLinks2003/settings.cfg` |

Godot's `app_userdata` is under `~/Library/Application Support/Godot` on
macOS, `%APPDATA%\Godot` on Windows and `~/.local/share/godot` on Linux.

## How the game takes the launcher's settings

Most options are the game's own keys. A look preset sets a dozen options only
the game knows, so the launcher leaves `look` and `quality` under
`[launcher]`; at its next start the game applies the look, then the quality,
saves, and removes the section (`GraphicsSettings.apply_launcher_requests`).
New in the game for the launcher: `[graphics] display_mode`, `window_width`,
`window_height`, and `[audio] master` and `music` (`AudioSettings`).

## Launcher updates

The game updates itself through the launcher. The launcher knows the git
tree id of `launcher/` it was built from (stamped by CI in
`launcher/scripts/build_info.gd`) and says so in its status when `main` has a
different one; a new launcher is downloaded from the releases page.

## The release

The release job publishes only from the newest commit on `main`, one run at
a time. Before this, runs that finished out of order could replace a newer
build with an older one.

## macOS signing

The launcher and the game are ad-hoc signed, not notarised, so the first
start needs right-click > Open. Builds the launcher downloads itself aren't
quarantined, so updates open without that step. Notarising needs an Apple
Developer account (a Developer ID certificate and an app-specific password as
CI secrets).

## Running and testing from source

```bash
godot --path launcher                                  # run it
godot --headless --path launcher -s res://tests/run_tests.gd
```

`OL_LAUNCHER_DATA` and `OL_GAME_USER_DIR` point the launcher at other
folders (the tests use them). `--tab=1` opens on Settings, `--import=PATH`
starts copying from a disc image or folder.
