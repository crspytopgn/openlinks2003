#!/usr/bin/env python3
"""Downloads the free (CC0) textures and sky that the public build uses in
place of the original game's art, from Poly Haven (https://polyhaven.com),
and the leaf texture of the 3D trees from ambientCG (https://ambientcg.com)
and photoscanned fir sprigs for the conifers from Poly Haven.

    python3 tools/fetch_free_assets.py [--out game/free_assets] [--strict]

Nothing here comes from Links 2003. The files are not committed (see
.gitignore); CI runs this before importing the project, and the game falls
back to plain shading when they are missing. The grass, rough, sand, path
and dirt slots are photoscans from ambientCG (AMBIENT_GROUNDS), with Poly
Haven as the fallback. Each slot below lists the Poly Haven assets to try in order; if none of them exists any more, the most
downloaded asset whose name or tags match the slot's keywords is used. The
files are saved under fixed names, so the game doesn't care which asset was
picked, and CREDITS.md in the output folder records what was.

Without --strict a failed download is reported and skipped, so a Poly Haven
outage leaves the build working, just untextured.
"""

import argparse
import io
import json
import os
import sys
import time
import urllib.request
import zipfile

import sky_pack

API = "https://api.polyhaven.com"
AMBIENTCG = "https://ambientcg.com"
# ambientCG leaf sets (photographed leaves with an opacity map), in order of
# preference: 3 x 2 leaves each. {out name: map suffix in the zip}.
LEAF_SETS = ["LeafSet009", "LeafSet010"]
LEAF_MAPS = {"leaf_albedo.png": "_Color.png", "leaf_opacity.png": "_Opacity.png"}
# Poly Haven photoscanned fir sprigs (the twig atlas of its fir_tree_01
# model) for the needle cards of the 3D conifers: {out name: (map, format)}.
TWIG_ASSET = "fir_tree_01"
TWIG_MAPS = {"twig_albedo.jpg": ("twig_diff", "jpg"), "twig_opacity.png": ("twig_alpha", "png")}
USER_AGENT = "OpenLinks2003-asset-fetch (https://github.com/crspytopgn/openlinks2003)"



# ambientCG photoscanned sets, preferred over Poly Haven's for these slots
# (Poly Haven has no short mown lawn or fine bunker sand): {slot: asset
# ids in order}.
AMBIENT_GROUNDS = {
    "grass": ["Grass005", "Grass008"],  # short, clean lawn: fairway, green, tee
    "rough": ["Grass004", "Grass001"],  # dense, longer grass with straw
    "sand": ["Ground080", "Ground054"],  # fine bunker sand, raked and trodden
    "path": ["Concrete034", "Concrete031"],  # cart paths (tinted to the course's)
    "dirt": ["Ground103"],  # bare, worn ground
}
AMBIENT_MAPS = {"albedo.jpg": "_Color.jpg", "normal.jpg": "_NormalGL.jpg", "roughness.jpg": "_Roughness.jpg",
                "height.jpg": "_Displacement.jpg"}
AMBIENT_RES = "2K"


def texture_maps(res):
    return {"albedo.jpg": ("Diffuse", res, "jpg"), "normal.jpg": ("nor_gl", res, "jpg"), "roughness.jpg": ("Rough", res, "jpg"),
            "height.jpg": ("Displacement", res, "jpg")}


# slot: (asset type, preferred ids, fallback keywords, {out name: (map, resolution, format)})
SLOTS = {
    "grass": ("textures", ["leafy_grass", "sparse_grass", "aerial_grass_rock"], ["grass"], texture_maps("1k")),
    "rough": ("textures", ["forrest_ground_01", "forest_ground_04", "brown_mud_leaves_01"], ["forest ground", "grass"], texture_maps("1k")),
    "sand": ("textures", ["coast_sand_01", "coast_sand_02", "aerial_beach_01"], ["sand"], texture_maps("1k")),
    "path": ("textures", ["concrete_floor_02", "concrete_floor_01"], ["concrete"], texture_maps("1k")),
    "dirt": ("textures", ["brown_mud_02", "dry_ground_rocks"], ["mud", "dirt"], texture_maps("1k")),
    "bark": ("textures", ["bark_brown_02", "bark_brown_01", "pine_bark"], ["bark"], texture_maps("1k")),
    "sky": ("hdris", ["kloofendal_48d_partly_cloudy_puresky", "kloofendal_43d_clear_puresky"], ["pure sky", "clear"], {"panorama.hdr": ("hdri", "2k", "hdr")}),
}

