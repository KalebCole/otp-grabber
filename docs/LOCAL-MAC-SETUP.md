# Local macOS app setup and acceptance run

This is the native macOS migration build of OTP Grabber. CI builds it and runs
its Swift tests. On the target Mac, the app has read fresh Messages codes across
two signed releases without changing Full Disk Access. Gmail and the remaining
live acceptance checks below still need confirmation. Keep the 0.1.0 source
agent and extension available until those checks pass.

## Prepare Gmail

1. Install the [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) on a
   machine where you can sign in to the Google account that owns the Cloud project.
   Sign in and select an existing project. Create a project only if you need one:

   ```bash
   gcloud auth login
   gcloud projects list
   gcloud projects create YOUR_UNIQUE_PROJECT_ID --name="OTP Grabber"
   gcloud config set project YOUR_UNIQUE_PROJECT_ID
   gcloud services enable gmail.googleapis.com
   gcloud services list --enabled --filter="name:gmail.googleapis.com"
   ```

   Skip the `projects create` command when using an existing project. `gcloud auth
   login` still opens a browser for Google account sign-in. The remaining project
   and API commands run in the terminal.
2. In the [Google Auth Platform](https://console.cloud.google.com/auth/overview),
   configure Branding, Audience, and Data Access for the account that will use the
   app. Add `https://www.googleapis.com/auth/gmail.readonly` to Data Access. If
   External and in Testing, add the account under test users.
3. This repository's **Desktop app** OAuth client is already included in the app.
   If using a different project or replacing that client, create a new Desktop app
   client on the [Clients page](https://console.cloud.google.com/auth/clients) and
   enter its ID in app Settings. Google's documented setup for this client and the
   consent screen uses the Cloud Console; the `gcloud iam oauth-clients` command
   creates a different kind of client and is not suitable for Gmail desktop access.
   Save the Desktop client's secret when Google shows it. Google's token endpoint
   requires that secret for this client even with PKCE. If it was not saved, use
   **Add Secret** on that client's details page to generate a replacement. The app
   uses a random local loopback port, PKCE, and the `gmail.readonly` scope. It
   stores the client secret and refresh token in Keychain. Do not put either in
   this repository or send them through chat.
4. If the consent screen is External and remains in Testing, expect refresh-token
   expiry after seven days and reconnect through the app. For long-term personal
   use, review Google's publishing and restricted-scope personal-use guidance.
5. Open the menu bar panel, choose Settings, paste the Desktop client secret into
   the secure field (or use **Paste secret from Clipboard**), and choose Connect
   Gmail. The app includes this project's
   desktop client ID by default; the field remains editable if the client changes.
   Finish consent in the default browser on the same Mac. The secret field can be
   left empty on later connections because the app reads it from Keychain.

   To skip the app's secret field, save the secret directly to the Mac's Keychain
   from Terminal. After copying only the secret value, run:

   ```bash
   cd "$HOME/Developer/otp-grabber-macos"
   swift scripts/import-gmail-client-secret.swift --clipboard
   ```

   If you have Google's downloaded Desktop client JSON file, use
   `swift scripts/import-gmail-client-secret.swift --file "/path/to/client_secret.json"`
   instead. The importer checks that the JSON client ID matches the app's saved
   client ID. Neither command prints the secret. The clipboard command clears the
   copied value after saving it if the clipboard has not changed. Then choose
   **Connect Gmail** in the app and complete consent in the browser on the same
   Mac. If macOS asks whether OTP Grabber may access the saved Keychain item,
   allow it.

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
scripts/install-menubar.sh --development
```

Development builds are ad hoc signed and may need a new Full Disk Access grant
after each update. For personal GitHub releases, follow
[personal release signing](../signing/README.md) once, then use the signed
release artifact with `scripts/install-menubar.sh "/path/to/OTP Grabber.app"`.
The installer validates the pinned signature and installs at
`~/Applications/OTP Grabber.app`. Self-signed builds are not notarized and may
require **Open Anyway** on a Mac that downloads them.

For issue #9's update check, record the macOS version, installed path, app
version, certificate fingerprint, designated requirement, and only the Messages
read result (`success`, `denied`, or `other`) before and after an update. Do not
touch the Full Disk Access setting between reads or record message contents,
senders, or codes. The first move away from ad hoc signing may require one new
grant; test retention between two subsequent releases signed with the same
identity. See [the research and check procedure](research/2026-10-16-issue-9-full-disk-access-updates.md).

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
      connected account. Test a message inside a multi-message thread. The link
      uses the source message ID; its behavior still needs live confirmation.
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
