#ifndef CARBONYL_SRC_BROWSER_X_MIRROR_H_
#define CARBONYL_SRC_BROWSER_X_MIRROR_H_

#include <cstdint>

#include "build/build_config.h"
#include "carbonyl/src/browser/export.h"
#include "ui/gfx/native_ui_types.h"

namespace carbonyl::x_mirror {

// Optional X11 mirror surface for the Carbonyl compositor bridge. Enabled
// by setting CARBONYL_X_MIRROR=1 at process start. When enabled, each
// compositor frame is additionally blitted into a visible X window on
// $DISPLAY, alongside the existing terminal render. Allows external
// capture (scrot, ffmpeg, x11vnc) of the actual rendered pixels while the
// trusted-input pipeline and terminal output stay unchanged. Gated off by
// default so headless/terminal-only deployments pay zero runtime cost.
//
// All functions are safe to call unconditionally; they no-op when the
// mirror is disabled or fails to initialize.

CARBONYL_VIZ_EXPORT bool Enabled();

// Return whether `widget` currently owns Carbonyl's compositor output. Before
// an operator window attaches, the synthetic headless compositor remains the
// owner. Once attached, only the matching native widget may render output.
CARBONYL_VIZ_EXPORT bool ShouldRenderCompositor(gfx::AcceleratedWidget widget);

// Route mirror pixels to an embedder-owned X11 accelerated widget. This is
// used by the experimental Views operator host, which owns input and window
// lifetime while Carbonyl continues consuming the same software frame for the
// terminal. Calls with a null widget are ignored.
CARBONYL_VIZ_EXPORT void AttachToWindow(gfx::AcceleratedWidget widget);

// Stop targeting `widget` before its owning Views host is destroyed.
CARBONYL_VIZ_EXPORT void DetachFromWindow(gfx::AcceleratedWidget widget);

// Ensure the retained compositor raster and XImage descriptor are sized to
// (width, height). The initial X window uses this size, but subsequent window
// manager resizes do not resize the compositor: the raster remains fixed and
// is centered, clipped, or letterboxed in the independently-sized X window.
CARBONYL_VIZ_EXPORT void EnsureSize(int width, int height);

// Copy the damaged rect from the Carbonyl compositor shared-memory
// buffer to the mirror window. `pixels` points at the base of the full
// frame (same buffer the terminal renderer consumes); stride is assumed
// to be width * 4 (BGRA8), matching Chromium's software compositor.
CARBONYL_VIZ_EXPORT void Blit(const uint8_t* pixels,
                              int damage_x,
                              int damage_y,
                              int damage_w,
                              int damage_h);

}  // namespace carbonyl::x_mirror

#endif  // CARBONYL_SRC_BROWSER_X_MIRROR_H_
