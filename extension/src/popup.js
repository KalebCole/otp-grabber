import { copyThenAcknowledge, createApiClient } from "./api.js";
import { derivePopupState, relativeAge } from "./model.js";

const state = document.querySelector("#state");
const historyRegion = document.querySelector("#history-region");
const historyToggle = document.querySelector("#history-toggle");
const historyList = document.querySelector("#history-list");
let api;
let history = [];

function esc(value) { const span = document.createElement("span"); span.textContent = value; return span.innerHTML; }
function showLoading() { state.setAttribute("aria-busy", "true"); state.innerHTML = '<div class="spinner" aria-hidden="true"></div><p>Looking for your freshest code…</p>'; }
function showSetup(message = "Connect your private agent to find a code.") { state.setAttribute("aria-busy", "false"); state.innerHTML = `<p>${esc(message)}</p><a class="text-button" href="options.html" target="_blank">Open connection settings</a>`; }

function render(result) {
  state.setAttribute("aria-busy", "false");
  const view = derivePopupState(result);
  if (view.kind === "offline") return showSetup("Your agent is unavailable. Check the private connection.");
  if (view.kind === "empty") { state.innerHTML = '<p>No recent verification code was found.</p>'; return; }
  const { latest } = view;
  state.innerHTML = `<div class="success-panel"><p class="meta">${esc(latest.source === "gmail" ? "Gmail" : "Messages")} · ${esc(relativeAge(latest.timestamp_ms))}</p><div class="code" role="text" aria-label="Code ${esc(latest.code.split("").join(" "))}">${esc(latest.code)}</div><p class="meta">${esc(latest.sender || latest.subject || "Verification code")}</p><p class="copy-status">Copying…</p></div>${view.kind === "partial" ? `<p class="warning">${esc(view.errors.map((error) => `${error.source}: ${error.message}`).join(" · "))}</p>` : ""}`;
}
async function copyRecord(record) {
  await navigator.clipboard.writeText(record.code);
}

function renderHistory() {
  historyList.replaceChildren();
  for (const record of history) {
    const item = document.createElement("li"); const button = document.createElement("button");
    button.type = "button"; button.innerHTML = `<span class="history-code">${esc(record.code)}</span><span class="meta">${esc(relativeAge(record.timestamp_ms))}</span>`;
    button.addEventListener("click", async () => { await copyThenAcknowledge({ record, copy: copyRecord, archive: (id) => api.archive(id) }); });
    item.append(button); historyList.append(item);
  }
  historyRegion.hidden = history.length === 0;
}

async function load() {
  showLoading();
  const settings = await chrome.storage.local.get(["serverUrl", "token"]);
  if (!settings.serverUrl || !settings.token) return showSetup();
  try {
    api = createApiClient(settings);
    const latestResult = await api.latest();
    render(latestResult);
    if (latestResult.latest) {
      try {
        const outcome = await copyThenAcknowledge({ record: latestResult.latest, copy: copyRecord, archive: (id) => api.archive(id) });
        const copyStatus = state.querySelector(".copy-status");
        if (copyStatus) copyStatus.textContent = outcome.archive === "failed" ? "Copied — Gmail archive will retry next time." : "Copied to clipboard";
      } catch {
        const copyStatus = state.querySelector(".copy-status");
        if (copyStatus) { copyStatus.textContent = "Code ready to copy"; copyStatus.classList.add("error-text"); }
      }
    }
    try { history = (await api.history()).codes; renderHistory(); } catch { history = []; renderHistory(); }
  } catch { showSetup("Your agent is unavailable. Check the private connection."); }
}

historyToggle.addEventListener("click", () => { const open = historyToggle.getAttribute("aria-expanded") !== "true"; historyToggle.setAttribute("aria-expanded", String(open)); historyList.hidden = !open; });
load();
