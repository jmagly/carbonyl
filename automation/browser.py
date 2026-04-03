#!/usr/bin/env python3
"""
Carbonyl browser automation layer.

Spawns Carbonyl in a PTY (local binary or Docker fallback), sends
keystrokes, and returns the rendered screen as plain text via pyte.

Local binary (preferred):
    build/pre-built/x86_64-unknown-linux-gnu/carbonyl
    Built by: scripts/build-local.sh

Docker fallback (if no local binary):
    docker run fathyb/carbonyl

Usage:
    python automation/browser.py search "search term"
    python automation/browser.py open https://example.com --wait 10
"""

import argparse
import os
import re
import subprocess
import sys
import time
import unicodedata
from pathlib import Path

import pexpect
import pyte

# Terminal dimensions Carbonyl will render to
COLS = 220
ROWS = 50

# Repo root — two levels up from this file (automation/browser.py)
_REPO_ROOT = Path(__file__).resolve().parent.parent

# Chromium flags to suppress first-run noise, sync, and keychain prompts.
# Applied to every Carbonyl launch regardless of session.
_HEADLESS_FLAGS = [
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-sync",
    "--password-store=basic",
    "--use-mock-keychain",
]

def _session_manager():
    """Import and return a SessionManager, handling both package and script contexts."""
    try:
        from automation.session import SessionManager
    except ImportError:
        # Running as a script directly (python automation/browser.py)
        import importlib.util
        _spec = importlib.util.spec_from_file_location(
            "session", Path(__file__).parent / "session.py"
        )
        _mod = importlib.util.module_from_spec(_spec)
        _spec.loader.exec_module(_mod)
        SessionManager = _mod.SessionManager
    return SessionManager()


def _local_binary() -> Path | None:
    """Return path to local carbonyl binary if it exists and is executable."""
    triple = subprocess.run(
        ["bash", "scripts/platform-triple.sh"],
        capture_output=True, text=True, cwd=_REPO_ROOT,
    ).stdout.strip()
    candidate = _REPO_ROOT / "build" / "pre-built" / triple / "carbonyl"
    return candidate if candidate.is_file() and os.access(candidate, os.X_OK) else None

# Unicode ranges that are graphical block/box characters Carbonyl uses for
# pixel-level rendering. These are not page text — strip them for agents.
_BLOCK_CHARS = re.compile(
    r"[\u2500-\u257F"   # Box Drawing
    r"\u2580-\u259F"   # Block Elements (▀▄█▌▐░▒▓ etc.)
    r"\u25A0-\u25FF"   # Geometric Shapes
    r"\uFFFD]"         # Replacement char
)


def _is_text_char(ch: str) -> bool:
    """Return True for printable non-block characters."""
    if _BLOCK_CHARS.match(ch):
        return False
    cat = unicodedata.category(ch)
    # Keep letters, numbers, punctuation, symbols, spaces
    return cat[0] in ("L", "N", "P", "S", "Z") or ch == " "


def extract_text(screen: pyte.Screen) -> str:
    """
    Pull readable text out of a pyte screen, filtering out the block/quad
    characters Carbonyl uses for graphical rendering.
    Returns lines with leading/trailing whitespace stripped, blank lines
    collapsed, result trimmed.
    """
    lines = []
    for row_idx in sorted(screen.buffer.keys()):
        row = screen.buffer[row_idx]
        raw = "".join(char.data for char in row.values())
        # Keep only text characters
        text = "".join(ch if _is_text_char(ch) else " " for ch in raw)
        # Collapse runs of spaces
        text = re.sub(r" {2,}", "  ", text).strip()
        if text:
            lines.append(text)
    # Deduplicate consecutive identical lines (artifact of rendering)
    deduped = []
    for line in lines:
        if not deduped or line != deduped[-1]:
            deduped.append(line)
    return "\n".join(deduped)


