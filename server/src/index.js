// OpenLinks2003 online play: a Cloudflare Worker that routes to one Durable
// Object per live room and one per round played in your own time.
//
//   POST /rooms                    -> {code}          make a live room
//   GET  /rooms/CODE  (WebSocket)                     join it (see room.js)
//   POST /games  {token, name, conditions}  -> view   start a round in your own time
//   GET  /games/ID                          -> view   everyone's progress
//   POST /games/ID/join   {token, name}     -> view
//   POST /games/ID/record {token, record}   -> view   send your round so far
//
// See server/README.md.

import { GAME_ID_LENGTH, ROOM_CODE_LENGTH, isCode, randomCode } from "./protocol.js";
export { RoomObject } from "./room_object.js";
export { GameObject } from "./game_object.js";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

function withCors(response) {
  if (response.status === 101) return response;
  const r = new Response(response.body, response);
  for (const [k, v] of Object.entries(CORS)) r.headers.set(k, v);
  return r;
}

async function createIn(namespace, length, extra) {
  // A few tries in case a code is in use.
  for (let i = 0; i < 5; i++) {
    const code = randomCode(length);
    const stub = namespace.get(namespace.idFromName(code));
    const r = await stub.fetch(`https://do/create?code=${code}&id=${code}`, extra);
    if (r.status !== 409) return r;
  }
  return Response.json({ error: "try again" }, { status: 503 });
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean);
    let response;
    if (parts[0] === "rooms" && parts.length === 1 && request.method === "POST") {
      response = await createIn(env.ROOMS, ROOM_CODE_LENGTH, { method: "POST" });
    } else if (parts[0] === "rooms" && parts.length === 2 && isCode(parts[1], ROOM_CODE_LENGTH)) {
      response = await env.ROOMS.get(env.ROOMS.idFromName(parts[1])).fetch(request);
    } else if (parts[0] === "games" && parts.length === 1 && request.method === "POST") {
      const body = await request.text();
      response = await createIn(env.GAMES, GAME_ID_LENGTH, { method: "POST", body });
    } else if (parts[0] === "games" && parts.length >= 2 && isCode(parts[1], GAME_ID_LENGTH)) {
      const stub = env.GAMES.get(env.GAMES.idFromName(parts[1]));
      const action = parts[2] || "";
      response = await stub.fetch(new Request(`https://do/${action}`, request));
    } else if (url.pathname === "/") {
      response = Response.json({ name: "openlinks2003", version: 1 });
    } else {
      response = Response.json({ error: "not found" }, { status: 404 });
    }
    return withCors(response);
  },
};
