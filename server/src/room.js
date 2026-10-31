// A live room: up to four players, one of them the host, who starts the round
// (docs/online-play.md, "Live rounds"). Every game plays the whole round in
// step from the host's setup and one numbered stream of events (each shot's
// inputs, each drop). The server only relays and enforces who may send what:
// an event must be the next number and come from the game that plays that
// player (the setup's `owners`). The golf runs in the players' games.
//
// RoomState is plain data plus pure methods, so it can be stored between
// messages (Durable Objects may sleep) and tested without Cloudflare.
// Each method returns a list of sends: {to, msg}, where `to` is a member id,
// "all", or {except: id}.

import { MAX_PLAYERS, QUICK_CHAT_COUNT, PROTOCOL_VERSION, cleanName } from "./protocol.js";

// Messages only the host sends, relayed to everyone else.
const HOST_ONLY = new Set(["setup", "state", "end"]);
// Events kept for nobody; a player who drops out has their seats played by
// the host from then on.

export class RoomState {
  constructor(code, data = null) {
    this.code = code;
    // {id, name, seat}
    this.members = [];
    this.host = 0;
    this.nextId = 1;
    // Number of the next event of the round.
    this.seq = 0;
    // The host's last `setup` and `state`, for players who join late or
    // reconnect.
    this.setup = null;
    this.state = null;
    this.ended = false;
    if (data) Object.assign(this, data);
  }

  toJSON() {
    const { code, members, host, nextId, seq, setup, state, ended } = this;
    return { code, members, host, nextId, seq, setup, state, ended };
  }

  member(id) {
    return this.members.find((m) => m.id === id) || null;
  }

  _roster() {
    return {
      type: "members",
      host: this.host,
      members: this.members.map((m) => ({ id: m.id, name: m.name, seat: m.seat })),
    };
  }

  // A new connection says hello: {type: "hello", v, name}. Returns
  // {id, sends} or {error}.
  join(hello) {
    if (!hello || hello.type !== "hello") return { error: "say hello first" };
    if (hello.v !== PROTOCOL_VERSION) return { error: `this room speaks version ${PROTOCOL_VERSION}; update the game` };
    const name = cleanName(hello.name);
    if (!name) return { error: "pick a name of 1 to 20 letters" };
    if (this.ended) return { error: "this round has finished" };
    if (this.setup) return { error: "this round has started" };
    if (this.members.length >= MAX_PLAYERS) return { error: "the room is full" };
    if (this.members.some((m) => m.name.toLowerCase() === name.toLowerCase())) {
      return { error: `someone called ${name} is already here` };
    }
    let seat = 0;
    while (this.members.some((m) => m.seat === seat)) seat++;
    const id = this.nextId++;
    this.members.push({ id, name, seat });
    if (this.members.length === 1) this.host = id;
    const welcome = { type: "welcome", code: this.code, you: id, seat, host: this.host };
    const sends = [{ to: id, msg: welcome }];
    if (this.setup) sends.push({ to: id, msg: this.setup });
    if (this.state) sends.push({ to: id, msg: this.state });
    sends.push({ to: "all", msg: this._roster() });
    return { id, sends };
  }

  // A connection closed. The oldest remaining player becomes host; their
  // game carries on from the last state it saw.
  leave(id) {
    const m = this.member(id);
    if (!m) return [];
    this.members = this.members.filter((x) => x.id !== id);
    const sends = [];
    if (this.members.length === 0) return sends;
    if (id === this.host) {
      this.host = this.members[0].id;
      sends.push({ to: "all", msg: { type: "host_left", name: m.name, host: this.host } });
    } else {
      sends.push({ to: "all", msg: { type: "left", name: m.name, seat: m.seat } });
    }
    // The host's game plays the leaver's players from here on.
    if (this.setup && Array.isArray(this.setup.owners)) {
      const hostSeat = this.member(this.host).seat;
      this.setup.owners = this.setup.owners.map((o) => (o === m.seat ? hostSeat : o));
      sends.push({ to: "all", msg: { type: "owners", owners: this.setup.owners, host: hostSeat } });
    }
    sends.push({ to: "all", msg: this._roster() });
    return sends;
  }

  // A message from member `id`. Returns {sends} or {error} (sent back to the
  // sender only; the connection stays open).
  message(id, msg) {
    const m = this.member(id);
    if (!m) return { error: "not in the room" };
    if (!msg || typeof msg.type !== "string") return { error: "messages need a type" };
    const fromHost = id === this.host;
    if (HOST_ONLY.has(msg.type)) {
      if (!fromHost) return { error: `only the host sends ${msg.type}` };
      const out = { ...msg, from: m.seat };
      if (msg.type === "state") this.state = out;
      if (msg.type === "setup") {
        if (this.setup) return { error: "the round has started" };
        if (!Array.isArray(msg.owners) || !msg.owners.every((o) => this.members.some((x) => x.seat === o))) {
          return { error: "setup needs owners: a seat in the room for each player" };
        }
        this.seq = 0;
        this.setup = out;
      }
      if (msg.type === "end") this.ended = true;
      return { sends: [{ to: { except: id }, msg: out }] };
    }
    switch (msg.type) {
      case "event": {
        // The next shot or drop of the round, from the game that plays it.
        if (!this.setup) return { error: "the round hasn't started" };
        const owners = this.setup.owners;
        if (!Number.isInteger(msg.player) || msg.player < 0 || msg.player >= owners.length) return { error: "event needs a player" };
        if (owners[msg.player] !== m.seat) return { error: "that player isn't yours" };
        if (msg.seq !== this.seq) return { error: `expected event ${this.seq}` };
        if (msg.kind !== "shot" && msg.kind !== "drop") return { error: "events are shots or drops" };
        this.seq++;
        return { sends: [{ to: { except: id }, msg: { ...msg, from: m.seat } }] };
      }
      case "chat":
        if (!Number.isInteger(msg.id) || msg.id < 0 || msg.id >= QUICK_CHAT_COUNT) return { error: "unknown quick chat" };
        return { sends: [{ to: "all", msg: { type: "chat", id: msg.id, from: m.seat, name: m.name } }] };
      case "mismatch":
        // A player's game replayed a shot and got a different result: everyone
        // hears, and the round is marked "not agreed".
        return {
          sends: [{ to: "all", msg: { type: "mismatch", shot: msg.shot | 0, from: m.seat, name: m.name } }],
        };
      case "ping":
        return { sends: [{ to: id, msg: { type: "pong" } }] };
      default:
        return { error: `unknown message ${msg.type}` };
    }
  }
}
