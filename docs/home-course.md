# The built-in course: Kettle Hollow

The course the game plays when no original course files are loaded (the
main menu's "built in" course, career events without course files, the
CI renders). It used to be nine separate patches of made-up rolling ground
with circular greens, box tees and straight fairway strips. It is now one
routed parkland nine on real ground, drawn the way courses are really
built.

- Built by `tools/homecourse/build_home_course.py` into
  `game/assets/courses/home.olc`, a course designer file (gzipped, about
  300 KB; `DesignedCourse.load_file` reads gzipped or plain JSON)
  ([course-designer.md](course-designer.md)). `PlaceholderCourseLoader`
  loads it, so it plays through `DesignedTerrain` like any designer or
  real-world course, and it can be opened and edited in the designer.
- Rebuild after changing the routing or the rules below:
  `python3 tools/homecourse/build_home_course.py --preview /tmp/home.png`
  (fetches about 9 elevation tiles into `--cache`, default `/tmp/dem`; the
  preview is a top-down map for checking the layout).

## The ground

Real ground, not noise: a 1.5 x 1.1 km patch of glacial kettle-moraine
farmland in south-east Wisconsin (43.42 N, 88.30 W; no golf course there),
from the open Terrarium elevation tiles (Mapzen / AWS Open Data), which
there come from USGS 3DEP lidar (public domain). Kettle moraine is the
hummocky ground left by ice sheets: knolls, kettle hollows and long
slopes, 33 m of relief over the site. It is classic golf ground; the
course takes only the landform, nothing of any course.

The lidar keeps field drains, tracks and crop rows, so the builder blurs it
by about 6 m (the landform stays) and adds the small ground movement the
tiles are too coarse for (0.3 m at 30 m, 0.1 m at 13 m, 5 cm at 6 m), as
real fairways are never flat. Inside the playing corridors the ground is
eased half way toward a 20 m blur, as a course's shaping softens what the
farm left.

## Routing and yardages

Par 36, 3,416 yards from the back tees: two par 3s, five par 4s and two par
5s, the usual mix for a nine. The holes run as a loop from a clubhouse
spot on the high ground: hole 1 plays 11 m downhill into the valley, 2 to 4
work round the low ground (3 is a downhill par 3 over a pond), 5 climbs
back up, 6 to 8 cross the plateau and 9 returns, past a pond, to finish
beside the first tee.

| Hole | Par | Yards | Shape |
|---|---|---|---|
| 1 | 4 | 403 | Downhill, slight left |
| 2 | 4 | 425 | Dogleg left along the valley |
| 3 | 3 | 178 | Downhill over a pond |
| 4 | 5 | 513 | Up the valley, two bends |
| 5 | 4 | 328 | Short, uphill |
| 6 | 4 | 434 | Dogleg right across the plateau |
| 7 | 3 | 207 | Long par 3 |
| 8 | 4 | 410 | Straight, firm |
| 9 | 5 | 517 | Dogleg left past a pond, home |

Each hole has three tee boxes (back, middle and forward, 26 to 66 m apart
on the 4s and 5s), staggered a little off the line, as real ones are. The
stroke index follows difficulty (6 and 2, the long dogleg 4s, are 1 and 3).

## Shapes and figures

Nothing is a circle or a box. Every outline is a closed spline through
control points (the designer's `CourseShape`), with its radius or edges
wandering by a few low harmonics, so no two greens, tees or bunkers share a
template.

| Feature | What it is | Figures used |
|---|---|---|
| Tees | Rounded rectangles (superellipses), 8 to 10 m wide, 10 to 20 m long, raised 0.4 m with 1-in-4 banks | Typical tee pads |
| Fairways | Ribbons along the line with edges that wander independently and rounded ends; from about 120 m off the back tee to the green front | 34 to 36 m (37 to 39 yd) in the landing zone, narrowing to 23 to 25 m at the approach |
| Rough | A band of semi-rough about 15 m either side of the fairway, deep rough beyond | First cut and intermediate rough as mown on parkland courses |
| Greens | Organic pear shapes, long along the approach | 484 to 624 square metres (5,200 to 6,700 sq ft; the US average is about 6,000) |
| Collar | 1.8 m ring (the designer's fringe) | |
| Bunkers | Lobed outlines, 0.7 m deep, the face built up 1.1 m on the side it faces (the green for greenside bunkers, the tee for fairway ones), so the sand is seen | Fairway bunkers 14 to 30 m long at 205 to 395 m off the tee (where drives finish); greenside 10 to 17 m |
| Ponds | Organic outlines in a graded basin, so the banks are gentle on every side | |
| Cart paths | 2.4 m asphalt, curving from behind each green to the next tee | |

## Green contours

Each green is a push-up green: 0.45 m proud of the ground round it, tilted
back to front (1.6 to 2.6 %) with a cross tilt (0.4 to 1.0 %), so it drains
to the front as real greens do. Four of the nine have a tier: a 0.4 to
0.45 m step over 6 m across the green. Three soft knobs and hollows of up
to 9 cm on each make putts break. The surrounds fall off quicker at the
front (a false front over 7 m) than at the sides and back (11 m), where
grassy mounds of 0.5 to 1 m sit about 11 m out.

Pins are cut where the green holds a putt: at most 3 % within 2.5 m, at
least 4.5 m from the edge, off the tier faces, and front, middle or back
in turn round the nine.

Measured on the built course: mean slope 1.9 to 2.6 % on the greens
without a tier (largest 3.3 %), and the tier faces at 11 to 14 %. Tour
greens are about 1.5 to 3 %, and a pin needs no more than about 3 % at
green speeds of 10 to 11 on the stimpmeter.

## Trees

About 3,600 trees and 500 bushes: tree lines 40 to 90 m off each hole's line,
groves where a slow noise puts them, and woods thickening round the
boundary. Pines stand in their own stands; the rest are broadleaf, as
in Wisconsin's oak and maple woods. A further 4,200 trees stand close in the
deep woods away from play.

Trees within `DesignedCourse.HOLE_REACH` (60 m) of a hole's line are placed
one by one for that hole (they cast baked shade and the gallery avoids
them); every other tree on the course is drawn batched
(`DesignedTerrain._add_distant_trees`, impostors at a distance), so the
woods across the whole course are seen from every hole for a few draw
calls. The batched trees cast no sun shadows: drawing them a second time
for the shadow map pushed the tee view over the 2 million triangle budget
(render_check), and at 60 m or more from play their shadows seldom fall
where the player looks. Every tree keeps its obstacle for the ball.

Pond banks run down to the water line over `DesignedTerrain.WATER_BANK`
(5 m) outside the outline and carry on under it with no step. A dig that
started at the outline left a cliff that the 2 m height grid drew as a
sawtooth shore.

## Mowing

Stripes run along each hole (the tee-to-pin line), at the mower's real
cut: about 3 m on fairways (fairway units), 1.5 m on tees (triplex) and
0.55 m on greens (walk-behind greens mowers), and softer on greens and tees
than on fairways (`DesignedTerrain.MOWN`, `STRIPE_METRES`). This applies to
every designed and real-world course.

## Credits

Ground: Terrarium elevation tiles (Mapzen, AWS Open Data), from USGS 3DEP
lidar, which is public domain. The course file carries the credit line.
