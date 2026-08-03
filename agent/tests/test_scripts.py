"""Dry-run coverage for the macOS setup scripts."""

from __future__ import annotations

import subprocess
import unittest
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
