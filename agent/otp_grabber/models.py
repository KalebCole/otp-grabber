"""JSON-ready value models for the source-agent service."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping


@dataclass(frozen=True, slots=True)
class CodeRecord:
    id: str
    source: str
    code: str
    sender: str
    subject: str
    timestamp_ms: int

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any]) -> CodeRecord:
        timestamp = value.get("timestamp_ms")
        if isinstance(timestamp, bool) or not isinstance(timestamp, int):
            raise ValueError("record timestamp must be an integer")

        record = cls(
            id=str(value.get("id", "")).strip(),
            source=str(value.get("source", "")).strip(),
            code=str(value.get("code", "")).strip(),
            sender=str(value.get("sender", "")).strip(),
            subject=str(value.get("subject", "")).strip(),
            timestamp_ms=timestamp,
        )
        if not record.id or not record.source or not record.code:
            raise ValueError("record is missing a required value")
        return record

    def to_dict(self) -> dict[str, str | int]:
        return {
            "id": self.id,
            "source": self.source,
            "code": self.code,
            "sender": self.sender,
            "subject": self.subject,
            "timestamp_ms": self.timestamp_ms,
        }


@dataclass(frozen=True, slots=True)
class SourceError:
    source: str
    message: str

    def to_dict(self) -> dict[str, str]:
        return {"source": self.source, "message": self.message}


@dataclass(frozen=True, slots=True)
class PollResult:
    latest: CodeRecord | None
    errors: tuple[SourceError, ...]

    def to_dict(self) -> dict[str, object]:
        return {
            "latest": self.latest.to_dict() if self.latest else None,
            "errors": [error.to_dict() for error in self.errors],
        }


@dataclass(frozen=True, slots=True)
class HistoryResult:
    codes: tuple[CodeRecord, ...]

    def to_dict(self) -> dict[str, object]:
        return {"codes": [record.to_dict() for record in self.codes]}


@dataclass(frozen=True, slots=True)
class ArchiveResult:
    id: str
    archived: bool
    already_archived: bool

    def to_dict(self) -> dict[str, str | bool]:
        return {
            "id": self.id,
            "archived": self.archived,
            "already_archived": self.already_archived,
        }
