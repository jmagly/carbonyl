# ADR-001: Language Architecture — Rust Core + PyO3 Python Bindings + gRPC

**Date:** 2026-04-02
**Status:** APPROVED
**Deciders:** Carbonyl core team

---

## Status

APPROVED

---

## Context

Carbonyl is a Chromium-based terminal browser being evolved into a general-purpose agent browser runtime. The existing codebase consists of approximately 3,154 lines of Rust handling terminal rendering and Chromium FFI, plus approximately 1,500 lines of Python automation built on pexpect and pyte.

The evolution to an agent browser runtime requires four new architectural layers:

- **Control API** — structured command surface replacing ad-hoc terminal scraping
- **Session Manager** — lifecycle, pooling, isolation, hibernation
- **Presence Layer** — timing humanization, identity management, fingerprint coherence
- **Observation Engine** — fused multi-channel capture (a11y tree, screenshots, DOM, network, console)

Two constraints shape the language decision above all others:

1. The primary consumer of the runtime is **matric-test** (TypeScript). The runtime must be callable from TypeScript without requiring a Python process in the loop.
2. The AI agent ecosystem — LangChain, CrewAI, AutoGen, DSPy, and the long tail of agent frameworks — is **overwhelmingly Python**. Any integration story that is not `pip install` is a friction wall.

These two constraints point in different directions, which is precisely why the language architecture decision requires an explicit record.

### Timing Precision Requirement

The Presence Layer must generate humanized timing at microsecond resolution — keystroke inter-arrival jitter, mouse Bezier trajectories, dwell distributions. Python's asyncio event loop has approximately 1 ms scheduling resolution. This makes Python unsuitable as the runtime for the Presence Layer, regardless of ecosystem alignment.

### Current Code Inventory

| Layer | Language | Lines | Notes |
|-------|----------|-------|-------|
| Terminal rendering pipeline | Rust | ~1,800 | Quadrant binarization, ANSI output |
| Input handling | Rust | ~600 | ANSI/CSI/SGR parser, keyboard, mouse |
| Chromium FFI bridge | Rust | ~400 | `extern "C"` rendering and input dispatch |
| Frame sync | Rust | ~200 | 60 FPS deadline-based |
| Navigation UI + CLI | Rust | ~150 | URL bar, flags |
| Python automation | Python | ~1,500 | pexpect+pyte, sessions, daemon, screen analysis |

---

## Options Evaluated

### Option A: 100% Rust

Rewrite the Python automation layer in Rust. All new layers implemented in Rust. No polyglot boundary.

**Pros:**
- Single language, single toolchain
- Maximum performance, no FFI overhead
- Compile-time session isolation safety via the type system
- No runtime impedance mismatch

**Cons:**
- The AI ecosystem is Python. There are no Rust libraries in LangChain's tool registry, CrewAI's agent scaffolding, or AutoGen's plugin surface. Any team reaching for Carbonyl from an AI framework will require a subprocess bridge or a network API anyway.
- This option defers the Python question rather than resolving it, and arrives at the same FFI work as Option C after additional iteration.

**Score: 3.20 / 5**

---

### Option B: Rust Core + Python Control Layer

Keep Rust for low-level rendering and FFI. Implement the Control API, Session Manager, Presence Layer, and Observation Engine in Python.

**Pros:**
- Python AI ecosystem alignment
- Fast iteration on control logic
- Lower onboarding cost for Python-fluent contributors

**Cons:**
- Two runtimes in the same process create memory and lifecycle management complexity.
- The GIL limits true concurrency. Multi-session management with concurrent observations per session saturates a single-threaded Python runtime.
- Presence Layer timing humanization requires microsecond precision. Python's event loop resolution (~1 ms) makes this impossible without resorting to native extensions — arriving at Option C by a longer path.
- Session isolation becomes a convention enforced by application code rather than a type-system guarantee.
- Logic duplication risk: session state tracked in both Rust (Chromium process handles) and Python (session objects) creates divergence surface.

**Score: 3.35 / 5**

---

### Option C: Rust Core + PyO3 Python Bindings + gRPC (CHOSEN)

Implement all runtime logic in Rust. Expose two calling surfaces:

- **PyO3 bindings** — in-process Python access, `pip install carbonyl`, zero network overhead
- **gRPC server (tonic)** — language-agnostic networked access for TypeScript, Go, Java, and any other consumer

```
Mode 1 (in-process):   Python → PyO3 → Rust runtime → Chromium
Mode 2 (networked):    Any language → gRPC → Rust runtime → Chromium
```

