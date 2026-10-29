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
const { collect, importPicked, readFile, Disc, longNames } = window.olFiles;
const pick = (files) => files.map((file) => ({ file, path: file.webkitRelativePath || "" }));
const rels = async (files) => (await collect(pick(files), () => {})).entries.map((e) => e[0]).sort();

const dir = mkdtempSync(join(tmpdir(), "olfiles-"));
const bytes = (s) => new Uint8Array([...s].map((c) => c.charCodeAt(0)));
const crz = new Uint8Array(5000).map((_, i) => (i * 7) & 0xff);

// [name, make_test_iso.py flags, sector size]: cooked, BlindWrite raw, raw
// with subchannel data, and an odd pregap that only the scan finds.
const layouts = [
  ["disc.iso", [], 2048],
  ["disc.b6i", ["--raw"], 2352],
  ["sub.b6i", ["--raw", "--sub"], 2448],
  ["odd.bin", ["--raw", "--pregap", "37"], 2352],
];
for (const [name, flags, size] of layouts) {
  const path = join(dir, name);
  execFileSync("python3", [join(here, "make_test_iso.py"), path, ...flags]);
  const file = new File([readFileSync(path)], name);

  const disc = new Disc(file);
  assert.ok(await disc.open(), `finds the ISO volume in ${name}`);
  assert.equal(disc.size, size);

  // Nothing is stored (no IndexedDB here): the files are read from the image.
  assert.equal(await importPicked(pick([file]), () => {}), 3);
  assert.deepEqual(await rels([file]), [
    "COURSES/TEST.CRZ",
    "OBJECT.LIB",
    "Object/Tall Trees/Tall Trees100.btx",
  ], "GAME files under their long names, videos skipped");
  assert.deepEqual(await readFile("COURSES/TEST.CRZ", 0, 1 << 20), crz, "multi-sector file reads back intact");
  for (const [start, len] of [[0, 1], [2047, 2], [2000, 3000], [4095, 905], [4999, 10]]) {
    assert.deepEqual(await readFile("COURSES/TEST.CRZ", start, len), crz.subarray(start, start + len),
      `range ${start}+${len} across sector boundaries in ${name}`);
  }
  const btx = await readFile("Object/Tall Trees/Tall Trees100.btx", 0, 4096);
  assert.equal(btx.length, 768);
  assert.equal(btx[255], 255);
}

// A picked folder from an install: paths are relative to the GAME folder.
const loose = [
  Object.assign(new File([bytes("lib")], "OBJECT.LIB"), { webkitRelativePath: "links2003/GAME/OBJECT.LIB" }),
  Object.assign(new File([bytes("crz")], "Cabo.crz"), { webkitRelativePath: "Links 2003/Courses/Cabo.crz" }),
  Object.assign(new File([bytes("x")], "Links.exe"), { webkitRelativePath: "Links 2003/Links.exe" }),
];
assert.deepEqual(await rels(loose), ["Courses/Cabo.crz", "OBJECT.LIB"]);
await importPicked(pick(loose), () => {});
assert.deepEqual(await readFile("Courses/Cabo.crz", 1, 10), bytes("rz"), "loose files read directly");

// Picking only the BlindWrite descriptors says which files to pick instead.
await assert.rejects(collect(pick([new File([bytes("BWT5")], "Links CD1.b6t")]), () => {}), /\.b6i/);
// An image the reader can't make sense of is named.
await assert.rejects(collect(pick([new File([new Uint8Array(100000)], "blank.iso")]), () => {}), /blank\.iso/);

assert.equal(longNames(bytes("P\0\0\0\x40\0game\\A\\B.X\0Long\\Name.x\0")).get("A/B.X"), "Long/Name.x");
console.log("game_files.js tests passed");
