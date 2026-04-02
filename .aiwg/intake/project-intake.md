# Project Intake Form (Existing System)

**Document Type**: Brownfield System Documentation
**Generated**: 2026-04-01
**Source**: Codebase analysis of `/mnt/dev-inbox/fathyb/carbonyl`

---

## Metadata

- **Project name**: Carbonyl
- **Repository**: git@git.integrolabs.net:roctinam/carbonyl.git (origin) / git@github.com:jmagly/carbonyl.git (github)
- **Upstream**: https://github.com/fathyb/carbonyl
- **Current Version**: 0.0.3
- **Last Upstream Tag**: 0.0.3 (2023-02-18)
- **License**: BSD-3-Clause
- **Stakeholders**: Engineering (roctinam), upstream maintainer (fathyb)

---

## System Overview

**Purpose**: Carbonyl is a Chromium-based browser built to run inside a terminal. It renders web pages — including WebGL, WebGPU, audio, video, and animations — natively as ANSI/xterm sequences in any TTY. It is not a text-mode browser like Lynx but a full Blink/V8 browser that outputs to the terminal display layer.

**Current Status**: Open source, public release at v0.0.3. Upstream project; this repo is a workspace fork under `roctinam` with `github` (fathyb/carbonyl) as publish target.

**Platforms Supported**: Linux (amd64, arm64), macOS (amd64, arm64), Windows 11 / WSL

**Distribution**: Docker Hub (`fathyb/carbonyl`), NPM (`carbonyl`), direct binary archives

---

## Problem and Outcomes

**Problem Statement**: Full web browsing inside terminal environments has historically required either a text-only renderer (Lynx, w3m) or a heavyweight VNC/X forwarding setup. Carbonyl bridges this gap by embedding Chromium and redirecting its rendering pipeline to ANSI escape sequences.

**Target Personas**:
- Developers who live in terminal environments (SSH, tmux, remote servers)
- Users on low-bandwidth or headless systems needing a capable browser
- Automation/testing use cases requiring a headless browser with terminal integration

**Key Capabilities**:
- < 1 second startup time
- 60 FPS rendering target
- 0% idle CPU (event-driven, no polling)
- Full WebGL, WebGPU, Web Audio, Web Video support
- ANSI 256-color and bitmap (sixel/kitty) rendering modes

---

## Current Scope and Features

### Core Features (from codebase analysis)

| Feature | Location | Notes |
|---------|----------|-------|
| Terminal TTY control (raw mode, resize) | `src/input/tty.rs` | ioctl-based |
| ANSI input parsing (keyboard, mouse) | `src/input/parser.rs`, `keyboard.rs`, `mouse.rs` | Full escape sequence support |
| DCS (Device Control String) protocol | `src/input/dcs/` | For bitmap/sixel support |
| Color quantization (Chromium → 256-color ANSI) | `src/output/quantizer.rs` | KD-tree based |
| Quadrant character rendering | `src/output/quad.rs` | Introduced in v0.0.3 |
| Frame synchronization | `src/output/frame_sync.rs` | 60 FPS, vsync-aligned |
| Threaded render loop | `src/output/render_thread.rs` | Lazy-started, mpsc-driven |
| Navigation UI | `src/ui/navigation.rs` | Address bar, basic UI chrome |
| Rust ↔ Chromium FFI bridge | `src/browser/bridge.rs`, `bridge.cc/h` | via `cxx` crate |
| CLI argument parsing | `src/cli/cli.rs` | `--fps`, `--bitmap`, `--shell-mode` flags |
| Docker container build | `Dockerfile`, `scripts/docker-*.sh` | Multi-arch (amd64, arm64) |
| NPM package distribution | `scripts/npm-*.sh` | Wraps binaries for npm install |

### Known Limitations (from README)
- Fullscreen mode not supported

### TODO / In-Progress (from codebase)
- `navigation.rs`: "TODO: Unicode" — incomplete Unicode support in navigation bar

---

## Architecture (Current State)

**Architecture Style**: Thin integration layer over Chromium — modular monolith in Rust, compiled to a shared library (`libcarbonyl`), loaded by a patched Chromium headless shell.