**Pros:**
- Single source of truth. All session logic, timing, and observation fusion live in Rust. There is no dual-implementation drift risk.
- `pip install carbonyl` is achievable via maturin. The Python developer experience is identical to polars, pydantic-core, ruff, or tokenizers — all of which use this exact pattern.
- gRPC provides first-class TypeScript access (the primary matric-test consumer) via generated clients from the protobuf schema. Go and Java get the same with no additional work.
- Proven at scale: the PyO3 + maturin pattern is established across the Python data and ML ecosystem.
- Presence Layer timing runs entirely in Tokio, achieving nanosecond-range scheduling resolution.

**Cons:**
- PyO3 learning curve for contributors unfamiliar with it: estimated 2–3 weeks to productive fluency.
- pyo3-asyncio introduces complexity at the Tokio/asyncio boundary, particularly around cancellation semantics.
- Two FFI boundaries exist in the call chain: Python → PyO3 → Rust, and separately Rust → Chromium FFI. These are independent and do not compound, but they require distinct expertise.

**Score: 3.85 / 5**

---

## Decision

**Option C is adopted: Rust core + PyO3 Python bindings + gRPC.**

The decisive factor is where the logic lives.

Session management, presence timing, and observation fusion require correctness guarantees that the Rust type system provides and Python cannot — session isolation via ownership, timing precision via Tokio, concurrent observation via async tasks without GIL contention. These must live in Rust.

Python is a calling convention, not a runtime. PyO3 makes it a thin calling convention: no separate process, no serialization overhead, direct memory access to Rust objects from Python. The `pip install` experience for AI framework integrators is preserved.

gRPC solves the polyglot problem for every non-Python consumer. TypeScript (matric-test), Go, Java, and any future consumer get generated clients from the protobuf schema at no additional design cost.

---

## Consequences

### Positive

- The Rust type system enforces session isolation at compile time across all consumers.
- Tokio provides microsecond-resolution scheduling for the Presence Layer — a hard requirement that Python cannot meet.
- A single protobuf schema defines the complete Control API surface. Changes propagate to all language clients via codegen.
- Python AI framework integration (`pip install carbonyl`, then `from carbonyl import Session`) is first-class and requires no subprocess management by the caller.
- matric-test gets a typed TypeScript gRPC client generated from the same schema.

### Negative

- PyO3 and pyo3-asyncio add build complexity. The Cargo.toml dependency graph grows. Contributors need familiarity with both Rust async patterns and PyO3's GIL acquisition model.
- maturin is a separate build tool from Cargo. Producing a Python wheel requires a distinct build pipeline alongside the existing cargo build.
- Two FFI boundaries (Python → PyO3 → Rust, and Rust → Chromium FFI) must be maintained independently.

### Neutral

- The existing Chromium FFI layer is unchanged. The new gRPC and PyO3 surfaces sit above it.
- The Python automation layer (browser.py, daemon.py, session.py, screen_inspector.py) is preserved and continues to function throughout migration. Deprecation is scheduled for Phase 7, not Phase 0.

---

## Implementation Phases

| Phase | Weeks | Deliverable |
|-------|-------|-------------|
| 1 | 1–4 | Rust foundation: tonic gRPC server, session manager skeleton, protobuf schema |
| 2 | 5–8 | Presence Layer, Observation Engine, Rust test suite |
| 3 | 9–12 | PyO3 bindings, maturin build pipeline, Python SDK |
| 4 | 13–16 | SDK polish, LangChain integration, TypeScript gRPC client for matric-test |

---

## Backtracking Triggers

These conditions warrant revisiting this decision before Phase 3:

1. **PyO3 async bridging proves unreliable** (persistent cancellation bugs, memory unsafety under load): fall back to gRPC-only with a thin Python subprocess wrapper. The gRPC server is built in Phase 1 and is always present; PyO3 becomes additive, not load-bearing.

2. **Chromium distribution makes `pip install` impractical** (wheel size, binary distribution policy): adopt a Docker-first deployment model. The gRPC API is network-accessible by design; callers connect to a sidecar container rather than importing a wheel.

3. **AI ecosystem shifts to TypeScript as the primary agent framework language**: gRPC becomes the primary integration surface. PyO3 bindings become a lower priority. The architecture does not change; only resourcing priority shifts.

---

## References

- [polars](https://github.com/pola-rs/polars) — PyO3 + maturin at production scale
- [pydantic-core](https://github.com/pydantic/pydantic-core) — Rust validation engine with Python bindings
- [tokenizers](https://github.com/huggingface/tokenizers) — HuggingFace's PyO3 pattern
- [tonic](https://github.com/hyperspace-rs/tonic) — Rust gRPC implementation
- Carbonyl migration plan: `docs/migration-plan.md`
