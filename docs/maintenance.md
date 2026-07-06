# Carbonyl Maintenance Guide

Carbonyl upstream (`fathyb/carbonyl`) has been inactive since February 2023.
This fork maintains it for use in automated agent testing pipelines.

## Build Architecture

Carbonyl is two pieces:

| Component | Build time | When to rebuild |
|-----------|-----------|-----------------|
| **Chromium runtime** (`headless_shell` + libs) | 1–3 hours via Docker | Chromium version bump, patch changes |
| **`libcarbonyl.so`** (Rust library) | ~10 seconds via cargo | Any Rust code change |

For day-to-day development, only the Rust library needs rebuilding. The
Chromium runtime is downloaded once and cached.

## Quick Start

```bash
# One-time setup — Python automation lives in carbonyl-agent now
python3 -m venv .venv
.venv/bin/pip install carbonyl-agent

# Build local binary (downloads ~75MB Chromium runtime, builds Rust lib ~10s)
bash scripts/build-local.sh

# Test it
.venv/bin/carbonyl-agent search "duckduckgo test"
```

## Keeping Dependencies Current

### Rust crates (easy — do this regularly)

```bash
source ~/.cargo/env
cargo update            # update Cargo.lock to latest compatible versions
cargo test --lib        # confirm nothing broke
git add Cargo.lock
git commit -m "chore(deps): update Rust crate lockfile"
```

To bump a specific crate to a new major version, edit `Cargo.toml` then run
`cargo update`.

### Chromium version (involved — do when security patches are needed)

Chromium is currently at `150.0.7871.47` (M150, upgraded July 2026 from M148).
The upgrade path was: M111 → M120 → M132 → M135 → M140 → M147 → M148 → M150. Updating it requires:

1. **Choose a new Chromium version**: check https://chromiumdash.appspot.com/releases
   for a stable branch release.

2. **Update `.gclient`**: change the `@<version>` ref and set `"managed": False`.
   Then manually check out the tag before syncing:
   ```bash
   git -C chromium/src fetch origin refs/tags/<version>
   git -C chromium/src checkout <version>
   bash scripts/gclient.sh sync
   chromium_upstream=$(git -C chromium/src rev-parse HEAD)
   ```

3. **Update `scripts/patches.sh`**: set `chromium_upstream`, `skia_upstream`,
   and `webrtc_upstream` to the new base commits. Get skia/webrtc from DEPS:
   ```bash
   python3 -c "exec(open('chromium/src/DEPS').read()); print(vars['skia_revision'])"
   python3 -c "exec(open('chromium/src/DEPS').read()); print(vars['webrtc_revision'])"
   ```

4. **Rebase patches** using `--3way` (plain `git am` will fail on context drift):
   ```bash
   bash scripts/patches.sh apply   # fails on first conflict
   # then for each conflict:
   git am --abort
   git am --3way --committer-date-is-author-date chromium/patches/chromium/000N-*.patch
   # resolve conflict markers, git add, git am --continue
   ```
   Common conflict patterns to expect:
   - `//build:chromeos_buildflags` removed in M120+ — drop from patch diffs
   - `headless_screen.{h,cc}`: M135 switched to `HeadlessScreenInfo` multi-display
     constructor — keep M135 signature, inject `Bridge::GetDPI()` into new path
   - `compositor.h`: M135 added `ExternalBeginFrameControllerClientFactory` — keep both
   - `layer_tree_host.h`: M135 added `PropertyTreeDelegate` — keep both fields

5. **Verify cross-layer dependencies** after patching:
   ```bash
   bash scripts/audit-cross-layer.sh
   ```
   This checks that `//carbonyl/src/blink:text_capture` visibility and the
   symlink structure are intact. Fix any reported issues before building.

6. **Rebuild runtime** (requires Docker, ~2 hours):
   ```bash
   bash scripts/docker-build.sh Default
   bash scripts/copy-binaries.sh Default
   ```

7. **Save updated patches**:
   ```bash
   bash scripts/patches.sh save
   git add chromium/patches/ scripts/patches.sh chromium/.gclient
   git commit -m "chore(chromium): rebase patches on M<version> (<version>)"
   ```

8. **Upload new runtime** to the release page (makes `build-local.sh` fast for others):

   Runtimes are distributed as release assets on `roctinam/carbonyl`. Each release is
   tagged `runtime-<hash>` where the hash is computed from the Chromium version, patches,
   and bridge files. Run for each target platform:

   ```bash
   # linux/amd64 (run on the build host after docker-build.sh)
   GITEA_TOKEN=<token> bash scripts/runtime-push.sh

   # linux/arm64 (built in the mutsu Colima profile)
   GITEA_TOKEN=<token> bash scripts/mutsu-build-linux-arm64.sh --publish

   # macos/amd64 and macos/arm64 (run on a Mac after docker-build.sh)
   GITEA_TOKEN=<token> bash scripts/runtime-push.sh
   GITEA_TOKEN=<token> bash scripts/runtime-push.sh arm64
   ```

   The upload token must have release-write scope on `roctinam/carbonyl`.
   If the tarball exceeds a server-side upload limit, adjust the limit in the
   hosting platform's configuration.

   For release cuts, `release.yml` validates every requested runtime asset
   before staging and runs `scripts/verify-release-asset-version.sh` for native
   Linux x86_64 tarballs, failing the release if the semantic release tag and
   `carbonyl --version` disagree. Set `include_linux_arm64=true` only after
   `runtime-<hash>/aarch64-unknown-linux-gnu.tgz` exists for the tag's runtime
   hash.

