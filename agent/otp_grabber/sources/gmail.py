"""Gmail verification-code source backed by the Google Workspace CLI."""

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


class GmailSource:
    """Read recent Gmail messages through an injected ``gws`` command runner."""

    def __init__(
        self,
        *,
        run_command: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
        executable: str = "gws",
        environment: Mapping[str, str] | None = None,
        timeout_seconds: int = 25,
        max_results: int = 12,
    ) -> None:
        self._run_command = run_command
        self._executable = executable
        self._environment = dict(os.environ)
        if environment is not None:
            self._environment.update(environment)
        self._environment.setdefault(
            "GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND",
            "file",
        )
        self._timeout_seconds = timeout_seconds
        self._max_results = max_results

    def _gws(self, *arguments: str) -> dict[str, Any]:
        command = [self._executable, *arguments]
        result = self._run_command(
            command,
            capture_output=True,
            text=True,
            env=self._environment,
            timeout=self._timeout_seconds,
        )
        if result.returncode != 0:
            detail = (result.stderr or "").strip()[:300]
            raise RuntimeError(f"gws failed: {detail}")
        output = (result.stdout or "").strip()
        object_start = output.find("{")
        if object_start > 0:
            output = output[object_start:]
        try:
            value = json.loads(output or "{}")
        except json.JSONDecodeError as error:
            raise RuntimeError("gws returned invalid JSON") from error
        if not isinstance(value, dict):
            raise RuntimeError("gws returned an unexpected JSON value")
        return value

    def _get_message(self, message_id: str) -> dict[str, Any]:
        parameters = {
            "userId": "me",
            "id": message_id,
            "format": "full",
        }
        return self._gws(
            "gmail",
            "users",
            "messages",
            "get",
            "--params",
            json.dumps(parameters),
        )

    def archive_message(self, message_id: str) -> None:
        """Remove the Inbox label from one acknowledged Gmail message."""
        parameters = {"userId": "me", "id": message_id}
        body = {"removeLabelIds": ["INBOX"]}
        self._gws(
            "gmail",
            "users",
            "messages",
            "modify",
            "--params",
            json.dumps(parameters),
            "--json",
            json.dumps(body),
        )

    def fetch_recent(self, *, since_timestamp_ms: int) -> list[dict[str, Any]]:
        """Return extracted Gmail records newer than the supplied epoch time."""
        parameters = {
            "userId": "me",
            "maxResults": self._max_results,
            "q": (
                f"after:{int(since_timestamp_ms) // 1000} "
                f"in:anywhere ({_QUERY_KEYWORDS})"
            ),
        }
        listing = self._gws(
            "gmail",
            "users",
            "messages",
            "list",
            "--params",
            json.dumps(parameters),
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
                        "utf-8",
                        errors="replace",
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
            r"<(?:style|script)[^>]*>.*?</(?:style|script)>",
            " ",
            text,
            flags=re.I | re.S,
        )
        text = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()
