// Part of face_calibration.sh: runs game/web/face_photo.js (MediaPipe's Face
// Landmarker) in headless Chromium on the rendered faces face_0.png ...
// in a folder and writes their landmarks to landmarks.json there.
// Usage: node face_calibration.mjs <folder>
import { createRequire } from "node:module";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const dir = path.resolve(process.argv[2]);
const script = path.join(path.dirname(fileURLToPath(import.meta.url)), "../../game/web/face_photo.js");
const faces = fs.readdirSync(dir).filter((f) => /^face_\d+\.png$/.test(f)).length;

const server = http.createServer((req, res) => {
  const name = req.url.split("?")[0].slice(1);
  if (name === "") {
    res.writeHead(200, { "Content-Type": "text/html" });
    return res.end('<!doctype html><script src="face_photo.js"></script>');
  }
  const file = name === "face_photo.js" ? script : path.join(dir, path.basename(name));
  if (!fs.existsSync(file)) {
    res.writeHead(404);
    return res.end();
  }
  res.writeHead(200, { "Content-Type": file.endsWith(".js") ? "text/javascript" : "image/png" });
  fs.createReadStream(file).pipe(res);
});
await new Promise((resolve) => server.listen(0, resolve));
const browser = await chromium.launch();
const page = await browser.newPage();
await page.goto(`http://localhost:${server.address().port}/`);
const out = [];
for (let i = 0; i < faces; i++) {
  const [ok, value] = await page.evaluate(
    (url) =>
      new Promise((resolve) =>
        window.olFace.useUrl(url, (ok, v) => (ok ? window.olFace.find((ok2, v2) => resolve([ok2, v2])) : resolve([ok, v]))),
      ),
    `face_${i}.png`,
  );
  out.push(ok ? JSON.parse(value).points : []);
  if (!ok) console.error(`face_${i}: ${value}`);
}
fs.writeFileSync(path.join(dir, "landmarks.json"), JSON.stringify(out));
console.log(`found ${out.filter((p) => p.length).length} of ${faces} faces`);
await browser.close();
server.close();
