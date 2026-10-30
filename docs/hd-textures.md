# HD texture packs

An HD pack is a folder (or a `.zip` of one) of upscaled copies of the game's
textures. The game uses a pack's copy of a texture wherever there is one, and
the original everywhere else, so a pack can be partial. Nothing from the
original game ships with this project, and packs are never published: each
player makes one from their own files (see [clean-room.md](clean-room.md)).

## 1. Export the textures

`tools/oltex` writes every texture it can read as PNG (a few menu pictures
stay JPEG), sorted into one folder per kind:

```bash
cmake -S . -B build && cmake --build build --target oltex
build/tools/oltex/oltex export textures/ /path/to/links2003 /path/to/patch-1.07
```

Pass the game folder (an install, or the discs' `GAME` folders) and,
optionally, the unpacked v1.07 patch (`7z x Links2k3_107_Final.exe`). Locked
courses are opened with the game executable found among the inputs, or the
one given with `--exe`.

| Folder | Holds | Source |
|---|---|---|
| `terrain` | Ground textures. `standard__*` is the shared set; `<course>__*` come with each course | `STDTER_1.LIB`, `.CRZ`/`.RNG` |
| `sky` | Cloud skies, 4,800 x 320 panoramas. `patch__*` are the v1.07 skies | `PANSKY.LIB` (`skyNN`), patch `skies/*.sky` |
| `horizon` | Course horizons, 7,680 x 720 panoramas with a transparent sky. `<course>` is the course's own; `PanNN` are spares | `.CRZ` `Panorama`, `PANSKY.LIB` (`PanNN`) |
| `billboards` | Trees, bushes, rocks: the largest size (`A`) of each sprite | `OBJECT/**/*.BTX`, `.CRZ` |
| `crowds` | Spectator sprites | `CROWDS.LIB`, `TRNYCRWD.LIB` |
| `golfers` | `<golfer>__*`: face, hair and clothes textures; `clubs__*` | `POLYANI/*.L3` |
| `models` | 3D object textures: `<course>__<maq>_<level>`, `library__<object>_<n>` | `.CRZ` `.maq`, `OBJECT/3D*/*.CMF` |
| `ui` | Menus, HUD, logos, hole previews (not used by the game yet) | `GRAPHICS.LS`, `SETUP.LS`, `HELP.LS`, `.CRZ` |

A texture of a course or golfer is written as `<kind>/<sub>__<name>.png`,
not in a subfolder, so that an upscaler's batch mode can take a whole kind
at once. `hdpack.json` lists each texture's original size, its border and
whether it has transparency.

Two things are done to help upscalers:

- Textures that tile (`terrain`) get a 16-pixel border copied from the
  opposite edges, and the panoramas (`sky`, `horizon`) get 64 pixels on the
  left and right. The upscaler then sees the texels that really neighbour
  each edge, so the result stays seamless. The game trims the border off.
- Fully transparent pixels take the colour of the visible pixels next to
  them, so upscaling doesn't pull a dark fringe into the edges of leaves.

## 2. Upscale

Upscale each kind folder into a folder of the same name in the pack, for
example `Links 2003 HD/terrain`. The suggested models and scales are in
the guide that comes with the export (`UPSCAYL-GUIDE.md`, written for
Upscayl). Two limits apply:

- Skies and horizons should be upscaled at most 2x. Wider images are shrunk
  back to 16,384 pixels (8,192 in the browser) when loaded.
- Billboards and spectators are drawn from a shared atlas at up to 1,024
  pixels a side with an HD pack (512 without), so 2x is usually enough.

The upscaled files can keep the upscaler's suffix (`_upscayl_4x_remacri`)
and can be in subfolders (`terrain/cabo/Sand 1A.png` for
`terrain/cabo__Sand 1A.png`). Files the pack leaves out stay original.

## 3. Use the pack in the game

In the game's settings, set **HD textures** to On and choose the pack
folder (the one that holds `terrain`, `sky` and so on) or a `.zip` of it.
The pack applies to textures loaded after that, so it shows from the next
course or hole. It can also be given as `--hd-pack=/path` on the command line
or in the `LINKS2003_HD_PACK` environment variable.

HD packs work in the desktop builds. The browser build doesn't offer them
yet.

## How the game finds a texture

`HdPack` (`game/scripts/assets/hd_pack.gd`) indexes the pack once, then each
loader asks for its texture by kind and name:

| Loader | Asks for |
|---|---|
| `CrzCourseLoader` (ground) | `terrain/<course>` for the course's own textures, `terrain/standard` for the standard library |
| `CourseObjects` (round) | `billboards`, `crowds`, `models/<course>` |
| `DecodedObjectLibrary` | `billboards`, `models/library` |
| `LinksGolfer` | `golfers/<golfer>`, `golfers/clubs` |
| `CourseBackdrop` | `sky/<skyNN>`, `horizon/<course>` |

A texture of a kind with a border is trimmed back using the original's size.
An image that was upscaled without its border is recognised and kept whole:
its size is a whole multiple of the original but not of the bordered size.
