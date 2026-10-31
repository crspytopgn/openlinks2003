# Green reading and putting practice in Links 2003

Status: partial (behaviour from the game's own manual and dialog text; no
code or numbers decoded)
Seen in: `HELP.LS` (the in-game help, `MAIN.TXT` inside), `PRACTT.DLL`
(the Practice dialog), setting names in `LinksMMIII.exe`

This is what the original offers for reading greens and practising putts,
summarised in our own words, and how OpenLinks2003 matches it. Nothing
here is copied from the game; the help text can be read with
`tools/lsarchive/lsarchive.py extract HELP.LS <dir>`.

## The aids, by skill level

The player's skill level decides which aids are there:

| Skill | Putting Assistant | Green Analyzer | Grid |
|-------|-------------------|----------------|------|
| Amateur | full | yes | yes |
| Professional | partial | yes | yes |
| Championship | no | yes | yes |
| Elite | no | no | no |

At Elite the aiming marker can also only be moved in the main view.
`GreenRead.assistant_level`, `grid_allowed` and `analyzer_allowed` follow
this table, with our skill levels 0 to 3 standing for Amateur to Elite.

### Grid

A grid laid over the green while putting. The player picks it in the
player settings; Alt+G toggles it during play and Ctrl+G swaps between a
plain yellow grid and a coloured one. The executable's setting names
include "Color Grid By Height", "Hori Grid" and "Vert Grid", so the colours
show height, and the grid's line counts are settings of their own. The
spacing and colours aren't decoded.

Ours (`GreenGrid`): Settings > Putting grid picks Yellow, Coloured by height
(blue low, red high, scaled to the grid's own lowest and highest point), or
the TV grid coloured by steepness with downhill ticks. G and Ctrl+G work as
in the game. Lines are a metre apart (our choice).

### Breakline Indicator

An option in the player settings: a yellow line at the foot of the aiming
marker as it moves over the green. It points the way the ground falls, and
its height shows how steep it is. Ours: `BreaklineIndicator`, at every skill
level, with our own sizes.

### Putting Assistant

An option in the player settings for Amateur and Professional players.

- Amateur: the right line for the putt is drawn while aiming, and with the
  Classic (three-click) swing a red dot on the meter marks the right power.
  With the Real Time swing a mark on the swing's status bar shows how far to
  take the club back.
- Professional: a wider area round the line instead, so the putt still has
  to be judged.

Ours: the line is the computer golfers' own putt plan run through the
round's physics (`PuttRead.read`), drawn exactly at Amateur and as a band
widening with distance at Professional (`PuttRead.show_band`; the band's
width is our guess). The red dot is on our meter (`SwingMeter.target`); the
mouse swing's backswing mark isn't done.

### Green Analyzer

A viewing mode from the Display menu: a camera that moves freely round the
current hole's green (only the green is drawn), looking at the pin, the
ball or the aiming marker, with a height slider, a pivot mode that orbits
between two of those, and the grid on demand.

Ours: the read views (V, or the Read the green button). Crouched behind the
ball, from behind the hole, and from the low side are what golfers do on a
real green and are there at every level. The overhead view stands in for
the Green Analyzer and, like it, isn't there at Elite. A free orbit camera
isn't done.

### Other information

The info panel shows the slope under the ball (an arrow along the dotted
lines for side and up or down slopes) and the rise from the ball to the
marker and the pin. Ours shows the slope at the ball against the line to
the hole in the putting panel, and the rise in the shot panel as before.

The game's green speed and firmness options are in already
(`LinksGround.green_for`). We also give the speed as a stimpmeter reading:
how far a ball leaving the ramp at 6 ft/s rolls on the flat with the game's
own rolling resistance, frame by frame (`GreenRead.stimp`). That comes to
about 4 ft (soft, slow) to 7.5 ft (firm, fast), 5.3 ft for medium and
normal: slower than most real greens (8 to 11 at clubs, 12 or more on
tour). The physics is the game's, so it isn't changed.

## Practice

The Practice screen picks a course (or the driving range), the holes and
the conditions, and one of four practice options: Play Through, Driving
Only, Chipping Only and Putting Only. During practice the Shot Options menu
adds New Position (the ball moves to another random spot), Next Hole and
Practice Options, and drops cost no penalty. Auto-Mulligan keeps the ball
at the same spot for the next try, after a pause of 1 to 3 seconds. With
"Enforce Normal Drop Rules" off, the ball can be dragged to a new spot.

Ours: Play > Putting practice on the round setup page
(`PuttingPractice`). Each chosen hole's green becomes a practice green, as
at a club: up to six cups cut on the flatter parts (the hole's own pin
first), each with a short stick, the one being putted to with a yellow
pennant. Free putting keeps the ball at its spot (Auto-Mulligan) until N
moves it; the distance and the kind of slope (uphill, downhill, left to
right, right to left) can be set. Two practice-green drills are added:
Around the clock (six balls in a ring 3 ft out, start again on a miss) and
a lag ladder (20 to 50 ft, scoring each putt that finishes within 3 ft).

## Open questions

- The grid's spacing, colours and line counts, and the assistant's band
  width.
- How the Green Analyzer's camera moves.
- Whether the breakline indicator is limited by skill level (the help
  doesn't say so).
