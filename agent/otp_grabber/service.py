"""Coordinate OTP sources and retain a small recent-code history."""

from __future__ import annotations

import time
from collections.abc import Callable, Mapping, Sequence
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from threading import Condition, Lock
from typing import Any, Protocol

from agent.otp_grabber.models import (
    ArchiveResult,
    CodeRecord,
    HistoryResult,
    PollResult,
    SourceError,
)


class CodeSource(Protocol):
    def fetch_recent(
        self, *, since_timestamp_ms: int
    ) -> Sequence[Mapping[str, Any]]: ...


class GmailSource(CodeSource, Protocol):
    def archive_message(self, message_id: str) -> None: ...


@dataclass
class _ArchiveAttempt:
    done: bool = False
    error: BaseException | None = None
    waiters: int = 0


class FreshestCodeService:
    """Poll Gmail and Messages concurrently and retain fresh unique records."""

    def __init__(
        self,
        *,
        gmail_source: GmailSource,
        messages_source: CodeSource,
        clock_ms: Callable[[], int] | None = None,
        recent_window_ms: int = 600_000,
        history_limit: int = 20,
    ) -> None:
        if recent_window_ms <= 0:
            raise ValueError("recent_window_ms must be positive")
        if history_limit <= 0:
            raise ValueError("history_limit must be positive")
        self._sources = {
            "gmail": gmail_source,
            "messages": messages_source,
        }
        self._gmail_source = gmail_source
        self._clock_ms = clock_ms or (lambda: time.time_ns() // 1_000_000)
        self._recent_window_ms = recent_window_ms
        self._history_limit = history_limit
        self._history: list[CodeRecord] = []
        self._eligible_gmail_ids: set[str] = set()
        self._archived_gmail_ids: set[str] = set()
        self._lock = Lock()
        self._archive_condition = Condition(self._lock)
        self._archive_attempts: dict[str, _ArchiveAttempt] = {}

    def poll_latest(self) -> PollResult:
        now_ms = int(self._clock_ms())
        cutoff_ms = now_ms - self._recent_window_ms
        with ThreadPoolExecutor(max_workers=len(self._sources)) as executor:
            futures = {
                name: executor.submit(
                    source.fetch_recent,
                    since_timestamp_ms=cutoff_ms,
                )
                for name, source in self._sources.items()
            }

            records: list[CodeRecord] = []
            errors: list[SourceError] = []
            for source_name, future in futures.items():
                try:
                    source_records = future.result()
                except Exception as error:
                    errors.append(SourceError(source_name, str(error)))
                    continue
                records.extend(
                    self._valid_records(
                        source_records,
                        source_name=source_name,
                        cutoff_ms=cutoff_ms,
                        now_ms=now_ms,
                    )
                )

        records.sort(key=lambda item: item.timestamp_ms, reverse=True)
        with self._lock:
            self._merge_history(records, cutoff_ms=cutoff_ms)
            self._prune_archive_state()
            if records and records[0].source == "gmail":
                self._eligible_gmail_ids.add(records[0].id)
        return PollResult(
            latest=records[0] if records else None,
            errors=tuple(errors),
        )

    def get_history(self) -> HistoryResult:
        cutoff_ms = int(self._clock_ms()) - self._recent_window_ms
        with self._lock:
            self._history = [
                record
                for record in self._history
                if record.timestamp_ms >= cutoff_ms
            ]
            result = HistoryResult(tuple(self._history))
            self._prune_archive_state()
            self._eligible_gmail_ids.update(
                record.id for record in result.codes if record.source == "gmail"
            )
            return result

    def acknowledge_archive(self, message_id: str) -> ArchiveResult:
        normalized_id = str(message_id).strip()
        with self._archive_condition:
            attempt = self._archive_attempts.get(normalized_id)
            if attempt is not None:
                attempt.waiters += 1
                try:
                    while not attempt.done:
                        self._archive_condition.wait()
                    if attempt.error is not None:
                        raise attempt.error
                    return ArchiveResult(normalized_id, True, True)
                finally:
                    attempt.waiters -= 1
                    if attempt.done and attempt.waiters == 0:
                        self._archive_attempts.pop(normalized_id, None)
            if normalized_id not in self._eligible_gmail_ids:
                raise ValueError("message ID is not eligible for Gmail archive")
            if normalized_id in self._archived_gmail_ids:
                return ArchiveResult(normalized_id, True, True)

            attempt = _ArchiveAttempt()
            self._archive_attempts[normalized_id] = attempt

        try:
            self._gmail_source.archive_message(normalized_id)
        except BaseException as error:
            with self._archive_condition:
                attempt.error = error
                attempt.done = True
                self._archive_condition.notify_all()
                if attempt.waiters == 0:
                    self._archive_attempts.pop(normalized_id, None)
            raise

        with self._archive_condition:
            if normalized_id in self._eligible_gmail_ids:
                self._archived_gmail_ids.add(normalized_id)
            attempt.done = True
            self._archive_condition.notify_all()
            if attempt.waiters == 0:
                self._archive_attempts.pop(normalized_id, None)
        return ArchiveResult(normalized_id, True, False)

    @staticmethod
    def _valid_records(
        values: Sequence[Mapping[str, Any]],
        *,
        source_name: str,
        cutoff_ms: int,
        now_ms: int,
    ) -> list[CodeRecord]:
        records = []
        for value in values:
            try:
                record = CodeRecord.from_mapping(value)
            except (AttributeError, TypeError, ValueError):
                continue
            if (
                record.source == source_name
                and cutoff_ms <= record.timestamp_ms <= now_ms
            ):
                records.append(record)
        return records

    def _merge_history(
        self,
        records: Sequence[CodeRecord],
        *,
        cutoff_ms: int,
    ) -> None:
        by_identity: dict[tuple[str, str, str], CodeRecord] = {}
        for record in [*self._history, *records]:
            if record.timestamp_ms < cutoff_ms:
                continue
            identity = (record.code, record.source, record.sender)
            existing = by_identity.get(identity)
            if existing is None or record.timestamp_ms > existing.timestamp_ms:
                by_identity[identity] = record
        self._history = sorted(
            by_identity.values(),
            key=lambda item: item.timestamp_ms,
            reverse=True,
        )[: self._history_limit]

    def _prune_archive_state(self) -> None:
        recent_gmail_ids = {
            record.id for record in self._history if record.source == "gmail"
        }
        self._eligible_gmail_ids.intersection_update(recent_gmail_ids)
        self._archived_gmail_ids.intersection_update(recent_gmail_ids)
