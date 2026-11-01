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
values (offsets 0x04 to 0x38); the ground class follows at 0x54 (the whole
record is in [crz.md](crz.md#terraintypes-ground-classes)). When the ball
touches the ground the game looks up the record under it. Most records of a
ground class carry the same values, but not all: Gleneagles has a second
cart path (asphalt beside concrete) and rough records that use the deep
grass values, and other courses have their own dirt and grass. The bounce
and roll now use the record under the ball (`olcore::links_surface(const
CrzTerrainType&)`, `CourseAreas.links_surface`); green records are the
exception, as the game's green options below replace them all.

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
these per-class values as defaults (`links_surface`) for ground without
records (our own courses and the designer).

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

### Green firmness and speed

The game's green options replace every green record on the course. Firmness
(soft, moderate, hard) picks one of three built-in green records; moderate
is the default record above. Speed (slow, normal, fast) then sets the
rolling resistance from those three records' own values: normal keeps the
firmness's own, and each step faster or slower moves one record along, past
the ends by the same step again:

| Firmness | Restitution | Impact friction | Skid friction | Impact drag | Spin grip | Slow | Normal | Fast |
|----------|-------------|-----------------|---------------|-------------|-----------|------|--------|------|
| Soft | 0.21 | 0.09 | 0.315 | 0.549 | 0.9 | 0.1361 | 0.1208 | 0.1054 |
| Moderate | 0.23 | 0.08 | 0.383 | 0.496 | 1.219 | 0.1208 | 0.1054 | 0.09 |
| Hard | 0.25 | 0.10 | 0.2025 | 0.461 | 1.3 | 0.1054 | 0.09 | 0.0746 |

(the last three columns are the rolling resistance). The other values match
the default green. The options sit on the game's Conditions screen with the wind (none, breezy,
windy), and the tournament screen sets the same three per round; there is
no fairway firmness option. A "course settings" choice keeps the course's own records
instead, which the game warns "could produce unexpected results". The code
also has a second set of three records and three more speeds, with their own
formulas, that the options screen does not offer; they are not ported.
Ported as `links_green` (olcore) and `LinksGround.green_for`; the game shell
has "Green firmness" and "Green speed" settings (medium and normal by
default).

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
unidentified player setting skip this step (human players go through the
swing model below, which starts from the same values).

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

### The swing: how a miss reaches the strike

For a human player the same routine then applies the swing. Its inputs are
the swing method, the skill level (0, the easiest, to 3), and the meter's
accuracy as a whole number of steps, the contact c (positive is a hook, and
for sand a heavier strike). Each lie has three more values for this:

| Class | LieAngularSnap | LiePowerSnap | Snap |
|-------|----------------|--------------|------|
| Green, fairway, water | 0.1 | 0 | 1 |
| Rough | 0.1 | 0.03 | 1.5 |
| Deep grass | 0.1 | 0.05 | 2 |
| Sand | 0.2 | 0.2 | 2 |
| Path | 0.1 | 0 | 4 |
| Dirt, rocks | 0.1 | 0 | 3 |
| Bushes | 0.1 | 0 | 1.5 |

**PowerStroke.** On levels 1 to 3 the contact becomes a miss m:

1. An overswing (power above the golfer's full power P) multiplies it by
   (power - P) / 2 when that is above 1.
2. It is multiplied by 2, 5 or 6 for levels 1, 2 and 3, then by the lie's
   Snap (whole numbers, truncated at each step).
3. A non-zero miss is scattered: m = int(m (0.35 + 0.001 (r1 + r2 + r3)))
   with three draws of 0 to 100, so between 0.35 and 0.65 of itself. It is
   capped at +/-60.
4. The turn is m (75 + r) / 100 degrees with r from 0 to 24, times 2/3, 1/1.9
   or 1/2 for levels 1, 2 and 3. The aim turns left by it and the path right
   by it (path_error falls), so the face stays where it was but the club
   swings across it: positive m is a pull-hook, negative a push-slice. In
   sand the aim is left alone.
5. On levels 2 and 3 a miss also costs 1 to |m| percent of power (a random
   draw, never the whole swing), and every swing has a little scatter: power
   moves up to 0.25 percent and the face up to 0.1 degree, either way.

Level 0 skips all of this.

**Mouse swing.** The swing brings its own face and path angles in degrees
and its loft multiplier; nothing above applies.

**The strike.** Unless the ball is on the tee, the contact then decides how
cleanly the ball comes off. With n = |c| (on level 1 n = |c| - 1 and on
level 0 n = |c| - 2, never below 0, and a factor k of 0.8 or 0.6, else 1):

- spin multiplier = LieAngular - k n LieAngularSnap, at least 0.25;
- speed multiplier = LiePower - k n LiePowerSnap (the mouse swing leaves out
  the LiePowerSnap term except in sand), at least 0.25, and no more than a
  quality limit q.

q is 1 on the green, 0.6 - 0.03 |c| in rough, 0.4 - 0.03 |c| in sand, 0.95 -
0.06 |c| on path, dirt, bushes and rocks, and 0.9 - 0.01 |c| plus up to
+/-0.005 of noise elsewhere (fairway, deep grass), never below 0.3. Only the
driver feels all of it: the 3-wood feels half, the two longest irons a fifth
and a twentieth, and every other club none. Levels 0, 1 and 2 soften q to
(q + 1) / 2, 0.8 q + 0.2 and 0.9 q + 0.1. So a driver off the fairway comes
off at about 90 percent of the speed it has off the tee, and from rough at 60
percent.

Sand then replaces both multipliers by the table above (the contact is
mirrored for a left-handed PowerStroke player), and both the face and path
errors are dropped. A ball on the tee skips the strike step; with PowerStroke
its power moves up to 1 percent and its aim up to 0.06 degree either way.

The random draws are the C runtime's rand(), in the order given. Ported as
`links_apply_swing` (olcore) and `LinksLaunch.apply_swing`, checked against
the game's code on 270 random swings across every class, club, level and
method.

### The PowerStroke meter

**Geometry and speed.** The three-click meter has 69 positions. A full
swing starts at the snap line, position 15, and climbs: position 54 is
full power and 55 to 67 are overswing. Chips and putts have their own
meters that start at the bottom (0) and run to 68. The marker moves one
position at a time; each step waits `n x 70 / (1.2 e)` of the game's 8 ms
frames (whole frames, the fraction carried to the next step), where `e`
eases between 70 and 42 on a 40-position cycle (70 at positions 15 and 55,
42 at 35; coming down the cycle is one position later) and `n` depends on
the meter and the position:

| Meter | Climbing: frames from position | Falling |
|-------|--------------------------------|---------|
| Full swing | 6 from 13, 5 from 17, 4 from 22, 3 from 28, 2 from 47, 1 from 63 | 1 |
| Chip | 5, then 4 from 20, 3 from 29, 2 from 45 | 2 |
| Putt (long and short) | 5, then 4 from 28, 3 from 38, 2 from 48 | 2 |

So a full backswing takes about 1.05 s to full power, 1.2 s to the top,
and the marker comes back down from the top to the bottom in about 0.55 s.
Once a chip or putt has its power, its steps keep the speed of the power
position, and a putt slows by half again within five positions of it.

**Clicks.** A power click below position 25 (16 for chips and putts) waits
until the marker gets there. A full swing's marker always runs on to the
top and back; a power click on the way down counts only in the overswing,
and with no power by position 48 on the way down the game sets it 12 below
the marker and snaps 3 below that. A chip or putt turns six positions
past its power click (at most 68). The snap click on the way down sets the
contact: a click while the marker is still above the power position snaps
6 below it (at it for chips and putts); a click above position 30 waits
until the marker comes down to 30, so the snap lands between 0 and 30, 15
either side of the line.

**Power.** A full swing gives `(p - 15) / 39` of the club's power rating
at position p, so 54 is 100 percent, and each overswing position adds
8/13 of a power point, 8 more at the top. The rating is the club's default
record: 112, 108, 106, 104, 102, 100 and 98 for the woods (clubs 0 to 6),
then 98, 96, 94, 92, 90, 88, 86, 84, 82 for the irons (7 to 15) and 80 for
the three wedges; the mouse swing's most power per club is the same list.
The game shell does the same (`LinksShotModel.club_rating`), and a computer
golfer's planned power is a share of it too, its forced-power penalty
counted against 100 percent of the club. Flat carries at power 100 and at
the rating, no wind, show what it does: driver 212 m to 242 m, 3 wood 209
to 227, 4 iron 192 to 176, 7 iron 158 to 139, pitching wedge 124 to 105,
sand wedge 109 to 93. The shell's club distances (`Club.total_m`, close to
the power-100 numbers) are scaled by rating / 100 for reach and the auto
club (`ShotModel.reach_scale`), which is within about 4 percent of the
real change. A
chip's power comes from its own table: 7 at the snap line, then 0.4 a
position, rising by 0.05 a position every nine positions (0.45, 0.5, ...
0.65), to 34.95 at the top. A long putt's table runs from 1.9 at the snap
line to 16.8 at the top and a short putt's from 1.0 to 7.4, both times 0.7.

The game shell's `SwingMeter` runs this meter (`LinksPowerStroke`, a
GDScript model of the game's meter object) and draws it at these
positions, the snap line 15 positions up; its accuracy is how far the snap
lands from the line, over 15 positions.

**Contact.** The meter turns where the third click lands into the contact. The game
measures the click in meter units past a perfect zone, clamps it at 25 units
either way, then

    t = int(x * steps / int(width * scale)),  c = int(int(0.2 t) / 2)

where width is the meter size (150, 192 or 238) and, for levels 0 to 3,
scale is 2, 1.5, 1.5 and 1.4 and steps 225, 180, 180 and 165. So the meter
gives at most one step either way: a full miss is c = +/-1, which the swing
model above magnifies. The levels also change how fast the meter runs.
Ported as `links_meter_contact`; the game shell maps an accuracy of +/-1 on
our meter to 25 units (late is a push-slice); the skill level is the
"Swing skill" setting (level 3, the hardest, by default). Computer golfers
skip this model, as in the game; they have their own.

### Chips

Chip is one of the game's shot types (with Draw, Straight, Fade, Flop,
Punch and Putt; Straight has Pick and Explode variants for sand). When the
game picks a club for the ball's position it picks the shot type too: the
putter on the green, otherwise a Chip if the ball is within 100 ft of the
hole (the straight-line distance to a point a foot above it) and not in
sand. The player can change it.

