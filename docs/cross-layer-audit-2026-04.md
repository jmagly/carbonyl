# Cross-Layer Audit — 2026-04-09

**Issue**: [roctinam/carbonyl#29](https://git.integrolabs.net/roctinam/carbonyl/issues/29)
**Triggered by**: [#27](https://git.integrolabs.net/roctinam/carbonyl/issues/27) (M135 cppgc cascade)
**Blocks**: [#28](https://git.integrolabs.net/roctinam/carbonyl/issues/28) (Path A — extract text capture into blink TU)
**Tool**: `scripts/audit-cross-layer.sh`
**Patch series state**: 23 patches (post-Path-B, M135 ship)

## TL;DR

**Net cross-layer blink-include reaches in current main: 0.**

After patch 0023 (Path B) landed, the carbonyl patch series has zero
`blink/renderer/*` includes in non-blink translation units. The only
cross-layer boundary crossings remaining are calls into the public
`carbonyl/src/browser/bridge.h` header from blink TUs, which are by
design and don't trigger the cppgc cascade.

This means **Path A (#28) is a clean structural refactor** — no hidden
time bombs to discover, no other patches to rewrite alongside the text
capture extraction. The work is exactly what #28 says it is and
nothing more.

## Findings summary

| Category | Count | Severity | Status |
|----------|-------|----------|--------|
| A — blink includes added to non-blink | 8 | Critical (cppgc cascade) | Cancelled by Cat B (net = 0) |
| B — blink includes removed from non-blink | 8 | Informational | All in patch 0023 (Path B) |
| C — carbonyl refs in blink TUs | 12 | Watch | All via public `bridge.h`, no impact |
| D — blink files patched by carbonyl | 24 | Informational | Path A target dir is new |
| E1 — forward decls of blink in non-blink | 0 | Watch | Clean |
| E2 — static_cast to blink from non-blink | 1 | Watch | Currently dead code |
| **Total findings** | **29** | | **0 active threats** |

## Detailed classification

### Category A — blink/renderer includes added to non-blink TUs (8)

All 8 findings are in **patch 0010** (`Conditionally-enable-text-rendering`),
all targeting `content/renderer/render_frame_impl.cc`:

| Include | Purpose |
|---------|---------|
| `core/exported/web_view_impl.h` | Cast to `WebViewImpl*` for paint record access |
| `core/dom/frame_request_callback_collection.h` | Frame callback registration |
| `core/frame/local_frame_view.h` | Local frame view for paint walk |
| `core/frame/web_local_frame_impl.h` | Web local frame impl access |
| `core/paint/paint_flags.h` | Paint flag types |
| `core/layout/layout_view.h` | Layout view access |
| `platform/graphics/paint/cull_rect.h` | Cull rect for paint record |
| `platform/graphics/paint/paint_record_builder.h` | Paint record construction |

**Verdict**: These are the cppgc cascade trigger documented in #27.
**Status**: Cancelled by Category B (patch 0023 removed all 8). Net = 0.
**Path A scope**: All 8 will move into the new `text_capture.cc` blink TU.

### Category B — blink/renderer includes removed from non-blink TUs (8)

All 8 findings are in **patch 0023** (`Path B build fixes`), removing the
exact same 8 includes that Category A added. Same target file
(`content/renderer/render_frame_impl.cc`).

**Verdict**: Symmetric cancellation. Path B is doing exactly what we
intended — net cross-layer reach is zero after this patch series.

### Category C — `carbonyl::*` references in blink TUs (12)

All 12 findings reference `carbonyl::Bridge::BitmapMode()` (or
`carbonyl::blink::BitmapMode()` in the now-superseded patch 0012)
from blink translation units:

| Patch | File | Reference |
|-------|------|-----------|
| 0010 | `core/css/resolver/style_resolver.cc` | `carbonyl::Bridge::BitmapMode()` |
| 0010 | `platform/fonts/font.cc` | `carbonyl::Bridge::BitmapMode()` (×3) |
| 0012 | `core/css/resolver/style_resolver.cc` | `carbonyl::blink::BitmapMode()` (superseded by 0013) |
| 0012 | `platform/fonts/font.cc` | `carbonyl::blink::BitmapMode()` (×3, superseded by 0013) |
| 0013 | `core/css/resolver/style_resolver.cc` | `carbonyl::Bridge::BitmapMode()` (final) |
| 0013 | `platform/fonts/font.cc` | `carbonyl::Bridge::BitmapMode()` (×3, final) |

**Verdict**: **No impact, by design.**
- These are blink TUs (under `third_party/blink/`), so they get `INSIDE_BLINK`
  defined automatically by their GN target.
- They reference `carbonyl::Bridge::BitmapMode()` via
  `carbonyl/src/browser/bridge.h`, which is a public carbonyl header
  designed to be includable from anywhere.
- `bridge.h` has zero blink/cppgc dependencies — it's just a static method
  declaration. Including it doesn't pull in `garbage_collected.h` or any
  other cppgc machinery.
- `Bridge::BitmapMode()` returns a bool that gates carbonyl's text-rendering
  customizations: in bitmap mode, the customizations are skipped (early
  return); in non-bitmap mode, they apply carbonyl-specific styling.

These references **must stay** even after Path A lands. They're how the
blink-side text rendering knows whether to apply carbonyl overrides.
Path A only affects the **content/renderer/** side of the b64 capture path,
not the blink-side rendering customizations.

### Category D — Files under `third_party/blink/` patched by carbonyl (24)

24 (file × patch) entries enumerating which blink files carbonyl modifies.
Deduped to unique files:

| Blink file | Patches |
|------------|---------|
| `bindings/core/v8/script_promise_resolver.cc` | 0005, 0023 |
| `core/BUILD.gn` | 0013 |
| `core/css/resolver/style_resolver.cc` | 0008, 0010, 0012, 0013, 0020, 0023 |
| `core/paint/text_decoration_painter.cc` | 0007 |
| `platform/BUILD.gn` | 0010, 0012, 0013, 0022 |
| `platform/fonts/font.cc` | 0002, 0010, 0012, 0013, 0021, 0023 |
| `platform/graphics/compositing/paint_artifact_compositor.cc` | 0005 |
| `platform/graphics/graphics_context.cc` | 0005 |
| `platform/graphics/graphics_context.h` | 0023 |
| `public/web/web_frame_widget.h` | 0010 |

**Verdict**: **Informational, no action needed.**
- 9 source files + 1 public header + 2 BUILD.gn files
- All under `third_party/blink/`, all compiled with `INSIDE_BLINK`
- Path A's new files will live in a **new directory**:
  `third_party/blink/renderer/core/carbonyl/`. They don't conflict with
  any of these existing modifications.

### Category E1 — Forward declarations of `blink::*` in non-blink files (0)

**Clean.** No early-warning creep precursors found.

### Category E2 — `static_cast<blink::*>` from non-blink files (1)

One finding:

```
patch 0010 | content/renderer/render_frame_impl.cc
  auto* view = static_cast<blink::WebViewImpl*>(GetWebFrame()->View());
```

**Verdict**: **Currently dead code.** This cast lives inside the
`render_callback_` lambda which patch 0023 wrapped in `#if 0`. The
cast is no longer compiled.

**Path A action**: when the lambda body moves into the new
`text_capture.cc`, this cast moves with it. Inside a real blink TU, the
cast is fine because `WebViewImpl` is a legitimate internal type that
the blink TU can see directly without a forward decl.

## Implications for #28 (Path A)

The audit confirms that #28's scope is exactly what was originally
estimated:

1. **Create** `third_party/blink/renderer/core/carbonyl/` directory
2. **Add** `BUILD.gn` defining a new GN target `carbonyl_text_capture`
3. **Add** `text_capture.h` declaring `carbonyl::text_capture::CaptureFromWebView()`
4. **Add** `text_capture.cc` containing:
   - The 8 `blink/renderer/*` includes from Category A
   - The `TextCaptureDevice` class (currently in patch 0010, wrapped in `#if 0`)
   - The lambda body with the static_cast from E2
   - The glyph→base64 conversion logic
5. **Modify** `content/renderer/render_frame_impl.cc` (in the same Path A patch):
   - Remove the `#if 0` wrappers added by patch 0023
   - Replace the lambda body with a single call to `carbonyl::text_capture::CaptureFromWebView()`
   - The only carbonyl-related include becomes `carbonyl/src/browser/text_capture_client.h`
     (a new public header that forward-declares the entry point — no blink/renderer reach)
6. **Modify** `chromium/src/carbonyl/src/browser/BUILD.gn` to depend on the new blink target

That's it. No other patches need to change. The 12 Category C blink-side
references stay where they are. The 24 Category D file modifications
stay where they are. **Path A is a contained refactor.**

## Implications for future rebases

### Add audit to upgrade SOP

Re-run `scripts/audit-cross-layer.sh` after every rebase. **If Category A
returns to non-zero, the cppgc cascade is back.** This is the canonical
gate.

Suggested SOP additions in `MAINTENANCE.md` step 7 (after `patches.sh save`):

```bash
bash scripts/audit-cross-layer.sh > /tmp/audit-current.md
diff -u docs/cross-layer-audit-2026-04.md /tmp/audit-current.md
```

If the diff shows new Category A entries, **stop and refactor before
the build**. Don't try to fix the cascade in render_frame_impl.cc.

### Update audit report on each rebase

After a clean rebase, regenerate the audit report:

```bash
bash scripts/audit-cross-layer.sh > docs/cross-layer-audit-$(date +%Y-%m).md
git rm docs/cross-layer-audit-2026-04.md  # if updating
```

Or: keep historical reports in the repo as a record of the carbonyl
patch series's layering posture over time.

## Sign-off

- [x] Audit script committed to `scripts/audit-cross-layer.sh`
- [x] Findings document committed to `docs/cross-layer-audit-2026-04.md`
- [x] All 29 findings classified
- [x] Net cross-layer reach in current main = 0 (Cat A cancelled by Cat B)
- [x] No new "triggers cascade later" issues need to be filed
- [x] #28 scope confirmed as originally written (no expansion needed)

**Closes #29.**
