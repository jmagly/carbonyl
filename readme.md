<div align="center">

<pre>
   O    O
    \  /
   O —— Cr —— O
    /  \
   O    O
</pre>

# Carbonyl

**Chromium-based browser that runs in a terminal — 60 FPS, 0% idle CPU, SSH-friendly**

```bash
pip install carbonyl-agent && carbonyl-agent install
```

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Chromium M147](https://img.shields.io/badge/chromium-M147.0.7727.94-4285F4?style=flat-square&logo=googlechrome&logoColor=white)](https://chromium.googlesource.com/chromium/src/+/refs/tags/147.0.7727.94)
[![Runtime](https://img.shields.io/badge/runtime-releases-green?style=flat-square)](https://github.com/jmagly/carbonyl/releases)

[**Get Started**](#-get-started) · [**Fork Status**](#active-fork--continued-maintenance) · [**Build from Source**](#building-from-source) · [**Comparisons**](#comparisons) · [**Blog**](https://fathy.fr/carbonyl)

</div>

---

## What Carbonyl Is

Carbonyl is a Chromium-based browser that renders into terminal text. It supports pretty much all Web APIs — WebGL, WebGPU, audio and video playback, animations — and starts in less than a second, runs at 60 FPS, and idles at 0% CPU. It does not require a window server (works in a safe-mode console) and runs comfortably over SSH. Carbonyl originally started as [`html2svg`](https://github.com/fathyb/html2svg) and is now the runtime behind it.

This repository (`jmagly/carbonyl`) is the **maintained fork** of the original [`fathyb/carbonyl`](https://github.com/fathyb/carbonyl), which has been inactive since early 2023. It tracks upstream Chromium stable (currently M147) and publishes runtime tarballs as release assets.

---

## Looking for the automation SDK?

Most users want **[carbonyl-agent](https://github.com/jmagly/carbonyl-agent)** — the Python SDK that drives Carbonyl for scripted browsing, scraping, and agent-based testing. It handles binary discovery, session persistence, daemon reconnection, and bot-detection evasion out of the box.

```bash
pip install carbonyl-agent
carbonyl-agent install   # downloads the verified runtime binary
```

```python
from carbonyl_agent import CarbonylBrowser

b = CarbonylBrowser()
b.open("https://example.com")
b.drain(8.0)
print(b.page_text())
b.close()
```

For multi-instance orchestration (N concurrent browsers over PTY + Unix socket, with gRPC + REST), see **[carbonyl-fleet](https://github.com/jmagly/carbonyl-fleet)**.

This repo (`jmagly/carbonyl`) is the Chromium fork and the source of the runtime tarballs. Most users do **not** need to build it.

---

## Get Started

### Use the runtime (recommended)

```bash
pip install carbonyl-agent
carbonyl-agent install
```

The installer downloads a verified-by-SHA256 runtime tarball from the release page. No compilation required.

### Run Carbonyl directly

```bash
# From Docker (upstream image — M111-era, dated but works)
docker run --rm -ti fathyb/carbonyl https://youtube.com

# Or via npm (upstream package — M111-era)
npm install --global carbonyl
carbonyl https://github.com

# Or download a pre-built runtime from release assets (M147, current)
# See: https://github.com/jmagly/carbonyl/releases
```

---

## Active Fork — Continued Maintenance

The original repository ([fathyb/carbonyl](https://github.com/fathyb/carbonyl)) has been inactive since early 2023. This fork is actively maintained for use in headless browser automation and agentic pipelines.

### What's different in this fork

- **Chromium M147** (147.0.7727.94) — current upstream stable. Upgraded from M111 across six phases (M111 → M120 → M132 → M135 → M140 → M147). 24 patches applied. Runtime tarballs published as [release assets](https://github.com/jmagly/carbonyl/releases).
- **Python automation layer** ([`carbonyl-agent`](https://github.com/jmagly/carbonyl-agent)) — extracted into a standalone installable package. `CarbonylBrowser` class with persistent sessions, daemon reconnect, mouse movement, click-by-text, and screen extraction.
- **Fleet server** ([`carbonyl-fleet`](https://github.com/jmagly/carbonyl-fleet)) — Rust server for N concurrent browsers with gRPC + REST + Python SDK.
- **Bot-detection mitigations** — Firefox UA spoof, `--disable-http2`, `AutomationControlled` suppressed, organic mouse movement API.
- **Session management** — named persistent profiles, fork/snapshot, `SessionManager` CLI.
- **CI infrastructure** — automated workflows for fast checks and full Chromium runtime builds, pinned to dedicated build hosts.

**`--carbonyl-b64-text` restored in M135**: the experimental text-capture mode was temporarily disabled during the initial M135 ship and has been re-enabled via a structural refactor (Path A, [issue #28](https://github.com/jmagly/carbonyl/issues/28)). Both bitmap rendering (default) and b64 text capture are functional on M147.

**Maintenance commitment:** Security-relevant Chromium versions are tracked on a best-effort basis. The automation API is under active development. Issues and PRs welcome.

---

## Project Family

| Repo | Purpose | Build tech |
|------|---------|------------|
| [`carbonyl`](https://github.com/jmagly/carbonyl) | Chromium fork + runtime tarballs (this repo) | Chromium, GN, ninja, Rust |
| [`carbonyl-agent`](https://github.com/jmagly/carbonyl-agent) | Python automation SDK (single-instance) | Python 3.11+, pyte, pexpect |
| [`carbonyl-fleet`](https://github.com/jmagly/carbonyl-fleet) | Fleet server (N concurrent browsers, gRPC + REST) | Rust, tonic, axum |

---

## Known Issues

- Fullscreen mode not supported yet

---

## Comparisons

### Lynx

Lynx is the original terminal web browser, and the oldest one still maintained.

**Pros**
- When it understands a page, Lynx has the best layout, fully optimized for the terminal

**Cons** _(some might sound like pluses, but Browsh and Carbonyl let you disable most of those if you'd like)_
- Does not support a lot of modern web standards
- Cannot run JavaScript/WebAssembly
- Cannot view or play media (audio, video, DOOM)

### Browsh

Browsh is the original "normal browser in a terminal" project. It starts Firefox in headless mode and connects to it through an automation protocol.

**Pros**
- Easier to update the underlying browser: just update Firefox
- As of today, Browsh supports extensions while Carbonyl doesn't (on our roadmap)

**Cons**
- Runs slower and requires more resources than Carbonyl. 50× more CPU for the same content on average, because Carbonyl does not downscale or copy the window framebuffer — it natively renders to the terminal resolution.
- Uses custom stylesheets to fix the layout, which is less reliable than Carbonyl's changes to its HTML engine (Blink).

---

## Operating System Support

| OS | Status |
|----|--------|
| Linux (Debian, Ubuntu, Arch) | ✅ Tested |
| macOS | ✅ Tested (upstream; M147 fork not yet rebuilt on macOS) |
| Windows 11 / WSL | 🟡 Reported working (upstream) |

---

## Demo

<table>
  <tbody>
    <tr>
      <td>
        <video src="https://user-images.githubusercontent.com/5746414/213682926-f1cc2de7-a38c-4125-9257-92faecfc7e24.mp4">
      </td>
      <td>
        <video src="https://user-images.githubusercontent.com/5746414/213682913-398d3d11-1af8-4ae6-a0cd-a7f878efd88b.mp4">
      </td>
    </tr>
    <tr>
      <td colspan="2">
        <video src="https://user-images.githubusercontent.com/5746414/213682918-d6396a4f-ee23-431d-828e-4ad6a00e690e.mp4">
      </td>
    </tr>
  </tbody>
</table>

---

## Building from Source

> You almost certainly do not need to do this — use `carbonyl-agent install` to pull a pre-built runtime.

Carbonyl is split in two parts:

- **Core** (`libcarbonyl.so`) — written in Rust, builds in seconds via `cargo`
- **Runtime** (`headless_shell`) — a modified Chromium build with 24 patches, requires the full Chromium toolchain

If you're just changing the Rust code, build `libcarbonyl` and drop it into a release version of Carbonyl. You do not need to rebuild Chromium.

### Core (Rust library)

```bash
cargo build
```

### Runtime (Chromium + libcarbonyl)

> ⚠️ Building Chromium takes considerable wall time, disk space, and memory. Expect **~100 GB of disk** and a heavy compile workload.

Notes:
- Building the runtime is essentially the Chromium build flow with extra steps to patch and bundle the Rust library.
- Scripts in `scripts/` are thin wrappers around `gn`, `ninja`, etc.
- Cross-compiling Chromium for arm64 on Linux requires an amd64 processor.
- Tested on Linux and macOS.

#### Fetch Chromium sources

```bash
./scripts/gclient.sh sync
```

#### Apply Carbonyl patches

> Any existing changes in `chromium/src/` will be stashed. Save your work first.

```bash
./scripts/patches.sh apply
```

#### Configure the GN build

```bash
./scripts/gn.sh args out/Default
```

When prompted, enter:

```gn
import("//carbonyl/src/browser/args.gn")

# uncomment to build for arm64
# target_cpu = "arm64"

# comment to disable ccache
cc_wrapper = "env CCACHE_SLOPPINESS=time_macros ccache"

# comment for a debug build
is_debug = false
symbol_level = 0
is_official_build = true
```

#### Build binaries

```bash
./scripts/build.sh Default
```

Produces:
- `out/Default/headless_shell` — browser binary
- `out/Default/icudtl.dat`
- `out/Default/libEGL.so`
- `out/Default/libGLESv2.so`
- `out/Default/v8_context_snapshot.bin`

#### Build the Docker image

```bash
./scripts/docker-build.sh Default arm64
./scripts/docker-build.sh Default amd64
```

#### Run

```bash
./scripts/run.sh Default https://wikipedia.org
```

See [MAINTENANCE.md](MAINTENANCE.md) for detailed upgrade procedures, patch rebasing guidance, and the rebase SOP used to move M111 → M147.

---

## Documentation

- [MAINTENANCE.md](MAINTENANCE.md) — upgrade procedure, patch reference commits, GN args notes
- [changelog.md](changelog.md) — full rebase history (M111 → M147)
- [AIWG.md](AIWG.md) — AIWG framework integration
- [docs/architecture.md](docs/architecture.md) — cross-layer architecture notes
- [docs/rust-chromium-boundary.md](docs/rust-chromium-boundary.md) — Rust/C++ layer map, FFI boundary overview, rebuild recipes by change type, verification patterns
- [docs/chromium-integration.md](docs/chromium-integration.md) — catalog of every Carbonyl modification to Chromium (patches, injected sources, FFI, build flags)
- [chromium/patches/chromium/](chromium/patches/chromium/) — the 24 tracked patches

---

## Contributing

PRs and issues welcome at [github.com/jmagly/carbonyl](https://github.com/jmagly/carbonyl).

Most meaningful changes to the Python automation path belong in [`carbonyl-agent`](https://github.com/jmagly/carbonyl-agent). This repo is the Chromium side — patches, build scripts, runtime infrastructure.

---

## Community & Support

- **Issues**: [github.com/jmagly/carbonyl/issues](https://github.com/jmagly/carbonyl/issues)
- **GitHub Discussions**: [github.com/jmagly/carbonyl/discussions](https://github.com/jmagly/carbonyl/discussions)

---

## License

**MIT License** — see [LICENSE](LICENSE).

Carbonyl includes Chromium, which is BSD-licensed. See `chromium/src/LICENSE` after a checkout for upstream terms.

---

## Sponsors

<table>
<tr>
<td width="33%" align="center">

### [Roko Network](https://roko.network)

**The Temporal Layer for Web3**

Enterprise-grade timing infrastructure for blockchain applications.

</td>
<td width="33%" align="center">

### [Selfient](https://selfient.xyz)

**No-Code Smart Contracts for Everyone**

Making blockchain-based agreements accessible to all.

</td>
<td width="33%" align="center">

### [Integro Labs](https://integrolabs.io)

**AI-Powered Automation Solutions**

Custom AI and blockchain solutions for the digital age.

</td>
</tr>
</table>

**Interested in sponsoring?** Open a [GitHub Discussion](https://github.com/jmagly/carbonyl/discussions).

---

## Acknowledgments

Built on top of [Carbonyl](https://github.com/fathyb/carbonyl) by Fathy Boundjadj, which in turn sits on [Chromium](https://www.chromium.org/) and [Skia](https://skia.org/). The M111→M147 rebase path was informed by [CEF](https://github.com/chromiumembedded/cef)'s `blink_glue.cc` pattern for the Path A structural fix. Thanks to the Chromium cppgc / Oilpan maintainers for the underlying template machinery (see [issue #27](https://github.com/jmagly/carbonyl/issues/27)).

---

<div align="center">

**[⬆ Back to Top](#carbonyl)**

</div>
