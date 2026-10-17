# Security

OTP Grabber runs locally on the Mac that receives Gmail and Messages. Treat the
app's host and configuration as credential-bearing systems.

## Supported versions

Security fixes are released on the latest tagged version. This project is
pre-1.0; upgrade to the newest release before reporting a reproducible issue.

## Data and permissions

The app requests read-only Gmail OAuth access and reads the local Messages
database in read-only mode. It stores the Gmail refresh token and OAuth client
secret in the macOS Keychain and copies selected codes to the local clipboard.
It keeps one day of local finding history. The [Keychain dependency and password
prompt](https://github.com/KalebCole/otp-grabber/issues/20) are open issues.

Grant Full Disk Access only to the installed
`~/Applications/OTP Grabber.app`. Do not post codes, message content, OAuth
secrets, or personal paths in public issues.

## Safe installation

Install a verified signed release at `~/Applications/OTP Grabber.app`. The
installer checks the pinned personal signing identity before replacing the app.
Keep that identity stable across updates. These releases are self-signed for
personal use and are not notarized.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting or a private security advisory
for this repository. If that option is unavailable, open a minimal issue
asking for a private contact channel. Do not include exploit details, message
content, hostnames, authentication values, or personal paths in a public issue.
