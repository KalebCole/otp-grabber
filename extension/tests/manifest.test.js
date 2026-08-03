import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);

async function json(path) {
  return JSON.parse(await readFile(new URL(path, root), "utf8"));
}

test("manifest is MV3, keyed, and only requests private optional origins", async () => {
  const manifest = await json("manifest.json");
  assert.equal(manifest.manifest_version, 3);
  assert.match(manifest.key, /^MIIB/);
  assert.deepEqual(manifest.permissions, ["storage", "clipboardWrite"]);
  assert.deepEqual(manifest.host_permissions, []);
  assert.deepEqual(manifest.optional_host_permissions, [
    "https://*.ts.net/*",
    "http://127.0.0.1/*",
    "http://localhost/*",
  ]);
  assert.equal(manifest.action.default_popup, "popup.html");
  assert.ok(manifest.options_ui.open_in_tab);
});

test("options requests the selected origin and popup has no manual refresh chrome", async () => {
  const options = await readFile(new URL("src/options.js", root), "utf8");
  const popup = await readFile(new URL("popup.html", root), "utf8");
  assert.match(options, /chrome\.permissions\.request/);
  assert.doesNotMatch(popup, /id="refresh"|aria-label="Refresh code"/);
});

test("extension documents have external module scripts and restrictive CSP", async () => {
  const manifest = await json("manifest.json");
  assert.equal(manifest.content_security_policy.extension_pages, "script-src 'self'; object-src 'self'; base-uri 'self'");
  for (const page of ["popup.html", "options.html"]) {
    const content = await readFile(new URL(page, root), "utf8");
    assert.doesNotMatch(content, /<script(?![^>]+\bsrc=)/i, page);
    assert.doesNotMatch(content, /\bon\w+\s*=/i, page);
    assert.match(content, /<script\s+type="module"\s+src="[^"']+"/i, page);
  }
});
