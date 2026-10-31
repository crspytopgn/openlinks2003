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
khaki clothes; the bag is built in code (`GolfBag`, one mesh, three
materials).

Code: `game/scripts/caddie/` (`Caddie`, `CaddieAdvice`, `CaddieNote`,
`GolfBag`).

## Golf buggy

Still to come: drive a buggy between shots (faster on cart paths, kept off
greens, tees, bunkers and water), with a key to skip straight to the ball.
