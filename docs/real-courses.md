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
| Ground heights | [Terrain Tiles on AWS Open Data](https://registry.opendata.aws/terrain-tiles/) (Mapzen "Terrarium" PNG tiles, zoom 15) | Open; each underlying source has its own attribution, listed below |

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

### Better national data (not used yet)

Many countries now publish 0.5 to 1 m lidar that is finer than the tiles.
These portals are the candidates for a later "high detail" source per
country. Each needs its own download format and map projection, and some
need a free key, so none is wired in yet:

| Country | Portal | Notes |
| --- | --- | --- |
| England | [DEFRA Data Services Platform](https://environment.data.gov.uk/survey) | 1 m composite DTM, OGL |
| Scotland | [Scottish Remote Sensing Portal](https://remotesensingdata.gov.scot) | lidar phases 1 to 6, OGL |
| Wales | [DataMapWales](https://datamap.gov.wales) | 1 m DTM, OGL |
| Northern Ireland | [OpenDataNI](https://www.opendatani.gov.uk) | partial cover |
| Ireland | [Geological Survey Ireland / OPW lidar](https://www.gsi.ie) | partial cover |
| Netherlands | [AHN via PDOK](https://www.pdok.nl) | 0.5 m DTM, CC0, WCS |
| Belgium (Flanders) | [Digitaal Vlaanderen DHM](https://www.vlaanderen.be/digitaal-vlaanderen) | 1 m |
| Denmark | [Dataforsyningen](https://dataforsyningen.dk) | 0.4 m DHM, free key |
| France | [IGN RGE ALTI / LiDAR HD](https://geoservices.ign.fr) | 1 m, open licence |
| Spain | [CNIG / PNOA lidar](https://centrodedescargas.cnig.es) | CC BY 4.0 |
| Germany | per state (for example NRW, Bavaria open data) | 1 m DGM in most states |
| Switzerland | [swisstopo swissALTI3D](https://www.swisstopo.admin.ch) | 0.5 m, open |
| Finland, Sweden, Norway | National land surveys (MML, Lantmäteriet, Kartverket hoydedata) | 1 to 2 m |
| United States | [USGS 3DEP 1 m](https://apps.nationalmap.gov/downloader/) | public domain |
| Canada | [NRCan HRDEM](https://open.canada.ca) | 1 to 2 m, OGL Canada |
| Australia | [ELVIS](https://elevation.fsdf.org.au) | 1 to 5 m, CC BY |
| New Zealand | [LINZ 1 m lidar](https://data.linz.govt.nz) | CC BY 4.0 |
| Japan | [GSI 5 m DEM](https://fgd.gsi.go.jp) | GSI terms |
| Global | [Copernicus GLO-30](https://spacedata.copernicus.eu) | 30 m, free |

### Aerial photos (planned)

Only public-domain or openly licensed photos may be used (not Google, Bing
or Apple imagery). Candidates: USDA NAIP (US, public domain, 0.6 to 1 m),
the national orthophotos of the Netherlands (PDOK, CC BY), Denmark, France
(IGN BD ORTHO, open licence), Spain (PNOA), Switzerland (SWISSIMAGE), New
Zealand (LINZ, CC BY) and England (Environment Agency vertical photography,
OGL). They would help place single trees and tune ground colours; the
importer doesn't use them yet.

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
- **Cart paths:** `golf=cartpath` and `golf_cart=designated` ways.
- **Ground:** the tile heights at every 2 m sample, bilinear. Heights below
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
itself. Nothing from these services is stored in the repository; each
player's game fetches it when they build a course.

## Code map

```
game/scripts/realcourse/
  geo_frame.gd            GeoFrame: latitude and longitude to course metres
  terrain_tiles.gd        TerrainTiles: which tiles, PNG decoding, height sampling
  real_course_builder.gd  RealCourseBuilder: OpenStreetMap data to a DesignedCourse
  real_course_fetcher.gd  RealCourseFetcher: the Nominatim, Overpass and tile requests
  real_course_dialog.gd   RealCourseDialog: the designer's window
game/tests/realcourse_tests.gd  checks on a made-up map (no network)
```

## Still to do

- High-detail national lidar per country (the table above).
- Aerial photos for tree placement and ground colours.
- Buildings (`building=*`) as objects, and the course outline as out of
  bounds where the club marks it so.
- Building the ground over several frames, so the browser doesn't pause
  for a few seconds on big courses.
