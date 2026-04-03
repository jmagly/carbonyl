# Project Intake Form — Carbonyl Automation Layer

**Document Type**: Brownfield System Documentation (New Component)
**Generated**: 2026-04-02
**Component**: `automation/` — Python automation layer over Carbonyl
**Parent Intake**: [`project-intake.md`](./project-intake.md) (base Carbonyl browser)

---

## Metadata

- **Component name**: Carbonyl Automation Layer
- **Repository**: `git@git.integrolabs.net:roctinam/carbonyl.git` (origin)
- **Component path**: `automation/` within the carbonyl repo
- **Language**: Python 3.11+
- **Version**: No tagged release; built and used as a local module
- **License**: Inherits BSD-3-Clause from parent repo
- **Stakeholders**:
  - Joseph Magly (roctinam) — primary developer and sole current operator
  - LLM agents consuming the automation API for web task execution

---

## System Overview

**Purpose**: The automation layer exposes Carbonyl's terminal-rendered Chromium browser as a programmable, bot-detection-resistant web automation platform. It provides four interlocking capabilities: persistent named browser sessions (cookies and JS state survive restarts), coordinate-precise terminal interaction (keyboard, click, mouse movement), a persistent daemon process reachable over a Unix socket, and a screen inspection toolkit oriented toward LLM-agent use.

**Current Status**: Functional, brownfield. Built in a single development session; all four modules are working. No automated tests, no packaging, no versioning beyond the parent repo's git history.

**Platforms Supported**: Linux (amd64). Requires a PTY, so native Linux only — not WSL without a PTY wrapper, not macOS without Carbonyl binary cross-compilation.

---

## Problem Statement and Outcomes

**Problem Statement**

Automating modern web applications via headless Chromium faces three compounding obstacles:

1. **Bot detection at the server side**: Akamai Bot Manager and similar systems fingerprint the JA3 TLS handshake, HTTP/2 SETTINGS frames, the `navigator.webdriver` flag, and the `User-Agent` header. Stock headless Chromium trips all four signals simultaneously.

2. **Session continuity**: Standard headless scripts re-initialize the browser per run, losing cookies and localStorage. Sites requiring authenticated sessions force a fresh login on every script execution.

3. **Agent-hostile screen access**: Raw ANSI/VT100 output from Carbonyl is not directly usable by an LLM agent. Converting it to usable coordinates, structured text, and annotated snippets requires a translation layer.

**Target Personas**

| Persona | Description | Primary Need |
|---------|-------------|--------------|
| Joseph Magly (developer/operator) | Writes automation scripts against specific sites | Full API access, session management, daemon control |
| LLM agent | Executes browser sub-tasks (navigate, find, click, read) | Structured text output, annotated coordinates, stable click API |

**Success Metrics**

- Bot detection bypass: Automation scripts successfully interact with Akamai-protected sites without triggering blocks
- Session persistence: A script can reconnect to a named session and resume from an authenticated state without re-login
- Click accuracy: `find_text()` + `click()` coordinates produce the intended DOM event on the target element
- Agent legibility: `annotate()` and `render_grid()` output is sufficient for an LLM to identify and act on UI elements without seeing raw ANSI bytes

---

## Current Scope and Features

### Feature Table