### Patch reference commits

The `scripts/patches.sh` script uses hardcoded upstream base commits (current: M150):

| Repo | Base commit | Chromium version |
|------|-------------|-----------------|
| Chromium | `0c3cca15d78645281db2d339b2dc3d6fad4ee90a` | M150 (150.0.7871.47) |
| Skia | `14d05ec761901b6e9e9193af8b347ab3a7f6fed0` | DEPS @ 150.0.7871.47 |
| WebRTC | `1f975dfd761af6e5d76d28333191973b258d82a8` | DEPS @ 150.0.7871.47 |

When updating Chromium, update all three to the new version's base commits
before running `patches.sh apply`.

### Notes on current patch set (M150)

- **Total patches**: 35. The M150 rebase regenerates the Chromium patch stack
  against `150.0.7871.47`.

- **Rebase changes baked into existing patches**:
  - `text_decoration_painter.cc` and `ui/gfx/render_text.cc`: underline,
    overline, and strike drawing remain disabled while preserving the M150 text
    decoration API shape.
  - `headless_browser_impl.h`: keeps M150's browser declarations while retaining
    the Carbonyl bridge hooks and input thread.
  - Blink `BUILD.gn` targets were refreshed for M150's target layout while
    preserving the `//carbonyl/src/blink:text_capture` dependency path.
  - `third_party/blink/renderer/platform/BUILD.gn`: the stale
    `//carbonyl/src/browser:blink` dependency remains removed.
  - `src/browser/args.gn`: stale M150 GN args were removed
    (`enable_nacl`, `enable_system_notifications`, `use_vaapi_x11`), and the
    old `use_qt` switch is now `use_qt5 = false` plus `use_qt6 = false`.

- **Patch 35** (`fix-m150-add-logging-include-for-viz-proxy`): adds
  `base/logging.h` to `software_output_device_proxy.cc` so the restored viz
  proxy compiles with M150's include graph.

- **CI/runtime verification**: PR #269 is green at `95c3cc7`. Check/Lint,
  Security, and Validate Patches passed on runs 585-587. The amd64 runtime
  matrix passed for both headless and x11 on run 583, publishing runtime hash
  `027cf47450dc6ce9`. Text-render parity passed on run 588 for `static.html`,
  `css-rich.html`, and `dynamic.html` using the same runtime hash.

- **Patch 22** (`fix-m135-remove-stale-blink-target-dep`): removes a stale
  `:blink` GN dep from `blink/renderer/platform/BUILD.gn` (artifact of patch
  0012/0013 mismatch — patch 0013 reverted source changes but left the dep)
- **Patch 23** (`fix-m135-Path-B-build-fixes-disable-b64-text-capture`):
  surgical M135 build fixes — restores `Dispose()` definition and fixes API
  drift. The b64 text-capture disable was superseded by patch 0024.
- **Patch 24** (`fix-chromium-Path-A-allow-carbonyl-src-blink-to-depend`):
  grants `//carbonyl/src/blink:text_capture` visibility into blink GN targets,
  enabling the Path A structural fix that restores `--carbonyl-b64-text`.
- **Patch 25/26**: carry the M148 follow-up adjustments for compositor/debug
  dump drift and terminal-render paint flow. Keep these separate until the next
  audit decides whether they should be folded into their originating patches.

- **Patch 03** (`Setup-shared-software-rendering-surface`): removes `[EnableIf=is_win]`
  guard from `CreateLayeredWindowUpdater` in `display_private.mojom`, making it
  cross-platform. Also changes `Draw()` → `Draw(gfx.mojom.Rect damage_rect)`.

- **Patch 13** (`Refactor-rendering-bridge`): restores `software_output_device_proxy.cc/h`
  into `components/viz/service/display_embedder/` (upstream removed it in M135).
  The `LayeredWindowUpdater` Mojo interface is still present in M135. Updated
  for the M135 `CreatePlatformCanvasWithPixels` signature (added `bytes_per_row`
  parameter).

- **`carbonyl/src/viz/`**: `CarbonylSoftwareOutputDevice` is a Carbonyl-owned copy
  of the former upstream proxy class, kept for future use if the Mojo path is ever
  replaced (e.g. M137+ removes `LayeredWindowUpdater`).

- **Skia/WebRTC patches**: none needed at M135. The two former Skia patches
  (disable text rendering, export private APIs) were superseded during the M120
  rebase; WebRTC's GIO patch was rendered unnecessary by `rtc_use_pipewire=false`.

### Path A and the `//carbonyl/src/blink:text_capture` source set

