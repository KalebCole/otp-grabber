import base64
import json
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

from agent.otp_grabber.config import generate_config, load_config, update_gmail_backend
from agent.otp_grabber.sources.gmail import GmailSource, _QUERY_KEYWORDS
from agent.otp_grabber.sources.messages import MessagesSource

from agent.tests.test_extractor import typedstream_body


def encode_gmail_body(text: str) -> str:
    return base64.urlsafe_b64encode(text.encode("utf-8")).decode("ascii")


class RecordingRunner:
    def __init__(self, responses):
        self.responses = iter(responses)
        self.calls = []

    def __call__(self, command, **kwargs):
        self.calls.append((command, kwargs))
        return subprocess.CompletedProcess(
            command,
            returncode=0,
            stdout=next(self.responses),
            stderr="",
        )


class GmailSourceTests(unittest.TestCase):
    def test_gog_fetch_uses_protected_launcher_and_readonly_exact_authorities(self):
        runner = RecordingRunner(
            [
                json.dumps({"results": [{"id": "m1"}]}),
                json.dumps(
                    {
                        "message": {
                            "id": "m1",
                            "internalDate": "1785725100000",
                            "payload": {
                                "headers": [
                                    {"name": "From", "value": "verify@example.test"},
                                    {"name": "Subject", "value": "Your verification code"},
                                ],
                                "mimeType": "text/plain",
                                "body": {"data": encode_gmail_body("Your verification code is A7B9C2.")},
                            },
                        }
                    }
                ),
            ]
        )
        source = GmailSource(
            backend="gog",
            run_command=runner,
            launcher="/protected/direct-env.zsh",
            client="test-client",
            account="account@example.test",
        )

        records = source.fetch_recent(since_timestamp_ms=1785724800000)

        self.assertEqual([record["id"] for record in records], ["m1"])
        self.assertEqual(runner.calls[0][0], [
            "/bin/zsh", "-c", 'source "$1"; shift; exec "$@"', "--",
            "/protected/direct-env.zsh", "gog", "--client", "test-client",
            "--account", "account@example.test", "--enable-commands-exact",
            "gmail.messages.search", "--readonly", "--no-input", "--json",
            "gmail", "messages", "search",
            "after:1785724800 in:anywhere (" + _QUERY_KEYWORDS + ")",
            "--max", "12",
        ])
        self.assertEqual(runner.calls[1][0], [
            "/bin/zsh", "-c", 'source "$1"; shift; exec "$@"', "--",
            "/protected/direct-env.zsh", "gog", "--client", "test-client",
            "--account", "account@example.test", "--enable-commands-exact",
            "gmail.raw", "--readonly", "--no-input", "--json", "gmail", "raw", "m1",
        ])

    def test_gog_archive_has_only_archive_write_authority(self):
        runner = RecordingRunner(["{}"])
        source = GmailSource(
            backend="gog",
            run_command=runner,
            launcher="/protected/direct-env.zsh",
            client="test-client",
            account="account@example.test",
        )

        source.archive_message("m1")

        command = runner.calls[0][0]
        self.assertEqual(command, [
            "/bin/zsh", "-c", 'source "$1"; shift; exec "$@"', "--",
            "/protected/direct-env.zsh", "gog", "--client", "test-client",
            "--account", "account@example.test", "--enable-commands-exact",
            "gmail.archive", "--no-input", "--json", "gmail", "archive", "m1",
        ])
        self.assertNotIn("--readonly", command)

    def test_rejects_unknown_backend(self):
        with self.assertRaisesRegex(ValueError, "backend"):
            GmailSource(backend="other")

    def test_config_defaults_to_gws_and_allows_gog_opt_in(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "agent.json"
            generate_config(path, token_factory=lambda: "x" * 32)
            self.assertEqual(load_config(path).gmail_backend, "gws")

            path.write_text(
                '{"port":8877,"token":"' + "x" * 32
                + '","gmail_backend":"gog","gog_launcher":"/protected/direct-env.zsh",'
                + '"gog_client":"test-client","gog_account":"account@example.test"}'
            )
            config = load_config(path)
            self.assertEqual(config.gmail_backend, "gog")
            self.assertEqual(config.gog_launcher, "/protected/direct-env.zsh")

    def test_gog_config_requires_all_explicit_runtime_values(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "agent.json"
            path.write_text('{"port":8877,"token":"' + "x" * 32 + '","gmail_backend":"gog"}')

            with self.assertRaisesRegex(ValueError, "gog_launcher"):
                load_config(path)

    def test_gog_timeout_and_stderr_do_not_expose_runtime_configuration(self):
        secret_launcher = "/private/path/launcher.zsh"
        secret_account = "private@example.test"

        def time_out(command, **kwargs):
            raise subprocess.TimeoutExpired(command, 25)

        source = GmailSource(
            backend="gog", run_command=time_out, launcher=secret_launcher,
            client="private-client", account=secret_account,
        )
        with self.assertRaisesRegex(RuntimeError, "^gmail source timed out$") as timeout:
            source.fetch_recent(since_timestamp_ms=0)
        self.assertNotIn(secret_launcher, str(timeout.exception))
        self.assertNotIn(secret_account, str(timeout.exception))

        source = GmailSource(
            backend="gog",
            run_command=lambda command, **kwargs: subprocess.CompletedProcess(
                command, 1, "", f"failed for {secret_launcher} {secret_account}"
            ),
            launcher=secret_launcher, client="private-client", account=secret_account,
        )
        with self.assertRaisesRegex(RuntimeError, "^gmail source command failed$") as failed:
            source.fetch_recent(since_timestamp_ms=0)
        self.assertNotIn(secret_launcher, str(failed.exception))
        self.assertNotIn(secret_account, str(failed.exception))

    def test_atomic_backend_update_preserves_core_config_and_removes_gog_values_on_rollback(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "agent.json"
            generate_config(path, token_factory=lambda: "x" * 32)

            update_gmail_backend(
                path, backend="gog", gog_launcher="/protected/launcher.zsh",
                gog_client="test-client", gog_account="account@example.test",
            )
            self.assertEqual(load_config(path).gmail_backend, "gog")
            self.assertEqual(load_config(path).token, "x" * 32)

            update_gmail_backend(path, backend="gws")
            payload = json.loads(path.read_text())
            self.assertEqual(load_config(path).gmail_backend, "gws")
            self.assertNotIn("gog_account", payload)

    def test_gog_envelope_canary_uses_only_readonly_search_and_raw(self):
        runner = RecordingRunner([
            json.dumps({"results": [{"id": "listed-message"}]}),
            json.dumps({"message": {"id": "known-message", "payload": {}}}),
        ])
        source = GmailSource(
            backend="gog", run_command=runner, launcher="/protected/launcher.zsh",
            client="test-client", account="account@example.test",
        )

        result = source.verify_gog_envelopes(message_id="known-message", since_timestamp_ms=0)

        self.assertEqual(result, {"listing_count": 1, "message_id": "known-message"})
        for command, _ in runner.calls:
            self.assertIn("--readonly", command)
            self.assertNotIn("gmail.archive", command)

    def test_fetches_real_shaped_messages_with_file_keyring(self):
        runner = RecordingRunner(
            [
                json.dumps(
                    {
                        "messages": [
                            {"id": "18f1a2b3c4d", "threadId": "thread-1"}
                        ],
                        "resultSizeEstimate": 1,
                    }
                ),
                "Using keyring backend: file\n"
                + json.dumps(
                    {
                        "id": "18f1a2b3c4d",
                        "threadId": "thread-1",
                        "labelIds": ["INBOX"],
                        "internalDate": "1785725100000",
                        "payload": {
                            "mimeType": "multipart/alternative",
                            "headers": [
                                {
                                    "name": "From",
                                    "value": "Example <verify@example.test>",
                                },
                                {
                                    "name": "Subject",
                                    "value": "Your verification code",
                                },
                            ],
                            "body": {"size": 0},
                            "parts": [
                                {
                                    "mimeType": "text/plain",
                                    "body": {
                                        "size": 41,
                                        "data": encode_gmail_body(
                                            "Your verification code is A7B9C2."
                                        ),
                                    },
                                }
                            ],
                        },
                    }
                ),
            ]
        )
        source = GmailSource(
            run_command=runner,
            executable="gws",
            environment={"PATH": "/usr/bin"},
        )

        records = source.fetch_recent(since_timestamp_ms=1785724800000)

        self.assertEqual(
            records,
            [
                {
                    "id": "18f1a2b3c4d",
                    "source": "gmail",
                    "code": "A7B9C2",
                    "sender": "Example <verify@example.test>",
                    "subject": "Your verification code",
                    "timestamp_ms": 1785725100000,
                }
            ],
        )
        self.assertEqual(len(runner.calls), 2)
        list_command, list_options = runner.calls[0]
        self.assertEqual(list_command[:5], ["gws", "gmail", "users", "messages", "list"])
        list_params = json.loads(list_command[list_command.index("--params") + 1])
        self.assertEqual(list_params["userId"], "me")
        self.assertIn("after:1785724800", list_params["q"])
        self.assertEqual(
            list_options["env"]["GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND"],
            "file",
        )


class RecordingConnector:
    def __init__(self, connection):
        self.connection = connection
        self.calls = []

    def __call__(self, database, **kwargs):
        self.calls.append((database, kwargs))
        return self.connection


class MessagesSourceTests(unittest.TestCase):
    def setUp(self):
        self.connection = sqlite3.connect(":memory:")
        self.connection.executescript(
            """
            CREATE TABLE handle (
                ROWID INTEGER PRIMARY KEY,
                id TEXT
            );
            CREATE TABLE message (
                ROWID INTEGER PRIMARY KEY,
                handle_id INTEGER,
                text TEXT,
                attributedBody BLOB,
                date INTEGER,
                service TEXT,
                is_from_me INTEGER
            );
            """
        )

    def tearDown(self):
        try:
            self.connection.close()
        except sqlite3.ProgrammingError:
            pass

    @staticmethod
    def apple_nanoseconds(unix_seconds: int) -> int:
        return (unix_seconds - 978307200) * 1_000_000_000

    def test_reads_attributed_sms_from_read_only_database_with_sender_priority(self):
        cutoff_seconds = 1_785_724_800
        self.connection.execute(
            "INSERT INTO handle (ROWID, id) VALUES (?, ?)",
            (1, "63189(smsft)"),
        )
        body = "93754447 is your Parcel Pending access code."
        self.connection.execute(
            """
            INSERT INTO message
                (ROWID, handle_id, text, attributedBody, date, service, is_from_me)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                1,
                1,
                None,
                typedstream_body(body),
                self.apple_nanoseconds(cutoff_seconds + 10),
                "SMS",
                0,
            ),
        )
        for index in range(85):
            handle_id = index + 2
            self.connection.execute(
                "INSERT INTO handle (ROWID, id) VALUES (?, ?)",
                (handle_id, f"+1206555{index:04d}"),
            )
            self.connection.execute(
                """
                INSERT INTO message
                    (ROWID, handle_id, text, attributedBody, date, service, is_from_me)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    index + 2,
                    handle_id,
                    "Ordinary conversation",
                    None,
                    self.apple_nanoseconds(cutoff_seconds + 100 + index),
                    "iMessage",
                    0,
                ),
            )
        self.connection.commit()
        connector = RecordingConnector(self.connection)
        source = MessagesSource(
            database_path="/fixture/chat.db",
            connect=connector,
        )

        records = source.fetch_recent(
            since_timestamp_ms=cutoff_seconds * 1000
        )

        self.assertEqual(
            records,
            [
                {
                    "id": "1",
                    "source": "messages",
                    "code": "93754447",
                    "sender": "63189",
                    "subject": body,
                    "timestamp_ms": (cutoff_seconds + 10) * 1000,
                }
            ],
        )
        self.assertEqual(
            connector.calls,
            [
                (
                    "file:/fixture/chat.db?mode=ro",
                    {"uri": True},
                )
            ],
        )


if __name__ == "__main__":
    unittest.main()
