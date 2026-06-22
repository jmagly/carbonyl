#!/usr/bin/env python3
"""issue #178 / #217 — verify multi-byte UTF-8 (non-ASCII) input.

Drives Carbonyl in a PTY against fixture.html, types a Cyrillic then a CJK
character as raw UTF-8 bytes (as a terminal/IME would deliver them), and checks
the focused input's value — reflected into document.title and emitted as a
UTF-8 OSC sequence — contains the intended characters.

With the fix (UTF-8 accumulation + codepoint key FFI), 'д' (0xD0 0xB4) and '中'
(0xE4 0xB8 0xAD) each arrive as one keypress and land in the input. Without it,
each byte was a separate single-byte keypress and the input got garbage.

Exit 0 = PASS (input value == 'д' then 'д中').
Exit 1 = FAIL (value wrong; observed titles printed).
Exit 2 = SETUP-FAIL (page never reached READY).
"""
import os, sys, pty, time, re, struct, fcntl, termios, signal, select, pathlib

HERE = pathlib.Path(__file__).resolve().parent
BIN = os.environ.get("CARBONYL_BIN", "carbonyl")
URL = sys.argv[1] if len(sys.argv) > 1 else (HERE / "fixture.html").as_uri()
COLS, ROWS = 120, 40
TITLE_RE = re.compile(rb"\x1b\]0;([^\x07]*)\x07")

STEPS = [("д".encode("utf-8"), "VAL:д"),          # Cyrillic д (#178)
         ("中".encode("utf-8"), "VAL:д中")]    # CJK 中 (#217)


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
            except BlockingIOError:
                continue
            except OSError:
                return
            if not chunk:
                return
            buf += chunk
            for m in TITLE_RE.findall(buf):
                d = m.decode("utf-8", errors="replace")
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
        if not wait("READY", 20):
            print(f"SETUP-FAIL: page never reached READY (seen: {seen!r}).")
            cleanup()
            return 2
        pump(2.5)  # settle so the frame is focused before typing

        for utf8_bytes, expected in STEPS:
            ok = False
            for _ in range(2):  # retry once in case the first lands too early
                os.write(fd, utf8_bytes)
                if wait(expected, 5):
                    ok = True
                    break
            if not ok:
                print(f"FAIL: input did not become {expected!r}. Observed (tail): {seen[-12:]!r}")
                cleanup()
                return 1

        print("PASS: Cyrillic and CJK input landed intact (issue #178/#217 fixed).")
        cleanup()
        return 0
    finally:
        cleanup()


if __name__ == "__main__":
    sys.exit(main())
