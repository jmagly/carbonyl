# Carbonyl v0.2.0-alpha.1

**First alpha release of the `jmagly/carbonyl` fork.**

This release covers the full journey from M111 (upstream carbonyl v0.0.3, Feb 2023) to current upstream stable Chromium M147 (147.0.7727.94). It also ships the companion projects that consume Carbonyl at the automation-SDK and fleet layers.

---

## Highlights

### Chromium upgraded to M147 (from M111)

Six-phase rebase brought the fork from a 3-year-old Chromium base to current upstream stable:

| Phase | From → To | Commit |
|-------|-----------|--------|
| 1 | M111 → M120 | `88d2d4d` |
| 2 | M120 → M132 | `2293579` |
| 3 | M132 → M135 | `c40955f` |
| 4 | M135 → M140 | `5f165fe` |
| 5 | M140 → M147 | `58e50bd` |

Final patch count: **24** (was 21 at M132, +3 for M135-era structural fixes). Current runtime built on `147.0.7727.94`.

### Structural fix for cppgc cascade

Path A (commit `61b9095`) extracts the `--carbonyl-b64-text` text-capture path into a dedicated Blink translation unit (`//carbonyl/src/blink:text_capture`). This resolves the M135-era Oilpan/cppgc template cascade that would have gated every future rebase past M135.

### Smoke test for `--carbonyl-b64-text`

`scripts/test-b64-text.sh` runs an end-to-end test using a deterministic HTML fixture, PTY capture, and 3-string assertions against rendered terminal output. Passes 3/3 on M147 with no cppgc/Oilpan failures in stderr.

### Companion repositories

Two sibling projects consume this runtime:

- **[carbonyl-agent](https://github.com/jmagly/carbonyl-agent)** — Python automation SDK (`pip install carbonyl-agent`). Session persistence, daemon mode, screen inspection, bot-detection evasion.
- **[carbonyl-fleet](https://github.com/jmagly/carbonyl-fleet)** — Rust fleet server for N concurrent browsers. gRPC + REST + Python SDK. Argon2id auth, snapshot integrity, cgroup wrapping.

### CI infrastructure

- `cargo check` / `clippy` / library tests on push
- Full Chromium build + runtime upload via a manual workflow
- `scripts/audit-cross-layer.sh` — cross-layer dependency audit run after every rebase
- `scripts/test-b64-text.sh` — b64 text-capture smoke test wired into the runtime build pipeline

### Runtime distribution

Runtime tarballs are published as GitHub release assets. The upstream CDN (`carbonyl.fathy.fr`) is no longer used. `scripts/runtime-pull.sh` and `carbonyl-agent install` fetch from the release asset URL.

---

## Downloads

### Runtime tarball (pre-built)

Users who just want to **run** Carbonyl do not need to build from source. The runtime tarball includes the pre-built `headless_shell`, shared libraries, and `libcarbonyl.so`.

- **x86_64-unknown-linux-gnu**: `carbonyl-0.2.0-alpha.1-x86_64-unknown-linux-gnu.tgz` (259 MB) — attached to this release.
  - SHA256: `02fc43dc383fd79c54c4c320d273dcc1c48d640a1081b39b3c82017267018848`

### Recommended install (via carbonyl-agent)

```bash
pip install carbonyl-agent
carbonyl-agent install
```

This pulls the same runtime tarball, verifies its SHA256, and installs it under `~/.local/share/carbonyl/bin/<triple>/`.

---

## What's in the tarball

```
x86_64-unknown-linux-gnu/
├── carbonyl              # ~3 GB binary (debug+symbols, linked with libcarbonyl.so)
├── libcarbonyl.so        # Rust core library
├── libEGL.so             # ANGLE
├── libGLESv2.so          # ANGLE
├── icudtl.dat            # ICU data
└── v8_context_snapshot.bin
```

---

## Known limitations

- **Linux x86_64 only** for this alpha — arm64 and macOS runtimes not yet rebuilt on M147. Tracked for v0.2.0 stable.
- Binary is not stripped — 3 GB with debug symbols. Strip locally if distribution size matters.
- Fullscreen mode not supported (upstream carbonyl limitation).
- `enable_nacl` warning during `gn gen` (GN arg removed in M140, harmless).

---

## Breaking changes from upstream v0.0.3

- **Runtime distribution moved from `carbonyl.fathy.fr` to release assets.** Old CDN URLs will 404. Use `carbonyl-agent install` or pull the tarball attached to this release.
- **Python automation layer extracted** to the standalone `carbonyl-agent` package. The legacy `automation/` directory in this repo still works for backward compatibility but is slated for removal. New code should `pip install carbonyl-agent` and use the standalone SDK.

---

## Upgrading from older fork snapshots

If you were pulling a runtime from a pre-v0.2.0 state:

```bash
# Delete the old runtime dir to force a fresh download
rm -rf ~/.local/share/carbonyl/bin

# Pull fresh
pip install --upgrade carbonyl-agent
carbonyl-agent install
```

---

## Verification

- **`ninja headless:headless_shell`**: 2775/2775 targets, clean build
- **`cargo test --lib`**: green
- **`scripts/test-b64-text.sh`**: 3/3 pass
- **`scripts/audit-cross-layer.sh`**: Category A findings remain inert (inside `#if 0` blocks, no active cppgc cascade)
- **USPS PO Box smoke test**: pass (real-world login + SSO flow, verified via carbonyl-agent on 2026-04-15)

---

## Acknowledgments

Built on top of [Carbonyl](https://github.com/fathyb/carbonyl) by Fathy Boundjadj. The M111→M147 rebase path drew on [CEF](https://github.com/chromiumembedded/cef)'s `blink_glue.cc` pattern for the Path A structural fix. Thanks to the Chromium cppgc/Oilpan maintainers for the template machinery underlying the Path A diagnosis.

Sponsors: [Roko Network](https://roko.network), [Selfient](https://selfient.xyz), [Integro Labs](https://integrolabs.io).

---

## What's next

- **v0.2.0** stable — arm64 and macOS runtimes added, companion issue cleanup
- **Rolling rebases** — track upstream Chromium stable within one milestone going forward
- **CI automation** — automated releases from tag push
- **carbonyl-agent v0.3** — documented in its own CHANGELOG
