# Carbonyl Migration Plan: MVP to Agent Browser Runtime

**Date:** 2026-04-02
**Status:** Active
**Language architecture:** See `docs/adr-001-language-architecture.md`

---

## Overview

This document describes the phased migration of Carbonyl from its current MVP state — a terminal browser with a Python automation layer — to a general-purpose agent browser runtime with a gRPC Control API, PyO3 Python bindings, a Session Manager, an Observation Engine, and a Presence Layer.

The migration spans approximately 30 weeks across 8 phases (Phase 0 through Phase 7). Each phase has a defined scope, clear entry and exit criteria, and an explicit statement of what existing functionality must remain intact.

---

## Current State

### Rust Runtime (~3,154 lines)

| Component | Description |
|-----------|-------------|
| Terminal rendering pipeline | Quadrant binarization, ANSI output generation |
| Input handling | ANSI/CSI/SGR parser, keyboard dispatch, mouse event routing |
| Chromium FFI bridge | `extern "C"` functions for rendering callbacks and input dispatch |
| Frame sync | 60 FPS deadline-based frame scheduling |
| Navigation UI | URL bar, back/forward controls |
| CLI | `--fps`, `--zoom`, `--debug`, `--bitmap` flags |

### Python Automation (~1,500+ lines)

| File | Description |
|------|-------------|
| `browser.py` | `CarbonylBrowser` class — spawns Carbonyl via pexpect, pyte screen parsing, text extraction, click/type/navigate methods, session support, daemon reconnection |
| `daemon.py` | Persistent browser daemon — Unix socket JSON-RPC, forked process management, start/stop/attach lifecycle |
| `session.py` | Session management — create, fork, snapshot, restore, destroy, named profiles via `--user-data-dir` |
| `screen_inspector.py` | Screen analysis — grid rendering, coordinate visualization, text search, region summary |

### Build System

- Cargo for Rust (`libcarbonyl.so`)
- GN/Ninja for Chromium headless shell — pinned at `111.0.5511.1`
- 14 Chromium patches, 2 Skia patches, 1 WebRTC patch
- Docker build for reproducible Chromium compilation
- `build-local.sh` downloads pre-built runtime and builds Rust library (~10 seconds)
- npm package for distribution

### Test Coverage

Zero. There are no tests across any layer of the current codebase.

---

## Target State

| Component | Technology |
|-----------|-----------|
| Control API | gRPC (tonic) + WebSocket, replacing Unix socket JSON-RPC |
| Session Manager | Rust — pool, topology (shared/isolated), hibernation, resource ceilings |
| Observation Engine | Rust — fused multi-channel capture via CDP (a11y tree, screenshots, DOM, network, console) |
| Presence Layer | Rust + Tokio — timing humanization, identity management, fingerprint coherence |
| Streaming | Unified screencast + terminal + events; RTMP/SRT output via ffmpeg |
| CDP exposure | Alongside existing terminal I/O |
| Python bindings | PyO3 + maturin — `pip install carbonyl` |
| Multi-session | Shared Chromium process via CDP BrowserContext isolation |
| Test suite | Comprehensive — cargo tests for Rust, pytest for Python bindings |

---

## Migration Principles

1. **Never break what works.** The Python automation layer (browser.py, daemon.py, session.py, screen_inspector.py) remains functional throughout all phases. Callers using pexpect+pyte automation must not experience regressions.

2. **Build new layers alongside existing code, not instead of it.** The gRPC Control API coexists with the Unix socket JSON-RPC daemon. CDP coexists with terminal rendering. Replacement is scheduled; it is not performed preemptively.

3. **CDP first.** CDP access unblocks the Observation Engine, the Session Manager, and ultimately the PyO3 bindings. Phase 0 validates CDP connectivity before any new layer is built.

4. **Tests before features on all new code.** The existing codebase has zero tests. All new components are written test-first. No new component reaches Phase completion without a passing test suite.

5. **Deprecate, do not rip out.** The Python automation layer is eventually replaced by the PyO3 SDK and the gRPC Control API. Deprecation is announced in Phase 7. The files are kept in the repository for at least one release cycle as reference material.

