# Golfer animation script (`SCRIPT.TXT` in `POLYANI/*.L3`)

Status: complete (plain text)
Seen in: every golfer archive, plus a commented example at
`GAME/POLYANI/SCRIPT.TXT`

## Overview

An INI-style text file that tells the game which model and club files a
golfer uses, which textures can be swapped, and which animation clips to
play in each phase of a shot. Comments start with `;`, also at the end of
a line. Values are case-insensitive file or clip names; a clip name `X`
refers to `X.CLP` in the same archive.

## Sections

`[Details]`

| Key | Meaning |
|-----|---------|
| `Name` | Display name |
| `Cumstomizable Parts` (sic) | Number of `[customizable part N]` sections |
| `Customizable Mesh` | 1 if the mesh can be swapped |
| `Extrema` | Space-separated joint and locator names the game tracks on the body (crown, hat brim, shoulders, elbows, knuckles, heels, `clubJoint`) |
| `ClubExtrema` | Locators on the club (`clubHeadLocator`, `clubHeadLocatorAft`, `clubHeadLocatorFore`) |

`[file_locations]` maps logical names to files. `golfer.skl` and
`golfer_low.skl` are the high and low detail models; the club models and
textures come from another archive, written `clubs.l3|driver.skl`. Any file
not listed is in the same archive as the script.

`[customizable part N]` has `Title` (Shirts, Pants), `Varieties`,
`Textures` and `TextureK` patterns where `%%` is replaced by the variety
number (`L_A01_Shirt01_%%.TGA` gives `L_A01_SHIRT01_01.TGA` ...).

`[Driver]`, `[Chip]`, `[Iron]`, `[Putter]` describe one shot type each:

| Key | Played |
|-----|--------|
| `Address` | Settling over the ball |
| `PreSwing` | Idle loops at address (breathing, waggles), picked at random |
| `Swing` | The swing itself; several entries (half swing, putt lengths) |
| `FinishBreath` | Holding the finish |
| `Finish2Neutral`, `NeutralBreath` | Back to a relaxed stance and idling there |
| `InFlightReactions` | Reactions while the ball is in the air |
| `PostFlightReactions` | Reactions once the ball has stopped |
| `PostFlightIdle` | Idles afterwards |
| `Neutral2Stretch`, `StretchBreath`, `Stretches`, `Stretch2Neutral` | Stretch routine between shots |
| `FollowThrough` | Putter only |

Lists are comma-separated. A clip can carry timed events in brackets:
`DriverSwing( 0@29 1@32 2@46)` means event 0 at frame 29, event 1 at frame
32, event 2 at frame 46. The event numbers are listed in the file:

| Event | Meaning |
|------:|---------|
| 0 | Top of backswing |
| 1 | Play swing sound |
| 2 | Launch the ball |
| 3 | Ball lands |
| 4 | Ball closest to hole |
| 5 | Ball in hole |
| 6 | Ball stops rolling |

Reactions carry one event that says when they should start, so
`IronShortInHoleRaiseArms( 5@46)` is played so that frame 46 lines up with
the ball dropping. Reaction names spell out when they fit: `Short`/`Long`
(during or after flight), then `InHole`, `Good`, `OK`, `Bad`, `VeryBad`,
`Close`, or `English` (body English while the ball curves).

## Swing timing tables (`DRIVERSWING.TXT`, `IRONSWING.TXT`, `PUTTER*.TXT`)

Text dumps written by the export tool, kept in the archives. They list the
club head path of the swing clip: first per clip frame at 30 fps ("Original
Frames": time, head x/y/z, distance travelled, speed), then resampled at
equal distances ("Equidistant Frames": time, head x/y/z, distance, speed,
acceleration, and a mapping back to clip time). The same equidistant table
is stored in binary inside the swing `.CLP` (the `swingmap` and `fullswing
curve` allocations; see [carrera-store.md](carrera-store.md)). The game
probably uses it to drive the swing clip from the mouse in the real-time
swing.
