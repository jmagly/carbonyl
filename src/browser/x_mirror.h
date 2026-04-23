#ifndef CARBONYL_SRC_BROWSER_X_MIRROR_H_
#define CARBONYL_SRC_BROWSER_X_MIRROR_H_

#include <cstdint>

#include "build/build_config.h"
#include "carbonyl/src/browser/export.h"

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

// Ensure the mirror window and backing XImage descriptor are sized to
// (width, height). Safe to call on every frame; creates the window
// lazily on first call and only reacts when the size changes.
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