---

## What to Keep

The following components are preserved and form the foundation for new layers:

| Component | Disposition |
|-----------|------------|
| All Rust code — terminal rendering, input handling, FFI bridge, frame sync | Kept as-is. This is the foundation. |
| `session.py` concepts — named sessions, fork, snapshot, restore | Concepts reimplemented in Rust Session Manager (Phase 3). Python file kept during transition. |
| `screen_inspector.py` concepts — text search, coordinate visualization | Useful for terminal stream analysis. Concepts carried into Observation Engine. Python file kept during transition. |
| `browser.py` bot-detection flags — UA spoofing, HTTP/2 disable, automation flag removal | Moved into Presence Layer identity profile management (Phase 4). |
| `daemon.py` Unix socket protocol | Kept as backward-compatible fallback throughout Phase 2 and Phase 3. |

---

## What Gets Replaced

| Current | Replacement | Phase |
|---------|------------|-------|
| pexpect+pyte terminal scraping | CDP programmatic access | 1 |
| Unix socket JSON-RPC (`daemon.py`) | gRPC Control API | 2 |
| Python session management (`session.py`) | Rust Session Manager | 3 |
| Manual `mouse_path()` trajectory generation | Presence Layer Bezier trajectory engine | 4 |
| Screen text extraction via pyte | CDP a11y tree + fused Observation Engine | 1 |

---

## Phased Plan

### Phase 0: Foundation (Weeks 1–2)

**Objective:** Establish test infrastructure and validate CDP connectivity. Zero risk to existing functionality.

**Scope:**
- Enable `--remote-debugging-port` on Carbonyl launch. Verify the flag passes through the CLI and the Chromium invocation.
- Verify that Playwright (TypeScript) can connect to the Carbonyl instance via CDP and execute basic navigation.
- Add `cargo test` infrastructure to the workspace. Identify pure functions suitable for unit testing.
- Write unit tests for: color conversion, quadrant binarization, xterm escape sequences, `screen_inspector.py` text search logic.
- Add pytest infrastructure for the Python automation layer. Write smoke tests that exercise the existing `CarbonylBrowser` class.

**Exit criteria:**
- `cargo test` runs and passes for all tested pure functions.
- `pytest` runs and passes for Python smoke tests.
- Playwright connects to Carbonyl via CDP and navigates to a URL.
- No regressions in existing terminal rendering or Python automation.

**Risk:** None. This phase adds test infrastructure and a debugging flag. No existing code path is modified.

---

### Phase 1: CDP + Observation Engine (Weeks 3–6)

**Objective:** Build the Observation Engine in Rust. Establish fused multi-channel observation as a first-class primitive.

**Scope:**
- Implement a CDP client in Rust that connects to the Chromium remote debugging endpoint.
- Implement fused observation capture: accessibility tree, screenshot, DOM snapshot, network events, console output — collected atomically within a single Rust async task.
- Implement state fingerprinting: derive a deterministic hash from the fused observation that identifies unique application states.
- Write a full `cargo test` suite for the Observation Engine.

**Coexistence:** The Python automation layer continues working via terminal throughout this phase. Two channels coexist: CDP (new Rust Observation Engine) and terminal scraping (existing pexpect+pyte). Neither interferes with the other.

**Exit criteria:**
- Observation Engine captures all five channels (a11y, screenshot, DOM, network, console) in a single atomic call.
- State fingerprinting produces stable hashes across repeated observations of the same page state.
- `cargo test` passes for the Observation Engine.
- Python automation layer smoke tests continue to pass.

---

### Phase 2: Control API (Weeks 7–10)

**Objective:** Replace the Unix socket JSON-RPC daemon with a typed gRPC Control API.

**Scope:**
- Define the protobuf schema covering: session management, action dispatch (navigate, click, type, scroll), observation retrieval, tab management.
- Implement the gRPC server in Rust using tonic.
- Implement session, action, observation, and tab endpoints.
- Write gRPC integration tests.
- Keep `daemon.py` and its Unix socket protocol running as a backward-compatible fallback.

