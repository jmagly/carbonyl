// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

#ifndef CARBONYL_SRC_BLINK_TEXT_CAPTURE_H_
#define CARBONYL_SRC_BLINK_TEXT_CAPTURE_H_

// Public entry point for carbonyl text capture.
//
// This header is safe to include from non-blink translation units (the content
// layer specifically). It deliberately includes nothing from
// third_party/blink/renderer/* to avoid pulling Oilpan/cppgc machinery into
// the include graph of the caller (see roctinam/carbonyl#27 for the M135
// cppgc cascade incident this exists to prevent).
//
// The implementation lives in text_capture.cc, which is compiled as a real
// blink translation unit (with INSIDE_BLINK defined) and is therefore free
// to reach into blink/renderer/core/* internals.
//
// See roctinam/carbonyl#28 for the structural rationale.

#include <vector>

#include "carbonyl/src/browser/carbonyl.mojom-forward.h"
#include "carbonyl/src/browser/export.h"

namespace blink {
class WebLocalFrame;
}  // namespace blink

namespace carbonyl::text_capture {

// Walks the paint record of the given frame, captures all visible glyph
// runs as carbonyl::mojom::TextData entries, and writes them to *out_data.
//
// Caller must:
//   - Pass a non-null WebLocalFrame
//   - Pass a non-null out_data (its previous contents are discarded)
//
// Returns true if any text was captured. Returns false if the frame had
// nothing to render (e.g. zero-size, hidden, no paint record).
//
// Thread-safety: must be called on the renderer main thread.
CARBONYL_RENDERER_EXPORT bool CaptureFromFrame(
    blink::WebLocalFrame* frame,
    std::vector<carbonyl::mojom::TextDataPtr>* out_data);

}  // namespace carbonyl::text_capture

#endif  // CARBONYL_SRC_BLINK_TEXT_CAPTURE_H_
