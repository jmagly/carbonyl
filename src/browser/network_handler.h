// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Network-event capture FFI (issue #6). Sibling to `accessibility_handler`
// and `javascript_handler` — lives in its own GN component (`:network`) for
// the same reason: depending on `//content/public/browser` from `:bridge`
// would close a skia/content dependency cycle.
//
// The handler is a process-wide singleton installed on the primary
// WebContents in `OnBrowserStart` (chromium patch 0032). It observes
// `content::WebContentsObserver::ResourceLoadComplete`, which fires once per
// completed resource (success or failure) with a
// `blink::mojom::ResourceLoadInfo` carrying the final URL, request method,
// HTTP status code, and load timing. Each completed resource is serialized to
// a one-line JSON object and pushed to the Rust side via a registered C
// callback; Rust owns the bounded ring buffer (see `src/browser/bridge.rs`).
//
// Scope (locked for #6): this observation point yields URL / method / status /
// timing / mime / cached / byte-counts — everything the issue's acceptance
// criteria require. It does NOT carry request/response body content or header
// maps; `ResourceLoadInfo` exposes only byte counts. Capturing bodies/headers
// would require a `URLLoaderFactory` interceptor and is deliberately deferred.
//
// Per-event JSON shape:
//   {"url":"...","method":"GET","status":200,"timing_ms":12.5,
//    "mime":"text/html","cached":false,"body_bytes":1234}
//
// Capture is opt-in (disabled by default): `carbonyl_set_network_capture(true)`
// arms it. While disarmed, `ResourceLoadComplete` early-returns before any
// serialization, so an un-armed session pays no per-resource cost — satisfying
// the "no measurable throughput impact" criterion. HTTP/socket exposure of the
// buffered log is out of scope (carbonyl-fleet#11).
//
// Thread-affinity: `ResourceLoadComplete` is delivered on the browser UI
// thread, so the registered callback (the Rust ring-buffer append) runs on the
// UI thread — the Rust side guards the buffer with a Mutex, no post_task.

#ifndef CARBONYL_SRC_BROWSER_NETWORK_HANDLER_H_
#define CARBONYL_SRC_BROWSER_NETWORK_HANDLER_H_

#include "carbonyl/src/browser/export.h"
#include "content/public/browser/web_contents_observer.h"

namespace content {
class WebContents;
}

namespace carbonyl {

// C callback invoked once per completed resource with a JSON object string
// (valid only for the duration of the call — the callee copies synchronously;
// no ownership transfer, nothing to free). Invoked on the UI thread.
using CarbonylNetworkCallback = void (*)(const char* json_event);

// Process-wide singleton observing the primary WebContents' resource loads.
// Sibling to JavaScriptHandler; same lifetime/observer contract.
class CARBONYL_BRIDGE_EXPORT NetworkHandler
    : public content::WebContentsObserver {
 public:
  // Install the singleton on the given WebContents. Idempotent — a second
  // call against a different WebContents replaces the binding. Called from
  // `headless/app/headless_shell.cc::OnBrowserStart` via chromium patch 0032.
  static void InstallFor(content::WebContents* web_contents);

  // content::WebContentsObserver:
  void ResourceLoadComplete(
      content::RenderFrameHost* render_frame_host,
      const content::GlobalRequestID& request_id,
      const blink::mojom::ResourceLoadInfo& resource_load_info) override;

 private:
  explicit NetworkHandler(content::WebContents* web_contents);
  ~NetworkHandler() override;

  // content::WebContentsObserver:
  void WebContentsDestroyed() override;

  static NetworkHandler* g_instance_;
};

// C-ABI surface consumed by `src/browser/bridge.rs`.
extern "C" {

// Register the per-event sink. The Rust bridge calls this once at startup with
// its ring-buffer trampoline. Passing nullptr detaches the sink.
CARBONYL_BRIDGE_EXPORT void carbonyl_set_network_callback(
    CarbonylNetworkCallback callback);

// Arm/disarm capture. Disabled by default; while disabled,
// `ResourceLoadComplete` does no serialization. The carbonyl-fleet socket
// layer (#11) arms it on demand.
CARBONYL_BRIDGE_EXPORT void carbonyl_set_network_capture(bool enabled);

}  // extern "C"

}  // namespace carbonyl

#endif  // CARBONYL_SRC_BROWSER_NETWORK_HANDLER_H_
