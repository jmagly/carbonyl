#!/usr/bin/env python3
"""Issue #160 live diagnostic for Amazon regional text rendering.

This is not a deterministic CI test: Amazon may geo-route, bot-wall, or change
markup. It isolates each run in a fresh Chromium profile and reports enough
signals to classify whether text is missing from the DOM or only from the
terminal renderer.
"""

from __future__ import annotations

import os
import pathlib
import pty
import re
import shutil
import signal
import select
import shlex
import subprocess
import sys
import tempfile
import time
import fcntl
import struct
import termios
import urllib.error
import urllib.request
from dataclasses import dataclass


DEFAULT_URLS = [
    "https://www.amazon.com/dp/B09TTDRXNS",
    "https://www.amazon.fr/dp/B0B14J2RJ3",
]

ANSI_RE = re.compile(rb"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\)|[@-Z\\-_])")
PRINTABLE_RE = re.compile(r"[A-Za-z0-9À-ÿ]")


@dataclass
class CommandResult:
    code: int
    stdout_bytes: int
    stdout_sample: str
    stderr_tail: str


@dataclass
class HttpProbe:
    status: int | None
    final_url: str
    content_type: str
    body_bytes: int
    signals: str
    error: str


@dataclass
class UrlResult:
    url: str
    http_probe: HttpProbe
    innertext: CommandResult
    raw_dom: CommandResult
    terminal_printable: int
    terminal_bytes: int
    terminal_sample: str


def carbonyl_bin() -> str:
    return os.environ.get("CARBONYL_BIN", "carbonyl")


def urls() -> list[str]:
    raw = os.environ.get("ISSUE160_URLS")
    return raw.split() if raw else DEFAULT_URLS


def timeout_seconds() -> int:
    return int(os.environ.get("ISSUE160_TIMEOUT", "45"))


def idle_ms() -> str:
    return os.environ.get("ISSUE160_IDLE_MS", "5000")


def capture_seconds() -> float:
    return float(os.environ.get("ISSUE160_CAPTURE_SECONDS", "12"))


def extra_args() -> list[str]:
    return shlex.split(os.environ.get("ISSUE160_CHROMIUM_ARGS", ""))


def keep_artifacts() -> bool:
    return os.environ.get("ISSUE160_KEEP_ARTIFACTS", "").lower() in {"1", "true", "yes"}


def text_sample(data: bytes, limit: int = 240) -> str:
    text = data.decode(errors="replace")
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > limit:
        return text[: limit - 1] + "…"
    return text


def signal_summary(text: str) -> str:
    lowered = text.lower()
    signals = []
    for needle, label in (
        ("robot check", "robot-check"),
        ("captcha", "captcha"),
        ("automated access", "automated-access"),
        ("not a robot", "not-a-robot"),
        ("continue shopping", "continue-shopping"),
        ("continuer vos achats", "continue-shopping"),
        ("continuer les achats", "continue-shopping"),
        ("cliquez sur le bouton", "continue-shopping"),
        ("sorry", "sorry-page"),
        ("service unavailable", "service-unavailable"),
        ("certificate", "certificate"),
        ("timed out", "timeout"),
    ):
        if needle in lowered:
            signals.append(label)
    return ",".join(dict.fromkeys(signals)) or "none"


def http_probe(url: str) -> HttpProbe:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/147.0 Safari/537.36"
            ),
            "Accept-Language": "en-US,en;q=0.9,fr;q=0.8",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds()) as response:
            body = response.read(8192)
            content_type = response.headers.get("content-type", "")
            return HttpProbe(
                response.status,
                response.geturl(),
                content_type,
                len(body),
                signal_summary(text_sample(body, 4000)),
                "",
            )
    except urllib.error.HTTPError as exc:
        body = exc.read(8192)
        return HttpProbe(
            exc.code,
            exc.geturl(),
            exc.headers.get("content-type", ""),
            len(body),
            signal_summary(text_sample(body, 4000)),
            "",
        )
    except Exception as exc:  # noqa: BLE001 - diagnostics should report, not crash.
        return HttpProbe(None, url, "", 0, "probe-error", f"{type(exc).__name__}: {exc}")