A chip launches like any other shot with the chosen club, but its power is
the chip meter's (or the mouse chip's) own, in the same units as a full
swing's (34.95 at most from the meter, 43.8 from the mouse). Its PowerStroke
miss is a full swing's except that the lost power is drawn and then not
taken off: the chip still pulls, pushes and scatters. A computer golfer's
chip misses by its chip rating.

The game shell picks chips by the same rule (`_auto_club`), shows "chip"
after the club, and swings them on the chip meter or as a mouse chip.

### Computer golfers' misses

A computer golfer plans a perfect shot (power, and zero face and path
error), then the game adds its misses. Each golfer has a steadiness rating
from 0 to 100 for each kind of shot: tee shots, and off the ground by club
group (driver and woods, clubs 0 to 6; 1 to 3 irons; 4 to 6; 7 to 9; the
three wedges), plus chips. It also has a most power per club. Where n is
100 minus the rating, two draws give

    line   = (rand % n + rand % n + n / 8) / 2
    length = (rand % n + rand % n + n / 8) / 2

(integer arithmetic, line first; n / 6 for the line of a tee shot; 0 when n
is 0). A plan with more power than the golfer has takes the excess, in whole
percent, off the rating for the line (twice over off the ground).

The direction miss is line / 2 and the power miss is length, both times the
lie's AngleMiss (or PowerMiss; the two are equal in every record) and then
times 1/8, so a rating of 80 misses by about 0.7 degrees and 1.4 percent of
power on a typical shot. The direction miss is capped at 10 (5 for a golfer
flagged steady) and added to or taken off either the face or the path, each
choice a coin flip. Off the tee both misses then grow by (rand % 100) / 100
(the game means a random sign but always adds, and draws an unused number
after each). A steady golfer's misses are then halved.

