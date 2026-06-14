# Carbonyl v0.2.0-alpha.3

**Trusted automation Phase 0 — visual capture and CI hardening.**

Two-week burst on top of `v0.2.0-alpha.1` (M147). Adds the visual-capture
half of the trusted-automation pipeline, separates the per-ozone runtime
release lanes, hardens CI inside a pinned builder container, and ships
the supporting workflows (mirror, release, dual-output validation).

`v0.2.0-alpha.2` was tagged on 2026-04-17 with one viewport fix but
never published as a release; the change is rolled into this one.

---

## Highlights

### X-mirror — second output surface, single Chromium process

`CARBONYL_X_MIRROR=1` makes the `ozone_platform=x11` variant *also* blit
each compositor frame into a real X window via `XPutImage`, alongside
the existing terminal render. External tooling (`scrot`, `ffmpeg`,
`x11vnc`) can capture the same pixels Chromium drew, while the
trusted-input pipeline and ANSI-quadrant terminal output stay
unchanged. Single process, single TLS context, single JS realm —
fingerprint coherence is preserved.

- Implementation: `src/browser/x_mirror.{h,cc}` + a small splice into
  `host_display_client.cc`. ~200 LOC, all in the Carbonyl-owned tree.
  Xlib confined to one translation unit so its global-namespace macros
  don't pollute the rest of the codebase.
- Gated off by default; headless deployments pay zero runtime cost
  beyond the link.
- Three deployment modes are now formally supported: terminal-only,
  x11 + uinput trusted input, x11 + uinput + X-mirror. Operator
  reference: `docs/runtime-modes.md`.

Refs: `jmagly/carbonyl#63`.

### Per-ozone runtime release lanes

Headless and x11 runtime variants now publish to distinct Gitea
release tags so they can coexist:

- `runtime-<hash>` — headless variant (preserves the historical tag
  shape; existing consumers unaffected)
- `runtime-x11-<hash>` — x11 variant (with x_mirror compiled in)

`runtime-pull.sh` and `runtime-push.sh` both gained an explicit
`--ozone=…` flag; the `CARBONYL_OZONE_TAG` env var still works for
CI. Closes a silent-clobber bug where the second variant to upload
would overwrite the first at the same release tag.

Refs: `jmagly/carbonyl#64`.

### Dual-output validation harness

`scripts/test-x-mirror.sh` exercises both rendering pipelines from a
single Carbonyl process and asserts on both surfaces simultaneously:

- Terminal stream — ≥50 Unicode quadrant block runs and 24-bit ANSI
  SGR escapes for the fixture's signature colours
- X framebuffer — `scrot` pixel histogram crossing minimum coverage
  thresholds for the same colours

Wired into `build-runtime.yml` as a post-publish step on every x11
build (commit `eee943d`); a regression in either pipeline now blocks
the release.

### CI runs in a pinned container, end-to-end

- `Dockerfile.builder` pins Rust to `1.91.0` via a `RUST_VERSION`
  build-arg; toolchain drift no longer leaks in from titan's host
  rustup channel.
- New `rust-toolchain.toml` at repo root mirrors the pin so local dev
  matches CI.
- `check.yml` migrated into the builder container with `--user`
  mapping so CI no longer leaves root-owned artifacts in the
  workspace. Closes `#50`.
- `cargo clippy -- -D warnings` is now actually green: 54 pre-existing
  lints (mix of real bugs like `write` → `write_all`, missing
  `# Safety` docs on `unsafe fn`, and style noise) cleared in
  `7458695`. Crate-wide `#![allow]` for the few intentional
  conventions (identity-op for visual alignment, FFI raw pointers).

### New CI workflows

- **`mirror.yml`** — automatic `origin → github` mirror on push to
  `main` and on `v*` tag push. `--force-with-lease` only; tokens never
  land in `git config`. Closes `#53`.
- **`release.yml`** — on `v*` tag, pulls the matching `runtime-<hash>`
  release, repackages as `carbonyl-<version>-<triple>.tgz` with a
  `.sha256` companion, creates Gitea + GitHub releases with
  `RELEASE-<tag>.md` as the body. Hard rule: never rebuilds Chromium;
  fails loudly if the runtime release is absent. Closes `#52`.

### Documentation

- `docs/runtime-modes.md` — operator reference covering the three
  deployment shapes, full CLI flag + env var matrix, session
  portability rules across modes.
- `docs/ci-secrets.md` — secrets inventory, 90-day rotation procedure,
  scope principles, and a leak-response playbook. Closes `#54`.
- `docs/ci-runner-titan.md` — host runbook with directory layout,
  bootstrap procedure, cache invalidation, security posture. Closes
  `#55`.

### Cleanup

- `automation/` Python tree (2,283 LOC, 6 files) deleted. The
  automation layer lives in
  [`jmagly/carbonyl-agent`](https://github.com/jmagly/carbonyl-agent)
  via `pip install carbonyl-agent`. Doc references across
  `MAINTENANCE.md`, `docs/development-guide.md`, and
  `scripts/build-local.sh` updated to point at the package. Closes
  `#36` and `#25`.

### From v0.2.0-alpha.2 (rolled in)

- `--viewport=WxH` / `CARBONYL_VIEWPORT` — explicit CSS viewport
  override; the terminal samples a `cells * (2, 4)` window of the
  resulting raster. Use for reproducible layout independent of
  terminal size. Closes the open part of `#37`.

---

## Downloads

### Runtime tarball

| Variant | Tarball | Triple |
|---|---|---|
| Headless (terminal-only) | `carbonyl-0.2.0-alpha.3-x86_64-unknown-linux-gnu.tgz` | `x86_64-unknown-linux-gnu` |
| x11 (with X-mirror) | `carbonyl-0.2.0-alpha.3-x11-x86_64-unknown-linux-gnu.tgz` | `x86_64-unknown-linux-gnu` |

Both have a `.sha256` companion file as a release asset.

### Recommended install (via carbonyl-agent)

```bash
pip install carbonyl-agent
carbonyl-agent install
```

For the x11 variant (visual capture or trusted-input automation):

```bash
bash scripts/runtime-pull.sh --ozone=x11
```

---

## Verification

- `ninja headless:headless_shell`: green for both ozone variants
- `cargo clippy --target x86_64-unknown-linux-gnu -- -D warnings`: green
- `scripts/test-b64-text.sh`: 3/3 pass on M147
- `scripts/test-x-mirror.sh`: terminal + X framebuffer both pass against
  `tests/fixtures/x-mirror.html`

---

## Closed issues in this release

`carbonyl`: #25, #36, #46, #50, #52, #53, #54, #55, #56, #57, #63, #64

`carbonyl-agent`: #37

---

## Known limitations (unchanged from alpha.1)

- Linux x86_64 only — arm64 + macOS not yet rebuilt on M147
- Binary not stripped (~3 GB with debug symbols)
- Fullscreen mode not supported
- `--viewport` is opt-in; without it the terminal-derived legacy
  viewport is used (kept for backward compatibility)

---

## What's next

- **Phase 1 — Trusted input wired into real automation** flows (the
  uinput emitter productionised in `carbonyl-agent#36`)
- **W0.6 text-render parity** (`#62`) — comparison fixture across the
  two ozone variants
- **carbonyl-agent v0.1 PyPI publish** (release-blockers tracked in
  the `carbonyl-agent` repo)
