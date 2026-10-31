# Online play, leaderboards and fair play: design

Status: design. Hot seat (several people at one keyboard,
[game-shell.md](game-shell.md#menus-and-game-modes)) is built; nothing online
is. This note covers online head-to-head play (live and in your own time),
leaderboards, keeping both fair with an open-source client, hosting and its
cost, accounts, and how courses from the discs fit in. It ends with a
recommendation and a phased plan.

## Goals

- Two to four people play one round from their own machines: desktop and the
  browser build on GitHub Pages, in any mix.
- Live rounds (everyone online at once) and correspondence rounds (each
  player takes their shots when they like, over hours or days).
- Leaderboards: a daily and weekly challenge everyone plays in the same
  conditions, plus all-time boards per course.
- Results that can't be faked by editing the client, which is open source
  and easy to change.
- No game data crosses the network or sits on a server
  ([clean-room.md](clean-room.md) still holds).
- Free to run at hobby scale, and nobody needs to run a server for a casual
  game with friends.

## The key idea: a round is its inputs

Golf is turn-based and every shot is a handful of numbers: club, aim, power,
accuracy (or the PowerStroke mouse stroke), plus whatever is random (wind,
the miss model). If every random draw comes from a **round seed**, the whole
round can be replayed from a short list of inputs, about 20 bytes a shot,
2 to 3 KB for 18 holes and four players.

That one change gives us almost everything below:

- **Multiplayer** sends inputs, not ball positions.
- **Replays** of any round, any leaderboard entry, any friend's best.
- **Ghosts:** race a friend's or the leader's recorded round.
- **Fair play:** a checker (the server or another player) re-runs the inputs
  through the same physics and gets the score itself, so a client that just
  claims "54" or quietly made its drives longer is caught.

Built so far (phase 1): the round seed, `ShotRecord` and `RoundRecord`
(`game/scripts/replay/`), finished rounds saved to `user://replays/`, and
`RoundReplay.verify`, which the headless tests run on the full test round
along with a changed swing, card and seed that it must catch.

**Result codes** are also built. When a round ends, X copies a result code
(`OLR1-` and the gzipped record, a few thousand characters). A friend
pastes it on the round setup page. Their game finds the course by its file
name, checks the file hash and physics, and replays every shot. It shows
"Checked" or what didn't match, then plays the same course, tees and wind
(the same seed). The final message shows the friend's score next to theirs.
This works with no server.

Limits: resumed rounds can't be checked, because the wind is drawn again on
resume. In the browser the check needs the course file in memory, so it says
it can't check there yet, though the same conditions can still be played.

What it needs (phase 1 below):

1. A `seed` in `RoundSetup`. Wind and every other draw are worked out from
   `(seed, hole, shot number)` without hidden running state, so a replay
   doesn't have to make the same calls in the same order. Today `Wind` keeps
   one `RandomNumberGenerator` running through the round, and
   `LinksShotModel.rng`, the mouse swing (`main.gd` `_on_mouse_stroke`) and
   `ComputerGolfer` draw from `randi()`.
2. A `ShotRecord` per shot: player, hole, stroke, club, aim, power, accuracy
   or the mouse stroke samples, and the result (where the ball stopped, the
   lie, penalties) so a checker can compare.
3. A `RoundRecord`: setup, seed, the shot model and its version, a hash of
   the course file, the shots. Saved in `user://replays/`.
4. `RoundReplay.verify(record, course, model)`: re-runs every shot and checks
   each stopping point (within a few centimetres) and the card. CI plays
   rounds headlessly, records them and verifies them, so a change that breaks
   determinism fails the build.

**Floating point across platforms.** Desktop and the browser build (wasm)
may round a few maths functions differently. Checks therefore compare each
shot's stopping point within a tolerance, and the next shot starts from the
*recorded* position, so tiny differences never pile up or change a score.
If the C++ core (`libs/olcore`) later runs everywhere through GDExtension,
it can use fixed maths and be bit-exact.

## Playing together

### Live rounds

Built (phase 2, not yet live: the server isn't deployed). Every game in the
room plays the whole round itself, **in step**:

1. The **host** (whoever made the room) picks the course and starts the
   round. Its `setup` message carries the `RoundSetup`, the seed, the wind
   level and `owners`: which game plays each player. Computer golfers belong
   to the host. A guest finds the course by file name and checks its hash.
2. From then on the round is one numbered stream of **events**: each shot's
   inputs (a `ShotRecord`) and each drop (reason, option, spot). A player's
   own game plays their shot at once (the meter is timing-critical, so it
   never waits on the network) and sends it. Every other game waits in
   `State.REMOTE` until that event arrives, then plays the same inputs through
   its own physics (`GolfRound._apply_remote`). Turn order, honour, penalties
   and cards follow by themselves, because every game runs the same rules
   on the same events.
3. **Everyone checks everyone.** If a replayed shot stops more than 5 cm
   from where the sender's did, that game sends `mismatch` and everyone sees
   that the round is not agreed. A cheating player would need every other
   player to cheat with them.
4. The server checks that each event is the next number and comes from the
   game that owns that player. When someone leaves, the host's game plays
   their players from then on. When the host leaves, the oldest remaining
   player becomes host.
5. Quick-chat only to start ("Nice shot", "Unlucky", "Good game"), no free
   text or voice, so there is nothing to moderate.

The headless tests play a nine-hole round between two games joined in one
process: two people and the host's computer golfer, with a drop. Both games
agree on every shot and card. The lobby (main menu > Play online, shown once
a server is set) makes or joins a room by its 4-letter code. Not yet built:
rejoining a round in progress, timeouts, and quick-chat buttons.

Waiting on three other people is the slow part of online golf, so a room can
pick **simultaneous play**: each player plays their own ball without waiting,
others' balls appear as ghosts when their shots arrive, and the hole ends when
all are in. Stroke play and Stableford suit it; match play and the team modes
keep strict turns.

Timeouts (to come): a live turn waits 90 s, then the others can let the
host's game play the shot with a computer golfer.

### Correspondence rounds (in your own time)

The same round, stored on the server instead of held by a host. A player
opens the game, sees "Your turn on 7 against Dave", plays one shot or a whole
hole, and leaves. The server keeps the `RoundRecord` and the seed, so nobody
can reroll the wind by quitting. A browser notification or an email is out
of scope at first; the main menu shows waiting rounds.

### Transport

Golf sends a few small messages per shot, so speed doesn't matter but
reaching everyone does. Two options:

| | WebRTC data channel (`WebRTCMultiplayerPeer`) | WebSocket relay (`WebSocketPeer`) |
|---|---|---|
| Needs a server | Only to swap offers ("signalling"); strict routers also need a TURN relay | One small relay for every message |
| Works in the single-threaded web build | Yes | Yes |
| Behind strict NAT / school / office networks | Needs TURN (metered, costs money) | Always works (it's plain HTTPS) |
| Correspondence rounds | No, needs a server anyway | Same server |
| Code to write | Signalling plus WebRTC setup on each platform | One protocol |

**Recommendation: the WebSocket relay.** The server we need for leaderboards
and correspondence rounds also relays live rounds, no TURN bill, one code
path. Copy-and-paste WebRTC ("send this code to your friend") can come later
for people who want no server at all. Desktop LAN play over ENet isn't
worth a second transport.

## Leaderboards

- **Daily and weekly challenges:** one course, tees, wind level and seed for
  everyone, so everyone gets the same wind on every shot. One ranked attempt
  per challenge (the server hands out the seed and remembers who started),
  unlimited practice attempts on a different seed.
- **Course boards:** best gross round per course and tees, plus closest to
  the pin and longest drive per hole.
- **Handicap-adjusted** boards later, using `Handicap` and the index the
  player earned from submitted, verified rounds rather than one they typed.
- Each entry links to its replay; open it and watch the round, or play
  against it as a ghost.

## Fair play with an open-source client

Anyone can change and rebuild the client, so obfuscation and "anti-cheat"
software don't help. Instead the server (or the other players) only accepts
what it can check itself.

| Cheat | Stopped by |
|---|---|
| Posting a fake score | Results are never sent, only inputs. The checker computes the score. |
| A modified client with longer drives, a bigger cup, softer rough | The checker runs its own physics and course copy. |
| Rerolling the wind (quit and restart until it's calm) | The server issues the seed and counts every start; correspondence rounds live on the server. |
| Editing the replay afterwards to improve one shot | The server issues the seed only when the round starts and records when each shot was sent. In live rounds the other players check each shot as it happens. |
| A bot that hits perfect power and accuracy every time | Can't be prevented outright (true of every golf game). Mitigations: the swing sends its timing (meter clicks, mouse samples) and the server checks it looks human; separate boards for each meter difficulty; statistical flags (too many perfect swings in a row); every entry has a replay anyone can watch and report. |
| Multiplayer host cheating | Every other player checks every shot (above). |

Honest limit: a careful bot playing at a human-looking level can't be
caught by maths. Watchable replays and a report button handle the rest,
which is what speedrun and golf-game communities rely on.

## Disc courses and courses anyone can have

Two things decide what a checker can verify: the **course** and the
**physics**. The server may only hold open material.

| | Course | Physics |
|---|---|---|
| Open (server may hold it) | Designer courses (`.olcourse`, author agrees), real courses built from open map and lidar data, the placeholder course | `StandardShotModel` |
| Needs the discs or the exe | The 39 legacy `.CVT` courses and the 2003 courses | `LinksShotModel` (tables read from the player's own exe) |

- **Live and correspondence rounds:** a room only offers courses and a
  physics model every player has. Players match on `course_key` plus a hash
  of the course file, so two players with the same disc course play
  together. Every player owns the data, so every player can check every shot.
  Designer courses can be sent in the lobby when the author has marked them
  shareable; community courses from Links Corner are not sent (we link to
  where to get them instead).
- **Verified leaderboards:** courses and physics the server can hold. A real
  course is saved once as a file (with its open-data attributions), so the
  server and every player use the identical build rather than refetching
  map data that may have changed.
- **Disc-course leaderboards ("player-checked"):** the server can't re-run
  them, so it checks what it can (seed, timing, plausibility) and shows them
  with a different badge. Whenever someone who owns the course opens the
  replay, their game re-runs it and reports a mismatch automatically, so
  every viewer is a checker.

## Accounts

- **No passwords and no email at first.** The first time a player goes
  online the game makes a random key pair and keeps it in `user://`; the
  server knows the player by that key and a display name (checked against a
  word list, unique, changeable). Nothing personal is stored.
- **Optional sign-in with GitHub or Discord** (free OAuth) later, to keep the
  same name on another device or after a reinstall. Losing the key without
  that just means a new name.
- Names can be reported; a moderator can rename or hide a player.
- Delete my data: a button that removes the player and their entries.

## Hosting and cost

| Option | What it gives | Cost at hobby scale | Notes |
|---|---|---|---|
| **Cloudflare Workers + Durable Objects (SQLite)** | WebSocket rooms (one Durable Object per room), leaderboards and records in SQLite, static API | Free plan covers thousands of rounds a day | Code is TypeScript or wasm; Durable Objects with SQLite are on the free plan. The free plan's CPU limit per request is short (10 ms), so re-running a whole round may need Workers Paid ($5 a month) or a split into per-hole checks. |
| Supabase (Postgres, auth, edge functions) | Database, OAuth, realtime | Free tier | Free projects pause after a week idle. |
| A small VPS (Hetzner, OVH) running Nakama or our own server | Everything, full control | About £4 to £6 a month | Needs looking after (updates, backups). |
| Talo (open-source game backend with a Godot plugin) | Leaderboards, players, events | Free tier, or self-host | Its leaderboards trust the client's score; checks would be ours. |
| GitHub only (Actions + Pages) | Static boards rebuilt from submissions | Free | Minutes of delay, and GitHub's terms don't welcome Actions as a game backend. Not recommended. |

**Recommendation: Cloudflare Workers + Durable Objects** on the free plan,
with the code in this repo under `server/` and deployed by CI. Data stays
small (a round record is a few KB). Prices and limits change: check them
before signing up.

**Server-side checking** needs the physics on the server. The C++ core
already holds it (`ball_physics.cpp`, `shot.cpp`, `swing.cpp`,
`scoring.cpp`, and the Links model files), so it builds to wasm for the
Worker, and the same wasm build is the step that unlocks GDExtension in the
browser ([CLAUDE.md](../CLAUDE.md)). The headless GDScript replay checker
stays in CI as the reference.

## What's needed from Michael

- **Phase 2 needs a Cloudflare account** (free) and an API token added as a
  GitHub Actions secret. Nothing is paid unless we move to Workers Paid
  ($5 a month), which would be asked about first.
- **GitHub or Discord sign-in** (phase 4) needs OAuth apps registered under
  his account (free).

## Plan

**Phase 1: replayable rounds (no server, free).**
Round seed; wind and every random draw worked out from (seed, hole, shot);
`ShotRecord` and `RoundRecord`; recording every round to `user://replays/`;
`RoundReplay.verify`; CI plays, records and verifies rounds on both shot
models. Then a **challenge code**: a short text holding course key, tees,
wind level and seed, so friends play the same conditions and compare scores
with no server, plus a **result code** carrying the replay, which the
friend's game checks and can play back.

**Phase 2: the server, friends' rooms and correspondence rounds.**
Cloudflare Worker under `server/`; player keys and names; rooms by
4-letter code over WebSocket; the live protocol above with every client
checking every shot; correspondence rounds stored on the server; resume.
Browser and desktop together.

**Phase 3: leaderboards and server checks.**
`olcore` to wasm; the server re-runs submitted rounds on open courses with
`StandardShotModel`; daily and weekly challenges; course boards; replays and
ghosts from the boards; player-checked boards for disc courses.

**Phase 4: polish.**
Simultaneous play; sign-in with GitHub or Discord; handicap boards from
verified rounds; swing-timing plausibility and outlier flags; reports and
moderation; seasons.
