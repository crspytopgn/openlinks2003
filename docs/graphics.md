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
  GPU. There it runs at High quality, with grass level 2 (3 on iPads and
  other large-screen iOS devices) and 3D trees. Shadows reach at most
  200 m in the browser, so the shadow map stays sharp near the golfer.
  Other phones get Performance, and software renderers never get the higher tier.
- The terrain shader used by the default and designed courses reads the
  grass and rough scans' height maps. Within about 35 m the texture shifts
  with the view (one parallax step), and within about 110 m low parts
  darken around each map's mean (sand has no height map, to stay within
  WebGL 2's sixteen textures). The default course draws its surfaces from
  a 1 m splat map with a first cut of rough, so edges are crisp.
- Saved preset settings carry a `look_version`. When the presets change,
  they are redone once, and a capable device that an older version put on
  Performance moves up.

- The default lens is 40 degrees (vertical), as on TV golf. The aim view
  stands further back to match (`RoundCamera.lens_factor`), so the golfer
  keeps his size and the hole behind him is compressed. It also pitches
  down to keep the ball off the bottom edge. Settings offers 35 to 80
  degrees, and the old default of 50 moves to 40 once.

## Effects

- **Lighting** (`Scenery.apply`): Classic is the linear tone map with flat
  colour ambient, tuned so the textures keep their own colours. Photoreal
  uses the AgX tone map (natural highlights, no lime greens), a strong,
  warm sun against fill about a fifth as bright (from the sky on Forward+,
  a 60% stronger flat fill on Compatibility, as real shade is far lighter
  than ours measured), a sky-coloured shade fill on the ground, rough and
  fescue (`shade_fill`, `Scenery._update_shade_fill`; on Forward+ too,
  more gently, as its own shade was also near black under trees:
  even skylight added as emission and the lit albedo scaled to match, so
  sunlit turf keeps its brightness while tree shade reads about 55% as
  bright as sun, a darker, bluer green, as in real photos, where its tone
  curve and grade had crushed it to about 10%, near black), turf toned to real course photos (`turf_tone.gdshaderinc`:
  about 30% less saturated and nudged to olive; 50 photos measured in Lab),
  stronger aerial perspective, a lower 30 degree afternoon sun for long
  shadows (Classic keeps Links' 38 degrees), a natural grade (saturation
  1.12, a slight warm balance; 2K25's greens are olive, not lime), glow only
  off real highlights (no whole-image bloom veil), volumetric haze with light shafts (Forward+,
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
  reach 22, 36 and 55 m, with 4, 8 and 13 tufts a square metre on a
  jittered grid (an even sward, not clumps and bare patches) out to 45% of
  the reach and a quarter of that beyond, where the tufts are sinking into
  the ground; a chunk is rebuilt when it crosses that line. A tuft is
  twelve thin blades of three triangles spread over its footprint, each
  with its own shade and about one in ten dry, dark down in the tuft and
  a deeper, cooler green at the tip, so the rough reads as a dense, dark
  fur rather than bright tips on the ground. Heights follow real cuts: the
  first cut 3.5 to 5 cm (`CourseTerrain.first_cut_at`), rough 6 to 11 cm,
  deep rough 12 to 22 cm. Visual only: the ball never
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
  Conifer needle cards draw photoscanned fir sprigs from Poly Haven's
  fir_tree_01 twig atlas (colour and alpha maps, fetched by
  tools/fetch_free_assets.py): two by three sprigs of 40 to 55 cm per card,
  each one of four in the atlas. Broadleaf cards draw a whole photo
  branch spray when the spray atlas is there: `tools/trees/leaf_spray.py`
  (run by fetch_free_assets.py, needs Pillow) lays the photo leaves out
  along twigs at real size (7 to 11 cm on a 2 m card), tilted, overlapping,
  darker behind and each shadowing the leaves under it, as 2 x 2 sprays.
  A card shows one of them, mirrored at random, and fades out when seen
  edge-on (a card on edge smears its leaves into streaks); the crown's
  core is solid inside a ragged outline from the same sprays. The leaves
  are no longer on a grid, so the dot and checkerboard patterns at a
  distance are gone, and the impostors are baked from the same cards.
  Without the atlas the cards fall back to the grid of single leaves
  above. Poly Haven's whole scanned trees (2 to 17
  million triangles, 50 to 960 MB each) are too heavy to ship.
- **Tall fescue** (`FescueField`, `shaders/fescue.gdshader`): the deep
  rough, which is most of a hole's ground out of play, grows tufts of long
  grass 40 to 75 cm tall from about 15 m (fading in to 45 m, past the near
  3D tufts, so a ball in the rough by the camera stays in view) out to 90,
  140 or 180 m by the Grass setting, 0.4 to 0.8 tufts a square metre.
  Each tuft is three crossed cards from the fescue atlas, which
  `tools/grass/fescue_atlas.py` draws (no download, needs Pillow; run by
  fetch_free_assets.py): a low mass of fine grey-green blades, a quarter
  of them straw towards the tip, leaning and bending, with thin stalks of
  pale buff seed heads standing above (as in Geograph photos of summer
  links rough; the first atlas, all straw-gold and thick, read as yellow
  dots from the tee). The cards take about half the ground's colour, more
  further off (higher mips) where the blades blur together, hold their
  blades up under the alpha test only a little so a far tuft doesn't close
  into a blob, and vary tuft to tuft, sway in the wind, take the
  baked tree shade, and are built in 32 m chunks, two a frame, as the
  camera moves. Without it the built-in course's hills read as green felt.
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
  beside the fairway (colour only, the ball plays it as rough; designed
  courses, the built-in one included, paint one 1.8 m wide,
  `DesignedTerrain.FIRST_CUT_WIDTH`, and grow shorter 3D grass on it); bunkers
  with a trimmed, slightly ragged edge sharpened from the sand weight
  (the sand colour taken back out of the grass beside it) and a shaded
  lip of turf; and with 3D trees on, a wood round the edge of the ground,
  out of bounds: a skirt of shrubs, two rows of full trees, two deeper
  rows that are only ever impostors (`TreeFactory.FAR_ONLY`), and behind
  them a dark, unlit band (`_wood_floor`) so no sky shows under the
  crowns. Impostors darken towards their base, as the crown shades its
  trunk. The pond bed is dark silt rather than the map's blue.
- **Greens, collars and tees** (`terrain.gdshader`, `Materials.terrain_cut`,
  2026-11-04, checked against Geograph photos of real greens): a green
  reads about a tenth lighter than the ground round it and is one even,
  fine sward: none of the fairway's wide light and dark patches, the lawn
  scan at a fifth of its size, little relief and faint 0.55 m stripes.
  Round it runs the collar (`DesignedTerrain.COLLAR_WIDTH`, 1.2 m, raster
  code 10, plays as fringe): a deeper, unstriped ring cut a little
  longer. Wider fringe beyond it is the approach, striped like the
  fairway. The green's edge is one smooth, crisp mown line: the signed
  distance to each green's outline is baked at 1 m into the rows below
  the surface codes in the splat texture (`_green_edges`), since the
  0.5 m codes alone drew it as scallops. Tees are cut finer than before
  too, with fewer patches. Mowing stripes near the camera (within about
  10 m) take their light and dark from the view's heading rather than
  each pixel's, so a stripe keeps one tone along its length on a wide
  close-up instead of breaking into blotches. Stripes fade to their mean
  once a pixel spans a third of one (`mow_band`), fade out in triangles
  whose corners belong to two holes (`mow_rate`), greens, collars,
  approaches and tees always take their own hole's stripe direction
  (`DesignedTerrain._stripe_uv`), and the stripe width is the nearest
  texel's, never a blend: each of these drew fields of moire or
  fingerprint rings beside greens.
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
  gusts roughen patches of the surface and leave others glassy. Ripples
  calm with the pixel footprint (`fwidth`), so far water is a smooth
  mirror instead of aliased bands, and reflections up to about ten
  degrees above the horizon show the dark trees of the far bank.
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
- **The golfer's own shade** (`golfer_occlusion.gdshaderinc`): the free
  golfer's limbs, trunk and head are 11 capsules (`GolferCloth.OCCLUDERS`,
  set each frame from the posed skeleton), and the clothes and skin darken
  where they face one close by: the inside of the arms, the shirt under
  them, between the legs, under the chin. It takes ambient light and 70%
  of the sun (`contact_share`), works in both renderers and is off on Low.
  Cloth is never whiter than `GolferSurface.WHITEST` (a white cap or shoe
  burnt out to a flat glowing patch), pale cloth gets less rim light, and
  the pack's trouser texture keeps 30% of its scuffs
  (`GolferCloth.TEXTURE_DETAIL`). In the browser, dynamic resolution stops
  at 80% (`DynamicResolution.WEB_MIN_SCALE`): with only a plain stretch,
  half resolution turned every edge to stair steps on an iPad.
