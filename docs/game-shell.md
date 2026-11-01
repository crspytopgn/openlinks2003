# Game shell

The playable round in `game/`: hole flow, the swing meter, ball physics,
scoring, and the interfaces that decoded original data plugs into. Until the
decoders land, everything runs on placeholders, so the game is playable in
the browser and on desktop today.

## Playing

| Input | Action |
| --- | --- |
| Left / Right | Aim (hold Shift for fine aim) |
| Up / Down | Change club (the game picks one for you each shot) |
| Q / E | Shape the shot: draw or fade, one degree at a time (up to 6) |
| W / S | Hit it higher or lower: the ball one step forward or back (up to 3) |
| Space or left click | Swing meter: start, set power, set accuracy |
| Space or left click | Skip the ball flight, continue after a shot |
| Tab | Show or hide the scorecard |
| F1 | Broadcast and Tour: bring back the key hints, folded away from the second hole |
| Esc | Menu: resume, scorecard, settings (quality, fullscreen, v-sync, anti-aliasing, 3D resolution, field of view), restart, main menu |
| M | Back to the main menu once the round is over |
| F11 | Toggle fullscreen |
| U | Mulligan, right after a shot (Settings > Mulligans) |
| C | Open the course viewer (courses made by `olcourse export`) |

### Click to aim

Right-click on the course while aiming to aim at that spot (`ClickAim`: a
ray from the camera to the ground). Away from the green the round also takes
the shortest club whose full swing reaches it, as in modern sims; chips and
putts only turn the aim. A click on the sky does nothing. Left-click stays
the swing.

### Touch screens and game pads

On a phone or tablet (the web build) buttons on the left aim (held), change
club and open the menu. A swipe anywhere else is the mouse swing: put a
finger down, drag it back down the screen (40% of the screen's height is a
full deflection), then flick it up, briskly and straight. Lifting the finger
before the downswing calls the swing off. A tap starts the swing meter, and
later taps click it.

On a game pad the left stick or D-pad left and right aim (LB for fine aim),
D-pad up and down change club, A is the swing meter (and continues), Back
shows the scorecard and Start opens the menu. The right stick is the mouse
swing: pull it back, then push it forward. B calls it off before the
downswing; the next swing waits for the stick to come back to rest.

Both feed Links 2003's own mouse swing (`LinksMouse`) through `AnalogSwing`
(`ui/analog_swing.gd`), which reads the stick or finger as a position and
hands the swing the mouse movement it would have made, so the club's
momentum, the power from speed through the ball and the hook, slice and
miss rules are the original's. A full deflection is 650 mouse pixels for a
full swing (about 85% on the meter, where the mouse also slows into the top)
and 1000 / the club's response for chips and putts, which follow the mouse
directly, so all the way back fills the meter and half way is half. A brisk
flick (about 0.1 to 0.2 s) hits a driver near the club's best; a slower push
hits softer. These sizes are our own choice, tuned with scripted swings
against `libs/olcore/src/links_mouse.cpp`. Sideways movement scales the same
way: at the hardest skill a stick kept within about a third of the way off
straight stays inside the hook and slice line.

The swing meter is the classic three-click Links arc. Click once to start the
backswing; the marker climbs the left side of the arc towards 100% at the
top. Click again to set power; the marker runs back down. Click a third time
as it crosses the white snap line at the bottom. Early (above the line) pulls
and hooks the ball left, late pushes and slices it right.

The yellow ring shows where a full swing would land (for putts, the hole
distance). Holes run tee to cup, then on to the next. Out of bounds is
stroke and distance. A hole is picked up at 10 strokes.

Shot shaping uses Links 2003's own shot setup (ball position, club face and
stance, `LinksLaunch.Setup`) through `ShotShape`: a fade turns the stance,
and so the swing path, left of the target and the face back square to it,
so the ball starts on line and curves right; a draw is the reverse. Moving
the ball forward launches it higher with more spin, back lower with less.
The shape resets to square each shot and is kept in the shot record, so
replays and result codes play it back. With the game's executable the
game's own launch does the rest; the stand-in physics starts the ball 75%
along the face and adds 160 rpm of sidespin per degree of face to path, and
1 degree of launch and 5% of backspin per ball step. The limits (6 degrees,
3 steps) are ours: the game's setup screen limits are not read yet.

### Mulligans

Settings > Mulligans (off by default): one per player per nine holes, or
one per hole. Right after a shot, while its result shows, U takes it again
from the same spot as if it never happened: the strokes, penalties and that
hole's stats go back. The shot stays in the round's record marked
`"mulligan": true`, and the replay checker leaves it off the card. Not on a
holed shot, in a friend's round, the shared-ball team modes or practice.

### Launch monitors

Settings > Launch monitor (desktop builds; a browser can't listen on a
port): the game listens on TCP port 921 for the open "GSPro Connect" v1
protocol that most home launch monitors and their connector apps speak
(`OpenConnect`, `OpenConnectServer`). Point the app at this computer's
address and port 921. Each shot message's ball data (speed in mph, vertical
and horizontal launch angles, total spin and spin axis, or back and side
spin) becomes the launch of the person's next shot, played through the
current shot model with the wind, bounce and roll as usual; rough and sand
take off speed and spin as they do for a swing. Each message is answered
with code 200, and the app is told which club is up (code 201, `"Club":
"DR"`, `"7I"`, `"PT"`). HLA and spin axis are taken as positive to the
right. Shots are recorded as measured (`ShotRecord.monitor`), so replays
play them back and online play can tell them apart.

### Gimmes

Settings > Gimmes (off by default, as in Links 2003): a ball that stops on
the green inside 2, 3 or 4 feet of the hole is conceded for one stroke and
counted as a putt. The conceded stroke is kept with the round's drops
(`"gimme": true`, penalty 1), so the replay checker adds it to the card.
Never in a friend's round from a result code, nor in a scramble, whose best
ball is picked only after everyone has played.

### Pick up

Settings > Pick up ends a hole for a player who reaches double par or
triple bogey without holing out (never more than the usual 10), to keep
casual rounds moving. The card keeps the strokes played. Off in a friend's
round, so the result codes compare.

### Interface size

Settings > Interface size scales the menus and HUD (the window's content
scale: 0.85, 1, 1.15 or 1.3 on top of the usual stretch), larger for phones
and TVs, smaller for a big monitor up close.

### Colours

Settings > Colours swaps the swing meter's green and red (good and bad
marks, the fill past the snap point) for blue and white, which stay apart
for red-green colour blindness (`SwingMeter.colour_safe`).

### Captions

Settings > Captions shows what the golfer says (their voice bank's event
name in brackets, such as "[Golfer: Great Shot]", not the words spoken) and
the crowd's reactions ("[The crowd roars]") above the hints
(`SoundCaptions`). The Broadcast commentary is already on-screen text.

### Hole positions

