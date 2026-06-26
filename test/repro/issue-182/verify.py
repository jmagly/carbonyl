#!/usr/bin/env python3
"""Issue #182 local diagnostic for promptless downloads."""

from __future__ import annotations

import contextlib
import http.server
import os
import pathlib
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time


FILENAME = "carbonyl-issue-182.txt"
CONTENT = b"Carbonyl issue 182 download fixture\n"


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/download":
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Disposition", f'attachment; filename="{FILENAME}"')
        self.send_header("Content-Length", str(len(CONTENT)))
        self.end_headers()
        self.wfile.write(CONTENT)

    def log_message(self, fmt, *args):
        return


def carbonyl_bin() -> str:
    return os.environ.get("CARBONYL_BIN", "carbonyl")


def timeout_seconds() -> int:
    return int(os.environ.get("ISSUE182_TIMEOUT", "20"))


@contextlib.contextmanager
def serve_fixture():
    with ReusableTCPServer(("127.0.0.1", 0), Handler) as httpd:
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        try:
            yield f"http://127.0.0.1:{httpd.server_address[1]}/download"
        finally:
            httpd.shutdown()
            thread.join(timeout=5)


def main() -> int:
    work = pathlib.Path(tempfile.mkdtemp(prefix="carbonyl-issue-182."))
    download_dir = work / "downloads"
    download_dir.mkdir()
    try:
        with serve_fixture() as url:
            proc = subprocess.Popen(
                [
                    carbonyl_bin(),
                    f"--download-dir={download_dir}",
                    f"--user-data-dir={work / 'profile'}",
                    "--no-sandbox",
                    "--disable-gpu",
                    url,
                ],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            target = download_dir / FILENAME
            deadline = time.time() + timeout_seconds()
            while time.time() < deadline:
                if target.exists() and target.read_bytes() == CONTENT:
                    proc.terminate()
                    proc.wait(timeout=5)
                    print("PASS: attachment downloaded to --download-dir.")
                    print(f"download: {target}")
                    return 0
                time.sleep(0.25)

            proc.terminate()
            try:
                _, stderr = proc.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                _, stderr = proc.communicate(timeout=5)
            print("FAIL: expected download did not appear.")
            print(f"download dir: {download_dir}")
            if stderr:
                print("stderr tail:")
                for line in stderr.decode(errors="replace").splitlines()[-8:]:
                    print(f"  {line}")
            return 1
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
