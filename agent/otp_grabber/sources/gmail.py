"""Gmail verification-code source backed by gws or the constrained gog CLI."""

from __future__ import annotations

import base64
import html
import json
import os
import re
import subprocess
from collections.abc import Callable, Mapping
from typing import Any

from agent.otp_grabber.extractor import extract_code


_QUERY_KEYWORDS = (
    'verification OR passcode OR OTP OR "one-time" OR "one time" OR '
    '"security code" OR "login code" OR "sign-in code" OR "your code" OR '
    '"verification code" OR "authentication code" OR "access code" OR '
    '"confirmation code" OR "2fa" OR "two-factor"'
)
_GOG_SOURCE_COMMAND = 'source "$1"; shift; exec "$@"'


class GmailSource:
    """Read recent Gmail messages through gws by default or constrained gog."""

    def __init__(
        self,
        *,
        backend: str = "gws",
        run_command: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
        executable: str = "gws",
        gog_executable: str = "gog",
        launcher: str | None = None,
        client: str | None = None,
        account: str | None = None,
        environment: Mapping[str, str] | None = None,
        timeout_seconds: int = 25,
        max_results: int = 12,
    ) -> None:
        if backend not in {"gws", "gog"}:
            raise ValueError("backend must be 'gws' or 'gog'")
        if backend == "gog":
            for name, value in (("launcher", launcher), ("client", client), ("account", account)):
                if not isinstance(value, str) or not value.strip():
                    raise ValueError(f"gog {name} must be configured")
        self._backend = backend
        self._run_command = run_command
        self._executable = executable
        self._gog_executable = gog_executable
        self._launcher = launcher
        self._client = client
        self._account = account
        self._environment = dict(os.environ)
        if environment is not None:
            self._environment.update(environment)
        self._environment.setdefault(
            "GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND",
            "file",
        )
        self._timeout_seconds = timeout_seconds
        self._max_results = max_results

    def _run(self, command: list[str], *, environment: Mapping[str, str] | None = None) -> dict[str, Any]:
        try:
            result = self._run_command(
                command,
                capture_output=True,
                text=True,
                env=environment,
                timeout=self._timeout_seconds,
            )
        except subprocess.TimeoutExpired as error:
            raise RuntimeError("gmail source timed out") from error
        if result.returncode != 0:
            raise RuntimeError("gmail source command failed")
        output = (result.stdout or "").strip()
        object_start = output.find("{")
        if object_start > 0:
            output = output[object_start:]
        try:
            value = json.loads(output or "{}")
        except json.JSONDecodeError as error:
            raise RuntimeError(f"{self._backend} returned invalid JSON") from error
        if not isinstance(value, dict):
            raise RuntimeError(f"{self._backend} returned an unexpected JSON value")
        return value

    def _gws(self, *arguments: str) -> dict[str, Any]:
        return self._run([self._executable, *arguments], environment=self._environment)

    def _gog(self, authority: str, *arguments: str, readonly: bool) -> dict[str, Any]:
        command = [
            "/bin/zsh",
            "-c",
            _GOG_SOURCE_COMMAND,
            "--",
            self._launcher,
            self._gog_executable,
            "--client",
            self._client,
            "--account",
            self._account,
            "--enable-commands-exact",
            authority,
        ]
        if readonly:
            command.append("--readonly")
        command.extend(("--no-input", "--json", *arguments))
        return self._run(command)

    def _get_message(self, message_id: str) -> dict[str, Any]:
        if self._backend == "gog":
            response = self._gog("gmail.raw", "gmail", "raw", message_id, readonly=True)
            message = response.get("message", response)
            if not isinstance(message, dict):
                raise RuntimeError("gog returned an unexpected JSON value")
            return message
        parameters = {"userId": "me", "id": message_id, "format": "full"}
        return self._gws(
            "gmail", "users", "messages", "get", "--params", json.dumps(parameters)
        )

    def archive_message(self, message_id: str) -> None:
        """Remove the Inbox label from one acknowledged Gmail message."""
        if self._backend == "gog":
            self._gog("gmail.archive", "gmail", "archive", message_id, readonly=False)
            return
        parameters = {"userId": "me", "id": message_id}
        body = {"removeLabelIds": ["INBOX"]}
        self._gws(
            "gmail", "users", "messages", "modify", "--params", json.dumps(parameters),
            "--json", json.dumps(body),
        )

    def verify_gog_envelopes(self, *, message_id: str, since_timestamp_ms: int) -> dict[str, int | str]:
        """Run a read-only authenticated gog search/raw envelope canary."""
        if self._backend != "gog":
            raise ValueError("gog envelope canary requires the gog backend")
        query = f"after:{int(since_timestamp_ms) // 1000} in:anywhere ({_QUERY_KEYWORDS})"
        listing = self._gog(
            "gmail.messages.search", "gmail", "messages", "search", query,
            "--max", "1", readonly=True,
        )
        summaries = listing.get("messages", listing.get("results"))
        if not isinstance(summaries, list):
            raise RuntimeError("gog returned an unexpected search envelope")
        message = self._get_message(message_id)
        if not isinstance(message.get("payload"), Mapping):
            raise RuntimeError("gog returned an unexpected raw envelope")
        return {"listing_count": len(summaries), "message_id": message_id}

    def fetch_recent(self, *, since_timestamp_ms: int) -> list[dict[str, Any]]:
        """Return extracted Gmail records newer than the supplied epoch time."""
        query = f"after:{int(since_timestamp_ms) // 1000} in:anywhere ({_QUERY_KEYWORDS})"
        if self._backend == "gog":
            response = self._gog(
                "gmail.messages.search", "gmail", "messages", "search", query,
                "--max", str(self._max_results), readonly=True,
            )
            listing = {"messages": response.get("messages", response.get("results", []))}
        else:
            parameters = {"userId": "me", "maxResults": self._max_results, "q": query}
            listing = self._gws(
                "gmail", "users", "messages", "list", "--params", json.dumps(parameters)
            )

        records = []
        for summary in listing.get("messages", []):
            if not isinstance(summary, dict) or not summary.get("id"):
                continue
            message = self._get_message(str(summary["id"]))
            record = _message_record(message)
            if record is not None and record["timestamp_ms"] >= since_timestamp_ms:
                records.append(record)
        records.sort(key=lambda record: record["timestamp_ms"], reverse=True)
        return records


