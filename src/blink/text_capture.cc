// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// This file is a real blink translation unit. It is compiled with
// INSIDE_BLINK defined (via the //third_party/blink/renderer:inside_blink
// config in BUILD.gn) and is free to include blink/renderer/core/* and
// blink/renderer/platform/* headers without triggering the cppgc cascade
// that broke the M111-era patches when they tried to do the same thing
// from content/renderer/ in M135.
//
// See roctinam/carbonyl#27 (diagnosis) and #28 (this fix).

#include "carbonyl/src/blink/text_capture.h"

#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "base/base64.h"
#include "carbonyl/src/browser/carbonyl.mojom.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/renderer/core/exported/web_view_impl.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/frame/local_frame_view.h"
#include "third_party/blink/renderer/core/frame/web_local_frame_impl.h"
#include "third_party/blink/renderer/core/layout/layout_view.h"
#include "third_party/blink/renderer/platform/graphics/paint/cull_rect.h"
#include "third_party/blink/renderer/platform/graphics/paint/paint_record_builder.h"
#include "third_party/skia/include/core/SkBlendMode.h"
#include "third_party/skia/include/core/SkCanvas.h"
#include "third_party/skia/include/core/SkColor.h"
#include "third_party/skia/include/core/SkImageInfo.h"
#include "third_party/skia/include/core/SkMatrix.h"
#include "third_party/skia/include/core/SkMesh.h"
#include "third_party/skia/include/core/SkPath.h"
#include "third_party/skia/include/core/SkPoint.h"
#include "third_party/skia/include/core/SkRRect.h"
#include "third_party/skia/include/core/SkRect.h"
#include "third_party/skia/include/core/SkSamplingOptions.h"
#include "third_party/skia/include/core/SkSurfaceProps.h"
#include "third_party/skia/include/core/SkVertices.h"
#include "third_party/skia/src/core/SkClipStackDevice.h"
#include "third_party/skia/src/core/SkDevice.h"
#include "third_party/skia/src/core/SkFontPriv.h"
#include "third_party/skia/src/text/GlyphRun.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/gfx/geometry/skia_conversions.h"

namespace carbonyl::text_capture {

namespace {

// SkClipStackDevice subclass that intercepts glyph runs and stores them as
// carbonyl::mojom::TextData entries. Moved verbatim from the original
// patch 0010 (`Conditionally-enable-text-rendering`) where it lived inside
// content/renderer/render_frame_impl.cc — see #27/#28 for why.
class TextCaptureDevice : public SkClipStackDevice {
 public:
  TextCaptureDevice(const SkImageInfo& info, const SkSurfaceProps& props)
      : SkClipStackDevice(info, props) {
    clear(SkRect::MakeWH(info.width(), info.height()));
  }

  void swap(std::vector<carbonyl::mojom::TextDataPtr>& data) {
    data.swap(data_);
  }

  void clear() { data_.clear(); }

  void clear(const SkRect& rect) {
    data_.push_back(carbonyl::mojom::TextData::New(
        std::string(), gfx::SkRectToRectF(rect), 0));
  }

 protected:
  sk_sp<SkDevice> createDevice(const CreateInfo& info,
                               const SkPaint*) override {
    return sk_make_sp<TextCaptureDevice>(
        info.fInfo, SkSurfaceProps(0, info.fPixelGeometry));
  }

  void drawDevice(SkDevice* baseDevice,
                  const SkSamplingOptions&,
                  const SkPaint& paint) override {
    if (isUnsupportedPaint(paint)) {
      return;
    }

    auto blendMode = paint.getBlendMode_or(SkBlendMode::kClear);

    if (blendMode != SkBlendMode::kSrc && blendMode != SkBlendMode::kSrcOver) {
      return;
    }

    auto* device = static_cast<TextCaptureDevice*>(baseDevice);
    SkMatrix transform = device->getRelativeTransform(*this);

    for (auto& data : device->data_) {
      data_.push_back(carbonyl::mojom::TextData::New(
          data->contents,
          gfx::SkRectToRectF(transform.mapRect(gfx::RectFToSkRect(data->bounds))),
          data->color));
    }
  }

  void drawPaint(const SkPaint&) override {}
  void drawOval(const SkRect&, const SkPaint&) override {}
  void drawPoints(SkCanvas::PointMode,
                  size_t,
                  const SkPoint[],
                  const SkPaint&) override {}
  void drawImageRect(const SkImage*,
                     const SkRect*,
                     const SkRect& rect,
                     const SkSamplingOptions&,
                     const SkPaint&,
                     SkCanvas::SrcRectConstraint) override {
    // clear(scale(rect));
  }

  void drawVertices(const SkVertices* vertices,
                    sk_sp<SkBlender>,
                    const SkPaint& paint,
                    bool = false) override {
    drawRect(vertices->bounds(), paint);
  }