- **Realistic people** (`tools/golfer/rocketbox.py`, MIT Microsoft
  Rocketbox avatars): six photographed people moved onto the free golfer's
  skeleton, so every clip, IK and the self-shade work on them. They are the
  pros, crowd, computer players and a new player's golfer
  (`PlayerLook.person`); the sculpted body stays as "Custom". The fit:
  arm bones turned by their elbow's hinge plane and stretched to the rig's
  length (longer arms bent at the elbow to reach the grip), shoulders
  brought forward to the rig's, hands laid over the rig's finger joints,
  feet only turned about the vertical (flat soles), spine pivots at the
  rig's heights. `golfer_person.gdshader` dyes shirt, trousers and shoes
  from a regions mask, keeping the folds (luminance around the garment's
  median, deepened). Browsers and phones load their maps at 1024.
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
- **Tournament gallery** (`Gallery`, Broadcast and Tour only): gallery
  ropes on 1.1 m stakes 4 m apart, the rope hung at 0.85 m with a 6 cm sag.
  They run 7 m either side of the tee from just behind the markers to 30 m
  down the hole, and round the back of the green 5 m off the putting
  surface. Behind them stands a crowd of the player creator's people (random
  `PlayerLook`, no clubs, standing upright in the rig's idle, each at their
  own point in it), facing the play. Each holds their arms as people in
  tour gallery photos do (`CrowdArms`, a SkeletonModifier3D over the idle):
  about a third folded, a quarter hanging, a fifth behind the back, the
  rest hands in pockets; it fades out while they clap or groan. The crowd is 0, 10, 18
  or 28 people from Low to Ultra, nearest the tee and green first. Spectators
  cast no sun shadows: a dozen meshes each, redrawn into every shadow
  split, would cost more than the rest of the hole. Each gets a soft contact
  shadow instead, all in one MultiMesh. The 28 people add about 260 draw
  calls from the tee.
  The spectators react to each shot as the crowd sounds do: everyone
  celebrates a roar, most a cheer, a few polite applause, and about half show
  dismay at a groan or an "ooh". The crowd watches the golfer: at each
  address every spectator turns towards them, a moment apart (keeping a
  little of their own angle), and their heads follow (GolferLook); once the
  ball is struck the heads follow the ball. Spectators wear no golf glove.
