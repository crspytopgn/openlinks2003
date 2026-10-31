# Graphics: looks, effects and performance

The game aims for two things at once: a photoreal course on a gaming PC,
and a smooth, good-looking round on a cheap laptop, a phone or the browser.
Golf helps with both, because the scene is static and the camera sits still
between shots. None of this touches the physics.

## Looks

Settings has a **Look** preset that sets every option below. Changing any
single option makes the look **Custom**.

| Look | Lighting | Upscaler | Effects | 3D grass |
| --- | --- | --- | --- | --- |
| Photoreal | Photoreal, Ultra | FSR 2 at full resolution (temporal AA) | sharpen, bloom, SSAO, far depth of field, light vignette and grain | High |
| Natural | Photoreal, High | none, MSAA 2x | light sharpen, bloom, SSAO, vignette | Medium |
| Cinematic | Photoreal, Ultra | FSR 2 | strong bloom, film grade, vignette, grain, depth of field | High |
| Classic Links | Classic (Links 2003's flat colours) | none, MSAA 2x | none | off |
| Performance | Photoreal, Low | FSR 1 at 75% (stretched in the browser), sharpened | none | Low |

On the first run (or with settings saved before looks existed),
`GraphicsSettings.detect_look()` picks one: Photoreal on a dedicated GPU,
Natural on integrated graphics and desktop browsers, and Performance on
phones, tablets and software renderers. The browser build also caps quality
at Medium and grass at Low.

## Effects

- **Lighting** (`Scenery.apply`): Classic is the linear tone map with flat
  colour ambient, tuned so the textures keep their own colours. Photoreal
  uses ACES, a brighter, warmer sun, fill light from the sky on Forward+,
  stronger aerial perspective, volumetric haze with light shafts (Forward+,
  Ultra) and screen-space reflections on water (Forward+, High and up).
- **Post pass** (`PostProcess`, `shaders/post_process.gdshader`): contrast-
  adaptive sharpening, colour grading (Neutral, Vivid, Warm afternoon, Cool
  morning, Film), vignette and film grain in one full-screen pass. It works
  on both renderers and is hidden when every effect is off.
- **Bloom** is the renderer's glow. **SSAO** (plus SSIL at Ultra) and
  **depth of field** (far blur only, so the ball and golfer stay sharp) need
  Forward+.
- **Upscaler**: FSR 1 or FSR 2 on Forward+. **Dynamic resolution**
  (`DynamicResolution`) lowers the 3D resolution, down to half, when frames
  miss 30 or 60 fps and raises it again when there's room.

## World detail

- **3D grass** (`GrassField`, `shaders/grass.gdshader`): tufts of blades in
  the rough and deep rough only, in 12 m chunks around the camera, built two
  chunks a frame. Tufts take the colour of the ground under them
  (`CourseTerrain.ground_color_at`), bend with the wind and shrink away at
  the edge of the radius, so there's no visible line. Low, Medium and High
  reach 22, 36 and 55 m. Visual only: the ball never sees it.
- **Trees in the wind**: the course billboards sway with the hole's wind
  (`foliage_sway` and `wind_vector` global shader uniforms, set by
  `GolfRound`). Classic Links keeps them still, as in the original.
- **Ground**: disc textures borrow the free photo texture's normal map at a
  low strength, so a low sun picks out the grain, and mown surfaces get a
  faint sheen. Course water uses the animated water shader instead of a flat
  colour, with finer, wind-driven ripples.

## Still to do

- Photoscanned 3D trees (with impostors at distance) as an option in place
  of the disc billboards, keeping the same collision shapes.
- Baked shadows and AO per hole for the static scenery, and cloud shadows.
- Texture compression tiers per device (Basis/ASTC), a frame-time and
  draw-call budget check in CI, and the HD pack in the browser.
