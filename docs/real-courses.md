# Real courses from open data

The course designer can build a real golf course from its name. Press
**Real course...** in the designer, type a club or course anywhere in the
world (for example "St Andrews Old Course"), pick the right match, and the
game fetches open map and elevation data, builds the course, saves it and
opens it in the designer for polishing. It works the same on desktop and in
the browser, needs no account or API key, and uses no Google data.

A course is only as complete as its map. Well-mapped courses (most famous
ones and many clubs in the UK, Europe and the US) come in with every hole,
tee, green, bunker and pond; others may have only a boundary. If OpenStreetMap
has no holes for a course, the importer says so: anyone can map them at
[openstreetmap.org](https://www.openstreetmap.org) (the golf tags are
documented at [wiki.openstreetmap.org/wiki/Tag:leisure=golf_course](https://wiki.openstreetmap.org/wiki/Tag:leisure%3Dgolf_course)),
and the next import picks them up.

## Where the data comes from

| Step | Source | Licence |
| --- | --- | --- |
| Name to place | [Nominatim](https://nominatim.openstreetmap.org) (OpenStreetMap's search) | ODbL; [usage policy](https://operations.osmfoundation.org/policies/nominatim/): at most one search a second, which a person typing never reaches |
| Holes, fairways, greens, tees, bunkers, water, woods, trees, cart paths | [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API) (public servers, tried in turn) | OpenStreetMap, ODbL 1.0 |
| Ground heights | National lidar where a service covers the course (below), else the [Terrain Tiles on AWS Open Data](https://registry.opendata.aws/terrain-tiles/) (Mapzen "Terrarium" PNG tiles, zoom 15) | Per source, below |
| Trees | Lidar canopy height (surface model minus ground) where offered, else the aerial photo, plus OpenStreetMap's trees and woods | As the source |
| Aerial photo | National orthophoto tile services (below) | Per source, below |
| Land cover (trees the map lacks, ground colours without a photo) | [Impact Observatory / Microsoft / Esri Sentinel-2 10 m land cover](https://www.arcgis.com/home/item.html?id=cfcb7609de5f478eb7666240902d4d3d), Esri image service | CC BY 4.0 |

### Elevation by country

The terrain tiles already merge the best open elevation data per region, so
the importer gets national lidar wherever it was open when the tiles were
built, and global data elsewhere. Zoom 15 is about 4.8 m per pixel at the
equator and 2.7 m in Scotland; the course grid is 2 m.

| Where | Underlying data in the tiles |
| --- | --- |
| England | Environment Agency lidar (data.gov.uk, 2 m) |
| United States | USGS 3DEP / National Elevation Dataset (about 10 m, finer in places) |
| New Zealand | LINZ 8 m DEM |
| Norway | Kartverket DEM |
| Austria | Austrian 10 m DGM |
| Australia | Geoscience Australia DEM |
| Canada | CDEM |
| Mexico | INEGI continental relief |
| Arctic | ArcticDEM |
| Europe elsewhere | EU-DEM (25 m) |
| Everywhere else | SRTM (30 m), GMTED, ETOPO1 for the sea floor |

Courses in places covered only by SRTM or EU-DEM come out with the right
broad shape (hills, valleys, the slope of the land) but without small
humps and hollows; those are worth sculpting by hand in the designer.

### National lidar (used where it covers the course)

`NationalLidar` (`game/scripts/realcourse/national_lidar.gd`) asks these
services for the course's box in latitude and longitude, at 1 m, in
requests of at most 1000 pixels a side (Japan's comes as web map tiles).
Where the boxes overlap (near borders), each service is tried in turn and
the first that covers at least a quarter of the course is used. All of them allow requests from a
web page, so the browser build uses them too. Where a service has gaps
(under water, some buildings, past a border) the Terrain Tiles fill in,
shifted to match. Under 25% coverage, it isn't used.

| Where | Service | Ground | Surface (for trees) | Licence |
| --- | --- | --- | --- | --- |
| England | Environment Agency lidar composite, WCS 2.0 | 1 m DTM | 1 m first-return DSM | Open Government Licence v3.0 |
| Netherlands | AHN via PDOK, WCS 2.0 | 0.5 m DTM | 0.5 m DSM | CC0 |
| Flanders (Belgium) | Digitaal Hoogtemodel Vlaanderen II, WCS 1.0 | 1 m DTM | 1 m DSM | Modellicentie Gratis Hergebruik |
| North Rhine-Westphalia (Germany) | Geobasis NRW, WCS 2.0 (asked for Deflate) | 1 m DGM | 1 m DOM | dl-de/zero-2-0 |
| France | IGN RGE ALTI / LiDAR HD via the Geoplateforme WMS-R (float BIL) | 1 m | LiDAR HD MNS where flown | Licence Ouverte 2.0 |
| Norway | Kartverket national lidar (NHM), WCS 1.0 | 1 m DTM | 1 m DOM | CC BY 4.0 |
| Japan | GSI elevation tiles (PNG, height in centimetres): DEM1A at zoom 17 where flown, else DEM5A (zoom 15), else DEM10B (zoom 14) | 1 to 10 m | none | GSI terms (credit) |
| United States | USGS 3DEP ImageServer exportImage | 1 to 10 m, best available | none | Public domain |

`GeoRaster` reads what they send: GeoTIFF in either byte order, float32 or
int16, uncompressed or Deflate with the floating-point predictor, in
strips or tiles, placed by ModelPixelScale and ModelTiepoint or
ModelTransformation; the raw float BIL from WMS; and GSI's colour-coded
PNG tiles.

**Trees from lidar:** the canopy height is the surface model minus the
ground. Every local peak at least 3 m tall is a tree, its height the peak
height, one per 4 m at most; level peaks (roofs) are skipped, and so are
trees on OpenStreetMap buildings, play areas and water. A wooded course
has tens of thousands, so the ones nearest the holes are planted first, up
to 6000; with lidar trees, woods aren't filled by guesswork.

### Aerial photos

`AerialPhotos` (`game/scripts/realcourse/aerial_photos.gd`) fetches web
mercator tiles at zoom 17 (about 0.8 m a pixel; zoom 16 for big courses)
and crops them to a north-up photo of the course, at most 2048 pixels a
side, saved beside the course as `<course>.photo.jpg` (the `.olc` names it
in `source.photo`). The designer lays it over the ground (**Show the aerial
photo**), to check and trace the course against.

| Where | Service | Licence |
| --- | --- | --- |
| Flanders (Belgium) | Digitaal Vlaanderen summer orthophoto (WMS) | Modellicentie Gratis Hergebruik |
| North Rhine-Westphalia | Geobasis NRW DOP (WMS) | dl-de/zero-2-0 |
| Netherlands | PDOK Luchtfoto RGB (Beeldmateriaal Nederland) | CC BY 4.0 |
| Switzerland | swisstopo SWISSIMAGE | free reuse with credit |
| Austria | basemap.at orthophoto | CC BY 4.0 |
| France | IGN BD ORTHO via the Geoplateforme | Licence Ouverte 2.0 |
| Spain | PNOA (IGN Espana) | CC BY 4.0 |
| Japan | GSI seamless photo | GSI terms (credit) |
| United States | USGS The National Map orthoimagery (NAIP) | Public domain |

WMS services are asked for each web mercator tile's box. Services answer
white or empty tiles outside their country; those don't count, and the next
service is tried when fewer than half the tiles have a photo.

**Ground colours from the photo:** with a photo, the ground takes its
colours partly from it, softened to about 6 m so crowns and cars blur out
and kept near the game's own brightness: most beyond the course (fields,
tracks, car parks), a lot in the rough (worn and dry patches), and only a
touch on fairways, tees and greens, which keep their stripes. Deep shade
and water in the photo are skipped. This works in the designer and in the
round (`DesignedTerrain`, `DesignedCourse.tint_image()`).

The photo also helps with trees. With lidar trees, the crown colour picks
pines (dark green) or broadleaves (lighter, or brown in a winter photo).
Without lidar, cells of 5 m that are mostly dark leafy pixels or deep shade,
darker than the fairways' grass, become trees.

### Land cover (everywhere)

`LandCover` (`game/scripts/realcourse/land_cover.gd`) fetches the 10 m
Sentinel-2 land cover for the course box in one request (8-bit classes:
water, trees, flooded vegetation, crops, built-up, bare, snow, clouds,
grass and scrub). It is used where the finer data is missing:

- **Trees:** without lidar or photo trees, each tree pixel outside the
  mapped woods gets a tree, nearest the holes first, at most half of the
  tree budget, and none within 25 m of a hole's line (at 10 m a tree-lined
  fairway reads as woods).
- **Ground colours:** without a photo, a picture of the classes in their
  typical colours (fields, bare ground, towns, grass, woods) is saved
  beside the course as `<course>.ground.png` (`source.ground`) and tints the
  ground the same way a photo does. It is coarse (10 m) and doesn't show in
  the designer's photo overlay.

### Not covered yet

England has no open aerial photo service. These were checked on
2026-10-31 and don't work from a web page yet, so courses there use the
Terrain Tiles (see the table above) and OpenStreetMap's trees:

- Scotland (remotesensingdata.gov.scot): its WCS is switched off.
- Wales (DataMapWales): the GeoServer has no lidar coverage.
- Ireland (GSI/OPW): lidar coverage maps only, no height service.
- Denmark (Dataforsyningen): needs a free account token.
- Canada (NRCan HRDEM): the WCS rejects requests in latitude and longitude.
- Australia (ELVIS): no open height service.
- New Zealand (LINZ): needs a key.
- Wallonia, Germany's other states, Switzerland's swissALTI3D, Sweden,
  Finland: answer only in their national projection, or with no
  cross-site access.
- Spain's 5 m model: whole metres only.

### Scorecards

Par comes from each hole's `par` tag and the stroke index from its
`handicap` tag when mappers have added them; otherwise par is guessed from
the length. Most scorecard websites forbid copying their data, so the
importer doesn't read them. Anyone can add a missing par or stroke index to
OpenStreetMap from the club's own published scorecard.

## How the map becomes a course

`RealCourseBuilder` (`game/scripts/realcourse/real_course_builder.gd`):

- **Area:** the `leisure=golf_course` outline containing the picked place
  (or the nearest one), plus 80 m of ground round it, at most 3.6 km a side.
  With no outline, the golf features within 1.5 km of the place.
- **Projection:** a local tangent plane at the course centre (`GeoFrame`):
  +z north, +x west. Latitudes and longitudes stay 64-bit floats until they
  are metres, since a `Vector2` would round them by tens of centimetres.
- **Areas:** `golf=green`, `tee`, `fairway`, `bunker` (sand), `rough`,
  `fringe`, `water_hazard` and `lateral_water_hazard`, `natural=water`
  (water), `natural=scrub` and `heath` (deep rough). Multipolygons are joined
  from their outer ways. Outlines are simplified (0.3 m for greens, tees and
  bunkers, more for big areas, at most 90 points) and clipped to the area.
  Streams, ditches and rivers become water strips cut into 60 m pieces, so
  each piece keeps its own water line on sloping ground.
- **Several courses at one club:** when the holes' `golf:course:name` names
  two or more courses of nine holes or more, each is built as its own
  course; the first is opened and the others saved beside it.
- **Holes:** each `golf=hole` line whose start or end lies inside the chosen
  course's outline, in `ref` order. The pin is the `golf=pin` on the green
  at the end of the line, else the green's centre; tees are the tee boxes
  along the start of the line, back to forward (up to three); the line's
  bends become aim points. A line drawn green to tee is turned round.
- **Trees:** `natural=tree` points (sized by their `height` tag),
  `natural=tree_row` lines (a tree every 7 m) and woods (`natural=wood`,
  `landuse=forest`) filled on a jittered 9 m grid, thinned to keep the
  course under 5000 trees. `leaf_type` picks pines or broadleaves. No tree
  is planted on a fairway, green, tee, bunker or in water.
- **What the map lacks:** many clubs are mapped with their hole lines but
  not every green, tee, fairway or bunker. `CourseGuesser`
  (`game/scripts/realcourse/course_guesser.gd`) draws whatever a hole is
  missing at typical sizes along its line: a green round the pin (about
  520, 600 and 650 m2 for par 3, 4 and 5, a quarter longer than wide), a
  tee box at each tee, on par 4s and 5s a fairway from the landing area
  (at most 140 m out) to the green, about 34 m wide and narrower at its
  ends, and, on holes with no bunker mapped within 45 m of the line, two
  or three greenside bunkers and a fairway bunker at 230 m. They are saved
  with `"guessed": true`, and the designer's message says how many there
  are, so they can be checked against the photo and redrawn.
- **Cart paths:** `golf=cartpath` and `golf_cart=designated` ways.
- **Ground:** the lidar or tile heights at every 2 m sample, bilinear. Heights below
  -12 m (the sea floor) are raised to -12 m, then the grid is stored round
  the midpoint of its range; the sea-level height of that midpoint is kept
  in the course's `source`.

The result is an ordinary designed course (`.olc`) with two extra keys:
`credits` (the attribution, shown under the course name in the designer)
and `source` (where it came from). It plays with the usual ground textures,
grass and trees of the current graphics look.

## Licence notes

OpenStreetMap data is under the [ODbL](https://opendatacommons.org/licenses/odbl/).
A course built from it is a derivative of the map: keep its `credits` when
sharing it, and share it under the ODbL too. The importer adds the credits
itself, with one line for each lidar or photo source used. Nothing from
these services is stored in the repository; each player's game fetches it
when they build a course. The aerial photo stays on the player's machine
beside the course and isn't part of an exported `.olc`.

## Code map

```
game/scripts/realcourse/
  geo_frame.gd            GeoFrame: latitude and longitude to course metres
  geo_raster.gd           GeoRaster: GeoTIFF and BIL height grids
  national_lidar.gd       NationalLidar: the lidar services, and trees from the canopy
  aerial_photos.gd        AerialPhotos: the photo services, the course photo, trees from it
  land_cover.gd           LandCover: 10 m land cover, trees and ground colours from it
  course_guesser.gd       CourseGuesser: greens, tees, fairways and bunkers the map lacks
  terrain_tiles.gd        TerrainTiles: which tiles, PNG decoding, height sampling
  real_course_builder.gd  RealCourseBuilder: OpenStreetMap data to a DesignedCourse
  real_course_fetcher.gd  RealCourseFetcher: the Nominatim, Overpass and tile requests
  real_course_dialog.gd   RealCourseDialog: the designer's window
game/tests/realcourse_tests.gd  checks on a made-up map (no network)
```

## Still to do

- Finding missing greens, fairways and bunkers in the lidar (hollows,
  smooth raised greens) and photos (bright sand, striped grass) instead of
  guessing them.
- More lidar and photo services (above); reprojecting from national
  grids would open most of the rest.
- Buildings (`building=*`, already read to keep trees off them) as
  objects, and the course outline as out of bounds where the club marks it
  so.
- Building the ground over several frames, so the browser doesn't pause
  for a few seconds on big courses.
