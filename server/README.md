# Online play server

The server behind online rooms and rounds played in your own time
([docs/online-play.md](../docs/online-play.md)). It runs as a Cloudflare
Worker with Durable Objects on the free plan. It is plain JavaScript with no
dependencies, and `node --test "test/*.test.js"` tests it without Cloudflare.

It is **not deployed yet**. Until it is, the game's online menu stays hidden.

## What it does

- **Live rooms.** `POST /rooms` makes a room and returns a 4-letter code. Each
  player's game opens a WebSocket to `/rooms/CODE`. The first player in is
  the host, and the host's game runs the round. The server relays messages
  and enforces who may send what (`src/room.js`), but it never runs any golf.
- **Rounds in your own time.** `POST /games` starts one: the server picks the
  seed, so nobody can reroll the wind. Each player sends their `RoundRecord`
  as they play (`/games/ID/record`). Shots already sent can't be changed or
  taken back (`src/game.js`). `GET /games/ID` shows everyone's progress.
- **Players** have no accounts. Each game makes a random token and keeps it
  in `user://`. The server stores only a hash of it, and names are checked
  for length and characters.

### Room messages

Every message is JSON with a `type`. A new connection's first message is
`{type: "hello", v: 1, name}`. The server answers with `welcome {code, you,
seat, host}` and then the host's last `setup` and `state` (for late joiners).
Everyone also gets `members`.

| From | Type | Goes to | Notes |
|---|---|---|---|
| host | `setup`, `state` | everyone else | Kept for players who join later |
| host | `turn {seat}` | everyone else | Whose shot it is |
| player on `turn` | `shot {...}` | host | Anyone else is refused |
| host | `result {...}` | everyone else | Ends the turn |
| host | `end` | everyone else | Round over, room closes to newcomers |
| anyone | `chat {id}` | everyone | Quick-chat number, 0 to 7; no free text |
| anyone | `mismatch {shot}` | everyone | My replay of that shot disagrees |
| anyone | `ping` | sender (`pong`) | |
| server | `members`, `left`, `host_left`, `error {reason}` | | When the host leaves, the oldest player becomes host |

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
