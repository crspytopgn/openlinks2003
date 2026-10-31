// Shared limits and checks for the online protocol (see server/README.md).
// Plain JavaScript with no dependencies, so `node --test` runs it as is.

export const PROTOCOL_VERSION = 1;
export const MAX_PLAYERS = 4;
// A room message: a shot or a whole round state for a late joiner.
export const MAX_MESSAGE_BYTES = 64 * 1024;
// A round record in a round played in your own time.
export const MAX_RECORD_BYTES = 256 * 1024;
// Room codes avoid letters that read alike (I, O).
export const CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ";
export const ROOM_CODE_LENGTH = 4;
export const GAME_ID_LENGTH = 8;
// Quick chat: the client shows the text for each id; nothing typed is sent.
export const QUICK_CHAT_COUNT = 8;

export function randomCode(length, random = Math.random) {
  let s = "";
  for (let i = 0; i < length; i++) {
    s += CODE_LETTERS[Math.floor(random() * CODE_LETTERS.length)];
  }
  return s;
}

export function isCode(text, length) {
  if (typeof text !== "string" || text.length !== length) return false;
  for (const c of text) {
    if (!CODE_LETTERS.includes(c)) return false;
  }
  return true;
}

// A display name: 1 to 20 letters, digits, spaces and a little punctuation.
export function cleanName(name) {
  if (typeof name !== "string") return null;
  const n = name.trim().replace(/\s+/g, " ");
  if (n.length < 1 || n.length > 20) return null;
  if (!/^[\p{L}\p{N} .'_-]+$/u.test(n)) return null;
  return n;
}

// A player's secret token (made by the game and kept in user://): 32 to 128
// URL-safe characters. The server only keeps its hash.
export function isToken(token) {
  return typeof token === "string" && /^[A-Za-z0-9_-]{32,128}$/.test(token);
}

export async function hashToken(token) {
  const bytes = new TextEncoder().encode(token);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// A 31-bit odd round seed, like GolfRound's.
export function randomSeed() {
  const a = new Uint32Array(1);
  crypto.getRandomValues(a);
  return (a[0] & 0x7fffffff) | 1;
}

export function byteLength(text) {
  return new TextEncoder().encode(text).length;
}
