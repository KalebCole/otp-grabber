import base64
import json
import sqlite3
import subprocess
import unittest

from agent.otp_grabber.sources.gmail import GmailSource
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
