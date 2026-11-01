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

## What 2K25 does that we don't

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
   the sun.
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
