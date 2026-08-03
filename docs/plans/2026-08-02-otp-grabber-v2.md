# OTP Grabber v2 Implementation Plan

> **For Hermes:** Use subagent-driven development or an autonomous coding agent to implement this plan task by task. Enforce failing-test-first for behavior code and retain command output as evidence.

**Goal:** Ship a public, reusable macOS verification-code utility with a tailnet-only Apple source agent, Calm Card Chrome extension, native menu-bar app, and Impeccable-built GitHub Pages installer site.

**Architecture:** A Python standard-library source agent runs as a LaunchAgent on the Apple device that owns Gmail and Messages access. MacBook clients call its small authenticated JSON API through Tailscale Serve. Chrome and AppKit clients share the same behavioral contract: fetch freshest, copy, then acknowledge Gmail archive.

**Tech stack:** Python 3.11 stdlib, Chrome MV3 JavaScript/CSS, Swift 6 + AppKit/Foundation, static HTML/CSS/JS, unittest/node:test/Swift XCTest, GitHub Actions, Tailscale Serve, Impeccable CLI.

---

### Task 1: Repository and test harness

**Files:** create `.gitignore`, `LICENSE`, `README.md`, `Makefile`, `pyproject.toml`, `package.json`, `agent/tests/`, `extension/tests/`, `menubar/Tests/`.

1. Add empty test harnesses and CI-friendly commands.
2. Run each test command and record the expected no-tests or missing-module failure.
3. Add minimal package scaffolding.
4. Re-run until harnesses execute cleanly.
5. Commit.

### Task 2: Shared code extraction and source adapters

**Files:** create `agent/otp_grabber/extractor.py`, `agent/otp_grabber/sources/gmail.py`, `messages.py`, and focused tests.

1. Write failing extraction tests for explicit numeric/alphanumeric codes, code-first SMS, URLs, dates, addresses, order IDs, sequential digits, and typedstream bodies.
2. Implement minimal extraction logic and make tests pass.
3. Write failing adapter tests using real-shaped Gmail JSON and SQLite fixture rows.
4. Implement adapters with injected command/database dependencies.
5. Refactor only after full suite is green. Commit.

### Task 3: Freshest-code service and Gmail archive protocol

**Files:** create `agent/otp_grabber/service.py`, `models.py`, tests.

1. Test concurrent source polling, freshest ordering, partial failure, total failure, bounded history, and expired windows.
2. Implement service.
3. Test that archive is rejected for unknown/non-Gmail IDs, accepted once for returned Gmail IDs, and idempotent on retry.
4. Implement archive acknowledgment with Gmail `messages.modify` removing `INBOX`.
5. Full Python suite. Commit.

### Task 4: Authenticated localhost API and installer

**Files:** create `agent/otp_grabber/server.py`, `security.py`, `config.py`, API tests, `scripts/install-agent.sh`, `scripts/uninstall-agent.sh`, `scripts/serve-tailnet.sh`, plist template.

1. Test bearer auth, constant-time helper, malformed JSON, body cap, method/path allowlist, rate cap, CORS, and safe error responses.
2. Implement HTTP server bound to loopback.
3. Test config generation excludes secrets from source paths and produces mode-600 files.
4. Implement idempotent LaunchAgent install and Tailscale Serve helper.
5. Verify scripts with ShellCheck if available and dry-run modes. Commit.

### Task 5: Calm Card Chrome extension

**Files:** create `extension/manifest.json`, `src/api.js`, `src/model.js`, popup/options HTML/CSS/JS, icons, and node tests.

1. Test response normalization, freshest selection, partial/offline states, URL validation, and copy-then-archive ordering.
2. Implement pure model/API modules.
3. Build popup matching `DESIGN.md`: automatic fetch/copy, Gmail archive acknowledgment, hidden history, source warning, setup link.
4. Build options/onboarding with local storage and authenticated health test.
5. Add CSP/permission tests and deterministic manifest key. Commit.

### Task 6: Native macOS menu-bar app

**Files:** create `menubar/Package.swift`, sources for config, API, controller, status item, tests, `scripts/build-menubar.sh`, `scripts/install-menubar.sh`.

1. Write failing Swift tests for config parsing, latest response, freshness, partial errors, and archive request creation.
2. Implement model/API layer.
3. Implement `NSStatusItem`, menu states, copy-then-archive, refresh, settings reveal, and LSUIElement app packaging.
4. Build universal/local architecture `.app` with Command Line Tools, ad-hoc sign, zip.
5. Run XCTest and launch-process smoke test. Commit.

### Task 7: Impeccable landing page

**Files:** create `docs/index.html`, `docs/styles.css`, `docs/app.js`, social asset, `docs/404.html`, `PRODUCT.md`, `DESIGN.md`.

1. Install project-scoped Impeccable for GitHub Copilot.
2. Use `/impeccable shape` and `/impeccable craft` in Copilot with the product and design files.
3. Implement a single persuasive narrative: repeated code hunt, one-click handoff, private architecture, install/setup.
4. Add release CTA and copyable AI-agent setup prompt.
5. Run browser responsive/a11y checks plus `npx impeccable detect docs/`; fix every unwaived finding. Commit.

### Task 8: Documentation, CI, and release packaging

**Files:** create `.github/workflows/ci.yml`, `pages.yml`, `release.yml`, `SECURITY.md`, `CONTRIBUTING.md`, finish `README.md`.

1. Document one-Mac and Mac-mini-plus-MacBook setups without personal values.
2. Add permission table and threat boundaries.
3. Add CI for Python, JS, Swift-on-macOS, shell scripts, secret scan, and Impeccable.
4. Add deterministic extension and menu-bar release zips plus checksums.
5. Run all gates locally. Commit.

### Task 9: Real deployment and end-to-end verification

1. Install new source agent on Mac mini using existing Gmail/Messages access and a freshly generated token.
2. Configure a dedicated tailnet-only Tailscale Serve HTTPS port. Confirm Funnel is not enabled for this handler.
3. Install unpacked Chrome extension and menu-bar app on the online MacBook over Tailscale SSH.
4. Exercise exact production API from both clients with a real or injected test code.
5. Verify clipboard value, Gmail archive ordering in a non-destructive fixture, menu-bar process, Chrome extension presence, and launch-at-login registration.
6. Record installation receipts without secrets. Commit only generic docs.

### Task 10: Preserve legacy, publish, and configure GitHub

1. Rename existing private `KalebCole/otp-grabber` to `otp-grabber-legacy`; keep its original commit and set archived=true.
2. Create public `KalebCole/otp-grabber` from this clean history.
3. Push main and create a signed/tagged v2 release with verified artifacts.
4. Enable Pages from GitHub Actions, wait for deployment, fetch and inspect the live site.
5. Set repository description, homepage URL, topics, and security settings.
6. Run independent adversarial review against `specs/acceptance.md`, secret scan, remote repository, live Pages site, and installed MacBook runtime.