| Feature | Module | Key API | Status |
|---------|--------|---------|--------|
| Spawn Carbonyl in a PTY | `browser.py` | `CarbonylBrowser.open(url)` | Working |
| Local binary auto-detection | `browser.py` | `_local_binary()` | Working |
| Docker fallback | `browser.py` | `open()` fallback branch | Working |
| Keyboard input | `browser.py` | `send(text)`, `send_key(key)` | Working |
| Left-click (SGR mouse) | `browser.py` | `click(col, row)` | Working |
| Mouse move (entropy) | `browser.py` | `mouse_move(col, row)`, `mouse_path(points)` | Working |
| Screen drain / buffering | `browser.py` | `drain(seconds)` | Working |
| URL bar navigation | `browser.py` | `navigate(url)` | Working |
| Raw screen buffer | `browser.py` | `raw_lines()` | Working |
| Filtered readable text | `browser.py` | `page_text()` | Working |
| Text search (1-indexed) | `browser.py` | `find_text(text)` | Working |
| Click by text | `browser.py` | `click_on(text)`, `click_text(text)` | Working |
| Click by text + row | `browser.py` | `click_at_row(text, row)` | Working |
| Screen inspector access | `browser.py` | `inspector()` | Working |
| Firefox UA spoofing | `browser.py` | `_HEADLESS_FLAGS` | Working |
| HTTP/2 disable | `browser.py` | `--disable-http2` flag | Working |
| AutomationControlled disable | `browser.py` | `--disable-blink-features` flag | Working |
| Persistent browser daemon | `daemon.py` | `start_daemon(session, url)` | Working |
| Unix socket JSON-RPC server | `daemon.py` | `_BrowserServer` / `_BrowserHandler` | Working |
| Daemon client proxy | `daemon.py` | `DaemonClient` | Working |
| Interactive REPL (attach) | `daemon.py` | `daemon attach <session>` | Working |
| Named session creation | `session.py` | `SessionManager.create(name)` | Working |
| Session fork | `session.py` | `SessionManager.fork(src, dst)` | Working |
| Session snapshot | `session.py` | `SessionManager.snapshot(name, tag)` | Working |
| Session restore | `session.py` | `SessionManager.restore(name, tag)` | Working |
| Live process detection | `session.py` | `SessionManager.is_live(name)` | Working |
| Stale lock cleanup | `session.py` | `SessionManager.clean_stale_lock(name)` | Working |
| Coordinate grid rendering | `screen_inspector.py` | `render_grid(marks, regions)` | Working |
| LLM annotation output | `screen_inspector.py` | `annotate(marks, context_rows)` | Working |
| Crosshair view | `screen_inspector.py` | `crosshair(col, row, radius)` | Working |
| Calibration dot map | `screen_inspector.py` | `dot_map(step_col, step_row)` | Working |
| Region summarization | `screen_inspector.py` | `summarise_region(...)` | Working |
| Text search in inspector | `screen_inspector.py` | `find(text)` | Working |

### What Is Explicitly Out of Scope

- JavaScript injection or DevTools Protocol (CDP) — all interaction is via terminal I/O
- Page content extraction via DOM parsing — screen buffer is the only data source
- Screenshot capture — output is ANSI text, not images
- Multi-browser parallelism within a single daemon — one browser per daemon process
- Windows or macOS support — PTY-dependent, Linux only

---

## Architecture

### Component Map

```
┌─────────────────────────────────────────────────────────────────┐
│  Caller (Python script or LLM agent)                            │
└────────┬───────────────────────────────────────────┬────────────┘
         │ direct import                              │ Unix socket
         │                                           │ (JSON-RPC)
┌────────▼──────────────────┐           ┌────────────▼───────────┐
│  CarbonylBrowser           │           │  DaemonClient           │
│  (browser.py)              │           │  (daemon.py)            │
│                            │           │  thin proxy, mirrors    │
│  - pexpect PTY spawn       │           │  CarbonylBrowser API    │
│  - pyte screen emulation   │           └────────────┬───────────┘
│  - SGR mouse protocol      │                        │
│  - page_text / find_text   │           ┌────────────▼───────────┐
│  - inspector() factory     │           │  _BrowserServer         │
└────────┬──────────────────┘           │  (daemon.py)            │
         │                              │  ThreadingUnixStream     │
         │ --user-data-dir              │  dispatches to           │
┌────────▼──────────────────┐           │  CarbonylBrowser held   │
│  SessionManager            │           │  in daemon process      │
│  (session.py)              │           └────────────────────────┘
│                            │
│  ~/.local/share/carbonyl/  │           ┌────────────────────────┐
│  sessions/<name>/          │           │  ScreenInspector        │
│  ├── session.json          │           │  (screen_inspector.py)  │
│  └── profile/              │           │                         │
│      (Chromium user-data)  │           │  wraps raw_lines()      │
│                            │           │  snapshot               │
│  snapshot, fork, restore   │           │  render_grid / annotate │
└────────────────────────────┘           └────────────────────────┘
                          │
         ┌────────────────▼──────────────────────────────────────┐
         │  Carbonyl binary (Rust/Chromium)                        │
         │  local: build/pre-built/<triple>/carbonyl               │
         │  fallback: docker run fathyb/carbonyl                   │
         └───────────────────────────────────────────────────────┘
```

### Data Flow — Direct Mode

