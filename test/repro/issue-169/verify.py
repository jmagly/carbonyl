#!/usr/bin/env python3
"""issue #169 — verify TAB advances form focus.

Drives Carbonyl in a PTY against fixture.html, whose focusin handler reflects
the focused field id into document.title. Carbonyl emits the title as an OSC
sequence on stdout (renderer.rs set_title -> "\\x1b]0;{title}\\x07"), so we can
observe focus changes from the terminal byte stream WITHOUT rendering pixels —
this works on a GL-less headless host.

Protocol:
  1. Wait for the page to load and autofocus #f0 (title -> CFOCUS:f0).
  2. Send TAB (0x09). With the fix (patch 0009: 0x09 -> VKEY_TAB) focus advances
     to #f1 (title -> CFOCUS:f1). Without it, TAB was inserted as a literal tab
     and the title stayed CFOCUS:f0.
  3. Send TAB again -> CFOCUS:f2.

Exit 0 = focus advanced on TAB (fix works). Exit 1 = focus did not advance
(regression / fix absent). Exit 2 = harness/setup error (page never loaded).

Usage: CARBONYL_BIN=/path/to/carbonyl python3 verify.py [fixture_url]
"""
import os, sys, pty, time, re, struct, fcntl, termios, signal, pathlib

HERE = pathlib.Path(__file__).resolve().parent
BIN = os.environ.get("CARBONYL_BIN", "carbonyl")
URL = sys.argv[1] if len(sys.argv) > 1 else (HERE / "fixture.html").as_uri()

COLS, ROWS = 120, 40
TITLE_RE = re.compile(rb"\x1b\]0;CFOCUS:(\w+)\x07")


def latest_focus(buf):
    """Return the id from the most recent CFOCUS title in the buffer, or None."""
    matches = TITLE_RE.findall(buf)
    return matches[-1].decode() if matches else None


def main():
    pid, fd = pty.fork()
    if pid == 0:  # child: become carbonyl in terminal mode
        ws = struct.pack("HHHH", ROWS, COLS, 0, 0)
        fcntl.ioctl(0, termios.TIOCSWINSZ, ws)
        env = dict(os.environ, COLUMNS=str(COLS), LINES=str(ROWS), CARBONYL_TAB_FOCUS="1")
        args = [BIN, "--no-sandbox", "--disable-gpu", URL]
        os.execvpe(BIN, args, env)
        os._exit(127)

    buf = b""

    def drain(seconds):
        nonlocal buf
        end = time.time() + seconds
        while time.time() < end:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if chunk:
                buf += chunk
            else:
                time.sleep(0.02)

    def wait_for_focus(target, timeout):
        nonlocal buf
        end = time.time() + timeout
        while time.time() < end:
            try:
                chunk = os.read(fd, 65536)
                if chunk:
                    buf += chunk
            except OSError:
                break
            if latest_focus(buf) == target:
                return True
            time.sleep(0.05)
        return False

    def cleanup():
        try:
            os.kill(pid, signal.SIGTERM)
            os.waitpid(pid, 0)
        except OSError:
            pass

    try:
        # 1. page load + autofocus -> #f0
        if not wait_for_focus("f0", timeout=20):
            cur = latest_focus(buf)
            print(f"SETUP-FAIL: page never reached CFOCUS:f0 (last focus: {cur!r}). "
                  f"Is CARBONYL_BIN a working runtime that renders this page?")
            cleanup()
            return 2

        # Settle: CFOCUS:f0 can fire from autofocus before the frame has fully
        # taken focus and the renderer is ready to process a key event. Sending
        # TAB too early drops the first focus traversal (observed flakiness).
        # Drain briefly so the frame is focused before we send TAB.
        drain(2.5)

        # 2. TAB -> #f1
        os.write(fd, b"\t")
        if not wait_for_focus("f1", timeout=6):
            print("FAIL: TAB did not advance focus from #f0 -> #f1 "
                  "(fix absent or regressed; TAB likely inserted as text).")
            cleanup()
            return 1

        # 3. TAB -> #f2 (confirms repeatable traversal, not a one-off)
        os.write(fd, b"\t")
        if not wait_for_focus("f2", timeout=6):
            print("FAIL: TAB advanced #f0 -> #f1 but not #f1 -> #f2 "
                  "(partial focus traversal).")
            cleanup()
            return 1

        print("PASS: TAB advanced focus #f0 -> #f1 -> #f2 (issue #169 fixed).")
        cleanup()
        return 0
    finally:
        cleanup()


if __name__ == "__main__":
    sys.exit(main())