### Component Map

```
┌─────────────────────────────────────────────────┐
│                   User / Terminal                │
└──────────────────────┬──────────────────────────┘
                       │ TTY / ANSI
┌──────────────────────▼──────────────────────────┐
│         libcarbonyl (Rust shared library)        │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  input/  │  │  output/ │  │   browser/    │  │
│  │  tty.rs  │  │ renderer │  │  bridge.rs    │  │
│  │  parser  │  │ quantizer│  │  (FFI layer)  │  │
│  │  mouse   │  │ painter  │  └──────┬────────┘  │
│  └──────────┘  └──────────┘         │ cxx FFI   │
└────────────────────────────────────┼────────────┘
                                     │
┌────────────────────────────────────▼────────────┐
│         Chromium headless_shell (patched)        │
│    Blink (HTML/CSS) · V8 (JS) · Skia (GFX)     │
│    Mojo IPC · Media (H.264) · Web APIs          │
└─────────────────────────────────────────────────┘
```

### Thread Model

| Thread | Owns | Communication |
|--------|------|---------------|
| Main / Chromium | Browser event loop, V8, Blink | — |
| Render thread (lazy) | ANSI output, color quantization | `mpsc::Receiver<Message>` |
| Input listener | TTY raw-mode reads, ANSI parsing | Chromium event injection |

### Data Flow
1. Chromium renders frame → bitmap captured via Mojo display client
2. `libcarbonyl` quantizes RGB → 256-color ANSI
3. Render thread diffs frame, emits xterm escape sequences to stdout
4. TTY input → ANSI parser → translated to Chromium key/mouse events

### Integration Points

| Service | Purpose | Location |
|---------|---------|----------|
| Chromium renderer | HTML/CSS/JS execution | `src/browser/renderer.cc` |
| Chromium compositor | Frame delivery | `src/browser/host_display_client.cc` |
| Mojo IPC | Render service messaging | `src/browser/bridge.mojom` |
| NPM registry | Binary distribution | `scripts/npm-*.sh` |
| Docker Hub | Container distribution | `scripts/docker-*.sh` |

### Data Models
No persistent data models. Stateless per invocation. User data (cookies, sessions) stored in `/carbonyl/data` (Docker volume), managed entirely by Chromium.

---

## Scale and Performance

**Current Capacity**: Single-user CLI tool; no multi-tenancy, no server-side scaling concern. Each invocation is an isolated browser process.

**Performance Targets** (from README and code):
- Startup: < 1 second
- Frame rate: 60 FPS (configurable via `--fps`)
- CPU idle: 0% (event-driven via Chromium vsync + mpsc)

**Optimizations Present**:
- Lazy render thread initialization
- KD-tree color quantization for efficient nearest-color lookup
- Quadrant character rendering (v0.0.3) — higher visual resolution per terminal cell
- Frame diff (painter.rs) — only emits changed cells
- Event-driven architecture (no polling loops)

**Bottlenecks / Pain Points**:
- Chromium build time: 1+ hour, ~100 GB disk (development friction, not runtime)
- H.264 codec: Proprietary, included for media support — licensing consideration for redistribution
- `unsafe` code in FFI and TTY ioctl layers — correctness relies on discipline

---

## Security and Compliance

**Security Posture**: Minimal / intentional

**Rationale**: Carbonyl is a client-side tool. There is no authentication, no multi-user model, no network service exposed. Security considerations are:
1. **Chromium sandbox**: Disabled via `--no-sandbox` in Docker (intentional for headless). Users running locally use system sandbox.
2. **FFI safety**: `unsafe` in bridge.rs and tty.rs; isolated and well-contained.
3. **No secrets in codebase**: Confirmed. No hardcoded credentials, tokens, or keys.

**Data Classification**: Public. No PII, no payment data, no PHI.

**Compliance Requirements**:
- **H.264 codec**: Proprietary codec. Commercial redistribution may require licensing from MPEG-LA. Currently included in Chromium build args (`enable_h264 = true`).
- **Export controls**: Chromium inherits U.S. export regulations; H.264 adds complexity.
- **No GDPR, HIPAA, PCI-DSS, or SOC2 requirements detected.**

