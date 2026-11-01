# Caddie and golf buggy

Two optional extras that Links 2003 doesn't have. Both are off by default,
so a round plays exactly as the original unless the player turns them on.

## Caddie

Settings > Caddie. At each of the players' shots (never a computer
golfer's) a caddie stands off to the side with the bag, and a card above the
controls line gives their read:

> 153 to the pin, playing 160 uphill. 7 Iron. Start it 5 yards left for the wind.

> 13 feet, uphill. Breaks left to right, start it 6" left of the hole. Be firm with it.

The read comes from the tour-level computer golfer's plan (`ComputerGolfer`),
run through the round's own physics, wind and course, so it agrees with how
the ball will actually fly and roll. "Plays like" uses a caddie's rules of
thumb: a yard per yard of rise, one per cent per mph into the wind and half
that helping (`CaddieAdvice.plays_like_m`).

How much the caddie says follows Settings > Swing skill, so the caddie
doesn't make the hard levels easy:

| Swing skill | The caddie says |
| --- | --- |
| Levels 1 and 2 | Yardage, plays-like, club and how hard, the line in yards; the putt's break to the inch and the pace |
| Level 3 | The same, but only which side to favour, and the break in words ("a touch", "a fair bit", "a lot") |
| Level 4 (Links 2003's hardest) | Yardage, plays-like and club; on the green the slope and which way it breaks |

Planning is spread over frames (3 ms a frame), so the browser build doesn't
stall. The figure is the free MakeHuman golfer (CC0) in a standing pose with
white overalls of a tournament caddie; the bag is built in code (`GolfBag`, one mesh, three
materials).

Code: `game/scripts/caddie/` (`Caddie`, `CaddieAdvice`, `CaddieNote`,
`GolfBag`).

## Golf buggy

Settings > Golf buggy. When a person's next ball is more than 40 m from the
buggy, they drive to it: Up/Down or W/S to drive and brake (and back up),
Left/Right or A/D to steer. A yellow ring marks the ball and the controls
line counts the yards. Stop within about 14 m (40 m if the ball is on the
green) and play goes on. **Space or a click skips the drive** and leaves the
buggy parked beside the ball, so a round with the buggy on is no slower
than without it. Computer golfers never drive, and on a new hole the buggy
waits beside the tee.

While driving, the golfer sits at the wheel (the free golfer, posed seated
from its rest positions, hands on the wheel), and the swing meter, shot
info and wind panels hide until the drive ends.

Handling (`BuggyDrive`) is a planar rigid-body vehicle model stepped at
120 Hz, with the published figures of a current two-seat electric fleet
cart (448 kg kerb weight, 1.635 m wheelbase, 3.3 kW 48 V AC motor, 24 km/h):

- 530 kg with the golfer aboard, 300 kg m^2 of yaw inertia, the centre of
  gravity behind the middle (the batteries) and 0.55 m up.
- Rear drive: 1500 N at the wheels from a stand, then the motor's 3.3 kW,
  and a governor at 15 mph (5.5 mph in reverse) that also
  regenerates to hold the speed downhill. Pedals take a moment to press,
  and the automatic park brake holds it, even on a hill, once the pedals
  are up and it has stopped.
- Tyres with 9000 N/rad of cornering stiffness per axle, saturating
  smoothly at the grip of the ground (0.85 on cart paths, 0.62 on grass,
  0.55 in the rough, 0.45 in deep rough), inside a friction circle per
  axle, so it understeers, wheelspins and slides. The steering ratio
  slows at speed, as a game pad or keyboard needs.
- Weight moves back under acceleration and forward under braking, which
  changes the grip at each axle.
- Brakes on the rear wheels only (the real cart has self-adjusting rear
  drums), so it stops at about 0.3 g, in 8 m from full speed on grass,
  and the rear can slide if you stamp on it on wet-feeling turf.
- Rolling resistance by ground (0.015 on paths, 0.045 on grass, 0.14 in the
  rough, 0.22 in deep rough), air drag, and gravity along and across the
  slope.

What comes out of that, checked in the tests: about 15 mph on grass and
paths (0 to 13 mph in 4 to 5 s), 10 mph in the rough, 6.5 mph in deep
rough, 8.5 mph up a 15% hill, held at the governor coming down, half a g of
cornering grip, and a stop from full speed in about 2.2 s.

Sound (`BuggySound`) is made in code as looping clips whose pitch and
volume follow the cart, so it works on the web build too: the AC motor's
whine rising with speed (silent at a standstill, as electric carts are),
tyre noise that hisses on paths and rumbles in the rough, and the clack of
the automatic park brake letting go and setting. The body lags the ground
over crests and dips before its springs settle it, and small bumps in the
turf jiggle it, more in the rough and at speed.

It stops at the edge of greens, bunkers and water, as real course rules
ask.

The cart is our own model (CC0), built by `tools/buggy/build_golf_cart.py`
into `game/assets/buggy/golf_cart.glb`. It follows the published
dimensions and the general shape of a current two-seat fleet cart, without
any maker's names or badges: 2.38 m long, 1.20 m wide, 1.765 m to the sun
top, a 1.635 m wheelbase, 0.89 m front and 0.98 m rear track, a 295 mm
floorboard and 18x8.5-8 tyres on 8 inch steel rims. The golfer is about
1.77 m tall and the ball and hole are the Rules of Golf sizes;
`_test_real_scale` checks all of these. The moulded body panels, seat and
sun top are signed distance shapes drawn from side, plan and front outlines
with rounded edges and cut wheel arches, meshed by marching cubes and
simplified (`tools/buggy/sdf.py`), with ambient occlusion baked into the
vertex colours so it looks solid without any extra cost at run time. The
paint is a slate blue-grey metallic, with beige seats and sun top, black
sills, bumpers and dash, a folding windscreen, round front struts and
square rear posts. If the file is missing, a simple box cart built in code
stands in. The body squats, dives and leans on its springs (a damped spring
per axis, about 1.3 Hz). It sits on the ground under its four wheels,
pitching and rolling with the slopes, and a chase camera follows it.

Code: `game/scripts/buggy/` (`BuggyDrive`, `GolfBuggy`).