The power miss is taken off the power if the hole is more than 230 yards
away, and otherwise added or taken off on a coin flip. The direction miss
also costs half itself in power. A miss that would leave no power is backed
off: the step shrinks by 0.75 (0.4 for the direction's cost) and is added
back until the power is positive. The angles are taken as degrees, the
unit the game's mouse swing uses for its face and path.

Ported as `links_computer_miss` (olcore) and `LinksLaunch.computer_miss`,
checked against the game's code on 330 random cases and the C++ against our
reference on 20,000. The game shell uses it for a computer golfer's full
swings (putts keep OpponentSkill's own mistakes) and, without the golfers'
own files, gives every shot type the level's single rating from
`SkillProfile::links_rating` (40, 65, 85 and 95: our numbers), with the most
power at 100 percent.

Chips use the chip rating (the Chip shot type above). Not ported: one
other shot type, which goes to a separate routine; and a
routine that, from the second shot of a hole, scales both misses (from a
quarter up to eighteen times) and can change the club by how the golfer is
scoring on the hole against a target. Without it both scales are 1, as on a
tee shot.

### Putts

The putter (club 19, which has no row in the club table) has its own
launch:

- The face angle is `a = face error + (face setting - 30) + (stance
  setting - 30)` degrees and the path `b = path error + (stance setting -
  30)`. Unlike a full swing, the face error is added, so a positive one
  sends the ball right.
- The ball leaves flat along `(sin a, cos a, 0)` at `cos(a - b) x power x
  2.3436` ft/s, turned by the aim. Power is the putt's strength straight
  from the meter; there is no lie, loft or club table in it.
- Its spin is backspin exactly as fast as rolling would need
  (`speed x 2.2736` rev/s about the side axis), so a putt first skids, with
  the green's skid friction slowing it hard, and only then rolls.
- Both vectors are tilted onto the slope under the ball (about x by
  `atan2(n.y, n.z)`, then about y by `-atan2(n.x, n.z)`), and the ball
  starts on the ground, skidding, with its centre one radius over the
  slope (`R / n.z`), not in flight.

On a flat, moderate, normal-speed green a putt of power 4 goes about 4.5
ft, 10 about 28 ft and 25 about 112 ft. The game's own putt meters (see
"The PowerStroke meter") give at most 11.8 on the long scale and 5.2 on
the short one, and the mouse putt at most about 15.6, so in the game a putt
tops out at about 40 ft (meter) or 60 ft (mouse) on such a green; nothing
in the swing code reaches further. The game shell's meter keeps its own
linear scale, 25 at full, so long putts stay playable on our greens.

A PowerStroke miss on a putt only turns the face. The miss in steps is
worked out as for a full swing (times 6, 5 or 2 by skill, times the lie's
snap, scattered, clamped at 60) but with no overswing, then flipped in sign
and added to the face error as `(75 + rand % 25) / 100 x miss x (1/2,
1/1.9 or 2/3)` degrees. A late snap therefore pushes the putt right. No
power is lost (the game still draws the number it would use), there is no
scatter and no strike quality step. Skill 0 putts never miss.

Ported as `links_putt`, `links_putt_slope` and the putter branch of
`links_apply_swing` (olcore), with `BallState::on_ground` starting the
simulation on the ground; `LinksLaunch.putt` and `LinksShotModel` in the
game shell. Checked against the game's own routines: the launch on 25
random putts and the miss on every skill with several snaps.

### Computer golfers' putts

Putts go to a routine of their own, using two more ratings from the
golfer's definition: one for long putts and one for short ones. With D the
straight distance to the hole in feet and `ft = int(D)`:

- Under 2 ft (3.5 ft for a steady golfer) the putt is left alone.
- The rating is the short-putt one up to 3 ft. Between 3 and 15 ft it moves
  towards the long-putt one by a twelfth of the gap per foot past 3. From
  15 ft on it is the long-putt one for a steady golfer; otherwise it is the
  short one less 2 points per foot past 15, but never below the long one
  less 30 (and simply 10 when the long rating is 30 or under). The game
  does this sum in signed bytes, so it wraps on very long putts.
- At 6 ft and under the line miss is halved. A rating of 100 never misses
  past 6 ft and counts as 98 inside it.
- With n = 100 - rating, two pairs of draws below n give
  `line = (r%n + r%n) / 3 x 0.5` and `length = (r%n + r%n) / 3`.
- By distance: at 2 ft a rating over 60 leaves the putt alone, and
  otherwise line / 3 and length / 4; 3 to 6 ft, line x 0.4 and length x
  2/7; 7 ft and more, length x 0.5.
- From the fairway (fringe) both grow by 1.5 and from rough by 2.
- The line, divided by 30, turns the path (radians) either way. For a putt
  that only costs pace through `cos(face - path)`; the computer's line is
  only as good as its read.
- The length is divided by `max((100 - ft) / 3, 10)` (10 from 100 ft) and
  goes on the putt power: long three times in four, short otherwise. A
  short putt that would reach zero backs off by 0.75 a step.

A routine that scales a computer's misses by how it stands on the hole (see
above) also feeds this one; without it both scales are 1. Ported as
`links_computer_putt_miss` (olcore) and `LinksLaunch.computer_putt_miss`.
It agrees with the game's code in an emulator on 360 random cases, and the
C++ port with a reference on 50,000. The game shell gives both putt ratings
the golfer's level rating.

