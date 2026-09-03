#!/usr/bin/env python3
"""Loopback-only fixture server for the native operator controls (#288)."""

from __future__ import annotations

import http.server
import time
from urllib.parse import urlsplit


PAGE = """<!doctype html>
<meta charset="utf-8">
<title>operator controls {name}</title>
<style>
html, body {{ width: 100%; height: 100%; margin: 0; }}
body {{ background: {background}; }}
#page-marker, #input-marker, #leak-marker {{
  position: fixed; width: 48px; height: 48px; bottom: 8px;
}}
#page-marker {{ left: 8px; background: {marker}; }}
#input-marker {{ left: 72px; background: #222222; }}
#leak-marker {{ left: 136px; background: #222222; }}
input {{ margin: 12px; width: 240px; height: 32px; }}
</style>
<input id="page-input" autofocus aria-label="page input">
<div id="page-marker"></div>
<div id="input-marker"></div>
<div id="leak-marker"></div>
<script>
const input = document.querySelector('#page-input');
const inputMarker = document.querySelector('#input-marker');
const leakMarker = document.querySelector('#leak-marker');
input.addEventListener('input', event => {{
  if (event.isTrusted &&
      (input.value.endsWith('page-input') ||
       input.value.endsWith('zoom-focus'))) {{
    inputMarker.style.background = '#7733aa';
  }}
}});
addEventListener('keydown', event => {{
  if (event.isTrusted &&
      ((event.ctrlKey &&
        ['l', 'r', '+', '=', '-', '0'].includes(event.key)) ||
       (event.altKey && (event.key === 'ArrowLeft' ||
                        event.key === 'ArrowRight')))) {{
    leakMarker.style.background = '#aa0011';
  }}
}}, {{capture: true}});
</script>
"""


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        path = urlsplit(self.path).path
        print(f"GET {path}", flush=True)
        if path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/two")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if path == "/slow":
            body = PAGE.format(
                name="slow", background="#554400", marker="#ddaa00"
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body) + 8))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
            time.sleep(20)
            try:
                self.wfile.write(b"<!--x-->")
            except (BrokenPipeError, ConnectionResetError):
                pass
            return

        if path == "/two":
            body = PAGE.format(
                name="two", background="#112266", marker="#22aaee"
            ).encode()
        else:
            body = PAGE.format(
                name="one", background="#116611", marker="#11cc44"
            ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    server = Server(("127.0.0.1", 0), Handler)
    print(f"PORT {server.server_port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
