import test from "node:test";
import assert from "node:assert/strict";
import { GameState } from "../src/game.js";
import { GameObject } from "../src/game_object.js";

const conditions = {
  course_name: "Kauri", course_file: "kauri.olcourse", course_hash: "ab12", holes: 1, tees: 0,
  wind_level: 2, mode: 0, model: "standard",
};
const shot = (n) => ({ index: n, power: 0.8, rest: [n, 0, n] });
const record = (seed, shots, extra = {}) => ({
  seed, course_hash: "ab12", holes: 1, tees: 0, model: "standard", wind_level: 2, shots, ...extra,
});

test("a round in your own time: conditions, joining, and shots that can't be taken back", () => {
  const { game, error } = GameState.create("ABCDEFGH", 77, 1, "k1", "Ann", conditions);
  assert.equal(error, undefined);
  assert.match(GameState.create("X", 1, 1, "k", "Ann", { ...conditions, model: "x" }).error, /model/);
  assert.match(GameState.create("X", 1, 1, "k", "Ann", { course_name: "a" }).error, /conditions need/);
  assert.ok(game.join("k2", "Bo", 2).ok);
  assert.ok(game.join("k2", "Bo", 2).ok, "joining twice is fine");
  assert.match(game.join("k3", "ann", 2).error, /already playing/);
  assert.match(game.submit("k9", record(77, []), 3).error, /join/);
  assert.match(game.submit("k1", record(78, []), 3).error, /seed/);
  assert.match(game.submit("k1", record(77, [], { wind_level: 0 }), 3).error, /wind/);
  assert.match(game.submit("k1", record(77, [], { course_hash: "zz" }), 3).error, /course_hash/);
  assert.match(game.submit("k1", record(77, [], { resumed: true }), 3).error, /resumed/);
  assert.ok(game.submit("k1", record(77, [shot(0), shot(1)]), 3).ok);
  assert.match(game.submit("k1", record(77, [shot(0)]), 4).error, /taken back/);
  assert.match(game.submit("k1", record(77, [shot(0), { ...shot(1), power: 1 }]), 4).error, /shot 2 was changed/);
  assert.ok(game.submit("k1", record(77, [shot(0), shot(1), shot(2)], { finished: true, cards: [[3]] }), 5).ok);
  assert.match(game.submit("k1", record(77, [shot(0), shot(1), shot(2), shot(3)]), 6).error, /finished/);
  const view = game.view(false);
  assert.equal(view.seed, 77);
  assert.deepEqual(view.players.map((p) => [p.name, p.shots, p.finished]), [["Ann", 3, true], ["Bo", 0, false]]);
  assert.equal(view.players[0].record, undefined);
  assert.ok(!JSON.stringify(game.view()).includes("k1"), "player keys stay on the server");
});

// A stand-in for a Durable Object's storage.
function fakeCtx() {
  const data = new Map();
  return {
    storage: {
      get: async (k) => data.get(k),
      put: async (k, v) => data.set(k, structuredClone(v)),
      setAlarm: async () => {},
      deleteAll: async () => data.clear(),
    },
    blockConcurrencyWhile: (fn) => fn(),
  };
}

const post = (path, body) => new Request(`https://do${path}`, { method: "POST", body: JSON.stringify(body) });
const token = (c) => c.repeat(40);

test("the game object keeps a round between requests and hides tokens", async () => {
  const ctx = fakeCtx();
  const obj = new GameObject(ctx, {});
  let r = await obj.fetch(post("/create?id=ABCDEFGH", { token: token("a"), name: "Ann", conditions }));
  assert.equal(r.status, 200);
  const made = await r.json();
  assert.equal(made.id, "ABCDEFGH");
  assert.ok(made.seed > 0 && made.seed % 2 === 1);
  r = await obj.fetch(post("/create?id=ABCDEFGH", { token: token("a"), name: "Ann", conditions }));
  assert.equal(r.status, 409);
  r = await obj.fetch(post("/join", { name: "Bo" }));
  assert.equal(r.status, 401);
  r = await obj.fetch(post("/join", { token: token("b"), name: "Bo" }));
  assert.equal(r.status, 200);
  r = await obj.fetch(post("/record", { token: token("b"), record: record(made.seed, [shot(0)]) }));
  assert.equal(r.status, 200);
  // A fresh object (the Durable Object woke up again) reads the stored round.
  const again = new GameObject(ctx, {});
  await new Promise((done) => setTimeout(done, 0));
  const view = await (await again.fetch(new Request("https://do/"))).json();
  assert.deepEqual(view.players.map((p) => p.shots), [0, 1]);
  assert.ok(!JSON.stringify(view).includes(token("a")));
  r = await again.fetch(post("/record", { token: token("b"), record: record(made.seed + 2, [shot(0)]) }));
  assert.equal(r.status, 400);
});