Links 2003 courses keep 18 hole positions for each hole, in three groups of
six (`HoleData.pins`, [crz.md](formats/crz.md)). Round setup > Pins plays
the usual one (the first) or a random one per hole, picked from the round
seed (`RoundSetup.pick_pin`), so a friend's round from a result code and a
resumed round play the same positions. What the three groups stand for
(days of a tournament, or difficulty) isn't known yet, so the choice is
over all of them. Courses with one position (the placeholder and designed
courses) keep it.

### Practice range

Round setup > Play > Driving range plays the built-in practice ground's
range (`scripts/practice/practice_ground.gd`, `PracticeGround`), laid out
from photos of real club and tour ranges: a 80 m grass tee line with
hitting stations, each with a 55-ball pyramid and blue tee-line markers, a
rope on stakes behind and old divots along the line; a striped field
110 m wide with range balls lying out on it; and flagged target greens at
50, 75, 100, 125, 150, 175, 200 and 250 yards, staggered left and right,
each with a yardage board facing the tee (`RangeDressing`; all the balls
are one MultiMesh). Auto-aim picks the furthest target the club reaches.

Play > Range target game is the same range with a bucket of 20 balls
(`RangeGame`): a ball that lands or finishes on a target green scores its
points (10 at 50 yards up to 50 at 250), double inside the bullseye (35 %
of the radius round the flag), and the last two balls score double. The
launch monitor panel keeps the score and the session's best bucket.

Play > Practice putting green is the practice ground's big rolling green
(about 38 m across, up to 2 to 3 % of slope) with the putting practice
below. Play > Putting on this course's greens and Hitting from this
course's tees are the earlier ways, on the chosen course.

Hitting from this course's tees: one person hits from the tee of the
chosen course as often as they like. The ball comes back after each shot,
nothing is scored or saved, and N and B move to the next or previous hole
for other targets. A launch monitor (`LaunchMonitor`, `LaunchMonitorPanel`)
shows each shot's ball speed, launch angle, back and side spin (from the
launch the shot model made, `ShotResult.launch`), carry, total, offline,
apex and descent angle, and the session's average carry, total and
left-right spread with that club. With the game's files on the `.RNG`
driving range course this is the range Links 2003 has.

### Drops

Water costs a stroke and a drop. **D** while aiming declares the ball
unplayable (one stroke; not on the tee or the green), and on a cart path
**F** takes a free drop. The drop menu lists the options (keys 1 to 3), the
ball sits on the default spot, a white ring marks the zone, and the arrow
keys move the ball inside it (Up: towards the pin, Shift: fine, Page Down:
back 10 m). Space or a click drops; Backspace cancels a voluntary drop.
Computer golfers, and a player who just confirms, take the legal drop that
leaves the shortest way to the pin.

| Reason | Penalty | Options |
| --- | --- | --- |
| Water | 1 | Back on the line from the pin through where the ball last crossed into the water; within two club lengths of that point; replay from the last spot |
| Unplayable | 1 | Back on the line from the pin through the ball; within two club lengths of the ball; replay from the last spot. In a bunker the drop stays in the sand |
| Cart path | 0 | Within a club length of the nearest point off the path |

A drop may never be nearer the pin than its reference point, in water, out
of bounds or on the green. This is what Links 2003 enforces (its drop menu,
the free drop on paths, and the "you cannot drop..." refusals); the zone
shapes come from the Rules of Golf (rules 16, 17 and 19), since how Links
draws its own drop corridor isn't known. Courses don't mark water as yellow
or red, so every water hazard offers lateral relief (`LATERAL_WATER` in
`main.gd`). Not done: Links actually drops the ball and lets it roll (and
re-drops when it rolls out of the zone); here it is placed. Links 2003 has
no lost balls, and out of bounds is known at once, so there are no
provisional balls. The rules are `olcore/rules.cpp`, ported to
`game/scripts/rules/drop_rules.gd`.

## Menus and game modes

Once the game files are ready, the boot screen is the main menu: **Play a
round**, the game-file buttons, **Settings** and **Quit** (desktop). Play a
round opens the setup page (`ui/round_setup_panel.gd`): course, tees (back,
middle, forward; courses with one tee box play from it whatever is chosen),
holes (all, front nine, back nine), game mode and one to four players with
names. The choice is a `RoundSetup`, saved under `[round]` in
`user://settings.cfg` with the last course, and handed to the round through
`GolfRound.setup`.

Players share the round in turn (hot seat). On each hole everyone tees off
in order of the honour (the lowest score on the last hole goes first; ties
keep their order), then whoever is furthest from the hole plays. The other
balls stay on the ground where they lie. When the next swing is a different
person's from the last one, the screen dims and names who plays next, with
the hole, shot and distance (`ui/hand_over_panel.gd`); Space, Enter or a
click carries on, and Tab still shows the scorecard. Computer golfers'
turns skip it, so one person against the computer never sees it. Online
play is still a design: [online-play.md](online-play.md). The modes:

| Mode | Players | Scoring |
| --- | --- | --- |
| Stroke play | 1 to 4 | Lowest total |
| Match play | 2 | Hole by hole; ends once the leader can't be caught ("3 & 2") |
| Skins | 2 to 4 | One skin a hole for the outright lowest score; ties carry over |
| Best ball | 3 or 4, two teams | Each team counts its best score per hole |
| Stableford | 1 to 4 | 2 points for par, one more per stroke under, one fewer per stroke over |
| Scramble | 2 to 4, two teams | Everyone on the team hits; the team plays on from the best shot, one stroke per round of shots |
| Alternate shot | 2 to 4, two teams | One ball per team; partners take turns hitting it and take turns on the tee |

