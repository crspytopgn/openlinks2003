// The Durable Object behind one round played in your own time.

import { GameState } from "./game.js";
import { MAX_RECORD_BYTES, hashToken, isToken, randomSeed } from "./protocol.js";

// Rounds are kept for 30 days after their last shot.
const KEEP_MS = 30 * 24 * 60 * 60 * 1000;

export class GameObject {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.game = null;
    ctx.blockConcurrencyWhile(async () => {
      const data = await ctx.storage.get("game");
      if (data) this.game = new GameState(data);
    });
  }

  async fetch(request) {
    const url = new URL(request.url);
    const now = Date.now();
    if (request.method === "GET") {
      if (!this.game) return Response.json({ error: "no such round" }, { status: 404 });
      return Response.json(this.game.view());
    }
    const text = await request.text();
    if (text.length > MAX_RECORD_BYTES) return Response.json({ error: "too large" }, { status: 413 });
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      return Response.json({ error: "not JSON" }, { status: 400 });
    }
    if (!isToken(body.token)) return Response.json({ error: "missing player token" }, { status: 401 });
    const key = await hashToken(body.token);
    let out;
    if (url.pathname === "/create") {
      if (this.game) return Response.json({ error: "taken" }, { status: 409 });
      out = GameState.create(url.searchParams.get("id"), randomSeed(), now, key, body.name, body.conditions);
      if (out.game) this.game = out.game;
    } else if (!this.game) {
      return Response.json({ error: "no such round" }, { status: 404 });
    } else if (url.pathname === "/join") {
      out = this.game.join(key, body.name, now);
    } else if (url.pathname === "/record") {
      out = this.game.submit(key, body.record, now);
    } else {
      return Response.json({ error: "not found" }, { status: 404 });
    }
    if (out.error) return Response.json({ error: out.error }, { status: 400 });
    await this.ctx.storage.put("game", { ...this.game });
    await this.ctx.storage.setAlarm(now + KEEP_MS);
    return Response.json(this.game.view(false));
  }

  async alarm() {
    await this.ctx.storage.deleteAll();
    this.game = null;
  }
}
