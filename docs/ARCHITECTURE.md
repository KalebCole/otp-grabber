# Architecture

## Trust boundary

OTP Grabber has one credential-bearing component: the source agent. It runs on the Mac that already has access to Gmail and Messages. Clients never receive Gmail OAuth state or direct Messages database access.

```text
Gmail via gws ─┐
               ├─ source agent, 127.0.0.1:8877
Messages DB ───┘             │
                             │ bearer-authenticated HTTPS
                       Tailscale Serve
                             │
                  ┌──────────┴──────────┐
             Chrome MV3           macOS menu bar
```

## Data flow

1. A client requests `GET /v1/latest` with a bearer token.
2. The source agent queries recent Gmail and Messages records and normalizes candidates.
3. The agent returns the freshest code plus non-fatal source errors.
4. The client writes the code to the local clipboard.
5. Only after clipboard success, a Gmail-backed record receives `POST /v1/archive`.
6. The agent removes the Gmail `INBOX` label. Messages records are never mutated.

## API

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/health` | Authenticated readiness check |
| `GET` | `/v1/latest` | Freshest normalized code and source errors |
| `GET` | `/v1/history` | Recent normalized codes |
| `POST` | `/v1/archive` | Idempotent Gmail archive acknowledgment |

All routes except preflight require `Authorization: Bearer <token>`. Request bodies are capped at 64 KiB. Unknown routes and methods return generic errors.

## Network posture

- The Python server binds to `127.0.0.1` in code, not configuration.
- `scripts/serve-tailnet.sh` creates a background Tailscale Serve proxy.
- The helper rejects Funnel/public-exposure flags.
- Clients accept HTTPS `.ts.net` origins or loopback HTTP(S) only.
- Tokens live in mode-600 source/client configuration or Chrome local storage.

## Client behavior

Both clients use the same ordering guarantee: **copy first, archive second**. A failed clipboard write never archives the email. A failed archive keeps the copied code visible and reports retry guidance.

The Chrome extension requests no browsing, tab, or content-script permission. Access to a chosen `.ts.net` or loopback origin is optional and granted during setup.
