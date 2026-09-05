import assert from "node:assert/strict";
import test from "node:test";

class Element {
  constructor(tagName = "div") {
    this.tagName = tagName;
    this.attributes = new Map();
    this.children = [];
    this.listeners = new Map();
    this.classNames = new Set();
    this.classList = { add: (name) => this.classNames.add(name) };
    this.hidden = false;
    this.textContent = "";
    this._innerHTML = "";
  }

  set innerHTML(value) {
    this._innerHTML = value;
    this.children = [];
    for (const className of ["copy-status", "code"]) {
      if (!value.includes(`class="${className}"`)) continue;
      const child = new Element(className === "code" ? "button" : "p");
      child.classNames.add(className);
      child.textContent = className === "copy-status" ? "Copying…" : value.match(new RegExp('<button class="code"[^>]*>([^<]+)</button>'))?.[1] ?? "";
      this.children.push(child);
    }
  }

  get innerHTML() { return this._innerHTML || this.textContent; }
  setAttribute(name, value) { this.attributes.set(name, String(value)); }
  getAttribute(name) { return this.attributes.get(name) ?? null; }
  replaceChildren(...children) { this.children = children; }
  append(child) { this.children.push(child); }
  addEventListener(type, listener) { this.listeners.set(type, listener); }
  async dispatch(type) { await this.listeners.get(type)?.(); }
  querySelector(selector) {
    if (!selector.startsWith(".")) return null;
    const className = selector.slice(1);
    for (const child of this.children) {
      if (child.classNames.has(className)) return child;
      const nested = child.querySelector(selector);
      if (nested) return nested;
    }
    return null;
  }
}

function popupDom() {
  const elements = new Map([
    ["#state", new Element()],
    ["#history-region", new Element()],
    ["#history-toggle", new Element("button")],
    ["#history-list", new Element("ul")],
  ]);
  return {
    querySelector(selector) { return elements.get(selector) ?? null; },
    createElement(tagName) { return new Element(tagName); },
    elements,
  };
}

async function loadPopup({ latest, history = [], clipboard, archiveCalls, deferLoad = false, throwDuringImport = false }) {
  const original = Object.fromEntries(["chrome", "document", "fetch", "navigator"].map((name) => [name, Object.getOwnPropertyDescriptor(globalThis, name)]));
  const cleanup = () => {
    for (const [name, descriptor] of Object.entries(original)) {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor);
      else delete globalThis[name];
    }
  };
  const replaceGlobal = (name, value) => Object.defineProperty(globalThis, name, { configurable: true, writable: true, value });
  try {
    const dom = popupDom();
    if (throwDuringImport) dom.querySelector = () => { throw new Error("popup setup failed"); };
    replaceGlobal("document", dom);
    replaceGlobal("chrome", { storage: { local: { get: async () => ({ serverUrl: "https://otp-mini.example.ts.net", token: "test-token" }) } } });
    replaceGlobal("navigator", { clipboard: { writeText: clipboard } });
    replaceGlobal("fetch", async (url, options) => ({
      ok: true,
      status: 200,
      async json() {
        if (url.endsWith("/v1/latest")) return { latest, errors: [] };
        if (url.endsWith("/v1/history")) return { codes: history };
        if (url.endsWith("/v1/archive")) { archiveCalls.push(JSON.parse(options.body).id); return { archived: true }; }
        throw new Error(`Unexpected URL: ${url}`);
      },
    }));
    const loaded = import(new URL(`../src/popup.js?test=${Date.now()}-${Math.random()}`, import.meta.url));
    if (deferLoad) await new Promise((resolve) => setTimeout(resolve, 0));
    else {
      await loaded;
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
    return { dom, loaded, cleanup };
  } catch (error) {
    cleanup();
    throw error;
  }
}

test("loadPopup restores mocked globals when module setup fails", async () => {
  const names = ["chrome", "document", "fetch", "navigator"];
  const original = Object.fromEntries(names.map((name) => [name, Object.getOwnPropertyDescriptor(globalThis, name)]));
  await assert.rejects(() => loadPopup({
    latest: null,
    clipboard: async () => {},
    archiveCalls: [],
    throwDuringImport: true,
  }), /popup setup failed/);
  for (const name of names) assert.deepEqual(Object.getOwnPropertyDescriptor(globalThis, name), original[name]);
});

const gmail = {
  id: "gmail-1",
  source: "gmail",
  code: "123456",
  sender: "Accounts",
  subject: "Your code",
  timestamp_ms: 1_700_000_000_000,
};

test("popup automatically copies the normalized newest code before archiving Gmail", async () => {
  const writes = [];
  const archiveCalls = [];
  const popup = await loadPopup({
    latest: gmail,
    clipboard: async (value) => { writes.push(value); },
    archiveCalls,
  });
  try {
    assert.deepEqual(writes, ["123456"]);
    assert.deepEqual(archiveCalls, ["gmail-1"]);
  } finally {
    popup.cleanup();
  }
});

