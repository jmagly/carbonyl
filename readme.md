<table align="center">
  <tbody>
    <tr>
      <td>
        <p></p>
        <pre>
   O    O
    \  /
O —— Cr —— O
    /  \
   O    O</pre>
      </td>
      <td><h1>Carbonyl</h1></td>
    </tr>
  </tbody>
</table>

Carbonyl is a Chromium based browser built to run in a terminal. [Read the blog post](https://fathy.fr/carbonyl).

It supports pretty much all Web APIs including WebGL, WebGPU, audio and video playback, animations, etc..

It's snappy, starts in less than a second, runs at 60 FPS, and idles at 0% CPU usage. It does not require a window server (i.e. works in a safe-mode console), and even runs through SSH.

Carbonyl originally started as [`html2svg`](https://github.com/fathyb/html2svg) and is now the runtime behind it.

## Looking for the automation SDK?

Most users want **[carbonyl-agent](https://git.integrolabs.net/roctinam/carbonyl-agent)** — the Python automation package that drives Carbonyl for scripted browsing, scraping, and agent-based testing. It handles binary discovery, session persistence, daemon reconnection, and bot-detection evasion out of the box.

```bash
pip install carbonyl-agent
carbonyl-agent install   # downloads the runtime binary
```

```python
from carbonyl_agent import CarbonylBrowser

b = CarbonylBrowser()
b.open("https://example.com")
b.drain(8.0)
print(b.page_text())
b.close()
```

For multi-instance orchestration (N concurrent browsers over PTY + Unix socket), see **[carbonyl-fleet](https://git.integrolabs.net/roctinam/carbonyl-fleet)**.

This repo (`roctinam/carbonyl`) is the Chromium fork and the source of the runtime tarballs. Most users do **not** need to build it.

## Active Fork — Continued Maintenance

The original repository ([fathyb/carbonyl](https://github.com/fathyb/carbonyl)) has been inactive since early 2023. This fork is actively maintained for use in headless browser automation and agentic pipelines.

**What's different in this fork:**

- **Chromium M147** (147.0.7727.94) — current upstream stable. Upgraded from M111 across six phases (M111 → M120 → M132 → M135 → M140 → M147). 24 patches applied. Runtime tarballs published to [Gitea releases](https://git.integrolabs.net/roctinam/carbonyl/releases).
- **Python automation layer** ([`carbonyl-agent`](https://git.integrolabs.net/roctinam/carbonyl-agent)) — extracted into a standalone installable package. `CarbonylBrowser` class with persistent sessions, daemon reconnect, mouse movement, click-by-text, and screen extraction. Designed for agent-driven web interaction.
- **Bot-detection mitigations** — Firefox UA spoof, `--disable-http2`, `AutomationControlled` suppressed, organic mouse movement API.
- **Session management** — named persistent profiles, fork/snapshot, `SessionManager` CLI.
- **CI infrastructure** — Gitea Actions workflows for fast checks and full Chromium runtime builds, pinned to dedicated build hosts.

**`--carbonyl-b64-text` restored in M135**: the experimental text-capture mode was temporarily disabled during the initial M135 ship and has been re-enabled via a structural refactor (Path A, [issue #28](https://git.integrolabs.net/roctinam/carbonyl/issues/28)). Both bitmap rendering (default) and b64 text capture are functional.

**Maintenance commitment:** Security-relevant Chromium versions will be tracked on a best-effort basis. The automation API is under active development. Issues and PRs welcome.

## Usage

> Carbonyl on Linux without Docker requires the same dependencies as Chromium.

### Docker

```shell
$ docker run --rm -ti fathyb/carbonyl https://youtube.com
```

### npm

```console
$ npm install --global carbonyl
$ carbonyl https://github.com
```

### Binaries

- [macOS amd64](https://github.com/fathyb/carbonyl/releases/download/v0.0.3/carbonyl.macos-amd64.zip)
- [macOS arm64](https://github.com/fathyb/carbonyl/releases/download/v0.0.3/carbonyl.macos-arm64.zip)
- [Linux amd64](https://github.com/fathyb/carbonyl/releases/download/v0.0.3/carbonyl.linux-amd64.zip)
- [Linux arm64](https://github.com/fathyb/carbonyl/releases/download/v0.0.3/carbonyl.linux-arm64.zip)

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

## Known issues

- Fullscreen mode not supported yet

## Comparisons

### Lynx

Lynx is the original terminal web browser, and the oldest one still maintained.

#### Pros

- When it understands a page, Lynx has the best layout, fully optimized for the terminal

#### Cons

> Some might sound like pluses, but Browsh and Carbonyl let you disable most of those if you'd like

- Does not support a lot of modern web standards
- Cannot run JavaScript/WebAssembly
- Cannot view or play media (audio, video, DOOM)

### Browsh

Browsh is the original "normal browser into a terminal" project. It starts Firefox in headless mode and connects to it through an automation protocol.

#### Pro

- It's easier to update the underlying browser: just update Firefox
- This makes development easier: just install Firefox and compile the Go code in a few seconds
- As of today, Browsh supports extensions while Carbonyl doesn't, although it's on our roadmap

#### Cons

- It runs slower and requires more resources than Carbonyl. 50x more CPU power is needed for the same content in average, that's because Carbonyl does not downscale or copy the window framebuffer, it natively renders to the terminal resolution.
- It uses custom stylesheets to fix the layout, which is less reliable than Carbonyl's changes to its HTML engine (Blink).

## Operating System Support

As far as tested, the operating systems under are supported:

- Linux (Debian, Ubuntu and Arch tested)
- MacOS
- Windows 11 and WSL

## Contributing

Carbonyl is split in two parts: the "core" which is built into a shared library (`libcarbonyl`), and the "runtime" which dynamically loads the core (`carbonyl` executable).

The core is written in Rust and takes a few seconds to build from scratch. The runtime is a modified version of the Chromium headless shell and takes more than an hour to build from scratch.

If you're just making changes to the Rust code, build `libcarbonyl` and replace it in a release version of Carbonyl.

### Core

```console
$ cargo build
```

### Runtime

Few notes:

- Building the runtime is almost the same as building Chromium with extra steps to patch and bundle the Rust library. Scripts in the `scripts/` directory are simple wrappers around `gn`, `ninja`, etc..
- Building Chromium for arm64 on Linux requires an amd64 processor
- Carbonyl is only tested on Linux and macOS, other platforms likely require code changes to Chromium
- Chromium is huge and takes a long time to build, making your computer mostly unresponsive. An 8-core CPU such as an M1 Max or an i9 9900k with 10 Gbps fiber takes around ~1 hour to fetch and build. It requires around 100 GB of disk space.

#### Fetch

> Fetch Chromium's code.

```console
$ ./scripts/gclient.sh sync
```

#### Apply patches

> Any changes made to Chromium will be reverted, make sure to save any changes you made.

```console
$ ./scripts/patches.sh apply
```

#### Configure

```console
$ ./scripts/gn.sh args out/Default
```

> `Default` is the target name, you can use multiple ones and pick any name you'd like, i.e.:
>
> ```console
> $ ./scripts/gn.sh args out/release
> $ ./scripts/gn.sh args out/debug
> # or if you'd like to build a multi-platform image
> $ ./scripts/gn.sh args out/arm64
> $ ./scripts/gn.sh args out/amd64
> ```

When prompted, enter the following arguments:

```gn
import("//carbonyl/src/browser/args.gn")

# uncomment this to build for arm64
# target_cpu = "arm64"

# comment this to disable ccache
cc_wrapper = "env CCACHE_SLOPPINESS=time_macros ccache"

# comment this for a debug build
is_debug = false
symbol_level = 0
is_official_build = true
```

#### Build binaries

```console
$ ./scripts/build.sh Default
```

This should produce the following outputs:

- `out/Default/headless_shell`: browser binary
- `out/Default/icudtl.dat`
- `out/Default/libEGL.so`
- `out/Default/libGLESv2.so`
- `out/Default/v8_context_snapshot.bin`

#### Build Docker image

```console
# Build arm64 Docker image using binaries from the Default target
$ ./scripts/docker-build.sh Default arm64
# Build amd64 Docker image using binaries from the Default target
$ ./scripts/docker-build.sh Default amd64
```

#### Run

```
$ ./scripts/run.sh Default https://wikipedia.org
```

## Sponsors

This project is supported by:

- **[Roko Network](https://roko.network)** — The Temporal Layer for Web3. Enterprise-grade timing infrastructure for blockchain applications.
- **[Selfient](https://selfient.xyz)** — No-Code Smart Contracts for Everyone. Democratizing Web3 by making blockchain-based agreements accessible without coding.
- **[Integro Labs](https://integrolabs.io)** — AI-Powered Automation Solutions. Custom AI and blockchain solutions for digital automation and transformation.

Interested in sponsoring? Open a [GitHub Discussion](https://github.com/jmagly/carbonyl/discussions).
