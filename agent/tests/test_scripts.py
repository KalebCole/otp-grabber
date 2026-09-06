"""Dry-run coverage for the macOS setup scripts."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"


class ScriptTests(unittest.TestCase):
    def run_script(self, name: str, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(SCRIPTS / name), *arguments],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_install_dry_run_describes_private_launchagent(self):
        result = self.run_script("install-agent.sh", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("127.0.0.1", result.stdout)
        self.assertIn("dry-run", result.stdout)

        template = (SCRIPTS / "com.otpgrabber.agent.plist.template").read_text()
        self.assertIn("<key>PATH</key>", template)
        self.assertIn("/opt/homebrew/bin", template)
        self.assertIn("GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND", template)
        self.assertIn("StandardErrorPath", template)
        self.assertIn("StandardOutPath", template)
        installer = (SCRIPTS / "install-agent.sh").read_text()
        self.assertIn("command -v python3.11", installer)

    def test_uninstall_dry_run_is_idempotent(self):
        result = self.run_script("uninstall-agent.sh", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dry-run", result.stdout)

    def test_gmail_backend_dry_run_requires_explicit_gog_values_and_has_gws_rollback(self):
        missing = self.run_script("configure-gmail-backend.sh", "--dry-run", "--gog")
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("--gog-launcher", missing.stderr)

        gog = self.run_script(
            "configure-gmail-backend.sh", "--dry-run", "--gog",
            "--gog-launcher", "/protected/launcher.zsh",
            "--gog-client", "test-client", "--gog-account", "account@example.test",
        )
        self.assertEqual(gog.returncode, 0, gog.stderr)
        self.assertIn("readiness", gog.stdout)

        rollback = self.run_script("configure-gmail-backend.sh", "--dry-run", "--gws")
        self.assertEqual(rollback.returncode, 0, rollback.stderr)
        self.assertIn("gws", rollback.stdout)

    def test_gmail_backend_non_dry_run_authenticates_without_token_leakage_and_rolls_back(self):
        token = "test-readiness-token-abcdefghijklmnopqrstuvwxyz0123456789"

        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            app_dir = home / "Library" / "Application Support" / "OTP Grabber"
            app_dir.mkdir(parents=True)
            config = app_dir / "agent.json"
            plist = home / "Library" / "LaunchAgents" / "com.otpgrabber.agent.plist"
            plist.parent.mkdir(parents=True)
            plist.write_text("<plist />")
            original = {
                "port": 1,
                "token": token,
                "allowed_origins": [],
                "gmail_backend": "gws",
            }

            fake_bin = Path(temporary) / "bin"
            fake_bin.mkdir()
            launchctl_log = Path(temporary) / "launchctl.log"
            launchctl = fake_bin / "launchctl"
            launchctl.write_text(
                "#!/usr/bin/env bash\nset -eu\nprintf '%s\\n' \"$*\" >> \"$LAUNCHCTL_LOG\"\n"
            )
            launchctl.chmod(0o755)
            sleep = fake_bin / "sleep"
            sleep.write_text("#!/usr/bin/env bash\nexit 0\n")
            sleep.chmod(0o755)

            def run_attempt(status: int) -> tuple[subprocess.CompletedProcess[str], list[str], str]:
                requests: list[str] = []
                request_started = threading.Event()
                release_response = threading.Event()

                class HealthHandler(BaseHTTPRequestHandler):
                    def do_GET(self):  # noqa: N802 - HTTP handler interface
                        authorization = self.headers.get("Authorization", "")
                        requests.append(authorization)
                        request_started.set()
                        release_response.wait(timeout=5)
                        response_status = status if authorization == f"Bearer {token}" else 401
                        self.send_response(response_status)
                        self.end_headers()
                        self.wfile.write(b'{"ok":true}' if response_status == 200 else b"unhealthy")

                    def log_message(self, format, *args):
                        pass

                server = ThreadingHTTPServer(("127.0.0.1", 0), HealthHandler)
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                config.write_text(json.dumps({**original, "port": server.server_port}) + "\n")
                environment = {
                    **os.environ,
                    "HOME": str(home),
                    "PATH": f"{fake_bin}:{os.environ['PATH']}",
                    "PYTHON_BIN": sys.executable,
                    "LAUNCHCTL_LOG": str(launchctl_log),
                }
                process = subprocess.Popen(
                    [
                        "bash", str(SCRIPTS / "configure-gmail-backend.sh"), "--gog",
                        "--gog-launcher", "/protected/launcher.zsh",
                        "--gog-client", "test-client",
                        "--gog-account", "account@example.test",
                    ],
                    cwd=ROOT,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=environment,
                )
                self.assertTrue(request_started.wait(timeout=5), "health server was not called")
                process_table = subprocess.run(
                    ["ps", "-axo", "pid=,ppid=,command="], text=True, capture_output=True, check=True
                ).stdout.splitlines()
                entries = [line.strip().split(None, 2) for line in process_table if line.strip()]
                descendants = {str(process.pid)}
                while True:
                    children = {fields[0] for fields in entries if len(fields) == 3 and fields[1] in descendants}
                    if children.issubset(descendants):
                        break
                    descendants.update(children)
                curl_argv = "\n".join(
                    fields[2] for fields in entries
                    if len(fields) == 3 and fields[0] in descendants and "curl" in fields[2]
                )
                self.assertNotIn(token, curl_argv)
                release_response.set()
                stdout, stderr = process.communicate(timeout=15)
                server.shutdown()
                thread.join(timeout=5)
                server.server_close()
                return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr), requests, curl_argv

            failed, failed_requests, _ = run_attempt(503)
            self.assertNotEqual(failed.returncode, 0)
            self.assertTrue(failed_requests)
            self.assertTrue(all(request == f"Bearer {token}" for request in failed_requests))
            self.assertEqual(json.loads(config.read_text())["gmail_backend"], "gws")
            self.assertNotIn(token, failed.stdout + failed.stderr)

            succeeded, success_requests, _ = run_attempt(200)
            self.assertEqual(succeeded.returncode, 0, succeeded.stderr)
            self.assertEqual(success_requests, [f"Bearer {token}"])
            self.assertEqual(json.loads(config.read_text())["gmail_backend"], "gog")
            self.assertNotIn(token, succeeded.stdout + succeeded.stderr)
            self.assertNotIn(token, launchctl_log.read_text())

    def test_gog_envelope_canary_requires_confirmation_and_advertises_readonly_commands(self):
        missing = self.run_script("gog-envelope-canary.sh", "--dry-run")
        self.assertNotEqual(missing.returncode, 0)

        result = self.run_script(
            "gog-envelope-canary.sh", "--dry-run", "--confirm-read-only",
            "--config", "/protected/agent.json", "--message-id", "message-id",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--readonly", result.stdout)

    def test_serve_rejects_public_exposure_flags(self):
        result = self.run_script("serve-tailnet.sh", "--funnel", "--dry-run")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("public exposure is not supported", result.stderr)

    def test_serve_dry_run_uses_tailscale_serve_not_funnel(self):
        result = self.run_script("serve-tailnet.sh", "--dry-run", "--port", "8787")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("tailscale serve", result.stdout)
        self.assertIn("--bg", result.stdout)
        self.assertIn("--yes", result.stdout)
        self.assertNotIn("funnel", result.stdout.lower())


if __name__ == "__main__":
    unittest.main()
