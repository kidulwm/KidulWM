#!/usr/bin/env python3
"""KidulWM IMAP email notification watcher.

Polls a configurable IMAP server and forwards new unread-mail events into
KidulWM's notification stream. Designed for Proton Bridge on localhost, but
works with any IMAP server.

Config file:
    ~/.config/kidulwm/imap.conf

Example:
    host=127.0.0.1
    port=1143
    username=your-bridge-username
    password=your-bridge-password
    poll_seconds=30

Install:
    cp scripts/imap-watcher.py /usr/local/bin/kidulwm-imap-watcher
    cp config/systemd/user/kidulwm-imap-watcher.service ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now kidulwm-imap-watcher
"""

import configparser
import imaplib
import os
import subprocess
import sys
import time
from pathlib import Path

CONFIG_PATH = Path.home() / ".config" / "kidulwm" / "imap.conf"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 1143
DEFAULT_POLL_SECONDS = 30


def send_notification(title: str, body: str) -> None:
    try:
        subprocess.run(
            ["kidulwm-control", "notification_test", title, body, "email", "normal", "email"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        print(f"failed to send notification: {e.stderr.decode('utf-8', errors='replace')}", file=sys.stderr)
    except FileNotFoundError:
        print("kidulwm-control not found in PATH", file=sys.stderr)


def read_config() -> dict:
    cfg = {
        "host": DEFAULT_HOST,
        "port": DEFAULT_PORT,
        "username": "",
        "password": "",
        "poll_seconds": DEFAULT_POLL_SECONDS,
    }
    if not CONFIG_PATH.exists():
        return cfg
    parser = configparser.ConfigParser()
    # Allow a simple key=value file without a section header.
    with CONFIG_PATH.open("r", encoding="utf-8") as f:
        parser.read_string("[default]\n" + f.read())
    section = parser["default"]
    if section.get("host"):
        cfg["host"] = section.get("host")
    if section.get("port"):
        value = section.get("port")
        try:
            cfg["port"] = int(value) if value is not None else DEFAULT_PORT
        except ValueError:
            pass
    if section.get("username"):
        cfg["username"] = section.get("username") or ""
    if section.get("password"):
        cfg["password"] = section.get("password") or ""
    if section.get("poll_seconds"):
        value = section.get("poll_seconds")
        try:
            cfg["poll_seconds"] = int(value) if value is not None else DEFAULT_POLL_SECONDS
        except ValueError:
            pass
    return cfg


def fetch_summary(imap: imaplib.IMAP4, uid: bytes) -> tuple[str, str]:
    """Return (sender_name, subject) for a single message UID."""
    try:
        status, data = imap.uid("fetch", uid.decode("ascii"), "(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])")
        if status != "OK" or not data or data[0] is None:
            return "Email", "New message"
        header_bytes = data[0][1] if isinstance(data[0], tuple) else b""
        header = header_bytes.decode("utf-8", errors="replace")
        sender = "Email"
        subject = "New message"
        for line in header.splitlines():
            if line.lower().startswith("from:"):
                from_value = line[5:].strip()
                # Extract a display name if present: "Name" <email@example.com>
                if "<" in from_value:
                    name_part = from_value.split("<")[0].strip().strip('"').strip()
                    if name_part:
                        sender = name_part
                else:
                    sender = from_value
            elif line.lower().startswith("subject:"):
                subject_value = line[8:].strip()
                if subject_value:
                    subject = subject_value
        return sender, subject
    except Exception as e:
        print(f"failed to fetch message summary: {e}", file=sys.stderr)
        return "Email", "New message"


def check_mail(cfg: dict) -> None:
    host = cfg["host"]
    port = cfg["port"]
    username = cfg["username"]
    password = cfg["password"]

    if not username or not password:
        print("username or password not set in imap.conf; sleeping", file=sys.stderr)
        return

    try:
        if port == 993:
            imap = imaplib.IMAP4_SSL(host=host, port=port)
        else:
            imap = imaplib.IMAP4(host=host, port=port)
    except Exception as e:
        print(f"imap connect failed: {e}", file=sys.stderr)
        return

    try:
        try:
            imap.login(username, password)
        except imaplib.IMAP4.error as e:
            print(f"imap login failed: {e}", file=sys.stderr)
            return

        status, _ = imap.select("INBOX", readonly=True)
        if status != "OK":
            print("select inbox failed", file=sys.stderr)
            return

        status, data = imap.uid("search", "UTF-8", "(UNSEEN)")
        if status != "OK":
            print("unseen search failed", file=sys.stderr)
            return

        uids = [uid for uid in (data[0] or b"").split() if uid]
        unseen_count = len(uids)

        # Persist state in a tiny file so we survive watcher restarts.
        state_path = Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")) / "kidulwm-imap-state"
        last_digest = ""
        last_count_str = ""
        try:
            if state_path.exists():
                parts = state_path.read_text(encoding="utf-8").strip().split("\n", 1)
                last_count_str = parts[0]
                last_digest = parts[1] if len(parts) > 1 else ""
        except Exception:
            pass

        count_changed = str(unseen_count) != last_count_str
        if count_changed and unseen_count > 0:
            if unseen_count == 1:
                sender, subject = fetch_summary(imap, uids[0])
                digest = f"{sender}|{subject}"
                if digest != last_digest:
                    send_notification(sender, subject)
                    last_digest = digest
                    last_count_str = str(unseen_count)
            else:
                body = f"{unseen_count} new"
                if body != last_digest:
                    send_notification("Email", body)
                    last_digest = body
                    last_count_str = str(unseen_count)
        elif count_changed and unseen_count == 0:
            last_count_str = "0"
            last_digest = ""

        try:
            state_path.write_text(f"{last_count_str}\n{last_digest}", encoding="utf-8")
        except Exception as e:
            print(f"failed to write state: {e}", file=sys.stderr)

    finally:
        try:
            imap.close()
        except Exception:
            pass
        try:
            imap.logout()
        except Exception:
            pass


def main() -> int:
    if not CONFIG_PATH.exists():
        print(f"config missing: {CONFIG_PATH}", file=sys.stderr)
        return 1

    cfg = read_config()
    if not cfg["username"] or not cfg["password"]:
        print(f"set username and password in {CONFIG_PATH}", file=sys.stderr)
        return 1

    print("kidulwm-imap-watcher running", file=sys.stderr, flush=True)
    while True:
        check_mail(cfg)
        time.sleep(cfg["poll_seconds"])


if __name__ == "__main__":
    sys.exit(main())
