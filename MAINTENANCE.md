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
# One-time setup
python3 -m venv .venv
.venv/bin/pip install -r automation/requirements.txt

# Build local binary (downloads ~75MB Chromium runtime, builds Rust lib ~10s)
bash scripts/build-local.sh

# Test it
.venv/bin/python automation/browser.py search "duckduckgo test"
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

Chromium is currently at `120.0.6099.109` (M120, upgraded Apr 2026 from M111).
The target is M135. Updating it requires:

1. **Choose a new Chromium version**: check https://chromiumdash.appspot.com/releases
   for a stable branch release.

2. **Update `.gclient`**: change the `@111.0.5511.1` ref to the new version.

3. **Rebase patches**: the 21 Chromium patches + 2 Skia + 1 WebRTC need to apply
   cleanly on the new base. This is the hard part.

   ```bash
   # Sync Chromium source (requires depot_tools and ~100 GB disk)
   bash scripts/gclient.sh sync
   bash scripts/patches.sh apply   # will show conflicts if any
   ```

4. **Fix conflicts**: each patch in `chromium/patches/chromium/` touches
   Chromium internals for display routing and rendering. Conflicts are
   usually small — adjust line numbers, API changes.

5. **Rebuild runtime** (requires Docker, ~2 hours):
   ```bash
   bash scripts/docker-build.sh Default
   bash scripts/copy-binaries.sh Default
   ```

6. **Save updated patches**:
   ```bash
   bash scripts/patches.sh save
   git add chromium/patches/
   git commit -m "chore(chromium): update to M<version>"
   ```

7. **Upload new runtime** (optional — makes `build-local.sh` fast for others):
   ```bash
   CDN_ACCESS_KEY_ID=... CDN_SECRET_ACCESS_KEY=... bash scripts/runtime-push.sh Default
   ```

### Patch reference commits

The `scripts/patches.sh` script uses hardcoded upstream base commits:

| Repo | Base commit | Chromium version |
|------|-------------|-----------------|
| Chromium | `92da8189788b1b373cbd3348f73d695dfdc521b6` | M111 (current) |
| Skia | `486deb23bc2a4d3d09c66fef52c2ad64d8b4f761` | M111 (current) |
| WebRTC | `727080cbacd58a2f303ed8a03f0264fe1493e47a` | M111 (current) |

**M135 target commits** (update `scripts/patches.sh` when rebasing to M135):

| Repo | Base commit | Source |
|------|-------------|--------|
| Skia | `6e445bdea696eb6b6a46681dfc1a63edaa517edb` | DEPS @ 135.0.7049.84 |
| WebRTC | `9e5db68b15087eccd8d2493b4e8539c1657e0f75` | DEPS @ 135.0.7049.84 |

When updating Chromium, update these to the new Chromium's third-party base
commits before running `patches.sh apply`.

### Patch 07 re-anchor (M135)

Patch 07 (`Disable-text-effects.patch`) currently targets:
- `third_party/blink/renderer/core/paint/ng/ng_text_painter_base.cc`

In M135, the `ng/` subdirectory was dissolved (~M120). The `ng_text_painter_base.cc` file
was merged into `third_party/blink/renderer/core/paint/text_painter_base.cc`, then further
consolidated. In M135, only `text_painter.cc` and `painter_base.cc` exist in that directory.

**Action before Phase 1:** Confirm which M135 file contains `PaintUnderOrOverLineDecorations`
(likely `text_painter.cc`) and re-target the patch accordingly.

### Patch 13 rewrite context (M135)

Patch 13 (`Refactor-rendering-bridge.patch`) creates `software_output_device_proxy.cc` which
uses the `LayeredWindowUpdater` Mojo interface (removed ~M137) for shared-memory pixel capture.

In M135, the hook point is `components/viz/service/display_embedder/software_output_device_ozone.cc`.
The `SoftwareOutputDeviceOzone` class interface:

```cpp
class SoftwareOutputDeviceOzone : public SoftwareOutputDevice {
  SoftwareOutputDeviceOzone(std::unique_ptr<ui::PlatformWindowSurface>,
                             std::unique_ptr<ui::SurfaceOzoneCanvas>);
  SkCanvas* BeginPaint(const gfx::Rect& damage_rect);
  void EndPaint();
  void Resize(const gfx::Size& viewport_pixel_size, float scale_factor);
  void OnSwapBuffers(SwapBuffersCallback, gfx::FrameData data);
};
```

Rewrite strategy: subclass `SoftwareOutputDeviceOzone` and override `EndPaint()` to
intercept the rendered `SkCanvas` pixels via `SkCanvas::readPixels()` into a shared memory
buffer, then signal the Carbonyl Rust bridge.

## Automation Layer

`automation/browser.py` uses the local binary when present, Docker otherwise:

- **Local binary**: `build/pre-built/<triple>/carbonyl` (set by `build-local.sh`)
- **Docker fallback**: `fathyb/carbonyl` image

The automation is consumed by agent testing loops:

```python
from automation.browser import search_duckduckgo, CarbonylBrowser

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
