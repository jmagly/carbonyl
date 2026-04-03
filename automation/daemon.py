#!/usr/bin/env python3
"""
Carbonyl persistent browser daemon.

Keeps a Carbonyl browser running in the background and exposes it over a
Unix domain socket. Callers reconnect without losing cookies, localStorage,
or in-memory session state.

Commands:
    python automation/daemon.py start <session-name> [url]
    python automation/daemon.py stop  <session-name>
    python automation/daemon.py status
    python automation/daemon.py attach <session-name>   # interactive REPL

Wire protocol (newline-delimited JSON over Unix socket):
    Request:  {"cmd": "...", ...args}
    Response: {"ok": true, "result": ...}  |  {"ok": false, "error": "..."}

Supported commands:
    send      {"text": "..."}
    click     {"col": N, "row": N}
    key       {"key": "enter|tab|..."}
    drain     {"seconds": N}
    navigate  {"url": "..."}
    page_text {}                       → {"result": "..."}
    url       {}                       → {"result": "https://..."}
    close     {}                       → graceful shutdown
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import socketserver
import sys
import threading
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Find project root and add to path
# ---------------------------------------------------------------------------
_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from automation.browser import CarbonylBrowser, log
from automation.session import SessionManager, _DEFAULT_SESSION_DIR

_SOCK_SUFFIX = ".sock"
_PID_KEY = "daemon_pid"
_SOCK_KEY = "daemon_socket"


# ---------------------------------------------------------------------------
# Socket path helpers
# ---------------------------------------------------------------------------

def _sock_path(session_name: str, session_dir: Path | None = None) -> Path:
    root = session_dir or _DEFAULT_SESSION_DIR
    return root / f"{session_name}{_SOCK_SUFFIX}"


def is_daemon_live(session_name: str, session_dir: Path | None = None) -> bool:
    """Return True if a daemon is accepting connections for this session."""
    sock = _sock_path(session_name, session_dir)
    if not sock.exists():
        return False
    try:
        c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        c.settimeout(1.0)
        c.connect(str(sock))
        c.close()
        return True
    except (ConnectionRefusedError, FileNotFoundError, OSError):
        sock.unlink(missing_ok=True)
        return False


# ---------------------------------------------------------------------------
# Client proxy  (used by CarbonylBrowser when daemon is live)
# ---------------------------------------------------------------------------

class DaemonClient:
    """Thin client that forwards browser calls to a running daemon."""

    def __init__(self, session_name: str, session_dir: Path | None = None) -> None:
        self._sock_path = _sock_path(session_name, session_dir)
        self._sock: socket.socket | None = None
        self._buf = ""

    def connect(self) -> None:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(10.0)
        s.connect(str(self._sock_path))
        self._sock = s

    def disconnect(self) -> None:
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None

    def _rpc(self, payload: dict, timeout: float | None = None) -> dict:
        if not self._sock:
            raise RuntimeError("Not connected to daemon")
        # For drain commands, extend timeout beyond the drain duration
        if payload.get("cmd") == "drain" and timeout is None:
            timeout = payload.get("seconds", 2.0) + 10.0
        if timeout is not None:
            self._sock.settimeout(timeout)
        data = json.dumps(payload).encode() + b"\n"
        self._sock.sendall(data)
        # Read until newline
        resp_buf = b""
        while True:
            chunk = self._sock.recv(65536)
            if not chunk:
                raise RuntimeError("Daemon closed connection")
            resp_buf += chunk
            if b"\n" in resp_buf:
                break
        # Restore default timeout
        self._sock.settimeout(10.0)
        resp = json.loads(resp_buf.split(b"\n")[0])
        if not resp.get("ok"):
            raise RuntimeError(f"Daemon error: {resp.get('error')}")
        return resp

    # Mirror the CarbonylBrowser API
    def send(self, text: str) -> None:
        self._rpc({"cmd": "send", "text": text})

    def mouse_move(self, col: int, row: int) -> None:
        self._rpc({"cmd": "mouse_move", "col": col, "row": row})

    def click(self, col: int, row: int) -> None:
        self._rpc({"cmd": "click", "col": col, "row": row})

    def send_key(self, key: str) -> None:
        self._rpc({"cmd": "key", "key": key})

    def drain(self, seconds: float) -> None:
        self._rpc({"cmd": "drain", "seconds": seconds})

    def navigate(self, url: str) -> None:
        self._rpc({"cmd": "navigate", "url": url})

    def page_text(self) -> str:
        return self._rpc({"cmd": "page_text"})["result"]

    def nav_bar_url(self) -> str:
        return self._rpc({"cmd": "url"})["result"]

    def find_text(self, text: str) -> list[dict]:
        """Return [{col, row, end_col}, ...] for all occurrences (all 1-indexed)."""
        return self._rpc({"cmd": "find_text", "text": text})["result"]

    def raw_lines(self) -> list[dict]:
        """Return [{row, text}, ...] for the full raw screen buffer."""
        return self._rpc({"cmd": "raw_lines"})["result"]

    def close_daemon(self) -> None:
        """Send close command (shuts down daemon + browser)."""
        try:
            self._rpc({"cmd": "close"})
        except Exception:
            pass
        self.disconnect()


# ---------------------------------------------------------------------------
# Daemon server
# ---------------------------------------------------------------------------

class _BrowserHandler(socketserver.StreamRequestHandler):
    """Handle one client connection, dispatching JSON commands to the browser."""

    def handle(self):
        log(f"daemon: client connected from {self.client_address}")
        buf = b""
        try:
            while True:
                chunk = self.rfile.read1(65536)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        req = json.loads(line)
                        resp = self._dispatch(req)
                    except Exception as exc:
                        resp = {"ok": False, "error": str(exc)}
                    self.wfile.write(json.dumps(resp).encode() + b"\n")
                    self.wfile.flush()
                    if req.get("cmd") == "close":
                        return
        except Exception as exc:
            log(f"daemon: handler error: {exc}")

    def _dispatch(self, req: dict) -> dict:
        browser: CarbonylBrowser = self.server.browser
        cmd = req.get("cmd")
        try:
            if cmd == "send":
                browser.send(req["text"])
            elif cmd == "mouse_move":
                browser.mouse_move(req["col"], req["row"])
            elif cmd == "click":
                browser.click(req["col"], req["row"])
            elif cmd == "key":
                browser.send_key(req["key"])
            elif cmd == "drain":
                browser.drain(req.get("seconds", 2.0))
            elif cmd == "navigate":
                browser.navigate(req["url"])
            elif cmd == "page_text":
                return {"ok": True, "result": browser.page_text()}
            elif cmd == "url":
                return {"ok": True, "result": browser.nav_bar_url()}
            elif cmd == "find_text":
                # Find text in raw screen buffer; return [{col, row, end_col}, ...]
                # All values are 1-indexed (col of first char, end_col inclusive).
                needle = req.get("text", "")
                matches = []
                for row_idx in sorted(browser._screen.buffer.keys()):
                    row = browser._screen.buffer[row_idx]
                    line = "".join(c.data for c in row.values())
                    start = 0
                    while True:
                        idx = line.find(needle, start)
                        if idx == -1:
                            break
                        matches.append({
                            "col": idx + 1,
                            "row": row_idx + 1,
                            "end_col": idx + len(needle),
                        })
                        start = idx + 1
                return {"ok": True, "result": matches}
            elif cmd == "raw_lines":
                # Return raw screen lines as [{row, text}, ...] for coord-based search
                lines = []
                for row_idx in sorted(browser._screen.buffer.keys()):
                    row = browser._screen.buffer[row_idx]
                    lines.append({"row": row_idx + 1,
                                  "text": "".join(c.data for c in row.values())})
                return {"ok": True, "result": lines}
            elif cmd == "close":
                # Signal main thread to shut down
                self.server.shutdown_requested = True
                return {"ok": True, "result": "closing"}
            else:
                return {"ok": False, "error": f"Unknown command: {cmd!r}"}
            return {"ok": True, "result": None}
        except Exception as exc:
            return {"ok": False, "error": str(exc)}


class _BrowserServer(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True

    def __init__(self, sock_path: str, browser: CarbonylBrowser):
        self.browser = browser
        self.shutdown_requested = False
        # Remove stale socket
        try:
            os.unlink(sock_path)
        except FileNotFoundError:
            pass
        super().__init__(sock_path, _BrowserHandler)


# ---------------------------------------------------------------------------
# Daemon entry point (runs in the forked process)
# ---------------------------------------------------------------------------

def _run_daemon(
    session_name: str,
    url: str,
    sock_path: Path,
    session_dir: Path | None = None,
) -> None:
    """
    This function runs in the daemon process (after fork).
    Opens the browser, starts the socket server, serves until shutdown.
    """
    import atexit

    log(f"daemon: starting for session {session_name!r}")
    sm = SessionManager(session_dir)

    browser = CarbonylBrowser(session=session_name)
    browser.open(url)
    # Initial drain to let the page start loading
    browser.drain(3.0)

    server = _BrowserServer(str(sock_path), browser)
    log(f"daemon: listening on {sock_path}")

    # Update session metadata with socket path
    if sm.exists(session_name):
        try:
            meta = sm._read_meta(session_name)
            data = {
                "id": meta.id, "name": meta.name,
                "created_at": meta.created_at, "tags": meta.tags,
                "forked_from": meta.forked_from,
                "snapshot_of": meta.snapshot_of,
                _PID_KEY: os.getpid(),
                _SOCK_KEY: str(sock_path),
            }
            sm._meta_path(session_name).write_text(json.dumps(data, indent=2) + "\n")
        except Exception as exc:
            log(f"daemon: failed to update metadata: {exc}")

    def _cleanup():
        log("daemon: cleaning up...")
        try:
            sock_path.unlink(missing_ok=True)
        except Exception:
            pass
        browser.close()

    atexit.register(_cleanup)

    # Poll for shutdown request in a thread; serve_forever blocks otherwise
    def _watch():
        while not server.shutdown_requested:
            time.sleep(0.5)
        log("daemon: shutdown requested")
        server.shutdown()

    threading.Thread(target=_watch, daemon=True).start()
    server.serve_forever()
    _cleanup()
    log("daemon: exited")


# ---------------------------------------------------------------------------
# Public: start / stop / status
# ---------------------------------------------------------------------------

def start_daemon(
    session_name: str,
    url: str = "about:blank",
    session_dir: Path | None = None,
    *,
    wait: float = 5.0,
) -> int:
    """
    Fork a daemon process for this session and wait until it's accepting
    connections. Returns the daemon PID.
    """
    sm = SessionManager(session_dir)
    if not sm.exists(session_name):
        sm.create(session_name)

    sock = _sock_path(session_name, session_dir)

    if is_daemon_live(session_name, session_dir):
        raise RuntimeError(
            f"Daemon for session {session_name!r} is already running."
        )

    pid = os.fork()
    if pid == 0:
        # Child — become daemon
        os.setsid()
        # Redirect stdio to /dev/null
        devnull = os.open("/dev/null", os.O_RDWR)
        for fd in (0, 1, 2):
            os.dup2(devnull, fd)
        os.close(devnull)
        try:
            _run_daemon(session_name, url, sock, session_dir)
        except Exception:
            pass
        os._exit(0)
    else:
        # Parent — wait for socket to appear
        deadline = time.time() + wait
        while time.time() < deadline:
            if is_daemon_live(session_name, session_dir):
                return pid
            time.sleep(0.3)
        raise RuntimeError(
            f"Daemon for {session_name!r} did not start within {wait}s "
            f"(socket: {sock})"
        )


def stop_daemon(
    session_name: str,
    session_dir: Path | None = None,
) -> None:
    """Send a close command to the daemon, then clean up."""
    if not is_daemon_live(session_name, session_dir):
        log(f"No live daemon for {session_name!r}")
        return
    client = DaemonClient(session_name, session_dir)
    client.connect()
    client.close_daemon()
    log(f"Daemon for {session_name!r} stopped.")


def daemon_status(session_dir: Path | None = None) -> list[dict]:
    """Return status dicts for all sessions that have a live daemon."""
    sm = SessionManager(session_dir)
    results = []
    for s in sm.list():
        name = s["name"]
        live = is_daemon_live(name, session_dir)
        results.append({"session": name, "daemon_live": live})
    return results


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _cmd_start(args: argparse.Namespace) -> None:
    url = args.url or "about:blank"
    log(f"Starting daemon for session {args.session!r} → {url}")
    pid = start_daemon(args.session, url=url)
    print(f"Daemon started (PID {pid})")
    print(f"Socket: {_sock_path(args.session)}")


def _cmd_stop(args: argparse.Namespace) -> None:
    stop_daemon(args.session)


def _cmd_status(args: argparse.Namespace) -> None:
    statuses = daemon_status()
    if not statuses:
        print("No sessions.")
        return
    fmt = "{:<30} {}"
    print(fmt.format("SESSION", "DAEMON"))
    print("-" * 45)
    for s in statuses:
        live = "running" if s["daemon_live"] else "stopped"
        print(fmt.format(s["session"], live))


def _cmd_attach(args: argparse.Namespace) -> None:
    """Simple interactive REPL that relays commands to a live daemon."""
    if not is_daemon_live(args.session):
        print(f"No live daemon for {args.session!r}. Start one first.", file=sys.stderr)
        sys.exit(1)
    client = DaemonClient(args.session)
    client.connect()
    print(f"Attached to {args.session!r}. Commands: text|click col row|drain N|url|page|nav URL|quit")
    while True:
        try:
            line = input("> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not line:
            continue
        parts = line.split(None, 3)
        cmd = parts[0].lower()
        try:
            if cmd in ("quit", "exit", "q"):
                break
            elif cmd == "url":
                print(client.nav_bar_url())
            elif cmd == "page":
                print(client.page_text())
            elif cmd == "drain":
                secs = float(parts[1]) if len(parts) > 1 else 2.0
                client.drain(secs)
                print(f"(drained {secs}s)")
            elif cmd == "click":
                col, row = int(parts[1]), int(parts[2])
                client.click(col, row)
                print(f"(clicked {col},{row})")
            elif cmd == "nav":
                client.navigate(parts[1])
                print(f"(navigating to {parts[1]})")
            elif cmd == "key":
                client.send_key(parts[1])
                print(f"(key: {parts[1]})")
            elif cmd == "text":
                client.send(parts[1] if len(parts) > 1 else "")
            elif cmd == "stop":
                client.close_daemon()
                print("Daemon stopped.")
                break
            else:
                print(f"Unknown: {cmd!r}")
        except Exception as exc:
            print(f"Error: {exc}")
    client.disconnect()


def main() -> None:
    parser = argparse.ArgumentParser(description="Carbonyl browser daemon")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_start = sub.add_parser("start", help="Start a persistent browser daemon")
    p_start.add_argument("session", help="Session name")
    p_start.add_argument("url", nargs="?", default=None, help="Initial URL (default: about:blank)")

    p_stop = sub.add_parser("stop", help="Stop a running daemon")
    p_stop.add_argument("session")

    sub.add_parser("status", help="Show daemon status for all sessions")

    p_attach = sub.add_parser("attach", help="Interactive REPL for a live daemon")
    p_attach.add_argument("session")

    args = parser.parse_args()
    {"start": _cmd_start, "stop": _cmd_stop, "status": _cmd_status, "attach": _cmd_attach}[args.cmd](args)


if __name__ == "__main__":
    main()
