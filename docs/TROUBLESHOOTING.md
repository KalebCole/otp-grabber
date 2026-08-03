# Troubleshooting

## Source agent is offline

1. Check launchd:
   ```bash
   launchctl print "gui/$(id -u)/com.otpgrabber.agent"
   ```
2. Check logs:
   ```bash
   tail -n 100 "$HOME/Library/Logs/OTP Grabber/agent.err.log"
   ```
3. Test the loopback endpoint with the token from `~/Library/Application Support/OTP Grabber/agent.json`:
   ```bash
   TOKEN="$(python3 -c 'import json,os; print(json.load(open(os.path.expanduser("~/Library/Application Support/OTP Grabber/agent.json")))["token"])')"
   curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8877/v1/health
   unset TOKEN
   ```

Do not paste the token into an issue or shared shell history.

## Gmail source unavailable

- Confirm `gws` is installed and authenticated for Gmail.
- Run a harmless `gws gmail users messages list` request in the same account.
- Keep `GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file` when launchd cannot access the interactive keychain backend.
- Reauthenticate `gws` if it reports `invalid_grant` or an expired token.

## Messages source unavailable

Grant Full Disk Access to the Python executable used by the LaunchAgent, then restart the agent. The source reads `~/Library/Messages/chat.db` and does not modify it.

## Tailscale URL does not respond

```bash
tailscale serve status
scripts/serve-tailnet.sh --port 8877
```

Confirm both Macs are online in the same tailnet. OTP Grabber does not support Tailscale Funnel or another public proxy.

## Chrome rejects the private origin

- Use the origin only, for example `https://source-device.example-tailnet.ts.net:8877`.
- Do not include `/v1/latest`, credentials, a query, or a fragment.
- When Chrome prompts, allow the extension to reach that exact private origin.
- If the permission was removed, save settings again to request it.

## Code appears but was not copied

The code remains selectable in the Calm Card. macOS or Chrome may block clipboard writes when the popup is not active. Reopen the extension or choose Refresh in the menu-bar app.

## Gmail message stayed in Inbox

Copying succeeded before archive was attempted. The client leaves the code visible and reports that archive will retry. Reopen the client after the source connection recovers.

## Menu-bar app shows setup

Create `~/Library/Application Support/OTP Grabber/client.json` with mode `600`:

```json
{
  "server_url": "https://source-device.example-tailnet.ts.net:8877",
  "token": "paste-the-source-agent-token"
}
```

Then quit and reopen OTP Grabber.
