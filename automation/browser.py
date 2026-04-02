#!/usr/bin/env python3
"""
Carbonyl browser automation layer.

Spawns Carbonyl in a PTY via Docker, sends keystrokes, and returns the
rendered screen as plain text using a pyte terminal emulator.

Usage:
    python automation/browser.py search "search term"
    python automation/browser.py open https://example.com --wait 10
"""

import argparse
import re
import sys
import time
import unicodedata

import pexpect
import pyte

# Terminal dimensions Carbonyl will render to
COLS = 220
ROWS = 50

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
    def __init__(self, cols: int = COLS, rows: int = ROWS):
        self.cols = cols
        self.rows = rows
        self._screen = pyte.Screen(cols, rows)
        self._stream = pyte.ByteStream(self._screen)
        self._child: pexpect.spawn | None = None

    def open(self, url: str) -> None:
        # -t allocates a TTY inside the container so Carbonyl sees isatty(stdout)
        cmd = (
            f"docker run --rm -it "
            f"fathyb/carbonyl --fps=5 {url}"
        )
        self._child = pexpect.spawn(
            "bash", ["-c", cmd],
            dimensions=(self.rows, self.cols),
            timeout=90,
            encoding=None,  # raw bytes — pyte needs bytes
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

    def nav_bar_url(self) -> str:
        """Extract the URL shown in Carbonyl's navigation bar, if visible."""
        text = self.page_text()
        m = re.search(r"https?://[^\s\]]+", text)
        return m.group(0) if m else ""

    def page_text(self) -> str:
        """Return current screen as clean readable text."""
        return extract_text(self._screen)

    def close(self) -> None:
        if self._child and self._child.isalive():
            self._child.terminate(force=True)


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
