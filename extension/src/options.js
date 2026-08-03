import { createApiClient } from "./api.js";
import { validateServerUrl } from "./model.js";

const form = document.querySelector("#settings-form");
const serverInput = document.querySelector("#server-url");
const tokenInput = document.querySelector("#token");
const status = document.querySelector("#form-status");
const button = form.querySelector("button");

function setStatus(message, kind = "") { status.textContent = message; status.className = `form-status ${kind}`; }

async function restore() {
  const settings = await chrome.storage.local.get(["serverUrl", "token"]);
  serverInput.value = settings.serverUrl || "";
  tokenInput.value = settings.token || "";
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const validated = validateServerUrl(serverInput.value);
  if (!validated.ok) return setStatus(validated.error, "error");
  const token = tokenInput.value.trim();
  if (!token) return setStatus("Enter your agent token.", "error");
  button.disabled = true; setStatus("Testing your private connection…");
  try {
    const permissionOrigin = `${new URL(validated.value).origin}/*`;
    const granted = await chrome.permissions.request({ origins: [permissionOrigin] });
    if (!granted) {
      setStatus("Allow access to this private agent address to continue.", "error");
      return;
    }
    const api = createApiClient({ serverUrl: validated.value, token });
    await api.health();
    await chrome.storage.local.set({ serverUrl: validated.value, token });
    setStatus("Connected and saved.", "success");
  } catch (error) {
    setStatus(error instanceof Error ? error.message : "Could not connect to the agent.", "error");
  } finally { button.disabled = false; }
});

restore();
