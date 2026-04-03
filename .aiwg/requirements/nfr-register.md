# NFR Register: Carbonyl Automation Layer

**Version**: 1.0
**Date**: 2026-04-02
**Scope**: Python automation library (`automation/`) over the Carbonyl terminal browser (headless Chromium via PTY).
**Components**: `CarbonylBrowser` (browser.py), `DaemonClient` / `_BrowserServer` (daemon.py), `SessionManager` (session.py), `ScreenInspector` (screen_inspector.py).

---

## NFR-001: drain() Completes Within a Bounded Time Window

**Category**: Performance

**Statement**: `CarbonylBrowser.drain(seconds)` MUST return no later than `seconds + 0.5s` after it is called. The caller bears full responsibility for selecting a wait duration that is appropriate for the expected page render. The library MUST NOT silently extend or repeat the wait.

**Rationale**: `drain()` is the sole mechanism for letting Carbonyl render output into the pyte screen buffer. Because Chromium rendering is non-deterministic, the library cannot know when a page is "done." The contract is therefore time-bounded rather than content-based: callers choose a duration (typically 2–8 s for first load, 1–3 s for interactions) and accept the tradeoff between latency and render completeness. Exceeding the specified window without notice would break every automation script that sequences actions on timing.

**Acceptance Criteria**:
- [ ] `drain(N)` returns within `N + 0.5 s` under normal I/O conditions (verified by timing the call with `time.monotonic()`).
- [ ] When `pexpect.EOF` is raised (process exited) during draining, `drain()` exits immediately rather than waiting for the remainder of the window.
- [ ] `drain()` on a daemon-connected browser delegates to `DaemonClient.drain()`, which sets the socket timeout to `seconds + 10 s` to absorb round-trip overhead without masking hang conditions.
- [ ] Documentation (docstring or README) states the 2–8 s typical range and the caller-chosen tradeoff explicitly.

**Current Status**: Met — `drain()` in browser.py loops with 0.1 s non-blocking reads and breaks on EOF; `DaemonClient._rpc` extends the socket timeout by 10 s for drain commands.

---

## NFR-002: find_text() Completes in Under 100 ms on a Full 50-Row Screen

**Category**: Performance

**Statement**: `CarbonylBrowser.find_text(text)` and `ScreenInspector.find()` MUST complete in under 100 ms when the pyte screen buffer contains the maximum configured screen size (COLS=220, ROWS=50).

**Rationale**: `find_text()` is called inline during interactive automation sequences — inside `click_on()`, `click_at_row()`, and agent reasoning loops. Any latency above 100 ms compounds with network and rendering waits to make scripts feel sluggish and breaks time-budget assumptions in tight interaction loops. A 220×50 screen is 11 000 characters; a linear string search over that space is well within the 100 ms budget on any modern CPU.

**Acceptance Criteria**:
- [ ] Timed invocation of `find_text("nonexistent")` (worst case — scans entire buffer) on a fully populated 220×50 pyte screen completes in under 100 ms on the reference platform (x86_64 Linux, Python 3.11+).
- [ ] `click_on()` and `click_at_row()` call `find_text()` at most once per invocation; they do not iterate the buffer again internally.
- [ ] Daemon-side `find_text` handler (dispatched in `_dispatch`) performs the same O(ROWS × COLS) scan without additional copies of the buffer.

**Current Status**: Met — both implementations are single-pass `str.find` loops over at most 50 rows; no regex, no sorting beyond `sorted(buffer.keys())`.

---

## NFR-003: Daemon RPC Round-Trip Latency

**Category**: Performance

**Statement**: For commands that do not involve waiting (e.g., `send`, `click`, `navigate`, `page_text`, `find_text`), the Unix socket RPC round-trip between `DaemonClient` and `_BrowserServer` MUST add no more than 20 ms of overhead over the equivalent direct in-process call on the same host.

