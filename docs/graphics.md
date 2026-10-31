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

## Device tiers

- The browser build picks Natural on capable devices
  (`GraphicsSettings.web_capable()`): every iPad and iPhone, recent Adreno,
  Mali, Immortalis and Xclipse phone GPUs, and desktop browsers on a real
  GPU. There it runs at High quality, with grass level 2 and 3D trees.
  Other phones get Performance, and software renderers never get the higher tier.
- Saved preset settings carry a `look_version`. When the presets change,
  they are redone once, and a capable device that an older version put on
  Performance moves up.

## Effects

- **Lighting** (`Scenery.apply`): Classic is the linear tone map with flat
  colour ambient, tuned so the textures keep their own colours. Photoreal
  uses the AgX tone map (natural highlights, no lime greens), a strong,
  warm sun against fill about a fifth as bright (from the sky on Forward+,
  a quarter stronger flat fill on Compatibility so shade isn't black),
  stronger aerial perspective, volumetric haze with light shafts (Forward+,
  Ultra) and screen-space reflections on water (Forward+, High and up).
- **Global illumination** (`Scenery.gi_available`): at Ultra with Photoreal
  lighting on Forward+ and a real graphics card, SDFGI bounces sunlight off
  the turf into the shade and shuts the sky out under trees (six cascades
  from 0.4 m cells; the flat fill drops to 60% to make room). Never on
  software renderers or the web. Ultra also gets the softest sun shadow
  filter, and High the next one down.
- **Post pass** (`PostProcess`, `shaders/post_process.gdshader`): contrast-
  adaptive sharpening, colour grading (Neutral, Vivid, Warm afternoon, Cool
  morning, Film), vignette and film grain in one full-screen pass. It works
  on both renderers and is hidden when every effect is off.
- **Bloom** is the renderer's glow. **SSAO** (plus SSIL at Ultra) and
  **depth of field** (far blur only, so the ball and golfer stay sharp) need
  Forward+.
- **Time of day** (Settings > Graphics, Photoreal lighting only, not part
  of the looks): Afternoon (the light the game always had), Morning,
  Midday, Golden hour, or Through the round, which moves the sun from
  morning on the first hole through midday to golden hour on the last
  (`Scenery.TIMES`, `ROUND_TIMES`). Each sets the sun's height, bearing,
  colour and strength, the fill light's colour, an exposure that makes up
  for a low sun, the haze colour and thickness, and a tint for the
  photographed sky (`shaders/photo_sky.gdshader`, with a warm glow round
  a low sun), the course's horizon band and the sky in the water (the
  global `sky_tint`). The baked ground shade follows the sun, since it is
  baked at each hole's start after the sun has moved. Classic lighting
  keeps Links 2003's fixed afternoon sun.
- **Upscaler**: FSR 1 or FSR 2 on Forward+. **Dynamic resolution**
  (`DynamicResolution`) lowers the 3D resolution, down to half, when frames
  miss 30 or 60 fps and raises it again when there's room.

## World detail

- **3D grass** (`GrassField`, `shaders/grass.gdshader`): tufts of blades in
  the rough and deep rough only, in 12 m chunks around the camera, built two
  chunks a frame. Tufts take the colour of the ground under them
  (`CourseTerrain.ground_color_at`), bend with the wind and shrink away at
  the edge of the radius, so there's no visible line. Low, Medium and High
  reach 22, 36 and 55 m. A tuft is eight thin blades of three triangles,
  each with its own shade and about one in five dry and straw-coloured,
  dark at the root and bleached at the tip. Visual only: the ball never
  sees it. The shader
  must not use `specular_disabled`: in Compatibility (the web build) that
  drops the sun from the blades and they go dark. Compatibility also has no
  sky fill light, so `GrassField` lifts the blades' `brightness` there.
- **Trees in the wind**: the course billboards sway with the hole's wind
  (`foliage_sway` and `wind_vector` global shader uniforms, set by
  `GolfRound`). The 3D trees and bushes lean with the wind and rock with
  its gusts as a whole, more the higher up, trunk and branches with the
  leaves (`shaders/tree_wind.gdshaderinc`, shared by the bark and leaf
  shaders), and each leaf spray flutters on top. Classic Links keeps them
  still, as in the original.
