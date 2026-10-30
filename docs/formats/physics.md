# Ball physics (`LinksMMIII.exe`)

Status: partial (flight, bounce and roll complete; launch located but not
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
5. **Collision.** The straight path of the ball's centre from p to p' is
   tested against the terrain and objects. The ground counts as hit where
   the centre reaches it (not one radius above it). On a hit the ball is
   put back to the contact: velocity and spin are blended between the start
   and end of the step at the moment of contact (see below), the centre is
   placed one radius off the ground along the normal, and the impact is
   resolved. The rest of that step is dropped.

   The moment of contact assumes the velocity changed linearly over the
   step. With `a` the ratio of one velocity component at the start of the
   step to the same component at the end (x if it is non-zero at both ends,
   else z, else y), and `s` the fraction of the path covered, it solves
   `(1 - a) t^2 + a t = s` for t between 0 and 1.

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
values (offsets 0x04 to 0x38); the ground class byte follows at 0x54. When
the ball touches the ground the game looks up the record under it. In the
two courses checked so far (Gleneagles and the driving range) every record
of a ground class carries the same values, apart from a second cart path
(asphalt beside concrete) and one rough record that uses the deep grass
values.

The ground code reads seven of them:

| Offset | Name | Use | Green | Fairway | Rough | Sand |
|--------|------|-----|-------|---------|-------|------|
| 0x14 | restitution | normal speed kept by a bounce | 0.23 | 0.27 | 0.24 | 0.20 |
| 0x18 | impact friction | friction in a bounce | 0.08 | 0.13 | 0.088 | 0.05 |
| 0x1C | skid friction | friction while the ball slides | 0.38 | 0.13 | 0.10 | 0.071 |
| 0x20 | impact drag | speed lost along the ground in a bounce | 0.50 | 0.44 | 0.52 | 0.64 |
| 0x24 | roll resistance | rolling resistance | 0.11 | 0.18 | 0.60 | 0.90 |
| 0x28 | stop speed | bounces end when the ball leaves slower than twice this | 0.5 | 0.5 | 1 | 0.5 |
| 0x2C | spin grip | how much spin friction puts on | 1.2 | 1.0 | 2 | 4 |

The other classes: water (5), cart path (6, the hardest and fastest:
restitution 0.75, roll resistance 0.07), dirt (7), bushes (8), rocks (9,
restitution 0.50) and deep grass (10, roll resistance 0.61). olcore keeps
these per-class values as defaults (`links_surface`); the remaining
offsets, 0x04 to 0x10 and 0x30 to 0x38, are lie and launch values (0x04 is
probably the share of full power from that lie: rough 0.41, deep grass
0.20).

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

The ball is in one of four modes: flight, skid (sliding, spin not yet
matched to the speed), roll and rest. All of it was checked by running the
game's own routines on made-up terrain (flat, sloped, a bowl, a crest, a
ledge, a cliff, every ground class) and comparing every 1/60 s step with
olcore: they agree to rounding, and the ball stops on the same step.

### Bounce

At a landing on ground with normal n:

- **Water** stops the ball. **Sand** plugs it when it comes in faster than
  60 ft/s along the normal, one landing in four (picked from the landing
  position, `int((x + y + z) x 12)` divisible by 4).
- The frame: `side` is the unit vector along n x v, `along` is side x n.
  `vt` is the speed along the ground, `vn` the speed into it, and `w0` the
  spin about `side` in rad/s.
- **Drag along the ground:** `L = sqrt(vt vn) x impact drag`, scaled by
  `0.4 + vt vn / 2833` when `vt vn` is under 1,700 (a gentle landing loses
  less), and never more than vt.
- **Spin:** if the ball is already close to rolling (the bottom of the ball
  slips by less than 0.2 ft/s), it keeps `vt - L` and takes the matching
  spin. Otherwise friction acts: the speed changes by
  `-(1 + e) mu vn - L` and the spin by `(1 + e) grip mu vn x 2.5 / R` (both
  reversed when the backspin is faster than the ball), where e is the
  restitution, mu the impact friction and grip the spin grip. If that
  would reverse the slip, the ball stops at rolling instead, at the speed
  where the two lines cross.
- **Rebound:** the normal speed is multiplied by the restitution. On rough
  the outgoing direction turns by up to plus or minus 3.7 degrees, and off
  rocks by any angle, both picked from the landing position rather than at
  random.
- The spin keeps only its component about `side`. If the ball leaves with
  less than twice the surface's stop speed along the normal, it does not
  bounce: it starts to skid along the ground.

### Skid and roll

Each step of dt (1/60 s), with n the ground normal one step ahead along the
velocity:

- **Slope:** the pull along the ground is gravity times the normal's
  horizontal tilt, scaled by `sqrt(0.5625 sin^2 + 0.25 cos^2)`, where the
  angle is between the slope and the direction of travel: a ball rolling
  straight down a slope feels half of the pull, one rolling across it three
  quarters.
- **Resistance:** the roll resistance times the ground's support (gravity
  plus that pull), growing by 20% per ft/s above 30 ft/s. When it would
  stop the ball within the step, the ball rests if the slope cannot move
  it, and otherwise starts again from standstill.
- **Skid friction:** while skidding, friction of `support x skid friction`
  opposes the slip of the bottom of the ball, and turns into spin at
  `spin grip x 5.684 x dt` per step. Once the slip is small enough to stop
  within a step, the ball rolls, and from then on its spin just follows its
  speed.
- The new position sits on the ground (centre `R / n.z` above it), and the
  velocity is turned to run along the ground there, keeping its speed.
- **Leaving the ground:** if that new height differs from the old by more
  than 0.316 ft (`0.1` squared), the step is thrown away and the ball flies
  instead, so it sails off ledges and cliffs and over sharp crests.
- **Too steep:** on grass (green, fairway, rough, deep grass), where the
  slope is steeper than about 53 degrees (`n.z < 0.6`), the game looks up
  to a foot ahead in steps of 1/12 ft for flatter ground within a foot of
  the ball's height, and drops the ball onto it.
- **Stuck:** every second on the ground the ball must have moved 0.14 ft
  across, or it stops.

### Rough and rocks

The game has a random number generator: a 32-bit shift register (feedback
from bits 0, 1, 2, 4, 6 and 31; each number takes 32 shifts and keeps the
low bit of each), seeded at launch from the ball's position in whole feet
(x times y, or 0x12345678 when that is zero).

- **Rough:** each step on the ground draws two numbers. Above 1.5 ft/s, 45%
  of steps make the ball hop: it flies towards a point a little above the
  ground ahead (0.02 ft plus a random share of up to 0.13 ft, the full
  amount at 40 ft/s, less when slower) at 90% of its speed. This is what makes a ball in the rough
  bobble and die.
- **Rocks:** above 1 ft/s the ball is kicked up halfway between its path
  and the normal, keeping its speed times the restitution. Slower, it
  either stops (half the time) or is flicked up by up to six times its
  speed.

### Not ported

- The cup: the game's hole routine (and its 0.18 ft radius) is not worked
  through; olcore uses its own.
- Trees and other objects in flight and while rolling, and balls rolling
  on objects such as bridges.

## Open questions

- How green hardness and speed change the green's values.
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
   distance, number of bounces, and roll after landing. The bounce and roll
   code already matches the game's; this checks the launch and the spin it
   lands with.
4. 30 ft putts on a flat green at each green speed setting: how far a
   given meter setting rolls.
5. 7 iron from fairway, rough, deep grass and sand at full power: carry.
