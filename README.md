# OTP Grabber

OTP Grabber is a native macOS menu bar app that finds recent verification codes
in Gmail and Messages on the same Mac, copies the newest eligible code, and
keeps one day of local history.

[Latest release](https://github.com/KalebCole/otp-grabber/releases/latest) ·
[Local Mac setup](docs/LOCAL-MAC-SETUP.md) ·
[Troubleshooting](docs/TROUBLESHOOTING.md) ·
[Architecture](docs/ARCHITECTURE.md)

## Install the native Mac app

The release app is built for an Apple silicon Mac. On the Mac where you use
Messages and Gmail:

1. Download `otp-grabber-menubar-macos-arm64.zip` from the
   [latest release](https://github.com/KalebCole/otp-grabber/releases/latest)
   and extract it.
2. Clone the repository if you do not already have it, then install the
   extracted app:

   ```bash
   git clone https://github.com/KalebCole/otp-grabber.git
   cd otp-grabber
   scripts/install-menubar.sh "/path/to/extracted/OTP Grabber.app"
   ```

   If you already have a checkout, run `git pull` there before the installer.
   The installer verifies the release signature before replacing the app,
   installs it at `~/Applications/OTP Grabber.app`, and starts it. It also
   registers the app to launch at login.
3. If macOS blocks this self-signed download, open **System Settings → Privacy
   & Security** and choose **Open Anyway** for OTP Grabber.
4. For Messages, add and enable the installed `~/Applications/OTP Grabber.app`
   under **System Settings → Privacy & Security → Full Disk Access**, then quit
   and reopen the app.
5. For Gmail, open the app's **Settings** and follow the
   [Gmail setup guide](docs/LOCAL-MAC-SETUP.md#prepare-gmail). The app uses a
   read-only Gmail OAuth connection. Gmail requires separate Google project
   setup; Messages can be used without connecting Gmail.

The native app runs locally on this Mac.

## Update

Updates are manual. Update this repository checkout, download and extract the
new macOS zip from its [GitHub release](https://github.com/KalebCole/otp-grabber/releases),
and run the same `scripts/install-menubar.sh` command with the new app bundle.
Keep the install path at `~/Applications/OTP Grabber.app`. The installer checks
the pinned signer and restores the previous app if the replacement cannot
launch.

Personal releases reuse one self-signed signing identity. They are **not
notarized** and may require **Open Anyway** on a new Mac. The first switch from
an older ad hoc signed build can require a new Full Disk Access grant. The
`v0.0.1` to `v0.0.2` update retained Messages access on the target Mac without
changing Full Disk Access; see the [test record](docs/research/2026-10-16-issue-9-full-disk-access-updates.md).
Release maintainers can read [personal release signing](signing/README.md).

## Known limits

- Gmail code copying and the remaining [live acceptance checks](docs/LOCAL-MAC-SETUP.md#live-acceptance-record)
  have not been confirmed on the target Mac. Messages reading and signed update
  access have been confirmed.
- Gmail credentials currently use the Mac's Keychain. The reported password
  prompt and request to remove that dependency are tracked in
  [issue #20](https://github.com/KalebCole/otp-grabber/issues/20).
- These releases are intended for personal use on your Macs and do not have an
  Apple Developer ID signature or notarization.

## Develop

On macOS with Swift installed:

```bash
make test
make check
scripts/build-menubar.sh
```

Local development builds are ad hoc signed. Use a tagged release for an app
that should keep the stable personal signing identity. `make package` requires
the personal signing identity.

## License

[MIT](LICENSE)