1. Caller instantiates `CarbonylBrowser(session="my-session")`
2. `open(url)` checks for a live daemon via `is_daemon_live()` — if none, spawns the Carbonyl binary in a pexpect PTY
3. `SessionManager` provides or creates the Chromium `--user-data-dir` path, cleaning any stale `SingletonLock`
4. Caller drives interaction: `drain()` feeds PTY bytes into `pyte.ByteStream` → `pyte.Screen`
5. `find_text()` scans `pyte.Screen.buffer` for string matches, returning 1-indexed `{col, row, end_col}`
6. `click(col, row)` sends SGR escape `\x1b[<0;{col};{row}M` (press) and `m` (release) into the PTY
7. `mouse_move(col, row)` sends SGR button code 32 (`\x1b[<32;{col};{row}M`) for entropy events
8. `page_text()` passes the current `pyte.Screen` through `extract_text()` which filters block/quad Unicode and collapses whitespace
9. `inspector()` returns a `ScreenInspector` initialized from `raw_lines()` for coordinate visualization

### Data Flow — Daemon Mode

1. `start_daemon(session, url)` forks a child process, calls `os.setsid()`, redirects stdio to `/dev/null`
2. Child runs `_run_daemon()`: spawns `CarbonylBrowser`, listens on Unix socket at `~/.local/share/carbonyl/sessions/<name>.sock`
3. Caller connects via `DaemonClient`, sends newline-delimited JSON commands
4. `_BrowserHandler` dispatches each command to the held `CarbonylBrowser` instance in the daemon process
5. Session metadata (`session.json`) is updated with the daemon PID and socket path
6. `close` command triggers `server.shutdown_requested = True` → watcher thread calls `server.shutdown()` → `atexit` cleanup removes the socket file and calls `browser.close()` with a graceful SIGTERM

### Integration Points

| Integration | Purpose | Mechanism |
|-------------|---------|-----------|
| Carbonyl binary | Full browser rendering and input | pexpect PTY spawn, ANSI I/O |
| Docker image (`fathyb/carbonyl`) | Fallback when no local binary | `docker run --rm -it` via pexpect |
| pyte | VT100/ANSI terminal emulation | `pyte.Screen` + `pyte.ByteStream` |
| pexpect | PTY management, nonblocking read | `pexpect.spawn` with `dimensions` |
| Chromium SingletonLock | Live-process detection | symlink read + `os.kill(pid, 0)` |
| Unix domain socket | Daemon IPC | `socketserver.ThreadingUnixStreamServer` |

### Coordinate System

All public APIs use **1-indexed (col, row)** coordinates throughout:
- `find_text()` returns `col` as the 1-indexed start column
- `click(col, row)` passes `col` and `row` directly into the SGR escape sequence
- `ScreenInspector.find()`, `render_grid(marks=...)`, `annotate(marks=...)` all use 1-indexed tuples
- Internal pyte buffer is 0-indexed; all consumer-facing code applies `+1` offsets at the boundary

### Terminal Dimensions

Default rendering window: **220 columns x 50 rows**. These dimensions are passed as `pexpect.spawn(dimensions=(rows, cols))` and determine the coordinate space for all click and find operations.

---

## Scale and Performance

**Current Scale**: Single-user, single-session tool. Not a service. No multi-tenancy, no request routing, no horizontal scaling concern.

**Timing Characteristics**:
- `drain(seconds)`: Blocking read loop with 0.1s `pexpect` timeout per chunk; suitable for `seconds` values of 3–15 for typical page loads
- `find_text()`: Linear scan of `pyte.Screen.buffer` — O(rows × cols) per call; at 220×50 this is negligible
- Daemon socket RPC: Local Unix socket round-trip; no meaningful latency beyond the operation itself (e.g., `drain` adds its duration)
- `page_text()` extraction: Single pass with regex; at screen dimensions of 11,000 characters, sub-millisecond

**Known Timing Constraints**:
- Page load waits are caller-controlled via `drain(seconds)` — no async/event-driven page-load detection exists
- Daemon `drain` extends socket timeout by 10s beyond the drain duration to prevent premature socket closure

**No performance targets are defined**. The system is used interactively and in scripted flows where human-scale latency (seconds) is acceptable.

---

## Security and Compliance

### Bot Detection Bypass

