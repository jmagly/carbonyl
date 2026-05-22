// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "carbonyl/src/browser/accessibility_handler.h"

#include <cstring>
#include <unordered_map>
#include <utility>
#include <vector>

#include "base/json/json_writer.h"
#include "base/logging.h"
#include "base/values.h"
#include "content/public/browser/browser_accessibility_state.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/web_contents.h"
#include "ui/accessibility/ax_enum_util.h"
#include "ui/accessibility/ax_enums.mojom.h"
#include "ui/accessibility/ax_mode.h"
#include "ui/accessibility/ax_node_data.h"
#include "ui/accessibility/ax_relative_bounds.h"
#include "ui/accessibility/ax_tree_update.h"
#include "ui/gfx/geometry/rect_f.h"

namespace carbonyl {

namespace {

// Sentinel JSON returned when the tree cannot be produced. Heap-allocate
// a fresh copy on every call so the caller's free() symmetry holds.
const char* AllocateNoTreeError() {
  constexpr const char kErrorJson[] = "{\"error\":\"no_tree\"}";
  const size_t len = sizeof(kErrorJson);  // includes NUL
  char* out = new char[len];
  std::memcpy(out, kErrorJson, len);
  return out;
}

// Heap-allocate a copy of `s` as a C string suitable for handing across
// the FFI boundary. The caller frees via `carbonyl_free_string()`, which
// uses `delete[]` to match this `new char[]`.
const char* AllocateCString(const std::string& s) {
  const size_t len = s.size() + 1;
  char* out = new char[len];
  std::memcpy(out, s.c_str(), len);
  return out;
}

// Build a node-id -> AXNodeData* index from the flat `nodes` vector in
// `AXTreeUpdate`. The serialized form is intentionally flat; we rebuild
// the parent/child structure here so emission can be a single recursive
// walk from the root.
using NodeIndex = std::unordered_map<int32_t, const ui::AXNodeData*>;

NodeIndex BuildIndex(const ui::AXTreeUpdate& update) {
  NodeIndex index;
  index.reserve(update.nodes.size());
  for (const ui::AXNodeData& node : update.nodes) {
    index.emplace(node.id, &node);
  }
  return index;
}

// Serialize one AX node + its in-tree descendants. Ignored nodes are
// pruned — their non-ignored descendants are NOT lifted up (mirrors
// chromium's own tree-pruning convention; an automation client that
// needs the full structure can disable pruning via a future flag).
base::Value::Dict SerializeNode(const ui::AXNodeData& node,
                                const NodeIndex& index) {
  base::Value::Dict out;

  out.Set("role", ui::ToString(node.role));

  // Accessible name / value / description. `GetStringAttribute` returns
  // an empty string when the attribute is absent — emit the field only
  // when populated to keep the JSON payload compact for large trees.
  const std::string& name =
      node.GetStringAttribute(ax::mojom::StringAttribute::kName);
  if (!name.empty()) {
    out.Set("name", name);
  }
  const std::string& value =
      node.GetStringAttribute(ax::mojom::StringAttribute::kValue);
  if (!value.empty()) {
    out.Set("value", value);
  }
  const std::string& description =
      node.GetStringAttribute(ax::mojom::StringAttribute::kDescription);
  if (!description.empty()) {
    out.Set("description", description);
  }

  // Boolean state flags. These map directly from AXNodeData state bits
  // to the JSON booleans the issue specifies. Both fields are always
  // emitted (true OR false) so downstream automation can rely on their
  // presence without a key-existence check.
  out.Set("focused",
          node.HasState(ax::mojom::State::kFocusable) &&
              node.GetBoolAttribute(ax::mojom::BoolAttribute::kFocused));
  out.Set("disabled", node.GetRestriction() ==
                          ax::mojom::Restriction::kDisabled);

  // Bounding box: CSS px, viewport-relative (per design decision lock
  // in issue #4 cycle #1). `AXRelativeBounds::bounds` is a gfx::RectF
  // already in CSS px in the renderer's coordinate space; the snapshot
  // from `RequestAXTreeSnapshotWithinBrowserProcess` preserves that
  // space. Viewport-relative is the natural output — no scroll-offset
  // adjustment is applied here (per cycle #1 lock).
  const gfx::RectF& rect = node.relative_bounds.bounds;
  base::Value::Dict bbox;
  bbox.Set("x", rect.x());
  bbox.Set("y", rect.y());
  bbox.Set("w", rect.width());
  bbox.Set("h", rect.height());
  out.Set("bounding_box", std::move(bbox));

  // Recurse into children. `child_ids` is stored as int32_t; AX node
  // IDs are AXNodeID (also int32_t). Look up each child in the flat
  // index; skip missing IDs defensively (shouldn't happen in a
  // well-formed snapshot, but a renderer bug shouldn't crash carbonyl).
  base::Value::List children;
  for (int32_t child_id : node.child_ids) {
    auto it = index.find(child_id);
    if (it == index.end()) {
      continue;  // Dangling child ID; log if it becomes a real signal.
    }
    const ui::AXNodeData* child = it->second;
    if (child->IsIgnored()) {
      continue;  // Pruned per design.
    }
    children.Append(SerializeNode(*child, index));
  }
  out.Set("children", std::move(children));

  return out;
}

}  // namespace

// Static instance pointer. Single-process model means this is a plain
// global; not thread-safe by itself, but FFI callers post to the UI
// thread before touching it (see header file thread-affinity note).
AccessibilityHandler* AccessibilityHandler::g_instance_ = nullptr;

// static
void AccessibilityHandler::InstallFor(content::WebContents* web_contents) {
  if (!web_contents) {
    LOG(WARNING) << "carbonyl::AccessibilityHandler::InstallFor: "
                    "called with nullptr WebContents, ignoring";
    return;
  }

  // Replace any prior binding. The previous instance self-deletes via
  // its `WebContentsDestroyed` observer when its WebContents is torn
  // down; if `InstallFor` is called against a new WebContents while the
  // old one is still alive we just leak the prior `g_instance_` (acceptable
  // — carbonyl's headless shell only constructs one WebContents per
  // process today, so this branch is defensive, not load-bearing).
  if (g_instance_) {
    LOG(WARNING) << "carbonyl::AccessibilityHandler: replacing existing "
                    "binding (multi-WebContents not supported)";
  }

  // Force-enable browser-side AX mode so subsequent
  // `RequestAXTreeSnapshotWithinBrowserProcess()` calls return a
  // populated tree rather than an empty update (per cycle #1 lock:
  // "Force AXMode::kWebContentsOnly at startup"). Applying the mode at
  // the BrowserContext level means any WebContents subsequently attached
  // to the context inherits it — patches 0027 and 0028 both install
  // handlers on the same context, so this also covers the implicit
  // dependency of `DumpTextHandler::Mode::kAccessibility` on AX being
  // on (see #90 unblock note in PR #98).
  content::BrowserAccessibilityState::GetInstance()
      ->SetAccessibilityModeForBrowserContext(
          web_contents->GetBrowserContext(), ui::kAXModeWebContentsOnly);
  LOG(INFO) << "carbonyl::AccessibilityHandler: bound to WebContents, "
            << "AX mode forced to kAXModeWebContentsOnly";

  g_instance_ = new AccessibilityHandler(web_contents);
}

// static
const char* AccessibilityHandler::GetTreeJSON() {
  if (!g_instance_ || !g_instance_->web_contents()) {
    return AllocateNoTreeError();
  }

  // The browser-side snapshot is synchronous: it walks the existing
  // browser-side AXTree mirror (one per RenderFrameHost) and returns
  // a flat AXTreeUpdate. No renderer IPC — safe to call from a single
  // task on the UI thread.
  ui::AXTreeUpdate update =
      g_instance_->web_contents()->RequestAXTreeSnapshotWithinBrowserProcess();

  if (update.nodes.empty()) {
    // Snapshot ran but produced no nodes — typical when AX mode was
    // not on at the time the WebContents was constructed. Surface
    // `no_tree` rather than emit an empty `{}` so automation can
    // distinguish "AX off" from "page has no accessible content".
    return AllocateNoTreeError();
  }

  NodeIndex index = BuildIndex(update);
  auto root_it = index.find(update.root_id);
  if (root_it == index.end()) {
    LOG(WARNING) << "carbonyl::AccessibilityHandler: snapshot has root_id "
                 << update.root_id << " but no matching node in nodes[]";
    return AllocateNoTreeError();
  }

  base::Value::Dict root_dict = SerializeNode(*root_it->second, index);
  std::string json;
  if (!base::JSONWriter::Write(base::Value(std::move(root_dict)), &json)) {
    LOG(ERROR) << "carbonyl::AccessibilityHandler: base::JSONWriter::Write "
                  "failed; returning no_tree sentinel";
    return AllocateNoTreeError();
  }

  return AllocateCString(json);
}

AccessibilityHandler::AccessibilityHandler(content::WebContents* web_contents)
    : content::WebContentsObserver(web_contents) {}

AccessibilityHandler::~AccessibilityHandler() = default;

void AccessibilityHandler::WebContentsDestroyed() {
  // The WebContents we were observing has been torn down. Clear the
  // singleton pointer and self-delete — the FFI will return `no_tree`
  // on subsequent calls until a fresh `InstallFor` happens (which it
  // won't, in carbonyl's single-WebContents model — but the contract
  // is the same as `dump_text_handler`).
  if (g_instance_ == this) {
    g_instance_ = nullptr;
  }
  delete this;
}

// ------------------------------ FFI exports ------------------------------

extern "C" {

CARBONYL_BRIDGE_EXPORT const char* carbonyl_get_accessibility_tree() {
  return AccessibilityHandler::GetTreeJSON();
}

CARBONYL_BRIDGE_EXPORT void carbonyl_free_string(const char* ptr) {
  // Matches the `new char[]` in AllocateCString / AllocateNoTreeError.
  // `delete[]` on nullptr is well-defined no-op per [expr.delete]/2.
  delete[] ptr;
}

}  // extern "C"

}  // namespace carbonyl
