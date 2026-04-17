# Rust ↔ Chromium boundary and rebuild guide

Where code lives, how the two sides communicate, and what to rebuild when you change something. If you only read one doc before touching Carbonyl internals, this is it.

Related:
- [chromium-integration.md](chromium-integration.md) — detailed catalog of every Carbonyl-specific modification to Chromium (patches, injected sources, FFI entries). This doc is the map; that one is the reference.
- [MAINTENANCE.md](../MAINTENANCE.md) — Chromium version upgrade procedure (infrequent but expensive).
- [development-guide.md](development-guide.md) — general contributor onboarding (prereqs, repo layout, dev workflow).

---

## The three layers

```
┌─────────────────────────────────────────────────────────────────┐
│                          Rust crate                             │
│  (src/, Cargo.toml → libcarbonyl.so)                            │
│  Terminal renderer, input loop, CLI, Window sizing, FFI exports │
└──────────┬──────────────────────────────────────────┬───────────┘
           │                                          │
           │  extern "C" functions                    │  static calls
           │  (Chromium → Rust)                       │  (Rust → Chromium)
           │  carbonyl_renderer_get_size              │  carbonyl::Bridge::GetDPI
           │  carbonyl_renderer_draw_bitmap           │  (never used directly
           │  carbonyl_bridge_get_dpi                 │   from Rust today —
           │  carbonyl_renderer_listen, ...           │   Chromium-internal only)
           │                                          │
┌──────────▼──────────────────────────────────────────▼───────────┐
│                Injected Carbonyl C++ source                     │
│  (src/browser/, lives at chromium/src/carbonyl/src/browser/     │
│   via build/ scripts — net-new files, not patches)              │
│                                                                 │
│   • bridge.{h,cc}       Static DPI / bitmap-mode singleton      │
│   • renderer.{h,cc}     Declares the Rust FFI, wraps the opaque │
│                         carbonyl_renderer* handle, exposes      │
│                         Renderer::GetCurrent()->DrawBitmap etc. │
│   • host_display_client Mojo LayeredWindowUpdater → DrawBitmap  │
│   • render_service_impl Mojo service wiring                     │
│   • carbonyl.mojom      Mojo interface definitions              │
│   • bridge.rs           (Rust lives here too, compiled via      │
│                          build.rs into libcarbonyl.so)          │
└──────────┬──────────────────────────────────────────────────────┘
           │ includes, static calls, ODR-linkage
┌──────────▼──────────────────────────────────────────────────────┐
│                   Upstream Chromium (patched)                   │
│  (chromium/src/, patched via chromium/patches/chromium/*.patch) │
│                                                                 │
│   • ui/display/display.cc         ← DSF override (patch 0006)   │
│   • headless/**                   ← display setup (0006, 0013)  │
│   • components/viz/service/**     ← compositor output (0013,    │
│                                     +the #37 Option C fix)      │
│   • third_party/blink/renderer/** ← font override (0008),       │
│                                     decoration disable (0007)   │
│   • 20+ other files across 24 .patch files                      │
└─────────────────────────────────────────────────────────────────┘
```

Key mental model: **the final `carbonyl` binary is a patched Chromium `headless_shell` that `dlopen`s `libcarbonyl.so` at process start.** The two communicate via a stable C ABI declared in `src/browser/renderer.cc` (for "Chromium calls Rust") and the `carbonyl::Bridge` / `carbonyl::Renderer` C++ classes (for "Rust already exited; Chromium code now uses Carbonyl state it inherited").

---

## Where each thing lives

### Source

| What | Path | Owner |
|------|------|-------|
| Rust runtime source | `src/**/*.rs` | Carbonyl |
| Rust FFI exports | `src/browser/bridge.rs` | Carbonyl |
| Injected C++ source | `src/browser/*.{h,cc,mojom}`, `src/browser/BUILD.gn`, `src/browser/args.gn` | Carbonyl |
| Dead-code C++ stubs (prepared for future M-version) | `src/viz/carbonyl_software_output_device.{h,cc}` | Carbonyl (not wired in) |
| Chromium patches | `chromium/patches/chromium/*.patch` | Carbonyl (applied to upstream) |
| Upstream Chromium | `chromium/src/` | Google, patched on sync |
| Injected C++ inside Chromium tree | `chromium/src/carbonyl/` | Mirrored from `src/browser/` by build |

### Build artifacts

