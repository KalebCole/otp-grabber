import test from "node:test";
import assert from "node:assert/strict";

import { copyThenAcknowledge, createApiClient } from "../src/api.js";

const latest = {
  id: "gmail-1",
  source: "gmail",
  code: "123456",
  sender: "Accounts",
  subject: "Your code",
  timestamp_ms: 1_700_000_000_000,
};

function response(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async json() { return body; },
  };
}

test("API client uses authenticated exact endpoints and normalizes responses", async () => {
  const calls = [];
  const api = createApiClient({
    serverUrl: "https://otp-mini.example.ts.net",
    token: "test-token",
    fetchFn: async (url, options) => {
      calls.push({ url, options });
      return response({ latest, errors: [] });
    },
  });

  assert.deepEqual(await api.latest(), { latest, errors: [] });
  assert.deepEqual(calls, [{
    url: "https://otp-mini.example.ts.net/v1/latest",
    options: {
      method: "GET",
      headers: { Authorization: "Bearer test-token", Accept: "application/json" },
      signal: undefined,
    },
  }]);
});

test("API client uses the agent health endpoint", async () => {
  const calls = [];
  const api = createApiClient({
    serverUrl: "https://otp-mini.example.ts.net",
    token: "test-token",
    fetchFn: async (url, options) => {
      calls.push({ url, options });
      return response({ ok: true });
    },
  });

  assert.deepEqual(await api.health(), { ok: true });
  assert.equal(calls[0].url, "https://otp-mini.example.ts.net/v1/health");
});

test("API client sends archive acknowledgement only for explicit IDs", async () => {
  const calls = [];
  const api = createApiClient({
    serverUrl: "http://127.0.0.1:8765/",
    token: "test-token",
    fetchFn: async (url, options) => {
      calls.push({ url, options });
      return response({ id: "gmail-1", archived: true, already_archived: false });
    },
  });

  await api.archive("gmail-1");
  assert.deepEqual(calls[0], {
    url: "http://127.0.0.1:8765/v1/archive",
    options: {
      method: "POST",
      headers: {
        Authorization: "Bearer test-token",
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: '{"id":"gmail-1"}',
      signal: undefined,
    },
  });
});

test("copy succeeds before Gmail archive starts", async () => {
  const events = [];
  const outcome = await copyThenAcknowledge({
    record: latest,
    copy: async (code) => { events.push(`copy:${code}`); },
    archive: async (id) => { events.push(`archive:${id}`); },
  });
  assert.deepEqual(events, ["copy:123456", "archive:gmail-1"]);
  assert.deepEqual(outcome, { copied: true, archive: "acknowledged" });
});

test("copy failure never archives and archive failure preserves copied result", async () => {
  const events = [];
  await assert.rejects(() => copyThenAcknowledge({
    record: latest,
    copy: async () => { throw new Error("clipboard denied"); },
    archive: async () => { events.push("archive"); },
  }), /clipboard denied/);
  assert.deepEqual(events, []);

  const outcome = await copyThenAcknowledge({
    record: latest,
    copy: async () => { events.push("copy"); },
    archive: async () => { throw new Error("archive unavailable"); },
  });
  assert.deepEqual(events, ["copy"]);
  assert.equal(outcome.copied, true);
  assert.equal(outcome.archive, "failed");
  assert.match(outcome.archiveError, /archive unavailable/);
});

test("Messages results copy without archive acknowledgement", async () => {
  const events = [];
  const outcome = await copyThenAcknowledge({
    record: { ...latest, id: "message-1", source: "messages" },
    copy: async () => { events.push("copy"); },
    archive: async () => { events.push("archive"); },
  });
  assert.deepEqual(events, ["copy"]);
  assert.equal(outcome.archive, "not-applicable");
});

test("API client emits a safe error for failed responses", async () => {
  const api = createApiClient({
    serverUrl: "https://otp-mini.example.ts.net",
    token: "test-token",
    fetchFn: async () => response({ detail: "token should not surface" }, 401),
  });
  await assert.rejects(() => api.health(), /Server request failed \(401\)/);
});