### The mouse swing

The PowerStroke mouse swing never looks at the mouse button or at a snap
line. It moves a club up and down a swing meter from the mouse's movement,
frame by frame, and the club strikes the ball when it comes back down to
the ball line. (An earlier port read the sideways drift below as the timing
of letting go of the button; that was wrong.)

**Input.** Each frame the game reads how far the cursor has moved from the
middle of the screen, in whole pixels, and puts it back. Down the screen
(towards the player) is the backswing. Its arithmetic assumes 60 frames a
second (16.6668 ms). Forward movement is ignored until the mouse has come
back. A frame with no movement is skipped; the third still frame in a row
counts, three frames long.

**The mouse's speed.** The pull or push of the last frame is the club's
driving speed. The game smooths it with the frame after: it caps it at 127
pixels a frame, eases out spikes (a speed that jumps past 110, or past 125
counting the acceleration, is held at 127 until the stroke settles, then
blended two thirds from the frame before) and, if the push suddenly falls
by more than 50 pixels a frame during the downswing, it takes 90 and grows
it by a fifth each frame until the mouse stops.

**The club.** On a full swing the club has momentum. Its speed `v` follows
`a = speed x r - 10 v` (with the sign turned once the mouse has turned),
so it chases the mouse with a tenth of a second's lag. `r` is 1.25 for
clubs 0 to 7, 1.15 for the rest, 0.75 for the putter, times 0.75 on a chip.
On a chip or putt the club follows the mouse directly (its step each frame
is `speed x r`), with a speed wobbled by up to 5%. The club's travel moves
the marker: one unit of travel is 800 x (backswing room) / 1000 meter
pixels going back and 800 x (meter height) / 640 coming down, so the meter
covers the same mouse travel at every size. In the top 65 pixels the
backswing slows to a quarter (0.3 on a chip or with an iron) and less
again near the top.
The club starts counting once its speed passes 0.2; before the downswing it
cannot move backwards. When its speed changes sign, the backswing becomes
the downswing (the reading at that moment, 0 to 1, is how far back the club
went). If it turns again before reaching the ball, the swing goes back to
being a backswing.