---

## Team and Operations

**Original Authors**: Fathy Boundjadj (primary), 11 unique contributors total (upstream)
**Workspace Owner**: roctinam (Joseph Magly) — fork maintained here as workspace

**Development Velocity (upstream)**:
- 88 commits over 3.5 months (late 2022 – early 2023)
- Slowing post-v0.0.3 — upstream appears to be in maintenance/low-activity phase

**Branch Strategy**: Conventional commits (`feat/`, `fix/`, `chore/`, `doc/`, `perf/`)

**Process Maturity**:
- Version control: Git, semantic versioning, changelog
- CI/CD: Build scripts present; no GitHub Actions workflows found in checked directory
- Testing: No automated test suite detected
- Documentation: Good README, changelog; no API docs or architecture docs

**Operational**:
- Monitoring: None (stateless CLI tool, no server to monitor)
- Logging: `src/utils/log.rs` — stderr output via `CARBONYL_ENV_DEBUG`
- Alerting: N/A
- Runbooks: None (not needed for CLI distribution)

---

## Dependencies and Infrastructure

### Runtime Dependencies (Docker)
- `libasound2` — ALSA audio
- `libexpat1` — XML parsing (Chromium)
- `libfontconfig1` — Font configuration
- `libnss3` — NSS crypto (Chromium TLS)

### Rust Crate Dependencies
| Crate | Version | Purpose |
|-------|---------|---------|
| `libc` | 0.2 | System call FFI |
| `unicode-width` | 0.1.10 | Terminal column width |
| `unicode-segmentation` | 1.10.0 | Grapheme cluster boundaries |
| `chrono` | 0.4.23 | Date/time utilities |
| `cxx` | 1.0.88 | Rust ↔ C++ FFI framework |
| `cc` | 1.0.79 | C/C++ compilation in build.rs |

### Build Toolchain
| Tool | Purpose |
|------|---------|
| `cargo` | Rust compilation |
| `gn` | Chromium build configuration |
| `ninja` | Chromium build execution |
| `gclient` | Chromium source sync |
| `docker` | Container image building/pushing |
| `git-cliff` | Changelog generation |

### Infrastructure
- Hosting: N/A (distributed CLI, not a service)
- Container registry: Docker Hub (`fathyb/carbonyl`)
- Package registry: NPM (`carbonyl`)
- Binary releases: GitHub Releases (zip archives per platform/arch)
- Upstream CI: Not visible from fork

---

## Known Issues and Technical Debt

| Issue | Severity | Location |
|-------|---------|----------|
| Unicode support incomplete in nav bar | Low | `src/ui/navigation.rs:TODO` |
| H.264 commercial licensing | Medium | `src/browser/args.gn` (enable_h264=true) |
| `--no-sandbox` in Docker | Low-Medium | `Dockerfile` (intentional, document clearly) |
| No automated test suite | Medium | Entire codebase |
| Chromium build is 100 GB / 1+ hour | Dev friction | `chromium/` submodule |
| Upstream low-activity post v0.0.3 | Risk | git history |

---

## Why This Intake Now?

**Context**: Establishing a workspace fork of the upstream `fathyb/carbonyl` project under `roctinam` on the internal Gitea forge. The GitHub remote (`github`) is the publish target; `origin` is the internal workspace. This intake documents the codebase baseline before any local development begins.

**Goals**:
1. Document current state of the inherited codebase
2. Establish SDLC baseline for any local modifications
3. Identify technical debt and risk areas before extending
4. Set foundation for future improvements (tests, CI/CD, potential feature work)

---

## Attachments

- Solution profile: [`solution-profile.md`](./solution-profile.md)
- Option matrix: [`option-matrix.md`](./option-matrix.md)
- Codebase: `/mnt/dev-inbox/fathyb/carbonyl`
- Internal repo: `git@git.integrolabs.net:roctinam/carbonyl.git`
- Upstream: `https://github.com/fathyb/carbonyl`