# Import settings Godot would otherwise guess: compressed with mipmaps, as
# 3D textures need. Written next to each file before the project is imported.
# The HDR sky is not imported: pack_sky() writes it for the game instead.
TEXTURE_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode={mode}
compress/lossy_quality=0.85
mipmaps/generate={mipmaps}
process/size_limit={limit}
"""


def get(url, retries=4):
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001 - network errors of every kind are retried
            if attempt == retries - 1:
                raise
            print(f"  retrying {url}: {e}")
            time.sleep(2 ** (attempt + 1))
    return b""


def get_json(url):
    return json.loads(get(url))


def choose(kind, preferred, keywords):
    assets = get_json(f"{API}/assets?t={kind}")
    for asset_id in preferred:
        if asset_id in assets:
            return asset_id, assets[asset_id]
    matches = []
    for asset_id, info in assets.items():
        text = " ".join([asset_id, info.get("name", "")] + info.get("tags", []) + info.get("categories", [])).lower()
        if any(k in text for k in keywords):
            matches.append((info.get("download_count", 0), asset_id))
    if not matches:
        raise RuntimeError(f"no {kind} asset matches {keywords}")
    asset_id = max(matches)[1]
    return asset_id, assets[asset_id]


def pack_sky(path):
    """The HDR sky as a deflated .olsky next to it (see sky_pack.py), and the
    .hdr itself left out of the import and the export. Lossless, and half
    the size of Godot's import, which the pack stores uncompressed."""
    packed_path = os.path.splitext(path)[0] + ".olsky"
    if not (os.path.exists(packed_path) and os.path.getmtime(packed_path) >= os.path.getmtime(path)):
        with open(path, "rb") as f:
            packed, _raw = sky_pack.pack(f.read())
        with open(packed_path, "wb") as f:
            f.write(packed)
    with open(path + ".import", "w") as f:
        f.write('[remap]\n\nimporter="skip"\n')


def fetch_slot(out_dir, slot, spec):
    kind, preferred, keywords, maps = spec
    asset_id, info = choose(kind, preferred, keywords)
    files = get_json(f"{API}/files/{asset_id}")
    for out_name, (map_name, res, fmt) in maps.items():
        entry = files[map_name][res][fmt]
        path = os.path.join(out_dir, f"{slot}_{out_name}")
        if not (os.path.exists(path) and os.path.getsize(path) == entry.get("size", -1)):
            print(f"  {slot}: {asset_id} {map_name} {res} -> {path}")
            data = get(entry["url"])
            with open(path, "wb") as f:
                f.write(data)
        if fmt == "hdr":
            pack_sky(path)
            continue
        with open(path + ".import", "w") as f:
            f.write(TEXTURE_IMPORT.format(mode=1, limit=size_limit(f"{slot}_{out_name}"), mipmaps="true"))
    authors = ", ".join(info.get("authors", {}).keys())
    return f"- **{slot}**: [{info.get('name', asset_id)}](https://polyhaven.com/a/{asset_id}) by {authors or 'Poly Haven'}, CC0"


# Slots seen mostly from a distance, kept at 1024 pixels to save video
# memory in the browser.
SMALL_SLOTS = ("path_", "dirt_", "bark_")


def size_limit(out_name):
    """Roughness is soft detail: 1024 pixels is plenty and saves memory."""
    soft = out_name.startswith("roughness") or "_roughness" in out_name or "_height" in out_name
    return 1024 if soft or out_name.startswith(SMALL_SLOTS) else 0


def fetch_ambient_ground(out_dir, slot):
    """A photoscanned ground set from ambientCG for `slot`, or None."""
    for asset_id in AMBIENT_GROUNDS.get(slot, []):
        try:
            paths = {name: os.path.join(out_dir, f"{slot}_{name}") for name in AMBIENT_MAPS}
            marker = os.path.join(out_dir, f".{slot}_{asset_id}")
            if not (os.path.exists(marker) and all(os.path.exists(p) for p in paths.values())):
                print(f"  {slot}: {asset_id} {AMBIENT_RES}-JPG")
                data = get(f"{AMBIENTCG}/get?file={asset_id}_{AMBIENT_RES}-JPG.zip")
                with zipfile.ZipFile(io.BytesIO(data)) as z:
                    for name, suffix in AMBIENT_MAPS.items():
                        member = next(m for m in z.namelist() if m.endswith(suffix))
                        with open(paths[name], "wb") as f:
                            f.write(z.read(member))
                open(marker, "w").close()
            for name, p in paths.items():
                with open(p + ".import", "w") as f:
                    f.write(TEXTURE_IMPORT.format(mode=1, limit=size_limit(f"{slot}_{name}"), mipmaps="true"))
            return f"- **{slot}**: [{asset_id}]({AMBIENTCG}/view?id={asset_id}) by ambientCG, CC0"
        except Exception as e:  # noqa: BLE001 - try the next set, then Poly Haven
            print(f"  {slot}: {asset_id} failed: {e}")
    return None


