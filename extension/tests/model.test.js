import test from "node:test";
import assert from "node:assert/strict";

import {
  derivePopupState,
  normalizeHistoryResponse,
  normalizeLatestResponse,
  selectFreshest,
  validateServerUrl,
} from "../src/model.js";

const gmail = {
  id: "gmail-1",
  source: "gmail",
  code: "123456",
  sender: "Accounts",
  subject: "Your code",
  timestamp_ms: 1_700_000_000_000,
};

const messages = {
  ...gmail,
  id: "message-1",
  source: "messages",
  code: "654321",
  timestamp_ms: 1_700_000_010_000,
};

test("normalizes a valid latest response and orders its errors", () => {
  assert.deepEqual(normalizeLatestResponse({
    latest: gmail,
    errors: [
      { source: "messages", message: "database unavailable" },
      { source: "gmail", message: "timed out" },
    ],
  }), {
    latest: gmail,
    errors: [
      { source: "gmail", message: "timed out" },
      { source: "messages", message: "database unavailable" },
    ],
  });
});

test("rejects malformed code records instead of rendering unsafe data", () => {
  assert.throws(
    () => normalizeLatestResponse({ latest: { ...gmail, timestamp_ms: "now" }, errors: [] }),
    /timestamp_ms/,
  );
  assert.throws(
    () => normalizeLatestResponse({ latest: { ...gmail, source: "unknown" }, errors: [] }),
    /source/,
  );
});

test("normalizes history newest first and only retains valid records", () => {
  assert.deepEqual(normalizeHistoryResponse({ codes: [gmail, messages] }).codes, [messages, gmail]);
});

test("selects the freshest record across available source results", () => {
  assert.deepEqual(selectFreshest([gmail, messages]), messages);
  assert.equal(selectFreshest([]), null);
});

test("derives success, empty, partial, and offline popup states", () => {
  assert.equal(derivePopupState({ latest: gmail, errors: [] }).kind, "success");
  assert.equal(derivePopupState({ latest: gmail, errors: [{ source: "messages", message: "offline" }] }).kind, "partial");
  assert.equal(derivePopupState({ latest: null, errors: [] }).kind, "empty");
  assert.equal(derivePopupState({ latest: null, errors: [{ source: "gmail", message: "offline" }] }).kind, "offline");
});

test("accepts only loopback HTTP or HTTPS tailnet URLs without paths or credentials", () => {
  assert.deepEqual(validateServerUrl("http://127.0.0.1:8765"), { ok: true, value: "http://127.0.0.1:8765" });
  assert.deepEqual(validateServerUrl("https://otp-mini.example.ts.net/"), { ok: true, value: "https://otp-mini.example.ts.net" });
  for (const value of [
    "http://otp-mini.example.ts.net",
    "https://example.com",
    "https://user:pass@otp-mini.example.ts.net",
    "https://otp-mini.example.ts.net/api",
    "file:///tmp/config",
  ]) {
    assert.equal(validateServerUrl(value).ok, false, value);
  }
});
