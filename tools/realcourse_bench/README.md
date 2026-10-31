# Real-course detection benchmark

Measures how well `CourseDetector` finds greens, bunkers and fairways, on
courses whose OpenStreetMap mapping is complete: the mapped shapes are taken
out, `CourseGuesser.fill` runs, and what it finds is scored against the map.
Dev tool only: the fetched data stays in `/tmp/bench` and is never committed.

```bash
export GODOT=/path/to/godot          # Godot 4.4
tools/realcourse_bench/bench_all.sh  # fetch the courses in bench_list.txt and their close-ups
$GODOT --headless --path game -s $PWD/tools/realcourse_bench/bench_eval.gd            # all
$GODOT --headless --path game -s $PWD/tools/realcourse_bench/bench_eval.gd -- crans   # one
$GODOT --headless --path game -s $PWD/tools/realcourse_bench/bench_view.gd -- crans 0 # picture
```

`bench_eval.gd` prints, per course and in total:

- greens: mapped greens holding a pin, how many were found, how many overlap
  the mapped green by 60% or more ("good"), the mean overlap (intersection
  over union), and "wrong" (overlap under 20%);
- sand: mapped bunkers within 45 m of a pin, bunkers found, found ones on a
  mapped bunker ("hit") or not ("false"), and mapped bunkers found;
- fairways: par 4 and 5 holes, fairways found, the mean share of a found
  fairway on a mapped one, and "bad" (under half).

`bench_lengths.gd -- <slug>` prints each hole's length in yards, to check against the
club's scorecard. `NODETAIL=1` leaves out the close-ups and `NOPHOTO=1` the course photo.
`bench_view.gd` draws six holes: mapped shapes on the left, found ones on
the right (`/tmp/bench/view_<slug>_<first hole>.png`). The fetch scripts
need network access to Nominatim, the OSM API and the photo services.
