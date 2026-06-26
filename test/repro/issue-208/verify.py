#!/usr/bin/env python3
"""Issue #208 local diagnostic for --file-dialog-path."""

from __future__ import annotations

import fcntl
import functools
import http.server
import os
import pathlib
import pty
import re
import select
import signal
import socketserver
import struct
import termios
import tempfile
import threading
import time


HERE = pathlib.Path(__file__).resolve().parent
BIN = os.environ.get("CARBONYL_BIN", "carbonyl")
COLS, ROWS = 120, 40
TITLE_RE = re.compile(rb"\x1b\]0;(FD:[^\x07]*)\x07")
LEFT_DOWN_BUTTON = b"\x1b[<0;10;5M"
LEFT_UP_BUTTON = b"\x1b[<0;10;5m"


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


def timeout_seconds() -> float:
    return float(os.environ.get("ISSUE208_TIMEOUT", "20"))


def serve_fixture():
    handler = functools.partial(
        http.server.SimpleHTTPRequestHandler,
        directory=str(HERE),
    )
    httpd = ReusableTCPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    return httpd, thread, f"http://127.0.0.1:{httpd.server_address[1]}/fixture.html"


def main() -> int:
    httpd, thread, url = serve_fixture()
    profile = pathlib.Path(tempfile.mkdtemp(prefix="carbonyl-issue-208."))
    pid, fd = pty.fork()
    if pid == 0:
      fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
      env = dict(os.environ, COLUMNS=str(COLS), LINES=str(ROWS))
      fixture = HERE / "picker-fixture.txt"
      args = [
          BIN,
          f"--file-dialog-path={fixture}",
          f"--user-data-dir={profile}",
          "--no-sandbox",
          "--disable-gpu",
          url,
      ]
      os.execvpe(args[0], args, env)
      os._exit(127)

    buf = b""
    seen: list[str] = []

    def pump(seconds: float) -> None:
        nonlocal buf
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([fd], [], [], min(0.1, max(0.0, end - time.time())))
            if not ready:
                continue
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return
            if not chunk:
                return
            buf += chunk
            for match in TITLE_RE.findall(buf):
                title = match.decode(errors="replace")
                if title not in seen:
                    seen.append(title)

    def wait_for(predicate, timeout: float) -> bool:
        end = time.time() + timeout
        while time.time() < end:
            pump(0.1)
            if predicate():
                return True
        return False

    def cleanup() -> None:
        try:
            os.kill(pid, signal.SIGTERM)
            os.waitpid(pid, 0)
        except OSError:
            pass
        httpd.shutdown()
        thread.join(timeout=5)

    try:
        if not wait_for(lambda: "FD:ready" in seen, timeout_seconds()):
            print(f"SETUP-FAIL: page never reached FD:ready. Seen: {seen!r}")
            return 2

        os.write(fd, LEFT_DOWN_BUTTON)
        os.write(fd, LEFT_UP_BUTTON)
        expected = "FD:selected:picker-fixture.txt"
        if wait_for(lambda: expected in seen, timeout_seconds()):
            print("PASS: showOpenFilePicker resolved to --file-dialog-path.")
            print(f"seen: {seen!r}")
            return 0

        print(f"FAIL: picker did not resolve to fixture. Seen: {seen!r}")
        return 1
    finally:
        cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
