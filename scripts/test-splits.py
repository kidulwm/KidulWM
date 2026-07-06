#!/usr/bin/env python3
"""test-splits.py — exercise KidulWM IPC split and ping commands.

Run after `zig build run` (or the no-backend dev binary) is listening on
$XDG_RUNTIME_DIR/kidulwm-control.sock.
"""
import json
import os
import socket
import sys

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000"), "kidulwm-control.sock")


def send(req: dict) -> dict:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(2)
        s.connect(SOCK)
        s.sendall((json.dumps(req) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        return json.loads(data.decode())


def main() -> int:
    print(f"socket: {SOCK}")
    for cmd in ["ping", "split_left", "split_right", "split_top", "split_bottom", "get_layout"]:
        try:
            resp = send({cmd: {}})
            print(f"{cmd:12} -> {resp}")
        except Exception as e:
            print(f"{cmd:12} -> ERROR: {e}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
