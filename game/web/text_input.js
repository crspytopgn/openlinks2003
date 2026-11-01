// Typing into the game's text boxes on phones and tablets in the browser.
//
// iOS (and some Android browsers) only show the on-screen keyboard when a
// real page input is focused inside the touch handler itself. Godot handles
// touches a frame later, so its LineEdits never get a keyboard there. Godot
// tells this file where its text boxes are (window.olText.setFields, in the
// game window's pixels); when a touch ends on one, a real <input> is put over
// it and focused at once, so the keyboard comes up. What is typed goes back
// to the LineEdit (see game/scripts/web/web_text_input.gd).
(() => {
  if (window.olText) return;

  let fields = []; // {id, x, y, w, h, text, hint, secret, max, numeric}
  let winW = 1;
  let winH = 1;
  let reply = null;
  let input = null;
  let activeId = 0;

  function canvas() {
    return document.getElementById("canvas") || document.querySelector("canvas");
  }

  function send(kind) {
    if (reply && activeId) {
      reply(JSON.stringify({ id: activeId, kind: kind, text: input.value }));
    }
  }

  function close() {
    if (!input || !activeId) return;
    send("done");
    activeId = 0;
    input.style.display = "none";
  }

  function ensureInput() {
    if (input) return input;
    input = document.createElement("input");
    input.type = "text";
    input.autocomplete = "off";
    input.setAttribute("autocorrect", "off");
    input.spellcheck = false;
    input.enterKeyHint = "done";
    input.style.cssText =
      "position:fixed;display:none;z-index:50;box-sizing:border-box;margin:0;" +
      "padding:0 8px;border:2px solid #8fd19e;border-radius:6px;outline:none;" +
      "background:#10241a;color:#fff;font-family:sans-serif;" +
      "-webkit-appearance:none;appearance:none";
    input.addEventListener("input", () => send("change"));
    input.addEventListener("keydown", (e) => {
      e.stopPropagation();
      if (e.key === "Enter") {
        e.preventDefault();
        send("submit");
        input.blur();
      }
    });
    input.addEventListener("keyup", (e) => e.stopPropagation());
    input.addEventListener("blur", close);
    document.body.appendChild(input);
    return input;
  }

  // Where field f is on the page, in CSS pixels.
  function place(f) {
    const c = canvas();
    if (!c) return null;
    const r = c.getBoundingClientRect();
    const sx = r.width / winW;
    const sy = r.height / winH;
    return { left: r.left + f.x * sx, top: r.top + f.y * sy, w: f.w * sx, h: f.h * sy };
  }

  function hit(x, y) {
    // Later fields are on top (Godot sends them in drawing order).
    for (let i = fields.length - 1; i >= 0; i--) {
      const p = place(fields[i]);
      if (p && x >= p.left && x <= p.left + p.w && y >= p.top && y <= p.top + p.h) {
        return fields[i];
      }
    }
    return null;
  }

  function position(f) {
    const p = place(f);
    if (!p) return;
    // At least 16px, or iOS zooms the page in on focus.
    const size = Math.max(16, Math.round(p.h * 0.5));
    const h = Math.max(p.h, size + 12);
    input.style.left = p.left + "px";
    input.style.top = p.top + (p.h - h) / 2 + "px";
    input.style.width = Math.max(p.w, 120) + "px";
    input.style.height = h + "px";
    input.style.fontSize = size + "px";
  }

  function open(f) {
    ensureInput();
    if (activeId && activeId !== f.id) close();
    activeId = f.id;
    input.type = f.secret ? "password" : "text";
    input.inputMode = f.numeric ? "decimal" : "text";
    input.placeholder = f.hint || "";
    if (f.max > 0) input.maxLength = f.max;
    else input.removeAttribute("maxlength");
    input.value = f.text || "";
    position(f);
    input.style.display = "block";
    // Inside the touch handler, so iOS shows the keyboard.
    input.focus();
    try {
      input.setSelectionRange(input.value.length, input.value.length);
    } catch (e) {
      // Some input types don't have a selection.
    }
  }

  function onTouchEnd(e) {
    if (input && e.target === input) return;
    const t = e.changedTouches && e.changedTouches[0];
    if (!t) return;
    const f = hit(t.clientX, t.clientY);
    if (f) open(f);
    // iOS doesn't blur an input when the canvas is tapped.
    else if (activeId) input.blur();
  }

  document.addEventListener("touchend", onTouchEnd, { capture: true, passive: true });

  window.olText = {
    setCallback(cb) {
      reply = cb;
    },
    // json: {w, h, fields: [...]}; positions are in the game window's pixels.
    setFields(json) {
      const data = JSON.parse(json);
      winW = Math.max(1, data.w);
      winH = Math.max(1, data.h);
      fields = data.fields || [];
      if (!activeId) return;
      const f = fields.find((g) => g.id === activeId);
      if (f) position(f);
      else input.blur(); // the box went away
    },
    // Test hooks.
    _hit: hit,
    _active: () => activeId,
  };
})();
