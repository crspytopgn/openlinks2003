// Reads the player's own Links 2003 files in the browser and keeps them in
// IndexedDB, so the web build can use them without anything being uploaded.
// The player picks their disc images (BlindWrite .b6i/.b5i/.bwi, .iso, raw
// .bin, Nero .nrg, Alcohol .mdf) or a folder, on any drive,
// holding an installed or extracted copy. From disc images, the GAME folder is
// stored under the long names Setup would give it, as tools/cdimage/cdimage.py
// does. Godot loads this file with JavaScriptBridge.eval and talks to it
// through window.olFiles (see game/scripts/web/web_game_files.gd).
(() => {
  if (window.olFiles) return;

  const DB_NAME = "openlinks2003-game-files";
  const STORE = "files";
  const INDEX_KEY = "index";
  // Videos, programs and the help/lesson archives aren't used by the game.
  const SKIP = /\.(wmv|exe|dll|hlp|cnt|ini|inf|isu|ico)$/i;
  const SKIP_NAMES = new Set(["lessons.ls", "help.ls"]);

  // ---- IndexedDB -----------------------------------------------------------

  let dbPromise = null;
  function db() {
    if (!dbPromise) {
      dbPromise = new Promise((resolve, reject) => {
        const req = indexedDB.open(DB_NAME, 1);
        req.onupgradeneeded = () => req.result.createObjectStore(STORE);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
    }
    return dbPromise;
  }

  async function tx(mode, fn) {
    const d = await db();
    return new Promise((resolve, reject) => {
      const t = d.transaction(STORE, mode);
      const store = t.objectStore(STORE);
      const req = fn(store);
      t.oncomplete = () => resolve(req ? req.result : undefined);
      t.onerror = () => reject(t.error);
      t.onabort = () => reject(t.error);
    });
  }
  const put = (key, value) => tx("readwrite", (s) => s.put(value, key));
  const get = (key) => tx("readonly", (s) => s.get(key));
  const clearAll = () => tx("readwrite", (s) => s.clear());

  // ---- ISO 9660 in raw or cooked images ------------------------------------

  // Sector size and data offset: cooked, raw Mode 1, raw Mode 2 Form 1, and
  // raw with 96 bytes of subchannel data after each sector.
  const LAYOUTS = [[2048, 0], [2352, 16], [2352, 24], [2448, 16], [2448, 24]];
  const PREGAPS = [0, 150];
  // Disc images by extension, and the descriptor or subchannel files that sit
  // next to them (BlindWrite .b6t, cue sheets and so on), which aren't needed.
  const IMAGE = /\.(b6i|b5i|bwi|iso|bin|img|nrg|mdf)$/i;
  const DESCRIPTOR = /\.(b6t|b5t|bwt|bws|bwa|b6s|cue|mds|ccd|sub|toc)$/i;
  // How far into an image to look for the volume when the usual layouts
  // don't fit (other pregaps, a leading audio track, an image header).
  const SCAN_BYTES = 64 * 1024 * 1024;

  class Disc {
    constructor(file) {
      this.file = file;
    }

    async open() {
      for (const [size, header] of LAYOUTS) {
        for (const pregap of PREGAPS) {
          Object.assign(this, { size, header, pregap });
          const s = await this.sector(16);
          if (s.length >= 6 && String.fromCharCode(...s.subarray(1, 6)) === "CD001") return true;
        }
      }
      return this.scan();
    }

    // Looks for the primary volume descriptor anywhere in the first
    // SCAN_BYTES, then takes the layout and start that put it at sector 16.
    async scan() {
      const chunk = 4 * 1024 * 1024;
      const end = Math.min(this.file.size, SCAN_BYTES);
      for (let start = 0; start < end; start += chunk) {
        const buf = new Uint8Array(await this.file.slice(start, start + chunk + 8).arrayBuffer());
        for (let i = buf.indexOf(0x43); i >= 0 && i + 5 <= buf.length; i = buf.indexOf(0x43, i + 1)) {
          if (buf[i - 1] !== 1 || String.fromCharCode(...buf.subarray(i, i + 5)) !== "CD001") continue;
          const at = start + i - 1;
          for (const [size, header] of LAYOUTS) {
            const base = at - header - 16 * size;
            if (base < 0) continue;
            // Accept a layout if the next descriptor is where it says.
            Object.assign(this, { size, header, pregap: 0 });
            this.base = base;
            const next = await this.sector(17);
            if (String.fromCharCode(...next.subarray(1, 6)) === "CD001") return true;
          }
          this.base = 0;
        }
      }
      return false;
    }

    offset(lba) {
      return (this.base || 0) + (lba + this.pregap) * this.size + this.header;
    }

    async sector(lba) {
      const off = this.offset(lba);
      return new Uint8Array(await this.file.slice(off, off + 2048).arrayBuffer());
    }

    // A Blob of `length` bytes starting at `lba`. Nothing is read: a raw image
    // becomes a list of 2048-byte slices that skip the sector headers.
    blob(lba, length) {
      if (this.size === 2048) {
        const off = this.offset(lba);
        return this.file.slice(off, off + length);
      }
      const parts = [];
      for (let rest = length; rest > 0; rest -= 2048, lba++) {
        const off = this.offset(lba);
        parts.push(this.file.slice(off, off + Math.min(2048, rest)));
      }
      return new Blob(parts);
    }

    async read(lba, length) {
      return new Uint8Array(await this.blob(lba, length).arrayBuffer());
    }

    // Root directory record, preferring the Joliet (long name) tree.
    async root() {
      let primary = null;
      for (let lba = 16; lba < 32; lba++) {
        const d = await this.sector(lba);
        if (String.fromCharCode(...d.subarray(1, 6)) !== "CD001" || d[0] === 255) break;
        if (d[0] === 1 && !primary) primary = d.slice(156, 190);
        const esc = String.fromCharCode(d[88], d[89], d[90]);
        if (d[0] === 2 && ["%/@", "%/C", "%/E"].includes(esc)) return [d.slice(156, 190), true];
      }
      return [primary, false];
    }

    // [{path: "/GAME/X.LS", lba, size}] for every file on the disc.
    async files() {
      const [record, joliet] = await this.root();
      const out = [];
      await this.walk(record, joliet, "", out);
      return out;
    }

    async walk(record, joliet, prefix, out) {
      const view = new DataView(record.buffer, record.byteOffset, record.byteLength);
      const data = await this.read(view.getUint32(2, true), view.getUint32(10, true));
      let pos = 0;
      while (pos < data.length) {
        const len = data[pos];
        if (len === 0) {
          pos = (Math.floor(pos / 2048) + 1) * 2048; // records never cross sectors
          continue;
        }
        const rec = data.subarray(pos, pos + len);
        pos += len;
        const raw = rec.subarray(33, 33 + rec[32]);
        if (raw.length === 1 && raw[0] <= 1) continue; // "." and ".."
        let name = "";
        if (joliet) {
          for (let i = 0; i + 1 < raw.length; i += 2) name += String.fromCharCode((raw[i] << 8) | raw[i + 1]);
        } else {
          name = String.fromCharCode(...raw);
        }
        name = name.split(";")[0];
        const path = `${prefix}/${name}`;
        const rv = new DataView(rec.buffer, rec.byteOffset, rec.byteLength);
        if (rec[25] & 2) await this.walk(rec.slice(), joliet, path, out);
        else out.push({ path, lba: rv.getUint32(2, true), size: rv.getUint32(10, true) });
      }
    }
  }

  // Setup's table of disc paths to install paths (docs/formats/object-library.md):
  // u32 0x50, u16 length, "game\DIR\FILE" NUL, "Install\Path" NUL.
  function longNames(bytes) {
    let text = "";
    for (let i = 0; i < bytes.length; i += 65536) {
      text += String.fromCharCode.apply(null, bytes.subarray(i, i + 65536));
    }
    const names = new Map();
    const re = /P\x00\x00\x00[\s\S]{2}(game\\[^\x00]+)\x00([^\x00]+)\x00/g;
    let m;
    while ((m = re.exec(text)) !== null) {
      if (m[2].charCodeAt(0) < 32) continue;
      names.set(m[1].slice(5).replace(/\\/g, "/").toUpperCase(), m[2].replace(/\\/g, "/"));
    }
    return names;
  }

  // The course decoder reads its keys from the game executable.
  const KEEP = new Set(["linksm_1.exe", "linksmmiii.exe"]);

  function wanted(rel) {
    const base = rel.split("/").pop().toLowerCase();
    return KEEP.has(base) || (!SKIP.test(base) && !SKIP_NAMES.has(base));
  }

  // ---- Import ----------------------------------------------------------------

  // Collects {rel, blob} entries from the picked files: disc images are
  // opened and walked, anything else is taken as part of a game folder.
  async function collect(fileList, progress) {
    const discs = [];
    const loose = [];
    const unreadable = [];
    let descriptors = 0;
    for (const f of fileList) {
      if (IMAGE.test(f.name)) {
        const d = new Disc(f);
        progress("Reading " + f.name, 0, 0);
        if (await d.open()) discs.push({ disc: d, files: await d.files() });
        else unreadable.push(f.name);
      } else if (DESCRIPTOR.test(f.name)) {
        descriptors++;
      } else {
        loose.push(f);
      }
    }
    if (discs.length === 0 && loose.length === 0) {
      if (unreadable.length) throw new Error("Couldn't find the game's files inside " + unreadable.join(", "));
      if (descriptors) {
        throw new Error("Those are the small descriptor files (.b6t). Pick the big image files next to them " +
          "(.b6i), or pick the whole folder.");
      }
    }

    // CD2 has no SETUP.EXE, so take the long names from whichever disc has it.
    let names = new Map();
    for (const { disc, files } of discs) {
      const setup = files.find((e) => e.path.toUpperCase() === "/SETUP.EXE");
      if (setup) {
        names = longNames(await disc.read(setup.lba, setup.size));
        break;
      }
    }

    const out = [];
    for (const { disc, files } of discs) {
      for (const e of files) {
        if (!e.path.toUpperCase().startsWith("/GAME/")) continue;
        const short = e.path.slice(6);
        const rel = names.get(short.toUpperCase()) || short;
        if (wanted(rel)) out.push({ rel, blob: disc.blob(e.lba, e.size), size: e.size });
      }
    }
    for (const f of loose) {
      // "links2003/GAME/Courses/x.crz" or "Links 2003/Courses/x.crz" -> "Courses/x.crz"
      let rel = (f.webkitRelativePath || f.name).replace(/\\/g, "/");
      const game = rel.toUpperCase().indexOf("/GAME/");
      if (game >= 0) rel = rel.slice(game + 6);
      else if (rel.includes("/")) rel = rel.slice(rel.indexOf("/") + 1);
      if (wanted(rel)) out.push({ rel, blob: f, size: f.size });
    }
    return out;
  }

  async function importFiles(fileList, progress) {
    const entries = await collect(fileList, progress);
    if (entries.length === 0) throw new Error("No Links 2003 files found in the selection");
    const index = new Map((await get(INDEX_KEY)) || []);
    const total = entries.reduce((n, e) => n + e.size, 0);
    let done = 0;
    for (const e of entries) {
      progress(e.rel, done, total);
      await put("f:" + e.rel.toLowerCase(), e.blob);
      index.set(e.rel, e.size);
      done += e.size;
    }
    await put(INDEX_KEY, [...index.entries()]);
    blobs.clear();
    progress("", total, total);
    return index.size;
  }

  // ---- Reading -------------------------------------------------------------

  const blobs = new Map();
  async function blobFor(rel) {
    const key = "f:" + rel.toLowerCase();
    if (!blobs.has(key)) {
      const b = await get(key);
      if (!b) throw new Error("not imported: " + rel);
      blobs.set(key, b);
    }
    return blobs.get(key);
  }

  function pickFiles(directory) {
    return new Promise((resolve) => {
      const input = document.createElement("input");
      input.type = "file";
      input.multiple = true;
      if (directory) input.webkitdirectory = true;
      else input.accept = ".b6i,.b6t,.b5i,.b5t,.bwi,.bwt,.iso,.bin,.img,.nrg,.mdf";
      input.style.display = "none";
      input.addEventListener("change", () => {
        resolve(Array.from(input.files || []));
        input.remove();
      });
      input.addEventListener("cancel", () => {
        resolve([]);
        input.remove();
      });
      // Browsers without the cancel event: give up once the page has focus
      // again and nothing was chosen.
      window.addEventListener(
        "focus",
        () => setTimeout(() => (input.files && input.files.length ? null : resolve([])), 1500),
        { once: true }
      );
      document.body.appendChild(input);
      input.click();
    });
  }

  // Godot can't await promises, so every call reports back through a
  // callback made with JavaScriptBridge.create_callback.
  function report(promise, cb) {
    promise.then(
      (value) => cb(true, value),
      (err) => cb(false, String((err && err.message) || err))
    );
  }

  window.olFiles = {
    Disc,
    longNames,
    collect,
    importFiles,

    // pick(directory, progressCb, doneCb): doneCb(ok, countOrError).
    // progressCb(name, bytesDone, bytesTotal) is called as files are stored.
    pick(directory, progressCb, doneCb) {
      report(
        pickFiles(directory).then((files) =>
          files.length === 0 ? 0 : importFiles(files, (n, d, t) => progressCb(n, d, t))
        ),
        doneCb
      );
    },

    // list(cb): cb(ok, JSON of [[path, size], ...]).
    list(cb) {
      report(get(INDEX_KEY).then((idx) => JSON.stringify(idx || [])), cb);
    },

    // read(path, offset, length, cb): cb(ok, ArrayBuffer).
    read(path, offset, length, cb) {
      report(blobFor(path).then((b) => b.slice(offset, offset + length).arrayBuffer()), cb);
    },

    // forget(cb): removes everything imported.
    forget(cb) {
      blobs.clear();
      report(clearAll(), cb);
    },
  };
})();
