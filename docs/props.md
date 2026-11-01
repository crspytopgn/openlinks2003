# Course props: modelled from real references

The golf buggy only started to look right once it was modelled from photos
of a real cart, measured to its maker's dimensions. The course props follow
the same method: for each one, find photos of the real thing and its real
sizes, then model it to match at 100% scale. Michael's standing rule is to
cross-reference real golf constantly, so check new props against photos
the same way before they go in.

All of them are built in code by `tools/props/build_props.py` (CC0, no
makers' names or logos) into `game/assets/props/`:

```bash
pip install numpy scikit-image fast-simplification
python3 tools/props/build_props.py            # all of them
python3 tools/props/build_props.py OUT golf_bag tee_sign   # some, elsewhere
```

Rounded and moulded parts are signed distance shapes (`tools/buggy/sdf.py`)
meshed with marching cubes and simplified, with ambient occlusion baked into
the vertex colours. Each prop is a single mesh with one surface per material,
so it costs one draw call per material. Godot adds the distance LODs on
import. `CourseProps` (game/scripts/graphics/course_props.gd) places them.
`_test_props_real_size` in `game/tests/run_tests.gd` checks each model's size
against the table below.

## The props and their references

Reference photos are for comparison only. They are never committed. The
side-by-side shots for each pass are kept in the project files
(`props/`).

| Prop | Real size (model) | Reference | Where it's used |
| --- | --- | --- | --- |
| Tour staff bag (`golf_bag.glb`) | Bag 0.92 m tall, about 0.32 x 0.27 m oval; driver's headcover top about 1.3 to 1.36 m | Staff bags are 35 to 37 in tall with a 9.5 to 11 in top ([Vessel](https://vesselgolf.com/blogs/golf/what-are-the-different-golf-bag-dimensions), [Caddie HQ](https://www.caddiehq.com/resources/what-is-the-standard-size-of-a-golf-bag)). A 45.5 in driver stands about 0.38 m above a 36 in bag's cuff. Photo: a tour staff bag on a fairway ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Wilson_Staff_Pro_(staff)_golf_bag.JPG)) | The caddie's bag and the bags on the buggy (`GolfBag`) |
| Spherical tee marker (`tee_marker.glb`) | 127 mm ball with a moulded band, sunk about 12 mm into the turf | A maker's spherical plastic tee marker ([Par Aide](https://www.paraide.com/products/tee-area/markers/spherical-plastic-tee-marker/)) | Both tee markers, 5.5 m apart (`GolfRound._add_tee_markers`) |
| Ball washer ensemble (`ball_washer.glb`) | 1.28 m to the top of the knob; washer about 0.17 m across; bin 0.34 m across with its lid at 0.62 m; ring base 0.5 m | A maker's tee ensemble ([Par Aide](https://www.paraide.com/products/tee-area/ball-washer/master-ensemble-with-trash-mate-single-unit/)). Scaled from the washer, which takes a 42.7 mm ball | Beside each tee |
| Tee sign (`tee_sign.glb`) | 75 mm square post 1.74 m tall; arched panel 0.46 x 0.72 m, its foot 0.7 m up, gold rim | A maker's cast hole sign ([Par Aide](https://www.paraide.com/products/fusioncast/fusioncast-tee-sign/)), scaled from its post | By the front of each tee, with the hole number, par and yards in raised gold lettering (Label3D) |
| Bench (`tee_bench.glb`) | 1.54 m (5 ft) long, seat 0.45 m up, back 0.97 m, arms 0.66 m | A maker's recycled-plastic back bench ([Par Aide](https://www.paraide.com/products/tee-area/benches/back-bench/)) | Behind the washer at each tee |
| Bunker rake (`bunker_rake.glb`) | 64 cm (25 in) head with tapered ends, 1.37 m (54 in) handle with a grip | The maker's 25 in head and 54 in handle ([Par Aide](https://paraide.com/products/bunkers/bunker-rakes/accuform-ace-ii-with-25-inch-head)) | One per bunker near the hole's line, at its edge on the side facing the play, handle out over the grass |
| Fairway yardage plate (`yardage_plate.glb`) | 0.3 x 0.2 m white plate with a gold rim, flush in the turf, gold number | A maker's in-ground yardage plate ([Par Aide](https://www.paraide.com/products/fusioncast/fusioncast-fairway-yardage/)) | On the line of the hole, 100, 150 and 200 yards from the pin, where that is fairway, read from the tee side |
| Yardage pole (`yardage_pole.glb`) | 38 mm (1.5 in) pole about 2 m tall, black and white bands, flush socket | A maker's vinyl-covered fairway pole ([Par Aide](https://www.paraide.com/products/course-markings/marker-stakes/fairway-and-hazard-poles/)) | At 150 yards, a metre into the rough at the right edge of the fairway (or the left) |
| Sponsor plaque (`sponsor_sign.glb`) | 0.61 x 0.3 m black plaque with a gold rim, its top about 1 m up on a short post | A maker's cast sponsor signs ([Par Aide](https://www.paraide.com/products/fusioncast/fusioncast-sponsor-sign/)) | Beside each tee sign, with a made-up local business (never a real one) |
| Water station (`water_station.glb`) | 0.58 m square, 1.38 m to the ridge, framed doors with a tap hole and a rubbish slot | A maker's recycled-plastic water cooler tower ([Par Aide](https://www.paraide.com/products/tee-area/water-coolers/water-cooler-tower/)), which takes a 5 or 10 gallon cooler | Beside every third tee, past the bench |
| Practice green flag (`practice_flag.glb`) | 24 in (0.61 m) white stick, 1/2 in across, brass ferrule, 0.2 x 0.14 m flag | A maker's junior flagstick and flag set ([Par Aide](https://www.paraide.com/products/practice-area/practice-green-markers-cups/jr-flagstick-marker-flag-sets/)) | In every cup of the practice green (`PracticeCups`); the cup being putted to flies a yellow flag |
| Course sign (`course_sign.glb`) | 12 x 6 in (0.3 x 0.15 m) moulded resin sign with clipped corners, on a steel spike | A maker's flexible resin course signs ([Par Aide](https://www.paraide.com/products/course-markings/signage/dura-flex-signs/)) | "Please repair ball marks", 2.5 m off the edge of each green on the side players walk on from |

## When they appear

- Tee markers and the bags appear everywhere.
- The tee furniture and rakes appear in the Broadcast and Tour presentations
  at Medium quality and above. They are not drawn in Classic Links, which
  has none, or at Low.
- Rakes are capped at 4, 8 or 12 per hole at Medium, High and Ultra, nearest
  the green first.
- The furniture stands on the right of the tee (looking down the hole), away
  from a right-handed golfer, and moves to the left if the right is water,
  sand, green or out of bounds.
- Everything here is scenery. Nothing collides with it, and the ball's
  physics never see it.

## Owned elsewhere

These props are left to the threads that own them: golf shoes and the cap
(the golfer thread), the grandstand and gallery ropes (the realism thread,
`Gallery`), trees (the trees thread), the flag, the cup and the ball
(the realism thread). The golf buggy is in `tools/buggy/`.

## Next candidates

Cart path direction signs (once cart paths are known on every course
type), and the golfer's own clubs.
