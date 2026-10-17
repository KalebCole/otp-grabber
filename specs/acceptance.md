# Acceptance Criteria

> Historical acceptance criteria for the legacy remote setup. The current
> native Mac checks are in [local Mac setup](../docs/LOCAL-MAC-SETUP.md).

## Source agent

- Binds only to `127.0.0.1` on a configurable port.
- Requires a high-entropy bearer token and uses constant-time comparison.
- Exposes authenticated health, latest-code, history, and email-archive endpoints.
- Polls Gmail and Messages concurrently, returning freshest valid code across both sources plus per-source errors.
- Gmail retrieval uses `gws` with file keyring support and never commits credentials.
- Messages retrieval reads `~/Library/Messages/chat.db` read-only and handles `attributedBody`.
- Archives Gmail by removing the `INBOX` label only after a client explicitly acknowledges clipboard success.
- Archive endpoint is idempotent and accepts only Gmail message IDs returned by the latest/history APIs.
- Has rate limiting, bounded request bodies, safe integer parsing, generic unauthenticated errors, and no secrets in logs.
- Installs as a per-user LaunchAgent using generated paths and config under `~/Library/Application Support/OTP Grabber`.
- Remote setup uses Tailscale Serve only. Documentation explicitly rejects Funnel/public exposure.

## Chrome extension

- MV3 and deterministic extension ID.
- Stores server URL and token in `chrome.storage.local`, never source.
- Options/onboarding validates a tailnet HTTPS or loopback URL before saving.
- Popup polls both sources on open and selects the freshest code.
- Successful clipboard write triggers Gmail archive acknowledgment for Gmail results only.
- Archive failure never hides or removes the copied code.
- Calm Card states: loading, success, empty, partial, offline, history.
- History is hidden by default.
- No inline script, remote code, eval, or broad browsing permissions.

## macOS menu-bar app

- Native Swift/AppKit status-item app with no Dock icon.
- Reads configuration from `~/Library/Application Support/OTP Grabber/client.json`.
- Menu action and global popup fetch the freshest code, write it to NSPasteboard, then acknowledge Gmail archive.
- Shows success, empty, partial, offline, and setup states.
- Starts at login via a documented user LaunchAgent installer.
- Can be built and packaged with Command Line Tools only; no Xcode project required.

## Historical landing and release checks (retired)

- The former static GitHub Pages site in `docs/` has been retired.
- Mobile and desktop responsive, keyboard accessible, reduced-motion aware.
- CTA points to latest GitHub release and offers a copyable AI-agent setup prompt.
- Includes an honest local-first architecture diagram and permission disclosure.
- Impeccable `detect` passes with zero unwaived findings.
- GitHub Actions runs tests and builds client artifacts. Pages deployment has
  been retired.
- Public repository contains no personal hostname, email, phone, user path, token, private key, database, or log.

## End-to-end

- On the real MacBook, Chrome popup and menu-bar app each fetch a real recent test code from the Mac mini agent and copy it.
- If no live verification code is available, a locally injected test fixture exercises the exact production API/client path without modifying Gmail or Messages.
- Installed Chrome extension is visible in `chrome://extensions` and menu-bar process is running after launch.
