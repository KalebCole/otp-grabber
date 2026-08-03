"""Behavior tests for the authenticated loopback HTTP API."""

from __future__ import annotations

import http.client
import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

from agent.otp_grabber.models import ArchiveResult, HistoryResult, PollResult
from agent.otp_grabber.security import constant_time_token_match
from agent.otp_grabber.server import MAX_BODY_BYTES, make_server


class StubService:
    def poll_latest(self):
        return PollResult(latest=None, errors=())

    def get_history(self):
        return HistoryResult(codes=())

    def acknowledge_archive(self, message_id):
        return ArchiveResult(message_id, True, False)


class APITestCase(unittest.TestCase):
    def setUp(self):
        self.server = make_server(
            service=StubService(),
            token="test-token",
            port=0,
            allowed_origins=("https://client.tailnet.ts.net",),
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=1)

    def request(self, method, path, *, token="test-token", body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=2)
        request_headers = dict(headers or {})
        if token is not None:
            request_headers["Authorization"] = f"Bearer {token}"
        if body is not None and "Content-Type" not in request_headers:
            request_headers["Content-Type"] = "application/json"
        connection.request(method, path, body=body, headers=request_headers)
        response = connection.getresponse()
        raw = response.read()
        connection.close()
        payload = json.loads(raw.decode("utf-8")) if raw else None
        return response.status, dict(response.getheaders()), payload

    def test_binds_only_loopback(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")

    def test_constant_time_token_helper_rejects_wrong_value(self):
        self.assertTrue(constant_time_token_match("test-token", "test-token"))
        self.assertFalse(constant_time_token_match("test-token", "wrong-token"))

    def test_unauthenticated_request_has_generic_error(self):
        status, _, payload = self.request("GET", "/v1/health", token=None)
        self.assertEqual(status, 401)
        self.assertEqual(payload, {"error": "unauthorized"})

    def test_authenticated_health_returns_no_secret(self):
        status, _, payload = self.request("GET", "/v1/health")
        self.assertEqual(status, 200)
        self.assertEqual(payload, {"ok": True})
        self.assertNotIn("token", json.dumps(payload))

    def test_latest_history_and_archive_use_the_service_contract(self):
        self.assertEqual(self.request("GET", "/v1/latest")[2], {"latest": None, "errors": []})
        self.assertEqual(self.request("GET", "/v1/history")[2], {"codes": []})
        status, _, payload = self.request("POST", "/v1/archive", body=b'{"id":"gmail-1"}')
        self.assertEqual(status, 200)
        self.assertEqual(
            payload,
            {"id": "gmail-1", "archived": True, "already_archived": False},
        )

    def test_malformed_json_is_a_safe_bad_request(self):
        status, _, payload = self.request("POST", "/v1/archive", body=b"{")
        self.assertEqual(status, 400)
        self.assertEqual(payload, {"error": "invalid_request"})

    def test_internal_exception_has_a_safe_error(self):
        class FailingService:
            def poll_latest(self):
                raise RuntimeError("token-like-detail")

        self.server.service = FailingService()
        status, _, payload = self.request("GET", "/v1/latest")
        self.assertEqual(status, 500)
        self.assertEqual(payload, {"error": "internal_error"})

    def test_body_larger_than_64kb_is_rejected(self):
        body = b"x" * (MAX_BODY_BYTES + 1)
        status, _, payload = self.request("POST", "/v1/archive", body=body)
        self.assertEqual(status, 413)
        self.assertEqual(payload, {"error": "request_too_large"})

    def test_method_and_path_allowlist_returns_safe_not_found(self):
        status, _, payload = self.request("DELETE", "/v1/latest")
        self.assertEqual(status, 404)
        self.assertEqual(payload, {"error": "not_found"})

    def test_rate_cap_rejects_request_after_limit(self):
        server = self.server
        server.rate_limiter.max_requests = 1
        self.assertEqual(self.request("GET", "/v1/health")[0], 200)
        status, _, payload = self.request("GET", "/v1/health")
        self.assertEqual(status, 429)
        self.assertEqual(payload, {"error": "rate_limited"})

    def test_cors_is_restricted_to_configured_allowlist(self):
        status, headers, _ = self.request(
            "OPTIONS", "/v1/latest", headers={"Origin": "https://client.tailnet.ts.net"}
        )
        self.assertEqual(status, 204)
        self.assertEqual(headers.get("Access-Control-Allow-Origin"), "https://client.tailnet.ts.net")
        status, headers, _ = self.request(
            "OPTIONS", "/v1/latest", headers={"Origin": "https://evil.example"}
        )
        self.assertEqual(status, 204)
        self.assertNotIn("Access-Control-Allow-Origin", headers)


class ConfigTestCase(unittest.TestCase):
    def test_generated_config_is_mode_600_and_has_no_source_path(self):
        from agent.otp_grabber.config import generate_config

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            generated = generate_config(path, port=8787, token_factory=lambda: "x" * 32)
            self.assertEqual(generated, path)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            data = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(data["token"], "x" * 32)
            self.assertEqual(data["port"], 8787)
            self.assertNotIn("source", json.dumps(data).lower())


if __name__ == "__main__":
    unittest.main()
