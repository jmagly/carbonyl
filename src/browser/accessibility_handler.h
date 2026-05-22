// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// AXTree extraction FFI (issue #4). Sibling to `dump_text_handler` —
// lives in its own GN component (`:accessibility`) for the same reason
// `:dump_text` does: depending on `//content/public/browser` from
// `:bridge` would introduce a skia/content dependency cycle.
//
// The handler is a process-wide singleton installed on the primary
// WebContents in `OnBrowserStart` (chromium patch 0028). The Rust FFI
// (`carbonyl_get_accessibility_tree`) dispatches to the singleton, which
// calls `WebContents::RequestAXTreeSnapshotWithinBrowserProcess()` —
// the browser-side, no-IPC snapshot — and serializes the resulting
// `ui::AXTreeUpdate` to JSON via `base::Value` + `base::JSONWriter`.
//
// JSON shape (per issue #4 acceptance criteria):
//   {
//     "role": "<ax::mojom::Role string>",
//     "name": "<accessible name>",
//     "value": "<accessible value, if any>",
//     "description": "<accessible description, if any>",
//     "focused": <bool>,
//     "disabled": <bool>,
//     "bounding_box": { "x": N, "y": N, "w": N, "h": N },  // CSS px, viewport-relative
//     "children": [ ... recursive ... ]
//   }
//
// Ignored AX nodes (per `AXNodeData::IsIgnored()`) are pruned from the
// emitted tree, mirroring Chromium's own accessibility-tree filtering.
// When AX mode is off or no WebContents is bound, the FFI returns:
//   { "error": "no_tree" }
//
// Ownership: C++ allocates the JSON string via `new char[]`. Callers
// MUST release it via `carbonyl_free_string()` — see the matching FFI
// declaration in `src/browser/bridge.rs`.

#ifndef CARBONYL_SRC_BROWSER_ACCESSIBILITY_HANDLER_H_
#define CARBONYL_SRC_BROWSER_ACCESSIBILITY_HANDLER_H_

#include <string>

#include "base/memory/raw_ptr.h"
#include "carbonyl/src/browser/export.h"
#include "content/public/browser/web_contents_observer.h"

namespace content {
class WebContents;
}

namespace carbonyl {

// Process-wide singleton that holds a pointer to the primary WebContents
// so the FFI can synchronously snapshot the accessibility tree without
// scanning a per-process WebContents registry.
//
// The handler observes the bound WebContents so it can null its pointer
// on destruction — the FFI then returns `{"error": "no_tree"}` rather
// than dereferencing a dangling pointer.
class CARBONYL_BRIDGE_EXPORT AccessibilityHandler
    : public content::WebContentsObserver {
 public:
  // Install the singleton on the given WebContents and force AX mode to
  // `kWebContents` so subsequent snapshots are populated. Idempotent —
  // second call against a different WebContents replaces the binding.
  // Called from `headless/app/headless_shell.cc::OnBrowserStart` via
  // chromium patch 0028.
  static void InstallFor(content::WebContents* web_contents);

  // Serialize the current AX tree to JSON. Always returns a non-null,
  // heap-allocated UTF-8 C string the caller must release via
  // `carbonyl_free_string()`. On any failure path (no singleton, no
  // bound WebContents, AX mode off, empty snapshot), returns the
  // sentinel JSON `{"error": "no_tree"}` — never returns nullptr.
  //
  // Thread-affinity: must be called on the browser UI thread. The Rust
  // FFI surface is invoked from the carbonyl input/render threads which
  // post to the UI thread before reaching here.
  static const char* GetTreeJSON();

 private:
  explicit AccessibilityHandler(content::WebContents* web_contents);
  ~AccessibilityHandler() override;

  // content::WebContentsObserver:
  void WebContentsDestroyed() override;

  // Singleton storage. nullptr until `InstallFor` is called; set back to
  // nullptr (and self-deleted) when the observed WebContents is torn
  // down.
  static AccessibilityHandler* g_instance_;
};

// C-ABI surface consumed by `src/browser/bridge.rs`. Declared here so
// the Rust FFI declarations stay in sync with the C++ signatures.
extern "C" {

// Returns a malloc'd JSON string (see GetTreeJSON above for shape and
// error semantics). Caller frees via `carbonyl_free_string`.
CARBONYL_BRIDGE_EXPORT const char* carbonyl_get_accessibility_tree();

// Release a string previously returned by `carbonyl_get_accessibility_tree`.
// Safe to call with nullptr (no-op).
CARBONYL_BRIDGE_EXPORT void carbonyl_free_string(const char* ptr);

}  // extern "C"

}  // namespace carbonyl

#endif  // CARBONYL_SRC_BROWSER_ACCESSIBILITY_HANDLER_H_