- **Crowd cards** (`Gallery`, `crowd_card.gdshader`): further back, 1.2 to
  5 m behind the ropes, the crowd thickens into camera-facing cards. Each
  card is one quad that turns about the vertical and draws a standing
  person in its fragment shader: head and hair, shirt, arms and hands,
  trousers and shoes, with a varied height (1.72 m, sd 9 cm), build, skin
  tone, shirt and trousers. Each also picks, in the shares seen in tour
  gallery photos, a cap or visor (half, with the brim's shade over the
  eyes), folded arms (a third), shorts with bare legs and white trainers (a
  quarter) and longer hair (about a third of those without a cap), with
  some grey hair; the legs darken a little towards the ground. The picks
  come from the instance id in the vertex shader, so every pixel of a card
  agrees. All the cards are one MultiMesh, so one draw call: 80, 160, 260
  or 360 cards from Low to Ultra (Low has cards and no 3D people), plus one
  more for the soft contact shadows they stand on, as the 3D people do,
  and one more for their sun shadows (below).
  They keep off greens, bunkers and water and 0.7 m apart.
  Once `CrowdImpostors` has baked its atlas, the cards show real people
  instead of the drawn figure: the first gallery of a session renders
  sixteen of the player creator's people (random looks, the crowd's idle,
  arms folded, hanging, behind the back or in pockets) from eight sides
  into a 1280 by 1280 atlas, in an off-screen viewport, as TreeFactory
  bakes its tree impostors (about 40 frames, once). Each card is turned
  to face the play and draws the view of its person from the side the
  camera is on, so the far crowd has faces, caps, clothes and folded arms
  and turns properly as the camera moves. Headless runs, and the moments
  before the bake finishes, keep the drawn figures.
