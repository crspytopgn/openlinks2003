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

## Realistic people (Microsoft Rocketbox)

The realistic golfers in `free_golfer_parts.olg` (parts `RB_*`, listed in
`PlayerLook.PEOPLE`) are avatars from the Microsoft Rocketbox library
(https://github.com/microsoft/Microsoft-Rocketbox): `Male_Adult_08`,
`Male_Adult_09`, `Male_Adult_11`, `Male_Adult_14`, `Female_Adult_13` and
`Female_Adult_17`. `tools/golfer/rocketbox.py` moves their meshes and skin
weights onto this golfer's skeleton, resizes their textures, adds the
clothes-region masks used to dye them, and fits the golf cap to each head.
They are used under the MIT licence:

> MIT License
>
> Copyright (c) Microsoft Corporation.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE
