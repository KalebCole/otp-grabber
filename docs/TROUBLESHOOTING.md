# Troubleshooting

The signed app installs at `~/Applications/OTP Grabber.app`. If its icon does
not appear in the menu bar, check that the app is installed and that its login
launch agent exists at
`~/Library/LaunchAgents/com.otpgrabber.menubar.plist`. Reinstall with
`scripts/install-menubar.sh "/path/to/extracted/OTP Grabber.app"` if needed.

## Messages access is denied

Enable the installed `~/Applications/OTP Grabber.app` in **System Settings →
Privacy & Security → Full Disk Access**, then quit and reopen it. Grant access
to this installed copy, since moving or replacing a differently signed app can
require a new grant. The app reads the local Messages database without changing
it.

## Gmail is not connected

Open the app's **Settings** and follow [Gmail setup](LOCAL-MAC-SETUP.md#prepare-gmail).
The app uses a read-only Gmail OAuth connection. If a Keychain password prompt
appears, see [issue #20](https://github.com/KalebCole/otp-grabber/issues/20).

## A downloaded app is blocked by macOS

These personal releases are self-signed and not notarized. For a release you
trust, use **System Settings → Privacy & Security → Open Anyway**. Install it
at the same path with `scripts/install-menubar.sh`; the installer checks the
pinned signer before replacing the existing app.

## No recent code appears

Try a fresh verification message, then open the menu bar panel again. A code
older than five minutes is not eligible for automatic copying. If one source
is unavailable, the panel should show a recovery message while still using
results from the other source. See the [live acceptance checklist](LOCAL-MAC-SETUP.md#live-acceptance-record)
for behavior that still needs confirmation on the target Mac.
