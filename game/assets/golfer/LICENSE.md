# free_golfer.glb

The golfer shown when the original game files aren't loaded. Nothing in it
comes from Links 2003.

Built by `tools/golfer/build_free_golfer.py` from these MakeHuman assets, all
released under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
(public domain) by their copyright holders (Data Collection AB, Joel Palmius,
Jonas Hauquier) in September 2020:

| Part | MakeHuman asset | Source |
| --- | --- | --- |
| Body mesh, macro targets (male, about 35, 1.83 m) | hm08 base mesh, `targets/macrodetails` | MPFB 2.0.18 `data/` ([extensions.blender.org](https://extensions.blender.org/add-ons/mpfb/)) |
| Skeleton and skin weights | `rigs/standard/rig.game_engine.json`, `weights.game_engine.json` | MPFB 2.0.18 `data/` |
| Skin | `skins/middleage_caucasian_male` | [MakeHuman system assets](https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip) |
| Shirt and trousers | `clothes/male_casualsuit06`, recoloured to a navy shirt and stone chinos, logo removed | system assets |
| Shoes | `clothes/shoes05` | system assets |
| Hair, eyes, eyebrows, eyelashes | `hair/short02`, `eyes/high-poly` (brown), `eyebrows/eyebrow001`, `eyelashes/eyelashes01` | system assets |

Only MakeHuman's data files are read; no MakeHuman or MPFB code is used. The
clubs, the poses and the animations (address, backswing, swing, putt,
celebrate) are this project's own work, keyed by hand in
`tools/golfer/pose.py` and `tools/golfer/build_free_golfer.py`, and are
released with the rest of the repository under its MIT licence.
