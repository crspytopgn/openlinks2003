// Checks game_files.js against small synthetic disc images (no game data).
//   node game/web/tests/test_game_files.mjs
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));
globalThis.window = globalThis;
new Function(readFileSync(join(here, "..", "game_files.js"), "utf8"))();
const { collect, Disc, longNames } = window.olFiles;

const dir = mkdtempSync(join(tmpdir(), "olfiles-"));
const bytes = (s) => new Uint8Array([...s].map((c) => c.charCodeAt(0)));
const crz = new Uint8Array(5000).map((_, i) => (i * 7) & 0xff);

for (const raw of [false, true]) {
  const path = join(dir, raw ? "disc.b6i" : "disc.iso");
  execFileSync("python3", [join(here, "make_test_iso.py"), path, ...(raw ? ["--raw"] : [])]);
  const file = new File([readFileSync(path)], raw ? "disc.b6i" : "disc.iso");

  const disc = new Disc(file);
  assert.ok(await disc.open(), "finds the ISO volume");
  assert.equal(disc.size, raw ? 2352 : 2048);
  assert.equal(disc.pregap, raw ? 150 : 0);

  const entries = await collect([file], () => {});
  const byRel = Object.fromEntries(entries.map((e) => [e.rel, e]));
  assert.deepEqual(Object.keys(byRel).sort(), [
    "COURSES/TEST.CRZ",
    "OBJECT.LIB",
    "Object/Tall Trees/Tall Trees100.btx",
  ], "GAME files under their long names, videos skipped");
  const got = new Uint8Array(await byRel["COURSES/TEST.CRZ"].blob.arrayBuffer());
  assert.deepEqual(got, crz, "multi-sector file reads back intact");
  const btx = new Uint8Array(await byRel["Object/Tall Trees/Tall Trees100.btx"].blob.arrayBuffer());
  assert.equal(btx.length, 768);
  assert.equal(btx[255], 255);
}

// A picked folder from an install: paths are relative to the GAME folder.
const loose = [
  Object.assign(new File([bytes("lib")], "OBJECT.LIB"), { webkitRelativePath: "links2003/GAME/OBJECT.LIB" }),
  Object.assign(new File([bytes("crz")], "Cabo.crz"), { webkitRelativePath: "Links 2003/Courses/Cabo.crz" }),
  Object.assign(new File([bytes("x")], "Links.exe"), { webkitRelativePath: "Links 2003/Links.exe" }),
];
const fromFolder = (await collect(loose, () => {})).map((e) => e.rel).sort();
assert.deepEqual(fromFolder, ["Courses/Cabo.crz", "OBJECT.LIB"]);

assert.equal(longNames(bytes("P\0\0\0\x40\0game\\A\\B.X\0Long\\Name.x\0")).get("A/B.X"), "Long/Name.x");
console.log("game_files.js tests passed");