| What | Path | Size | Produced by |
|------|------|------|-------------|
| Rust lib (debug) | `build/x86_64-unknown-linux-gnu/debug/libcarbonyl.so` | ~8 MB | `cargo build` |
| Rust lib (release) | `build/x86_64-unknown-linux-gnu/release/libcarbonyl.so` | ~800 KB | `cargo build --release` |
| Raw Chromium binary | `chromium/src/out/Default/headless_shell` | ~3.5 GB debug / ~200 MB release | `ninja -C chromium/src/out/Default headless:headless_shell` |
| Install layout | `build/pre-built/x86_64-unknown-linux-gnu/{carbonyl,libcarbonyl.so,icudtl.dat,libEGL.so,libGLESv2.so,v8_context_snapshot.bin}` | ~1 GB | `scripts/copy-binaries.sh` |
| Packaged runtime | `build/x86_64-unknown-linux-gnu.tgz` and the `carbonyl-VERSION-...tgz` alongside | ~75 MB (release, stripped) | `scripts/build.sh` or release pipeline |

The `build/pre-built/...` directory is what `carbonyl-agent install` populates on a consumer machine. When you want to test a change locally, update the file in `build/pre-built/.../` and any `carbonyl` invocation pointed at that directory picks it up.

### The three `libcarbonyl.so` copies that matter

Keep these in sync or you'll chase ghosts:

1. `build/{triple}/release/libcarbonyl.so` — what `cargo build --release` produces. Source of truth after a Rust rebuild.
2. `chromium/src/out/Default/libcarbonyl.so` — what Chromium's `headless_shell` dlopens at runtime when launched from the build tree. `scripts/build.sh` copies (1) → here.
3. `build/pre-built/{triple}/libcarbonyl.so` — what consumers run. `scripts/copy-binaries.sh` copies (1) → here, alongside the renamed `headless_shell`.

A Rust edit that forgets any of these three copies gets you behaviour from the stale one. See "Verification" below.

---

## The FFI boundary