def _message_record(message: Mapping[str, Any]) -> dict[str, Any] | None:
    payload = message.get("payload")
    if not isinstance(payload, Mapping):
        return None
    headers = {
        str(header.get("name", "")).lower(): str(header.get("value", ""))
        for header in payload.get("headers", [])
        if isinstance(header, Mapping)
    }
    subject = headers.get("subject", "")
    body = _extract_body(payload)
    code = extract_code(subject, body)
    if not code:
        return None
    return {
        "id": str(message.get("id", "")),
        "source": "gmail",
        "code": code,
        "sender": headers.get("from", ""),
        "subject": subject,
        "timestamp_ms": int(message.get("internalDate", 0) or 0),
    }


def _extract_body(payload: Mapping[str, Any]) -> str:
    chunks: list[str] = []

    def visit(part: Mapping[str, Any]) -> None:
        mime_type = str(part.get("mimeType", ""))
        body = part.get("body")
        data = body.get("data") if isinstance(body, Mapping) else None
        if mime_type.startswith("text/") and isinstance(data, str):
            padding = "=" * (-len(data) % 4)
            try:
                chunks.append(
                    base64.urlsafe_b64decode(data + padding).decode(
                        "utf-8", errors="replace"
                    )
                )
            except (ValueError, TypeError):
                pass
        for child in part.get("parts", []):
            if isinstance(child, Mapping):
                visit(child)

    visit(payload)
    text = " ".join(chunks)
    if "<" in text and ">" in text:
        text = re.sub(
            r"<(?:style|script)[^>]*>.*?</(?:style|script)>", " ", text,
            flags=re.I | re.S,
        )
        text = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()