The `--carbonyl-b64-text` text-capture mode is **restored** in M135 builds
via Path A ([#28](https://github.com/jmagly/carbonyl/issues/28),
landed in `61b9095`).

**Background**: The b64 text-capture path originally lived in
`content/renderer/render_frame_impl.cc` (a non-blink TU). In M135, including
`third_party/blink/renderer/core/*` headers from there triggers an
Oilpan/cppgc template cascade that hard-errors on `sizeof(void)`. Path B
(patch 23, [#27](https://github.com/jmagly/carbonyl/issues/27))
temporarily `#if 0`'d the entire text-capture block while Path A was developed.

**Path A solution**: The text-capture code was extracted into a dedicated blink
TU under `src/blink/` in the carbonyl repo:

| File | Purpose |
|------|---------|
| `src/blink/text_capture.h` | Public entry point — `carbonyl::TextCapture::Install()` |
| `src/blink/text_capture.cc` | Implementation — hooks `LayerTreeHost` for glyph capture |
| `src/blink/BUILD.gn` | Declares `//carbonyl/src/blink:text_capture` source set |

These files are symlinked into `chromium/src/carbonyl/src/blink/` during
builds. The source set is compiled with `INSIDE_BLINK` naturally (it depends
on blink targets), so the cppgc cascade vanishes. The content-side call site
in `render_frame_impl.cc` is now a thin call into
`carbonyl::TextCapture::Install()`.

Patch 0024 grants `//carbonyl/src/blink:text_capture` visibility into the
relevant blink GN targets (`blink/renderer/core`, `blink/renderer/platform`,
etc.).

**What to watch during rebases**:
- If blink reorganizes `inside_blink` config or `blink/renderer/core/BUILD.gn`
  visibility rules, patch 0024 may need updating.
- Run `scripts/audit-cross-layer.sh` after every rebase to verify that the
  cross-layer dependency graph is still valid.
- The symlink from `chromium/src/carbonyl/src/blink/` into the repo's
  `src/blink/` must be intact — `scripts/patches.sh apply` handles this.

**For maintainers**: Path A is the gating dependency for any Chromium rebase
past M135. If the blink GN target structure changes significantly in a future
milestone, the `text_capture` source set may need to be relocated — but the
pattern (dedicated blink TU for non-blink consumers) is the correct long-term
approach.

### GN args notes (M150)

Several feature flags are intentionally **left at their platform defaults**
(typically `true` on Linux) instead of being explicitly set to `false`:

- `enable_screen_ai_service`
- `enable_speech_service`
- `enable_pdf` / `enable_printing`
- `enable_plugins` / `enable_tagged_pdf`
- `enable_browser_speech_service`
- `enable_webui_certificate_viewer`

Setting any of these to `false` in `args.gn` triggers file-level `assert()`
failures in `chrome/test/BUILD.gn` during `gn gen`, because M135+'s
`gn_all` group transitively pulls those service BUILD.gn files into the
evaluation graph even though headless_shell never compiles their targets.
The features are not built into headless_shell either way (it has its own
if-guards on dependent targets).

**Removed from args.gn**: `enable_component_updater` (M135), `enable_nacl`
(M140), plus M150's stale `enable_system_notifications`, `use_vaapi_x11`, and
single `use_qt` switches no longer exist as used here. Setting them produces
"not declared in any declare_args block" warnings.

## Automation Layer

The Python automation layer was extracted into `jmagly/carbonyl-agent`
as the `carbonyl-agent` PyPI package. Binary discovery order (in the
package's `browser.py`):

1. `CARBONYL_BIN` env var (explicit override)
2. `~/.local/share/carbonyl/bin/<triple>/carbonyl` (installed via
   `carbonyl-agent install`)
3. `carbonyl` on `$PATH` (system-wide install)
4. `build/pre-built/<triple>/carbonyl` (local dev — set by
   `scripts/build-local.sh` in this repo)
5. Docker fallback: `fathyb/carbonyl`

The automation is consumed by agent testing loops:

```python
from carbonyl_agent import CarbonylBrowser, search_duckduckgo

# Search and get clean text back
results = search_duckduckgo("rust async runtime")

# Full control
b = CarbonylBrowser()
b.open("https://news.ycombinator.com")
b.drain(8.0)
text = b.page_text()
b.close()
```

## Threat Model for H.264

`src/browser/args.gn` sets `proprietary_codecs = true` and
`ffmpeg_branding = "Chrome"`, enabling H.264 (AVC). This is inherited from
the upstream project.

For internal/personal use this is fine. For commercial redistribution,
an MPEG-LA license is required or replace with AV1/VP9 (`enable_h264 = false`).

## CI Summary

| Job | What it does |
|-----|-------------|
| `check` | `cargo check` + `cargo clippy` (fast, no linking) |
| `test` | `cargo test --lib` |
| `build-local` | Downloads runtime, builds Rust lib, smoke tests, uploads artifact |

CI infrastructure references:
- [`docs/ci-cd-plan.md`](docs/ci-cd-plan.md) — pipeline architecture
- [`docs/ci-runner-titan.md`](docs/ci-runner-titan.md) — host state runbook
- [`docs/ci-secrets.md`](docs/ci-secrets.md) — secrets inventory, rotation, leak response
