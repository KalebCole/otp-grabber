"""Small authenticated HTTP API bound exclusively to IPv4 loopback."""

from __future__ import annotations

import argparse
import json
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Lock
from typing import Any

from agent.otp_grabber.security import constant_time_token_match, extract_bearer_token

MAX_BODY_BYTES = 64 * 1024
RATE_WINDOW_SECONDS = 60
RATE_MAX_REQUESTS = 60
_ALLOWED_ROUTES = {
    ("GET", "/v1/health"),
    ("GET", "/v1/latest"),
    ("GET", "/v1/history"),
    ("POST", "/v1/archive"),
}


class RateLimiter:
    def __init__(self, max_requests: int = RATE_MAX_REQUESTS, window_seconds: int = RATE_WINDOW_SECONDS) -> None:
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._requests: dict[str, deque[float]] = {}
        self._lock = Lock()

    def allow(self, client: str) -> bool:
        with self._lock:
            now = time.monotonic()
            requests = self._requests.setdefault(client, deque())
            cutoff = now - self.window_seconds
            while requests and requests[0] <= cutoff:
                requests.popleft()
            if len(requests) >= self.max_requests:
                return False
            requests.append(now)
            return True


class LocalAPIServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], service: Any, token: str, allowed_origins: tuple[str, ...]) -> None:
        self.service = service
        self.token = token
        self.allowed_origins = frozenset(allowed_origins)
        self.rate_limiter = RateLimiter()
        super().__init__(address, LocalAPIHandler)


class LocalAPIHandler(BaseHTTPRequestHandler):
    server: LocalAPIServer
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args: object) -> None:
        """Avoid request logging, which could include sensitive request targets."""

    def do_OPTIONS(self) -> None:
        if self.path not in {route[1] for route in _ALLOWED_ROUTES}:
            self._send_json(404, {"error": "not_found"})
            return
        self._send_json(204, None)

    def do_GET(self) -> None:
        self._dispatch()

    def do_POST(self) -> None:
        self._dispatch()

    def do_PUT(self) -> None:
        self._not_found()

    def do_DELETE(self) -> None:
        self._not_found()

    def _dispatch(self) -> None:
        if (self.command, self.path) not in _ALLOWED_ROUTES:
            self._not_found()
            return
        if not self.server.rate_limiter.allow(self.client_address[0]):
            self._send_json(429, {"error": "rate_limited"})
            return
        provided = extract_bearer_token(self.headers.get("Authorization"))
        if provided is None or not constant_time_token_match(self.server.token, provided):
            self._send_json(401, {"error": "unauthorized"})
            return
        try:
            if self.path == "/v1/health":
                self._send_json(200, {"ok": True})
            elif self.path == "/v1/latest":
                self._send_json(200, self.server.service.poll_latest().to_dict())
            elif self.path == "/v1/history":
                self._send_json(200, self.server.service.get_history().to_dict())
            else:
                body = self._read_json_body()
                if not isinstance(body, dict) or not isinstance(body.get("id"), str):
                    self._send_json(400, {"error": "invalid_request"})
                    return
                self._send_json(200, self.server.service.acknowledge_archive(body["id"]).to_dict())
        except _ResponseSent:
            return
        except ValueError:
            self._send_json(400, {"error": "invalid_request"})
        except Exception:
            self._send_json(500, {"error": "internal_error"})

    def _read_json_body(self) -> object:
        raw_length = self.headers.get("Content-Length")
        try:
            length = int(raw_length) if raw_length is not None else -1
        except ValueError as error:
            raise ValueError("invalid content length") from error
        if length < 0:
            raise ValueError("missing content length")
        if length > MAX_BODY_BYTES:
            self._send_json(413, {"error": "request_too_large"})
            raise _ResponseSent()
        raw = self.rfile.read(length)
        if len(raw) != length:
            raise ValueError("truncated body")
        try:
            return json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ValueError("malformed json") from error

    def _not_found(self) -> None:
        self._send_json(404, {"error": "not_found"})

    def _send_json(self, status: int, payload: object | None) -> None:
        encoded = b"" if status == 204 else json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Length", str(len(encoded)))
        if status != 204:
            self.send_header("Content-Type", "application/json; charset=utf-8")
        origin = self.headers.get("Origin")
        if origin in self.server.allowed_origins:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        if encoded:
            self.wfile.write(encoded)


class _ResponseSent(Exception):
    pass


def make_server(*, service: Any, token: str, port: int, allowed_origins: tuple[str, ...] = ()) -> LocalAPIServer:
    """Build a server that cannot be configured to bind publicly."""
    return LocalAPIServer(("127.0.0.1", port), service, token, allowed_origins)


def main() -> None:
    """Run the local service from its private configuration file."""
    parser = argparse.ArgumentParser(description="Run the OTP Grabber loopback API")
    parser.add_argument("--config", default=None, help="private agent configuration JSON")
    arguments = parser.parse_args()
    from pathlib import Path
    from agent.otp_grabber.config import load_config
    from agent.otp_grabber.service import FreshestCodeService
    from agent.otp_grabber.sources.gmail import GmailSource
    from agent.otp_grabber.sources.messages import MessagesSource

    config = load_config(Path(arguments.config) if arguments.config else None)
    service = FreshestCodeService(
        gmail_source=GmailSource(),
        messages_source=MessagesSource(
            database_path=Path.home() / "Library" / "Messages" / "chat.db"
        ),
    )
    server = make_server(
        service=service,
        token=config.token,
        port=config.port,
        allowed_origins=config.allowed_origins,
    )
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
