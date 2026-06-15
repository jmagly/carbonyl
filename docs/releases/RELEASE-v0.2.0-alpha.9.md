# Carbonyl v0.2.0-alpha.9

Packaging release on top of `v0.2.0-alpha.8`. Carbonyl now ships **native install
packages** — `.deb`, `.rpm`, `.AppImage` (Linux x86_64) and an unsigned `.pkg` /
`.dmg` (macOS Apple Silicon) — alongside the existing runtime tarballs and npm
package. The Chromium runtime is **byte-identical to alpha.8** (runtime hash
`283ca65ffeeaa2dc`, patch stack still 30); everything new here is packaging and
release engineering.

## Highlights

### Native install packages

Releases previously shipped only raw runtime tarballs. Each release now also
publishes proper OS-native installers
([#129](https://github.com/jmagly/carbonyl/issues/129)):

- **Debian/Ubuntu** — `carbonyl_<version>_amd64.deb`
- **Fedora/RHEL/openSUSE** — `carbonyl-<version>-1.x86_64.rpm`
- **Any Linux (portable)** — `carbonyl-<version>-x86_64.AppImage`
- **macOS (Apple Silicon)** — `carbonyl-<version>-macos-arm64.pkg` / `.dmg`

Linux packages install to `/usr/lib/carbonyl` with a `/usr/bin/carbonyl`
launcher, a desktop entry, and an icon; dependencies are declared so the package
manager pulls what's missing. macOS installs to `/usr/local/carbonyl` and
symlinks `/usr/local/bin/carbonyl`. See
[docs/install.md](../install.md) and
[ADR-003](../adr-003-native-install-packages.md).

The Linux installers are built automatically in `release.yml` on titan
(`nfpm` + `appimagetool` now baked into the builder image); the macOS installer
is built on the `mutsu` host and attached to the release.

> **macOS is unsigned** (no Apple Developer ID): Gatekeeper will warn on first
> launch. The bypass is documented in the `.dmg` and in `docs/install.md`. A
> signed + notarized installer will follow.

> Prerelease `.deb`/`.rpm` filenames show the version as `0.2.0~alpha.9` — the
> `~` is correct Debian/RPM ordering (sorts before `0.2.0`).

### Release-engineering fixes

- `release.yml` no longer fails the routine `v*` tag-push run when the macOS
  runtime asset is absent — a tag push warns and auto-skips macOS, while an
  explicit `workflow_dispatch` with `include_macos=true` still fails loudly
  ([#127](https://github.com/jmagly/carbonyl/issues/127)).
- The `mutsu` macOS build routes cargo cache + temp onto the external volume so
  the small boot disk can't fail the build with `ENOSPC`
  ([#128](https://github.com/jmagly/carbonyl/issues/128)).

### Multi-arch status

`aarch64-unknown-linux-gnu` (Linux arm64) is still **not** in this release — its
runtime isn't built yet ([#116](https://github.com/jmagly/carbonyl/issues/116));
its native packages follow once that runtime exists.

## What's in the runtime

Runtime hash `283ca65ffeeaa2dc` (identical to alpha.8).

Linux amd64, both Ozone variants:

- `carbonyl-0.2.0-alpha.9-x86_64-unknown-linux-gnu.tgz` — `headless` ozone (default; pure-terminal)
- `carbonyl-0.2.0-alpha.9-x11-x86_64-unknown-linux-gnu.tgz` — `x11` ozone (terminal + X-mirror; for trusted-input mode)

macOS Apple Silicon:

- `carbonyl-0.2.0-alpha.9-aarch64-apple-darwin.tgz` — `headless` ozone, built on the `mutsu` host

## Install packages

- `carbonyl_0.2.0~alpha.9_amd64.deb`
- `carbonyl-0.2.0~alpha.9-1.x86_64.rpm`
- `carbonyl-0.2.0-alpha.9-x86_64.AppImage`
- `carbonyl-0.2.0-alpha.9-macos-arm64.pkg` (unsigned)
- `carbonyl-0.2.0-alpha.9-macos-arm64.dmg` (unsigned; wraps the `.pkg`)

Each artifact ships with a `.sha256` companion. Install instructions:
[docs/install.md](../install.md).
