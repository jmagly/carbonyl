# Carbonyl Development Guide

Practical guide for contributors and engineers joining the project.

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Rust (via rustup) | 1.75+ | Rust runtime library |
| Python | 3.10+ with venv | Automation layer |
| Docker | Any recent | Chromium builds only (rare) |
| protoc | Any recent | gRPC schema compilation |
| Node.js | 20+ | npm package (optional) |

Install Rust via [rustup.rs](https://rustup.rs). All other tools via system package manager or official installers.

---

## Quick Start

```bash
# Clone
git clone https://git.integrolabs.net/roctinam/carbonyl.git
cd carbonyl

# Python setup
python3 -m venv .venv
.venv/bin/pip install -r automation/requirements.txt

# Build local binary (downloads ~75MB Chromium runtime, builds Rust lib ~10s)
bash scripts/build-local.sh

# Smoke test
.venv/bin/python automation/browser.py search "test query"
```

---

## Repository Structure

```
carbonyl/
├── src/                   # Rust runtime (libcarbonyl.so)
│   ├── browser/           # Chromium FFI bridge (Rust + C++)
│   ├── cli/               # Command-line parsing
│   ├── gfx/               # Graphics primitives (color, point, rect, size)
│   ├── input/             # Terminal input (ANSI parser, keyboard, mouse, DCS)
│   ├── output/            # Terminal rendering (renderer, painter, cells, quadrant)
│   ├── ui/                # Browser chrome (navigation bar)
│   └── utils/             # Logging, helpers
├── automation/            # Python automation layer (browser, daemon, session, inspector)
├── chromium/              # Chromium source config, patches, .gclient
├── scripts/               # Build, patch, release scripts
├── build/                 # Build output (gitignored)
└── docs/                  # Architecture and specifications
```

### src/ — Rust runtime

The core library compiled to `libcarbonyl.so`. Organized by concern:

- `browser/` — FFI bridge between Rust and the Chromium C++ layer. Low-level, changes here are rare and high-risk.
- `cli/` — Argument parsing and entry points for the command-line binary.
- `gfx/` — Pure data types for color, points, rectangles, and sizes. No I/O.
- `input/` — All terminal input handling: ANSI escape sequence parsing, keyboard events, mouse events, DCS sequences.
- `output/` — Terminal rendering pipeline: renderer, painter, cell model, quadrant block character encoding.
- `ui/` — Browser chrome rendered into the terminal (URL bar, indicators).
- `utils/` — Logging macros and miscellaneous helpers shared across crates.

### automation/ — Python layer

Python wraps the Rust library (and eventually the gRPC API) for scripting and test automation. Key modules: `browser.py` (CLI entrypoint), `daemon.py` (process lifecycle), `session.py` (session state), `inspector.py` (screen analysis).

### chromium/ — Chromium integration

Contains the `.gclient` configuration, custom patches against Chromium source, and any build configuration files. Most contributors never touch this directory.

### scripts/ — Build and tooling

Shell scripts for common operations. Notable:
- `build-local.sh` — Local dev build (Rust only, downloads pre-built Chromium runtime)
- `docker-build.sh` — Full Chromium build inside Docker (slow, rare)
- `patches.sh` — Apply or save Chromium source patches

---

## Build Architecture

Carbonyl has a two-part build. Day-to-day development only requires rebuilding the Rust library.

| Component | Build command | Approximate time | When to rebuild |
|-----------|--------------|------------------|-----------------|
| Rust library (`libcarbonyl.so`) | `cargo build --release` | ~10 seconds | Any Rust code change |
| Chromium runtime (`headless_shell`) | `bash scripts/docker-build.sh` | 1-3 hours | Chromium version bump or patch changes (rare) |

The Chromium runtime is downloaded pre-built during `build-local.sh`. You only run `docker-build.sh` if you are changing Chromium patches or bumping the Chromium version.

---

## Development Workflow

### Rust changes

```bash
cargo build --release   # build the library
cargo test --lib        # run unit tests
cargo clippy            # lint
```

The compiled library lands in `build/`. `build-local.sh` places the Chromium runtime alongside it.

### Python changes

```bash
source .venv/bin/activate
pytest tests/                                                         # when tests exist
python automation/browser.py open https://example.com --wait 5        # manual test
```

### Adding new Rust modules

1. Create the file in the appropriate `src/` subdirectory.
2. Add `pub mod your_module;` in the parent module's `mod.rs` or `lib.rs`.
3. If the module exports FFI functions, annotate them with `#[no_mangle] pub extern "C"`.
4. Write tests in a `#[cfg(test)] mod tests { }` block at the bottom of the file.
5. Run `cargo test` and `cargo clippy` before committing.

### Chromium patches (rare)

Only needed when making changes to Chromium source — for most contributors this never comes up.

```bash
# Apply existing patches to the checked-out Chromium source
bash scripts/patches.sh apply

# Edit files under chromium/src/...

# Regenerate and save updated patch files
bash scripts/patches.sh save
git add chromium/patches/
```

Keep patch diffs minimal. Larger Chromium changes dramatically increase future rebase cost.

---

## Code Style

**Rust**
- Format with `rustfmt` defaults (`cargo fmt`).
- No `clippy` warnings on merge. Run `cargo clippy -- -D warnings` locally.
- Prefer explicit error types over `unwrap()` in production paths.

**Python**
- Format with `black`, lint with `ruff`.
- Type hints on all public functions.
- Docstrings on public classes and non-trivial functions.

**Commits**
- Conventional Commits format: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`
- Subject line: imperative mood, under 72 characters.
- Body: explain *why*, not *what*.

**Pull Requests**
- One logical change per PR.
- Tests required for new code.
- Reference the relevant issue or ADR when applicable.

---

## Key Architectural Decisions

Before making structural changes, review these documents:

- `docs/adr-001-language-architecture.md` — Rationale for the Rust + PyO3 + gRPC architecture.
- `docs/migration-plan.md` — Phased implementation plan and what is in-scope for each milestone.
- `docs/architecture.md` — Component diagrams, sequence flows, and subsystem boundaries.

Changes that contradict an existing ADR require a new ADR documenting the decision and rationale.

---

## Debugging

### Environment variables

| Variable | Effect |
|----------|--------|
| `CARBONYL_ENV_DEBUG=1` | Enables debug logging in the Rust runtime |
| `RUST_LOG=debug` | Rust-level structured logging via `tracing` |

### CLI flags

| Flag | Effect |
|------|--------|
| `--debug` | Verbose output on the CLI binary |
| `--enable-logging --v=1` | Chromium browser-level logs (pass through to headless_shell) |

### Terminal buffer inspection

When debugging what the terminal renderer sees, use `browser.raw_lines()` to dump the pyte screen buffer contents. This is useful for diagnosing rendering artifacts or ANSI parse failures.

---

## Testing Strategy

The target testing architecture covers every layer of the stack:

| Layer | Framework | What is tested |
|-------|-----------|----------------|
| Rust pure functions | `#[test]` | Color math, quad encoding, xterm sequences, fingerprinting |
| Rust state machines | `#[test]` | ANSI parser transitions, renderer state |
| Rust async (session, API) | `#[tokio::test]` | Session lifecycle, gRPC endpoint behavior |
| Python automation | `pytest` | `screen_inspector`, session management |
| Python bindings | `pytest` + `pytest-asyncio` | PyO3 API correctness and error paths |
| Integration | `pytest` | End-to-end: launch, navigate, observe |
| gRPC contract | `buf lint` | Protobuf schema validation |

Run the full suite:

```bash
cargo test --lib          # Rust unit tests
pytest tests/             # Python tests (when present)
buf lint proto/           # protobuf lint
```

Tests for a given module live in the same file (Rust) or a mirrored `tests/` directory (Python). Do not place test code in production modules outside of `#[cfg(test)]` blocks.
