#!/usr/bin/env python3
"""Issue #213 local diagnostic for embedded PDF rendering."""

from __future__ import annotations

import contextlib
import functools
import http.server
import os
import pathlib
import pty
import re
import select
import shutil
import signal
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import fcntl
import struct
import termios
from dataclasses import dataclass


HERE = pathlib.Path(__file__).resolve().parent
PDF_TEXT = "Carbonyl PDF fixture text"
HTML_TEXT = "Carbonyl PDF wrapper ready"
ANSI_RE = re.compile(rb"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\)|[@-Z\\-_])")


@dataclass
class CommandResult:
    code: int
    stdout: str
    stderr_tail: str


@dataclass
class CheckResult:
    url: str
    innertext: CommandResult
    raw_dom: CommandResult
    terminal_text: str
    terminal_bytes: int


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


def carbonyl_bin() -> str:
    return os.environ.get("CARBONYL_BIN", "carbonyl")


def timeout_seconds() -> int:
    return int(os.environ.get("ISSUE213_TIMEOUT", "30"))


def dump_max_wait_ms() -> int:
    return int(os.environ.get("ISSUE213_DUMP_MAX_WAIT_MS", "5000"))


def idle_ms() -> str:
    return os.environ.get("ISSUE213_IDLE_MS", "3000")


def capture_seconds() -> float:
    return float(os.environ.get("ISSUE213_CAPTURE_SECONDS", "8"))


@contextlib.contextmanager
def serve_fixture():
    handler = functools.partial(
        http.server.SimpleHTTPRequestHandler,
        directory=str(HERE),
    )
    with ReusableTCPServer(("127.0.0.1", 0), handler) as httpd:
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        try:
            yield f"http://127.0.0.1:{httpd.server_address[1]}"
        finally:
            httpd.shutdown()
            thread.join(timeout=5)


def run_dump(url: str, mode: str, profile: pathlib.Path) -> CommandResult:
    args = [
        carbonyl_bin(),
        f"--dump-text{mode}",
        f"--idle={idle_ms()}",
        f"--max-wait={dump_max_wait_ms()}",
        f"--user-data-dir={profile}",
        "--no-sandbox",
        "--disable-gpu",
        url,
    ]
    try:
        proc = subprocess.run(
            args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout_seconds(),
            check=False,
        )
        stderr_tail = proc.stderr.decode(errors="replace").splitlines()[-8:]
        return CommandResult(
            proc.returncode,
            proc.stdout.decode(errors="replace"),
            "\n".join(stderr_tail),
        )
    except subprocess.TimeoutExpired as exc:
        stderr_tail = (exc.stderr or b"").decode(errors="replace").splitlines()[-8:]
        return CommandResult(
            124,
            (exc.stdout or b"").decode(errors="replace"),
            "\n".join(stderr_tail),
        )


def strip_terminal(data: bytes) -> str:
    clean = ANSI_RE.sub(b"", data)
    clean = clean.replace(b"\r", b"\n")
    return clean.decode(errors="replace")


def run_terminal(url: str, profile: pathlib.Path) -> tuple[str, int]:
    pid, fd = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        env = dict(os.environ, COLUMNS="120", LINES="40")
        args = [
            carbonyl_bin(),
            f"--user-data-dir={profile}",
            "--no-sandbox",
            "--disable-gpu",
            url,
        ]
        os.execvpe(args[0], args, env)
        os._exit(127)

    buf = b""
    deadline = time.time() + capture_seconds()
    try:
        while time.time() < deadline:
            wait = min(0.25, max(0.0, deadline - time.time()))
            ready, _, _ = select.select([fd], [], [], wait)
            if not ready:
                continue
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if chunk:
                buf += chunk
    finally:
        try:
            os.kill(pid, signal.SIGTERM)
            os.waitpid(pid, 0)
        except OSError:
            pass

    return strip_terminal(buf), len(buf)


def run_checks(url: str, work: pathlib.Path) -> CheckResult:
    inner = run_dump(url, "", work / "innertext")
    raw = run_dump(url, "=raw-dom", work / "raw-dom")
    terminal_text, terminal_bytes = run_terminal(url, work / "terminal")
    return CheckResult(url, inner, raw, terminal_text, terminal_bytes)


def contains_pdf_text(result: CheckResult) -> bool:
    return any(
        PDF_TEXT in value
        for value in (result.innertext.stdout, result.raw_dom.stdout, result.terminal_text)
    )


def print_result(name: str, result: CheckResult) -> None:
    print(name)
    print(f"  url:       {result.url}")
    print(f"  innertext: code={result.innertext.code} bytes={len(result.innertext.stdout)}")
    print(f"  raw-dom:   code={result.raw_dom.code} bytes={len(result.raw_dom.stdout)}")
    print(f"  terminal:  bytes={result.terminal_bytes} chars={len(result.terminal_text)}")
    print(f"  pdf text:  {'yes' if contains_pdf_text(result) else 'no'}")
    print()


def main() -> int:
    work = pathlib.Path(tempfile.mkdtemp(prefix="carbonyl-issue-213."))
    try:
        with serve_fixture() as base_url:
            wrapper = run_checks(f"{base_url}/fixture.html", work / "wrapper")
            direct = run_checks(f"{base_url}/sample.pdf", work / "direct-pdf")

        print("issue #213 PDF rendering diagnostic")
        print(f"runtime: {carbonyl_bin()}")
        print_result("wrapper page with embedded PDF", wrapper)
        print_result("direct PDF navigation", direct)

        html_loaded = any(
            HTML_TEXT in value
            for value in (
                wrapper.innertext.stdout,
                wrapper.raw_dom.stdout,
                wrapper.terminal_text,
            )
        )
        if not html_loaded:
            print("SETUP-FAIL: wrapper HTML marker was not observed.")
            if wrapper.innertext.stderr_tail:
                print("innertext stderr tail:")
                print(wrapper.innertext.stderr_tail)
            return 2

        if contains_pdf_text(wrapper):
            print("PASS: embedded PDF fixture text is visible through Carbonyl output.")
            return 0

        if contains_pdf_text(direct):
            print("FAIL: direct PDF text is visible, but embedded PDF text is not.")
            return 1

        print("FAIL: wrapper HTML loaded, but PDF fixture text is not visible.")
        return 1
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
