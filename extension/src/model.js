const VALID_SOURCES = new Set(["gmail", "messages"]);

function normalizeRecord(value) {
  if (!value || typeof value !== "object") {
    throw new TypeError("code record must be an object");
  }
  const record = {
    id: stringField(value.id, "id"),
    source: stringField(value.source, "source"),
    code: stringField(value.code, "code"),
    sender: optionalString(value.sender),
    subject: optionalString(value.subject),
    timestamp_ms: value.timestamp_ms,
  };
  if (!VALID_SOURCES.has(record.source)) {
    throw new TypeError("code record source is invalid");
  }
  if (!Number.isSafeInteger(record.timestamp_ms) || record.timestamp_ms < 0) {
    throw new TypeError("code record timestamp_ms must be a non-negative integer");
  }
  return record;
}

function stringField(value, name) {
  if (typeof value !== "string" || !value.trim()) {
    throw new TypeError(`code record ${name} must be a non-empty string`);
  }
  return value.trim();
}

function optionalString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeErrors(value) {
  if (!Array.isArray(value)) {
    throw new TypeError("errors must be an array");
  }
  return value.map((error) => {
    if (!error || typeof error !== "object") throw new TypeError("source error must be an object");
    return { source: stringField(error.source, "error source"), message: stringField(error.message, "error message") };
  }).sort((a, b) => a.source.localeCompare(b.source));
}

export function normalizeLatestResponse(value) {
  if (!value || typeof value !== "object") throw new TypeError("latest response must be an object");
  return { latest: value.latest === null ? null : normalizeRecord(value.latest), errors: normalizeErrors(value.errors) };
}

export function normalizeHistoryResponse(value) {
  if (!value || typeof value !== "object" || !Array.isArray(value.codes)) {
    throw new TypeError("history response must contain a codes array");
  }
  return { codes: value.codes.map(normalizeRecord).sort((a, b) => b.timestamp_ms - a.timestamp_ms) };
}

export function selectFreshest(records) {
  return records.reduce((freshest, record) => !freshest || record.timestamp_ms > freshest.timestamp_ms ? record : freshest, null);
}

export function derivePopupState(result) {
  const { latest, errors } = normalizeLatestResponse(result);
  if (latest && errors.length) return { kind: "partial", latest, errors };
  if (latest) return { kind: "success", latest, errors: [] };
  if (errors.length) return { kind: "offline", latest: null, errors };
  return { kind: "empty", latest: null, errors: [] };
}

export function validateServerUrl(rawValue) {
  if (typeof rawValue !== "string" || !rawValue.trim()) return { ok: false, error: "Enter your agent URL." };
  try {
    const url = new URL(rawValue.trim());
    const hostname = url.hostname.toLowerCase();
    const loopback = hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1";
    const tailnet = hostname.endsWith(".ts.net");
    if ((loopback && url.protocol !== "http:" && url.protocol !== "https:") || (tailnet && url.protocol !== "https:")) {
      return { ok: false, error: "Loopback uses HTTP(S); tailnet addresses require HTTPS." };
    }
    if (!loopback && !tailnet) return { ok: false, error: "Use a loopback or tailnet HTTPS URL." };
    if (url.username || url.password || (url.pathname !== "/") || url.search || url.hash) {
      return { ok: false, error: "Use only the agent origin, without a path or credentials." };
    }
    return { ok: true, value: url.origin };
  } catch {
    return { ok: false, error: "Enter a valid URL." };
  }
}

export function relativeAge(timestampMs, nowMs = Date.now()) {
  const seconds = Math.max(0, Math.floor((nowMs - timestampMs) / 1000));
  if (seconds < 60) return "just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  return `${Math.floor(seconds / 3600)}h ago`;
}
