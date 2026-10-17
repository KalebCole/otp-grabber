# Local macOS OTP Grabber spec and plan

> The native app now ships. The remote agent and extension described below have
> been removed. Use the [README](../../README.md) for current setup.

## Product decision

Build one personal macOS menu bar app. Opening its panel checks Gmail and Messages, then copies the newest received verification code if it arrived within the last **five minutes**. Show which source and sender supplied it, its age, and a clear copied or error state. A Gmail code also has an **Open in Gmail** action that opens its source message in the browser. If neither source has an eligible code, leave the clipboard unchanged.

The panel has a collapsed history with simple **All**, **Gmail**, and **Messages** filters inside it. History holds source-tagged codes from the previous 24 hours; each card has a manual **Copy** button and an age label, including codes older than five minutes. Gmail history cards also have **Open in Gmail**. History is secondary to the single-click copy flow. There is no text search or authenticator-code generation.

Gmail cards may also represent password-reset emails. These show the sender and destination domain and provide an **Open reset link** button. A link opens in the default browser only when clicked. The app does not submit a new password or change Gmail state. The first version connects one Gmail account.

## Current state

- The repository already has a native AppKit status item, but it only calls the Python agent's `/v1/latest` endpoint, copies the result, and may acknowledge Gmail archive. Its menu contains a result line, Refresh, settings-file reveal, and Quit. See `menubar/Sources/OTPGrabberMenuBar/main.swift` and `menubar/Sources/OTPGrabberMenuBarCore/OTPGrabberMenuBarCore.swift`.
- The Python agent reads `~/Library/Messages/chat.db` through read-only SQLite and gets Gmail via the `gws` command. See `agent/otp_grabber/sources/messages.py` and `agent/otp_grabber/sources/gmail.py`.
- The shared extractor scores code-shaped text in verification context and rejects several common false positives. It can guide a Swift port, but its patterns need to be tested against real examples. See `agent/otp_grabber/extractor.py`.
- Current history is in process memory, capped at 20 records, and pruned at the same 10-minute cutoff as fresh codes. It cannot show yesterday's codes or survive a restart. See `agent/otp_grabber/service.py`.
- The Chrome extension has a collapsed recent list, but the native app has no code cards, source filters, or history. The existing remote agent, Tailscale setup, and Chrome packaging serve a different product direction.

## Architecture target

```text
Menu bar icon → native panel/controller → Gmail reader (OAuth + Gmail API)
                                  ↘ Messages reader (read-only chat.db)
                     both → normalized findings → code/link extraction
                                               → 24-hour local SQLite cache
                                               → five-minute copy selection
                                               → macOS pasteboard
```

Use the existing macOS 13+ Swift package as the starting point. Host a compact SwiftUI panel from the menu bar item, and put source access, extraction, selection, and persistence behind small testable Swift interfaces. The installed app itself owns the source reads; it needs no HTTP server, bearer token, Tailscale connection, Chrome extension, or Python runtime. Remove those old paths and update packaging/docs after native parity is verified.

**Messages:** Read the local database in SQLite read-only mode, preserving the current inbound-only and timestamp handling. Grant Full Disk Access to the signed app through System Settings during onboarding; the app must detect and explain denied access. `chat.db` is an Apple-owned implementation detail, so test the adapter against supported macOS versions and fail clearly if its schema changes. Never write to Messages' database.

**Gmail:** Use a desktop OAuth client in a Google Cloud project with Gmail API enabled. Use the installed-app authorization flow with PKCE, request `gmail.readonly`, and store the refresh token in macOS Keychain. Query recent likely code and password-reset messages, fetch the needed message bodies, parse MIME text/HTML, and extract codes or HTTPS reset links. Keep a source-message reference so **Open in Gmail** can open the exact email for a Gmail code; test the browser link against the connected account rather than assuming an API message ID is itself a working web URL. Keep OAuth/account setup inside the app. `gmail.readonly` is a restricted scope; Google's personal-use exception may avoid verification for this one-user app. An external project left in Testing issues seven-day refresh tokens, so setup instructions must address its publishing state and reconnection behavior. Do not request `gmail.modify`, archive mail, or retain full message bodies.

**Extraction and freshness:** These are *received* codes, not HOTP/TOTP secrets to calculate. Search candidate text for verification context and 4–8-character codes, reject dates, phone numbers, order IDs, URLs, and ambiguous candidates, and preserve source message ID, sender, received time, and code. Prefer high confidence to guessing. On panel open, refresh both sources concurrently, merge and deduplicate findings by source/message identity, then choose the newest valid code with `receivedAt` in `[now − 5 minutes, now]`. A source failure should not suppress a valid result from the other. Reset links never trigger automatic copy or open.

