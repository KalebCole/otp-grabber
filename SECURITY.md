# Security

OTP Grabber is local-first software with access to sensitive message metadata. Treat its configuration and host device like any other credential-bearing system.

## Supported versions

Security fixes are released on the latest tagged version. This project is pre-1.0; upgrade to the newest release before reporting a reproducible issue.

## Trust boundary

- The source agent runs on an Apple device that already has access to Gmail and the local Messages database.
- The HTTP service binds to loopback only. Remote clients reach it through Tailscale Serve.
- Tailscale Funnel and public reverse proxies are outside the supported design.
- Clients store their endpoint and authentication value in local user settings. Those values are never bundled into release artifacts.
- The API returns only the selected code, source label, sender/service label, age, and opaque source identifier needed for the archive acknowledgement.
- A Gmail message is archived only after a client reports successful clipboard copy.

OTP Grabber reduces exposure; it does not make a compromised Mac, browser profile, or tailnet trustworthy.

## Required permissions

The source device may require macOS Full Disk Access for the process that reads Messages. Gmail access uses the locally configured Google Workspace CLI session. The menu-bar app needs clipboard write access through standard macOS APIs. Approve permissions only for binaries and paths you installed from this repository or a verified release.

## Safe deployment

1. Generate a fresh, high-entropy authentication value during installation.
2. Keep the service bound to `127.0.0.1`.
3. Use Tailscale Serve for private HTTPS. Never use Funnel.
4. Do not paste configuration files, logs containing message content, or live authentication values into issues.
5. Rotate the authentication value if a client device, browser profile, or config file may be exposed.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting or a private security advisory for this repository. If that option is unavailable, open a minimal issue asking for a private contact channel. Do not include exploit details, message content, hostnames, authentication values, or personal paths in a public issue.