**Rationale**: The daemon exists to eliminate Chromium cold-start time, not to introduce per-command overhead. Each automation script may issue dozens of `find_text` + `click` pairs per page interaction. An overhead budget of 20 ms per non-drain RPC keeps a 30-command sequence under 600 ms of pure protocol overhead — acceptable when page render time dominates.

**Acceptance Criteria**:
- [ ] `DaemonClient.page_text()` measured end-to-end (send JSON + recv JSON over Unix socket) averages under 20 ms on localhost under no contention.
- [ ] The wire protocol is newline-delimited JSON (no framing, no compression, no encryption) — the simplest framing that achieves the latency budget.
- [ ] The socket is `AF_UNIX SOCK_STREAM`; TCP loopback is never used (avoids TCP handshake and Nagle delays).
- [ ] `_rpc()` issues a single `sendall` and a single `recv` loop; it does not add artificial delays or retries for non-drain commands.

**Current Status**: Met — daemon.py uses `AF_UNIX`, newline-delimited JSON, and single-shot send/recv. No benchmarks are currently captured in CI.

---

## NFR-004: Daemon Survives Client Disconnect Without Crashing

**Category**: Reliability

**Statement**: A running `_BrowserServer` daemon MUST continue accepting new connections after any number of client disconnects, including abrupt disconnects (client crash, `SIGKILL`, network interruption on non-Unix transports).

**Rationale**: The daemon's entire value proposition is persistence — it outlives any single automation script. If a client script crashes or is killed mid-session, the browser and its authenticated session state must remain intact for the next client to reconnect. A daemon that exits on client disconnect defeats the purpose and can corrupt ongoing page state.

**Acceptance Criteria**:
- [ ] `_BrowserHandler.handle()` catches all exceptions in the outer `try/except` and logs them without re-raising; the `socketserver.ThreadingUnixStreamServer` thread pool continues accepting new connections.
- [ ] After a client socket is closed mid-read (simulated by `connection.close()` without sending EOF), the handler exits cleanly and the server thread count returns to baseline.
- [ ] `daemon_threads = True` is set on `_BrowserServer` so handler threads do not block server shutdown or accumulate indefinitely.
- [ ] `is_daemon_live()` returns True for the session after a client disconnect, and a new `DaemonClient.connect()` succeeds.

**Current Status**: Met — `_BrowserHandler.handle()` wraps the dispatch loop in `try/except`; `daemon_threads = True` is set; `is_daemon_live()` tests the socket with a fresh connection.

---

## NFR-005: Session Profile Must Not Be Corrupted on SIGKILL

**Category**: Reliability

**Statement**: If the Carbonyl/Chromium process is terminated with `SIGKILL` while a named session is active, the session profile directory MUST remain in a state from which Chromium can start cleanly on the next launch (stale `SingletonLock` removed, profile files not truncated mid-write).

**Rationale**: Chromium writes session data continuously. A `SIGKILL` prevents Chromium's own cleanup. The automation layer must not rely solely on Chromium's graceful exit path. If a stale `SingletonLock` remains, the next `open()` will fail silently or attempt to connect to a dead process. Profile file corruption (e.g., half-written SQLite WAL) is a Chromium-internal concern; the automation layer's responsibility is lock hygiene.

**Acceptance Criteria**:
- [ ] `SessionManager.clean_stale_lock(name)` is called by `CarbonylBrowser.open()` before spawning a new browser process for a named session (see browser.py line ~199).
- [ ] `_is_stale_lock()` reads the `SingletonLock` symlink, extracts the PID, and verifies it with `os.kill(pid, 0)` before declaring the lock stale; it does not unconditionally delete locks.
- [ ] `SessionManager.fork()` and `SessionManager.restore()` always clean the `SingletonLock` from the destination profile before returning.
- [ ] A SIGKILL scenario can be exercised manually: kill the Carbonyl PID, then verify `open()` succeeds on the next call for the same session without manual intervention.

**Current Status**: Met — `clean_stale_lock` is called in `open()` and in `fork()`/`restore()` profile copies. `_is_stale_lock` uses `os.kill(pid, 0)`.

