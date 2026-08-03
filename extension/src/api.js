import { normalizeHistoryResponse, normalizeLatestResponse, validateServerUrl } from "./model.js";

function safeOrigin(serverUrl) {
  const validated = validateServerUrl(serverUrl);
  if (!validated.ok) throw new TypeError(validated.error);
  return validated.value;
}

async function request(fetchFn, url, options) {
  let response;
  try {
    response = await fetchFn(url, options);
  } catch {
    throw new Error("Could not reach your OTP Grabber agent.");
  }
  if (!response.ok) throw new Error(`Server request failed (${response.status}).`);
  try {
    return await response.json();
  } catch {
    throw new Error("The agent returned an invalid response.");
  }
}

export function createApiClient({ serverUrl, token, fetchFn = fetch }) {
  const origin = safeOrigin(serverUrl);
  if (typeof token !== "string" || !token.trim()) throw new TypeError("Enter your agent token.");
  const headers = { Authorization: `Bearer ${token.trim()}`, Accept: "application/json" };
  const get = (path, signal) => request(fetchFn, `${origin}${path}`, { method: "GET", headers, signal });
  return {
    async health(signal) { return request(fetchFn, `${origin}/v1/health`, { method: "GET", headers, signal }); },
    async latest(signal) { return normalizeLatestResponse(await get("/v1/latest", signal)); },
    async history(signal) { return normalizeHistoryResponse(await get("/v1/history", signal)); },
    async archive(id, signal) {
      if (typeof id !== "string" || !id.trim()) throw new TypeError("Archive id is required.");
      return request(fetchFn, `${origin}/v1/archive`, {
        method: "POST",
        headers: { ...headers, "Content-Type": "application/json" },
        body: JSON.stringify({ id: id.trim() }),
        signal,
      });
    },
  };
}

export async function copyThenAcknowledge({ record, copy, archive }) {
  await copy(record.code);
  if (record.source !== "gmail") return { copied: true, archive: "not-applicable" };
  try {
    await archive(record.id);
    return { copied: true, archive: "acknowledged" };
  } catch (error) {
    return { copied: true, archive: "failed", archiveError: error instanceof Error ? error.message : "Archive acknowledgement failed." };
  }
}
