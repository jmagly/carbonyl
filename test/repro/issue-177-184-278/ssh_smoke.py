#!/usr/bin/env python3
"""Local SSH PTY smoke for issues #177/#184/#278.

Starts a private localhost sshd with temporary keys, runs Carbonyl as the
remote SSH command, injects an SGR left-click through the SSH client's PTY, and
observes the page via Carbonyl's OSC title output.
"""
import os
import pathlib
import pty
import re
import select
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time
import fcntl

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BIN = pathlib.Path(os.environ.get(
    "CARBONYL_BIN",
    ROOT / "build/pre-built/x86_64-unknown-linux-gnu/carbonyl",
)).resolve()
URL = (HERE / "fixture.html").as_uri()

COLS, ROWS = 120, 40
TITLE_RE = re.compile(rb"\x1b\]0;(SSHCLICK:[^\x07]*)\x07")
LEFT_DOWN = b"\x1b[<0;10;10M"
LEFT_UP = b"\x1b[<0;10;10m"


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def run_checked(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def start_sshd(tmp):
    sshd = shutil.which("sshd") or "/usr/sbin/sshd"
    ssh_keygen = shutil.which("ssh-keygen")
    if not pathlib.Path(sshd).exists():
        raise RuntimeError("sshd not found")
    if ssh_keygen is None:
        raise RuntimeError("ssh-keygen not found")

    host_key = tmp / "host_ed25519"
    client_key = tmp / "client_ed25519"
    authorized_keys = tmp / "authorized_keys"
    pid_file = tmp / "sshd.pid"
    log_file = tmp / "sshd.log"
    port = free_port()

    run_checked([ssh_keygen, "-q", "-t", "ed25519", "-N", "", "-f", str(host_key)])
    run_checked([ssh_keygen, "-q", "-t", "ed25519", "-N", "", "-f", str(client_key)])
    authorized_keys.write_text((client_key.with_suffix(".pub")).read_text())
    authorized_keys.chmod(0o600)

    config = tmp / "sshd_config"
    config.write_text(
        "\n".join([
            f"HostKey {host_key}",
            f"AuthorizedKeysFile {authorized_keys}",
            f"PidFile {pid_file}",
            f"Port {port}",
            "ListenAddress 127.0.0.1",
            "PasswordAuthentication no",
            "PubkeyAuthentication yes",
            "ChallengeResponseAuthentication no",
            "UsePAM no",
            "PermitTTY yes",
            f"AllowUsers {os.environ.get('USER', '')}",
            "LogLevel VERBOSE",
            "StrictModes no",
            "",
        ])
    )

    run_checked([sshd, "-f", str(config), "-E", str(log_file)])
    deadline = time.time() + 5
    while time.time() < deadline:
        if pid_file.exists():
            return port, client_key, pid_file, log_file
        time.sleep(0.05)
    raise RuntimeError(f"sshd did not create pid file; log:\n{log_file.read_text(errors='replace')}")


def main():
    if not BIN.exists() or not os.access(BIN, os.X_OK):
        print(f"SETUP-FAIL: CARBONYL_BIN not executable: {BIN}")
        return 2
    if shutil.which("ssh") is None:
        print("SETUP-FAIL: ssh client not found")
        return 2

    with tempfile.TemporaryDirectory(prefix="carbonyl-ssh-smoke-") as tmp_name:
        tmp = pathlib.Path(tmp_name)
        port, client_key, pid_file, log_file = start_sshd(tmp)
        pid = None
        fd = None
        buf = b""
        seen = []

        def cleanup():
            if pid:
                try:
                    os.kill(pid, signal.SIGTERM)
                    os.waitpid(pid, 0)
                except OSError:
                    pass
            if pid_file.exists():
                try:
                    os.kill(int(pid_file.read_text()), signal.SIGTERM)
                except OSError:
                    pass

        def pump(seconds):
            nonlocal buf
            end = time.time() + seconds
            while time.time() < end:
                r, _, _ = select.select([fd], [], [], min(0.1, max(0.0, end - time.time())))
                if not r:
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
                    if not seen or seen[-1] != title:
                        seen.append(title)

        def wait_for(title, timeout):
            end = time.time() + timeout
            while time.time() < end:
                pump(0.1)
                if title in seen:
                    return True
            return False

        try:
            remote_cmd = (
                f"env COLUMNS={COLS} LINES={ROWS} "
                f"{str(BIN)!r} --no-sandbox --disable-gpu {URL!r}"
            )
            pid, fd = pty.fork()
            if pid == 0:
                fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
                os.execvp("ssh", [
                    "ssh",
                    "-tt",
                    "-i", str(client_key),
                    "-o", "BatchMode=yes",
                    "-o", "IdentitiesOnly=yes",
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "UserKnownHostsFile=/dev/null",
                    "-p", str(port),
                    "127.0.0.1",
                    remote_cmd,
                ])
                os._exit(127)

            if not wait_for("SSHCLICK:ready", 20):
                print(f"SETUP-FAIL: remote Carbonyl never reached SSHCLICK:ready (seen: {seen!r}).")
                print(log_file.read_text(errors="replace"))
                return 2

            pump(2.5)
            for _ in range(2):
                os.write(fd, LEFT_DOWN)
                os.write(fd, LEFT_UP)
                if wait_for("SSHCLICK:clicked", 4):
                    print("PASS: SSH PTY delivered SGR left-click to remote Carbonyl.")
                    return 0

            print(f"FAIL: SSH PTY click did not reach page (seen: {seen!r}).")
            return 1
        finally:
            cleanup()


if __name__ == "__main__":
    sys.exit(main())
