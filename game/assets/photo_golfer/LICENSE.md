# Photo golfer frames

The frames of the "Photo golfer" option (Settings > Golfer > Photo). Nothing
in them comes from Links 2003 or from broadcast footage. Each take folder is
cut out of one freely licensed video by
`tools/photo_golfer/build_photo_golfer.py` (frame numbers and the ball's spot
are in `tools/photo_golfer/takes.json`):

| Take | Video | Author | Licence |
| --- | --- | --- | --- |
| `suvichaya_iron_dtl` | [Suvichaya Vinijchaitham Golf Swing Slow Mo 2026](https://commons.wikimedia.org/wiki/File:Suvichaya_Vinijchaitham_Golf_Swing_Slow_Mo_2026.webm) (Wikimedia Commons) | Hut2026 | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (public domain) |

The frames are cut out of their background (BiRefNet matting), cropped,
scaled and packed into sheets; they are otherwise unchanged. A new take must
come from a video under CC0 or CC BY (credit it here), or be filmed for the
project.
