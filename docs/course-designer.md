# Course designer

A Links-style course designer built into the game, so players can make their
own courses and play them in the same round, physics and scoring as the
game's courses. It runs the same in the browser and on desktop, and needs
nothing from the original game (with the player's game files loaded, trees
are drawn with the game's own tree objects).

Open it from the main menu with **Course designer**. It opens the last course
saved or played, or a new starter course with rolling ground and one par 4.

This is our own designer, not a copy of the original Arnold Palmer Course
Designer: it doesn't read or write the original `.CRS`/`.CRZ` formats, and
its file format is our own.

## Using it

The camera orbits a point on the ground:

| Input | Action |
| --- | --- |
| Right drag | Turn and tilt |
| Middle drag, or Shift + right drag | Pan (the ground follows the mouse) |
| Wheel | Zoom |
| W A S D, arrow keys | Move; Shift is faster |
| Q / E | Turn |
| T | Top-down view and back |
| F | Frame the current hole |
| Ctrl+Z, Ctrl+Y (or Ctrl+Shift+Z) | Undo, redo (30 steps) |
| Ctrl+S | Save |
| Delete | Remove the selected area |
| Esc | Cancel an outline, or clear the selection |

The tools on the left:

- **Select:** click an area to select it (the smallest area under the mouse,
  so a green rather than the fairway round it). Drag it, or drag its control
  points; double-click its edge to add a point, right-click a point to remove
  it. Changing the surface menu changes the selected area's surface. The
  current hole's tees, pin and aim points can be dragged too.
- **Draw area:** click to place an outline's control points, then click the
  first point, press Enter or right-click to close it. The outline is drawn
  as a smooth closed curve through the points. The surface menu picks what it
  is: fairway, green, tee, sand, water, fringe, rough, deep rough or out of
  bounds.
- **Raise, Lower, Smooth, Flatten:** hold the left button to sculpt the
  ground under the brush. Flatten levels to the height where the stroke
  started. Brush size and strength are in the panel.
- **Trees:** hold the left button to plant trees in the rough (never on
  fairways, greens, tees, sand or water); hold Shift to clear them.
- **Objects:** click to place the object picked in the list, Shift+click to
  remove the nearest. "Basic trees" are the two built-in trees. With the
  player's game files loaded, every group in the game's own `OBJECT.LIB` is
  listed too (trees, bushes, buildings, grandstands, crowds and the rest),
  drawn from the player's files. Turn and size are set in the panel, or
  randomised a little for natural planting. A course stores each object by
  its catalog file name and its measured size, so on a machine without the
  game files the course still plays the same: the game's trees are drawn as
  built-in trees of about the same height, and other objects aren't drawn
  but still stop the ball.
- **Path:** click to lay a cart path's points, then press Enter,
  right-click or double-click to finish. Width is in the panel; tick
  **Bridge** to make a bridge instead. Shift+click removes the nearest path.
- **Tee, Pin, Aim point:** place the current hole's back, middle and forward
  tees, its pin, and aim points for doglegs (the round's auto-aim uses them,
  and the hole is measured along them).

**Add** in the hole section starts a new hole at the middle of the view,
playing away from the camera, with a tee box, a fairway (for holes over
200 m) and a green to reshape. **Fly over the hole** previews it with the
round's own flyover camera, from behind the back tee down to the green; a
click or key stops it. The panel shows the hole's length and the par
that length usually plays to.

**Play this course** saves it and starts a one-player round on it. Designed
courses are also listed on the round setup page (marked "your design"), so
they can be played with every game mode and up to four players.

**Real course...** builds a real golf course from its name, from
OpenStreetMap and open elevation data; see [real-courses.md](real-courses.md).

**Save** writes `user://courses/<course name>.olc` (in the browser, the
browser's own storage for the site). **Open** lists the saved courses.
**Export** downloads the course file (browser) or saves it anywhere
(desktop); **Import** reads one back, so courses can be shared.

## How the ground works

`DesignedTerrain` (`game/scripts/designer/designed_terrain.gd`) is the
`CourseTerrain` the round plays on:

- **Heights** come from the sculpted grid (one sample every 2 m, bilinear
  between them), then the areas shape them: tee boxes become level pads
  0.25 m above their mean height, blended over 3 m; bunkers are dug 0.7 m in
  with a 2 m lip; ponds are sunk below a water line 0.3 m under the lowest
  point of their bank.
- **Surfaces** come from a raster of the areas at 0.5 m, painted in layer
  order whatever order they were drawn in: deep rough, out of bounds, rough,
  fairway, fringe, tee, green, sand, water (later layers cover earlier ones).
  Every green gets a 1.8 m fringe ring. Ground with no area is rough, and
  everything outside the course is out of bounds.
- **Trees and objects** are obstacles for the ball (`DesignerObjects`): the
  built-in trees get a trunk and a canopy sized to their meshes. Catalog
  objects are measured from the node the player's object library builds for
  them (the bounds of all its meshes, at scale 1). Models become a solid box
  of that size, turned with the object. Billboards follow the catalog's
  `collision` value: trees (0) get a trunk and a canopy 0.8 of their width
  across, solid ones (1) a column, and pass-through ones (2) nothing.
- **Cart paths** (`CoursePath`) are painted as fairway right after the
  fairway layer, so greens, bunkers and water still cover them, and drawn as
  a grey ribbon on the ground; the rules give a free drop from them. **Bridges** aren't painted: their deck runs
  in a straight slope from 0.4 m above one end to 0.4 m above the other,
  never less than 0.6 m above the ground or water under it, and is a chain
  of solid 0.3 m boxes the ball bounces off, with rails drawn either side.
- **Meshes** are built in 64 m chunks and cached; the designer rebuilds only
  the chunks an edit touched. A sloping apron runs out from the course edge
  so the course doesn't end in a cliff.

The surfaces use the game's usual surface physics (`Surface`), so a designed
course plays with the same bounce, roll, lies and penalties as any other.

## The `.olc` file

A UTF-8 JSON object:

| Key | Value |
| --- | --- |
| `format` | `"openlinks-course"` |
| `version` | `1` |
| `name`, `author` | Strings |
| `area` | `[x, z, width, depth]` of the course in metres (+x left, +z downrange) |
| `cell` | Metres between height samples: `2.0` |
| `heights` | `{"encoding": "cm-delta-s16-deflate-base64", "count": n, "data": "..."}`: the grid row by row (z then x), `cols = width / cell + 1` by `rows = depth / cell + 1`. Each height is in centimetres, stored as the difference from the previous one as a little-endian int16; the bytes are deflated and base64-encoded. Heights are kept within +-150 m. |
| `shapes` | `[{"surface": "Fairway", "points": [x0, z0, x1, z1, ...]}, ...]`: surface names as in `Surface.NAMES` |
| `holes` | `[{"par": 4, "tees": [x, z, ...], "pin": [x, z], "route": [x, z, ...]}, ...]`: tees back to forward, route is the aim points; an optional `stroke_index` (1 to 18) |
| `objects` | `[{"id": "tree_pine", "x": 0, "z": 0, "yaw": 90, "scale": 1}, ...]` |
| `paths` | `[{"points": [x0, z0, x1, z1, ...], "width": 2.5, "bridge": false}, ...]` (width 1 to 8 m) |
| `credits`, `source` | Optional: data credits to keep, and where a real course came from ([real-courses.md](real-courses.md)) |
| `object_info` | `{"<catalog file name>": {"kind": "model", "size": [x, y, z], "centre": [x, y, z]}, ...}`: the measured size of every catalog object the course uses, in metres at scale 1, with `kind` one of `model`, `tree`, `solid`, `soft`. Only sizes, never the objects themselves, so a shared file carries no game data. |

A medium course (1000 x 800 m) with a few holes is a few hundred kilobytes.
Readers refuse files with another `format`, a newer `version`, or a height
grid of the wrong size, and skip shapes and holes they can't read.

## Code map

```
game/scripts/designer/
  course_designer.gd     CourseDesigner: the scene (tools, picking, overlays, undo, files)
  designer_panel.gd      DesignerPanel: the side panel
  designer_camera.gd     DesignerCamera: the orbit camera
  designer_objects.gd    DesignerObjects: what can be placed, and their obstacles
  designer_files.gd      DesignerFiles: export and import (browser download and picker, desktop dialog)
  designed_course.gd     DesignedCourse: the course data, sculpting, the .olc format
  designed_hole.gd       DesignedHole: par, tees, pin and aim points
  course_path.gd         CoursePath: a cart path or bridge
  course_shape.gd        CourseShape: a painted area and its smoothed outline
  designed_terrain.gd    DesignedTerrain: heights, surfaces, obstacles and meshes
game/scripts/course/designed_course_loader.gd   DesignedCourseLoader (registered by default)
game/scenes/course_designer.tscn
game/tests/designer_tests.gd                    data checks; run_tests.gd also opens the
                                                scene and plays a round on a designed course
```

## Still to do

- Crisper surface edges: the colours blend between 2 m vertices. A splat map
  sampled in the terrain shader would give sharp, Links-like cut lines.
- The catalog's own `shape` field (not yet understood) could give tighter
  shapes than the measured boxes.
- Built-in (free) bushes, rocks and buildings for players without the game
  files.
- Hazard stakes, and lateral hazards for the rules.
- Per-course sky and horizon choices.
