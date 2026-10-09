# Local macOS app setup and acceptance run

This is the migration build of OTP Grabber. It has not passed a macOS build or the
live acceptance run below. Keep the 0.1.0 source agent and extension available until
the native app passes every check.

## Prepare Gmail

1. In a Google Cloud project, enable the Gmail API and configure an OAuth consent
   screen for the account that will use this app.
2. Create a **Desktop app** OAuth client. Copy its client ID. The app uses a random
   local loopback port, PKCE, and the `gmail.readonly` scope. It stores the refresh
   token in Keychain. Do not put the client secret or a token in this repository.
3. If the consent screen is External and remains in Testing, expect refresh-token
   expiry after seven days and reconnect through the app. For long-term personal
   use, review Google's publishing and restricted-scope personal-use guidance.
4. Open the menu bar panel, choose Settings, enter the desktop client ID, and choose
   Connect Gmail. Finish consent in the default browser.

Google's [desktop OAuth guide](https://developers.google.com/identity/protocols/oauth2/native-app)
describes the loopback redirect and PKCE. The [Gmail scope list](https://developers.google.com/workspace/gmail/api/auth/scopes)
classifies `gmail.readonly` as restricted.

## Prepare Messages

1. Install the signed app at its final path. Moving it later may require granting
   access again.
2. In System Settings, open Privacy & Security, then Full Disk Access. Add and enable
   `OTP Grabber.app`.
3. Quit and reopen the app. Send a fresh inbound test code to Messages. The app
   reads `~/Library/Messages/chat.db` in SQLite read-only mode.

## Build and install on the Mac

```bash
swift test --package-path menubar
swift run --package-path menubar OTPGrabberMenuBarChecks
scripts/build-menubar.sh
scripts/install-menubar.sh
```

The current build script uses ad-hoc signing. A stable Developer ID signature and
notarization still need to be set up before distributing the native app.

## Live acceptance record

Record the app version and redact all live codes, message text, OAuth tokens, and
reset links in the evidence. Check each item on the installed app:

- [ ] A Gmail code and a Messages code are each found independently.
- [ ] With both sources available, the newest received code within five minutes is
      copied. A code exactly five minutes old is eligible.
- [ ] No eligible code leaves the previous clipboard contents unchanged. Missing,
      empty, malformed, and `undefined` values cannot be copied.
- [ ] One source failing does not hide a valid code from the other. Full Disk Access,
      offline, and sign-in failures show useful recovery text.
- [ ] A Gmail code's **Open in Gmail** action opens the exact source email in the
      connected account. Test a message inside a multi-message thread. The current
      URL is based on the Gmail thread ID and is not yet verified for that case.
- [ ] Copy and browser actions leave Gmail labels, including Inbox, unchanged.
- [ ] A reset card shows sender and HTTPS destination domain. Its link opens only
      after **Open reset link** is clicked.
- [ ] History survives an app restart, expires after 24 hours, filters by source,
      and copies an older code only from its own **Copy** button.
- [ ] At normal Mac display scaling, the three history filters have equal widths,
      at least 36-point height, no clipping, keyboard focus, and an announced
      selected state.
- [ ] Launch at login works and the installed app needs no Python, Chrome extension,
      HTTP source server, or Tailscale process.
