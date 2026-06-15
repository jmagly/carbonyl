# ADR-003: Native install packages (.deb / .rpm / .AppImage / .pkg / .dmg)

- **Status:** Accepted
- **Date:** 2026-06-14
- **Issue:** roctinam/carbonyl#129
- **Supersedes:** none
- **Related:** #113 (release asset staging), #116 (arm64-linux runtime)

## Context

Carbonyl is distributed two ways today: the npm package (`carbonyl` plus
`@fathyb/carbonyl-<os>-<cpu>` platform packages built by `scripts/npm-package.mjs`)
and the raw runtime tarballs (`carbonyl-<version>-<triple>.tgz`) attached to each
release. Neither is a *native install*: a user cannot `apt install`, `dnf install`,
run an `.AppImage`, or double-click a macOS installer. The runtime is a small,
relocatable payload (one binary plus a handful of sibling libraries and data files),
so wrapping it in OS-native package formats is tractable.

We build two arch families today: Linux `x86_64` (headless + x11 ozone variants) on
the titan Gitea runner, and macOS `aarch64` on mutsu over SSH. arm64-linux is not yet
built (#116).

## Reasoning

1. **Problem analysis.** "Proper installs" means OS-native packages that place
   `carbonyl` on `PATH` with its support libraries resolvable, installable and
   removable through the platform's package manager (or a double-click installer on
   macOS). The blocker is purely packaging — the runtime payload already exists per
   arch under `build/pre-built/<triple>/`.
2. **Constraint identification.** (a) No Apple Developer ID, so macOS packages cannot
   be signed/notarized — Gatekeeper will warn. (b) CI must stay self-contained
   (`dev-ci-self-contained`): packaging tools are pinned + checksummed, not pulled
   `latest`. (c) Linux packaging must run on titan (Gitea runner); macOS packaging
   must run on mutsu (only host with `pkgbuild`/`hdiutil`). (d) The bundled `.so`s
   must resolve at runtime regardless of the binary's rpath.
3. **Alternatives considered.**
   - deb/rpm: hand-written `debian/` + rpm `.spec` vs **nfpm** (one declarative YAML →
     both). nfpm chosen — far less boilerplate, reproducible, single pinned binary.
   - Portable Linux: **AppImage** vs Flatpak/Snap. AppImage chosen — single-file, no
     runtime/store dependency, matches "double-click and run". Flatpak/Snap add a
     store/runtime and sandbox model that fights a terminal browser; deferred.
   - macOS: `.pkg` (CLI installer to `/usr/local/bin`) vs `.app`+`.dmg` drag-install.
     A terminal browser is a CLI, not a windowed app, so a **`.pkg`** is the correct
     "proper install"; we wrap it in a **`.dmg`** for the familiar download artifact.
   - macOS signing: signed+notarized vs **unsigned**. No Developer ID exists, so
     unsigned with a documented Gatekeeper bypass; signing is a follow-up.
4. **Decision rationale.** Use one packaging script per OS family that consumes a
   payload dir + version and emits the native artifacts, so the same code path runs
   locally and in CI. Anchor the Linux install under `/usr/lib/carbonyl` with a
   `/usr/bin/carbonyl` wrapper that sets `LD_LIBRARY_PATH` — robust whether or not the
   binary carries an `$ORIGIN` rpath. macOS installs under `/usr/local/carbonyl` with
   a `/usr/local/bin/carbonyl` symlink created by a pkg postinstall script.
5. **Consequence assessment.** Users gain first-class installs on the major
   platforms. macOS users see a one-time "unidentified developer" prompt until a
   Developer ID is acquired. The release pipeline grows a Linux packaging step
   (titan) and consumes macOS installers produced on mutsu. Packaging tools added to
   the builder image keep CI self-contained.

## Decision

1. **deb + rpm** via **nfpm** (pinned, checksum-verified binary), one
   `packaging/nfpm.yaml`, built on titan in `release.yml`.
2. **AppImage** via **appimagetool** (pinned, checksum-verified, run with
   `APPIMAGE_EXTRACT_AND_RUN=1` — no FUSE in CI), built on titan.
3. **macOS `.pkg`** (`pkgbuild` + `productbuild`) wrapped in a **`.dmg`** (`hdiutil`),
   **unsigned**, built on mutsu and published to the `runtime-<hash>` release; staged
   into the versioned release by `release.yml` like the existing tarballs.
4. **Linux default package = headless** runtime (no X11 dependency). An `-x11`
   package may follow.
5. **Install layout:** Linux `/usr/lib/carbonyl` + `/usr/bin/carbonyl` wrapper
   (`LD_LIBRARY_PATH`); macOS `/usr/local/carbonyl` + `/usr/local/bin/carbonyl`
   symlink.
6. **Icon:** a generated placeholder ships now; replace with the real logo when
   available.

## Consequences

- **Positive:** native installs (`apt`/`dnf`/AppImage/macOS installer); removable via
  the package manager; consistent layout; one script per OS family reused in CI.
- **Negative / accepted:** macOS shows a Gatekeeper warning (unsigned) until a
  Developer ID is in place; the bypass is documented. Packaging adds CI surface and a
  mutsu publish step. The placeholder icon is not the final brand asset.
- **Follow-ups:** sign + notarize macOS (needs Developer ID); arm64-linux packages
  once #116 lands its runtime; optional `-x11` Linux package; optional apt/yum repo
  hosting.
