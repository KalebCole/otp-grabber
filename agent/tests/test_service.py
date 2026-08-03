import json
import subprocess
import threading
import unittest

from agent.otp_grabber.service import FreshestCodeService
from agent.otp_grabber.sources.gmail import GmailSource


NOW_MS = 1_785_725_400_000


def record(
    message_id,
    source,
    code,
    timestamp_ms,
    *,
    sender="sender@example.test",
):
    return {
        "id": message_id,
        "source": source,
        "code": code,
        "sender": sender,
        "subject": "Verification code",
        "timestamp_ms": timestamp_ms,
    }


class StubSource:
    def __init__(self, responses):
        self._responses = iter(responses)
        self.cutoffs = []

    def fetch_recent(self, *, since_timestamp_ms):
        self.cutoffs.append(since_timestamp_ms)
        response = next(self._responses)
        if isinstance(response, BaseException):
            raise response
        return response


class CoordinatedSource:
    def __init__(self, started, peer_started, response):
        self._started = started
        self._peer_started = peer_started
        self._response = response

    def fetch_recent(self, *, since_timestamp_ms):
        self._started.set()
        if not self._peer_started.wait(timeout=1):
            raise RuntimeError("other source was not polled concurrently")
        return self._response


class ArchiveCapableSource(StubSource):
    def __init__(self, responses, archive_outcomes=()):
        super().__init__(responses)
        self._archive_outcomes = iter(archive_outcomes)
        self.archive_calls = []

    def archive_message(self, message_id):
        self.archive_calls.append(message_id)
        outcome = next(self._archive_outcomes, None)
        if isinstance(outcome, BaseException):
            raise outcome


class BlockingArchiveSource(ArchiveCapableSource):
    def __init__(
        self,
        responses,
        archive_started,
        archive_release,
        archive_outcomes=(),
    ):
        super().__init__(responses, archive_outcomes)
        self._archive_started = archive_started
        self._archive_release = archive_release

    def archive_message(self, message_id):
        self.archive_calls.append(message_id)
        self._archive_started.set()
        if not self._archive_release.wait(timeout=5):
            raise RuntimeError("archive release was not signaled")
        outcome = next(self._archive_outcomes, None)
        if isinstance(outcome, BaseException):
            raise outcome


class WaitObservedCondition(threading.Condition):
    def __init__(self, lock, wait_started):
        super().__init__(lock)
        self._wait_started = wait_started

    def wait(self, timeout=None):
        self._wait_started.set()
        return super().wait(timeout)


class RecordingArchiveRunner:
    def __init__(self):
        self.calls = []

    def __call__(self, command, **kwargs):
        self.calls.append((command, kwargs))
        return subprocess.CompletedProcess(
            command,
            returncode=0,
            stdout="{}",
            stderr="",
        )