The automation layer actively circumvents bot detection mechanisms. This is the system's core security-relevant design area:

| Detection Signal | Mechanism Defeated | Implementation |
|-----------------|-------------------|----------------|
| `navigator.webdriver = true` | `--disable-blink-features=AutomationControlled` Chromium flag | `_HEADLESS_FLAGS` in `browser.py` |
| Chromium User-Agent in HTTP headers and JS | Firefox 122 UA string spoof via `--user-agent` | `_HEADLESS_FLAGS` in `browser.py` |
| HTTP/2 SETTINGS frame fingerprint (Akamai secondary signal) | `--disable-http2` forces HTTP/1.1 | `_HEADLESS_FLAGS` in `browser.py` |
| Absence of `mousemove` DOM events (bot entropy check) | SGR button code 32 produces real `mousemove` events | `mouse_move()`, `mouse_path()` in `browser.py` |

**Residual fingerprint risk**: JA3 TLS fingerprint is Chromium's, not Firefox's. This remains a detectable signal on sites using TLS fingerprinting independent of HTTP/2. The HTTP/2 disable removes one major Akamai secondary signal but does not fully convert the TLS handshake to a Firefox profile.

### Credential and Session Storage

- Session profiles (cookies, localStorage, IndexedDB) are stored at `~/.local/share/carbonyl/sessions/<name>/profile/` as plain directories
- No encryption at rest
- No secrets stored in code — the session profile is a standard Chromium user-data-dir
- Session directory is readable by the user running the process; no additional access controls

### Chromium Sandbox

- The `--no-sandbox` flag is passed in every invocation via `_HEADLESS_FLAGS`
- This is a deliberate choice inherited from the base Carbonyl Docker setup
- Implication: Chromium runs without OS-level renderer sandboxing, which increases exposure if a malicious page exploits a renderer vulnerability

### Data Classification

No PII is handled by the automation layer itself. Session profiles may accumulate PII depending on which sites are browsed (account data, form fills, cookies). That data is the operator's responsibility.

### Compliance

No GDPR, HIPAA, PCI-DSS, or SOC 2 requirements identified for the automation layer itself. Compliance obligations depend entirely on the sites targeted and the data handled by the operator.

---

## Team and Operations

**Team**: Joseph Magly (sole developer and operator). No other contributors.

**Process Maturity**:
- Version control: Git (tracked in parent repo)
- Testing: None — no unit tests, no integration tests, no CI coverage
- Documentation: Inline docstrings throughout; no external docs or runbooks
- Packaging: Not packaged; imported directly as a module or run as a script

**Operational Characteristics**:
- No server to monitor — all processes are ephemeral or daemon'd locally
- Daemon PID and socket path are written to `session.json` on start; no central process registry
- Dead daemons clean up their socket file via `atexit` handler; stale sockets detected and removed by `is_daemon_live()` on next connection attempt
- Logging: `log()` writes to `stderr` prefixed with `[carbonyl]`; no log aggregation, no rotation

**Runbooks**: None. Operational knowledge is in the code and docstrings.

---

## Dependencies and Infrastructure

### Python Runtime Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `pexpect` | 4.9.0 | PTY spawn and nonblocking read |
| `pyte` | 0.8.2 | VT100/ANSI terminal emulation (screen buffer) |

Both are pure Python with no native extensions beyond `pexpect`'s use of `pty` from the standard library.

### Standard Library Dependencies

`os`, `socket`, `socketserver`, `threading`, `signal`, `json`, `re`, `shutil`, `time`, `pathlib`, `unicodedata`, `subprocess`, `importlib.util`

### System Dependencies

| Dependency | Purpose | Required By |
|------------|---------|------------|
| Carbonyl local binary | Browser rendering | Direct mode (preferred path) |
| Docker + `fathyb/carbonyl` image | Browser rendering fallback | Docker fallback path |
| `scripts/platform-triple.sh` | Detect binary arch triple | `_local_binary()` in `browser.py` |
| Linux PTY (`/dev/ptmx`) | Terminal emulation | pexpect |
| Unix domain sockets | Daemon IPC | `daemon.py` |

### Session Storage

Default location: `~/.local/share/carbonyl/sessions/`
Override: `$CARBONYL_SESSION_DIR` environment variable