**Exit criteria:**
- gRPC server starts and handles session create, action dispatch, and observation retrieval.
- Integration tests pass against a running Carbonyl instance.
- `daemon.py` Unix socket protocol continues to function without modification.
- A TypeScript gRPC client (generated from the protobuf schema) connects and executes a navigation action.

---

### Phase 3: Session Evolution (Weeks 11–14)

**Objective:** Implement the full Session Manager in Rust. Enable multi-session and flexible topology.

**Scope:**
- Multi-session support on a shared Chromium process via CDP `BrowserContext` isolation.
- Flexible topology: shared sessions (multiple agents read the same context), isolated sessions (independent BrowserContexts), multi-agent access control.
- Hibernation engine: extract portable session state to a JSON token via CDP, restore from token to a new BrowserContext.
- Resource ceiling enforcement per session (CPU, memory limits).
- Session lifecycle tests: create, fork, snapshot, restore, destroy.
- Hibernation round-trip tests: hibernate → serialize → restore → verify state.
- Topology scenario tests: concurrent agents on shared session, isolation verification between isolated sessions.

**Exit criteria:**
- Five concurrent sessions run on a single Carbonyl process without state leakage between isolated sessions.
- Hibernation round-trip passes: a session hibernated and restored arrives at the correct page state.
- Resource ceilings are enforced and tested.
- The `session.py` Python layer continues to function via terminal for backward compatibility.

---

### Phase 4: Presence Layer (Weeks 15–18)

**Objective:** Implement humanized timing and identity management for bot-detection evasion.

**Scope:**
- Timing humanization engine: keystroke inter-arrival jitter sampled from a configurable distribution, mouse movement via Bezier curves with realistic velocity profiles, dwell times before and after interactions.
- Identity profile management: User-Agent, viewport dimensions, timezone, language headers, HTTP/2 negotiation flags, automation flag removal. Carries forward the bot-detection flags from `browser.py`.
- Fingerprint coherence validation: verify that all identity signals are mutually consistent (e.g., UA string and navigator.userAgent agree, screen dimensions match viewport).

**Timing note:** All timing logic runs in Tokio. Python asyncio's ~1 ms event loop resolution is insufficient for the jitter distributions required here. This is a hard constraint, not a preference.

**Exit criteria:**
- Keystroke timing distribution tests pass: inter-arrival times match the configured distribution within statistical tolerance.
- Mouse trajectory tests pass: generated paths are smooth Bezier curves, velocity profiles within human range.
- Fingerprint coherence tests pass: no detectable internal inconsistencies across identity signals.
- All timing logic executes in Tokio, with no Python in the timing path.

---

### Phase 5: Streaming (Weeks 19–22)

**Objective:** Implement unified streaming of screencast, terminal output, and events.

**Scope:**
- CDP screencast integration: subscribe to `Page.screencastFrame`, forward frames to the unified stream.
- Terminal ANSI output forwarding: tap the existing terminal rendering pipeline and forward to the stream.
- Unified event stream: aggregate DOM events, network events, console output, and user actions into a single ordered stream.
- Watch server: gRPC streaming endpoint for clients that want a live event feed, plus a WebSocket bridge for browser-based observers.
- RTMP/SRT output via ffmpeg for external recording and monitoring.
- Stream correctness tests: verify frame ordering and no dropped events.
- Backpressure handling tests: verify the stream degrades gracefully under slow consumers.

**Exit criteria:**
- A gRPC streaming client receives live screencast frames and events.
- WebSocket observer connects and receives the same stream.
- RTMP output can be consumed by an external ffmpeg process.
- No regressions in terminal rendering or existing Python automation.

---

### Phase 6: PyO3 Python Bindings (Weeks 23–26)

**Objective:** Produce a `pip install carbonyl` Python package backed by the Rust runtime.

**Scope:**
- PyO3 wrappers for `Session`, `Observation`, and `Action` types.
- pyo3-asyncio bridge: expose Tokio futures as Python awaitables.
- maturin build pipeline: produce a platform wheel and verify installation from PyPI-compatible index.
- End-to-end test: `pip install carbonyl` in a clean virtual environment; run a browser session; receive a fused observation.
- pytest suite for binding correctness: verify all public API methods round-trip correctly across the PyO3 boundary.

