#ifndef CARBONYL_SRC_VIZ_CARBONYL_SOFTWARE_OUTPUT_DEVICE_H_
#define CARBONYL_SRC_VIZ_CARBONYL_SOFTWARE_OUTPUT_DEVICE_H_

#include <memory>

#include "base/memory/shared_memory_mapping.h"
#include "base/threading/thread_checker.h"
#include "build/build_config.h"
#include "components/viz/service/display/software_output_device.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "services/viz/privileged/mojom/compositing/layered_window_updater.mojom.h"

namespace carbonyl {

// Carbonyl-owned copy of the former viz::SoftwareOutputDeviceBase helper.
// That class was introduced by Carbonyl's patch 0013 and lived in
// components/viz/service/display_embedder/software_output_device_proxy.h.
// The upstream proxy architecture it depended on was removed after M132, so
// both the base class and the concrete class now live in the Carbonyl tree.
//
// Splits Resize/BeginPaint/EndPaint into delegated virtual methods so that
// subclasses only need to implement the allocation/draw/swap hooks.
class SoftwareOutputDeviceBase : public viz::SoftwareOutputDevice {
 public:
  SoftwareOutputDeviceBase() = default;
  ~SoftwareOutputDeviceBase() override;

  SoftwareOutputDeviceBase(const SoftwareOutputDeviceBase&) = delete;
  SoftwareOutputDeviceBase& operator=(const SoftwareOutputDeviceBase&) = delete;

  // viz::SoftwareOutputDevice implementation.
  void Resize(const gfx::Size& viewport_pixel_size,
              float scale_factor) override;
  SkCanvas* BeginPaint(const gfx::Rect& damage_rect) override;
  void EndPaint() override;

  // Called from Resize() when |viewport_pixel_size_| changes.
  virtual void ResizeDelegated() = 0;

  // Called from BeginPaint(); must return the SkCanvas to draw into.
  virtual SkCanvas* BeginPaintDelegated() = 0;

  // Called from EndPaint() when the damage rect is non-empty.
  virtual void EndPaintDelegated(const gfx::Rect& damage_rect) = 0;

 private:
  bool in_paint_ = false;

  THREAD_CHECKER(thread_checker_);
};

// Carbonyl's concrete SoftwareOutputDevice for headless rendering.
//
// Allocates a shared-memory pixel buffer and forwards each painted frame to
// the browser process via mojom::LayeredWindowUpdater, which calls
// Renderer::DrawBitmap() in host_display_client.cc. This is the mechanism
// that pipes Chromium's composited output to Carbonyl's Rust renderer.
//
// This class is a Carbonyl-tree replacement for the upstream
// SoftwareOutputDeviceProxy (removed after M132). Patch 0013 formerly created
// the proxy as a new file in components/viz/service/display_embedder/; it is
// now owned here so that no Chromium tree file is required.
//
// Patch 0013 (rewritten for M135) must:
//   1. Include "carbonyl/src/viz/carbonyl_software_output_device.h" in
//      output_surface_provider_impl.cc.
//   2. Instantiate CarbonylSoftwareOutputDevice instead of SoftwareOutputDeviceProxy.
//   3. Add "//carbonyl/src/viz:viz" as a dep in components/viz/service/BUILD.gn.
class CarbonylSoftwareOutputDevice : public SoftwareOutputDeviceBase {
 public:
  explicit CarbonylSoftwareOutputDevice(
      mojo::PendingRemote<viz::mojom::LayeredWindowUpdater>
          layered_window_updater);
  ~CarbonylSoftwareOutputDevice() override;

  CarbonylSoftwareOutputDevice(const CarbonylSoftwareOutputDevice&) = delete;
  CarbonylSoftwareOutputDevice& operator=(
      const CarbonylSoftwareOutputDevice&) = delete;

  // viz::SoftwareOutputDevice implementation.
  void OnSwapBuffers(
      viz::SoftwareOutputDevice::SwapBuffersCallback swap_ack_callback,
      gfx::FrameData data) override;

  // SoftwareOutputDeviceBase implementation.
  void ResizeDelegated() override;
  SkCanvas* BeginPaintDelegated() override;
  void EndPaintDelegated(const gfx::Rect& rect) override;

 private:
  // Called by the browser-side DrawAck Mojo callback.
  void DrawAck();

  mojo::Remote<viz::mojom::LayeredWindowUpdater> layered_window_updater_;

  std::unique_ptr<SkCanvas> canvas_;
  bool waiting_on_draw_ack_ = false;
  viz::SoftwareOutputDevice::SwapBuffersCallback swap_ack_callback_;

  // Shared memory mapping that backs canvas_. Not used on Windows (Windows
  // uses a platform canvas backed by an HBITMAP section instead).
#if !defined(WIN32)
  base::WritableSharedMemoryMapping shm_mapping_;
#endif
};

}  // namespace carbonyl

#endif  // CARBONYL_SRC_VIZ_CARBONYL_SOFTWARE_OUTPUT_DEVICE_H_