---

## NFR-006: Graceful Recovery When Carbonyl Process Dies Unexpectedly

**Category**: Reliability

**Statement**: If the Carbonyl process exits unexpectedly during a `drain()` or `send()` call, the `CarbonylBrowser` MUST raise or return a defined error state rather than hanging indefinitely. Daemon-mode browsers MUST allow reconnection after the daemon is restarted.

**Rationale**: Chromium can crash (OOM, GPU fault, signal from OS). An automation script that blocks forever on a dead process is unrecoverable without external timeout infrastructure. The library must expose the failure so the caller can react (retry, restart daemon, alert).

**Acceptance Criteria**:
- [ ] `drain()` catches `pexpect.EOF` and exits the loop immediately when the child process has exited; it does not raise an unhandled exception.
- [ ] `send()` on a dead `pexpect` child raises `pexpect.EOF` or `OSError`; it does not silently discard bytes or block.
- [ ] `DaemonClient._rpc()` raises `RuntimeError("Daemon closed connection")` when the daemon process is gone and the socket returns an empty read.
- [ ] `is_daemon_live()` removes the stale socket file (`sock.unlink(missing_ok=True)`) when a connection attempt fails, preventing future `connect()` calls from hanging on the dead socket.

**Current Status**: Partially Met — `drain()` handles EOF correctly; `is_daemon_live()` cleans the stale socket. However, `send()` on a dead child propagates `pexpect.EOF` without a structured error message, and there is no automatic restart or reconnect logic at the library level.

---

## NFR-007: Unix Socket Access Control (Local Process Isolation)

**Category**: Security

**Statement**: The daemon Unix socket MUST be accessible only to the OS user that started the daemon. No world-readable or group-readable socket permissions are acceptable.

**Rationale**: The daemon socket accepts arbitrary browser commands (navigate, click, send keystrokes, read page text). Any process that can connect can exfiltrate session cookies, inject keystrokes, or navigate to attacker-controlled URLs. Since the daemon is local-only, file permission bits on the socket file are the correct isolation boundary.

**Acceptance Criteria**:
- [ ] The socket file created by `_BrowserServer.__init__()` (via `socketserver.UnixStreamServer`) has permissions `0o600` or stricter (owner read/write only) on all supported platforms.
- [ ] No code path sets `SO_REUSEADDR` or equivalent flags that would loosen socket isolation.
- [ ] The daemon startup documentation notes that socket permissions are the security boundary and warns against running the daemon as root or in world-accessible directories.
- [ ] If the socket path resolves to a world-writable directory (e.g., `/tmp`), the daemon SHOULD log a warning at startup.

**Current Status**: Not Met — `_BrowserServer` inherits from `socketserver.ThreadingUnixStreamServer` without explicitly setting socket file permissions after creation. Default `umask` may result in `0o600`, but this is not enforced by code. No warning is emitted for world-writable socket directories. The default socket path is derived from the session directory (`~/.local/share/carbonyl/sessions/<name>.sock`), which is typically private, but this is not verified.

---

## NFR-008: Credential Files Must Not Be Readable by Other Users

**Category**: Security

**Statement**: Any file written by the automation layer that contains or could contain credentials (session metadata `session.json`, profile directories) MUST be created with permissions that prevent read access by other OS users (`chmod 700` for directories, `chmod 600` for files).

**Rationale**: Chromium session profiles contain authentication cookies, localStorage tokens, and cached credentials. On multi-user systems, world-readable profile directories expose authenticated sessions to any local user. `session.json` additionally contains daemon PID and socket path, which could be used to attach to a running browser.

**Acceptance Criteria**:
- [ ] `SessionManager.create()` creates the session directory and profile subdirectory with mode `0o700`.
- [ ] `session.json` is written with mode `0o600`.
- [ ] `SessionManager.fork()` and `SessionManager.restore()` apply the same permission constraints to the copied profile tree.
- [ ] A new installation on a system where `umask 022` is set (common default) results in profile directories that are not world-readable.

