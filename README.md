# OTP Grabber

> A local macOS replacement is in progress. Its Swift source is not yet verified on
> the target Mac. The 0.1.0 release and the legacy setup below describe the
> current supported build. See [local Mac setup and acceptance](docs/LOCAL-MAC-SETUP.md).

**The fresh verification code, already copied.**

OTP Grabber watches Gmail and Messages on a trusted Mac, then hands the newest code to Chrome or a macOS menu-bar app over your private Tailscale network. The client copies first. Gmail archives only after clipboard success.

[Website](https://kalebcole.github.io/otp-grabber/) · [Latest release](https://github.com/KalebCole/otp-grabber/releases/latest) · [Architecture](docs/ARCHITECTURE.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)

## What ships

- **Source agent:** Python 3.11+, launchd, Gmail via `gws`, Messages via the local database
- **Calm Card:** Chrome MV3 extension with automatic copy and hidden recent history
- **Menu bar:** native Swift/AppKit client packaged as `OTP Grabber.app`
- **Private transport:** loopback HTTP behind authenticated Tailscale Serve HTTPS

No content scripts. No browsing permission. No public proxy. No credentials in source control.

## Quick start

### 1. Install the source agent

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

### 2. Install a client

Download the [latest release](https://github.com/KalebCole/otp-grabber/releases/latest).

**Chrome**

1. Extract `otp-grabber-chrome-*.zip`.
2. Open `chrome://extensions`, enable Developer mode, and choose **Load unpacked**.
3. Select the extracted extension directory.
4. Open **Connection settings**. Enter the private Tailscale HTTPS origin and source-agent token.

**macOS menu bar**

1. Extract `otp-grabber-menubar-macos-arm64.zip`.
2. With this repo checked out on the Mac, install the extracted app at
   `~/Applications/OTP Grabber.app` and register its login launch agent:

   ```bash
   scripts/install-menubar.sh "/path/to/extracted/OTP Grabber.app"
   ```

   The signed personal-release installer becomes available after the one-time
   [signing setup](signing/README.md). For the legacy 0.1.0 ad hoc artifact, use
   `scripts/install-menubar.sh --development "/path/to/extracted/OTP Grabber.app"`.
3. Create `~/Library/Application Support/OTP Grabber/client.json`:

```json
{
  "server_url": "https://source-device.example-tailnet.ts.net:8877",
  "token": "paste-the-source-agent-token"
}
```

Set the file to mode `600`, then reopen the app.

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
reopen it. Later updates must be checked on the target Mac before permission
retention is considered verified; [the test record](docs/research/2026-10-16-issue-9-full-disk-access-updates.md)
excludes message text and codes.

These self-signed builds are for personal use and are **not notarized**. macOS
may require **Open Anyway** in Privacy & Security for a trusted download.

## Security model

The source agent is the only component with Gmail and Messages access. It binds to `127.0.0.1` in code. Tailscale Serve is the only supported remote path, and every API request requires a bearer token compared in constant time.

Clients accept only loopback HTTP(S) or HTTPS `.ts.net` origins. The Tailscale helper rejects Funnel and public-exposure flags. See [SECURITY.md](SECURITY.md) for the threat model and reporting process.

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
