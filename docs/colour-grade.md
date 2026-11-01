# The learned colour grade

The Photoreal look ends with a colour lookup (LUT) fitted so that the sky,
turf, trees and sand in our renders match the colours measured in real golf
photos. The fit is a measurement, not judged by eye. The lookups are in
`game/grade/` (one per time of day and renderer, 32x32x32, laid out as
1024x32 PNGs). `post_process.gdshader` applies them with two texture reads,
so they cost the same on every tier, the web included.

## How it is fitted

`tools/grade/fit_grade.py`:

1. **Regions.** Each photo and render is split into sky, turf, trees and
   sand by colour (CIE Lab) and height in the frame. The rules are strict,
   so people, carts, water and buildings are left out. Photos with little
   turf or sky are skipped, such as portraits and clubhouses. For the
   sunny-day fit, only photos whose sky is blue are kept (`--blue-sky -12`).
2. **Targets.** For each region, the median over the photos of each photo's
   Lab mean and spread.
3. **The lookup.** First a gentle lightness curve takes the renders' overall
   light and dark 40% of the way to the photos'. Then each region gets a
   Lab shift onto the photos' mean, with lightness stretched to their
   spread and colour shifted only, never stretched (stretching tints greys).
   The shifts are blended by how much an input colour looks like each
   region in the renders. Colours like none of them keep their own colour,
   and so do greys and whites (clouds, caps, the flagstick).
4. **Strength.** Afternoon uses 1.0, midday 0.9 and morning 0.85. The
   morning and midday renders already differ from afternoon on purpose, and
   the photos are mostly afternoon light.

The photos are only measured. The lookup holds nothing of them but a
handful of averages per region, and the photos are never committed.

## The photos

The 2026-11-01 fit used 62 sunny-day golf photos:
- Geograph Britain and Ireland: parkland and links courses (CC BY-SA 2.0),
  found with the `golf fairway`, `golf green flag` and `golf links`
  searches.
- Wikimedia Commons: Augusta National, and a Thai parkland course
  (CC BY-SA).

| Region (median Lab) | Photos       | Ours before #155 | Ours after #155 |
|---------------------|--------------|------------------|-----------------|
| Sky                 | 75 / -2 / -27 | 47 / 1 / -14    | 50 / 1 / -15    |
| Turf                | 56 / -16 / 31 | 45 / -26 / 38   | 50 / -18 / 30   |
| Trees               | 29 / -10 / 16 | 24 / -16 / 20   | 27 / -13 / 18   |

These are Compatibility afternoon renders of the default course, hole 2,
from the tee, the green and 14 m up. The fixes at source (turf tone and
exposure, #155) closed most of the turf gap. With the lookup on top, each
region's mean lands within about 2 (turf, trees) to 8 (sky) Lab units of
the photos. The sky can't go all the way, because lifting it further would
also lift every dark blue in the frame.

## Refitting

Refit after any change to the light, sky, exposure or surface colours.

1. Render each time of day with the HUD hidden: Compatibility, then
   Forward+ through lavapipe (see aaa-graphics-plan.md). The renders come
   from the uncommitted helper described in the thread memory: hole 2, the
   three views, with `PostProcess.grade_lut` off.
2. Run:

```
python3 tools/grade/fit_grade.py --refs photos/ --blue-sky -12 \
    --renders 'renders/compat-afternoon-*.png' --out game/grade/afternoon_compat.png \
    --strength 1.0 --preview /tmp/preview --report /tmp/report.json
```

3. Check the previews against the photos and the report's
   `distance_after`.

## Still to do

- **Golden hour.** It has no lookup yet. Real golden-hour golf photos on
  Geograph and Commons are too few and too mixed to fit one honestly. Our
  golden-hour renders are also very dark (trees at L 16), which is a source
  problem first.
- **Per-course looks** (links against parkland) belong at source, in each
  course's surface colours, not in a global lookup.