  void drawMesh(const SkMesh& mesh,
                sk_sp<SkBlender>,
                const SkPaint& paint) override {
    drawRect(mesh.bounds(), paint);
  }

  void drawPath(const SkPath& path,
                const SkPaint& paint,
                bool = false) override {
    drawRect(path.getBounds(), paint);
  }

  void drawRRect(const SkRRect& rect, const SkPaint& paint) override {
    drawRect(rect.rect(), paint);
  }

  bool isUnsupportedPaint(const SkPaint& paint) {
    return (paint.getShader() || paint.getBlender() || paint.getPathEffect() ||
            paint.getMaskFilter() || paint.getImageFilter() ||
            paint.getColorFilter() || paint.getImageFilter());
  }

  void drawRect(const SkRect& rect, const SkPaint& paint) override {
    if (paint.getStyle() == SkPaint::Style::kFill_Style &&
        paint.getAlphaf() == 1.0 && !isUnsupportedPaint(paint)) {
      auto blendMode = paint.getBlendMode_or(SkBlendMode::kClear);

      if (blendMode == SkBlendMode::kSrc ||
          blendMode == SkBlendMode::kSrcOver) {
        clear(scale(rect));
      } else {
        std::cerr << "Blending mode: " << SkBlendMode_Name(blendMode)
                  << std::endl;
      }
    }
  }

  void onDrawGlyphRunList(SkCanvas*,
                          const sktext::GlyphRunList& glyphRunList,
                          const SkPaint& paint) override {
    auto position = scale(glyphRunList.origin());

    for (auto& glyphRun : glyphRunList) {
      auto runSize = glyphRun.runSize();
      std::vector<SkUnichar> unichars(runSize);
      SkFontPriv::GlyphsToUnichars(glyphRun.font(), glyphRun.glyphsIDs().data(),
                                   runSize, unichars.data());

      // M135: -Wunsafe-buffer-usage rejects raw pointer indexing. Use
      // std::string to hold the bytes; std::string_view is implicit from it.
      std::string base64;
      base64.reserve(runSize);
      for (size_t i = 0; i < runSize; ++i) {
        base64.push_back(static_cast<char>(unichars[i]));
      }

      auto decoded = base::Base64Decode(base64);

      if (!decoded) {
        return;
      }

      data_.push_back(carbonyl::mojom::TextData::New(
          std::string(decoded->begin(), decoded->end()),
          gfx::RectF(position.x(), position.y(), 0, 0), paint.getColor()));
    }
  }

 private:
  SkRect scale(const SkRect& rect) { return localToDevice().mapRect(rect); }
  SkPoint scale(const SkPoint& point) { return localToDevice().mapPoint(point); }

  std::vector<carbonyl::mojom::TextDataPtr> data_;
};

// Owns a TextCaptureDevice and re-uses it across captures of the same
// viewport size.
class RendererService {
 public:
  RendererService() = default;

  SkCanvas* BeginPaint(int width, int height) {
    if (width != width_ || height != height_ || !device_) {
      width_ = width;
      height_ = height;

      device_ = sk_sp(new TextCaptureDevice(
          SkImageInfo::MakeUnknown(width, height),
          SkSurfaceProps(0, kUnknown_SkPixelGeometry)));
      canvas_ = std::make_unique<SkCanvas>(device_);
    }

    device_->clear();

    return canvas_.get();
  }

  void Swap(std::vector<carbonyl::mojom::TextDataPtr>& data) {
    device_->swap(data);
  }

 private:
  int width_ = 0;
  int height_ = 0;
  sk_sp<TextCaptureDevice> device_;
  std::unique_ptr<SkCanvas> canvas_;
};

}  // namespace

bool CaptureFromFrame(blink::WebLocalFrame* frame,
                      std::vector<carbonyl::mojom::TextDataPtr>* out_data) {
  if (!frame || !out_data) {
    return false;
  }

  // Per-frame singleton — re-uses the SkCanvas/TextCaptureDevice across calls
  // to avoid allocating a fresh one on every paint. Owned by the function-local
  // static so it lives as long as the renderer process.
  static RendererService renderer;

  size_t width = frame->DocumentSize().width();
  size_t height = frame->VisibleContentRect().height();

  if (width == 0 || height == 0) {
    return false;
  }

  auto* view = static_cast<blink::WebViewImpl*>(frame->View());
  if (!view) {
    return false;
  }

  auto* main_frame = view->MainFrameImpl();
  if (!main_frame || !main_frame->GetFrame()) {
    return false;
  }

  auto* local_frame_view = main_frame->GetFrame()->View();
  if (!local_frame_view) {
    return false;
  }

  local_frame_view->GetPaintRecord().Playback(
      renderer.BeginPaint(width, height));

  out_data->clear();
  renderer.Swap(*out_data);
  return !out_data->empty();
}

}  // namespace carbonyl::text_capture
