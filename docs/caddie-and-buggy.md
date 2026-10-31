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

Handling (`BuggyDrive`): a governed electric cart, about 16 mph on cart
paths, 14 mph on grass, 9 mph in the rough and slower in deep rough, 5.5 mph
in reverse. Steering is a kinematic bicycle model (1.65 m wheelbase, 32
degrees of lock, less of it at speed), hills slow it going up and push it
going down, and it stops at the edge of greens, bunkers and water, as real
course rules ask. The model (`GolfBuggy`) is built in code: a glossy white
two-seater with a canopy, tinted windscreen, bench seat, headlights and a
bag on the back, one mesh for the body (six materials) and four wheels that
turn and steer. It sits on the ground under its four wheels, pitching and
rolling with the slopes, and a chase camera follows it.

Code: `game/scripts/buggy/` (`BuggyDrive`, `GolfBuggy`).