**Current Status**: Not Met — `SessionManager` uses `profile.mkdir(parents=True, exist_ok=True)` and `Path.write_text()` without explicit `mode` arguments. Effective permissions depend entirely on the process `umask`. No `chmod` or `os.makedirs(..., mode=0o700)` calls are present.

---

## NFR-009: MFA Code Delivery via /tmp Must Be Secured

**Category**: Security

**Statement**: If any automation script uses `/tmp` as an inter-process channel for delivering MFA codes or other credentials, that file MUST use `O_CREAT | O_EXCL` creation (no TOCTOU race) and MUST be created with mode `0o600`. The file MUST be deleted immediately after consumption.

**Rationale**: `/tmp` is world-readable on most Linux systems. A race between file creation and permission-setting allows a local attacker to read the MFA code before the automation layer consumes it. MFA codes are time-limited but still represent a meaningful attack window on multi-user systems.

**Acceptance Criteria**:
- [ ] Any use of `/tmp` for credential delivery creates files atomically using `os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)` rather than `open(path, "w")`.
- [ ] The consuming code deletes the file with `os.unlink()` in a `finally` block.
- [ ] Alternatively, `tempfile.NamedTemporaryFile(mode='w', delete=False)` is used with explicit `os.chmod(path, 0o600)` before writing.
- [ ] Documentation notes that `/tmp`-based credential delivery is discouraged on shared systems and recommends environment variables or named pipes as alternatives.

**Current Status**: N/A — The current automation layer source code (`browser.py`, `daemon.py`, `session.py`, `screen_inspector.py`) does not use `/tmp` for credential delivery. This NFR applies to downstream automation scripts built on the library. It should be enforced via code review policy for any scripts that handle MFA.

---

## NFR-010: Linux x86_64 as Primary Platform; arm64 as Secondary

**Category**: Compatibility

**Statement**: The automation layer MUST run correctly on Linux x86_64. It SHOULD run on Linux arm64. No other operating systems are in scope for the pre-built binary path.

**Rationale**: Carbonyl pre-built binaries are distributed per target triple (e.g., `x86_64-unknown-linux-gnu`). The `_local_binary()` function selects the binary by running `scripts/platform-triple.sh`. Docker fallback extends reach to any platform with Docker, but incurs significant startup overhead and is not suitable for latency-sensitive automation.

**Acceptance Criteria**:
- [ ] `scripts/platform-triple.sh` returns a valid triple for x86_64 Linux and the corresponding binary exists at `build/pre-built/<triple>/carbonyl`.
- [ ] All automation tests pass on x86_64 Linux without Docker fallback.
- [ ] On arm64 Linux, `_local_binary()` either returns a valid arm64 binary path or falls back to Docker without crashing.
- [ ] The library does not use any x86_64-specific Python extensions or C extensions (only `pexpect` and `pyte`, both pure Python).
- [ ] `LD_LIBRARY_PATH` is set to the binary's directory at spawn time to satisfy Chromium's shared library dependencies.

**Current Status**: Met for x86_64 — binary exists at `build/pre-built/x86_64-unknown-linux-gnu/`. arm64 support is not validated by CI (no arm64 binary present in the repo).

---

## NFR-011: Python 3.11 Minimum Version

**Category**: Compatibility

**Statement**: The automation layer MUST require Python 3.11 or later and MUST NOT use language features or standard library APIs unavailable in Python 3.11.

**Rationale**: The codebase uses PEP 604 union type syntax (`X | Y`) in function signatures, which is only valid in annotations at runtime on Python 3.10+ and requires `from __future__ import annotations` on 3.9. Without this constraint being explicit, installation on older environments fails at import time with a cryptic `TypeError`, not a readable version error.

