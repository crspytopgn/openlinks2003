# Play the original Links 2003 on a Mac

`links2003-mac.sh` installs the original game from your own disc images into
a private Wine prefix and makes a `Links 2003.app` you can open from Finder.
It works on Apple Silicon (through Rosetta 2) and Intel Macs, macOS 10.15 or
later. Nothing from the game is downloaded or bundled: it comes only from the
images you point the script at.

## What you need

- The three Links 2003 disc images (`.b6i`, `.iso` or raw `.bin`), with
  `CD1`, `CD2` and `CD3` somewhere in their file names.
- The v1.07 patch, `Links2k3_107_Final.exe`.
- About 4 GB of free space and `python3` (`xcode-select --install` if macOS
  asks for it).

## One command

```bash
git clone https://github.com/crspytopgn/openlinks2003.git
cd openlinks2003
tools/mac/links2003-mac.sh setup --discs /path/to/folder/with/images
```

`--discs` defaults to `/Volumes/nvme.fanxiang/Claude/links2003/gameiso`, and
the patch is looked for in the same folder (`--patch FILE` to point
elsewhere; `--cd1/--cd2/--cd3 FILE` if the image names don't say which disc
they are). The script then:

1. Installs Rosetta 2 if needed and downloads a pinned Wine 11.20 build
   (Gcenx's macOS builds of WineHQ, checksum verified) into
   `~/Games/Links2003/wine`.
2. Turns each image into a virtual CD in `~/Games/Links2003/discs/cdN`,
   with the volume label and serial number Windows would report for the real
   disc. The game looks for its CD by label, so this stands in for the disc.
3. Creates a Windows XP prefix in `~/Games/Links2003/prefix` with disc 1 in
   `D:` and discs 2 and 3 in `E:` and `F:`, all as CD-ROM drives.
4. Runs the game's own `SETUP.EXE`. Click through it: pick the full install
   and keep the default folder. You can skip the DirectX and Windows Media
   extras. If setup asks for another disc in `D:`, press `1`, `2` or `3` in
   the Terminal window, then click OK.
5. Runs the 1.07 patch. Click through it with the default folder.
6. Makes `~/Applications/Links 2003.app`.

Each step is skipped when it's already done, so run `setup` again after a
problem and it carries on where it stopped.

## Playing

Open `Links 2003.app`, or run `tools/mac/links2003-mac.sh play`
(`play --launcher` starts the patch's launcher instead of the game).
`tools/mac/links2003-mac.sh winecfg` opens Wine's settings for the prefix,
for example to set a virtual desktop if fullscreen misbehaves.

Graphics go through Wine's own Direct3D (wined3d on OpenGL), which handles
the game's DirectX 8 renderer.

## Notes

- The 1.07 patch is required. Setup installs `LinksMMIII.exe` as a SafeDisc
  loader (the real game goes next to it as `rukshuk.icd`), and SafeDisc's
  driver can't run in Wine, so setup's "play now" step ends with "a debugger
  has been detected". That is harmless: the install is complete by then. The
  patch replaces the loader with an unprotected `LinksMMIII.exe`.
- Tried on an M4 Mac mini on 2026-10-30: the virtual CDs (labels
  `2003DISK1`-`2003DISK3`) and the disc swap during setup work.
- Wine caches a drive's label once it has looked at it. Pressing `1`-`3`
  during setup swaps the files in `D:`, but setup may still see disc 1's
  label. If setup then refuses the disc, point it at `E:` (disc 2) or `F:`
  (disc 3) if it offers a browse button.
- Settings: `LINKS2003_HOME` moves everything (default `~/Games/Links2003`),
  `LINKS2003_APP` moves the app, `LINKS2003_WINE` uses another Wine binary.
- To remove it all, delete `~/Games/Links2003` and the app.
- The virtual CDs hold copies of your discs: keep them private, like the
  images.
