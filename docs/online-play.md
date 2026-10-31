# Online play: design note

Status: design only. Nothing here is built yet. Hot seat (several people at
one keyboard, [game-shell.md](game-shell.md#menus-and-game-modes)) is the
model this builds on.

## Goals

- Two to four people play one round from their own machines: desktop, and
  the browser build on GitHub Pages.
- Every game mode that works in hot seat works online, computer golfers
  included.
- No game data crosses the network. Each player loads their own Links 2003
  files ([clean-room.md](clean-room.md) still holds), so a round can only use
  a course every player has. Players are matched on a course key (the same
  `RoundSetup.course_key` that saved rounds use) plus a hash of the course
  file.
- Nobody has to run a server for a casual game.

## Shape: one host, shots as messages

The round in `GolfRound` (`main.gd`) already separates whose ball is in play
(`current`) from who is hitting it (`shooter`), and every turn passes through
`_begin_turn`, `play_shot(power, accuracy)` and `_complete_flight`. That gives
a small, turn-based protocol:

1. The **host** owns the round: setup, the wind seed, the honour, cards and
   the order of play. It is the same state `SavedRound` writes, so a late
   joiner or a reconnect gets the whole round in one message.
2. When it is a remote player's turn, the host sends `turn {shooter, ball,
   at, lie}`. That player's machine aims and swings locally (the swing meter
   is timing-critical, so it never waits on the network) and sends back
   `shot {club, aim_deg, power, accuracy}`.
3. The host runs the shot through the `ShotModel` and broadcasts `result
   {shot inputs, final position, lie, strokes}`. Every client replays the
   same inputs through its own `ShotModel` for the flight, then snaps the
   ball to the host's final position, so small floating-point differences
   between platforms (desktop vs. wasm) never change a score.
4. Computer golfers run on the host only and send `shot` messages like
   anyone else.

Physics is deterministic for given inputs and a fixed wind seed (the tests
already rely on this), so the snap at step 3 should rarely move the ball more
than a few millimetres. The host's position is the one that counts.

## Transport

- **Browser and desktop together:** WebRTC data channels
  (`WebRTCMultiplayerPeer`), which work in single-threaded web exports and
  through most home routers. One reliable, ordered channel is enough: a round
  sends a few messages per shot.
- **Signalling:** a tiny stateless relay that swaps offers and answers
  under a short room code ("AB3K"). It holds no game state and could run on
  a free tier, or be swapped for copy-and-paste of the offer text for people
  who don't want any server.
- **Fallback:** where WebRTC can't connect (strict NAT), a TURN relay. That
  costs money to run, so it is optional and off by default.
- Desktop-only LAN play could use ENet directly, but one transport for every
  platform is simpler to test, so WebRTC comes first.

## The hand-over screen, online

Hot seat dims the screen between people (`HandOverPanel`). Online, the same
hook in `_begin_turn` instead shows "Waiting for NAME" on every machine but
the shooter's, and the shooter gets a short "Your shot" sting. A remote
player's camera follows the shot as it would in hot seat.

## Things to decide before building

- **Timeouts:** how long to wait for a remote shot before offering the
  others "skip" or "let the computer play it". Suggest 90 s, then a vote.
- **Dropped host:** first version ends the round and keeps a `SavedRound` on
  every machine so anyone can resume it later as host. Host migration can
  come after.
- **Cheating:** the host trusts each client's `power` and `accuracy`. That
  is fine among friends; ranked play would need server-side checks and is
  out of scope.
- **Chat and presence:** text quick-chat ("Nice shot", "Unlucky") only, no
  voice.
- **Handicaps:** each player's index travels with their name in the join
  message; the host's `RoundScoring` applies it as in hot seat.

## Build order

1. Lobby: room code, players and course check, then the host's `RoundSetup`
   sent to everyone.
2. The `turn` / `shot` / `result` loop for stroke play between two desktops.
3. The browser build, and every game mode.
4. Reconnect and resume from the host's saved round.
