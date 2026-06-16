// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "carbonyl/src/browser/javascript_handler.h"

#include <cstring>
#include <string>

#include "base/compiler_specific.h"
#include "base/functional/bind.h"
#include "base/json/json_writer.h"
#include "base/logging.h"
#include "base/strings/utf_string_conversions.h"
#include "base/values.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/isolated_world_ids.h"

namespace carbonyl {

namespace {

// Heap-allocate a copy of `s` as a C string for the FFI boundary. The caller
// frees via `carbonyl_free_string()` (exported by `:accessibility`), which
// uses `delete[]` to match this `new char[]`.
const char* AllocateCString(const std::string& s) {
  const size_t len = s.size() + 1;
  char* out = new char[len];
  UNSAFE_BUFFERS(std::memcpy(out, s.c_str(), len));
  return out;
}

// Build the error envelope `{"result":null,"error":"<reason>"}` as a freshly
// heap-allocated C string. `reason` is a static string literal (one of the
// documented reasons in the header).
const char* AllocateErrorEnvelope(const char* reason) {
  base::DictValue dict;
  dict.Set("result", base::Value());  // JSON null
  dict.Set("error", reason);
  std::string json;
  if (base::JSONWriter::Write(dict, &json)) {
    return AllocateCString(json);
  }
  // Writing a fixed-shape dict cannot realistically fail, but preserve the
  // free() contract with a hand-built constant copy if it ever does.
  constexpr const char kFallback[] =
      "{\"result\":null,\"error\":\"serialization_failed\"}";
  const size_t len = sizeof(kFallback);  // includes NUL
  char* out = new char[len];
  UNSAFE_BUFFERS(std::memcpy(out, kFallback, len));
  return out;
}

// UI-thread continuation invoked by ExecuteJavaScriptInIsolatedWorld with the
// script result. Serializes the value to JSON and hands ownership of the
// string to the supplied C callback. A void/undefined script result arrives
// as a NONE-typed base::Value, which serializes to "null".
void OnResult(CarbonylEvalCallback callback,
              void* user_data,
              base::Value result) {
  std::string json;
  if (!base::JSONWriter::Write(result, &json)) {
    callback(AllocateErrorEnvelope("serialization_failed"), user_data);
    return;
  }
  callback(AllocateCString(json), user_data);
}

}  // namespace

// Static instance pointer. Single-process model: a plain global, not
// thread-safe by itself; FFI callers post to the UI thread before touching it
// (see the header's thread-affinity note).
JavaScriptHandler* JavaScriptHandler::g_instance_ = nullptr;

// static
void JavaScriptHandler::InstallFor(content::WebContents* web_contents) {
  if (!web_contents) {
    LOG(WARNING) << "carbonyl::JavaScriptHandler::InstallFor: called with "
                    "nullptr WebContents, ignoring";
    return;
  }

  // Replace any prior binding. The previous instance self-deletes via its
  // `WebContentsDestroyed` observer; carbonyl's headless shell constructs a
  // single WebContents per process, so this replace branch is defensive.
  if (g_instance_) {
    LOG(WARNING) << "carbonyl::JavaScriptHandler: replacing existing binding "
                    "(multi-WebContents not supported)";
  }

  g_instance_ = new JavaScriptHandler(web_contents);
  LOG(INFO) << "carbonyl::JavaScriptHandler: bound to WebContents";
}

// static
void JavaScriptHandler::Evaluate(const std::string& script,
                                 CarbonylEvalCallback callback,
                                 void* user_data) {
  if (!callback) {
    LOG(WARNING) << "carbonyl::JavaScriptHandler::Evaluate: null callback, "
                    "ignoring";
    return;
  }

  if (!g_instance_ || !g_instance_->web_contents()) {
    callback(AllocateErrorEnvelope("no_web_contents"), user_data);
    return;
  }

  content::RenderFrameHost* frame =
      g_instance_->web_contents()->GetPrimaryMainFrame();
  if (!frame) {
    callback(AllocateErrorEnvelope("no_main_frame"), user_data);
    return;
  }

  // Run in the first embedder isolated world (ID 1 == ISOLATED_WORLD_ID_GLOBAL
  // + 1). The isolated world shares the DOM but not the page's JS globals, so
  // automation can query/manipulate the document without colliding with — or
  // being tampered by — page script. The result callback fires on the UI
  // thread (per RenderFrameHost::JavaScriptResultCallback contract), matching
  // OnResult's affinity.
  frame->ExecuteJavaScriptInIsolatedWorld(
      base::UTF8ToUTF16(script),
      base::BindOnce(&OnResult, callback, user_data),
      content::ISOLATED_WORLD_ID_CONTENT_END);
}

JavaScriptHandler::JavaScriptHandler(content::WebContents* web_contents)
    : content::WebContentsObserver(web_contents) {}

JavaScriptHandler::~JavaScriptHandler() = default;

void JavaScriptHandler::WebContentsDestroyed() {
  // The observed WebContents has been torn down. Clear the singleton and
  // self-delete; subsequent Evaluate() calls return the `no_web_contents`
  // envelope until a fresh InstallFor (which carbonyl's single-WebContents
  // model does not perform).
  if (g_instance_ == this) {
    g_instance_ = nullptr;
  }
  delete this;
}

// ------------------------------ FFI exports ------------------------------

extern "C" {

CARBONYL_BRIDGE_EXPORT void carbonyl_eval_javascript(
    const char* script,
    CarbonylEvalCallback callback,
    void* user_data) {
  // A null `script` is treated as the empty program (evaluates to undefined →
  // "null"). The callback (when non-null) is always invoked exactly once.
  JavaScriptHandler::Evaluate(script ? std::string(script) : std::string(),
                              callback, user_data);
}

}  // extern "C"

}  // namespace carbonyl