**Cache:** Keep only extracted codes and minimal display metadata in an app-owned SQLite database. Retain records for 24 hours, prune on open/refresh, and persist across restarts. Store reset links only as long as needed for the one-day list; never store entire emails or conversations. Keep the database private to the macOS user and the OAuth token in Keychain. Show older codes as old and require the history card's Copy button to copy them.

## Clipboard bug investigation

The checked-in Chrome path validates `code` as a nonempty string before calling clipboard write; the native client decodes a typed `String`. A literal `undefined` copied through either current path is **not reproduced from the checked-in code**. A stale installed extension, mismatched API response, or another copy caller remains possible; do not label one as the root cause without evidence.

1. On the current installed build, record its version, the `/v1/latest` response shape, the selected record, and the exact clipboard contents in a redacted local repro. Do not log actual passcodes or tokens.
2. Add a boundary check immediately before every copy: a selected code must be a nonempty validated value. On failure, preserve the prior clipboard and show an error.
3. In the new native flow, test malformed/missing code, empty results, source errors, and a successful copy. Remove the legacy extension copy path once the native app replaces it.

## Approved UI spec

Editable Figma prototype: https://www.figma.com/design/SqQbNjCtWNwEsNtXKtKLNy

The two frames show the normal menu bar panel after automatic copy and the expanded one-day history. They are visual prototypes, not running app screens. The default panel gives the copied code one clear focal point, offers **Open in Gmail** for a Gmail code, and keeps filters inside expanded history. It has no text search field or persistent connection-status footer.

The [interactive history preview](history-filter-preview.html) is the **approved reference for the history view**. It supersedes the clipped history filters in the Figma mockup. Its example codes and senders are illustrative, and its Gmail link is intentionally disconnected.

- Put **All**, **Gmail**, and **Messages** in one segmented control within expanded history. Each segment gets one equal-width column and a **36 px minimum height**, with enough padding for its label. No label, selected fill, or focus outline may be clipped.
- Show one clearly selected segment. **All** shows both sources; **Gmail** shows only Gmail findings; **Messages** shows only Messages findings. Update the visible list immediately when selection changes.
- Keep the source name on every finding, including when filtered. Show **Copy** on every code card and **Open in Gmail** only on Gmail code cards. Older codes require an explicit Copy click.
- Label the list **Last 24 hours**. If the selected source has no findings in that window, show a short source-specific empty state. Keep the segmented control keyboard reachable and expose its selected state to assistive technology.

## Build tasks

Complete tasks 1–8 before removing the old source agent and extension. The app's main copy flow is the first milestone; the one-day history can follow after that works on the MacBook.

| Task | Work | Done when |
| --- | --- | --- |
| 1. Lock behavior and investigate `undefined` | Capture the installed app/extension version and a redacted failing response; define sample code, non-code, reset-link, empty, and malformed messages. | The failure is reproduced or explicitly recorded as unreproduced, and the new copy boundary rejects missing values without changing the clipboard. |
| 2. Build the Swift domain core | Define code and reset-link findings, source identity, timestamps, extraction rules, deduplication, and five-minute selection. Port useful extractor cases from Python. | Fixtures cover Gmail and Messages codes, false positives, newer-code selection, and a code exactly at the cutoff. |
| 3. Read Messages locally | Move the read-only SQLite query into the native app and handle text/attributed bodies. Add a Full Disk Access setup state. | A real inbound test message produces a code; denied access shows an actionable explanation; Messages is never written. |
| 4. Connect one Gmail account | Add Google desktop OAuth with PKCE, `gmail.readonly`, Keychain token storage, refresh/reconnect handling, Gmail API message retrieval, and an exact source-message link. | A real code email is found, token refresh works, **Open in Gmail** opens that email, and copying leaves the email unchanged. |
| 5. Handle reset links | Find candidate links in recent Gmail MIME bodies, accept HTTPS links, and show sender plus destination domain before an explicit browser-open action. | A reset-link card opens the intended URL only when clicked and never triggers automatic copy. |
| 6. Orchestrate open-to-copy | Refresh both sources when the menu opens, tolerate one source failing, select the newest code no older than five minutes, and write only a validated code to `NSPasteboard`. | The main interaction works on the MacBook; no eligible code leaves the clipboard alone; success and partial-failure states are clear. |
| 7. Build the compact panel | Implement the simplified Figma layout with one copied-code state, Gmail source-message action, reset-link action, and unobtrusive settings. Keep All/Gmail/Messages filters inside expanded history. | The panel is usable from the menu bar icon at normal Mac display scaling and matches the agreed interaction without redundant copied or connection messages. |
| 8. Add one-day history | Persist minimal source-tagged findings in private local SQLite, prune after 24 hours, and implement the approved interactive history preview with manual Copy buttons. | History survives restart; filters show only their selected source without clipping; an old code is copied only by its own button. |
| 9. Package and onboard | Update the app icon, bundle, signing/notarization path, Gmail setup, Full Disk Access guidance, login behavior, and build scripts. | A clean install runs as one local app without Python, Chrome, an HTTP server, or Tailscale. |
| 10. Verify on the target Mac | Exercise Gmail and Messages independently and together, offline/auth/permission errors, reset links, clipboard contents, restart history, and launch at login. | Every acceptance check below passes on the MacBook. |
| 11. Remove the old architecture | Delete retired code and scripts, simplify tests/CI/releases, and rewrite product, security, and setup docs for the one-Mac design. | The repo has only the supported native product path and its build/test workflow passes. |