**Acceptance Criteria**:
- [ ] `automation/requirements.txt` or a `pyproject.toml` specifies `python_requires = ">=3.11"`.
- [ ] Running the library on Python 3.10 or earlier produces a clear version error at startup (not a `SyntaxError` or `TypeError` deep in a call stack).
- [ ] All files that use `X | Y` union syntax in runtime-evaluated positions (not just annotations) are guarded with `from __future__ import annotations` or restructured to use `Optional[X]` / `Union[X, Y]`.

**Current Status**: Partially Met — the code uses `X | Y` syntax throughout (e.g., `Path | None`, `str | None`). `daemon.py` and `screen_inspector.py` have `from __future__ import annotations`. `browser.py` does not have this guard but uses `X | Y` only in function signatures, which are lazily evaluated in Python 3.10+. No `python_requires` constraint is declared in `requirements.txt`.

---

## NFR-012: 1-Indexed Coordinate Convention Enforced Consistently

**Category**: Maintainability

**Statement**: All functions that accept or return terminal coordinates (column, row) MUST use the 1-indexed convention. The convention MUST be documented at the point of definition. Any function that internally uses 0-indexed offsets MUST convert before returning values to callers.

**Rationale**: SGR mouse protocol uses 1-indexed coordinates (e.g., `\x1b[<0;col;rowM`). pyte's screen buffer is 0-indexed internally. Mixing conventions silently shifts click targets by one cell and produces bugs that are difficult to diagnose because the error is exactly one character off. Enforcing 1-indexing at every public API boundary eliminates an entire class of off-by-one errors.

**Acceptance Criteria**:
- [ ] Every public function that accepts `col`/`row` parameters has a docstring stating "1-indexed" explicitly.
- [ ] `find_text()` in both `CarbonylBrowser` and `_dispatch` returns `col = idx + 1` and `row = row_idx + 1` (verified in code).
- [ ] `raw_lines()` returns `row = row_idx + 1`.
- [ ] `ScreenInspector.find()` returns `col = idx + 1` and does not mix 0-indexed offsets in its return values.
- [ ] New functions added to any of the four modules are reviewed for coordinate convention compliance before merge.

**Current Status**: Met — all public return values add `+1` to pyte's 0-indexed row/col. The `find_text` docstring in browser.py explicitly documents 1-indexed return values. `ScreenInspector` docstring states "Rows and cols are 1-indexed."

---

## NFR-013: New Browser Commands Must Be Added to Both CarbonylBrowser and DaemonClient

**Category**: Maintainability

**Statement**: Any new browser command (a method on `CarbonylBrowser`) MUST be mirrored by a corresponding method on `DaemonClient` and a handler case in `_BrowserServer._dispatch()`. The two implementations MUST produce identical results as observed by the caller.

**Rationale**: `CarbonylBrowser` operates in two modes: direct PTY (using `pexpect`) and daemon-proxied (using `DaemonClient`). When a method is added to one but not the other, the library silently breaks for daemon-connected callers — the error manifests at runtime rather than at definition time. This has already happened in the codebase: `find_text` and `raw_lines` were added to `CarbonylBrowser` and required corresponding additions to both `DaemonClient` and `_dispatch`.

**Acceptance Criteria**:
- [ ] A checklist exists (in CONTRIBUTING or code comments) enumerating the three locations that must be updated for any new browser command: (1) `CarbonylBrowser`, (2) `DaemonClient`, (3) `_BrowserServer._dispatch()`.
- [ ] The pattern `if self._daemon_client: return self._daemon_client.<method>(...)` is present in every `CarbonylBrowser` method that operates on the browser state.
- [ ] A test (manual or automated) exercises each public method in daemon-connected mode and verifies the result matches direct-mode output.

**Current Status**: Partially Met — the dispatch pattern is consistently followed for all existing methods. However, there is no documented checklist or automated test that enforces the three-way symmetry for new additions. The risk is realized silently at PR time.

---

## NFR-014: All Significant Actions Logged to stderr with [carbonyl] Prefix

**Category**: Observability

**Statement**: Every significant automation action (browser spawn, daemon start/stop, navigation, client connect/disconnect, error conditions) MUST be logged to stderr using the `log()` function, which prepends `[carbonyl]` to every message. Debug output MUST NOT go to stdout, which is reserved for page content.

