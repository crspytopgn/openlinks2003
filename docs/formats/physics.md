# Ball physics (`LinksMMIII.exe`)

Status: partial (flight complete; launch, bounce and roll located but not
yet worked through)
Seen in: the main executable, `LINKSM_1.EXE` on CD1 and `LinksMMIII.exe` in
the 1.07 patch (same model and tables in both), plus the `TerrainTypes`
entry of every course (see [crz.md](crz.md)).

## Overview

The game simulates the ball itself, in feet and seconds, with z pointing up.
A shot is a state machine: each 1/60 s step looks at the ball's mode and
runs one of a handful of routines (in flight, on the ground, rolling, at
rest, and a few special cases such as hitting a tree). Up to 2,000 steps
are kept for the replay and the tracer.

Everything below was found by reading the executable; the numbers in
olcore and the GDScript port come from this description. The two
coefficient tables are read from the player's own executable at runtime and
are not reproduced here.

## Units

| Quantity | Unit in the game |
|----------|------------------|
| Distance | feet |
| Speed | feet per second |
| Spin | revolutions per second (a vector along the spin axis) |
| Gravity | 32.152 ft/s^2 straight down (about 9.80 m/s^2) |
| Ball radius | 0.07 ft (a 1.68 in ball) |
| Step | 1/60 s (1/35 s in one special case not yet identified) |

The radius appears all over the ground code (offsets of 0.07 ft from the
surface). The constant 2.27364, which is 1 / (2 pi x 0.07), turns a surface
speed of the ball in ft/s into spin in rev/s.

## Flight

Each step takes the ball's position p, velocity v and spin w and does:

1. **Air velocity.** The wind is given as a heading in degrees and a speed.
   Its velocity is `speed x 0.73333` ft/s along `(sin heading, cos
   heading, 0)`, so it is horizontal, the same at every height, and blows at
   half of `speed x 1.46667` (mph to ft/s). Whether the speed the HUD shows
   is the same number is not confirmed yet. `a = v - wind`.
2. **Coefficients.** Drag `Cd` and lift `Cl` each come from a 2D table
   indexed by `|a|` (ft/s) and `|w|` (rev/s), bilinear between grid points
   and clamped to the edge of the grid.
3. **Acceleration.**
   - drag: `-0.004735 x Cd x |a| x a`
   - lift: `0.0057443 x Cl x |a| x (w/|w| x a)` (the spin axis crossed with
     the air velocity, so backspin lifts)
   - gravity: `(0, 0, -32.152)`

   Both scale factors are in 1/ft. 0.0057 is about what
   `0.5 x air density x ball area / ball mass` comes to for a regulation
   ball, so the tables hold true coefficients; drag is scaled down by about
   a fifth on top.
4. **Integration.** `v' = v + acceleration x dt`, then
   `p' = p + (v + v') / 2 x dt`. Spin is multiplied by `0.9994 ^ (60 dt)`,
   so a ball loses about 3.5% of its spin per second in the air.
5. **Collision.** The segment from p to p' is tested against the terrain
   and objects. On a hit the step is split at the contact point, the ground
   or object routine resolves the impact, and the rest of the step is run
   from there.

Two other pairs of scale factors (0.00712 for drag, 0.056991 for lift)
sit behind a flag that is only ever cleared, so they are unused in play.

### Coefficient tables

Each table is stored as: `u32 rows` (11), `u32 columns` (14), 11 f32 air
speeds in ft/s from 0 to 321, 14 f32 spin rates in rev/s from 0 to 200, two
u32 pointers to those axes, a u32 zero, then 11 x 14 f32 values, one row
per speed. The drag table comes first. Drag values are all positive, about
0.25 to 0.35 at golf speeds and up to 0.76 when the ball is nearly still.
The lift table is zero in the no-spin column and rises with spin, more
steeply at low speeds. `olcore::find_links_aero` and `LinksAero.from_exe`
find the two tables by this shape.

With these tables and tour-average launch data (167 mph, 10.9 deg, 2,686 rpm
for a driver) the driver carries about 274 yards, a 7 iron about 191 and a
sand wedge about 121.

