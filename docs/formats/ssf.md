# Sound script (`.SSF`)

Status: partial (event names, chance, type and wave lists are understood;
the trigger conditions on voice events are not)
Seen in: `GAME/PREDEF_1.SSF` (`predefined.ssf`, ball and swing effects),
`GAME/POLYANI/*.SSF` (golfer voices), `GAME/TOURNA_1.SSF` (commentary)

## Overview

A bank of sound events. Each event has a name ("Full Swing", "Ball Bounce
Sand", "Hook", "Putt Too Hard"), a type code that the game raises, a chance
or volume, and a list of candidate waves. The waves themselves are embedded
as complete RIFF WAV files (16-bit PCM, 22,050 Hz mono in the files seen).

Implemented by `olcore::SsfFile` (`libs/olcore/include/olcore/ssf.hpp`).

## Layout

All numbers are little-endian.

### File header (0x1c bytes)

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | char[4] | magic | `SSF\0` |
| 0x04 | u32 | version | 12 |
| 0x08 | u32 | | 8 |
| 0x0c | u32 | | 0 |
| 0x10 | u32 | | 0 |
| 0x14 | u32 | event_count | Number of `EVE` chunks |
| 0x18 | u32 | | Larger than the number of waves (37 for 27 waves, 255 for 102 events); possibly the next free id in the authoring tool |

### Chunks

The rest of the file is a sequence of chunks, each with a 16-byte header:

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | char[4] | tag | See below |
| 0x04 | u32 | size | Bytes of body after this header |
| 0x08 | u32 | | 8 |
| 0x0c | u32 | | 0 |

Chunks come in this order: `event_count` × `EVE`, one `WND`, one `WST`,
then one wave chunk per wave.

| Tag | Body |
|-----|------|
| `EVE\0` | One event (0x124 bytes, below) |
| `WND\0` | Wave names: NUL-terminated UTF-16LE strings back to back, one per wave, in wave order (`FULLSWNG.WAV`, `25-03-B1.wav`). A missing wave has an empty name. |
| `WST\0` | u32 per wave: the absolute file offset of that wave's chunk |
| `W` + u16 index + `\0` | A complete RIFF WAV file. The second and third bytes of the tag are the wave index. |

### `EVE` body (0x124 bytes)

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0x00 | u32 | | 1 in `predefined.ssf` and golfer files, 0 in `NONE.SSF` |
| 0x04 | char16[32] | name | UTF-16LE, NUL-padded |
| 0x44 | u32 | chance | 100 for effects. Voice events use 20 to 100; most likely the percent chance the line is spoken. |
| 0x48 | u32 | type | Effects: the game event code (0 full swing, 1 chip, 2 putt, 3 pin hit, 4 ball in cup, 5 hard collision, 6 pass-through collision, 7 splash, 16 to 26 ball bounce per surface, 27 flag, 28 to 32 hit golfer, birds, metal, wood, glass, 33 iron swing, 34 wood chip). Voices: 8 for reactions while the ball flies, 9 for comments after it stops. |
| 0x4c | u32 | | 0 |
| 0x50 | u32 | | Leftover pointer from the authoring tool (voice events only) |
| 0x54 | u32 | | Leftover pointer from the authoring tool (voice events only) |
| 0x58 | u32 | wave_count | Number of entries in the next field |
| 0x5c | u16[50] | waves | Wave indices to choose from; the first `wave_count` are used |
| 0xc0 | 100 bytes | conditions | Voice events only: small integers and 0xff/0xffff markers, probably the shot conditions (distance, lie, result) that select the event. Not decoded. |

Effect events in `predefined.ssf` map one event to one wave. Voice events
list one to four takes of the same line.

## The tournament bank

`GAME/TOURNA_1.SSF` (about 80 MB, 132 events, 253 waves) holds the
tournament crowd, not an announcer. Its waves are applause, cheers, groans
and "oohs" (`app2-*`, `app8-*`, `appmiss*`), a few spectator shouts while a
putt rolls (`GoInTheHole*`), and one background murmur (`WALLALOW.wav`).
It repeats the effect events of `predefined.ssf` (types 0 to 7 and 16 to
34) with no waves, and adds:

| Type | Events | When (from the names) |
|------|--------|------------------------|
| 8 | `Putt On It's Way` | while a putt is rolling |
| 9 | `Hole in one!`, `Short Bird` to `Long Par`, `Chip In`, `Hole Out (>100)`, `Shot OB or Water`, applause events | when the ball stops or drops, by score and putt length |
| 10 | `Great Shot lands < 15`, `Lip Out >8`, `Bad Drive`, chip, wedge, iron and putt grades | the reaction to how good the shot was |
| 14 | `Tee Shot`, `Tee Shot Par 3` | applause from the tee gallery |
| 15 | `Background Crowd` | a looping murmur |

### Conditions (partly understood)

The first 16 bytes of the condition block look like a distance test,
judging by how they change across events whose names give a distance:

| Offset | Type | Meaning (inferred) |
|--------|------|--------------------|
| 0xc1 | u8 | Comparison: 1 less than A, 2 between A and B, 0 at least A, 0xff no distance test |
| 0xc4 | u32 | Flags, probably lie, club or shot kind (0x35c on chips and pitches, 0x10 on sand shots) |
| 0xc8 | u32 | A |
| 0xcc | u32 | B |

On putts, A and B read as feet: `Short Bird` is under 3, `Med Bird` is
3 to 5, `Med-Long bird` is 5 to 8 and `Long Bird` is 8 or more. On full
shots they read as yards of shot length (120, 200, 220, 225, 240, 275).
The bytes after 0xd0 (0xff runs) are still unknown.

The game (OpenLinks) maps its crowd reactions onto groups of these events
in `LinksSoundBank.CROWD_EVENTS` and doesn't evaluate the conditions yet.

## Golfer voices

`GAME/POLYANI/*.SSF` hold each golfer's own spoken reactions (5 to 15 MB
each): the named pros (`DAVIDT_1`, `SERGIO_1`, `JESPER_1`, `ANNIKA_1`), the
generic `MALE1_1` to `MALE3_1` and `FEMALE_1`/`FEMALE_2`, and an empty
`NONE.SSF`. A golfer's bank starts with the first six letters of its `.L3`
archive. Voice events by type:

| Type | Examples | When |
|------|----------|------|
| 8 | `Hook`, `Slice`, `Crush Tee Shot`, `Putt Looks Good!`, `Putt Too Hard`, wind remarks | while the ball is moving |
| 9 | `Great Shot`, `In Water`, `OB`, `Lip Out`, `Nice Lag`, `Birdie`, `Bogie`, `Chip In` | after it stops or drops |
| 10 | `Approach Near-Pin`, `Tree Collision`, `Good Kick` | when it lands |
| 11 | `Address Tee Shot`, `Address Putt` | at address |
| 14 | `Perfect Swing`, `Bad Swing` | at impact |

`chance` (20 to 100 on these events) is the percentage chance the line is
spoken, which keeps the golfer from talking after every shot. The game
(OpenLinks) picks type 9 events by name from the shot's outcome
(`GolferVoice.event_for`) and honours `chance`; it doesn't evaluate the
condition blocks.

## Open questions

- The condition block at 0xc0 on voice events, and how the game picks
  between voice events that share type 8 or 9.
- Whether `chance` is a probability or a volume for effects.