**Call chain (in-process mode):**
```
Python caller
  → PyO3 binding
    → Rust Session Manager
      → Chromium FFI / CDP
```

**Exit criteria:**
- `pip install carbonyl` installs successfully on Linux x86_64.
- Python `async with Session() as s: obs = await s.observe()` executes and returns a valid `Observation` object.
- pytest suite passes for all binding methods.
- The gRPC Control API continues to function independently (PyO3 is additive).

---

### Phase 7: Deprecation and Polish (Weeks 27–30)

**Objective:** Deprecate the Python automation layer, ship documentation and integrations, performance tune.

**Scope:**
- Deprecate `browser.py` and `daemon.py`: add deprecation notices, keep files in repository as reference material for one release cycle, do not remove.
- Write user-facing documentation: quickstart guide, API reference, integration examples.
- LangChain tool wrapper: `CarbonylTool` implementing the LangChain `BaseTool` interface.
- TypeScript gRPC client for matric-test: generated from the protobuf schema, published as an npm package.
- Performance tuning: profile observation latency, gRPC throughput, PyO3 call overhead.
- Load testing: 10 concurrent sessions, sustained 5-minute run, measure memory and CPU ceilings.

**Exit criteria:**
- Deprecation notices present in `browser.py` and `daemon.py`.
- Quickstart guide covers: Docker launch, Python `pip install` path, TypeScript gRPC path.
- LangChain tool wrapper executes a navigation action from a LangChain agent.
- matric-test TypeScript client connects and runs a PRAV loop iteration.
- Load test passes at 10 concurrent sessions.

---

## Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|-----------|
| 1 | CDP + terminal rendering coexistence | Medium | High | Test in Phase 0 before any new layer is built. Chromium may not support both rendering modes simultaneously. If blocked, evaluate headless-first mode where terminal output is generated post-hoc from CDP screenshots. |
| 2 | PyO3 async bridging edge cases | Medium | Medium | pyo3-asyncio cancellation and exception propagation have known rough edges. Keep gRPC as an always-available fallback. If PyO3 async proves unreliable, the Python SDK wraps the gRPC client instead of the Rust runtime directly. |
| 3 | Chromium version lock at 111 | Low | Medium | Carbonyl is pinned at Chromium 111.0.5511.1 (2023). Some CDP domains and methods were introduced in later versions. Audit all CDP APIs required by the Observation Engine and Presence Layer against the Chromium 111 protocol definition before Phase 1. |
| 4 | Build complexity compounding | Low | Medium | tonic (gRPC) and maturin (PyO3) each add to an already complex build involving GN/Ninja and Cargo. Keep builds independent: `cargo build` produces the runtime binary and `libcarbonyl.so`; `maturin build` produces the Python wheel. They share source but have separate build entry points. |

---

## Dependency Map

```
Phase 0 (Foundation)
  └── Phase 1 (CDP + Observation)
        └── Phase 2 (Control API)
              ├── Phase 3 (Session Evolution)
              │     └── Phase 4 (Presence Layer)
              │           └── Phase 5 (Streaming)
              │                 └── Phase 6 (PyO3 Bindings)
              │                       └── Phase 7 (Deprecation + Polish)
              └── Phase 6 (PyO3 Bindings)  [can begin after Phase 2 provides stable API surface]
```

Phase 5 (Streaming) and Phase 6 (PyO3 Bindings) have no hard dependency on each other and can proceed in parallel if resources allow.

---

## References

- Language architecture decision: `docs/adr-001-language-architecture.md`
- matric-test PRAV loop: `git.integrolabs.net/roctinam/matric-test`
- Chromium 111 CDP protocol: `https://chromedevtools.github.io/devtools-protocol/`
- tonic gRPC framework: `https://github.com/hyperspace-rs/tonic`
- PyO3 documentation: `https://pyo3.rs`
- maturin build tool: `https://github.com/PyO3/maturin`
