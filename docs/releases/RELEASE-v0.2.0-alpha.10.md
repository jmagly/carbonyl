# Carbonyl v0.2.0-alpha.10

Container + framebuffer-foundations release on top of `v0.2.0-alpha.9`. Carbonyl
now ships a published **container image** (`ghcr.io/jmagly/carbonyl`), lands the
first cycle of a **direct `/dev/fb0` framebuffer backend**, hardens the Linux
install packages, and tightens runtime-release hygiene. The Chromium patch stack
is unchanged (30 patches); the runtime hash moves to `1d6058c2494e7a5d` because
the new framebuffer module compiles into the cdylib (it is dormant in this
build — see below).

## Highlights

### Runtime container image

The runtime is now published as an OCI image to
`ghcr.io/jmagly/carbonyl` ([#132](https://github.com/jmagly/carbonyl/issues/132)):

- Hardened image — bundled CA certificates for HTTPS, a sane default zoom, and
  `tini` as PID 1 for correct signal handling and zombie reaping.
- Both Ozone variants are covered (the `x11` image carries the X-mirror path for
  trusted-input mode).
- The packaging step falls back to default-branch tooling when building a tag
  that predates `package-image.sh`, so older tags can still be imaged.

```bash
docker run --rm -it ghcr.io/jmagly/carbonyl https://example.com
```

### Framebuffer backend (`/dev/fb0`) — cycle 1

First cycle of a direct-to-Linux-framebuffer output path, so Carbonyl can render
at full pixel resolution on a local system TTY without an X11/Wayland session —
kiosk, appliance, and recovery-console setups
([#125](https://github.com/jmagly/carbonyl/issues/125)):

- New self-contained backend module (`src/output/framebuffer.rs`): device open,
  `FBIOGET_{F,V}SCREENINFO` geometry, `mmap`, BGRA→native pixel conversion,
  stride-aware blit, and an explicit error taxonomy. The pure convert/blit/format
  core is unit-tested.
- New `--framebuffer[=PATH]` flag and `CARBONYL_FRAMEBUFFER` env var (default
  device `/dev/fb0`).

> **Dormant in this build.** The flag is parsed and the module is compiled in,
> but the backend is **not yet wired into the live render path**. When
> `--framebuffer` is set, startup prints a notice and falls back to the terminal
> renderer. Cycle 2 wires the live path, derives the viewport from device
> geometry, and pairs input. See
> [docs/framebuffer-backend.md](../framebuffer-backend.md).

The terminal/ANSI renderer remains the default and is unchanged.

### Packaging hardening

- `.deb` / `.rpm` now **declare the runtime's `dlopen`'d shared-library
  dependencies**, so the package manager pulls what Chromium loads at runtime
  rather than failing at launch ([#136](https://github.com/jmagly/carbonyl/issues/136)).
- The **AppImage is self-contained**, validated by a per-pixel-format render
  smoke test in CI ([#138](https://github.com/jmagly/carbonyl/issues/138)).

### Release-engineering

- **Only the latest runtime cut is kept.** Each runtime-affecting push publishes a
  fresh `runtime-<hash>` pair; `build-runtime.yml` now prunes stale runtime
  releases/tags after publishing, keeping only the current hash's headless + x11
  pair. The `v*` source releases are never touched
  ([#144](https://github.com/jmagly/carbonyl/issues/144)).
- The **Linux arm64 runtime build is now CI-dispatchable** on the `mutsu` host
  (SSH driven from a secret; Colima docker socket self-heals before the build)
  ([#116](https://github.com/jmagly/carbonyl/issues/116)). The arm64 runtime is
  **not shipped in this release** — that build is on hold pending validation.

### Multi-arch status

`aarch64-unknown-linux-gnu` (Linux arm64) and `aarch64-apple-darwin` (macOS Apple
Silicon) are **not** in this release — their runtimes aren't built for hash
`1d6058c2494e7a5d`. The release auto-skips them; native packages follow once
those runtimes exist ([#116](https://github.com/jmagly/carbonyl/issues/116)).

## What's in the runtime

Runtime hash `1d6058c2494e7a5d` (patch stack unchanged at 30; differs from
alpha.9's `283ca65ffeeaa2dc` only by the dormant framebuffer module linked into
the cdylib).

Linux amd64, both Ozone variants:

- `carbonyl-0.2.0-alpha.10-x86_64-unknown-linux-gnu.tgz` — `headless` ozone (default; pure-terminal)
- `carbonyl-0.2.0-alpha.10-x11-x86_64-unknown-linux-gnu.tgz` — `x11` ozone (terminal + X-mirror; for trusted-input mode)

## Install packages

Linux x86_64:

- `carbonyl_0.2.0~alpha.10_amd64.deb`
- `carbonyl-0.2.0~alpha.10-1.x86_64.rpm`
- `carbonyl-0.2.0-alpha.10-x86_64.AppImage`

Each artifact ships with a `.sha256` companion. Install instructions:
[docs/install.md](../install.md).

Container image: `ghcr.io/jmagly/carbonyl` (see Highlights).

> Prerelease `.deb`/`.rpm` filenames show the version as `0.2.0~alpha.10` — the
> `~` is correct Debian/RPM ordering (sorts before `0.2.0`).