**Drift.** Once the club is moving, the sideways movement adds up:
`drift += -dx x s`, held within 50, with `s` 0.02 on the easiest level,
0.03 on the next two and 0.05 on the hardest (0.04, 0.06 and 0.06 for
putts).

**The meter.** It is 278, 355 or 442 pixels tall on screens narrower than
1024, narrower than 1280, or wider, with the ball line 75, 96 or 119 up
from its bottom and the top of the backswing 10 below its end. Its reading
is how far the club is from the ball line to the top, in percent; a putt
shows `(2 + p) p / 3` of it instead.

**The strike.** The club's speed is the mean of its last two speeds (the
last three for chips and putts). A full swing whose speed would give more
than 120% of the club's power rating is pulled back to 120% (90% after a
sudden stop), wobbled. The ratings are the default club records' (112 for
the driver down to 80 for the wedges). Then, with `x = -drift`, `f` the
backswing and the stroke's angle `path = atan2((drift - drift two frames
earlier) x k, push)` (k = 1, 1.3, 1.7 or 2 by level, at most 20 degrees):

- *Full swing.* The speed is capped at `r x 8.4`. Power = speed x the
  club's gain (10.5 for the driver and woods down to 8.4 for the wedge)
  x `2f' - f'^2` with `f' = min(f + 0.05, 1)`, so a three-quarter backswing
  loses little. A drift within 10 pulls or pushes (path + x, face + 2x/3);
  from 10 to 18 the face turns by `0.1 x |x|` (hook or slice); past 18 the
  club misses. On the easiest level x is held within 17, so it never misses.
- *Putt.* The backswing asks for a speed `1 + 2.5 f`, give or take
  `w = 0.5 - c f` (c = 0.3, 0.33, 0.36, 0.4 by level). Faster adds up to
  `w / 15`; within the window the power scales from `1 - w/15` by a sixth
  per unit; slower falls off in proportion. Power = `(f + 2) f / 3 x 14.6`
  times that, wobbled 5%. The face is the stroke's angle times 0.5, 0.55,
  0.6 or 0.65; past 18 of drift the putt misses.
- *Chip.* The backswing asks for `(cap - 1) f + 0.1` give or take 0.2;
  slower falls off in proportion. Power = `(f + 1) f / 2 x 14.6 x 3`.

