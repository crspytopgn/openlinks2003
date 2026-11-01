// Checks text_input.js (the on-screen keyboard for the game's text boxes in
// phone and tablet browsers) against a tiny fake page.
//   node game/web/tests/test_text_input.mjs
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));

function fakeElement(tag) {
  const listeners = {};
  return {
    tag,
    style: {},
    attrs: {},
    value: "",
    focused: false,
    addEventListener(type, fn) {
      (listeners[type] ||= []).push(fn);
    },
    fire(type, e = {}) {
      for (const fn of listeners[type] || []) fn({ target: this, stopPropagation() {}, preventDefault() {}, ...e });
    },
    setAttribute(k, v) {
      this.attrs[k] = v;
    },
    removeAttribute(k) {
      delete this.attrs[k];
    },
    focus() {
      this.focused = true;
    },
    blur() {
      if (!this.focused) return;
      this.focused = false;
      this.fire("blur");
    },
    setSelectionRange() {},
    getBoundingClientRect() {
      // A 1280x720 game window drawn at half size, 10px down the page.
      return { left: 0, top: 10, width: 640, height: 360 };
    },
  };
}

const canvas = fakeElement("canvas");
const docListeners = {};
let created = null;
globalThis.window = globalThis;
globalThis.document = {
  getElementById: (id) => (id === "canvas" ? canvas : null),
  querySelector: () => canvas,
  createElement(tag) {
    created = fakeElement(tag);
    return created;
  },
  addEventListener(type, fn) {
    (docListeners[type] ||= []).push(fn);
  },
  body: { appendChild() {} },
};
new Function(readFileSync(join(here, "..", "text_input.js"), "utf8"))();

const replies = [];
window.olText.setCallback((json) => replies.push(JSON.parse(json)));
window.olText.setFields(
  JSON.stringify({
    w: 1280,
    h: 720,
    fields: [
      { id: 7, x: 100, y: 200, w: 400, h: 40, text: "Pebble", hint: "e.g.", secret: false, max: 0, numeric: false },
      { id: 9, x: 120, y: 210, w: 100, h: 20, text: "", hint: "", secret: false, max: 4, numeric: true },
    ],
  }),
);
const touch = (x, y) => {
  for (const fn of docListeners.touchend) fn({ target: canvas, changedTouches: [{ clientX: x, clientY: y }] });
};

// Field 7 is at (50, 110)-(250, 130) on the page; field 9 sits on top of it.
assert.equal(window.olText._hit(55, 112).id, 7);
assert.equal(window.olText._hit(65, 116).id, 9, "later fields are on top");
assert.equal(window.olText._hit(10, 10), null);

touch(200, 120);
assert.ok(created && created.focused, "a touch on a field focuses a page input");
assert.equal(window.olText._active(), 7);
assert.equal(created.value, "Pebble");
assert.equal(created.style.display, "block");
assert.ok(parseInt(created.style.fontSize) >= 16, "big enough that iOS doesn't zoom");

created.value = "Pebble Beach";
created.fire("input");
assert.deepEqual(replies.at(-1), { id: 7, kind: "change", text: "Pebble Beach" });
created.fire("keydown", { key: "Enter" });
assert.equal(replies.at(-2).kind, "submit");
assert.equal(replies.at(-1).kind, "done");
assert.equal(window.olText._active(), 0);
assert.equal(created.style.display, "none");

// A touch elsewhere closes it; a box that goes away closes it too.
touch(200, 120);
assert.equal(window.olText._active(), 7);
touch(600, 300);
assert.equal(window.olText._active(), 0);
touch(200, 120);
window.olText.setFields(JSON.stringify({ w: 1280, h: 720, fields: [] }));
assert.equal(window.olText._active(), 0);

// Number boxes keep their limit and keyboard.
window.olText.setFields(
  JSON.stringify({ w: 1280, h: 720, fields: [{ id: 9, x: 120, y: 210, w: 100, h: 20, text: "12", max: 4, numeric: true }] }),
);
touch(70, 120);
assert.equal(created.inputMode, "decimal");
assert.equal(created.maxLength, 4);
console.log("text_input.js tests passed");
