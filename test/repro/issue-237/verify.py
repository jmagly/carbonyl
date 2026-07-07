#!/usr/bin/env python3
"""issue #237 — verify Shift+Tab reverses form focus.

Companion to issue-169 (forward TAB focus). Here we confirm the *modifier* now
survives the input FFI: Carbonyl forwards key.modifiers.mask() to the C++ side,
which translates it to blink::WebInputEvent::kShiftKey, so Blink's
DefaultTabEventHandler runs reverse focus traversal on Shift+Tab.

Shift+Tab arrives from the terminal as the back-tab CSI Z sequence
(ESC [ Z = b"\\x1b[Z", terminfo `kcbt`); the parser decodes it to Tab (0x09)
with the shift modifier (#237).

Like issue-169, focus is observed GPU-independently: fixture.html reflects the
focused field id into document.title, which Carbonyl emits as an OSC sequence
(renderer.rs set_title -> "\\x1b]0;{title}\\x07").

Protocol:
  1. page load + autofocus -> CFOCUS:f0
  2. TAB (0x09)         -> CFOCUS:f1   (forward traversal — sanity)
  3. TAB (0x09)         -> CFOCUS:f2
  4. Shift+Tab (CSI Z)  -> CFOCUS:f1   (REVERSE traversal — the #237 fix)
  5. Shift+Tab (CSI Z)  -> CFOCUS:f0   (reverse is repeatable, not a one-off)

Exit 0 = Shift+Tab reversed focus (fix works).
Exit 1 = forward worked but Shift+Tab did not reverse (modifier dropped /
         CSI Z not decoded — fix absent or regressed).
Exit 2 = harness/setup error (page never loaded, or forward TAB itself broken).

Usage: CARBONYL_BIN=/path/to/carbonyl python3 verify.py [fixture_url]
"""
import os, sys, pty, time, re, struct, fcntl, termios, signal, pathlib

HERE = pathlib.Path(__file__).resolve().parent
BIN = os.environ.get("CARBONYL_BIN", "carbonyl")
URL = sys.argv[1] if len(sys.argv) > 1 else (HERE / "fixture.html").as_uri()

COLS, ROWS = 120, 40
TITLE_RE = re.compile(rb"\x1b\]0;CFOCUS:(\w+)\x07")

TAB = b"\t"            # 0x09
SHIFT_TAB = b"\x1b[Z"  # CSI Z (back-tab)


def latest_focus(buf):
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

        # Settle: let the frame fully take focus before sending keys (mirrors
        # the issue-169 flakiness note about TAB landing too early).
        drain(2.5)

        # 2. TAB -> #f1  (forward sanity)
        os.write(fd, TAB)
        if not wait_for_focus("f1", timeout=6):
            print("SETUP-FAIL: forward TAB did not advance #f0 -> #f1. "
                  "Forward focus (issue #169) is broken in this runtime; "
                  "cannot evaluate Shift+Tab reverse focus.")
            cleanup()
            return 2

        # 3. TAB -> #f2  (so we have room to reverse twice)
        os.write(fd, TAB)
        if not wait_for_focus("f2", timeout=6):
            print("SETUP-FAIL: forward TAB did not advance #f1 -> #f2.")
            cleanup()
            return 2

        # 4. Shift+Tab -> #f1  (THE #237 fix: reverse traversal)
        os.write(fd, SHIFT_TAB)
        if not wait_for_focus("f1", timeout=6):
            print("FAIL: Shift+Tab (CSI Z) did not reverse focus #f2 -> #f1 "
                  "(modifier dropped at the FFI or CSI Z not decoded — "
                  "issue #237 fix absent or regressed).")
            cleanup()
            return 1

        # 5. Shift+Tab -> #f0  (reverse is repeatable)
        os.write(fd, SHIFT_TAB)
        if not wait_for_focus("f0", timeout=6):
            print("FAIL: Shift+Tab reversed #f2 -> #f1 but not #f1 -> #f0 "
                  "(partial reverse traversal).")
            cleanup()
            return 1

        print("PASS: Shift+Tab reversed focus #f2 -> #f1 -> #f0 (issue #237 fixed).")
        cleanup()
        return 0
    finally:
        cleanup()


if __name__ == "__main__":
    sys.exit(main())
