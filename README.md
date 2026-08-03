# OTP Grabber

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
2. Move `OTP Grabber.app` to `/Applications` and open it.
3. Create `~/Library/Application Support/OTP Grabber/client.json`:

```json
{
  "server_url": "https://source-device.example-tailnet.ts.net:8877",
  "token": "paste-the-source-agent-token"
}
```

Set the file to mode `600`, then reopen the app.

## Security model

The source agent is the only component with Gmail and Messages access. It binds to `127.0.0.1` in code. Tailscale Serve is the only supported remote path, and every API request requires a bearer token compared in constant time.

Clients accept only loopback HTTP(S) or HTTPS `.ts.net` origins. The Tailscale helper rejects Funnel and public-exposure flags. See [SECURITY.md](SECURITY.md) for the threat model and reporting process.

## Develop

```bash
npm install
PYTHON=python3.11 make test
make check
make package
```

The suite covers extraction, source adapters, freshness ordering, archive idempotency and concurrency, API authentication and limits, Chrome state/API behavior, static web quality, Swift client behavior, and package construction.

## License

[MIT](LICENSE)
