#!/usr/bin/env python3
"""issue #199 — verify right-click forwards the right mouse button.

Drives Carbonyl in a PTY against fixture.html, injects an SGR right-button
press+release, and observes the page's reaction via the OSC title sequence
(GPU-independent; same technique as test/repro/issue-169).

The fixture reflects mouse events into document.title:
  - mousedown   -> RC:md:<button>     (button: 0=left, 1=middle, 2=right)
  - contextmenu -> RC:ctx:<button>

With the fix (patch 0009 mouse-button FFI), a right-button SGR arrives as
button==2: mousedown fires RC:md:2 and a contextmenu fires RC:ctx:2. Without it
(button hardcoded to kLeft), the right-click is delivered as a left click
(RC:md:0) and no contextmenu fires.

Exit 0 = PASS (RC:ctx:2 seen — right-click works).
Exit 1 = FAIL (no contextmenu with button 2; observed titles printed).
Exit 2 = SETUP-FAIL (page never reached RC:ready).

Usage: CARBONYL_BIN=/path/to/carbonyl python3 verify.py
"""
import os, sys, pty, time, re, struct, fcntl, termios, signal, select, pathlib

HERE = pathlib.Path(__file__).resolve().parent
BIN = os.environ.get("CARBONYL_BIN", "carbonyl")
URL = sys.argv[1] if len(sys.argv) > 1 else (HERE / "fixture.html").as_uri()

COLS, ROWS = 120, 40
TITLE_RE = re.compile(rb"\x1b\]0;(RC:[^\x07]*)\x07")
# SGR mouse, button 2 (right), at cell (10,10): press 'M', release 'm'.
RIGHT_DOWN = b"\x1b[<2;10;10M"
RIGHT_UP = b"\x1b[<2;10;10m"


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
        # Non-blocking drain via select: a static page emits no output, so a
        # plain blocking os.read would hang past the time budget.
        nonlocal buf
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], min(0.1, max(0.0, end - time.time())))
            if not r:
                continue
            try:
                chunk = os.read(fd, 65536)
            except BlockingIOError:
                continue
            except OSError:
                return
            if not chunk:
                return  # EOF (child exited)
            buf += chunk
            for m in TITLE_RE.findall(buf):
                d = m.decode(errors="replace")
                if not seen or seen[-1] != d:
                    seen.append(d)

    def wait(title, timeout):
        end = time.time() + timeout
        while time.time() < end:
            pump(0.1)
            if title in seen:
                return True
        return False

    def cleanup():
        try:
            os.kill(pid, signal.SIGTERM)
            os.waitpid(pid, 0)
        except OSError:
            pass

    try:
        if not wait("RC:ready", 20):
            print(f"SETUP-FAIL: page never reached RC:ready (seen: {seen!r}).")
            cleanup()
            return 2

        # Settle so the frame is focused/ready before injecting input.
        pump(2.5)

        # Right-click (retry once in case the first lands before readiness).
        for _ in range(2):
            os.write(fd, RIGHT_DOWN)
            os.write(fd, RIGHT_UP)
            if wait("RC:ctx:2", 4):
                print("PASS: right-click delivered button 2 and fired contextmenu "
                      "(issue #199 fixed).")
                cleanup()
                return 0

        md = [s for s in seen if s.startswith("RC:md:")]
        if "RC:md:2" in seen:
            print(f"FAIL: right button reached Blink (RC:md:2) but no contextmenu "
                  f"fired. Observed: {seen!r}")
        else:
            print(f"FAIL: right-click not delivered as button 2 "
                  f"(mousedowns: {md!r}; observed: {seen!r}).")
        cleanup()
        return 1
    finally:
        cleanup()


if __name__ == "__main__":
    sys.exit(main())