class CarbonylBrowser:
    def __init__(
        self,
        cols: int = COLS,
        rows: int = ROWS,
        session: str | None = None,
    ):
        """
        Args:
            cols, rows: Terminal dimensions Carbonyl renders to.
            session: Named session to use for persistent state. If given,
                     the session's profile directory is passed as
                     ``--user-data-dir`` to Chromium, preserving cookies,
                     localStorage, and IndexedDB across browser restarts.
                     Create/manage sessions with ``automation/session.py``
                     or ``SessionManager``.
        """
        self.cols = cols
        self.rows = rows
        self._session = session
        self._screen = pyte.Screen(cols, rows)
        self._stream = pyte.ByteStream(self._screen)
        self._child: pexpect.spawn | None = None

    def open(self, url: str) -> None:
        binary = _local_binary()
        args = ["--fps=5", "--no-sandbox"] + _HEADLESS_FLAGS

        if self._session:
            sm = _session_manager()
            if not sm.exists(self._session):
                sm.create(self._session)
            sm.clean_stale_lock(self._session)
            profile = sm.profile_dir(self._session)
            args.append(f"--user-data-dir={profile}")
            log(f"session: {self._session!r}  profile: {profile}")

        args.append(url)

        if binary:
            lib_dir = str(binary.parent)
            env = {**os.environ, "LD_LIBRARY_PATH": lib_dir}
            log(f"using local binary: {binary}")
            self._child = pexpect.spawn(
                str(binary), args,
                dimensions=(self.rows, self.cols),
                timeout=90,
                encoding=None,
                env=env,
                cwd=str(binary.parent),
            )
        else:
            log("local binary not found, falling back to Docker image")
            # Docker: mount session profile if provided; ignore _HEADLESS_FLAGS
            # (they're already baked into the image entrypoint)
            flag_str = " ".join(
                a for a in args
                if not a.startswith("--user-data-dir")
                and a not in _HEADLESS_FLAGS
            )
            vol = ""
            if self._session:
                sm = _session_manager()
                profile = sm.profile_dir(self._session)
                vol = f"-v {profile}:/data/profile "
                flag_str += " --user-data-dir=/data/profile"
            cmd = f"docker run --rm -it {vol}fathyb/carbonyl {flag_str}"
            self._child = pexpect.spawn(
                "bash", ["-c", cmd],
                dimensions=(self.rows, self.cols),
                timeout=90,
                encoding=None,
            )

    def drain(self, seconds: float) -> None:
        """Read output for `seconds`, feeding bytes into the screen buffer."""
        deadline = time.time() + seconds
        while time.time() < deadline:
            try:
                chunk = self._child.read_nonblocking(size=8192, timeout=0.1)
                self._stream.feed(chunk)
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

    def send(self, text: str) -> None:
        """Type text into the browser (encodes as UTF-8 bytes)."""
        self._child.send(text.encode("utf-8"))

    def click(self, col: int, row: int) -> None:
        """Send a left-click at terminal cell (col, row) using SGR mouse protocol."""
        press   = f"\x1b[<0;{col};{row}M".encode()
        release = f"\x1b[<0;{col};{row}m".encode()
        self._child.send(press)
        self._child.send(release)

    def click_on(self, text: str, offset_col: int = 0) -> bool:
        """
        Find `text` in the current screen buffer and click just after it.
        Returns True if found and clicked, False if not found.
        """
        for row_idx in sorted(self._screen.buffer.keys()):
            row = self._screen.buffer[row_idx]
            line = "".join(char.data for char in row.values())
            col = line.find(text)
            if col != -1:
                self.click(col + len(text) + 1 + offset_col, row_idx + 1)
                return True
        return False

    def send_key(self, key: str) -> None:
        """Send a named key sequence."""
        keys = {
            "enter":     b"\r",
            "tab":       b"\t",
            "backspace": b"\x7f",
            "up":        b"\x1b[A",
            "down":      b"\x1b[B",
            "left":      b"\x1b[D",
            "right":     b"\x1b[C",
            "escape":    b"\x1b",
        }
        seq = keys.get(key.lower())
        if seq is None:
            raise ValueError(f"Unknown key: {key!r}. Valid: {list(keys)}")
        self._child.send(seq)

    def navigate(self, url: str) -> None:
        """
        Navigate to `url` by editing the Carbonyl address bar directly.

        Carbonyl nav bar layout (row 0 in Carbonyl = terminal row 1):
          col 0-2   [❮] back   → mouse_down x in 0..=2
          col 3-5   [❯] forward → mouse_down x in 3..=5
          col 6-8   [↻] refresh → mouse_down x in 6..=8
          col 9     [
          col 10    space
          col 11+   URL field  → cursor = x - 11

        Clicking at terminal (col, row=1) with col >= 12 focuses the URL bar.
        Arrow keys (via ANSI sequences) move the cursor within the URL.
        """
        # 1. Click at col=12 row=1 → Carbonyl x=11 → cursor pos 0 in URL field
        self.click(12, 1)
        # 2. Jump cursor to end of current URL (Down arrow = \x1b[B = 0x12 internally)
        self._child.send(b"\x1b[B")
        # 3. Backspace entire URL (200 chars is more than any URL we'd see)
        self._child.send(b"\x7f" * 250)
        # 4. Type new URL
        self._child.send(url.encode("ascii"))
        # 5. Press Enter to navigate
        self._child.send(b"\r")

    def nav_bar_url(self) -> str:
        """Extract the URL shown in Carbonyl's navigation bar, if visible."""
        text = self.page_text()
        m = re.search(r"https?://[^\s\]]+", text)
        return m.group(0) if m else ""

    def page_text(self) -> str:
        """Return current screen as clean readable text."""
        return extract_text(self._screen)

    def close(self) -> None:
        if self._child:
            try:
                import signal, os
                if self._child.isalive():
                    # Kill the entire process group so Chromium child processes die too
                    try:
                        os.killpg(os.getpgid(self._child.pid), signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    self._child.terminate(force=True)
            except Exception:
                pass


def search_duckduckgo(
    query: str,
    wait_load: float = 8.0,
    wait_results: float = 12.0,
) -> str:
    """
    Open DuckDuckGo, type `query` into the autofocused search box,
    submit, and return the results page as clean text.
    """
    browser = CarbonylBrowser()
    try:
        log(f"opening https://duckduckgo.com ...")
        browser.open("https://duckduckgo.com")

        log(f"waiting {wait_load}s for page load ...")
        browser.drain(wait_load)

        # DuckDuckGo autofocuses the search box — type directly
        log(f"typing: {query!r}")
        browser.send(query)
        browser.drain(1.5)   # let autocomplete settle

        log("submitting (Enter) ...")
        browser.send_key("enter")

        log(f"waiting {wait_results}s for results ...")
        browser.drain(wait_results)

        url = browser.nav_bar_url()
        log(f"current URL: {url}")

        return browser.page_text()
    finally:
        browser.close()


def log(msg: str) -> None:
    print(f"[carbonyl] {msg}", file=sys.stderr, flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Carbonyl browser automation")
    sub = parser.add_subparsers(dest="cmd")

    sp = sub.add_parser("search", help="Search DuckDuckGo and print results as text")
    sp.add_argument("query", help="Search query")
    sp.add_argument("--wait-load", type=float, default=8.0, metavar="SEC")
    sp.add_argument("--wait-results", type=float, default=12.0, metavar="SEC")

    op = sub.add_parser("open", help="Open a URL and print page as text")
    op.add_argument("url")
    op.add_argument("--wait", type=float, default=10.0, metavar="SEC")

    args = parser.parse_args()

    if args.cmd == "search":
        print(search_duckduckgo(args.query, args.wait_load, args.wait_results))
    elif args.cmd == "open":
        browser = CarbonylBrowser()
        try:
            browser.open(args.url)
            browser.drain(args.wait)
            print(browser.page_text())
        finally:
            browser.close()
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