## Per-surface values (`TerrainTypes`)

Each course's `TerrainTypes` record starts with a u32 index and 14 f32
values (offsets 0x04 to 0x38); the ground class byte follows at 0x54. The
game copies the 14 values of the surface under the ball into a global
block, which starts out holding the cart path values. In the two courses
checked so far (Gleneagles and the driving range) every record of a ground
class carries the same values, so in practice they are per class.
Which routine reads which value is the next thing to work out; until then
the names below are guesses from the values.

| Offset | Fairway | Green | Guess |
|--------|---------|-------|-------|
| 0x04 | 1.0 | 1.0 | lie: share of full power (rough 0.41, deep grass 0.20) |
| 0x08 | 0.1 | 0.1 | |
| 0x0C | 1.0 | 1.0 | lie: share of spin or accuracy (rough 0.93) |
| 0x10 | 0 | 0 | lie: randomness (rough 0.03, sand 0.2) |
| 0x14 | 0.27 | 0.23 | bounce: normal restitution (cart path 0.75) |
| 0x18 | 0.13 | 0.08 | bounce: friction along the surface |
| 0x1C | 0.13 | 0.38 | bounce: spin response |
| 0x20 | 0.44 | 0.50 | |
| 0x24 | 0.18 | 0.11 | roll: resistance (sand 0.90, cart path 0.07, water 2.0) |
| 0x28 | 0.5 | 0.5 | |
| 0x2C | 1.0 | 1.2 | (rough 2, deep grass 3, sand 4) |
| 0x30 to 0x38 | 1, 1, 1 | 1, 1, 1 | (rough 1.5, deep grass 1.7 to 2, sand 1.9 to 2) |

Green hardness (soft, moderate, hard) and green speed (slow, normal, fast)
are game options that may override the green's values; the game warns that
a course's own settings "could produce unexpected results".

## Launch

The launch routine turns the swing into the ball's starting velocity and
spin. It uses per-club tables of 19 entries: seven woods (lofts 12, 15, 17,
19, 21, 23 and 25 degrees), irons 1 to 9 (16 to 44 degrees), and pitching,
sand and lob wedges (49, 55, 60 degrees). Beside the lofts there are four
more per-club tables (a speed factor from 2.0 to 2.8, a spin factor from 1.6
to 5, a small value from 0.05 to 0.2, and a value from 10 to 15.9), and the
ball speed looks like a club head speed in mph times 2.3436 (1.46667 ft/s
per mph times about 1.6) times the dot product of two directions, probably
the face and the swing path. Two launch angles are clamped, one to plus or
minus 15 degrees and one to plus or minus 30. Not ported yet: our launch
still uses tour-average launch monitor data.

## Ground

Not ported yet. The routines that resolve a landing, a bounce and the roll
read the per-surface values above. An impact turns the ball's velocity
into the surface's frame, works out how much spin the surface takes (using
the 0.07 ft radius and a threshold of 1,700), and turns it back. Hits on
trees appear to add a random deflection.

## Open questions

- Which per-surface value each ground routine reads, and how green
  hardness and speed change them.
- The full launch: where club head speed comes from (golfer profile, swing
  power) and how the four extra club tables are used.
- Whether the HUD shows the stored wind speed, which the flight halves.
- When the step is 1/35 s instead of 1/60 s.

## Checks against the real game

For when the game can be run side by side, on the driving range with no
wind and then with wind:

1. Full driver, 7 iron and sand wedge from the tee: carry, total, apex and
   hang time as the game's shot info reports them. These pin down the
   launch, given the flight model above.
2. The same three with 10 mph of wind into the golfer, behind and across:
   is the change half of what a true 10 mph wind would do?
3. Pitching wedge onto the green and onto the fairway: first bounce
   distance, number of bounces, and roll after landing.
4. 30 ft putts on a flat green at each green speed setting: how far a
   given meter setting rolls.
5. 7 iron from fairway, rough, deep grass and sand at full power: carry.
