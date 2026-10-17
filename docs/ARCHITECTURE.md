# Architecture

## Native macOS app

The personal macOS app runs on the Mac that receives Gmail and Messages. It
calls the Gmail API with a read-only OAuth scope, reads the local Messages
database in SQLite read-only mode, selects a recent code, and copies it to the
Mac clipboard. It keeps a local one-day history. The app currently stores its
Gmail refresh token and OAuth client secret in the macOS Keychain; [issue #20](https://github.com/KalebCole/otp-grabber/issues/20)
tracks the request to remove that dependency and password prompts.

```text
Gmail API ────┐
              ├─ native macOS app → recent-code selection → clipboard
Messages DB ─┘                    ↘ local one-day history
```

Tagged personal releases are signed with the pinned self-signed
identity described in [personal release signing](../signing/README.md).