- *Irons and wedges* (clubs 7 to 18; the game marks them in its club
  records). The full swing's own drift rule above is skipped. Instead,
  for full swings and chips alike, the stroke's angle is scaled by
  `2.16 - 0.16 (club - 7)` (2.16 for the 1 iron down to 0.4 for the lob
  wedge) and the drift only turns the face: by `0.05 x |x|` within 10;
  beyond that by `0.1 x |x|` for a leftward drift of 13 to 16 and by `3x`
  otherwise, and past 18 the club misses. They lose power for the drift
  as below, and the drift is halved before the straightness bonus.

Full swings, putts and iron chips lose `|1 - x / 120|` of their power for
the drift (`/ 80` on the two harder levels). Power stays within 1 and 145. Face and
path are wobbled by up to 5% (`j = (rand % 100 + 1) x 0.0005`, then `x (1 + j)`
or `x - j x` as one of two further draws is below the other). A straight
stroke then earns a bonus: with `n = |4x / 5| + |round(2 path) / 2|` (whole
numbers, at most 15), power is multiplied by `1 + (15 - n)^2 / K` with
K = 4500, 3000, 2250, 2250 by level: up to 5% more on the easiest level and
10% on the hardest. Only the woods earn it: irons, wedges and the putter
keep 1. Last, the path is eased to two thirds, a putter's face turns the
other way, and on the two easier levels a full swing's face and path are
cut to 40% (50% with an iron).

**Swing help.** An option in the game. With it on, the game counts each
player's strokes and those with no sideways movement at all. Once there
have been three or more strokes and more than three quarters were dead
straight, every stroke that connects (above the easiest level) has its path
nudged by `r = (rand % 100 - 50) / 10` degrees, moved out to at least 2
either way (so 2 to 5 degrees, left or right), before the bonus is worked
out. It seems meant to stop a mouse held perfectly straight from beating
the swing. Ported as `LinksMouseHelp` (olcore) and `LinksMouse.Help`; the
shell's "Swing help" setting turns it on, off by default. The face and path then go through the lie and strike
model above (`links_apply_swing` with the mouse method).