Layout per session:
```
<store>/<session-name>/
├── session.json          # metadata (id, name, created_at, tags, daemon_pid, daemon_socket)
└── profile/              # Chromium --user-data-dir (cookies, localStorage, IndexedDB, etc.)

<store>/<session-name>--snap--<tag>/    # snapshots follow same structure
<store>/<session-name>.sock             # Unix socket (present only while daemon is live)
```

### Infrastructure

No external infrastructure. All components run locally on the development machine. No network services are exposed (the Unix socket is filesystem-local). No cloud dependencies.

---

## Known Issues and Technical Debt

| Issue | Severity | Detail |
|-------|----------|--------|
| No automated tests | High | Zero test coverage across all four modules. Regressions in coordinate math, daemon lifecycle, or session management will be silent. |
| Stale `find_text` on daemon reconnect | Medium | `find_text()` in direct mode scans `pyte.Screen.buffer`; in daemon mode it re-implements the scan in `_BrowserHandler._dispatch`. These are two separate implementations that could diverge. |
| `drain()` is time-based, not event-based | Medium | No mechanism to detect page load completion. Callers must guess appropriate wait durations; too short misses content, too long wastes time. |
| `navigate()` uses fixed column offsets | Medium | The URL bar click at `col=12, row=1` and the 250-backspace clear are based on observed Carbonyl nav bar layout. Upstream Carbonyl changes to UI chrome could silently break navigation. |
| `--no-sandbox` in every invocation | Medium | Chromium sandbox disabled for all sessions, including non-Docker local binary. This is broader than the Docker-only intent in the base project. |
| No daemon restart on crash | Medium | If a daemon process exits unexpectedly, the socket file may not be cleaned up immediately. Callers will get `ConnectionRefusedError`; `is_daemon_live()` will clean the socket on next check, but the session state is lost. |
| Single-client daemon | Low | `_BrowserServer` uses `ThreadingUnixStreamServer` but the browser instance is not thread-safe. Concurrent RPC commands from multiple clients could interleave browser operations. Current usage is single-client but this is not enforced. |
| `reconnect()` implementation | Low | `CarbonylBrowser.reconnect()` calls `self.open("about:blank")` and relies on a side-effectful double-negation `not not self.open(...)` which returns `None`, always evaluating to `False`. The method does not reliably report reconnect success. |
| Block-character filter is heuristic | Low | `extract_text()` filters Unicode ranges for Box Drawing, Block Elements, and Geometric Shapes. Some legitimate page content in those ranges (rare) would be stripped. |
| JA3 TLS fingerprint not spoofed | Low | HTTP/2 disable removes one Akamai signal but the underlying TLS handshake still identifies Chromium. Sites using TLS fingerprinting (not HTTP/2 fingerprinting) remain able to detect the browser. |

---

## Why This SDLC Now?

**Context**: The automation layer was built as a focused engineering session to solve a concrete problem: automating Akamai-protected web applications without being blocked, while maintaining session state across script runs, and producing output usable by LLM agents. All four modules are functional and in active use.

This intake documents the as-built state before any broader development effort — capturing design decisions, technical debt, and scope boundaries while they are fresh, so future work has a clear baseline rather than inferring intent from code alone.

**Immediate Risks Motivating Documentation**:
- No tests means any refactor carries silent regression risk
- The daemon lifecycle and socket cleanup paths are the most complex failure modes and are not yet exercised by any test harness
- Coordinate system conventions (1-indexed throughout) are a correctness invariant that is easy to break silently during extension

**Goals for Future Work**:
1. Integration test harness against a known stable site (e.g., DuckDuckGo) covering the core `open → drain → find_text → click → drain → page_text` lifecycle
2. Daemon crash recovery — detect dead daemon and restart with session state intact
3. Event-driven page-load detection to replace fixed `drain(seconds)` waits
4. Single-client enforcement (or explicit thread-safety) in the daemon server

---

## Attachments

- Parent intake (base Carbonyl browser): [`project-intake.md`](./project-intake.md)
- Solution profile: [`solution-profile.md`](./solution-profile.md)
- Option matrix: [`option-matrix.md`](./option-matrix.md)
- Automation source: `/mnt/dev-inbox/fathyb/carbonyl/automation/`
- Internal repo: `git@git.integrolabs.net:roctinam/carbonyl.git`