def run_dump(url: str, mode: str, profile: pathlib.Path) -> CommandResult:
    args = [
        carbonyl_bin(),
        f"--dump-text{mode}",
        f"--idle={idle_ms()}",
        f"--max-wait={timeout_seconds() * 1000}",
        f"--user-data-dir={profile}",
        "--no-sandbox",
        "--disable-gpu",
        *extra_args(),
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
            len(proc.stdout),
            text_sample(proc.stdout),
            "\n".join(stderr_tail),
        )
    except subprocess.TimeoutExpired as exc:
        stderr = (exc.stderr or b"").decode(errors="replace").splitlines()[-8:]
        stdout = exc.stdout or b""
        return CommandResult(124, len(stdout), text_sample(stdout), "\n".join(stderr))


def strip_terminal(data: bytes) -> str:
    clean = ANSI_RE.sub(b"", data)
    clean = clean.replace(b"\r", b"\n")
    return clean.decode(errors="replace")


def run_terminal(url: str, profile: pathlib.Path) -> tuple[int, int, str]:
    pid, fd = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        env = dict(os.environ, COLUMNS="120", LINES="40")
        args = [
            carbonyl_bin(),
            f"--user-data-dir={profile}",
            "--no-sandbox",
            "--disable-gpu",
            *extra_args(),
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
            else:
                time.sleep(0.05)
    finally:
        try:
            os.kill(pid, signal.SIGTERM)
            os.waitpid(pid, 0)
        except OSError:
            pass

    clean = strip_terminal(buf)
    printable = len(PRINTABLE_RE.findall(clean))
    return printable, len(buf), text_sample(clean.encode(), 240)


def classify(result: UrlResult) -> str:
    dom_text = result.innertext.stdout_bytes > 200 or result.raw_dom.stdout_bytes > 2000
    terminal_text = result.terminal_printable > 200
    content_signals = signal_summary(
        " ".join(
            (
                result.innertext.stdout_sample,
                result.raw_dom.stdout_sample,
                result.terminal_sample,
            )
        )
    )
    gate_signals = ",".join(
        dict.fromkeys(
            signal
            for signals in (result.http_probe.signals, content_signals)
            if signals != "none"
            for signal in signals.split(",")
        )
    )
    if result.http_probe.status in {403, 429, 503} or gate_signals:
        return f"live-site gate ({gate_signals or 'http-status'})"
    if not dom_text:
        return "DOM/content unavailable"
    if dom_text and not terminal_text:
        return "terminal paint/text missing"
    return "text visible"


def main() -> int:
    work = pathlib.Path(tempfile.mkdtemp(prefix="carbonyl-issue-160."))
    results: list[UrlResult] = []
    try:
        for index, url in enumerate(urls(), start=1):
            profile_base = work / f"profile-{index}"
            probe = http_probe(url)
            inner = run_dump(url, "", profile_base / "innertext")
            raw = run_dump(url, "=raw-dom", profile_base / "raw-dom")
            printable, terminal_bytes, terminal_sample = run_terminal(
                url, profile_base / "terminal"
            )
            results.append(
                UrlResult(
                    url,
                    probe,
                    inner,
                    raw,
                    printable,
                    terminal_bytes,
                    terminal_sample,
                )
            )

        print("issue #160 live diagnostic")
        print(f"runtime: {carbonyl_bin()}")
        print()
        for result in results:
            print(result.url)
            print(
                "  http:      "
                f"status={result.http_probe.status} bytes={result.http_probe.body_bytes} "
                f"type={result.http_probe.content_type or '-'} "
                f"signals={result.http_probe.signals}"
            )
            if result.http_probe.error:
                print(f"  http err:  {result.http_probe.error}")
            if result.http_probe.final_url != result.url:
                print(f"  final url: {result.http_probe.final_url}")
            print(f"  innertext: code={result.innertext.code} bytes={result.innertext.stdout_bytes}")
            print(f"  raw-dom:   code={result.raw_dom.code} bytes={result.raw_dom.stdout_bytes}")
            print(
                "  terminal:  "
                f"bytes={result.terminal_bytes} printable={result.terminal_printable}"
            )
            print(f"  classify:  {classify(result)}")
            if result.innertext.stdout_sample:
                print(f"  innertext sample: {result.innertext.stdout_sample}")
            if result.raw_dom.stdout_sample:
                print(f"  raw-dom sample:   {result.raw_dom.stdout_sample}")
            if result.terminal_sample:
                print(f"  terminal sample:  {result.terminal_sample}")
            if result.innertext.code != 0 and result.innertext.stderr_tail:
                print("  innertext stderr tail:")
                for line in result.innertext.stderr_tail.splitlines():
                    print(f"    {line}")
            print()
        return 0
    finally:
        if keep_artifacts():
            print(f"artifacts retained: {work}")
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