**Rationale**: Automation scripts are frequently run as subprocesses by agent frameworks or CI pipelines. These frameworks capture stdout as the result and stderr as diagnostic output. Mixing log lines with page text on stdout corrupts the content and makes page parsing unreliable. The `[carbonyl]` prefix allows consumers to filter or grep log lines precisely.

**Acceptance Criteria**:
- [ ] `log()` is defined as `print(f"[carbonyl] {msg}", file=sys.stderr, flush=True)` and is the only channel for diagnostic output.
- [ ] No `print()` call in `browser.py`, `daemon.py`, or `session.py` writes diagnostic output to stdout.
- [ ] CLI `main()` functions in each module may write user-facing output (session lists, status tables) to stdout; this is not considered a violation.
- [ ] Daemon handler errors include the command name that failed (e.g., `"daemon: handler error: {exc}"` in `_BrowserHandler.handle()`).

**Current Status**: Partially Met — `log()` is used consistently for browser and daemon events. `session.py` uses `print()` for all output (CLI output to stdout is appropriate), but some session-level errors (e.g., failed metadata updates) are logged via `log()` in `daemon.py`. The daemon's `_dispatch` returns structured `{"ok": False, "error": str(exc)}` responses but does not always include the command name in the error message body.

---

## Summary Table

| NFR ID  | Title                                              | Category        | Priority | Status           |
|---------|----------------------------------------------------|-----------------|----------|------------------|
| NFR-001 | drain() Completes Within Bounded Time Window       | Performance     | High     | Met              |
| NFR-002 | find_text() Under 100 ms on Full Screen            | Performance     | High     | Met              |
| NFR-003 | Daemon RPC Round-Trip Latency                      | Performance     | Medium   | Met              |
| NFR-004 | Daemon Survives Client Disconnect                  | Reliability     | Critical | Met              |
| NFR-005 | Session Profile Not Corrupted on SIGKILL           | Reliability     | High     | Met              |
| NFR-006 | Graceful Recovery When Carbonyl Process Dies       | Reliability     | High     | Partially Met    |
| NFR-007 | Unix Socket Access Control                         | Security        | High     | Not Met          |
| NFR-008 | Credential Files Readable Only by Owner            | Security        | High     | Not Met          |
| NFR-009 | MFA Code Delivery via /tmp Secured                 | Security        | Medium   | N/A              |
| NFR-010 | Linux x86_64 Primary; arm64 Secondary              | Compatibility   | High     | Partially Met    |
| NFR-011 | Python 3.11 Minimum Version                        | Compatibility   | High     | Partially Met    |
| NFR-012 | 1-Indexed Coordinate Convention Enforced           | Maintainability | High     | Met              |
| NFR-013 | New Commands Mirrored in Browser and Daemon        | Maintainability | High     | Partially Met    |
| NFR-014 | Significant Actions Logged to stderr               | Observability   | Medium   | Partially Met    |

---

## Open Issues

1. **NFR-007 / NFR-008 (Security — file permissions)**: Neither socket file permissions nor profile directory permissions are explicitly set by code. This is the highest-priority gap. Both issues can be resolved with targeted `os.chmod` or `os.makedirs(mode=...)` calls at creation time.

2. **NFR-006 (Reliability — process death)**: There is no structured error type for "browser process died." Callers currently receive raw `pexpect.EOF` or `RuntimeError` with varying messages. A dedicated `CarbonylBrowserDead` exception would allow caller-side retry logic.

3. **NFR-011 (Compatibility — Python version)**: `python_requires` should be added to a `pyproject.toml` or `setup.cfg`. Until then, users on Python 3.10 will encounter silent runtime failures with `X | Y` annotations.

4. **NFR-013 (Maintainability — three-way symmetry)**: A code comment block in `daemon.py` above `_dispatch` enumerating the three locations to update would cost one minute to add and prevent the silent API gap pattern from recurring.
