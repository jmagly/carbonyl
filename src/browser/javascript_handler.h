// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// JavaScript-evaluation FFI (issue #5). Sibling to `accessibility_handler`
// and `dump_text_handler` — lives in its own GN component (`:javascript`)
// for the same reason: depending on `//content/public/browser` from
// `:bridge` would close a skia/content dependency cycle.
//
// The handler is a process-wide singleton installed on the primary
// WebContents in `OnBrowserStart` (chromium patch 0031). The Rust FFI
// (`carbonyl_eval_javascript`) dispatches to the singleton, which runs the
// script in the primary main frame's isolated world via
// `RenderFrameHost::ExecuteJavaScriptInIsolatedWorld()` and serializes the
// resulting `base::Value` to JSON.
//
// Result contract (delivered to the supplied C callback):
//   success: the script result serialized via base::WriteJson — e.g.
//            "\"hello\"", "42", "{\"a\":1}", "true"; a void/undefined result
//            serializes to "null".
//   error:   {"result": null, "error": "<reason>"}  (reasons:
//            no_web_contents, no_main_frame, serialization_failed)
//
// Async: unlike the synchronous accessibility snapshot, JS eval round-trips
// to the renderer; the result arrives on a UI-thread callback. The C callback
// is therefore invoked exactly once — synchronously on the error fast-paths,
// asynchronously on success.
//
// Ownership: the JSON string handed to the callback is allocated `new char[]`
// and MUST be released via `carbonyl_free_string()` (reused from
// `:accessibility`) — see the matching FFI in `src/browser/bridge.rs`.
//
// Thread-affinity: `Evaluate` must run on the browser UI thread. The Rust FFI
// posts from the input/socket thread to the UI thread before invoking, exactly
// as documented for `carbonyl_get_accessibility_tree`.

#ifndef CARBONYL_SRC_BROWSER_JAVASCRIPT_HANDLER_H_
#define CARBONYL_SRC_BROWSER_JAVASCRIPT_HANDLER_H_

#include <string>

#include "carbonyl/src/browser/export.h"
#include "content/public/browser/web_contents_observer.h"

namespace content {
class WebContents;
}

namespace carbonyl {

// C callback invoked once with a heap-allocated JSON C string and the opaque
// `user_data` passed to `carbonyl_eval_javascript`. The callee MUST release
// the string via `carbonyl_free_string()`. Invoked on the UI thread.
using CarbonylEvalCallback = void (*)(const char* json_result, void* user_data);

// Process-wide singleton holding the primary WebContents pointer so the FFI
// can dispatch a main-frame JS eval without scanning a WebContents registry.
// Sibling to AccessibilityHandler; same lifetime/observer contract.
class CARBONYL_BRIDGE_EXPORT JavaScriptHandler
    : public content::WebContentsObserver {
 public:
  // Install the singleton on the given WebContents. Idempotent — a second
  // call against a different WebContents replaces the binding. Called from
  // `headless/app/headless_shell.cc::OnBrowserStart` via chromium patch 0031.
  static void InstallFor(content::WebContents* web_contents);

  // Execute `script` in the primary main frame's isolated world and deliver
  // the serialized result to `callback(json, user_data)`. See the file header
  // for the JSON contract. Error fast-paths invoke `callback` synchronously;
  // the success path invokes it asynchronously on the UI thread. Must be
  // called on the browser UI thread.
  static void Evaluate(const std::string& script,
                       CarbonylEvalCallback callback,
                       void* user_data);

 private:
  explicit JavaScriptHandler(content::WebContents* web_contents);
  ~JavaScriptHandler() override;

  // content::WebContentsObserver:
  void WebContentsDestroyed() override;

  static JavaScriptHandler* g_instance_;
};

// C-ABI surface consumed by `src/browser/bridge.rs`.
extern "C" {

// Async. Schedules `script` on the primary main frame; `callback` fires once
// with a malloc'd JSON string the callee frees via `carbonyl_free_string`.
// If no handler/WebContents/frame is available, `callback` is still invoked
// (synchronously, before return) with the error envelope.
//
// `carbonyl_free_string` is exported by the `:accessibility` component, which
// this component depends on — it is intentionally NOT redeclared here.
CARBONYL_BRIDGE_EXPORT void carbonyl_eval_javascript(
    const char* script,
    CarbonylEvalCallback callback,
    void* user_data);

}  // extern "C"

}  // namespace carbonyl

#endif  // CARBONYL_SRC_BROWSER_JAVASCRIPT_HANDLER_H_
