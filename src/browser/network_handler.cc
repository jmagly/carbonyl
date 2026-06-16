// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "carbonyl/src/browser/network_handler.h"

#include <string>

#include "base/json/json_writer.h"
#include "base/logging.h"
#include "base/time/time.h"
#include "base/values.h"
#include "content/public/browser/global_request_id.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "net/base/load_timing_info.h"
#include "third_party/blink/public/mojom/loader/resource_load_info.mojom.h"
#include "url/gurl.h"

namespace carbonyl {

namespace {

// The registered per-event sink and the capture-armed flag. Single-process
// model: plain globals, touched only on the UI thread (ResourceLoadComplete
// affinity), so no synchronization is needed here — the Rust side guards its
// own ring buffer.
CarbonylNetworkCallback g_callback = nullptr;
bool g_enabled = false;

// Wall-clock elapsed for one resource: request start -> response headers
// received, in milliseconds. Returns 0 when either timestamp is null (e.g.
// served from cache before a request was sent).
double TimingMs(const net::LoadTimingInfo& t) {
  if (t.request_start.is_null() || t.receive_headers_end.is_null()) {
    return 0.0;
  }
  return (t.receive_headers_end - t.request_start).InMillisecondsF();
}

}  // namespace

// Static instance pointer. Single-process model: a plain global, touched on
// the UI thread only.
NetworkHandler* NetworkHandler::g_instance_ = nullptr;

// static
void NetworkHandler::InstallFor(content::WebContents* web_contents) {
  if (!web_contents) {
    LOG(WARNING) << "carbonyl::NetworkHandler::InstallFor: called with nullptr "
                    "WebContents, ignoring";
    return;
  }

  // Replace any prior binding. The previous instance self-deletes via its
  // `WebContentsDestroyed` observer; carbonyl's headless shell constructs a
  // single WebContents per process, so this replace branch is defensive.
  if (g_instance_) {
    LOG(WARNING) << "carbonyl::NetworkHandler: replacing existing binding "
                    "(multi-WebContents not supported)";
  }

  g_instance_ = new NetworkHandler(web_contents);
  LOG(INFO) << "carbonyl::NetworkHandler: bound to WebContents";
}

void NetworkHandler::ResourceLoadComplete(
    content::RenderFrameHost* /*render_frame_host*/,
    const content::GlobalRequestID& /*request_id*/,
    const blink::mojom::ResourceLoadInfo& resource_load_info) {
  // Opt-in: do nothing (not even serialize) unless armed and a sink exists.
  // This is the early-return that keeps an un-armed session at zero per-
  // resource cost.
  if (!g_enabled || !g_callback) {
    return;
  }

  base::DictValue event;
  event.Set("url", resource_load_info.final_url.spec());
  event.Set("method", resource_load_info.method);
  event.Set("status", resource_load_info.http_status_code);
  event.Set("timing_ms", TimingMs(resource_load_info.load_timing_info));
  event.Set("mime", resource_load_info.mime_type);
  event.Set("cached", resource_load_info.was_cached);

  std::string json;
  if (!base::JSONWriter::Write(event, &json)) {
    // A fixed-shape dict of primitives cannot realistically fail to serialize;
    // drop the event rather than push malformed JSON into the Rust buffer.
    LOG(WARNING) << "carbonyl::NetworkHandler: JSONWriter::Write failed, "
                    "dropping resource event";
    return;
  }

  // Synchronous: the Rust trampoline copies `json` into the ring buffer before
  // returning, so the local string's lifetime is sufficient and nothing
  // crosses the allocator boundary.
  g_callback(json.c_str());
}

NetworkHandler::NetworkHandler(content::WebContents* web_contents)
    : content::WebContentsObserver(web_contents) {}

NetworkHandler::~NetworkHandler() = default;

void NetworkHandler::WebContentsDestroyed() {
  if (g_instance_ == this) {
    g_instance_ = nullptr;
  }
  delete this;
}

// ------------------------------ FFI exports ------------------------------

extern "C" {

CARBONYL_BRIDGE_EXPORT void carbonyl_set_network_callback(
    CarbonylNetworkCallback callback) {
  g_callback = callback;
}

CARBONYL_BRIDGE_EXPORT void carbonyl_set_network_capture(bool enabled) {
  g_enabled = enabled;
}

}  // extern "C"

}  // namespace carbonyl
