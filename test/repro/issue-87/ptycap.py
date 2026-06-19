#!/usr/bin/env python3
"""Run carbonyl under a PTY with a forced winsize, so the terminal sets up
(cells = winsize) and the X-mirror window = cells*(2,4) px. Keeps the PTY
open for SETTLE seconds while carbonyl renders, then exits (carbonyl killed).

argv: COLS ROWS SETTLE BIN -- <carbonyl args...>
The launcher only owns the PTY/process; the caller grabs the X framebuffer.
"""
import os, sys, pty, struct, fcntl, termios, time, signal

cols, rows, settle = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3])
sep = sys.argv.index("--")
binpath = sys.argv[4]
cargs = sys.argv[sep + 1:]

pid, fd = pty.fork()
if pid == 0:  # child
    # Set PTY winsize BEFORE exec so the first TIOCGWINSZ carbonyl does sees it.
    ws = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(0, termios.TIOCSWINSZ, ws)
    env = dict(os.environ)
    env["CARBONYL_X_MIRROR"] = "1"
    env["COLUMNS"] = str(cols)
    env["LINES"] = str(rows)
    os.execvpe(binpath, [binpath] + cargs, env)
    os._exit(127)

# parent: set winsize on the master side too, drain output, wait, then kill.
ws = struct.pack("HHHH", rows, cols, 0, 0)
try:
    fcntl.ioctl(fd, termios.TIOCSWINSZ, ws)
except OSError:
    pass
end = time.time() + settle
while time.time() < end:
    try:
        os.read(fd, 65536)  # drain so carbonyl isn't blocked on a full PTY buf
    except OSError:
        break
    time.sleep(0.05)
try:
    os.kill(pid, signal.SIGTERM)
except OSError:
    pass
os.waitpid(pid, 0)
