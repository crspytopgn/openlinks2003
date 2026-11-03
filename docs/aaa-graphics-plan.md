# AAA graphics plan

The bar is PGA Tour 2K25 on Photoreal (desktop, Forward+) and as close as
WebGL allows on iPad Pro-class devices. Low-end devices keep a lean,
playable Performance look. This is the gap list from comparing our renders
with 2K25 press screenshots, 2026-11-01. The list is ranked by how much each
item moves the picture, with an owner for each. Tick items off here as they
land.

How to check: `/tmp/rc/q.sh` style quick renders (tee and flyover, about
1 min in Compatibility and 2 min in Forward+). Forward+ renders in the cloud
with Mesa lavapipe (`apt-get install mesa-vulkan-drivers`,
`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json`,
`--rendering-driver vulkan`). Run `tools/fetch_free_assets.py` and
`godot --import` first, or the ground renders black.

Rarely used tricks (view-dependent mowing stripes, heat shimmer and more,
with verdicts) are in `unusual-graphics-ideas.md`.

## Round 2 gaps, 2026-11-03

Almost every item in round 1 (below) has landed. This list comes from a
fresh audit of Photoreal at Ultra on Kettle Hollow hole 2, rendered at
1920x1080 in Forward+ (lavapipe) and Compatibility. Each view was checked
at full size: the tee, a 140 m approach, a 6 m putt, and the golfer from
3 m away. The references were 2K25 4K press shots and Geograph photos of
parkland courses. The list is ranked by how much each item moves the
picture.

1. **Trees, mid distance (graphics thread).** From the fairway, the crowns
   from about 60 m to the far tree line are almost black, flat masses in
   Forward+. In 2K25 and in real photos, the sunlit side of a crown is the
   brightest green in the frame. The near crowns also show black,
   square-stepped holes. This is the single biggest "cheap" signal left.
   Shadows and SSAO turned out not to be the cause (switching them off
   changed nothing): the crowns lit only by the sky went blue-grey.
   First step done: in Forward+ the leaves and impostors pass on
   yellow-green sky light (`transmit`, TreeFactory.TRANSMIT_FORWARD_PLUS),
   and the black holes are gone (the crown cores drew the black gaps of
   the leaf spray; they now show deeper, shaded leaves). Second step
   done: every tree has its own leaf colour from a hash of where it
   stands (`tree_tint.gdshaderinc`, yellower to darker and bluer, shared
   by the full tree and its impostor), and Forward+ leaves are a bluer
   green, so sunlit sides read green rather than lime. Still open: 2K25's
   sunlit highlights carry more blue (sky sheen on the leaves).
2. **Trees, close up (graphics thread).** Under the crowns you see long,
   straight, level limbs of constant thickness, like poles, and the same
   three broadleaf shapes repeated in rows. Real parkland trees have limbs
   that fork and taper and disappear into leaves, and every tree looks
   different. Plan: limbs that fork and bend and carry leaves along their
   length, not only at the tips, and more broadleaf variants. Done: limbs
   kink and fork at a knee, taper to the tip, carry sprays at each fork,
   and sit in the crown's shade (the bark darkens with height); five
   broadleaf variants instead of three.
3. **Rough and fescue (graphics thread).** The rough's 3D tufts are evenly
   scattered, bright-tipped cards that read like stickers on a flat ground
   texture. The deep rough banks read as a field of yellow dots. 2K25's
   rough is a dense, even fur that gets longer away from the fairway, and
   its fescue is wispy, with seed heads that catch the light. Plan: denser,
   shorter, darker-tipped tufts that blend into the ground colour, a first
   cut between fairway and rough, and fescue clumps built from thin blades
   and seed heads rather than yellow blobs.
4. **Shade fill (graphics thread).** In Compatibility, tree shadows on the
   fairway are near black, with no sky light in them. In real photos the
   shade under a tree is a darker, bluer green, never black. Plan: lift the
   shadow floor with sky-coloured ambient on terrain and grass in
   Compatibility.
5. **Tee boxes and ground shape (home-course builder).** 2K25's tees are
   raised, flat, closely mown platforms with a clean edge, and the ground
   round them rolls. Ours blend into the fairway, and the ground between
   holes is smooth. Plan: raised tee pads and gentle mounding in
   tools/homecourse, checked against the physics terrain.
6. **The golfer in Compatibility (golfer threads).** In Forward+ the golfer
   holds up well. In Compatibility his skin goes pale and flat and his
   light trousers glow at the edges (bloom). Done: the cause was
   Compatibility's exposure and fill lifts, which are tuned for the turf.
   People now take them back and get their fill more from above than
   below (Scenery.people_light, shaders/golfer_occlusion.gdshaderinc), and
   dyed cloth stops at real white with less rim light on light colours.