def fetch_leaves(out_dir):
    for asset_id in LEAF_SETS:
        try:
            paths = {name: os.path.join(out_dir, name) for name in LEAF_MAPS}
            if not all(os.path.exists(p) for p in paths.values()):
                print(f"  leaves: {asset_id} 1K-PNG")
                data = get(f"{AMBIENTCG}/get?file={asset_id}_1K-PNG.zip")
                with zipfile.ZipFile(io.BytesIO(data)) as z:
                    for name, suffix in LEAF_MAPS.items():
                        member = next(m for m in z.namelist() if m.endswith(suffix))
                        with open(paths[name], "wb") as f:
                            f.write(z.read(member))
            # Lossless: lossy compression invents light colours under the
            # transparent pixels, which then show as bright leaf edges.
            for p in paths.values():
                with open(p + ".import", "w") as f:
                    f.write(TEXTURE_IMPORT.format(mode=0, limit=0, mipmaps="true"))
            return f"- **leaves**: [{asset_id}]({AMBIENTCG}/view?id={asset_id}) by ambientCG, CC0"
        except Exception as e:  # noqa: BLE001 - try the next set
            print(f"  leaves: {asset_id} failed: {e}")
    raise RuntimeError("no leaf set could be fetched")


def fetch_twigs(out_dir):
    """The photoscanned fir sprigs for the conifers' needle cards."""
    paths = {name: os.path.join(out_dir, name) for name in TWIG_MAPS}
    if not all(os.path.exists(p) for p in paths.values()):
        files = json.loads(get(f"{API}/files/{TWIG_ASSET}"))
        for name, (key, fmt) in TWIG_MAPS.items():
            print(f"  twigs: {TWIG_ASSET} {key} 1k")
            with open(paths[name], "wb") as f:
                f.write(get(files[key]["1k"][fmt]["url"]))
    # Imported at 512 pixels (a sprig still gets about 3 pixels a
    # centimetre), which keeps the download inside its budget. The colour
    # can be lossy: the atlas fills the gaps round the sprigs with green,
    # so no bright fringes show (unlike the leaves); the alpha is lossless.
    for name, p in paths.items():
        with open(p + ".import", "w") as f:
            f.write(TEXTURE_IMPORT.format(mode=1 if name.endswith(".jpg") else 0, limit=512, mipmaps="true"))
    return f"- **twigs**: [Fir Tree 01](https://polyhaven.com/a/{TWIG_ASSET}) twig atlas by Poly Haven, CC0"


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(here, "..", "game", "free_assets"))
    ap.add_argument("--strict", action="store_true", help="fail if any asset can't be fetched")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    credits, failed = [], []
    for slot, spec in SLOTS.items():
        try:
            credit = fetch_ambient_ground(args.out, slot)
            credits.append(credit if credit else fetch_slot(args.out, slot, spec))
        except Exception as e:  # noqa: BLE001
            print(f"WARNING: couldn't fetch {slot}: {e}")
            failed.append(slot)
    try:
        credits.append(fetch_leaves(args.out))
    except Exception as e:  # noqa: BLE001
        print(f"WARNING: couldn't fetch leaves: {e}")
        failed.append("leaves")
    try:
        credits.append(fetch_twigs(args.out))
    except Exception as e:  # noqa: BLE001
        print(f"WARNING: couldn't fetch twigs: {e}")
        failed.append("twigs")
    with open(os.path.join(args.out, "CREDITS.md"), "w") as f:
        f.write("# Free assets\n\nDownloaded by tools/fetch_free_assets.py from Poly Haven and ambientCG (CC0).\n\n")
        f.write("\n".join(credits) + "\n")
    print(f"fetched {len(credits)} of {len(SLOTS) + 2} slots")
    if failed and args.strict:
        sys.exit(1)


if __name__ == "__main__":
    main()
