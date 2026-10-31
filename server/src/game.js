// A round played in your own time (docs/online-play.md, "Correspondence
// rounds"). Up to four players play the same course, tees and wind (the
// server's seed), each at their own pace; each sends their RoundRecord as
// they go. Shots already sent can't be changed: a new record must start with
// every shot of the last one.
//
// Plain data plus pure methods, like RoomState.

import { MAX_PLAYERS, cleanName } from "./protocol.js";

// What the creator picks, copied from their RoundSetup.
const CONDITION_KEYS = ["course_name", "course_file", "course_hash", "holes", "tees", "wind_level", "mode", "model"];

export class GameState {
  constructor(data) {
    // {id, seed, created, conditions, players: [{key, name, record, updated}]}
    Object.assign(this, data);
  }

  static create(id, seed, now, creatorKey, creatorName, conditions) {
    const name = cleanName(creatorName);
    if (!name) return { error: "pick a name of 1 to 20 letters" };
    const c = {};
    for (const k of CONDITION_KEYS) {
      if (conditions == null || !(k in conditions)) return { error: `conditions need ${k}` };
      c[k] = conditions[k];
    }
    if (typeof c.course_name !== "string" || typeof c.course_file !== "string" || typeof c.course_hash !== "string") {
      return { error: "course name, file and hash are text" };
    }
    for (const k of ["holes", "tees", "wind_level", "mode"]) {
      if (!Number.isInteger(c[k]) || c[k] < 0 || c[k] > 20) return { error: `${k} is a small number` };
    }
    if (c.model !== "standard" && c.model !== "links") return { error: "model is standard or links" };
    const game = new GameState({
      id,
      seed,
      created: now,
      conditions: c,
      players: [{ key: creatorKey, name, record: null, updated: now }],
    });
    return { game };
  }

  player(key) {
    return this.players.find((p) => p.key === key) || null;
  }

  join(key, playerName, now) {
    if (this.player(key)) return { ok: true };
    const name = cleanName(playerName);
    if (!name) return { error: "pick a name of 1 to 20 letters" };
    if (this.players.length >= MAX_PLAYERS) return { error: "this round is full" };
    if (this.players.some((p) => p.name.toLowerCase() === name.toLowerCase())) {
      return { error: `someone called ${name} is already playing` };
    }
    this.players.push({ key, name, record: null, updated: now });
    return { ok: true };
  }

  // Player `key` sends their round so far (a RoundRecord as a dictionary).
  submit(key, record, now) {
    const p = this.player(key);
    if (!p) return { error: "join the round first" };
    if (!record || typeof record !== "object" || !Array.isArray(record.shots)) return { error: "send a round record" };
    if (record.seed !== this.seed) return { error: "the round was played on another seed" };
    for (const k of ["course_hash", "holes", "tees", "model"]) {
      if (record[k] !== this.conditions[k]) return { error: `the round's ${k} doesn't match` };
    }
    if (record.wind_level !== this.conditions.wind_level) return { error: "the round's wind doesn't match" };
    if (record.resumed) return { error: "a resumed round can't be checked" };
    const before = p.record ? p.record.shots : [];
    if (record.shots.length < before.length) return { error: "shots can't be taken back" };
    for (let i = 0; i < before.length; i++) {
      if (JSON.stringify(record.shots[i]) !== JSON.stringify(before[i])) {
        return { error: `shot ${i + 1} was changed after it was sent` };
      }
    }
    if (p.record && p.record.finished) return { error: "your round is finished" };
    p.record = record;
    p.updated = now;
    return { ok: true };
  }

  // What anyone with the round's id sees: the conditions, the seed (each
  // game needs it to draw the wind) and everyone's progress. Player keys stay
  // on the server.
  view(withRecords = true) {
    return {
      id: this.id,
      seed: this.seed,
      created: this.created,
      conditions: this.conditions,
      players: this.players.map((p) => ({
        name: p.name,
        updated: p.updated,
        shots: p.record ? p.record.shots.length : 0,
        finished: !!(p.record && p.record.finished),
        cards: p.record ? p.record.cards || [] : [],
        record: withRecords ? p.record : undefined,
      })),
    };
  }
}
