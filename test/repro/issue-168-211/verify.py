#!/usr/bin/env python3
"""issues #168/#211 - classify dropdown click behavior.

Drives Carbonyl in a PTY against fixture.html and observes page state through
OSC title updates, matching the existing issue-169/199 repro pattern.

Protocol:
  1. Wait for DD:ready.
  2. Click a large button target. If DD:button:click is not observed, ordinary
     click mapping is broken and the dropdown result would be ambiguous.
  3. Click a large native <select> target. DD:select:focus or DD:select:md proves
     the terminal click reached the select element.
  4. Send ArrowDown + Enter. DD:select:change:beta proves the focused select can
     be changed without relying on a visible popup surface.

Exit 0 = PASS (button click, select focus/mousedown, and select change observed).
Exit 1 = FAIL (behavior classified; see printed reason).
Exit 2 = SETUP-FAIL (fixture did not load).

Usage: CARBONYL_BIN=/path/to/carbonyl python3 verify.py [fixture_url]
"""
import fcntl
import os
import pathlib
import pty
import re
import select
import signal
import struct
import sys
import termios
import time

HERE = pathlib.Path(__file__).resolve().parent
BIN = os.environ.get("CARBONYL_BIN", "carbonyl")
URL = sys.argv[1] if len(sys.argv) > 1 else (HERE / "fixture.html").as_uri()

COLS, ROWS = 120, 40
TITLE_RE = re.compile(rb"\x1b\]0;(DD:[^\x07]*)\x07")

LEFT_DOWN_BUTTON = b"\x1b[<0;10;5M"
LEFT_UP_BUTTON = b"\x1b[<0;10;5m"
LEFT_DOWN_SELECT = b"\x1b[<0;10;20M"
LEFT_UP_SELECT = b"\x1b[<0;10;20m"
ARROWDOWN = b"\x1b[B"
ENTER = b"\r"


def main():
    pid, fd = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        env = dict(os.environ, COLUMNS=str(COLS), LINES=str(ROWS))
        os.execvpe(BIN, [BIN, "--no-sandbox", "--disable-gpu", URL], env)
        os._exit(127)

    buf = b""
    seen = []

    def pump(seconds):
        nonlocal buf
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], min(0.1, max(0.0, end - time.time())))
            if not r:
                continue
            try:
                chunk = os.read(fd, 65536)
            except (BlockingIOError, OSError):
                return
            if not chunk:
                return
            buf += chunk
            for match in TITLE_RE.findall(buf):
                title = match.decode(errors="replace")
                if title not in seen:
                    seen.append(title)

    def wait_for(predicate, timeout):
        end = time.time() + timeout
        while time.time() < end:
            pump(0.1)
            if predicate():
                return True
        return False

    def click(down, up):
        os.write(fd, down)
        os.write(fd, up)

    def cleanup():
        try:
            os.kill(pid, signal.SIGTERM)
            os.waitpid(pid, 0)
        except OSError:
            pass

    try:
        if not wait_for(lambda: "DD:ready" in seen, 20):
            print(f"SETUP-FAIL: page never reached DD:ready (seen: {seen!r}).")
            cleanup()
            return 2

        pump(2.5)

        click(LEFT_DOWN_BUTTON, LEFT_UP_BUTTON)
        if not wait_for(lambda: "DD:button:click" in seen, 6):
            print("FAIL: ordinary button click did not reach Blink; likely click "
                  f"coordinate/mouse mapping, not select-popup specific. Seen: {seen!r}")
            cleanup()
            return 1

        click(LEFT_DOWN_SELECT, LEFT_UP_SELECT)
        select_reached = wait_for(
            lambda: "DD:select:md" in seen or "DD:select:focus" in seen,
            6,
        )
        if not select_reached:
            print("FAIL: button click worked, but click did not reach/focus the "
                  f"native select target. Seen: {seen!r}")
            cleanup()
            return 1

        pump(0.5)
        os.write(fd, ARROWDOWN)
        pump(0.2)
        os.write(fd, ENTER)
        if not wait_for(lambda: "DD:select:change:beta" in seen, 6):
            print("FAIL: native select was reached, but ArrowDown+Enter did not "
                  "change it to beta; likely popup/select keyboard handling. "
                  f"Seen: {seen!r}")
            cleanup()
            return 1

        print("PASS: button click and native select change both work "
              "(issues #168/#211 not reproduced by this fixture).")
        cleanup()
        return 0
    finally:
        cleanup()


if __name__ == "__main__":
    sys.exit(main())