7. **Crowd variety (realism lead).** At a distance the gallery is fine,
   but many heads read as the same white cap. Plan: more cap and hair
   colours, and bare heads. Done: spectators (PlayerLook.spectator) wear a
   cap only 45% of the time, in gallery colours led by navy and black
   (white about one in eleven), half of them dad caps. The rest show their
   own hair. Hair colour on the realistic people is still their own.

How this was checked: an uncommitted harness renders each view with the
look forced to Photoreal and quality to Ultra (Compatibility takes about
2 min, Forward+ through lavapipe about 20 min). The side-by-side sheet is
kept privately with the project files, not in the repo, because it holds
2K25 frames.

## Round 1: what 2K25 does that we don't

1. **Camera and lens (graphics thread).** 2K25 shoots the tee from low and
   behind with a long lens (narrow field of view). That compresses the hole,
   makes the trees a wall and puts the golfer large in frame, with a soft
   background. Our wide, high camera shows off the low-detail far scenery.
   Plan: a telephoto tee and approach camera (about 35 to 45 degree FOV),
   a lower eye height, and a light depth of field on the background in
   Photoreal.
2. **Light and grade (graphics thread).** 2K25 uses a lower, warmer sun,
   long shadows, deep shade under trees and natural olive-yellow greens.
   Ours were lime and flat. Plan: a lower afternoon sun, natural saturation,
   warm white balance and real distance haze (in progress), plus contact
   shadows and SSAO tuned for grass.
3. **Golfer (player creator and golfer animation threads).** He is always
   on screen. Ours has flat cloth, odd hands, plain skin and no cap or
   glove. Plan: cloth normal and detail maps (polo knit, trouser twill),
   skin with subsurface tint and pores, a cap or visor, a glove on the lead
   hand, real golf shoes, and hands that actually close on the grip (IK to
   the club). Fix the hands first, since Michael noticed them.
   Done 2026-11-01: clothes move (GolferCloth and golfer_cloth.gdshader:
   wind ripple, swing lag springs, twist/elbow/knee folds, by quality tier).
4. **Trees (trees, grass and water thread).** 2K25's trees are dense,
   photoscanned and layered; ours read as clumps. Plan: higher-quality CC0
   tree models with more leaf-card layers, light passing through the leaves,
   canopy self-shadowing and a dark understorey, and far trees as
   impostors, so the wall of trees reads as forest.
5. **Course edges and bunkers (graphics thread).** 2K25 bunkers have raised,
   ragged grass lips, a visible depth, rake lines and wet, darker sand at the
   edges. Its fairway and green edges are clean, with a first cut and a
   collar. Plan: lip geometry and shading on bunker edges, a fringe or
   collar ring round greens, and crisp but soft surface edges on every
   course type.
6. **Near grass (trees, grass and water thread).** 2K25 shows individual
   blades at the feet and fluffy rough. In Forward+ our 3D tufts blend into
   the ground and vanish. Plan: give the tufts their own shading and tips in
   Forward+, and add short blades on the fringe and first cut near the
   camera.
7. **Far scenery (skies thread, graphics thread).** In 2K25 the horizon
   melts into haze, with distant hills and treelines. Ours are flat, low
   panoramas with hard edges. Plan: layered haze (aerial perspective on
   terrain and trees), far terrain and treeline cards, and skies matched to
   the sun. Done for courses without a horizon panorama (Kettle Hollow,
   designed and real courses): `FarScenery` draws four rings of wooded
   hills and farmland round the course, each hazier than the one in front,
   with their feet lost in ground haze (calibrated on Geograph photos of
   Knole Park and Sundridge Park). Low quality draws two rings, Medium
   three, High and Ultra four with crown detail on the near ones.
8. **Crowd and props (realism lead, product lead).** 2K25 has 3D crowds,
   grandstands, ropes, signage and tee markers. Plan: varied 3D crowd
   meshes (CC0) close to the camera and cards further out, plus ropes,
   stands and proper tee markers.
9. **Animations (golfer animation thread).** These are the swing transition
   and follow-through, the club and hand contact, idles, reactions and the
   walk to the ball. They are already in progress with mocap; next are hand
   IK and reaction clips.
10. **UI (broadcast presentation).** 2K25's HUD is minimal and glassy, with
    a glowing 3D tracer. Ours has a long controls line along the bottom and
    flat panels. Plan: hide the controls hint after the first hole, use
    lighter frosted panels and tighter type, and add a glowing tracer that
    fades.

## Order for the graphics thread

1. Grade, lower sun and haze. Done in #141; the bloom veil that greyed
   Forward+ was removed after it.
2. Telephoto tee and approach camera with background depth of field.
3. Bunker lips, a green collar and soft surface edges.
4. Contact shadows, SSAO and GI tuning on desktop, and the iPad tier
   checked after each step.

Items 3, 4, 6, 8, 9 and 10 are owned by the threads named above and are
passed to them through the coordinator.
