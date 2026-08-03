"""Read verification codes from Apple's Messages database."""

from __future__ import annotations

import re
import sqlite3
from collections.abc import Callable
from os import PathLike
from typing import Any

from agent.otp_grabber.extractor import decode_attributed_body, extract_code


_APPLE_EPOCH_MS = 978_307_200_000

_COLUMNS = """
    m.ROWID,
    COALESCE(h.id, '?') AS sender,
    m.text,
    m.attributedBody,
    m.date,
    m.service
"""

_BASE_QUERY = """
    FROM message AS m
    LEFT JOIN handle AS h ON m.handle_id = h.ROWID
    WHERE m.is_from_me = 0
      AND m.date > ?
"""

_SMS_ISH = (
    "(m.service = 'SMS' OR LENGTH(COALESCE(h.id, '')) <= 7 "
    "OR h.id LIKE '%(smsft)')"
)


class MessagesSource:
    """Read recent inbound Messages rows through an injected SQLite connector."""

    def __init__(
        self,
        *,
        database_path: str | PathLike[str],
        connect: Callable[..., sqlite3.Connection] = sqlite3.connect,
    ) -> None:
        self._database_path = str(database_path)
        self._connect = connect

    def fetch_recent(self, *, since_timestamp_ms: int) -> list[dict[str, Any]]:
        """Return extracted Messages records newer than the supplied epoch time."""
        database_uri = f"file:{self._database_path}?mode=ro"
        connection = self._connect(database_uri, uri=True)
        apple_cutoff_ns = max(
            0,
            (int(since_timestamp_ms) - _APPLE_EPOCH_MS) * 1_000_000,
        )
        try:
            sms_rows = connection.execute(
                f"""
                SELECT {_COLUMNS}
                {_BASE_QUERY}
                  AND {_SMS_ISH}
                ORDER BY m.date DESC
                LIMIT 250
                """,
                (apple_cutoff_ns,),
            ).fetchall()
            other_rows = connection.execute(
                f"""
                SELECT {_COLUMNS}
                {_BASE_QUERY}
                  AND NOT {_SMS_ISH}
                ORDER BY m.date DESC
                LIMIT 80
                """,
                (apple_cutoff_ns,),
            ).fetchall()
        finally:
            connection.close()

        rows_by_id = {int(row[0]): row for row in [*sms_rows, *other_rows]}
        ordered_rows = sorted(
            rows_by_id.values(),
            key=lambda row: int(row[4] or 0),
            reverse=True,
        )
        records = []
        for row_id, sender, text, attributed_body, date, _service in ordered_rows:
            body = text or decode_attributed_body(
                bytes(attributed_body) if attributed_body is not None else None
            )
            if not body:
                continue
            code = extract_code("", body)
            if not code:
                continue
            records.append(
                {
                    "id": str(row_id),
                    "source": "messages",
                    "code": code,
                    "sender": _clean_sender(str(sender)),
                    "subject": re.sub(r"\s+", " ", body).strip()[:120],
                    "timestamp_ms": int(date) // 1_000_000 + _APPLE_EPOCH_MS,
                }
            )
        return records


def _clean_sender(sender: str) -> str:
    return re.sub(r"\(smsft\)$", "", sender, flags=re.I).strip()