test("popup result card manually copies the displayed code", async () => {
  const writes = [];
  const archiveCalls = [];
  const popup = await loadPopup({
    latest: gmail,
    clipboard: async (value) => { writes.push(value); },
    archiveCalls,
  });
  try {
    const displayedCode = popup.dom.elements.get("#state").querySelector(".code").textContent;
    assert.equal(displayedCode, gmail.code);
    await popup.dom.elements.get("#state").querySelector(".code").dispatch("click");
    assert.deepEqual(writes, [gmail.code, displayedCode]);
    assert.deepEqual(archiveCalls, [gmail.id, gmail.id]);
  } finally {
    popup.cleanup();
  }
});

test("manual click during automatic copy produces one clipboard write and Gmail archive", async () => {
  const writes = [];
  const archiveCalls = [];
  let releaseClipboard;
  let started;
  const clipboardStarted = new Promise((resolve) => { started = resolve; });
  const clipboard = async (value) => {
    writes.push(value);
    started();
    await new Promise((resolve) => { releaseClipboard = resolve; });
  };
  const popup = await loadPopup({ latest: gmail, clipboard, archiveCalls, deferLoad: true });
  try {
    await clipboardStarted;
    const manualCopy = popup.dom.elements.get("#state").querySelector(".code").dispatch("click");
    await new Promise((resolve) => setTimeout(resolve, 0));
    releaseClipboard();
    await manualCopy;
    await popup.loaded;
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.deepEqual(writes, [gmail.code]);
    assert.deepEqual(archiveCalls, [gmail.id]);
  } finally {
    popup.cleanup();
  }
});

test("popup history copies the selected normalized code", async () => {
  const writes = [];
  const archiveCalls = [];
  const historical = { ...gmail, id: "message-1", source: "messages", code: "654321" };
  const popup = await loadPopup({
    latest: { ...historical, id: "message-2", code: "777777" },
    history: [historical],
    clipboard: async (value) => { writes.push(value); },
    archiveCalls,
  });
  try {
    await popup.dom.elements.get("#history-list").children[0].children[0].dispatch("click");
    assert.deepEqual(writes, ["777777", "654321"]);
  } finally {
    popup.cleanup();
  }
});

test("popup history clipboard denial shows compact failure without archiving Gmail", async () => {
  const archiveCalls = [];
  const historical = { ...gmail, id: "gmail-history-1", code: "654321" };
  const popup = await loadPopup({
    latest: { ...gmail, id: "message-latest-1", source: "messages", code: "777777" },
    history: [historical],
    clipboard: async (value) => {
      if (value === historical.code) throw new Error("clipboard denied");
    },
    archiveCalls,
  });
  try {
    await popup.dom.elements.get("#history-list").children[0].children[0].dispatch("click");
    const status = popup.dom.elements.get("#state").querySelector(".copy-status");
    assert.equal(status.textContent, "Code ready to copy");
    assert.ok(status.classNames.has("error-text"));
    assert.deepEqual(archiveCalls, []);
  } finally {
    popup.cleanup();
  }
});

test("history clipboard denial is visible when no latest code is available", async () => {
  const archiveCalls = [];
  const historical = { ...gmail, id: "gmail-history-1", code: "654321" };
  const popup = await loadPopup({
    latest: null,
    history: [historical],
    clipboard: async () => { throw new Error("clipboard denied"); },
    archiveCalls,
  });
  try {
    await popup.dom.elements.get("#history-list").children[0].children[0].dispatch("click");
    const status = popup.dom.elements.get("#history-region").querySelector(".copy-status");
    assert.equal(status.textContent, "Code ready to copy");
    assert.ok(status.classNames.has("error-text"));
    assert.deepEqual(archiveCalls, []);
  } finally {
    popup.cleanup();
  }
});

test("popup never copies missing code values from an invalid API response", async () => {
  for (const code of [undefined, null, "", "   "]) {
    const writes = [];
    const archiveCalls = [];
    const popup = await loadPopup({
      latest: { ...gmail, code },
      clipboard: async (value) => { writes.push(value); },
      archiveCalls,
    });
    try {
      assert.deepEqual(writes, [], `code=${String(code)}`);
      assert.deepEqual(archiveCalls, [], `code=${String(code)}`);
    } finally {
      popup.cleanup();
    }
  }
});

test("popup shows compact copy failure without archiving Gmail", async () => {
  const archiveCalls = [];
  const popup = await loadPopup({
    latest: gmail,
    clipboard: async () => { throw new Error("clipboard denied"); },
    archiveCalls,
  });
  try {
    const status = popup.dom.elements.get("#state").querySelector(".copy-status");
    assert.equal(status.textContent, "Code ready to copy");
    assert.ok(status.classNames.has("error-text"));
    assert.deepEqual(archiveCalls, []);
  } finally {
    popup.cleanup();
  }
});
