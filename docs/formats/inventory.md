# Install inventory and format survey

Status: partial (first pass, from headers and directory names only)
Seen in: the three English Links 2003 discs and the v1.07 patch

This is a map of what the game ships and a first guess at what each file
type holds. Per-format documents (layout tables) come next; each section
below says how far we got. Short byte excerpts are quoted only to identify
signatures.

## Reading the discs

No Windows install is needed. The discs keep the game files uncompressed in
an ISO 9660 track (setup most likely just copies them; to be confirmed
against a real install), so
[`tools/cdimage/cdimage.py`](../../tools/cdimage/cdimage.py) can list or
extract them from your own `.b6i` images:

```bash
python3 tools/cdimage/cdimage.py list    Links2003-CD1.b6i
python3 tools/cdimage/cdimage.py extract Links2003-CD2.b6i ~/links2003 '/game/courses/*'
```

The BlindWrite images use raw 2352-byte Mode 1 sectors with a 150-sector
pregap. The discs carry no Joliet names, so everything is 8.3 and long names
are truncated (`TOURNA_1.SSF`, `LINKSM_1.EXE`). Setup restores the long names
when it installs; the v1.07 patch shows a few of them (`LinksMMIII.exe`,
`predefined.ssf`, `Season 1.SEA`, `Pro Roster.ROS`). The loader must
accept both spellings, and the executable refers to files case-insensitively
(`graphics.ls`, `GRAPHICS.LS`).

Full listings (path and size only):
[cd1.tsv](../install-listing/cd1.tsv),
[cd2.tsv](../install-listing/cd2.tsv),
[cd3.tsv](../install-listing/cd3.tsv),
[patch-1.07.tsv](../install-listing/patch-1.07.tsv).

## What is on each disc

| Disc | Files | Contents |
|------|------:|----------|
| CD1 | 271 | Setup, DirectX 8.1, Windows Media runtimes, intro video, manuals, and the whole `GAME/` folder except courses: executables, UI, sounds, golfer animations, crowds, skies, standard terrain, career mode, modes of play, the driving range |
| CD2 | 68 | The six courses (`CABO`, `CAMBRIAN`, `GEAGLES`, `KAURI`, `SKELETON`, `TRIBUTE`) as `.CRZ`, `.SHA`, `.TIP` and `.WMV` flyby, plus `CONVERT/`: 39 older courses (`.CVT`) and `CRX2CRZ.EXE`, which converts Links 2001 `.CRX` courses |
| CD3 | 1,685 | Arnold Palmer Course Designer (`APCD.EXE`) and its object library: 1,400+ objects in `GAME/OBJECT/` (trees, bushes, rocks, flowers, buildings, animals), ambient sounds, sample textures, `2001OBJS.EXE` (Links 2001 object pack, 160 MB) |
| Patch 1.07 | 48 | NSIS installer. New main executable and mode DLLs, rebalanced career seasons and rosters, 17 custom skies (`.sky`), three club sets (`.l3`) |

## Containers

Most data sits inside four container types. Cracking these unblocks
everything else, so they are the next documents to write.

### `LSls` indexed archive (`.LS`, `.L3`, `.TIP`)

Decoded: see [ls-archive.md](ls-archive.md). A 55-byte header, an index
of names and absolute offsets, then entries that each start with the same
55-byte header. Most entries are LZW-compressed; WAVs are mostly stored.

| File | Entries | Holds |
|------|--------:|-------|
| `GRAPHICS.LS` | 275 | HUD and swing-meter TGAs, also an entry named `CLUBDIST` (club distances?) |
| `SETUP.LS` | 104 | Menu UI TGAs |
| `SOUNDS.LS` | 55 | Ball and UI sound effects (WAV) |
| `LESSONS.LS` | 300+ | Lesson narration (WAV) |
| `HELP.LS`, `CREDITS.LS` | | Help pages, credits text |
| `GAMEDATA.LS` | 3 | Default career rosters (`.ROS`) |
| `MOPS.L3` | 47 | Mode-of-play scripts (`.MOP`) |
| `POLYANI/*.L3` | ~200 each | One golfer: model (`.SKL`), ~160 animation clips (`.CLP`), textures, `SCRIPT.TXT`; see [carrera-store.md](carrera-store.md) |
| `POLYANI/CLUBS.L3`, patch `PolyAni/clubs/*.l3` | ~10 | Club models (`DRIVER.SK...`) |
| `COURSES/*.TIP` | 18 | Per-hole spoken previews (`HOLPRV01.WAV`...) |

