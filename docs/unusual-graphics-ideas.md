# Unusual tricks for a photoreal look

Michael asked (2026-11-01) for ways of making the game look real that most
games don't use. This list is about rarely used tricks. The mainstream gap
list (camera, grade, golfer, trees, edges, grass, haze, crowd, UI) is in
`aaa-graphics-plan.md` and is not repeated here. Every idea has to scale:
it should cost nothing on the web and iPad tiers, or be desktop-only.

Verdicts: **Built** (in the game), **Do next**, **Later**, **No** (with why).

## Built

1. **Mowing stripes that depend on where you look from.** Real stripes are
   not two shades of grass. The mower lays the blades one way down one strip
   and the other way down the next. Blades laid away from you look pale and
   blades laid towards you look dark, so the stripes are strongest looking
   down the line, swap light for dark when you turn round, and nearly vanish
   looking across. Games paint them on as fixed colours. Ours now follow the
   view (`shaders/mow_sheen.gdshaderinc`, used by `terrain.gdshader` and
   `course_ground.gdshader`). It costs one dot product per pixel on every
   tier. Verdict: a clear win. It is subtle in a still image and obvious when
   the camera moves from the tee to the green.
2. **Heat shimmer on long-lens shots.** On a warm day, TV footage down a
   fairway shows the far green and tree line rippling, while the ground near
   the camera stays still. The post pass now displaces the far part of the
   picture by a pixel or two. Distance comes from the row's angle below the
   horizon and the camera's height, so the effect needs no depth buffer and
   works on the web. It grows with a longer lens and a higher sun and is off
   at dawn. It runs on the Photoreal look only and costs two noise lookups.
   Verdict: worth keeping. It only shows in motion, and it should stay
   faint, because strong shimmer looks like a bug.

## Do next

3. **A colour grade learned from real broadcast frames.** Collect about
   twenty CC-licensed photos of sunny courses, and twenty matching renders
   from the same angles. Fit a colour transfer for each region (sky, turf,
   trees, sand) by matching mean and covariance in Lab colour space, and
   bake it into a 32-cubed LUT. The post pass then does one 3D texture
   lookup, which is cheap everywhere. This makes the colours "photographic"
   by measurement rather than by eye. The grade belongs to the "Make course
   textures look photoreal" thread, so it should be built with them.
4. **Sky-matched lighting from real HDRIs.** Use a CC0 HDRI (Poly Haven)
   for the sky, read its sun direction and colour from the brightest
   pixels, and drive the directional light and ambient from it. The light,
   shadows and sky then always agree, which is the most common giveaway in
   cheap games. This belongs to the skies work.
5. **A camera operator.** Broadcast cameras on long lenses never sit dead
   still. They show a tiny drift, small corrections and a slight lag as they
   follow the ball, then settle. Add a small filtered noise to the camera
   (well under 0.1 degree at 40 degrees FOV) and a critically damped
   follow. It is free to run, and it does more for "this is filmed" than any
   shader. This needs agreement with the broadcast presentation owners.

## Later

6. **Offline-baked light for the whole hole.** Path trace sky light and
   bounce light over each hole's terrain offline (Blender Cycles from the
   course mesh) into a low-resolution lightmap, and use it like the
   existing GroundShade bake. Hollows and tree edges would then darken the
   way they do in photos. This is a big pipeline job. GroundShade AO
   already gets part of the way there.
7. **Texture synthesis from real photos.** Generate non-repeating fairway,
   rough and sand textures from one CC0 photo each, using example-based
   synthesis (texture-by-numbers or histogram-preserving blending) at
   import time. This removes visible tiling without extra cost at runtime.
   It overlaps with the textures thread.
8. **Photogrammetry or Gaussian-splat backdrops.** Splats of real
   tree lines and hills give unbeatable realism for distant scenery. Godot
   has no splat renderer, so it would need a custom compute or sorting
   pass, which won't run on WebGL 2 at 60 fps. A splat baked into layered
   impostor cards (render the splat from the tee and green, then use the
   images) is feasible offline. Worth a test on one hole once the courses
   have real tree lines.

## No

9. **A real-time ML "photo" enhancer** (such as Intel's 2021 GTA V
   enhancement). This is the most talked-about idea, and it really does
   look photographic. But it needs a big GPU to run at 60 fps, it doesn't
   exist for WebGL or iPad, and it flickers and invents detail. Use ML
   offline instead (Upscayl for the HD pack, and possibly ML texture
   synthesis), never per frame.
10. **Chromatic aberration, lens dirt and heavy film grain.** These read as
    a "game filter", because real broadcast lenses are very clean. Leave
    them out.
11. **TV detail enhancement (edge haloes).** Broadcast cameras sharpen with
    visible haloes, and adding them makes a frame look more like TV. But
    2K25 doesn't do this, and it makes a still look cheap. The existing
    CAS sharpening is enough.
