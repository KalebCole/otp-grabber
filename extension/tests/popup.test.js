import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { JSDOM } from "jsdom";

const popupHtml = await readFile(new URL("../popup.html", import.meta.url), "utf8");
const tick = () => new Promise((resolve) => setTimeout(resolve, 0));
async function click(element) { element.click(); await tick(); }

async function loadPopup({ latest, history = [], clipboard, archiveCalls, deferLoad = false, throwDuringImport = false }) {
  const original = Object.fromEntries(["chrome", "document", "fetch", "navigator"].map((name) => [name, Object.getOwnPropertyDescriptor(globalThis, name)]));
  let window;
  const cleanup = () => {
    window?.close();
    for (const [name, descriptor] of Object.entries(original)) {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor);
      else delete globalThis[name];
    }
  };
  const replaceGlobal = (name, value) => Object.defineProperty(globalThis, name, { configurable: true, writable: true, value });
  try {
    const jsdom = new JSDOM(popupHtml);
    window = jsdom.window;
    const dom = window.document;
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
    if (deferLoad) await tick();
    else {
      await loaded;
      await tick();
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

test("popup harness loads the static popup markup from popup.html", async () => {
  const popup = await loadPopup({ latest: null, clipboard: async () => {}, archiveCalls: [] });
  try {
    assert.equal(popup.dom.querySelector("#title")?.textContent, "OTP Grabber");
    assert.equal(popup.dom.querySelector("#history-region")?.hidden, true);
  } finally {
    popup.cleanup();
  }
});

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
    const displayedCode = popup.dom.querySelector("#state .code").textContent;
    assert.equal(displayedCode, gmail.code);
    await click(popup.dom.querySelector("#state .code"));
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
    const manualCopy = click(popup.dom.querySelector("#state .code"));
    await tick();
    releaseClipboard();
    await manualCopy;
    await popup.loaded;
    await tick();
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
    await click(popup.dom.querySelector("#history-list button"));
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
    await click(popup.dom.querySelector("#history-list button"));
    const status = popup.dom.querySelector("#state .copy-status");
    assert.equal(status.textContent, "Code ready to copy");
    assert.ok(status.classList.contains("error-text"));
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
    await click(popup.dom.querySelector("#history-list button"));
    const status = popup.dom.querySelector("#history-region .copy-status");
    assert.equal(status.textContent, "Code ready to copy");
    assert.ok(status.classList.contains("error-text"));
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
    const status = popup.dom.querySelector("#state .copy-status");
    assert.equal(status.textContent, "Code ready to copy");
    assert.ok(status.classList.contains("error-text"));
    assert.deepEqual(archiveCalls, []);
  } finally {
    popup.cleanup();
  }
});
