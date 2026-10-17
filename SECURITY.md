# Security

OTP Grabber is local-first software with access to sensitive message metadata. Treat its configuration and host device like any other credential-bearing system.

## Supported versions

Security fixes are released on the latest tagged version. This project is pre-1.0; upgrade to the newest release before reporting a reproducible issue.

## Trust boundary

The native macOS app reads Gmail through the Gmail API and Messages from the
local database on the same Mac. It requests read-only Gmail access, stores its
refresh token and OAuth client secret in the macOS Keychain, and writes selected
codes to the local clipboard. It does not require the source agent or Tailscale.
The [Keychain dependency and password prompt](https://github.com/KalebCole/otp-grabber/issues/20)
remain open issues for the native app.

For the legacy source-agent and Chrome-extension path:

- The source agent runs on an Apple device that already has access to Gmail and the local Messages database.
- The HTTP service binds to loopback only. Remote clients reach it through Tailscale Serve.
- Tailscale Funnel and public reverse proxies are outside the supported design.
- Clients store their endpoint and authentication value in local user settings. Those values are never bundled into release artifacts.
- The API returns only the selected code, source label, sender/service label, age, and opaque source identifier needed for the archive acknowledgement.
- A Gmail message is archived only after a client reports successful clipboard copy.

OTP Grabber reduces exposure; it does not make a compromised Mac, browser profile, or tailnet trustworthy.

## Required permissions

The native app needs Full Disk Access to read Messages and uses its own Gmail
OAuth connection. The legacy source agent needs Full Disk Access for its Python
executable and uses the locally configured Google Workspace CLI session.
Approve permissions only for binaries and paths you installed from this
repository or a verified release.

## Safe deployment

For the native app, install the verified signed release at
`~/Applications/OTP Grabber.app` and grant Full Disk Access to that installed
copy. Keep the signing identity stable across updates.

For the legacy source-agent path:

1. Generate a fresh, high-entropy authentication value during installation.
2. Keep the service bound to `127.0.0.1`.
3. Use Tailscale Serve for private HTTPS. Never use Funnel.
4. Do not paste configuration files, logs containing message content, or live authentication values into issues.
5. Rotate the authentication value if a client device, browser profile, or config file may be exposed.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting or a private security advisory for this repository. If that option is unavailable, open a minimal issue asking for a private contact channel. Do not include exploit details, message content, hostnames, authentication values, or personal paths in a public issue.
