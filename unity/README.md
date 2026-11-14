# Unity 6 trial

A side-by-side trial of Unity 6 (URP) as the game's engine, next to the
Godot game in `game/`. It is not a port: it plays one tee shot on hole 1 of
Kettle Hollow, over and over, so the two engines can be compared on the same
course, golfer and ball flight.

What it shows:

- **Hole 1 of Kettle Hollow** from `game/assets/courses/home.olc`: a 512 m
  Unity Terrain from the height grid, the surface shapes painted as the game
  paints them (`SurfaceRaster.cs`), photo terrain layers from the same free
  textures (`tools/fetch_free_assets.py`), 3 m mown stripes on the fairway.
- **Trees** placed from the course's objects, built from seeds like the
  game's TreeFactory (`TreeBuilder.cs`), with the leaf spray and fir twig
  photos.
- **The HDR sky** with the sun light found in it, ACES tonemapping, bloom,
  SSAO, 4096 soft shadows over 350 m.
- **The golfer**: a Rocketbox person (MIT) driven by the game's own mocap
  (`game/assets/golfer/free_golfer.glb`, read by `GlbRig.cs` and retargeted
  through Unity's humanoid system).
- **The ball** flown by `libs/olcore`, the same C++ the Godot port is tested
  against, through a small C interface (`Native/olcore_unity.cpp`): a shared
  library on desktop, compiled in from source on the Web. Run the desktop
  build with `-linksExe <path to the game's exe>` for the Links 2003 model.

## Building

Unity needs a licence (the free Personal one is fine). The **Unity trial**
workflow (`.github/workflows/unity-trial.yml`) builds Linux, Windows and Web
players and screenshots the Linux one once these repository secrets exist:
`UNITY_LICENSE` (the contents of `Unity_lic.ulf`), `UNITY_EMAIL` and
`UNITY_PASSWORD`.

Locally, with Unity 6000.0.86f1:

```bash
unity/prepare.sh Linux64     # or Win64, WebGL: fetches inputs, builds olcore
```

then open `unity/` in the editor and run **OpenLinks > Build trial scene**.
Everything in the scene is generated from code; the repository holds only
scripts, `Packages/manifest.json` and two settings files, and the editor is
set to text serialization.

Never put original game files in this folder (`docs/clean-room.md`).