- **3D trees** (`TreeFactory`, `shaders/tree_*.gdshader`): generated
  from a seed (three broadleaf, two pine and two bush variants): tapered
  branches with the free bark photo (Poly Haven), and leaf cards that each
  draw a spray of turned leaves from a photographed leaf set (ambientCG),
  or plain leaf shapes and needle sprigs without it. A broadleaf crown is
  clumps of sixteen small cards round each of about forty twig tips; each
  card holds a 7 by 7 grid of leaves (20 to 30 cm), nudged off their cells,
  shaded and tinted one by one, and thinned out towards the card's rim so
  it reads as a round, ragged spray rather than a square. Leaf normals
  point out from the middle of the crown, and the leaves use their own
  soft light (wrapped diffuse, light through the leaves, no specular,
  and a little fill of their own, more in Compatibility, which has no sky
  light), so a crown shades as one mass. A core of densely leaved cards
  fills each crown, so gaps show shaded leaves, not black. Bushes are a few
  thin stems under a low, wide crown of smaller sprays. Up to 6,000
  triangles a tree. Beyond 35, 70 or 120 m (the Trees setting: 3D near, 3D, 3D far)
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
  is scaled to its billboard's height. Bush billboards 0.6 m and taller
  become 3D bushes the same way (hedges keep their billboards), and the
  placeholder course has forty bushes along the edge of its trees. The ball's obstacles
  come from the course data, not the meshes. Leaf textures are sampled
  with gradients from the card's UV (the turned cells jump at their
  borders, which picks wild mip levels and sparkles in Compatibility).
- **Baked ground shade** (`GroundShade`, `shaders/ground_shade*`): when a
  hole starts, every tree, bush and rock billboard and every 3D model
  within 250 m of the tee, route and pin stamps a soft shadow (along
  the sun, stretched by the crown's height) and a soft dark patch at its
  foot into one top-down map, up to 1536 pixels and at least 0.5 m a
  pixel. The stamps are soft ellipses, or for a tree or bush with a shape
  in the course's `.SHA` file that shape ([sha.md](formats/sha.md), from a
  64-pixel-a-cell atlas), in one MultiMesh, multiplied into a
  white off-screen viewport on the GPU and read back once. The ground
  and grass shaders darken by it (R the sun shadow, G the occlusion)
  through global uniforms. The disc courses' standard ground materials
  get it from a next pass that draws black with the shade as alpha.
  (`blend_mul` darkened everything in Compatibility.) Near the camera,
  where the full 3D trees cast real-time shadows, the baked sun shadow
  fades out. Billboards and impostors cast no real-time shadows, so far
  trees get shadows only from this map.
- **Photo ground on disc courses** (`CrzTerrain.photo_ground`,
  `shaders/course_ground.gdshader`): with Photoreal lighting (every look
  but Classic), grass, fairway, green, rough, deep rough and sand draw the
  free photoscanned set of their surface (albedo, normal and roughness:
  ambientCG's short lawn for mown grass, dense long grass for rough, fine
  bunker sand, concrete for cart paths and bare ground for dirt) instead
  of the disc's 2003 texture. Paths and dirt keep their own hue
  (`realistic_class`). Greens draw the lawn scan at 0.6 m a repeat, so
  they read as fine putting turf next to the coarser collar. Path, dirt
  and bark sets stay at 1024 pixels to save video memory. The lawn scan's
  light and dark is boosted (`PHOTO_GAINS`), since it is shot in soft light
  and would read flat at playing distance; its roughness map gives glossy
  and matt blades near the camera. The photo's detail sits on the course's own colour for that
  material (the mean of its disc texture), made darker and deeper as real
  turf is (`realistic()`; pale disc rough becomes straw and olive). It is
  sampled at two scales, fades to its mean colour with distance, and has
  large lighter and darker patches. Fairways and greens get mowing stripes.
  Paths, dirt and rocks keep the disc textures. A blended edge (fairway to
  rough, round bunkers and tees) draws both layers' photo grounds, faded by
  the course's own ragged edge mask.