## What gets deleted or replaced

Delete these **after task 10 passes** so the working implementation remains available during migration:

| Path or feature | Disposition |
| --- | --- |
| `extension/` | Delete the Chrome popup, options page, assets, and JS tests. |
| `agent/` | Delete the Python HTTP agent and its tests after the Messages query and extractor behavior are ported to Swift. |
| `scripts/install-agent.sh`, `scripts/uninstall-agent.sh`, `scripts/serve-tailnet.sh`, `scripts/com.otpgrabber.agent.plist.template` | Delete the old LaunchAgent and network setup. |
| `menubar` HTTP `APIClient`, `ClientConfiguration`, `/v1/archive` call, and `client.json` setup | Replace with direct local readers, OAuth setup, and native clipboard orchestration. Keep and reshape the Swift package itself. |
| `package.json`, `package-lock.json`, `pyproject.toml`, `scripts/test-web.mjs` | Delete if no JS/Python web tooling remains after the site decision below. |
| `scripts/package-release.sh`, `Makefile`, `.github/workflows/verify.yml`, `.github/workflows/release.yml` | Rewrite for a single macOS app artifact and Swift checks; do not simply delete. |
| `README.md`, `PRODUCT.md`, `DESIGN.md`, `SECURITY.md`, `specs/acceptance.md`, `docs/ARCHITECTURE.md`, `docs/TROUBLESHOOTING.md` | Rewrite the parts that describe Chrome, the remote agent, Tailscale, and Gmail archiving. |

The GitHub Pages site in `docs/index.html`, `docs/app.js`, `docs/styles.css`, its social-card assets, `scripts/check-repository.sh` web checks, and `.github/workflows/pages.yml` advertise the old remote product. For a personal-only app, the recommended cleanup is to remove the site and Pages deployment, while keeping `docs/` for the new plan and setup notes. Keep `docs/BUILD-LOG.md` and the 2026-08-02 plan only if their historical record is useful; they must be clearly marked as superseded. Update `CHANGELOG.md` rather than deleting history.

## Acceptance checks

- Opening the app copies exactly the newest valid code from either source when it is at most five minutes old; opening it with no eligible code leaves the clipboard unchanged.
- Each source works when the other is unavailable. Permission and sign-in failures have understandable recovery actions.
- Expanded history matches the [approved preview](history-filter-preview.html): equal-width, at-least-36-px All/Gmail/Messages controls without clipping; source-matched lists; source-specific empty states; and source-tagged cards. It shows up to 24 hours of records after an app restart; old cards copy only when their Copy button is clicked. Gmail code cards open the exact source email only on **Open in Gmail**.
- A Gmail password-reset card opens its HTTPS link in the default browser only on explicit click and shows the destination domain. Gmail messages remain unchanged after code copy or link open.
- No malformed or absent code can write `undefined`, an empty string, or a placeholder to the clipboard.
- The installed app runs on the target Mac without a local server, Python, Chrome extension, or Tailscale.

## Source notes

- Apple documents menu bar window-style UI: https://developer.apple.com/documentation/swiftui/menubarextra
- Apple documents Full Disk Access for Messages data and the need for a user grant: https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac and https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- Google documents Gmail scopes, message listing and fetching, personal-use exceptions, and testing token expiry: https://developers.google.com/workspace/gmail/api/auth/scopes ; https://developers.google.com/workspace/gmail/api/guides/list-messages ; https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/get ; https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification ; https://developers.google.com/identity/protocols/oauth2
- Apple Keychain is suitable for small secrets such as refresh tokens: https://developer.apple.com/documentation/Security/keychain-services