class FreshestCodeServiceTests(unittest.TestCase):
    def make_service(
        self,
        gmail,
        messages,
        *,
        clock_ms=lambda: NOW_MS,
        recent_window_ms=600_000,
        history_limit=10,
    ):
        return FreshestCodeService(
            gmail_source=gmail,
            messages_source=messages,
            clock_ms=clock_ms,
            recent_window_ms=recent_window_ms,
            history_limit=history_limit,
        )

    def test_polls_gmail_and_messages_concurrently(self):
        gmail_started = threading.Event()
        messages_started = threading.Event()
        gmail = CoordinatedSource(
            gmail_started,
            messages_started,
            [record("g-1", "gmail", "123456", NOW_MS - 20_000)],
        )
        messages = CoordinatedSource(
            messages_started,
            gmail_started,
            [record("m-1", "messages", "654321", NOW_MS - 10_000)],
        )

        result = self.make_service(gmail, messages).poll_latest()

        self.assertEqual(result.latest.id, "m-1")
        self.assertEqual(result.errors, ())

    def test_returns_freshest_record_and_newest_first_history(self):
        gmail = StubSource(
            [[record("g-1", "gmail", "111111", NOW_MS - 30_000)]]
        )
        messages = StubSource(
            [
                [
                    record("m-old", "messages", "222222", NOW_MS - 40_000),
                    record("m-new", "messages", "333333", NOW_MS - 10_000),
                ]
            ]
        )
        service = self.make_service(gmail, messages)

        result = service.poll_latest()

        self.assertEqual(result.latest.id, "m-new")
        self.assertEqual(
            [item.id for item in service.get_history().codes],
            ["m-new", "g-1", "m-old"],
        )
        self.assertEqual(
            result.to_dict(),
            {
                "latest": {
                    "id": "m-new",
                    "source": "messages",
                    "code": "333333",
                    "sender": "sender@example.test",
                    "subject": "Verification code",
                    "timestamp_ms": NOW_MS - 10_000,
                },
                "errors": [],
            },
        )

    def test_returns_available_source_with_partial_failure(self):
        gmail = StubSource([RuntimeError("gmail unavailable")])
        messages = StubSource(
            [[record("m-1", "messages", "654321", NOW_MS - 10_000)]]
        )

        result = self.make_service(gmail, messages).poll_latest()

        self.assertEqual(result.latest.id, "m-1")
        self.assertEqual(
            [error.to_dict() for error in result.errors],
            [{"source": "gmail", "message": "gmail unavailable"}],
        )

    def test_returns_all_source_errors_when_every_source_fails(self):
        gmail = StubSource([RuntimeError("gmail unavailable")])
        messages = StubSource([RuntimeError("messages unavailable")])

        result = self.make_service(gmail, messages).poll_latest()

        self.assertIsNone(result.latest)
        self.assertEqual(
            result.to_dict(),
            {
                "latest": None,
                "errors": [
                    {"source": "gmail", "message": "gmail unavailable"},
                    {"source": "messages", "message": "messages unavailable"},
                ],
            },
        )

    def test_history_is_bounded_and_deduplicates_code_source_and_sender(self):
        gmail = StubSource(
            [
                [record("g-1", "gmail", "111111", NOW_MS - 40_000)],
                [record("g-2", "gmail", "111111", NOW_MS - 30_000)],
                [record("g-3", "gmail", "222222", NOW_MS - 20_000)],
                [record("g-4", "gmail", "333333", NOW_MS - 10_000)],
            ]
        )
        messages = StubSource([[], [], [], []])
        service = self.make_service(gmail, messages, history_limit=2)

        service.poll_latest()
        service.poll_latest()
        self.assertEqual(
            [item.id for item in service.get_history().codes],
            ["g-2"],
        )
        service.poll_latest()
        service.poll_latest()

        self.assertEqual(
            [item.id for item in service.get_history().codes],
            ["g-4", "g-3"],
        )

    def test_filters_expired_records_and_expires_existing_history(self):
        current_time = [NOW_MS]
        gmail = StubSource(
            [[record("g-old", "gmail", "111111", NOW_MS - 60_001)], []]
        )
        messages = StubSource(
            [[record("m-fresh", "messages", "222222", NOW_MS - 60_000)], []]
        )
        service = self.make_service(
            gmail,
            messages,
            clock_ms=lambda: current_time[0],
            recent_window_ms=60_000,
        )

        first = service.poll_latest()
        self.assertEqual(first.latest.id, "m-fresh")
        self.assertEqual(gmail.cutoffs, [NOW_MS - 60_000])

        current_time[0] += 60_001
        second = service.poll_latest()

        self.assertIsNone(second.latest)
        self.assertEqual(service.get_history().codes, ())


