// A live room: up to four players, one of them the host, who owns the round
// (docs/online-play.md, "Live rounds"). The server only relays and enforces
// who may send what; the golf runs in the players' games.
//
// RoomState is plain data plus pure methods, so it can be stored between
// messages (Durable Objects may sleep) and tested without Cloudflare.
// Each method returns a list of sends: {to, msg}, where `to` is a member id,
// "all", or {except: id}.

import { MAX_PLAYERS, QUICK_CHAT_COUNT, PROTOCOL_VERSION, cleanName } from "./protocol.js";

// Messages only the host sends, relayed to everyone else.
const HOST_ONLY = new Set(["setup", "turn", "result", "state", "end"]);

export class RoomState {
  constructor(code, data = null) {
    this.code = code;
    // {id, name, seat}
    this.members = [];
    this.host = 0;
    this.nextId = 1;
    // The seat whose shot the host is waiting for (from its last `turn`), or -1.
    this.turnSeat = -1;
    // The host's last `setup` and `state`, for players who join late or
    // reconnect.
    this.setup = null;
    this.state = null;
    this.ended = false;
    if (data) Object.assign(this, data);
  }

  toJSON() {
    const { code, members, host, nextId, turnSeat, setup, state, ended } = this;
    return { code, members, host, nextId, turnSeat, setup, state, ended };
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
      this.turnSeat = -1;
      sends.push({ to: "all", msg: { type: "host_left", name: m.name, host: this.host } });
    } else {
      sends.push({ to: "all", msg: { type: "left", name: m.name, seat: m.seat } });
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
      if (msg.type === "setup") this.setup = out;
      if (msg.type === "state") this.state = out;
      if (msg.type === "turn") {
        if (!Number.isInteger(msg.seat) || msg.seat < 0 || msg.seat >= MAX_PLAYERS) return { error: "turn needs a seat" };
        this.turnSeat = msg.seat;
      }
      if (msg.type === "result") this.turnSeat = -1;
      if (msg.type === "end") this.ended = true;
      return { sends: [{ to: { except: id }, msg: out }] };
    }
    switch (msg.type) {
      case "shot":
        // Only the player whose turn it is; it goes to the host, who runs it.
        if (this.turnSeat !== m.seat) return { error: "it isn't your turn" };
        if (fromHost) return { error: "the host plays its own shots" };
        return { sends: [{ to: this.host, msg: { ...msg, from: m.seat } }] };
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