- **Free course turf** (`terrain.gdshader`, `PlaceholderTerrain`, the
  designer's colours): olive, yellow-green turf rather than lime; crisp
  mowing stripes along the hole on fairways, greens and tees (7 m wide,
  from the mesh's UV: x across the hole, -y the stripe strength, so other
  meshes get none); a first cut of slightly darker rough 2.5 m wide
  beside the fairway (colour only, the ball plays it as rough); bunkers
  with a trimmed, slightly ragged edge sharpened from the sand weight
  (the sand colour taken back out of the grass beside it) and a shaded
  lip of turf; and with 3D trees on, two rows of woods round the edge of
  the ground, out of bounds and mostly impostors, so the hole no longer
  ends in a bare edge against the sky.
- **Water's edge**: a disc course's water triangles carry how far each
  vertex is from the bank (`CrzTerrain._shore_levels`: 0 on a vertex dry
  ground also uses, 0.5 one triangle out, 1 beyond, in the vertex colour).
  The water shader turns that into browner shallows that reflect less, a
  darker wet margin, and a thin, broken line of froth lapping the bank,
  all along a ragged, noisy line rather than the triangles' edges. Round
  ponds (placeholder course) do the same from their radius and fade into
  the bank along it. Designer and real-course ponds are the outline plus
  a grid of points every 4 m inside it (Delaunay, kept where a triangle's
  middle is inside), each carrying its distance from the bank over 10 m
  (`DesignedTerrain.water_surface_mesh`). The finest ripples are drifting noise instead of
  more sine waves (whose crossings showed a regular diamond pattern), and
  gusts roughen patches of the surface and leave others glassy.
- **Texture mappings and blended edges** (`TerrainMappings`,
  `shaders/terrain_mapped.gdshader`): the disc textures lie on the ground
  the way the course's `Mappings` entry says (per-hole fairway planars
  turned along the hole, cart paths running along the path, cylinders on
  rock walls; [crz.md](formats/crz.md#mappings-texture-projections)). The
  mesh carries the first layer's coordinates in UV, the second's in UV2
  and the mask's in CUSTOM0. Blended materials fade one texture into the
  other through their `... Alpha.tga` mask, so the edges between fairway
  and rough are soft and ragged instead of following the triangles.
- **Cloud shadows** (`cloud_shadow`, `cloud_offset` in
  `ground_shade.gdshaderinc`; Settings > Graphics): soft patches of value
  noise a few hundred metres across that drift with a wind aloft (2.5
  times the course's wind, at least 3 m/s) and take 32% of the light. Every
  ground shader and the grass take them through `ground_shading()`. On in
  every look but Classic and Performance.
- **Sky with Photoreal lighting**: the photographed cloud sky (Poly Haven)
  replaces the disc's painted sky. The course's own horizon panorama
  stays, which keeps Kauri's sea, and fades 30% into the haze.
  Compatibility shows the sky brighter, since it has no sky fill light.
  The water reflects the photographed sky itself (its clouds), with the
  far banks dark and green at the bottom of the reflection and a quarter
  of every reflection taken by the banks round it; the water's own colour
  is a dark, slightly green deep.
  The water reflects at most 60% of the plain sky colour (80% of the
  photographed sky), so a glancing view still shows deep water, not white.
  When the player picks a sky in Settings
  (anything but the course's own), Photoreal shows that disc sky instead
  and the light follows its weather (`Scenery._apply_weather`): the sun
  loses up to 65% of its energy and, in Forward+, its shadows soften,
  while the fill light grows by up to 60%; Sunrise and Mojave Sunset warm
  the sun. Classic always shows the chosen or course sky.
- **Matt surfaces**: ground (every terrain shader), grass tufts, trees
  and the golfer's cloth and skin are matt (roughness 0.9 to 1, specular
  0.1), so the sun and sky leave no plastic sheen; only the water and
  the clubs shine. The photo ground's colours (`realistic()`) are a little
  lighter to make up for the glare they no longer get.
- **Ground relief** (`PHOTO_RELIEF` in `crz_terrain.gd`): each photo set's
  height map shifts the texture with the view within about 35 m
  (two-step parallax, a few millimetres to 5 cm of relief per surface)
  and darkens its low parts and lightens its tops around the map's own
  mean (cavities between blades, pebbles and footprints), fading out
  sooner on finely tiled ground (greens) before its repeat shows, so the
  ground looks deep rather than printed on.
- **Billboards with Photoreal lighting** (`billboard_photo`, the shader in
  `course_objects.gd`): the disc's plant sprites are toned like the photo
  ground (more colour, less light, darker at the root where a clump
  shades itself), less so far away, and every sprite, spectators too,
  takes the cloud shadows passing over the ground. Not the baked ground
  shade: that map is dark wherever plants stand, their own occlusion
  included.
- **Photoreal grade** (`PostProcess.PHOTO_NEUTRAL`, `PHOTO_CURVE`): the
  Neutral grade under Photoreal lighting adds a gentle filmic S-curve on
  luminance, slightly warm highlights and cool shadows, so the render
  reads less flat and hazy. The other grades are unchanged.
- **Course shading from the `.SHA` file** ([sha.md](formats/sha.md)):
  billboards are darkened by how much light the course says reaches them
  (an instance colour, so trees inside a wood are deeper than those in the
  open), and 3D objects stamp their own footprint into the baked ground
  shade as a shadow and a soft darkening underneath.
- **Distance texture variants** (`terrain_mapped.gdshader`): disc ground
  textures fade into their coarser `... 32.tga` and `... 128.tga` variants
  with distance, which hides the tiling across a fairway. Only uniform
  branches, so it costs nothing on materials without variants and works in
  Compatibility.
- **Ground**: disc textures borrow the free photo texture's normal map at a
  low strength, so a low sun picks out the grain, and mown surfaces get a
  faint sheen. Course water uses the animated water shader instead of a flat
  colour, with finer, wind-driven ripples.
- **Gusts** (`WindGust`): the wind the eye sees surges and settles every
  few seconds (55% to 145% of the hole's wind, swinging up to 8 degrees),
  through the `wind_vector` shader global, so the flag, grass, trees and
  water ripples move together. Visual only: the ball flies in the game's
  own per-shot wind.
- **Flag** (`shaders/flag.gdshader`): a 20 by 14 inch flag on a 7 ft
  stick, as the Rules ask. It swings round the pole to fly downwind, lifts
  from hanging limp to straight out at about 20 mph, ripples faster as the
  wind gets up, and glows when the sun is behind it. Players can read the
  wind from it, as real golfers do.
- **Course marks** (`CourseMarks`, `shaders/course_mark.gdshader`): iron and
  wedge shots off the fairway or rough take a divot just ahead of the ball
  (longer for wedges, a nick off a tee, small for chips; woods and hybrids
  sweep it), approach shots landing hard on the green leave a pitch mark,
  and balls landing in sand leave a crater (a bunker shot leaves a long
  scoop). They last for the hole, at most 48 of them. Each is one small
  lit quad, so they cost almost nothing. Looks only. Golfers in a bunker
  leave shoe prints: the stance, and the walk in from behind the ball up to
  the edge of the sand.
- **True to scale at the pin**: the hole is its real 4.25 in (108 mm)
  across, painted (`shaders/cup.gdshader`) with the cut turf edge and the
  white liner on the far wall, which always faces the camera as in a real
  cup. The flagstick is 7 ft tall and 19 mm thick.
- **Tee peg**: a teed-up ball sits on a white peg, higher for the driver
  (2.5 cm of air under it) than for woods (1.2 cm) and irons (5 mm). The
  peg stays in the ground after the shot.
- **Ball contact shadow** (`shaders/ball_shadow.gdshader`): a soft dark
  blob under the ball, since a golf ball is too small for the sun's shadow
  maps. It follows the ball over the ground in flight and fades as it
  climbs.
- **Ball size** (Settings): drawn bigger with distance, as Links does, or
  at its true size everywhere.
- **Birds** (`CourseLife`, `shaders/bird.gdshader`): every 25 to 70
  seconds a small flock (3 to 9 birds in a loose V) crosses the sky 30 to
  70 m up, flapping and gliding. Each flock is one MultiMesh draw call.

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

## Download size

`tools/size_report.py` runs after the CI export. It writes each build's
download size, its game data (the `.pck`) and the biggest files in the pack
to the job summary, and fails CI when a build goes over
`tools/size_budget.json`. When it was added (2026-10-31) the game data was
33 MB, a third of it the HDR sky, and the Godot engine was the rest of each
download (about 70 MB uncompressed on Linux). Two import changes took the
data from 33 to 27.7 MB without changing the look (30.5 MB once the photoscanned sand, paths and height maps of #79 landed):

- the sky panorama has no mipmaps (it is only ever magnified), and
- textures without their own `.import` settings (the golfer's, extracted
  from its `.glb`) default to lossy WebP at quality 0.85 through
  `[importer_defaults]` in `project.godot`, instead of lossless.

`.import` files are not committed, so import settings live in
`tools/fetch_free_assets.py` (the free textures) and `project.godot` (the
defaults).

## Still to do

- Occlusion from the terrain itself (hollows, cliffs).
- Texture compression tiers per device (Basis/ASTC), and the HD pack in
  the browser.
