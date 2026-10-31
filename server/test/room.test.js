import test from "node:test";
import assert from "node:assert/strict";
import { RoomState } from "../src/room.js";
import { PROTOCOL_VERSION, cleanName, isCode, randomCode } from "../src/protocol.js";

const hello = (name) => ({ type: "hello", v: PROTOCOL_VERSION, name });
const typesTo = (sends, to) => sends.filter((s) => s.to === to || s.to === "all").map((s) => s.msg.type);

test("codes and names", () => {
  const c = randomCode(4);
  assert.ok(isCode(c, 4), c);
  assert.ok(!isCode("ABCI", 4) && !isCode("abc", 3) && !isCode("ABC", 4));
  assert.equal(cleanName("  Ann   Lee "), "Ann Lee");
  assert.equal(cleanName("Zoë O'Brien"), "Zoë O'Brien");
  assert.equal(cleanName(""), null);
  assert.equal(cleanName("x".repeat(21)), null);
  assert.equal(cleanName("<script>"), null);
});

test("joining: the first player hosts, seats fill in order, four at most", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann"));
  assert.equal(a.id, 1);
  assert.equal(room.host, 1);
  assert.deepEqual(typesTo(a.sends, 1), ["welcome", "members"]);
  const b = room.join(hello("Bo"));
  assert.equal(room.member(b.id).seat, 1);
  assert.match(room.join(hello("bo")).error, /already here/);
  room.join(hello("Cy"));
  room.join(hello("Di"));
  assert.match(room.join(hello("Ed")).error, /full/);
  assert.match(room.join({ type: "hello", v: 99, name: "X" }).error, /version/);
  assert.match(room.join({ type: "shot" }).error, /hello/);
});

test("late joiners get the host's setup and state", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann")).id;
  room.message(a, { type: "setup", course: "Kauri" });
  room.message(a, { type: "state", hole: 3 });
  const b = room.join(hello("Bo"));
  assert.deepEqual(typesTo(b.sends, b.id), ["welcome", "setup", "state", "members"]);
});

test("only the host runs the round; shots only on your turn, to the host", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann")).id;
  const b = room.join(hello("Bo")).id;
  const c = room.join(hello("Cy")).id;
  assert.match(room.message(b, { type: "setup" }).error, /only the host/);
  assert.match(room.message(b, { type: "result" }).error, /only the host/);
  assert.match(room.message(b, { type: "shot", power: 1 }).error, /your turn/);
  const turn = room.message(a, { type: "turn", seat: 1 });
  assert.deepEqual(turn.sends, [{ to: { except: a }, msg: { type: "turn", seat: 1, from: 0 } }]);
  assert.match(room.message(c, { type: "shot" }).error, /your turn/);
  const shot = room.message(b, { type: "shot", power: 0.9 });
  assert.deepEqual(shot.sends, [{ to: a, msg: { type: "shot", power: 0.9, from: 1 } }]);
  room.message(a, { type: "result", rest: [1, 2, 3] });
  assert.equal(room.turnSeat, -1);
  assert.match(room.message(b, { type: "shot" }).error, /your turn/);
  assert.match(room.message(a, { type: "turn" }).error, /seat/);
});

test("quick chat, mismatch reports and pings", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann")).id;
  const chat = room.message(a, { type: "chat", id: 2 });
  assert.deepEqual(chat.sends[0].msg, { type: "chat", id: 2, from: 0, name: "Ann" });
  assert.match(room.message(a, { type: "chat", id: 99 }).error, /quick chat/);
  assert.match(room.message(a, { type: "chat", text: "free text" }).error, /quick chat/);
  assert.equal(room.message(a, { type: "mismatch", shot: 7 }).sends[0].msg.shot, 7);
  assert.deepEqual(room.message(a, { type: "ping" }).sends, [{ to: a, msg: { type: "pong" } }]);
  assert.match(room.message(a, { type: "nonsense" }).error, /unknown/);
  assert.match(room.message(42, { type: "ping" }).error, /not in the room/);
});

test("when the host leaves, the next player hosts; a finished room takes nobody", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann")).id;
  const b = room.join(hello("Bo")).id;
  room.message(a, { type: "turn", seat: 1 });
  const sends = room.leave(a);
  assert.equal(room.host, b);
  assert.equal(room.turnSeat, -1);
  assert.deepEqual(sends.map((s) => s.msg.type), ["host_left", "members"]);
  // Ann comes back and takes the lowest free seat.
  const again = room.join(hello("Ann"));
  assert.equal(room.member(again.id).seat, 0);
  room.message(b, { type: "end" });
  assert.match(room.join(hello("Cy")).error, /finished/);
});

test("the state survives being stored", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann")).id;
  room.message(a, { type: "setup", course: "Kauri" });
  const copy = new RoomState("ABCD", JSON.parse(JSON.stringify(room.toJSON())));
  assert.equal(copy.host, a);
  assert.equal(copy.setup.course, "Kauri");
  assert.equal(copy.join(hello("Bo")).id, 2);
});
