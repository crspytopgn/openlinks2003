// The Durable Object behind one live room. Uses the WebSocket Hibernation
// API, so an idle room costs nothing while players think about their shot.

import { RoomState } from "./room.js";
import { MAX_MESSAGE_BYTES } from "./protocol.js";

// Rooms nobody has used for this long are deleted.
const IDLE_MS = 6 * 60 * 60 * 1000;

export class RoomObject {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.room = null;
    ctx.blockConcurrencyWhile(async () => {
      const data = await ctx.storage.get("room");
      if (data) this.room = new RoomState(data.code, data);
    });
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/create") {
      if (this.room) return new Response("taken", { status: 409 });
      this.room = new RoomState(url.searchParams.get("code"));
      await this._save();
      return Response.json({ code: this.room.code });
    }
    if (!this.room) return new Response("no such room", { status: 404 });
    if (request.headers.get("Upgrade") !== "websocket") return new Response("expected a websocket", { status: 426 });
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    pair[1].serializeAttachment({ id: 0 });
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(ws, data) {
    if (typeof data !== "string" || data.length > MAX_MESSAGE_BYTES) {
      ws.send(JSON.stringify({ type: "error", reason: "message too large" }));
      return;
    }
    let msg;
    try {
      msg = JSON.parse(data);
    } catch {
      ws.send(JSON.stringify({ type: "error", reason: "not JSON" }));
      return;
    }
    const { id } = ws.deserializeAttachment() || { id: 0 };
    if (id === 0) {
      const joined = this.room.join(msg);
      if (joined.error) {
        ws.send(JSON.stringify({ type: "error", reason: joined.error }));
        ws.close(4000, joined.error.slice(0, 100));
        return;
      }
      ws.serializeAttachment({ id: joined.id });
      await this._deliver(joined.sends);
      return;
    }
    const out = this.room.message(id, msg);
    if (out.error) {
      ws.send(JSON.stringify({ type: "error", reason: out.error }));
      return;
    }
    await this._deliver(out.sends);
  }

  async webSocketClose(ws) {
    await this._gone(ws);
  }

  async webSocketError(ws) {
    await this._gone(ws);
  }

  async alarm() {
    if (this.ctx.getWebSockets().length === 0) {
      await this.ctx.storage.deleteAll();
      this.room = null;
    } else {
      await this.ctx.storage.setAlarm(Date.now() + IDLE_MS);
    }
  }

  async _gone(ws) {
    const { id } = ws.deserializeAttachment() || { id: 0 };
    if (id !== 0 && this.room) await this._deliver(this.room.leave(id));
  }

  async _deliver(sends) {
    const sockets = this.ctx.getWebSockets();
    const idOf = (ws) => (ws.deserializeAttachment() || { id: 0 }).id;
    for (const { to, msg } of sends) {
      const text = JSON.stringify(msg);
      for (const ws of sockets) {
        const id = idOf(ws);
        if (id === 0) continue;
        const hit = to === "all" || to === id || (typeof to === "object" && to.except !== id);
        if (hit) {
          try {
            ws.send(text);
          } catch {
            // closed; webSocketClose tidies up
          }
        }
      }
    }
    await this._save();
  }

  async _save() {
    await this.ctx.storage.put("room", this.room.toJSON());
    await this.ctx.storage.setAlarm(Date.now() + IDLE_MS);
  }
}
