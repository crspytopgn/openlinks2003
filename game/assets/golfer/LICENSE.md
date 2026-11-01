# free_golfer.glb and free_golfer_parts.olg

The golfer shown when the original game files aren't loaded, and the body,
outfits and hair the player creator offers (the `.olg` look pack). Nothing
in them comes from Links 2003.

Built by `tools/golfer/build_free_golfer.py` from these MakeHuman assets, all
released under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
(public domain) by their copyright holders (Data Collection AB, Joel Palmius,
Jonas Hauquier) in September 2020:

| Part | MakeHuman asset | Source |
| --- | --- | --- |
| Body mesh, macro targets (male, about 35) | hm08 base mesh, `targets/macrodetails` | MPFB 2.0.18 `data/` ([extensions.blender.org](https://extensions.blender.org/add-ons/mpfb/)) |
| Body and face shapes (blend shapes) | `targets/macrodetails` (female, build, muscle, age), `targets/head`, `chin`, `cheek`, `nose`, `eyes`, `mouth`, `eyebrows`, `ears` | MPFB 2.0.18 `data/` |
| Skeleton and skin weights | `rigs/standard/rig.game_engine.json`, `weights.game_engine.json` | MPFB 2.0.18 `data/` |
| Skin | `skins/middleage_caucasian_male`, `skins/middleage_caucasian_female`, turned into grey detail for tinting | [MakeHuman system assets](https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip) |
| Outfits | `clothes/male_casualsuit06`, `male_casualsuit02`, `female_casualsuit02`, logos removed, turned into grey detail for tinting | system assets |
| Shoes | `clothes/shoes05` | system assets |
| Hair | `hair/short02`, `short03`, `short04`, `ponytail01`, `bob01`, `long01`, `afro01`, turned into grey detail for tinting | system assets |
| Eyes, eyebrows, eyelashes | `eyes/high-poly` with the `brown`, `brownlight`, `green`, `blue` and `grey` materials, `eyebrows/eyebrow001`, `eyelashes/eyelashes01` | system assets |

The face's fine detail (pores, lines, creases and the uneven colour of real
skin, two images in the look pack) is taken by `tools/golfer/face_detail.py`
from the "Lee Perry-Smith" head scan by Infinite Realities
(Lee Perry-Smith, [ir-ltd.net](https://ir-ltd.net/)), released under
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/), as shipped with
three.js (`examples/models/gltf/LeePerrySmith`). Changed: only the detail
finer than about a centimetre is kept (the scan's colour over a blur of
itself, and its normal map less a blur of it), fitted onto this golfer's
face, with his brows, lips, shut eyes and stubble left out.

Only MakeHuman's data files are read; no MakeHuman or MPFB code is used. The
clubs, the golf cap and the reference address poses are this project's own
work, keyed by hand in `tools/golfer/pose.py` and
`tools/golfer/build_free_golfer.py`, and are released with the rest of the
repository under its MIT licence.

The animations are motion capture, retargeted onto the golfer by
`tools/golfer/mocap_swing.py` (the wrist hinge, the club carry, the look at
the target and the retiming are this project's), from these takes of the
CMU Graphics Lab Motion Capture Database in Bruce Hahne's BVH conversion:
64_01 (address and swing), 64_13 (putting address and putt), 69_01 (walk),
79_69 (celebrate), 79_74 (upset), 77_02 (the caddie standing at ease)
and 77_08 (crouching to read a putt). CMU's terms: "This
data is free for use in research and commercial projects worldwide."

The data used in this project was obtained from mocap.cs.cmu.edu. The
database was created with funding from NSF EIA-0196217.