class ArchiveAcknowledgementTests(unittest.TestCase):
    def make_service(self, gmail, messages):
        return FreshestCodeService(
            gmail_source=gmail,
            messages_source=messages,
            clock_ms=lambda: NOW_MS,
        )

    def acknowledge_concurrently(
        self,
        service,
        message_id,
        archive_started,
        archive_release,
    ):
        waiter_started = threading.Event()
        service._archive_condition = WaitObservedCondition(
            service._lock,
            waiter_started,
        )
        results = [None, None]
        errors = [None, None]

        def acknowledge(index):
            try:
                results[index] = service.acknowledge_archive(message_id)
            except BaseException as error:
                errors[index] = error

        first = threading.Thread(target=acknowledge, args=(0,))
        second = threading.Thread(target=acknowledge, args=(1,))
        first.start()
        try:
            self.assertTrue(
                archive_started.wait(timeout=1),
                "external archive call did not start",
            )
            second.start()
            self.assertTrue(
                waiter_started.wait(timeout=1),
                "concurrent acknowledgement did not wait for the active attempt",
            )
        finally:
            archive_release.set()
            first.join(timeout=1)
            if second.ident is not None:
                second.join(timeout=1)

        self.assertFalse(first.is_alive())
        self.assertFalse(second.is_alive())
        return results, errors

    def test_rejects_unknown_and_returned_non_gmail_ids(self):
        gmail = ArchiveCapableSource([[]])
        messages = StubSource(
            [[record("m-1", "messages", "654321", NOW_MS - 10_000)]]
        )
        service = self.make_service(gmail, messages)
        service.poll_latest()

        with self.assertRaisesRegex(ValueError, "not eligible"):
            service.acknowledge_archive("unknown")
        with self.assertRaisesRegex(ValueError, "not eligible"):
            service.acknowledge_archive("m-1")

        self.assertEqual(gmail.archive_calls, [])

    def test_archives_a_returned_gmail_id_once_and_retry_is_idempotent(self):
        gmail = ArchiveCapableSource(
            [[record("g-1", "gmail", "123456", NOW_MS - 10_000)]]
        )
        service = self.make_service(gmail, StubSource([[]]))
        service.poll_latest()

        first = service.acknowledge_archive("g-1")
        retry = service.acknowledge_archive("g-1")

        self.assertEqual(
            first.to_dict(),
            {"id": "g-1", "archived": True, "already_archived": False},
        )
        self.assertEqual(
            retry.to_dict(),
            {"id": "g-1", "archived": True, "already_archived": True},
        )
        self.assertEqual(gmail.archive_calls, ["g-1"])

    def test_archive_eligibility_is_pruned_with_bounded_history(self):
        gmail = ArchiveCapableSource(
            [
                [record("g-1", "gmail", "123456", NOW_MS - 20_000)],
                [record("g-2", "gmail", "654321", NOW_MS - 10_000)],
            ]
        )
        service = FreshestCodeService(
            gmail_source=gmail,
            messages_source=StubSource([[], []]),
            clock_ms=lambda: NOW_MS,
            history_limit=1,
        )
        service.poll_latest()
        service.acknowledge_archive("g-1")

        service.poll_latest()

        with self.assertRaisesRegex(ValueError, "not eligible"):
            service.acknowledge_archive("g-1")
        self.assertEqual(gmail.archive_calls, ["g-1"])

    def test_history_access_proceeds_while_archive_io_is_blocked(self):
        archive_started = threading.Event()
        archive_release = threading.Event()
        history_returned = threading.Event()
        gmail = BlockingArchiveSource(
            [[record("g-1", "gmail", "123456", NOW_MS - 10_000)]],
            archive_started,
            archive_release,
        )
        service = self.make_service(gmail, StubSource([[]]))
        service.poll_latest()
        archive_results = []
        history_results = []

        def archive():
            archive_results.append(service.acknowledge_archive("g-1"))

        def read_history():
            history_results.append(service.get_history())
            history_returned.set()

        archive_thread = threading.Thread(
            target=archive,
        )
        history_thread = threading.Thread(target=read_history)

        archive_thread.start()
        self.assertTrue(archive_started.wait(timeout=1))
        history_thread.start()
        try:
            self.assertTrue(
                history_returned.wait(timeout=1),
                "get_history blocked behind archive I/O",
            )
        finally:
            archive_release.set()
            archive_thread.join(timeout=1)
            history_thread.join(timeout=1)
        self.assertFalse(archive_thread.is_alive())
        self.assertFalse(history_thread.is_alive())
        self.assertEqual(len(archive_results), 1)
        self.assertEqual(len(history_results), 1)

    def test_concurrent_acknowledgements_share_one_successful_archive_attempt(self):
        archive_started = threading.Event()
        archive_release = threading.Event()
        gmail = BlockingArchiveSource(
            [[record("g-1", "gmail", "123456", NOW_MS - 10_000)]],
            archive_started,
            archive_release,
        )
        service = self.make_service(gmail, StubSource([[]]))
        service.poll_latest()

        results, errors = self.acknowledge_concurrently(
            service,
            "g-1",
            archive_started,
            archive_release,
        )

        self.assertEqual(errors, [None, None])
        self.assertEqual(gmail.archive_calls, ["g-1"])
        self.assertEqual(
            sorted(result.already_archived for result in results),
            [False, True],
        )

    def test_concurrent_archive_failure_reaches_both_callers_and_can_retry(self):
        archive_started = threading.Event()
        archive_release = threading.Event()
        gmail = BlockingArchiveSource(
            [[record("g-1", "gmail", "123456", NOW_MS - 10_000)]],
            archive_started,
            archive_release,
            [RuntimeError("modify failed"), None],
        )
        service = self.make_service(gmail, StubSource([[]]))
        service.poll_latest()

        results, errors = self.acknowledge_concurrently(
            service,
            "g-1",
            archive_started,
            archive_release,
        )

        self.assertEqual(results, [None, None])
        self.assertTrue(
            all(
                isinstance(error, RuntimeError)
                and str(error) == "modify failed"
                for error in errors
            )
        )
        self.assertIs(errors[0], errors[1])
        self.assertEqual(gmail.archive_calls, ["g-1"])

        retry = service.acknowledge_archive("g-1")

        self.assertFalse(retry.already_archived)
        self.assertEqual(gmail.archive_calls, ["g-1", "g-1"])

    def test_non_latest_gmail_id_becomes_eligible_only_when_history_is_returned(self):
        gmail = ArchiveCapableSource(
            [[record("g-older", "gmail", "123456", NOW_MS - 20_000)]]
        )
        messages = StubSource(
            [[record("m-newer", "messages", "654321", NOW_MS - 10_000)]]
        )
        service = self.make_service(gmail, messages)
        service.poll_latest()

        with self.assertRaisesRegex(ValueError, "not eligible"):
            service.acknowledge_archive("g-older")

        service.get_history()
        service.acknowledge_archive("g-older")
        self.assertEqual(gmail.archive_calls, ["g-older"])

    def test_archive_failure_can_be_retried_until_it_succeeds(self):
        gmail = ArchiveCapableSource(
            [[record("g-1", "gmail", "123456", NOW_MS - 10_000)]],
            [RuntimeError("modify failed"), None],
        )
        service = self.make_service(gmail, StubSource([[]]))
        service.poll_latest()

        with self.assertRaisesRegex(RuntimeError, "modify failed"):
            service.acknowledge_archive("g-1")
        result = service.acknowledge_archive("g-1")

        self.assertFalse(result.already_archived)
        self.assertEqual(gmail.archive_calls, ["g-1", "g-1"])

    def test_gmail_archive_uses_messages_modify_to_remove_inbox(self):
        runner = RecordingArchiveRunner()
        source = GmailSource(
            run_command=runner,
            executable="gws",
            environment={"PATH": "/usr/bin"},
        )

        source.archive_message("g-1")

        self.assertEqual(len(runner.calls), 1)
        command, _options = runner.calls[0]
        self.assertEqual(
            command[:5],
            ["gws", "gmail", "users", "messages", "modify"],
        )
        params = json.loads(command[command.index("--params") + 1])
        body = json.loads(command[command.index("--json") + 1])
        self.assertEqual(params, {"userId": "me", "id": "g-1"})
        self.assertEqual(body, {"removeLabelIds": ["INBOX"]})


if __name__ == "__main__":
    unittest.main()
