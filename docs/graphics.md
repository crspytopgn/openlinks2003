# Graphics: looks, effects and performance

The game aims for two things at once: a photoreal course on a gaming PC,
and a smooth, good-looking round on a cheap laptop, a phone or the browser.
Golf helps with both, because the scene is static and the camera sits still
between shots. None of this touches the physics.

## Looks

Settings has a **Look** preset that sets every option below. Changing any
single option makes the look **Custom**.

| Look | Lighting | Upscaler | Effects | 3D grass | Trees |
| --- | --- | --- | --- | --- | --- |
| Photoreal | Photoreal, Ultra | FSR 2 at full resolution (temporal AA) | sharpen, bloom, SSAO, far depth of field, light vignette and grain | High | 3D far |
| Natural | Photoreal, High | none, MSAA 2x | light sharpen, bloom, SSAO, vignette | Medium | 3D |
| Cinematic | Photoreal, Ultra | FSR 2 | strong bloom, film grade, vignette, grain, depth of field | High | 3D far |
| Classic Links | Classic (Links 2003's flat colours) | none, MSAA 2x | none | off | classic |
| Performance | Photoreal, Low | FSR 1 at 75% (stretched in the browser), sharpened | none | Low | 3D near |

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
  reach 22, 36 and 55 m. Visual only: the ball never sees it. The shader
  must not use `specular_disabled`: in Compatibility (the web build) that
  drops the sun from the blades and they go dark. Compatibility also has no
  sky fill light, so `GrassField` lifts the blades' `brightness` there.
- **Trees in the wind**: the course billboards sway with the hole's wind
  (`foliage_sway` and `wind_vector` global shader uniforms, set by
  `GolfRound`). Classic Links keeps them still, as in the original.
- **3D trees** (`TreeFactory`, `shaders/tree_*.gdshader`): generated
  from a seed (three broadleaf and two pine variants): tapered branches
  with the free bark photo (Poly Haven), and leaf cards that each draw a
  grid of turned leaves from a photographed leaf set (ambientCG), or plain
  leaf shapes and needle sprigs without it. Leaf normals point out from the
  middle of the crown, and the leaves use their own soft light (wrapped
  diffuse, light through the leaves, no specular), so a crown shades as
  one mass. A solid dark core fills each crown. Up to 6,000 triangles a
  tree. Beyond 35, 70 or 120 m (the Trees setting: 3D near, 3D, 3D far)
  a tree becomes an impostor: one camera-facing quad showing the nearest
  of 8 views, baked once into an atlas (a row per variant) by rendering
  every variant into one off-screen viewport the first time a tree is
  made. Headless runs render nothing, so they keep the full trees. The
  3D trees replace the placeholder course's trees, and on a disc course
  its tree billboards 3 m and taller (broadleaf for "Trees", maples and
  the like, pine for evergreens; palms, dead trees and bushes keep their
  billboards). Course trees are drawn in MultiMeshes per 100 m chunk: the
  full trees of each 50 m cell per variant, hidden a little past the
  impostor distance, and one impostor MultiMesh for the chunk. The shaders
  switch each tree between the two at the camera's distance (the global
  `tree_impostor_distance`, measured from the main camera, so shadows
  agree). Variant and yaw come from a hash of the position, and each tree
  is scaled to its billboard's height. The ball's obstacles
  come from the course data, not the meshes. Leaf textures are sampled
  with gradients from the card's UV (the turned cells jump at their
  borders, which picks wild mip levels and sparkles in Compatibility).
- **Baked ground shade** (`GroundShade`, `shaders/ground_shade*`): when a
  hole starts, every tree, bush and rock billboard and every 3D model
  within 250 m of the tee, route and pin stamps a soft shadow (along
  the sun, stretched by the crown's height) and a soft dark patch at its
  foot into one top-down map, up to 1536 pixels and at least 0.5 m a
  pixel. The stamps are soft ellipses in one MultiMesh, multiplied into a
  white off-screen viewport on the GPU and read back once. The ground
  and grass shaders darken by it (R the sun shadow, G the occlusion)
  through global uniforms. The disc courses' standard ground materials
  get it from a next pass that draws black with the shade as alpha.
  (`blend_mul` darkened everything in Compatibility.) Near the camera,
  where the full 3D trees cast real-time shadows, the baked sun shadow
  fades out. Billboards and impostors cast no real-time shadows, so far
  trees get shadows only from this map.
- **Ground**: disc textures borrow the free photo texture's normal map at a
  low strength, so a low sun picks out the grain, and mown surfaces get a
  faint sheen. Course water uses the animated water shader instead of a flat
  colour, with finer, wind-driven ripples.

## Performance budget

`tests/render_check.gd` fails CI when the round goes over its budget, both
at the flyover and from the tee, in Compatibility and Forward+, with the
Photoreal look: 1,500 draw calls (shadow passes included), 2 million
triangles, 2,500 scene objects and 512 MB of video memory per frame
(1 GB in Forward+, which is desktop only: at Ultra its 8192-pixel shadow
atlas alone takes 256 MB, and CI measured 590 MB at the flyover). These
are counts rather than frame times, because CI renders in software and its
timings say nothing about a player's GPU. Counts are what make a scene slow
on phones and in the browser. The placeholder course used about 580 draw
calls, 0.7 million triangles, 1,100 objects and 125 MB from the tee in
Compatibility when the budget was set. Raise a limit only with a reason
written here.

## Still to do

- Cloud shadows, and occlusion from the terrain itself (hollows, cliffs).
- Texture compression tiers per device (Basis/ASTC), and the HD pack in
  the browser.
