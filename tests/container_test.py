#!/usr/bin/env pytest -vs
"""Tests for postfix container."""

# Standard Python Libraries
from email.message import EmailMessage
from imaplib import IMAP4_SSL
import os
import smtplib
import time
from typing import Any, List, Tuple

import pytest

ARCHIVE_PW: str = "foobar"
ARCHIVE_USER: str = "archive"
DOMAIN: str = "example.com"
IMAP_PORT: int = 1993
MESSAGE: str = """
This is a test message sent during the unit tests.
"""
READY_MESSAGE: str = "daemon started"
RELEASE_TAG: str = os.getenv("RELEASE_TAG", "")
TEST_SEND_PW: str = "testpassword"
TEST_SEND_USER: str = "testsender1"

def test_container_count(dockerc: Any) -> None:
    """Verify the test composition and container."""
    assert (
        len(dockerc.compose.ps(all=True)) == 1
    ), "Wrong number of containers were started."


def test_wait_for_ready(main_container: Any) -> None:
    """Wait for container to be ready."""
    TIMEOUT: int = 10
    for i in range(TIMEOUT):
        if READY_MESSAGE in main_container.logs():
            break
        time.sleep(1)
    else:
        raise Exception(
            f"Container does not seem ready.  "
            f'Expected "{READY_MESSAGE}" in the log within {TIMEOUT} seconds.'
        )


@pytest.mark.parametrize("port", [1025, 1587])
@pytest.mark.parametrize("to_user", [ARCHIVE_USER, TEST_SEND_USER])
def test_sending_mail(port: int, to_user: str) -> None:
    """Send an email message to the server."""
    msg = EmailMessage()
    msg.set_content(MESSAGE)
    msg["Subject"] = f"Test Message on port {port}"
    msg["From"] = f"test@{DOMAIN}"
    msg["To"] = f"{to_user}@{DOMAIN}"
    with smtplib.SMTP("localhost", port=port) as s:
        s.send_message(msg)


@pytest.mark.parametrize(
    "username,password",
    [
        (ARCHIVE_USER, ARCHIVE_PW),
        (TEST_SEND_USER, TEST_SEND_PW),
        pytest.param(ARCHIVE_USER, TEST_SEND_PW, marks=pytest.mark.xfail),
        pytest.param("your_mom", "so_fat", marks=pytest.mark.xfail),
    ],
)
def test_imap_login(username: str, password: str) -> None:
    """Test logging in to the IMAP server."""
    with IMAP4_SSL("localhost", IMAP_PORT) as m:
        m.login(username, password)


@pytest.mark.parametrize(
    "user,password", [(ARCHIVE_USER, ARCHIVE_PW), (TEST_SEND_USER, TEST_SEND_PW)]
)
def test_imap_messages_exist(user: str, password: str) -> None:
    """Test test existence of our test messages."""
    with IMAP4_SSL("localhost", IMAP_PORT) as m:
        m.login(user, password)
        typ, data = m.select()
        assert typ == "OK", f"Select did not return OK status for {user}"
        message_count = int(data[0])
        print(f"{user} inbox message count: {message_count}")
        assert message_count > 0, f"Expected message in the {user} inbox"


@pytest.mark.parametrize(
    "username,password", [(ARCHIVE_USER, ARCHIVE_PW), (TEST_SEND_USER, TEST_SEND_PW)]
)
def test_imap_reading(username: str, password: str) -> None:
    """Test receiving message from the IMAP server."""
    with IMAP4_SSL("localhost", IMAP_PORT) as m:
        m.login(username, password)
        typ, data = m.select()
        assert typ == "OK", "Select did not return OK status"
        message_count = int(data[0])
        print(f"inbox message count: {message_count}")
        typ, data = m.search(None, "ALL")
        assert typ == "OK", "Search did not return OK status"
        message_numbers = data[0].split()
        for num in message_numbers:
            typ, data = m.fetch(num, "(RFC822)")
            assert typ == "OK", f"Fetch of message {num} did not return OK status"
            print("-" * 40)
            print(f"Message: {num}")
            print(data[0][1].decode("utf-8"))
            # mark message as deleted
            typ, data = m.store(num, "+FLAGS", "\\Deleted")
            assert (
                typ == "OK"
            ), f"Storing '\\deleted' flag on message {num} did not return OK status"
        # expunge all deleted messages
        typ, data = m.expunge()
        assert typ == "OK", "Expunge did not return OK status"


@pytest.mark.parametrize(
    "username,password", [(ARCHIVE_USER, ARCHIVE_PW), (TEST_SEND_USER, TEST_SEND_PW)]
)
def test_imap_delete_all(username: str, password: str) -> None:
    """Test deleting messages from the IMAP server."""
    with IMAP4_SSL("localhost", IMAP_PORT) as m:
        m.login(username, password)
        typ, data = m.select()
        assert typ == "OK", "Select did not return OK status"
        typ, data = m.search(None, "ALL")
        assert typ == "OK", "Search did not return OK status"
        message_numbers = data[0].split()
        for num in message_numbers:
            # mark message as deleted
            typ, data = m.store(num, "+FLAGS", "\\Deleted")
            assert (
                typ == "OK"
            ), f"Storing '\\deleted' flag on message {num} did not return OK status"
        # expunge all deleted messages
        typ, data = m.expunge()
        assert typ == "OK", "Expunge did not return OK status"


@pytest.mark.parametrize(
    "username,password", [(ARCHIVE_USER, ARCHIVE_PW), (TEST_SEND_USER, TEST_SEND_PW)]
)
def test_imap_messages_cleared(username: str, password: str) -> None:
    """Test that all messages were expunged."""
    with IMAP4_SSL("localhost", IMAP_PORT) as m:
        m.login(username, password)
        typ, data = m.select()
        assert typ == "OK", "Select did not return OK status"
        message_count = int(data[0])
        print(f"inbox message count: {message_count}")
        assert message_count == 0, "Expected the inbox to be empty"


@pytest.mark.skipif(
    RELEASE_TAG in [None, ""], reason="this is not a release (RELEASE_TAG not set)"
)