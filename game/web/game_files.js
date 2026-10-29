// Reads the player's own Links 2003 files in the browser, so the web build
// can use them without anything being uploaded. The player picks their disc
// images (BlindWrite .b6i/.b5i/.bwi, .iso, raw .bin, Nero .nrg, Alcohol .mdf)
// or a folder, on any drive, holding an installed or extracted copy.
//
// Nothing is copied: picking only walks the discs' directories and builds an
// index of where each GAME file sits (under the long names Setup would give
// it, as tools/cdimage/cdimage.py does). Files are read straight from the
// picked images when the game asks for them. Where the browser has the File
// System Access API (Chrome, Edge), the picked files are remembered for next
// time and the browser only asks to allow access again; elsewhere the player
// picks them again on each visit, which takes seconds.
//
// Godot loads this file with JavaScriptBridge.eval and talks to it through
// window.olFiles (see game/scripts/web/web_game_files.gd).
(() => {
  if (window.olFiles) return;

  const DB_NAME = "openlinks2003-files-v2";
  const OLD_DB_NAME = "openlinks2003-game-files"; // held whole copies; deleted on start
  const STORE = "state";
  // Videos, programs and the help/lesson archives aren't used by the game.
  const SKIP = /\.(wmv|exe|dll|hlp|cnt|ini|inf|isu|ico|idb|pdb|sbr)$/i;
  const SKIP_NAMES = new Set(["lessons.ls", "help.ls"]);
  // The course decoder reads its keys from the game executable.
  const KEEP = new Set(["linksm_1.exe", "linksmmiii.exe"]);

  // ---- IndexedDB (only the index and file handles, never file contents) ----

  let dbPromise = null;
  function db() {
    if (!dbPromise) {
      dbPromise = new Promise((resolve, reject) => {
        if (typeof indexedDB === "undefined") return reject(new Error("no IndexedDB"));
        indexedDB.deleteDatabase(OLD_DB_NAME);
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
      const req = fn(t.objectStore(STORE));
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
    constructor(file, layout) {
      this.file = file;
      this.base = 0;
      if (layout) Object.assign(this, layout);
    }

    get layout() {
      return { size: this.size, header: this.header, pregap: this.pregap, base: this.base };
    }

    async open() {
      for (const [size, header] of LAYOUTS) {
        for (const pregap of PREGAPS) {
          Object.assign(this, { size, header, pregap, base: 0 });
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
            Object.assign(this, { size, header, pregap: 0, base });
            const next = await this.sector(17);
            if (String.fromCharCode(...next.subarray(1, 6)) === "CD001") return true;
          }
          this.base = 0;
        }
      }
      return false;
    }

    offset(lba) {
      return this.base + (lba + this.pregap) * this.size + this.header;
    }

    async sector(lba) {
      const off = this.offset(lba);
      return new Uint8Array(await this.file.slice(off, off + 2048).arrayBuffer());
    }

    // `length` bytes of data starting `start` bytes into the extent at `lba`.
    // A raw image is read in one contiguous slice, and the sector headers and
    // error-correction bytes are skipped in memory.
    async read(lba, length, start = 0) {
      if (length <= 0) return new Uint8Array(0);
      const first = lba + Math.floor(start / 2048);
      const skip = start % 2048;
      if (this.size === 2048) {
        const off = this.offset(first) + skip;
        return new Uint8Array(await this.file.slice(off, off + length).arrayBuffer());
      }
      const count = Math.ceil((skip + length) / 2048);
      const from = this.offset(first);
      const raw = new Uint8Array(await this.file.slice(from, from + count * this.size).arrayBuffer());
      const out = new Uint8Array(length);
      let pos = 0;
      for (let s = 0; s < count && pos < length; s++) {
        const a = s * this.size + (s === 0 ? skip : 0);
        const n = Math.min(length - pos, s * this.size + 2048 - a);
        out.set(raw.subarray(a, a + n), pos);
        pos += n;
      }
      return out;
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

  function wanted(rel) {
    const base = rel.split("/").pop().toLowerCase();
    return KEEP.has(base) || (!SKIP.test(base) && !SKIP_NAMES.has(base));
  }

  // "links2003/GAME/Courses/x.crz" or "Links 2003/Courses/x.crz" -> "Courses/x.crz"
  function folderRel(path) {
    const rel = path.replace(/\\/g, "/");
    const game = rel.toUpperCase().indexOf("/GAME/");
    if (game >= 0) return rel.slice(game + 6);
    return rel.includes("/") ? rel.slice(rel.indexOf("/") + 1) : rel;
  }

  // ---- Sources and the index -----------------------------------------------
  //
  // A source is something the player picked: a disc image or a loose file,
  // with its File System Access handle when the browser has one. The index
  // maps each game file's relative path to [source id, lba, size] for a file
  // on a disc, or [source id, -1, size] for a loose file.

  let index = new Map();
  const opened = new Map(); // source id -> Disc for an image, File otherwise

  // Indexes picked files, given as [{file, handle?, path}] where path is the
  // file's path inside a picked folder ("" for single files). Returns
  // {sources, entries} and opens the sources.
  async function collect(picked, progress) {
    const found = [];
    const loose = [];
    const unreadable = [];
    let descriptors = 0;
    for (const p of picked) {
      const name = p.file.name;
      if (IMAGE.test(name)) {
        const d = new Disc(p.file);
        progress("Reading " + name, 0, 0);
        if (await d.open()) found.push({ p, disc: d, files: await d.files() });
        else unreadable.push(name);
      } else if (DESCRIPTOR.test(name)) {
        descriptors++;
      } else {
        loose.push(p);
      }
    }
    if (found.length === 0 && loose.length === 0) {
      if (unreadable.length) throw new Error("Couldn't find the game's files inside " + unreadable.join(", "));
      if (descriptors) {
        throw new Error("Those are the small descriptor files (.b6t). Pick the big image files next to them " +
          "(.b6i), or pick the whole folder.");
      }
    }

    // CD2 has no SETUP.EXE, so take the long names from whichever disc has it.
    let names = new Map();
    for (const { disc, files } of found) {
      const setup = files.find((e) => e.path.toUpperCase() === "/SETUP.EXE");
      if (setup) {
        names = longNames(await disc.read(setup.lba, setup.size));
        break;
      }
    }

    opened.clear();
    const sources = [];
    const entries = [];
    for (const { p, disc, files } of found) {
      const id = sources.length;
      sources.push({ id, kind: "disc", layout: disc.layout, handle: p.handle || null });
      opened.set(id, disc);
      for (const e of files) {
        if (!e.path.toUpperCase().startsWith("/GAME/")) continue;
        const short = e.path.slice(6);
        const rel = names.get(short.toUpperCase()) || short;
        if (wanted(rel)) entries.push([rel, [id, e.lba, e.size]]);
      }
    }
    for (const p of loose) {
      const rel = folderRel(p.path || p.file.name);
      if (!wanted(rel)) continue;
      const id = sources.length;
      sources.push({ id, kind: "file", handle: p.handle || null });
      opened.set(id, p.file);
      entries.push([rel, [id, -1, p.file.size]]);
    }
    return { sources, entries };
  }

  // Makes the picked files the current game files, and remembers them when
  // the browser gave a handle for each.
  async function importPicked(picked, progress) {
    const { sources, entries } = await collect(picked, progress);
    if (entries.length === 0) throw new Error("No Links 2003 files found in the selection");
    index = new Map(entries);
    if (sources.every((src) => src.handle)) {
      try {
        await put("sources", sources);
        await put("index", entries);
      } catch (e) {
        // Remembering is a convenience; the files still work this visit.
      }
    }
    progress("", 1, 1);
    return index.size;
  }

  // Reopens remembered files. Returns "ready", "reconnect" (the browser
  // needs the player's OK to read them again), "denied" or "empty".
  async function restore(ask) {
    if (index.size && opened.size) return "ready";
    let sources, entries;
    try {
      sources = await get("sources");
      entries = await get("index");
    } catch (e) {
      return "empty";
    }
    if (!sources || !entries || !sources.length) return "empty";
    for (const src of sources) {
      const perm = ask
        ? await src.handle.requestPermission({ mode: "read" })
        : await src.handle.queryPermission({ mode: "read" });
      if (perm !== "granted") return ask ? "denied" : "reconnect";
    }
    opened.clear();
    try {
      for (const src of sources) {
        const file = await src.handle.getFile();
        opened.set(src.id, src.kind === "disc" ? new Disc(file, src.layout) : file);
      }
    } catch (e) {
      // Moved, renamed or on a drive that isn't plugged in.
      opened.clear();
      throw new Error("Couldn't open your game files where they were last time (" + e.message + ")");
    }
    index = new Map(entries);
    return "ready";
  }

  async function readFile(rel, offset, length) {
    const entry = index.get(rel);
    if (!entry) throw new Error("not loaded: " + rel);
    const [id, lba, size] = entry;
    const src = opened.get(id);
    if (!src) throw new Error("the game files need to be picked again");
    const n = Math.max(0, Math.min(length, size - offset));
    if (lba < 0) return new Uint8Array(await src.slice(offset, offset + n).arrayBuffer());
    return src.read(lba, n, offset);
  }

  // ---- Picking -------------------------------------------------------------

  const ACCEPT = [".b6i", ".b6t", ".b5i", ".b5t", ".bwi", ".bwt", ".iso", ".bin", ".img", ".nrg", ".mdf"];

  async function walkDirectory(dir, prefix, out) {
    for await (const [name, handle] of dir.entries()) {
      const path = prefix + "/" + name;
      if (handle.kind === "directory") await walkDirectory(handle, path, out);
      else out.push({ file: await handle.getFile(), handle, path });
    }
  }

  // [{file, handle?, path}] from the File System Access pickers when the
  // browser has them, otherwise from an <input type=file>.
  async function pickFiles(directory) {
    try {
      if (directory && window.showDirectoryPicker) {
        const dir = await window.showDirectoryPicker({ id: "links2003", mode: "read" });
        const out = [];
        await walkDirectory(dir, dir.name, out);
        return out;
      }
      if (!directory && window.showOpenFilePicker) {
        const handles = await window.showOpenFilePicker({
          id: "links2003",
          multiple: true,
          types: [{ description: "Links 2003 disc images", accept: { "application/octet-stream": ACCEPT } }],
        });
        return Promise.all(handles.map(async (handle) => ({ file: await handle.getFile(), handle, path: "" })));
      }
    } catch (e) {
      if (e && e.name === "AbortError") return [];
      throw e;
    }
    const files = await pickWithInput(directory);
    return files.map((file) => ({ file, path: file.webkitRelativePath || "" }));
  }

  function pickWithInput(directory) {
    return new Promise((resolve) => {
      const input = document.createElement("input");
      input.type = "file";
      input.multiple = true;
      if (directory) input.webkitdirectory = true;
      else input.accept = ACCEPT.join(",");
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
    importPicked,
    readFile,

    // True when picked files are remembered between visits.
    remembers: !!(window.showOpenFilePicker && window.showDirectoryPicker),

    // pick(directory, progressCb, doneCb): doneCb(ok, countOrError).
    pick(directory, progressCb, doneCb) {
      report(
        pickFiles(directory).then((picked) =>
          picked.length === 0 ? 0 : importPicked(picked, (n, d, t) => progressCb(n, d, t))
        ),
        doneCb
      );
    },

    // state(cb): cb(ok, "ready" | "reconnect" | "empty").
    state(cb) {
      report(restore(false), cb);
    },

    // reconnect(cb): asks the browser for permission to read the remembered
    // files again (call it from a click). cb(ok, "ready" | "denied" | "empty").
    reconnect(cb) {
      report(restore(true), cb);
    },

    // list(cb): cb(ok, JSON of [[path, size], ...]) for the current files.
    list(cb) {
      report(Promise.resolve(JSON.stringify([...index].map(([rel, e]) => [rel, e[2]]))), cb);
    },

    // read(path, offset, length, cb): cb(ok, ArrayBuffer).
    read(path, offset, length, cb) {
      report(readFile(path, offset, length).then((bytes) => bytes.buffer), cb);
    },

    // forget(cb): forgets the picked files.
    forget(cb) {
      opened.clear();
      index = new Map();
      report(clearAll().catch(() => undefined), cb);
    },
  };
})();