In scramble and alternate shot each team plays one ball (its first member's;
the partners' own balls sit out), and every member's card carries the team's
score, so the team rows of the scorecard show it. In a scramble the team
plays on from the shot that leaves the fewest expected strokes
(`OpponentSkill.expected_strokes`), so a person doesn't have to pick; a holed
shot ends the hole at once. Alternate shot counts swings, not penalty
strokes, when deciding whose turn it is. Team rounds don't go on the players'
handicap records. With handicaps, each team gets one handicap from its
players' indexes, low first, as the WHS recommends: alternate shot 50% of the
combined index, a scramble 35/15% for two players (25/20/15/10% for four),
played off the low. A scramble shot into the water is dropped at the
rules' best spot before the team compares its shots. Computer golfers play
both, taking their turns like anyone else.

`GameModes` (`game_modes.gd`) does the scoring and mirrors the game-mode
functions in `libs/olcore/src/scoring.cpp`. `RoundScoring` holds everyone's
cards and turns them into the HUD status line, the end-of-hole result and the
final standings. The scorecard shows a row per player plus the mode's rows
(points, skin winners, match holes, team best balls).

### Computer opponents

Any seat can be a computer golfer instead of a person ("Who" on the setup
page), so one person can play a match, skins or best ball against the
computer, or watch four computer golfers play. A computer golfer plays through
exactly the same physics as everyone else:

1. **Plan** (`ai/computer_golfer.gd`, `ComputerGolfer`). It tries clubs, aims
   and power through the round's own `ShotModel`, on the real hole, with the
   wind of that shot. Full shots aim at the pin when it is in range (with the
   power to get there) or down the hole's route, then correct twice for wind
   and curve. Putts aim at the hole, paced to finish 35 cm past, and read the
   green from where each try stops (up to eight tries). Where a try ends is
   scored by the strokes still to play from there (`expected_strokes`, rounded
   from published tour "strokes gained" baselines), with a stroke added for
   water and stroke and distance for out of bounds. Golfers with course
   management re-try their three best plans pulled and hooked, pushed and
   sliced, long and short, and take the best average, so they play away from
   water and bunkers. The weekend golfer just goes for the best-looking shot.
2. **Swing** (`ai/opponent_skill.gd`, `OpponentSkill`, ported from
   `libs/olcore/src/opponent.cpp`). The plan becomes swing-meter inputs, and
   the golfer's mistakes go on those inputs, never on the ball: power, timing
   (hook and slice) and line-up errors for each kind of shot (drive,
   approach, chip, putt), the odd duff or top, and a strength cap on how hard
   it can swing.

#### Calibrated to real numbers

A computer golfer is described by the numbers tour statistics use
(`GolferStats`): average drive, fairways hit, average distance from the hole
after an approach from 150 yards and after a chip from 20 yards, eight-footers
holed, and mishits. `golfer_profile` turns them into swing errors with tables
measured through the physics on flat ground by `tools/olcalibrate` (run it
with no argument for the standard physics, or with a Links 2003 executable to
add the game's physics; the exe is only read). So a golfer with the PGA
Tour's averages hits the PGA Tour's averages, and the C++ test
`opponent_matches_tour_numbers` keeps it that way:

| Level | Drive | Fairways | From 150 yd | Chip from 20 yd | 8 ft putts | Duffs |
| --- | --- | --- | --- | --- | --- | --- |
| Weekend golfer (about 18 handicap) | 220 yd | 45% | 60 ft | 14 ft | 33% | 6% |
| Club golfer (about 9) | 245 yd | 50% | 44 ft | 10 ft | 40% | 2.5% |
| Scratch golfer | 270 yd | 56% | 33 ft | 7.8 ft | 45% | 0.8% |
| Tour pro (the tour average) | 300 yd | 60% | 27 ft | 6.5 ft | 50% | 0.2% |

The tour column is the PGA Tour's ShotLink averages (about 2015 to 2024); the
amateurs are rounded from Broadie's *Every Shot Counts* and Arccos amateur
data. Measured with `olcalibrate`, the tour pro hits 59% of 30-yard fairways,
finishes 27.6 ft from 150 yards, 6.5 ft from a 20-yard chip, and holes 94%
from 3 ft, 50% from 8 ft and 18% from 20 ft (Broadie's tour make rates are
96%, 50% and 15%). A golfer swings at the power that drives the ball its
average drive with the standard physics. A full swing there goes about 290
yards, so the tour pro drives 285 and the weekend golfer 211.

With the Links 2003 physics a timing error turns the face (4.5 degrees at full
error) and each kind of error is scaled (`links_error_scale`) so the same
golfer hits the same numbers. Settings > Computer golfers > Classic Links
uses the game's own computer miss generators instead
(`LinksLaunch.computer_miss` and `computer_putt_miss`, see
[physics.md](formats/physics.md#computer-golfers-misses)), with each
golfer's ratings set from its numbers (`GolferProfile::links`). The game's own
putting holes everything inside 5 ft, so Classic golfers putt better than
real ones.

#### Who they are

Every computer golfer is a `TourPro` (`ai/tour_pro.gd`): its numbers plus a
style.

- **Shape**: a planned draw or fade (a timing offset); the planner aims for
  it, so a fader starts it left and lets it come back.
- **Aggression**: how far past the cup it paces putts (20 to 55 cm), how much
  it weighs its likely misses against the shot it means to hit, and whether
  it also looks at a line halfway to the middle of the green (where the
  hole's pin positions average out).
- **Course management**: how many of its best plans it re-tries with its own
  likely misses (none to four).
- **Nerve**: over the last three holes, when within two of the lead (in the
  group, or of a tournament's live leaderboard), a nervy golfer's errors grow
  by up to 30% and a clutch one's shrink.
- **Form**: each round starts with a form factor (wider for a streaky
  golfer), and birdies and bogeys move a short-term momentum.
- **Routine**: its pre-shot routine in real seconds (20 to 50 on tour), played
  quicker in the game: a fast player is over the ball and away while a slow
  one is still reading the shot.

Sixteen named pros (`TourPro.ROSTER`, ten men and six women) have numbers of
their own (Marcus Bell: 318 yards, 52% fairways; Kenji Morita: short, dead
straight and the best putter on tour; Mateo Ibarra: a superb ball-striker
whose putting goes under pressure). Their looks come from `GolferRoster` by
name. A "Tour pro" seat named after one of them plays as that pro. Plain
level seats get the level's numbers with a style of their own, drawn from the
round seed. Tournament and career field golfers are made up by
`TourPro.generate`: numbers around their level, longer hitters finding fewer
fairways, and their own style. `TourPro.scoring_average` turns any golfer's
numbers into a scoring average with rounded strokes-gained values (20 yards
of driving is about 0.75 a round, a foot closer from 150 yards about 0.2, a
point of eight-footers about 0.1).

Planning runs as small jobs over a few frames (about 6 ms of work a frame),
so the browser build doesn't stall. The computer "thinks" and then stands over
the ball for its own routine (about 1.2 to 3.5 s in all), then swings; a
click hurries it up. When every seat is a computer, holes move on by themselves after 4 s.
Seeded rounds (`GolfRound.wind_seed`) seed the computer golfers too, so the
tests play the same way every run.
### Handicaps and player profiles

Every finished round of nine holes or more goes on the player's profile,
matched by name (`PlayerProfiles`, saved in `user://profiles.cfg`; the
browser keeps it in IndexedDB). After three rounds the profile gives a
handicap index; until then the player can type a starting index on the setup
page ("12.3", or "+1.4" for a plus handicap). Rounds that stop early, such as
a match won 3 & 2, don't count.

The index follows the World Handicap System, simplified because Links
courses have a stroke index per hole but no course or slope rating: par
stands in for the course rating and every course has the standard slope.

- Each hole is capped at net double bogey (par + 2 + strokes received; par + 5
  without an index) to give the adjusted gross score.
- Score differential = adjusted gross - par, doubled for a nine.
- Index = the lowest 1 to 8 of the most recent 20 differentials, averaged,
  with the WHS adjustment of up to -2.0 for three to six rounds. Between +10.0
  and 54.0.

With "Handicaps: On" in the round setup, each player's playing handicap is
their index scaled to the holes played at the mode's allowance: 95% for
stroke play and Stableford, 100% for match play and skins, 90% for best
ball. Match play, skins and best ball play off the lowest handicap. Strokes
go on the hardest holes first, by the course's stroke index (a nine keeps
the order of the 18). Net scores then decide every mode, and the scorecard
adds a net row under each player, whose label shows their playing handicap.

Computer golfers keep no profile and play off a fixed index for their level
(`RoundSetup.computer_index`): weekend golfer 24.0, club golfer 12.0,
scratch golfer 0.0, tour pro +4.0. The setup page shows it in the player's
index box, so net and Stableford games against them work.

Each round also counts every player's fairways hit (tee shots on par 4s and
5s that finish on the fairway), greens in regulation (on the green, or in
the hole, with two strokes to spare for par) and putts (strokes played from
the green). They go on the round's record and into career totals that keep
counting after old rounds drop off the list.

The main menu's **Players** page (`PlayersPanel`) lists every profile with
its index, rounds and last date. Picking a player shows their career line
(scoring average per 18, fairways, greens in regulation, putts per 18) and
their recent rounds with each round's stats, and stars the rounds the index
counts. Delete asks once more, then removes
the profile.

Each profile also keeps personal records (`PlayerProfiles.records`): the
best score per course and round length, the longest drive (a driver from
the tee that stays in play), and counts of birdies, eagles and holes in
one. The players page shows them under the career line.

### Player creator

**New player** and each player's **Golfer** button on the Players page open
the player creator (`ui/player_creator.gd`, `PlayerCreator`): a live 3D
preview (`ui/golfer_preview.gd`; drag to turn, whole body, face close-up or
a swing) and tabs for

- **Body:** male to female, height (150 to 205 cm), build, muscle, age,
  skin tone (eight presets or any colour) and eye colour;
- **Face:** sixteen shape sliders (face width and length, cheeks,
  cheekbones, jaw, chin, nose width, length and bridge, eye size and
  spacing, brows, mouth, lips, ears);
- **Photo:** the face, skin and hair colour from a photo of the player
  (see below);
- **Hair:** seven styles or bald, any colour;
- **Clothes:** polo and trousers, long sleeves and trousers, or polo and
  shorts, with shirt, trousers, shoe and cap colours;
- **Equipment:** driver head, shaft finish, grips and ball colour (looks
  only; the clubs play as before).

The look (`player_look.gd`, `PlayerLook`) is saved with the player's
profile (`PlayerProfiles.set_look`, under `look` in `user://profiles.cfg`),
so it travels with their rounds, handicap and stats, and a renamed player
keeps it. A round finds each person's golfer by the name entered at setup.
Every player gets their own golfer on the tee and their own ball colour;
players without a look use the standard golfer. Without the original game
files, computer golfers get a look of their own, the same every time
(`PlayerLook.random` seeded by their name). With the game files, people who
made a golfer play as it and everyone else uses the original golfer.

How it is built: `FreeGolfer` takes its skeleton, clubs and animations from
`free_golfer.glb`, and its body, outfits and hair from the look pack
`assets/golfer/free_golfer_parts.olg` (`assets/golfer_parts.gd`,
`GolferParts`), which `tools/golfer/build_free_golfer.py` writes with
MakeHuman's own macro and face targets as blend shapes. For a look it bakes
each visible part once on the CPU (about 10 ms; meshes are cached), moves
the joints to the new shape, and scales the golfer about the ball for the
height. The GPU then draws plain skinned meshes with no blend shapes, the
same cost as the standard golfer, in both renderers. Colours multiply the
pack's grey detail textures, so any colour costs nothing extra.

#### Face from a photo

The Photo tab (`ui/face_from_photo.gd`, `FaceFromPhoto`) fits the face
sliders to a photo of the player. The photo stays on the device: it is
scaled down, held only while the creator is open, and never uploaded or
saved.

- **Web:** **Choose a photo** or **Take a selfie** (the front camera on
  phones). MediaPipe's Face Landmarker finds the face in the browser
  (`web/face_photo.js` through `scripts/web/web_face_photo.gd`). Its code
  and model (Apache-2.0, about 4 MB) are fetched from jsDelivr and Google's
  model storage the first time; they are not part of the build. The points
  can then be dragged.
- **Desktop:** **Choose a photo** opens a file dialog and the player taps
  20 points (eye corners, brows, nose, mouth, chin and the face's edges),
  prompted one at a time; scroll zooms and right-drag pans. There is no
  face finder on desktop yet: MediaPipe has no build Godot can load without
  a GDExtension, and running a model in GDScript would be slow.

`PlayerFaceFit` (`player_face_fit.gd`) turns the points into twelve
measurements that don't depend on the photo's size, position or tilt (eye
width and gap, brow height, nose length and width, mouth width and drop,
lip height, chin length, three face widths). The same 20 points on the
golfer's head, with how every body and face shape moves them, are in the
look pack's `face_fit` header (`tools/golfer/face_landmarks.py` finds them
on the MakeHuman mesh). A regularised Gauss-Newton fit (about 15 ms) then
sets the sliders a photo can show: face width and fullness, nose width and
length, eye size and spacing, brows and mouth width. The player's body
(sex, build, age) is kept, and so are the sliders a front view can't show
(jaw, chin, cheekbones, lips, nose bridge, ears, face length). Skin and hair
colours are the median of patches on the cheeks and forehead and above
it, divided by the detail textures' mean.

MediaPipe leans towards an average face, so a photo's measurements are
mapped back with a per-measurement offset and gain, and weighted by how
well MediaPipe follows each one. `tools/golfer/face_calibration.sh` measures
these on 48 renders of golfers with random faces, and picks the sliders
worth fitting. On the renders held out, the fitted sliders end up about
half as far from the truth as leaving them in the middle.

### Career

The main menu's **Career** page (`CareerPanel`, logic in `Career`,
`game/scripts/career/career.gd`, saved in `user://career.cfg`) runs seasons
of tour events against a field of computer golfers. A new career picks the
player (their profile, by name), the tour to start on, 4, 8 or 12 events a
season, 4-round events with a cut, 2 rounds or 1, full rounds or the front
nine, and whether two, one or no computer golfers play in the person's
group. Fewer partners and shorter events keep it quick on slow computers.

| Tour | Field | Field average (per 18, to par) | Cut | Purse | Moves |
|------|-------|-------------------------------|-----|-------|-------|
| Regional | 59 + you | 0 to +9 | top 30 and ties | $60,000 | top 5 move up |
| Challenge | 95 + you | -3 to +3.5 | top 50 and ties | $400,000 | top 5 move up |
| World | 131 + you | -3.5 to +1.5 | top 65 and ties | $8,000,000 | outside the top 100 drop down |

- **Schedule**: the season's events cycle through the player's courses (the
  same list as the setup page, including designed courses), shuffled. The
  middle event is a "Masters" at 1.5 times the purse; the last is the tour's
  Championship at twice the purse.
- **Rounds**: the person plays every round as stroke play from the tour's
  tees (middle on the Regional Tour, back otherwise), with up to two field
  golfers as computer partners (`Career.partner_level` maps their average
  to a computer level). Partners are drawn at random before the cut, then
  the golfers next to the person on the leaderboard. The round is tied to
  the career by `RoundSetup.career` (kept with a saved round), so a round
  counts once and a resumed round still counts.
- **The rest of the field** is simulated when the person's round is in:
  each golfer's average scaled to the holes played, plus a "day" offset
  shared by everyone (wind, pins) and their own spread. The partners' real
  cards replace their simulated rounds.
- **Cut and money**: four-round events cut after round two. Places are paid
  from a table close to the big tours' published shares (18% to the
  winner), normalised so the places down to the cut add up to the purse;
  everyone who makes the cut is paid, and ties split the places they fill.
  A tie for the win goes to a sudden-death playoff (simulated, from each
  golfer's average). Events without a cut pay down to the cut's number of
  places. A missed cut or a withdrawal plays the event out without the
  person.
- **Season end**: the money list decides who moves up a tour, and on the
  World Tour who keeps their card. The page then starts the next season.

The page shows the season line (money list place and earnings), the career
line (events, wins, top 10s, cuts, earnings, scoring average per 18), the
handicap index and personal records from the player's profile, the event
leaderboard, the money list and the schedule with results. In a career
round the ticker shows the event and the leaderboard before the round;
when the round ends the result is added and Space goes back to the Career
page. The rounds also go on the player's profile like any other round.


### Tournaments

Main menu > Tournament hosts an event of the person's own
(`tournament/tournament.gd`, `Tournament`, kept in `user://tournament.cfg`;
`ui/tournament_panel.gd` is the page):

- **Format**: stroke play, Stableford, a knockout match play draw (8 to 64,
  seeded by ability, 1 v 16 and so on) or a skins game (the person and three
  named pros; holes 1 to 6 are worth one share, 7 to 12 two, 13 to 18 three,
  ties carry, and anything left at the end goes to a playoff).
- **Courses**: one per round, from the person's courses.
- **Field**: men, women or mixed; 12 to 156 players; club amateurs, regional,
  challenge or world tour, or a major championship (the top two include the
  named pros).
- **Cut** after round 2 of 3 or 4 (top 65, 50 or 70 and ties), **purse**
  (paid by the tour shares Career uses), **weather** (calm to stormy, or
  changeable round to round, which sets the round's wind) and **tee times**
  (a morning or afternoon wave, or the tour draw: two waves and two tees on
  the first two days, then the leaders go out last).

The person plays every round for real with up to three field golfers, who
play as themselves (`RoundSetup.pros`). Everyone else is simulated hole by
hole: each golfer's expected score on a hole is the tour average for its par
plus their scoring average, the day (pins and firmness), the wind (worse
golfers lose more to it), their wave and their form. The odds of each score
(`HOLE_ODDS`, rounded from tour scoring: about 11% birdies on par 3s, 15% on
par 4s, 38% on par 5s) are tilted to that expectation, which keeps real shapes:
better golfers make more birdies and fewer bogeys, weak ones more doubles. A
tour-average golfer's simulated rounds average 0.6 under par 72 with a
round-to-round spread of about 2.8 strokes.

Field golfers start before and after the person's group (groups 10 minutes
apart, about 0.7 holes), so while the person plays, the live leaderboard
moves: the Tour presentation's rail shows the top five and the person's
group with the holes each has played, the Broadcast ticker shows the board,
and birdies and eagles near the top become captions ("Birdie at the 7th:
Callum Reid -6, T2"). A level match after 18 holes, and a tie for a
tournament, go to a simulated sudden-death playoff for now.

### Saved rounds

The round in progress is saved before every shot and at the end of each hole
(`SavedRound`, `user://saved_round.cfg`): the setup, everyone's card, the
hole, the honour, whose turn it is and where each ball lies. After quitting
(or closing the game, or the browser tab), the main menu offers **Resume
round** while the saved round's course is among the player's files, and the
round carries on from that shot. The wind is drawn again. Finishing the round
clears the save, and starting a new round replaces it.

`Handicap` (`handicap.gd`) mirrors the handicap functions in
`libs/olcore/src/scoring.cpp`; indexes and differentials are in tenths of a
stroke so both sides round the same way.

## Code map

```
game/scripts/
  boot.gd                       Game files, main menu and round setup
  player_face_fit.gd            PlayerFaceFit: face sliders and colours from a photo's face points
  main.gd                       GolfRound: the round state machine, turns, camera, HUD wiring
  scorecard.gd                  Scorecard (mirrors olcore/scoring)
  game_modes.gd                 GameModes: match, skins, best ball, Stableford (mirrors olcore/scoring)
  round_setup.gd                RoundSetup: course, tees, holes, mode and players for a round
  round_scoring.gd              RoundScoring: everyone's cards read in the chosen mode
  career/
    career.gd                   Career: tours, schedule, simulated field, cut, prize money, money list
  ai/
    computer_golfer.gd          ComputerGolfer: plans a computer opponent's shots through the ShotModel
    opponent_skill.gd           OpponentSkill: skill levels and swing mistakes (port of olcore/opponent)
  round_scoring.gd              RoundScoring: everyone's cards read in the chosen mode, gross or net
  handicap.gd                   Handicap: strokes per hole, net scores, the index (mirrors olcore/scoring)
  player_profiles.gd            PlayerProfiles: each player's rounds, handicap index and golfer
  player_look.gd                PlayerLook: a player's golfer from the player creator
  saved_round.gd                SavedRound: the round in progress, for Resume round
  physics/
    shot_model.gd               ShotModel: the physics interface the round uses
    standard_shot_model.gd      StandardShotModel: the stand-in model below
    links_shot_model.gd         LinksShotModel: the stand-in with the game's own flight, bounce and roll
    links_aero.gd               LinksAero: that flight model (port of olcore/links_flight)
    links_ground.gd             LinksGround: its bounce and roll (port of olcore/links_ground)
    wind.gd                     Wind: conditions for the round, hole and shot
    ball_physics.gd             BallPhysics: GDScript port of olcore ball_physics + shot
    swing.gd, club.gd           Swing-meter-to-launch mapping and the club table
    surface.gd                  Surface types and per-surface constants
    obstacle_field.gd           ObstacleField: trunks, canopies and walls (port of olcore/obstacles)
    ball_state.gd, shot_result.gd, flat_terrain.gd
  course/
    course_loader.gd            CourseLoader: interface for the .CRZ decoder
    course_data.gd, hole_data.gd, placed_object.gd
    course_terrain.gd           CourseTerrain: height, surface and mesh for a hole
    course_objects.gd           CourseObjects: a .CRZ's plants, 3D objects and spectators,
                                drawn per hole and turned into obstacles
    placeholder_*.gd            The procedural nine-hole stand-in course
  assets/
    asset_providers.gd          AssetProviders: where real decoders get registered
    object_library.gd           ObjectLibrary: interface for OBJECT.LIB and friends
    golfer_assets.gd, golfer_rig.gd   interfaces for the golfer model and animation
    sound_bank.gd               SoundBank: interface for game audio
    free_golfer.gd              FreeGolfer: the CC0 MakeHuman golfer, dressed and shaped by a PlayerLook
    golfer_parts.gd             GolferParts: its body, outfits and hair (assets/golfer/free_golfer_parts.olg)
    placeholder_*.gd            Primitive trees, a hand-animated figure golfer
  ui/
    swing_meter.gd, hud.gd, scorecard_panel.gd, wind_indicator.gd
    mouse_swing.gd, analog_swing.gd, touch_pad.gd   the mouse swing, and touch and stick input for it
    hud_art.gd, info_bar.gd, shot_panel.gd, shot_windows.gd   the original interface (below)
    round_setup_panel.gd, players_panel.gd, career_panel.gd, pause_menu.gd, settings_panel.gd, menu_style.gd
    player_creator.gd, golfer_preview.gd   PlayerCreator: the player creator and its 3D preview
    face_from_photo.gd            FaceFromPhoto: the creator's Photo tab (photo, face points, fit)
    hand_over_panel.gd          HandOverPanel: the hot-seat "pass the controls" screen
  designer/                     The course designer (docs/course-designer.md)
game/tests/run_tests.gd         Headless tests, including an auto-played full round
```

## Game files and the boot screen

`scenes/boot.tscn` is the first scene. On desktop it asks once for the
player's Links 2003 folder (saved as `[game] folder` in `user://settings.cfg`)
and offers the courses found in it. In the browser, `WebGameFiles`
(`game/scripts/web/`) drives `game/web/game_files.js`: the player picks disc
images or a folder, the script walks the ISO 9660 tracks itself (cooked,
raw or raw-plus-subchannel sectors, as `tools/cdimage/cdimage.py` does, and
scans for the volume when the pregap is unusual, so BlindWrite .b6t and
other descriptor files aren't needed) and indexes the GAME files under
Setup's long names without copying anything. Reads come straight from the
picked images. Where the File System Access API exists (Chrome, Edge), the
file handles and index are kept in IndexedDB so the next visit only needs the
player's OK. `WebGameFiles.copy_startup_files()` copies the few files read
before a round (`startup_files()`: object catalog, sound effects, course key,
standard ground textures, one golfer, plus the objects standing in for the
placeholder trees) into the in-memory filesystem at `/tmp/links2003`, which
becomes `GameFolder.override_path`. Courses (about 100 MB each) are copied
only when chosen. `node game/web/tests/test_game_files.mjs` tests the script against
synthetic disc images made by `game/web/tests/make_test_iso.py`.

The chosen course path is passed to the round through
`GolfRound.chosen_course`; any `CourseLoader` registered with `AssetProviders`
that accepts the path loads it.

## Graphics

`Scenery` (`game/scripts/graphics/scenery.gd`) owns the sky, sun, fog and
post-processing; `GraphicsSettings` holds the quality options and saves them
to `user://settings.cfg` under `[graphics]`. Shadows (cascade count, distance,
atlas size, softness), glow, SSAO and SSIL follow the quality level. The
screen-space effects only run on Forward+; the web build (Compatibility)
starts at Medium with FXAA.

The public build looks better with free photographic art: CI runs
`tools/fetch_free_assets.py`, which downloads CC0 ground textures (grass,
rough, sand; 1K albedo and normal maps) and a 2K HDR sky from
[Poly Haven](https://polyhaven.com) into `game/free_assets/`. They aren't
committed. `FreeAssets` loads them, `Materials.terrain()` blends them by the
rough and sand weights in the mesh's UV2 (`Materials.terrain_weights()`), and
`Scenery` uses the sky as a panorama. Without them the game falls back to the
procedural sky and shading. `game/free_assets/CREDITS.md` names the assets
used. Run the script once locally to see the same look on desktop.

Course meshes should use `Materials.terrain()` (vertex colour for the surface,
plus noise variation and close-up detail) and `Materials.water_disc()` for
ponds, so decoded courses match the placeholder. CI renders real frames with
Mesa on both renderers (`game/tests/render_check.gd`) to catch shader errors,
and uploads the screenshots as the `render-check` artifact.

## The original interface

With the player's own `GRAPHICS.LS`, the Classic Links presentation draws
its interface from the game's art (`HudArt` in `game/scripts/ui/hud_art.gd`
loads it; without the file the HUD keeps its plain look):

- Top left, one chrome info bar per line of shot information
  (`CRSINFO.TGA`, `InfoBar`), lettered in the game's font (`SPBT14.D3F`,
  [d3f.md](formats/d3f.md)).
- Bottom centre, the classic swing bar (`RIND12.TGA`, `SwingMeter`).
- Bottom left (`ShotPanel`), the PowerStroke title bar and the row for the
  club's kind (`PSTROKE1.TGA`), the club's name and reach in a stone window
  (`LIEBOX.TGA`), and under them the swing indicator gizmo with the club at
  the ball (`SIGRDR12`, `SIGRIR12`, `SIGRPT12.TGA` for woods, irons and the
  putter).
- Top right (`ShotWindows`), the wind window with the game's arrow
  (`WINDDIR.TGA`) turned to the wind, the elevation window with the
  `ELEV00` to `ELEV12` picture for the aim point's height above the ball,
  and the lie window with the lie and how much distance it allows.

What's measured and what's guessed: the pieces' rectangles in their sheets
are measured from the sheets' alpha, and the fonts and their metrics come
straight from the files. Where the game places each piece on screen, the
feet per elevation picture (5 here) and what the red-ringed gizmo variants
(`SIRD*`), the `HV*` and `EZ*` sheets, `SISYMB*` (shot-shape arrows and
tempo lights) and the `SI*.SHR` sprites are for aren't in the files; a
screenshot of the running game would settle them. `CLUBICNS.TGA` is loaded
but not placed yet.

## Broadcast presentation

Settings > Presentation switches between **Classic Links**, which frames
and dresses the round like Links 2003, and **Broadcast** (the default),
which presents it like a TV golf broadcast. Only the presentation changes:
the physics, the swing and the scoring are the same in both.

- `scripts/broadcast/shot_director.gd`: the camera director. It plans the
  cuts for each shot (behind the player, then a chase or side-on camera,
  then a landing camera or a camera behind the green looking back at the
  ball) and `RoundCamera` follows it. Putts get a low tracking camera.
- `RoundCamera.start_flyover()`: each hole opens with a flight from behind
  the tee, along the hole's route, down to the green. A click skips it.
- `scripts/broadcast/ball_tracer.gd`: the shot tracer, a camera-facing
  ribbon with a soft halo, a hot core and a flare at the ball, widened
  across the camera's view so it stays solid where the ball flies at the
  lens.
- `scripts/ui/glass.gd`, `glass_theme.gd`, `frosted_glass.gd`: the glass
  look of the menus and HUD, our own take on the translucent "liquid glass"
  of current phone and TV interfaces: rounded panels whose picture behind
  is bent at the edges and blurred, with a lit rim; pill buttons; Inter type
  (SIL Open Font License, `assets/fonts`); panels that spring open. The live
  blur runs only on Forward+ at Medium quality and up; the web build and Low
  quality draw the same shapes as plain tinted glass, with no extra pass.
- From the second hole the key hints fold away to a small "F1: controls";
  F1 brings them back.
- Replays: R between shots (and automatically after a holed approach, a
  long holed putt or a shot to tap-in range) plays the shot again from new
  camera angles, in slow motion round the landing and the cup.
- `scripts/broadcast/green_grid.gd`: on the green, a grid draped over the
  real terrain, coloured by slope, with downhill ticks. G hides it. It
  shows the slopes, not the putt's line.
- `scripts/broadcast/broadcast_overlay.gd`: the TV graphics, drawn from
  plain shapes: the score bug, the shot panel, a lower third as each player
  steps up, the shot card (carry, roll, total, height, lie, to the pin), the
  hole card with a map (`hole_map.gd`), the LIVE and REPLAY bugs, camera
  tags, captions, the scrolling ticker (the leaderboard with more than one
  player), wipes, and a pin-camera picture on approach shots (Medium quality
  and up, since it draws the scene twice).
- `scripts/broadcast/commentary.gd`: caption lines and the crowd reaction
  for each shot. The crowd sounds are `crowd_cheer`, `crowd_roar`,
  `crowd_groan` and `crowd_ooh` (the tournament bank with the game files,
  recorded crowds from `FreeSoundBank` without them).

### Tour

A third choice, **Tour**, is Broadcast with a modern tour graphics package
in our own look (`scripts/broadcast/tour_graphics.gd`). It is off by
default. It replaces the score bug, shot panel, hole card, lower third and
ticker with:

- a leaderboard rail down the left: holes to play, every player's place
  and score, and the player on the shot with a hole strip (the hole, its
  length, and which shot of par this is);
- a shot-data bar: a wind dial, the club, and a range line from the ball to
  the pin with the club's carry-to-total window. It also shows the expected
  score for the hole from here (`OpponentSkill.expected_strokes`);
- on par 4 and 5 tee shots, a driving zone drawn on the ground
  (`driving_zone.gd`): miss left, fairway and miss right, each with its
  chance and expected score. The chances assume start lines spread around
  the aim by `DrivingZone.SPREAD_DEG` for the swing skill, which is our
  guess and not Links data;
- on the green, the putt read (`putt_read.gd`): the computer golfers' putt
  plan run through the round's physics, drawn as an aim line, the ball's
  path and an aim target, with the distance, slope and aim in a panel;
- a tall hole map down the right (`HoleMap.build`) with a dot where every
  shot on the hole finished, coloured by player;
- a wider teal tracer.

Golfer voice lines (`scripts/audio/golfer_voice.gd`) play at impact, in
flight and on landing as well as after the ball stops. The timing is our
best guess. In the browser, the disc's crowd, menu and voice sounds are a
setting (Settings > Sounds, about 100 MB copied into memory, used from the
next start) and the light placeholder sounds play otherwise.

In every presentation, scene changes fade through black and menu panels fade
in (`scripts/ui/scene_fade.gd`).

## Putting practice and green reading

Links 2003's own green-reading aids and practice options are written up in
[formats/green-reading.md](formats/green-reading.md). In the round:

- `scripts/putting/green_read.gd` (`GreenRead`): the slope along and across
  a putt's line, the slope at the ball, the greens' speed as a stimpmeter
  reading from the physics, which aids each skill level gets, and the read
  views.
- Settings > Putting grid: Links 2003's yellow grid, its grid coloured by
  height, or the TV grid coloured by slope (`GreenGrid.Style`). Not at
  Elite skill, as in the game, except as the Broadcast presentation's TV
  graphic. G shows or hides it, Ctrl+G changes the look.
- Settings > Breakline indicator (`BreaklineIndicator`): a yellow line at
  the aiming marker leaning the way the green falls, taller where steeper.
- Settings > Putting assistant: at Amateur skill the line (`PuttRead`) and a
  red dot on the meter for the power; at Professional a band round the line.
- V (or the Read the green button): crouch behind the ball, look from behind
  the hole, from the low side, and from above (the Green Analyzer's stand-in,
  not at Elite). Aiming still works in these views.
- The putting panel on the right (`scripts/ui/putting_panel.gd`) shows the
  greens' firmness, speed and stimp and the slope at the ball.

Round setup > Play > Putting practice plays a practice green
(`scripts/putting/putting_practice.gd`, `practice_cups.gd`) on each chosen
hole's green, for the first player, with nothing scored or saved. Keys (and
buttons on the panel, for a mouse or a finger): N new spot, [ and ] the
distance, L the slope (any, uphill, downhill, left to right, right to left),
P the drill (free putting, around the clock, lag ladder), T the next cup, H
the next green. Free putting brings the ball back to the same spot after
each putt, like the original's Auto-Mulligan.

## Plugging in decoded data

Each decoder implements one small interface and registers it with
`AssetProviders` before the round starts (for example from an autoload).
Nothing in the round needs to change.

- **Courses (.CRZ):** subclass `CourseLoader` (`can_load(path)`,
  `load_course(path) -> CourseData`) and call
  `AssetProviders.register_course_loader(...)`. A course is a list of
  `HoleData` (par, tee, pin, route, placed objects) whose `terrain` is a
  `CourseTerrain`: `height_at(x, z)`, `surface_at(x, z)` returning a
  `Surface.Type`, and `build_visual()` for the mesh. Set
  `GolfRound.course_path` to the course file. `CrzCourseLoader`
  (`course/crz_course_loader.gd`, registered by default) does this for the
  game's own `.CRZ` and `.RNG` courses: it finds the cipher key in
  `LINKSM_1.EXE` through `GameFolder`, keeps it in `user://crz_keys.cfg`,
  and caches decoded terrain in `user://course_cache/`. Its `CrzTerrain`
  takes heights from the course mesh and surfaces from the ground classes in
  `TerrainTypes`, with each record's own bounce and roll values and its
  hazard and free-drop flags (`CourseAreas`). A ball that stops outside the
  hole's outline (`HoleIDShapes`) or in an out-of-bounds area (`OBIDShapes`)
  is out of bounds, and anywhere off the mesh is out of bounds at once.
- **Objects:** subclass `ObjectLibrary` (`instantiate(id) -> Node3D`) and
  set `AssetProviders.object_library`. `PlacedObject.id` is whatever key the
  library understands. `DecodedObjectLibrary.open(game_folder)` (in
  `assets/decoded_object_library.gd`) already does this for the real
  Course Designer objects; it accepts an OBJECT.LIB id as a decimal string or
  a catalog file name. It is not registered by default yet, because the
  placeholder course uses its own ids; the course decoder should register it
  together with real placements.
- **Golfer:** subclass `GolferAssets` (`create_golfer() -> GolferRig`, and
  optionally `create_golfer_for(look)` for a player's `PlayerLook`) and
  set `AssetProviders.golfer_assets`. `GolferRig.play()` receives
  `&"address"`, `&"backswing"`, `&"swing"`, `&"putt"` and `&"celebrate"`.
  `LinksGolferAssets` (`scripts/golfer/`) is used automatically when a game
  folder is configured: the original skinned, textured golfer and clubs as a
  `Skeleton3D`, driven by the original clips. Without a game folder,
  `PlaceholderGolferAssets` gives `FreeGolfer`: a realistic man built from
  MakeHuman's CC0 assets by `tools/golfer/build_free_golfer.py`, moving
  with motion capture (CMU mocap, retargeted by
  `tools/golfer/mocap_swing.py`): address with a look at the target, swing,
  putt (irons get their own address and swing, closer to the ball and more
  bent over, from `tools/golfer/iron.py`), a walk up to each new ball, a crouch behind the ball to read each
  putt, `celebrate` and `upset` reactions, and an `idle` stand (used by the
  caddie), baked into `game/assets/golfer/free_golfer.glb`, and dressed from
  the look pack `free_golfer_parts.olg` (see
  [Player creator](#player-creator); licence in `LICENSE.md` next to them).
  Two `SkeletonModifier3D`s run on top of the clips: `GolferLook` turns the
  head to follow the ball in flight (`GolferRig.watch`) and `GolferFeet`
  plants the feet on slopes (`GolferRig.set_ground`). If either file is
  missing it falls back to `PlaceholderGolfer`, the figure built from
  primitives.
- **Audio:** subclass `SoundBank` (`play(event)`, and optionally
  `play_detail(event, detail)`) and set
  `AssetProviders.sound_bank_factory` to a callable that builds it. Events:
  `&"hit"` (with the club, lie and power), `&"putt"`, `&"land"` (with the
  surface and speed), `&"cup"`, `&"splash"`, `&"applause"`, `&"footsteps"`,
  `&"club"` and the crowd reactions (see `sound_bank.gd`).
  `LinksSoundBank` (`scripts/audio/`) is used automatically when a game
  folder is configured (see `scripts/game_folder.gd`); it plays the
  original effects from `predefined.ssf`. Without the game files
  `FreeSoundBank` plays real recordings from `game/assets/sounds/` (CC0
  and CC BY field recordings from freesound.org, cut and mixed by
  `tools/audio/build_free_sounds.py` from `tools/audio/free_sounds.json`;
  credits in `game/assets/sounds/CREDITS.md`): a strike per club kind
  (driver, fairway wood or hybrid, iron, wedge) with turf, grass or sand
  layered in by lie, landings by surface and the crowd takes, each played
  with a little random pitch and level. Courses with no ambient sounds of
  their own get `FreeAmbience`. Like a real course on TV it is mostly
  quiet: wind in the trees (always a little, more with the wind); a bed
  picked from where the course is in the world when that is known (a
  course built from a map: deserts round Phoenix, the Gulf and inland
  Australia; woodland far north or south) and otherwise from its name
  (parkland, woodland, seaside, desert; a name that says links or bay
  wins), kept
  low, with birdsong loudest at dawn and quietest at midday (cicadas the
  other way); now and then a single bird calling from a tree 25 to 90 m
  away (a 3D sound, fainter and duller with distance); a far-off road;
  some mornings and afternoons a distant mower; and running water near
  ponds and creeks. The mix follows the camera round the hole, checked
  twice a second and faded smoothly: under the trees the birds and leaves
  are louder and the calls come from the hole's own trees; on an open
  fairway both drop away (on a seaside links the wind rises instead); water
  rises as the camera nears it. Somewhere warm (within 38 degrees of the
  equator) cicadas sing in the trees under the birds, loudest at midday.
  The time of day comes from Settings (and moves
  through the round with "Through the round"). In Broadcast and Tour the
  gallery murmurs from the tee and the green, and hushes while the player
  is over the ball. The road, mower and murmur are synthesised by
  `tools/audio/synth_ambience.py`. Menu buttons
  click with `ui_click.ogg`.
- **Physics:** subclass `ShotModel` (`launch(...)`, `simulate(...)`) and set
  `AssetProviders.shot_model`. This is where a model tuned against the
  original game, or the C++ core through GDExtension, replaces the stand-in.

Coordinates everywhere: +y up, +z downrange, +x to the golfer's left, metres.

## The stand-in physics

Published real-world golf ball physics, implemented in
`libs/olcore` (`ball_physics.cpp`, `shot.cpp`, `swing.cpp`) and ported to
GDScript in `game/scripts/physics/ball_physics.gd`:

- **Flight:** gravity, drag with Cd = 0.24 + 0.18 S and Magnus lift with
  CL = -0.05 + sqrt(0.0025 + 0.36 S) (capped at 0.35), where S is the spin
  ratio r|w|/|v| (Smits and Smith's fits), RK4 at 4 ms.
- **Bounce:** a rigid-sphere impulse model. Turf restitution follows Penner's
  fit e = 0.510 - 0.0375 v + 0.000903 v^2 (0.12 above 20 m/s), and the ball
  meets a crater wall tilted back by Penner's 15.4 deg x (v/18.6) x
  (angle/44.4). Coulomb friction pushes the contact point towards rolling
  without slipping, which is what checks a wedge on the green.
- **Roll:** 5/7 g along the slope for a rolling solid sphere, plus rolling
  resistance per surface. Green resistance gives roughly a Stimp 10 green.
- **Obstacles:** `CourseTerrain.obstacle_hit()` (`Terrain::obstacle_hit` in
  C++) reports the first trunk, canopy or wall a flight or roll step enters.
  A solid keeps 35% of the speed into its face and 75% along it; a canopy
  keeps 20% and drops the ball; a ball that settles on a flat top (a wall,
  a bridge) stays there. Rolling balls ignore canopies.
- **Wind:** drag and lift use the ball's velocity through the air, so a
  uniform wind (`BallParams::wind`, the `wind` argument in GDScript) slows,
  carries or pushes the ball sideways. It does not act on a rolling ball.
  `Wind` (`scripts/physics/wind.gd`) picks the conditions: a prevailing
  direction for the round, a speed and a shift for each hole, and a small
  change between shots, scaled by the Wind setting (Off, Light, Moderate,
  Strong).
- **Clubs:** tour-average launch monitor data (ball speed, launch angle,
  spin) for driver to pitching wedge; wedges and putter are estimates.

When the game folder has the executable, `LinksShotModel` replaces
`StandardShotModel` and plays the whole shot with the game's own model:
flight (`LinksAero`, `olcore/links_flight.hpp`) and bounce and roll
(`LinksGround`, `olcore/links_ground.hpp`); see
[formats/physics.md](formats/physics.md). The launch stays as above, and
trees and the cup use our own handling.

Apart from that model, none of these constants come from Links 2003. Tuning them against the
original game is the "(needs data)" item in the roadmap. `run_tests.gd` checks
the GDScript port against numbers from the C++ tests, so change both
together.

## Not done yet

Gusts during a flight, wind that changes with height, lie-specific animations,
camera styles from the original, computer opponents, and the real-time mouse swing.