Full catalog in [chromium-integration.md § FFI contract](chromium-integration.md#ffi-contract). Quick orientation here.

### Direction 1: Chromium → Rust (Chromium calls into libcarbonyl)

Functions declared `extern "C"` in `src/browser/bridge.rs`, consumed by `src/browser/renderer.cc` (which re-declares them as `extern "C"` at the top of the file to see them):

- `carbonyl_bridge_main` — Chromium entry point; blocks until Rust decides the process should continue as the browser.
- `carbonyl_bridge_bitmap_mode` / `carbonyl_bridge_get_dpi` — static singletons read once at Chromium startup via `Bridge::Configure`.
- `carbonyl_renderer_create` — allocates the opaque `carbonyl_renderer*` handle (actually `Box<Arc<Mutex<RendererBridge>>>` on the Rust side).
- `carbonyl_renderer_start`, `_resize`, `_get_size`, `_push_nav`, `_set_title`, `_clear_text`, `_listen`, `_draw_text`, `_draw_bitmap` — runtime calls through the Mutex-guarded bridge.

### Direction 2: Rust → Chromium (Rust observes / configures Chromium via C++ statics)

Injected C++ singletons that patches reach into:

- `carbonyl::Bridge::GetDPI()`, `::BitmapMode()`, `::Configure(dpi, bitmap_mode)`, `::Resize()` — file-scope statics in `src/browser/bridge.cc`. Set once at startup by `Renderer::Main()`, read by DSF-propagation patches (0006, 0013, 2026-04 Viz fix).
- `carbonyl::Renderer::GetCurrent()` → wraps the `carbonyl_renderer*` handle, exposes `GetSize()`, `DrawBitmap()`, etc. as C++ methods the Chromium-side code calls.

### Load-bearing invariants

Documented at each function's entry in the catalog. The ones that have bitten us:

- **`carbonyl_renderer_get_size`** returns the **CSS viewport** (`cells × scale`). Chromium must multiply by `carbonyl_bridge_get_dpi()` to get the physical raster size. If that multiplication is dropped anywhere in the compositor, only the upper-left `dpi²` fraction of the page is visible (issue #37).
- **`carbonyl_renderer_draw_bitmap`**: the `pixels_size` argument MUST equal `cells × (2, 4)` physical pixels, matching the renderer's 2×4 quadrant sampler. If the Chromium side hands a larger buffer, the renderer silently crops.
- **Mutex inside the `carbonyl_renderer*` bridge** is re-entered across `get_size` and `draw_bitmap`. Never call one while holding the other; treat them as exclusive entries.

---

## Rebuild recipes by change type

Know which rebuild your change needs before you wait hours for the wrong one.

### Pure Rust change (the fast case — ~10 seconds)

Applies to: anything under `src/**/*.rs` that doesn't change the `extern "C"` ABI.

```bash
cargo build --release
cp build/x86_64-unknown-linux-gnu/release/libcarbonyl.so chromium/src/out/Default/
cp build/x86_64-unknown-linux-gnu/release/libcarbonyl.so build/pre-built/x86_64-unknown-linux-gnu/
```

No Chromium rebuild needed. The `carbonyl` binary dlopens `libcarbonyl.so` at startup, so swapping the `.so` is enough.

### FFI ABI change (Rust side changes + possibly C++)

Applies to: adding/removing an `extern "C"` function, changing a struct layout, renaming a symbol Chromium calls.

1. Edit `src/browser/bridge.rs` (Rust declaration).
2. Edit `src/browser/renderer.cc` (C++ re-declaration at the top of the file) — or wherever Chromium-side calls happen.
3. `cargo build --release` + copy (as above).
4. `ninja -C chromium/src/out/Default headless:headless_shell` — will rebuild `renderer.o` and relink. Usually 5-15 min for one file + a final link.

### Injected Carbonyl C++ change (under `src/browser/*.{h,cc}`)

Applies to: editing `bridge.cc`, `renderer.cc`, `host_display_client.cc`, `render_service_impl.cc`.

```bash
ninja -C chromium/src/out/Default headless:headless_shell
cp chromium/src/out/Default/headless_shell build/pre-built/x86_64-unknown-linux-gnu/carbonyl
```

Realistic cost: a few minutes (recompile the one `.o`, relink `headless_shell` — the Chromium link itself is 5-10 min).

### Chromium patch change (modifying upstream source via a `.patch`)

Applies to: editing any `chromium/patches/chromium/*.patch`, or editing `chromium/src/**` files that a patch already modifies.

Same as above: `ninja -C chromium/src/out/Default headless:headless_shell`. Incremental unless the file you touched has wide fan-out in Chromium's DAG (core Blink headers can trigger thousands of rebuilds).

**Beware**: if you edit a patched file directly in `chromium/src/**` without updating the corresponding `.patch`, your change lives only in the build tree and gets wiped on the next `gclient sync` or patch re-apply. Round-trip through the patch file if you want the change to stick.

### Chromium version bump (the slow case — hours)

See [MAINTENANCE.md § Chromium version](../MAINTENANCE.md#chromium-version). Full sync + patch rebase + clean build is a multi-hour operation, worth scheduling explicitly.

### Going from a stale build tree to current (the surprise-slow case)

What bit us during the #37 fix: `chromium/src/out/Default` was ~10 days behind current source and triggered an 8+ hour ninja run. Before promising "a fast incremental rebuild," check:

```bash
stat -c '%y' chromium/src/out/Default/headless_shell
git -C chromium/src log -1 --format='%ci %H'
# if the binary is much older than the source checkout, expect a long rebuild
```

Realistic rates observed on a 20-core host at `-j 10`:
- v8/torque initializers: ~50 .o/min
- Blink core: ~20 .o/min
- Blink bindings (generated): ~50 .o/min
- Chromium link: 5-10 min single-threaded at the end

Total tasks at clean M147 build: ~38,877.

---

## Verification — "is my change actually live?"

The #37 investigation had a diagnostic gap: nothing cheap to run tells you "the binary you just launched contains the edit you think it contains." Fix that on every change.

### Quick timestamp check

```bash
# compare source to artifact
stat -c '%y %n' \
  src/browser/bridge.rs \
  build/pre-built/x86_64-unknown-linux-gnu/libcarbonyl.so \
  build/pre-built/x86_64-unknown-linux-gnu/carbonyl

# artifact mtimes should be newer than source mtimes if you rebuilt
```

### Symbol inspection (for C++ edits)

```bash
# look for a string you embedded in the edit
strings build/pre-built/x86_64-unknown-linux-gnu/carbonyl | grep <distinctive-string>

# for Carbonyl-specific classes
nm -D --demangle build/pre-built/x86_64-unknown-linux-gnu/carbonyl | grep carbonyl::
```

### Runtime debug log

The cheapest end-to-end verification is a `log::warning!` / `DLOG` the code path must hit. Example from the #37 diagnostic:

```rust
// src/browser/bridge.rs inside carbonyl_renderer_draw_bitmap
log::warning!(
    "carbonyl_renderer_draw_bitmap: pixels_size={}x{} cells={}x{}",
    pixels_size.width, pixels_size.height,
    bridge.window.cells.width, bridge.window.cells.height,
);
```

Run with `--debug`:

```bash
./carbonyl --no-sandbox --debug URL 2>carbonyl.log
grep pixels_size carbonyl.log | head
```

If the log line doesn't appear at all, your change didn't reach that code path. If it appears with values you didn't expect, you've found your bug without a second long rebuild.

Remove the log before committing.

---

## Release flow (source → published tarball)

```
src/**/*.rs        ──cargo build──→  build/{triple}/release/libcarbonyl.so
                                      │
                                      ▼
chromium/src/**  ──ninja──→ chromium/src/out/Default/headless_shell
                                      │
                                      ▼ (scripts/copy-binaries.sh)
                         build/pre-built/{triple}/
                                 ├── carbonyl                (renamed headless_shell)
                                 ├── libcarbonyl.so
                                 ├── icudtl.dat
                                 ├── libEGL.so / libGLESv2.so
                                 └── v8_context_snapshot*.bin
                                      │
                                      ▼ (scripts/build.sh tar step)
                             build/{triple}.tgz + sha256
                                      │
                                      ▼ (scripts/runtime-push.sh)
                       Gitea release "runtime-<hash>"
                       (hash from .gclient + patches + bridge files)
                                      │
                                      ▼
                       carbonyl-agent install (SHA-verified)
```

Each stage has tooling:
- `scripts/build.sh` — cargo + ninja + copy + tar
- `scripts/copy-binaries.sh` — assembles the install layout
- `scripts/runtime-push.sh` — uploads to Gitea (R2 path preserved in file history)
- `scripts/runtime-pull.sh` — consumer-side download + SHA verify
- `scripts/runtime-hash.sh` — deterministic hash over (`.gclient`, patches, bridge files)

---

## SDK-driven viewport

The CSS viewport Chromium lays out against is consumer-controlled, not derived from terminal cell count. Pass it in via either:

```bash
./carbonyl --no-sandbox --viewport=1280x800 URL
# or
CARBONYL_VIEWPORT=1280x800 ./carbonyl --no-sandbox URL
```

When set, Blink lays out against exactly that CSS viewport (e.g. 1280×800), DSF is forced to 1.0, and Chromium rasters at that same size in physical pixels. The terminal samples a `cells × (2, 4)` window of the raster. When the terminal is large enough (e.g. 640×200 cells → 1280×800 physical) the entire viewport fits in one frame; smaller terminals show the upper-left portion, and the SDK handles scroll / pan / quadrant-stitching to cover the rest.

**Why this matters**: the legacy terminal-derived path computed `browser = cells × scale` with sub-unit DSF (~0.38), which Chromium's plumbing combined into an absurdly wide CSS layout (~6926×4129 at a 500×149 terminal). The center of a normal desktop UI landed outside the sampled region — that's the bug issue #37 reports. With an explicit `--viewport`, the CSS layout is whatever the SDK asked for, independent of terminal cell count.

### SDK usage pattern (Python, `carbonyl-agent`)

```python
import os, subprocess

def spawn_carbonyl(url: str, viewport: tuple[int, int] | None = None):
    env = os.environ.copy()
    if viewport is not None:
        w, h = viewport
        env["CARBONYL_VIEWPORT"] = f"{w}x{h}"
    return subprocess.Popen(
        ["carbonyl", "--no-sandbox", url],
        env=env,
    )
```

Use the env var rather than the flag when embedding — the flag parser is tolerant of unknown args so mixing Chromium flags and `--viewport` is safe, but env-var keeps the spawning surface clean.

### Choosing a viewport size

- **Target a specific device size** — `1280×800`, `1920×1080`, `375×667` (iPhone). Reproducible layout across terminals.
- **Match the terminal** — pass `cells.w * 2 × cells.h * 4` to get exactly the legacy physical raster size without the DSF weirdness. Useful for debugging.
- **Full-page stitching** — pass a tall viewport (`1280×4000`) and have the SDK capture multiple terminal-sized quadrants as the page scrolls.

Unset (default) behaviour preserves the legacy terminal-derived sizing for backward compatibility, but any new consumer should pass `--viewport`.

---

## Quick answers to recurring questions

**Q: I edited Rust. Do I need to rebuild Chromium?**  No. `cargo build --release` + copy `libcarbonyl.so` to two places. ~10 seconds.

**Q: I edited `chromium/patches/.../0013-*.patch`. What do I rebuild?**  The patched file inside `chromium/src/**` — confirm it picks up your intent — then `ninja -C chromium/src/out/Default headless:headless_shell`. If you edit the patch but forget to re-apply it to the tree, nothing changes.

**Q: I edited `chromium/src/**` directly. Will the change survive?**  Only until the next `gclient sync` or `scripts/patches.sh apply`. Round-trip through the `.patch` file for durability.

**Q: My edit compiled but the binary behaves the same as before. What do I check?**
1. `stat` the artifact — is it actually newer than your edit?
2. Is the binary you're running the one you rebuilt? (`which carbonyl`, `readlink -f`)
3. Is your edit on the hot path? Add a debug log and confirm the line fires.

**Q: How long will a Chromium rebuild take?**  Depends on how stale the build tree is. An incremental after a 1-file change: minutes. After a 10-day source drift or a Chromium m-version bump: hours. Check `stat` on `headless_shell` vs the source checkout before committing to a schedule.
