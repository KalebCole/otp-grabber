# OTP Grabber

> The native macOS app is installed on the target Mac and has read Messages
> successfully across a signed update. Gmail and the remaining live checks are
> still in progress. The Python agent and Chrome extension remain available.
> See [local Mac setup and acceptance](docs/LOCAL-MAC-SETUP.md).

**The fresh verification code, already copied.**

The native macOS app reads Gmail and Messages on your Mac and copies the newest
eligible code. The older Python agent and Chrome extension can also hand off
codes over your private Tailscale network.

[Website](https://kalebcole.github.io/otp-grabber/) · [Latest release](https://github.com/KalebCole/otp-grabber/releases/latest) · [Architecture](docs/ARCHITECTURE.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)

## What ships

- **Native menu bar app:** Swift/AppKit app that reads Gmail and Messages locally,
  copies a recent code, and keeps one day of local history
- **Legacy source agent and Chrome extension:** Python, `gws`, and an authenticated
  Tailscale Serve connection for the older remote handoff

No content scripts. No browsing permission. No public proxy. No credentials in source control.

## Quick start

### Native macOS app (personal preview)

On the Mac that receives Gmail and Messages, clone this repository, download the
[latest signed release](https://github.com/KalebCole/otp-grabber/releases/latest),
and extract `otp-grabber-menubar-macos-arm64.zip`. Then run:

```bash
git clone https://github.com/KalebCole/otp-grabber.git
cd otp-grabber
scripts/install-menubar.sh "/path/to/extracted/OTP Grabber.app"
```

The app installs at `~/Applications/OTP Grabber.app` and registers a login
launch agent. Grant this installed app **Full Disk Access** in System Settings
for Messages, then follow [local Mac setup](docs/LOCAL-MAC-SETUP.md) to connect
Gmail. The native app does not use `client.json`, the Python source agent, or
Tailscale.

### Legacy source agent and Chrome extension

On the Mac that owns Gmail and Messages access:

```bash
git clone https://github.com/KalebCole/otp-grabber.git
cd otp-grabber
PYTHON_BIN="$(command -v python3.11)" scripts/install-agent.sh
scripts/serve-tailnet.sh --port 8877
```

Prerequisites:

- Python 3.11+
- `gws` installed and authenticated for Gmail
- Full Disk Access for the Python executable that reads `~/Library/Messages/chat.db`
- Tailscale with HTTPS certificates enabled

The installer creates a random token at:

```text
~/Library/Application Support/OTP Grabber/agent.json
```

The file and its parent directory are private to your macOS user.

Download a Chrome extension zip from a [GitHub release](https://github.com/KalebCole/otp-grabber/releases).

**Chrome**

1. Extract `otp-grabber-chrome-*.zip`.
2. Open `chrome://extensions`, enable Developer mode, and choose **Load unpacked**.
3. Select the extracted extension directory.
4. Open **Connection settings**. Enter the private Tailscale HTTPS origin and source-agent token.

### Personal native app releases

For future native releases, create and back up one self-signed signing identity,
save it in this repository's GitHub Actions secrets, and commit its **public**
fingerprint as described in [personal release signing](signing/README.md). A
`v*` tag then builds a release with that same identity. The workflow fails if
the key or fingerprint is missing or mismatched; it never publishes an ad hoc
fallback. Keep the private key and `.p12` out of Git.

On each Mac, update this checkout, download and extract the matching macOS zip
from the [GitHub release](https://github.com/KalebCole/otp-grabber/releases),
then run:

```bash
scripts/install-menubar.sh "/path/to/extracted/OTP Grabber.app"
```

The installer verifies the signed app before replacing the existing copy at
`~/Applications/OTP Grabber.app` and restores the previous copy if the updated
app cannot launch. Install updates manually at this same path. The first switch
from the old ad hoc signature to the stable identity may require **one new Full
Disk Access grant**. For Messages, enable the installed OTP Grabber app under
**System Settings → Privacy & Security → Full Disk Access**, then quit and
reopen it. On the target Mac, `v0.0.1` and `v0.0.2` both read fresh Messages
codes without changing Full Disk Access between installs; [the test record](docs/research/2026-10-16-issue-9-full-disk-access-updates.md)
excludes message text and codes.

These self-signed builds are for personal use and are **not notarized**. macOS
may require **Open Anyway** in Privacy & Security for a trusted download.

## Security model

The native app reads Gmail through the Gmail API and Messages from the local
database. It stores Gmail credentials in the Mac's Keychain; see [issue #20](https://github.com/KalebCole/otp-grabber/issues/20)
for the reported password prompt and request to remove that dependency.

The legacy source agent binds to `127.0.0.1` and uses authenticated Tailscale
Serve for remote clients. See [SECURITY.md](SECURITY.md) for that path's threat
model and reporting process.

## Develop

```bash
npm install
PYTHON=python3.11 make test
make check
make package # requires the personal signing identity and GitHub-compatible release setup
```

The suite covers extraction, source adapters, freshness ordering, archive idempotency and concurrency, API authentication and limits, Chrome state/API behavior, static web quality, Swift client behavior, and package construction.

## License

[MIT](LICENSE)
