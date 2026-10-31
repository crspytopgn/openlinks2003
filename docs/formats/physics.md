# Ball physics (`LinksMMIII.exe`)

Status: partial (flight, launch, bounce and roll complete; the swing meter,
lies and putting are next)
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
these per-class values as defaults (`links_surface`).

The game can write the records out as a table, which gives the names of all
fourteen values: 0x04 LieAngular, 0x08 LieAngularSnap, 0x0C LiePower, 0x10
LiePowerSnap, 0x14 CoefRestitution, 0x18 CoefFriction, 0x1C CoefViscosity,
0x20 Maliability, 0x24 RollingFriction, 0x28 RollingThreshold, 0x2C
ImpactOffset, 0x30 AngleMiss, 0x34 PowerMiss and 0x38 Snap. The first and
third are the lie effects below; the snap and miss values belong to the
swing meter:

| Class | LieAngular | LiePower | LieAngularSnap | LiePowerSnap | AngleMiss | PowerMiss | Snap |
|-------|-----------|----------|----------------|--------------|-----------|-----------|------|
| Green, fairway, water | 1 | 1 | 0.1 | 0 | 1 | 1 | 1 |
| Rough | 0.41 | 0.93 | 0.1 | 0.03 | 1.5 | 1.5 | 1.5 |
| Sand | 1 | 1 | 0.2 | 0.2 | 1.9 | 1.9 | 2 |
| Deep grass | 0.20 | 0.84 | 0.1 | 0.05 | 1.7 | 1.7 | 2 |
| Cart path | 1 | 1 | 0.1 | 0 | 2 | 2 | 4 |

Green hardness (soft, moderate, hard) and green speed (slow, normal, fast)
are game options that may override the green's values; the game warns that
a course's own settings "could produce unexpected results".

## Launch

The launch turns a strike into the ball's starting velocity and spin. It is
ported as `olcore::links_launch` (`links_launch.cpp`) and `LinksLaunch`
(`links_launch.gd`), and matches the game on 300 random strikes (every club,
aim, slope and setup) to within 1e-5.

### Club table

Five per-club rows of 19 floats, each followed by a spare zero, lie together
in the executable's data. The clubs are seven woods (driver first, lofts 12
to 25 degrees) and then twelve irons and wedges (1 iron at 16 degrees to the
lob wedge at 60). The putter is not in the table. Rows, in order:

| Row | Our name | Meaning | Range |
|-----|----------|---------|-------|
| 0 | `spin` | spin per unit of strike | 1.6 (driver) to 5 |
| 1 | `speed` | ball ft/s per percent of power | 2.0 to 2.8 |
| 2 | `loft_deg` | face loft in degrees | 12 to 60 |
| 3 | `glance` | share of speed left along the face | 0.05 to 0.2 |
| 4 | `ball_position` | degrees of loft per 14 ball-position steps | 10 to 15.9 |

As with the coefficient tables, the values are read from the player's
executable (`find_links_clubs` looks for five rows of plausible values with
zeros after the first four), and both versions of the game carry the same
numbers.

### Inputs

The shot record the launch reads holds the club, the aim heading, the power
in percent (100 is a full swing), a face error and a path error in radians,
a speed and a spin multiplier (both 1 for a clean strike), a loft multiplier
(normally 1) and three setup bytes: ball position, club face and stance, as
on the shot setup screen. Face and stance are square at 30. The neutral ball
position is 2 for the driver and 4 for every other club.

### The model

In the aim frame (x right, y along the aim line, z up), angles in degrees:

- Loft = loft multiplier x table loft + (neutral position - ball position)
  x table ball-position value / 14. Moving the ball back delofts the club.
- Path angle = (stance - 30) - path error. Face angle = (face - 30) +
  (stance - 30) - face error. So the stance turns both, the face setting
  turns only the face.
- Face normal F = (cos loft sin face, cos loft cos face, sin loft). Path
  P = (sin path, cos path, 0).
- Slope: the ground normal under the ball is turned into the aim frame and
  two angles are taken from it, across = atan2(n.x, n.z) clamped to +/-30
  and along = atan2(n.y, n.z) clamped to +/-15. F is turned about z by
  -across/10 (a side slope nudges the face), then F and P are both turned
  about x by -along (an up or down slope tilts the whole swing).
- d = F . P, how square the blow is. G = the unit part of P at right
  angles to F (the glancing direction).
- Strike speed S = speed multiplier x table speed x power.
- Velocity = (F d + G d glance) S: the ball leaves along the face normal
  with a little of the path left over along the face.
- Spin = (G x F) S x spin multiplier x table spin x 0.25 x d, in rev/s.
  With a square face this is pure backspin; a face open to the path tilts
  the axis for a slice, closed for a hook.
- Velocity and spin are turned from the aim frame to the course by the aim
  heading.

A full square driver leaves at 63.4 m/s (142 mph), 9.1 degrees up, with
5,050 rpm of backspin; through the Links flight, bounce and roll on flat
fairway it carries 231 yards and finishes at 252. The pitching wedge
carries 135 yards.

The launch also seeds the random numbers (see Rough and rocks) and sets the
ball on the ground at 0.07 / n.z above its lie.

### Lie effects

Before the launch, the routine that turns a swing into a shot looks up the
ground under the ball and sets the strike's spin and speed multipliers to
the lie's LieAngular and LiePower: from rough the ball keeps 41 percent of
its spin and 93 percent of its speed, from deep grass 20 and 84 percent.
This replaces whatever multipliers the swing gave. Computer players and one
unidentified player setting skip this step.

Sand works differently. The face error is dropped, so only the path shapes
a bunker shot, and the multipliers come from how much sand the club takes,
a whole-step miss from the swing meter (c below; 0 is the standard splash):

| Contact | Speed | Spin | Loft |
|---------|-------|------|------|
| c >= 0 (heavier) | 0.3 + (15 - c) / 150 | 0.25 + (15 - c) / 12 | 1 |
| -5 <= c < 0 (cleaner) | 0.4 + 0.1 |c| | 1.5 - 0.1 |c| | 1 |
| c < -5 (thin) | 0.9 - 0.065 (|c| - 5) | 1.5 - 0.1 |c| | 1 - 0.09 (|c| - 5) |

So a standard splash leaves at 40 percent of the speed of the same swing
from the fairway, with one and a half times the spin; a clean pick (c = -5)
keeps 90 percent. Both are then scaled by the sand's own lie values (1).
Ported as `links_apply_lie` (olcore) and `LinksLaunch.apply_lie`, checked
against the game's code on 32 lies and contacts.

### Not ported

- A flag from the caller that adds 10 degrees of loft and removes all spin;
  what sets it is not known yet.
- How the swing meters (PowerStroke and the mouse swing) fill the power,
  the face and path errors and the sand contact. Until then the game shell
  maps the meter's accuracy to a face error of up to 4 degrees and a sand
  contact of up to 10 steps heavy.
- Per-course lie values: olcore uses the class defaults above (every
  course checked so far uses them).

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
- How the swing meters fill the launch inputs (next step).
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