Ported as `LinksMouseClub` and `links_mouse_swing` (olcore,
`links_mouse.cpp`) and `LinksMouse` (GDScript). A reference written from
the game's code agreed with the game's own routines run in an emulator on
1500 random strokes (every frame's club position and state, then the power,
face, path, loft and bonus), and the C++ port agrees with that reference
on 3000 more. A second run fed the C++ port and the game's routines (with
each club's own kind, the post-processing and the swing help) the same
2000 strokes, 90 of them misses and 169 nudged: they agree on all but 4,
where the quality lands one step apart from float rounding at a boundary.
(An earlier port read the iron rule as a "Real Time" mode; it is the
club's kind.) The game shell's `MouseSwingControl` captures the mouse,
feeds the screen-pixel movement to 60 frames a second and draws the meter
the game's size for the window's width, at the same share (about 46%) of
the screen's height.

The game also works out a loft multiplier, `(f + 0.05) x power / (the most
power that backswing could give)` (for putts and chips the speed share
times f), and a second number for the shot that is 1 except on hooks
(falling to 0 at a drift of 28) and any leftward drift (rising); where the
shot uses them is not traced yet, so the shell leaves the club's loft alone.

### Not ported

- A flag from the caller that adds 10 degrees of loft and removes all spin;
  what sets it is not known yet.
- How the PowerStroke meter's snap position becomes the contact's units
  (the shell maps 15 positions to a full miss) and whether the level
  changes the meter's speed (the step tables do not depend on it).
- The mouse swing's golfer animation that holds the club at the ball until
  the golfer is ready, and where its loft multiplier goes.
- The Draw, Fade, Flop, Punch, Pick and Explode shot types (the game picks
  Pick or Explode in sand by distance) and the short-putt shot type; the
  shell plays full swings, chips and putts. A game option that doubles
  every PowerStroke miss is left out.
- Per-course lie values for the strike: the launch still takes the class
  defaults above (the bounce and roll use the course's own records).

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

### Out of bounds and hazards

Out of bounds is not a ground type. Each hole has an outline in the
course's `HoleIDShapes`, and some courses add out-of-bounds areas in
`OBIDShapes` (see [crz.md](crz.md#shapes-area-outlines)). The game asks
whether a position is within the hole's bounds when the shot is over, so a
ball that bounces out and back in is in play; olcore and the game judge it
where the ball stops (`Terrain::in_bounds`). Ground beyond the edge of the
course mesh still counts as out of bounds at once.

A hazard is a `TerrainTypes` record with bit 0 of its flags set: water,
running water and a few others such as mud. Drops are refused there, as on
water. Bit 3 marks free-drop ground (cart paths, concrete, asphalt, walls).

### The cup

The cup's radius R is set at launch from one of the launch routine's
arguments: 0.1875 ft (a 4.5 inch hole), 0.17708 ft (4.25 inches, the
regulation size) or 0.29167 ft (7 inches), then multiplied by the hole size
option (1 normally). The game's "is it in the hole" test answers 2 when the
ball's centre is within R − 0.07 ft of the pin horizontally (well inside),
1 within R + 0.0007 ft (over the hole), and 0 otherwise.

The game models the hole as a circle of radius R round the pin's base: a
rim edge at the green's level that the ball (radius 0.07 ft) can roll on,
and a cup below it. In the cup the ball has four modes of its own, and the
game runs them in sub-steps of 1/1200 s (20 a frame, counted down in single
precision). Positions below are relative to the pin's base.

- **Getting in.** On a green, after the ground step's checkpoint, a ball
  whose path crosses the circle is moved to the crossing (position by the
  fraction of the path, velocity and spin by the matching fraction of time)
  and starts rolling on the rim. A ball coming down from the air whose
  contact point is within R + 0.0007 ft does not bounce: it falls into the
  hole's air and plays the rest of its step there.
- **On the rim.** The edge holds the ball against it: it is pulled round
  the edge by gravity's component along the axis that tips it over, its
  velocity into the edge is cancelled, and it is put back 0.07 ft from the
  edge along the line from the edge to its centre, with spin to match its
  rolling. The earliest of three events ends the sub-step: rolling back out
  past R + 0.0007 ft (it rolls on, on the green), coming away from the edge
  because the edge would have to pull it to keep it there (found by
  halving the sub-step until the step is under 1/4096; it falls into the
  hole's air), or its centre dropping below the green's level (it slides
  down the wall).
- **In the hole's air.** Gravity alone. Events: touching the edge (it is
  placed against it; slower than 0.2 ft/s into the edge it rolls on the
  rim, faster it bounces off with half its speed into the edge), rising
  above 0.071 ft (back into normal flight, set on the green), or dropping
  below the green's level (it falls into the cup).
- **On the wall.** It keeps only its speed round the circle and falls,
  held on the circle.
- **Falling in the cup.** Gravity alone; reaching the circle it is put on
  it and either slides down the wall (slower than 0.2 ft/s into it) or
  bounces off it with 0.3 of that speed.

In every mode, once the centre is 1 ft below the green the ball is holed.
After an event the rest of the sub-step is played through the normal step
again (unless under 5% of it is left). Steps can nest this way, and the
game caps them at five deep; past that it sets a ball near the hole down
just outside it (olcore puts it at 1.06 R and stops it).

**The flagstick** is a pole of radius 1/24 ft (half an inch) on the pin.
The launch takes it out when the shot is struck from the hole's green (or
when its caller asks; that case is not identified). Otherwise, while
flying, rolling or in the hole's air, the first time the ball's centre
crosses the pole's circle anywhere from 0.5 ft below the pin's base to 8 ft
above it, the ball is moved to the crossing and sent off with its velocity
mirrored about the line from the pole's axis, times 0.3, and 0.09 of its
spin. It can only be hit once a shot.

olcore (`links_step` with a `LinksCup`) and the GDScript port follow all of
this, and match the game's code step for step in an emulator on putts that
drop, lip out round the rim, hit the flagstick or miss, and on balls
dropped into the hole's air.

### Trees and other objects

After each step (in flight, on the ground and in the hole's air) the game
checks the ball's path from its old centre to its new one against the
objects near it, then against the flagstick, and acts on the first hit.

Billboards (trees, bushes, grasses, rocks and other pictures) are flat
pictures standing on the ground and turned to face the viewer: the game
uses its view direction, so the picture's plane is upright and square to
it. olcore turns them to face back along the shot. A billboard is `height`
tall and `height * aspect` wide; the placement's two `2DPlant` extra fields
anchor it (see [course-objects.md](course-objects.md)), so it spans from
`anchor_x` of its width left of its base to the rest on the right, and from
`anchor_z` of its height below its base to the rest above.

- **Candidates.** Only a billboard whose plane the path crosses is tried,
  and not the one hit last (one shot can't hit the same object twice in a
  row).
- **Where.** The path is cut with the plane. Off the picture's rectangle
  there is no hit. Otherwise u (across, from its left edge) and v (up, from
  its bottom) are the fractions of the picture at that point, and the
  game looks at that pixel of the largest picture: a transparent pixel is
  no hit.
- **Solid or canopy.** Each type has the Course Designer library's
  `collision` value and six `shape` values (the course repeats them in
  its `MasterObj` types). Unless bit 1 of `collision` is set, the hit is
  solid when (u, v) is inside the rectangle `shape[2..5]` (u0, v0, u1, v1;
  a tree's trunk) or, one time in ten, anywhere else (the game decides by
  whether the bit pattern of v as a float divides by 10). Otherwise the
  canopy catches the ball when `shape[1] * 10` is more than the bit
  pattern of u modulo 10 (signed), so `shape[1]` is about the chance it
  does.
- **Solid hit.** The ball is moved to the hit, then 0.1 ft back along its
  path, keeps its spin, and its velocity (as at the end of the step) is
  mirrored off the picture's plane and scaled by the type's `shape[0]` when
  bit 0 of `collision` is set (solid objects: rocks, benches), else by 0.5
  (trees). Off a tree the plane's normal is first turned about the
  vertical by up to 60 degrees either way: by (where the hit is across the
  opaque run of pixels in that row, from 0 to 1, minus 0.5) times 2 pi / 3.
- **Canopy.** The ball stays where it met the picture and its velocity and
  spin are scaled by `(alpha / 255 * (1 - shape[0]) + shape[0]) * 0.9`.

Kauri's types: 78 trees (`collision` 0, e.g. shape 0.7, 0.92 and a trunk
rectangle), 39 solid objects (1; 0.8 to 0.91, 1, then the whole picture)
and 64 that only slow the ball (2; grasses and flowers, 0.91, 1).

olcore (`LinksObjects`, given to `links_step` or `ShotOptions::links_objects`)
and the GDScript port follow this. The game reads the full-size picture;
the Godot course loader keeps a copy reduced to 128 pixels on its longest
side, which moves the edges of the opaque parts by up to a few percent.

### 3D objects

Walls, bridges, buildings and other meshes are tested in the same pass as
billboards, as the ray from the step's start towards its end, reaching as
far as the end.

- **Candidates.** The ray must meet the object's placed bounding box
  (nearer than the end of the step). A 3D object is never skipped as the
  one hit last.
- **Faces.** Each face is cut into a fan of triangles from its first
  corner, and each triangle is met from one side only: a triangle seen from
  behind (its corners turning clockwise), or one the ray runs along, is no
  hit. The nearest hit across all faces wins.
- **See-through textures.** When the face's texture is marked see-through
  (see [course-objects.md](course-objects.md)) the game finds the texel at
  the hit and lets the ball through where its alpha is zero. It blends the
  texture coordinates of the mesh's first corner and the triangle's two
  other corners as numbered in the whole mesh (not in the face), a quirk we
  keep. The coordinates wrap round the picture.
- **Fast hit.** If the ball meets the face at 2 ft/s or more along its
  normal, its velocity (as at the end of the step) is mirrored off the face
  and scaled by 0.7. Its position and spin are those of the step at the
  point where it met the face.
- **Slow hit.** Otherwise the ball goes on to the object: its velocity is
  scaled by 0.7 and loses its part along the normal, and it sits 0.07 ft
  (its radius) off the face. Its mode is "on an object".
- **On an object.** The ground step runs as for rolling, but with the
  object's own surface (class 0; restitution 0.27, impact friction and skid
  friction 0.13, impact drag 0.44, roll resistance 0.2, stop speed 5, no
  spin grip, no lie effect) and the object's normal under the ball, found by
  a ray straight down from 5 ft above it. If the object is not above the
  terrain there, or no object is found under the ball's next spot, the
  ball flies off. If the height under the next spot differs from the
  ball's by more than about 0.32 ft (squared difference over 0.1), the game
  looks along the ball's path, both ways, from halfway between the two
  heights: a face within 2 ft of the next spot is a wall, and the ball
  bounces off it (velocity mirrored, no loss); otherwise it is a step it
  can't climb, and the ball stops where it is.

olcore (`LinksObjects::add_model`, `hit_model`) and the GDScript port follow
this; the course loader passes each placed mesh in.

### Not ported

- Hole size options other than 1 (the game uses a different cup routine).
- Where the ball is when it flies off an object: the game flies on from the
  step's end in a way that is hard to follow; olcore flies the step again
  from its start.
- Tournament-only 3D objects (kind 6): the game drops them outside
  tournaments; we always keep them, and all 3D objects are tested against
  the whole step.

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