- **Crowd sun shadows** (`shaders/person_shadow.gdshader`): the 3D people
  and the cards cast no real shadows (hundreds of people in the shadow
  maps would cost too much, and Compatibility's shadows stop near the
  camera), so each spectator gets a soft person-shaped patch on the ground
  that falls away from the sun: legs, body, neck and head, as long as the
  sun's height makes it (at most 2.6 times their height), sharp at the
  feet and softer towards the head, lying on the slope under them. The
  sun's direction comes from the `sun_travel` global uniform, which
  Scenery sets with the time of day. One MultiMesh for the 3D people and
  one for the cards, in both renderers.
- **Grandstand** (`Gallery`, par 3s and the last hole): a temporary
  bleacher stand behind the green, 24 m wide, with 8 rows 0.85 m deep rising
  0.42 m. The first row is 1.0 m up behind a dark green hoarding. It is set
  6 m behind the green rope and turned up to 50 degrees to clear water,
  sand, greens and trees, or left out if none of those fit. Par 3s also get
  a 16 m stand beside the tee, past the crowd along the tee rope, looking
  across at the golfer (TV par 3s are framed that way). The aluminium
  seat planks are light and the open backs under them in shade, so the
  rows read; white tube rails (a top and a middle rail on posts 2 m
  apart) run along the front, up both stepped sides and along the back.
  About 80% of the seats are filled with the crowd cards' baked people
  (`CrowdImpostors`), drawn from the head to the hips (the row in front
  hides the rest; the cards' `cut` uniform), all facing the green: one
  instanced draw call per stand.
- **Broadcast tee view** (`RoundCamera.aim`): in the Broadcast
  presentation the view behind the ball stands lower and closer
  (`BROADCAST_AIM_UP`, `BROADCAST_AIM_BACK`), at the golfer's hip as TV
  and PGA Tour 2K25 frame a tee shot: he stands tall in the frame from his
  shoes to his cap, with the horizon near the middle. Classic Links keeps
  the original's higher view; putts are unchanged.

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

Godot stores an imported HDR as uncompressed RGB9E5, so the sky was still
8 MB. It is no longer imported: `tools/fetch_free_assets.py` packs it with
`tools/sky_pack.py` into `free_assets/sky_panorama.olsky`, the same RGB9E5
pixels deflated (3.8 MB; only 7 pixels in the sun's core, far brighter than
white, differ by under 1% from Godot's rounding), and `FreeAssets.sky()`
inflates it into an `ImageTexture` once, in about 50 ms. That took the pack
from 36 MB to 31.7 MB on 2026-10-31.

`.import` files are not committed, so import settings live in
`tools/fetch_free_assets.py` (the free textures) and `project.godot` (the
defaults).

## Still to do

- Occlusion from the terrain itself (hollows, cliffs).
- Texture compression tiers per device (Basis/ASTC), and the HD pack in
  the browser.
