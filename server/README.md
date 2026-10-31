# Online play server

The server behind online rooms and rounds played in your own time
([docs/online-play.md](../docs/online-play.md)). It runs as a Cloudflare
Worker with Durable Objects on the free plan. It is plain JavaScript with no
dependencies, and `node --test "test/*.test.js"` tests it without Cloudflare.

It is **not deployed yet**. Until it is, the game's online menu stays hidden.

## What it does

- **Live rooms.** `POST /rooms` makes a room and returns a 4-letter code. Each
  player's game opens a WebSocket to `/rooms/CODE`. The first player in is
  the host and starts the round. From then on every game plays the whole
  round in step, from the host's setup (with its seed) and one numbered
  stream of events: each shot's inputs and each drop. Each game replays the
  others' shots through its own physics and reports any shot that stops
  somewhere else. The server relays messages and checks who may send what
  (`src/room.js`), but it never runs any golf.
- **Rounds in your own time.** `POST /games` starts one: the server picks the
  seed, so nobody can reroll the wind. Each player sends their `RoundRecord`
  as they play (`/games/ID/record`). Shots already sent can't be changed or
  taken back (`src/game.js`). `GET /games/ID` shows everyone's progress.
- **Players** have no accounts. Each game makes a random token and keeps it
  in `user://`. The server stores only a hash of it, and names are checked
  for length and characters.

### Room messages

Every message is JSON with a `type`. A new connection's first message is
`{type: "hello", v: 1, name}`, and the server answers with `welcome {code,
you, seat, host}`. Everyone also gets `members` whenever someone comes or
goes. Nobody can join once the round has started.

| From | Type | Goes to | Notes |
|---|---|---|---|
| host | `setup {owners, seed, ...}` | everyone else | Starts the round. `owners[i]` is the room seat whose game plays player `i` (computer golfers are the host's) |
| owner of `player` | `event {seq, player, kind: "shot" or "drop", ...}` | everyone else | Must be the next `seq` |
| host | `state`, `end` | everyone else | `end` closes the room |
| anyone | `chat {id}` | everyone | Quick-chat number, 0 to 7; no free text |
| anyone | `mismatch {shot}` | everyone | My replay of that event disagrees |
| anyone | `ping` | sender (`pong`) | |
| server | `members`, `left`, `host_left`, `owners`, `error {reason}` | | When someone leaves, the host's game plays their players (`owners`). When the host leaves, the oldest remaining player becomes host |

Limits: four players, 64 KB a message, 256 KB a round record. Idle rooms are
deleted after 6 hours, and rounds 30 days after their last shot.

### Known gaps

- The server doesn't re-run shots yet (phase 3), so rounds in your own time
  trust each game's physics. A friend's game can still check a result code.
- The seed is known from the start, so someone could rehearse a round offline
  before sending it. Ranked challenges will need the seed revealed hole by
  hole.

## Deploying (needs Michael's free Cloudflare account)

1. Make a free account at https://dash.cloudflare.com/sign-up.
2. Under My Profile > API Tokens, create a token from the "Edit Cloudflare
   Workers" template. Copy the token and your account ID (shown on the
   Workers & Pages overview).
3. In the GitHub repo, go to Settings > Secrets and variables > Actions. Add
   `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.
4. Run the "Deploy online server" workflow from the Actions tab. It prints
   the Worker's address (`https://openlinks2003.<account>.workers.dev`),
   which then goes into the game's online settings.

The free plan's daily request limits are far beyond what a few rounds use. A
golf round sends a few messages per shot.