### `ARC0` compressed archive (`.LIB`, `.BTX`, `.TOP`, `.CMF`, `.sky`)

`ARC0`, then three u32: total file size, an entry count, and the compressed
size of the first entry. Each entry is a zlib stream. Contents seen:

| File | Entries | First entry |
|------|--------:|-------------|
| `STDTER_1.LIB` (`stdterrain.lib`) | 228 | TGA: standard terrain textures |
| `PANSKY.LIB` | 50 | Tag `yks` with `desu`: panoramic sky images, probably DXT-compressed |
| `CROWDS.LIB` (also `TRNYCRWD.LIB`) | 981 | `BTCV` sprite: spectators |
| `OBJECT/**/*.BTX` | 6 | `BTCV` sprite: a 2D billboard object (tree, bush) |
| `OBJECT/TOPVIEWS/*.TOP` | 6 | `BTCV` sprite: top-down view of an object for the course map |
| `OBJECT/3D2K3*/*.CMF` | 1 | `Textures`: the texture set of a 3D object (see [model.md](model.md)) |
| patch `skies/*.sky` | 95 | Custom sky |

`BTCV` is the game's own texture format: tiled DXT5 blocks stored as runs.
See [arc0.md](arc0.md) and [btcv.md](btcv.md); both are now fully decoded.

### Chained zlib streams (`.CRZ`, `.CVT`, `.RNG`)

A 16-byte header that looks random (a hash or key?), then zlib streams back
to back with no index. The first stream always decompresses to the text
`V.2.0`. In `CABO.CRZ` the next streams are TGA textures, two JPEGs (course
artwork), 64 x 64 TGAs, and a WAV; later streams hold the actual course data
(terrain, holes, objects), not yet examined. `DRIVING.RNG` is the driving
range in the same container. `.CVT` files (older courses) put a terrain
texture list (`Rough01.tga`, `Fring01.tga`, `Fairw01.tga`, `Green01.tga`,
`Sand01.tga`) and float tables in their first streams, then switch to data
that is not a zlib stream.

### `.SHA` course shadow map

Starts `VER5JDHSHADOW` followed by the name of the course file it belongs to
(`driving.rng`), then mostly floats. One per course.

## Other game files

| Extension | Signature | Holds | Notes |
|-----------|-----------|-------|-------|
| `.SSF` | `SSF\0`, chunks tagged `EVE` | Sound banks: events (`Full Swing`, `Pin Hit`, `Ball-in-cup`, `Splash`) mapped to embedded WAVs; see [ssf.md](ssf.md) | `TOURNA_1.SSF` is commentary (84 MB); `POLYANI/*.SSF` are golfer voices; `PREDEF_1.SSF` is `predefined.ssf` |
| `.PLR`, `.PIN` | `KON\0` | Player profile; `.PIN` for the pro golfers | UTF-16 names |
| `.ROS` | `SRD\0` (disc), `NRD\0` (patch) | Career roster | Version changed in the patch |
| `.SEA` | `SHR\0` | Career season | |
| `.MOP` | none, high entropy | Mode-of-play script | 8 KB each, probably encrypted |
| `.PST` | count, then names | Course Designer object palette sets | |
| `OBJECT.LIB` (CD3) | count, then names | Object catalog: category, `.btx` path, `TopViews\*.top` path, sizes, object id | See [object-library.md](object-library.md) |
| `OBJECT/**/*.XYZ`, `.MAP`, `.PRV` | | 3D objects: mesh (`XYZ`), paletted copy of the textures (`MAP`), 128 x 128 preview (`PRV`) | 47 of each; see [model.md](model.md) |
| `.D3F` | `D3F4` + font name | Bitmap font | |
| `.TGA`, `.JPG`, `.WAV`, `.WMV`, `.BMP` | standard | | TGAs are mostly 32-bit, RLE in places |
| `LINKS.DAT`, `.MPD`, `.ICD`, `GOLFANI.DLL` | `MZ` | Windows DLLs | Code, not data |
| `START.OBJ`, `START.SBR`, `VC70.IDB` | | Build leftovers (compiler output) | Out of scope under the clean-room rules |

## Open questions

- Course data inside `.CRZ` after the media streams: terrain, surface
  types, holes, pins, object placement. This is the next big job.
- The 16-byte `.CRZ` header: checksum or key.
- How `.CVT` differs from `.CRZ` past its first streams.
- Golfer mesh and skeleton layouts in `.SKL`, and the sample encoding in
  `.CLP` (see [carrera-store.md](carrera-store.md)).
