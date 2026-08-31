#include "carbonyl/src/browser/x_mirror.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "base/compiler_specific.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/raw_ptr_exclusion.h"
#include "base/no_destructor.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"

#if BUILDFLAG(IS_LINUX)
// Xlib.h pollutes the global namespace heavily (Bool, Status, None, etc.)
// Keep it confined to this translation unit; other Carbonyl code goes
// through the small API declared in x_mirror.h.
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#endif

namespace carbonyl::x_mirror {

#if BUILDFLAG(IS_LINUX)

namespace {

class XMirrorState {
 public:
  static XMirrorState& Get() {
    static base::NoDestructor<XMirrorState> instance;
    return *instance;
  }

  bool enabled() const { return enabled_; }

  void EnsureSize(int width, int height) {
    if (!enabled_ || width <= 0 || height <= 0) {
      return;
    }
    PumpEvents();
    if (!enabled_ || (window_ != 0 && width == width_ && height == height_)) {
      return;
    }

    // Use the function-form Xlib entry points (XDefaultScreen, XRootWindow,
    // ...) instead of the DefaultScreen/RootWindow macros. The macros
    // expand to direct struct access (ScreenOfDisplay(dpy, scr) indexes
    // screens[scr]) which Chromium's -Wunsafe-buffer-usage plugin flags.
    int screen = XDefaultScreen(display_);
    if (window_ == 0) {
      Window root = XRootWindow(display_, screen);
      unsigned long black = XBlackPixel(display_, screen);
      window_ = XCreateSimpleWindow(display_, root, 0, 0, width, height, 0,
                                    black, black);
      XStoreName(display_, window_, "Carbonyl");
      XSelectInput(display_, window_, ExposureMask | StructureNotifyMask);
      wm_delete_window_ = XInternAtom(display_, "WM_DELETE_WINDOW", False);
      XSetWMProtocols(display_, window_, &wm_delete_window_, 1);
      XMapWindow(display_, window_);
      gc_ = XDefaultGC(display_, screen);
      visual_ = XDefaultVisual(display_, screen);
      depth_ = XDefaultDepth(display_, screen);
      window_width_ = width;
      window_height_ = height;
      ScheduleEventPump();
    }

    // Recreate the XImage descriptor at the new size. We never own the
    // pixel buffer — .data is swapped in per-frame to point at the
    // compositor's shared-memory mapping.
    if (image_) {
      image_->data = nullptr;
      XDestroyImage(image_);
      image_ = nullptr;
    }
    image_ = XCreateImage(display_, visual_, depth_, ZPixmap, 0,
                          /*data=*/nullptr, width, height,
                          /*bitmap_pad=*/32,
                          /*bytes_per_line=*/width * 4);
    width_ = width;
    height_ = height;
    frame_.assign(static_cast<size_t>(width_) * height_ * 4, 0);
    has_frame_ = false;
    XFlush(display_);
  }

  void Blit(const uint8_t* pixels, int damage_x, int damage_y,
            int damage_w, int damage_h) {
    if (!enabled_ || !image_ || window_ == 0) {
      return;
    }
    PumpEvents();
    if (!enabled_ || !pixels || damage_w <= 0 || damage_h <= 0) {
      return;
    }

    const int left = std::clamp(damage_x, 0, width_);
    const int top = std::clamp(damage_y, 0, height_);
    const int right = std::clamp(damage_x + damage_w, 0, width_);
    const int bottom = std::clamp(damage_y + damage_h, 0, height_);
    if (left >= right || top >= bottom) {
      return;
    }
    if (!has_frame_) {
      UNSAFE_BUFFERS(std::memcpy(frame_.data(), pixels, frame_.size()));
    } else {
      for (int y = top; y < bottom; ++y) {
        UNSAFE_BUFFERS(std::memcpy(
            frame_.data() + (static_cast<size_t>(y) * width_ + left) * 4,
            pixels + (static_cast<size_t>(y) * width_ + left) * 4,
            static_cast<size_t>(right - left) * 4));
      }
    }
    has_frame_ = true;
    Paint(left, top, right - left, bottom - top, /*clear_window=*/false);
    XFlush(display_);
  }

  void PumpEvents() {
    if (!enabled_ || !display_ || window_ == 0) {
      return;
    }
    bool repaint = false;
    bool clear_window = false;
    while (XPending(display_) > 0) {
      XEvent event;
      XNextEvent(display_, &event);
      if (event.xany.window != window_) {
        continue;
      }
      switch (event.type) {
        case Expose:
          repaint = repaint || event.xexpose.count == 0;
          break;
        case ConfigureNotify:
          window_width_ = event.xconfigure.width;
          window_height_ = event.xconfigure.height;
          repaint = true;
          clear_window = true;
          break;
        case ClientMessage:
          if (static_cast<Atom>(event.xclient.data.l[0]) ==
              wm_delete_window_) {
            XDestroyWindow(display_, window_);
            window_ = 0;
            enabled_ = false;
            return;
          }
          break;
        case DestroyNotify:
          window_ = 0;
          enabled_ = false;
          return;
      }
    }
    if (repaint && has_frame_) {
      Paint(0, 0, width_, height_, clear_window);
      XFlush(display_);
    }
  }

 private:
  friend class base::NoDestructor<XMirrorState>;

  void Paint(int source_x,
             int source_y,
             int paint_width,
             int paint_height,
             bool clear_window) {
    if (!image_ || !has_frame_ || window_ == 0) {
      return;
    }
    if (clear_window) {
      XClearWindow(display_, window_);
    }
    const int crop_x = std::max(0, (width_ - window_width_) / 2);
    const int crop_y = std::max(0, (height_ - window_height_) / 2);
    const int offset_x = std::max(0, (window_width_ - width_) / 2);
    const int offset_y = std::max(0, (window_height_ - height_) / 2);
    const int clipped_source_x = std::max(source_x, crop_x);
    const int clipped_source_y = std::max(source_y, crop_y);
    const int clipped_right =
        std::min(source_x + paint_width, crop_x + window_width_);
    const int clipped_bottom =
        std::min(source_y + paint_height, crop_y + window_height_);
    if (clipped_source_x >= clipped_right ||
        clipped_source_y >= clipped_bottom) {
      return;
    }
    image_->data = reinterpret_cast<char*>(frame_.data());
    XPutImage(display_, window_, gc_, image_, clipped_source_x,
              clipped_source_y, clipped_source_x - crop_x + offset_x,
              clipped_source_y - crop_y + offset_y,
              static_cast<unsigned int>(clipped_right - clipped_source_x),
              static_cast<unsigned int>(clipped_bottom - clipped_source_y));
    image_->data = nullptr;
  }

  void ScheduleEventPump() {
    if (event_pump_scheduled_) {
      return;
    }
    event_pump_scheduled_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE,
        base::BindOnce(&XMirrorState::RunScheduledEventPump,
                       base::Unretained(this)),
        base::Milliseconds(50));
  }

  void RunScheduledEventPump() {
    event_pump_scheduled_ = false;
    PumpEvents();
    if (enabled_ && window_ != 0) {
      ScheduleEventPump();
    }
  }

  XMirrorState() {
    const char* flag = std::getenv("CARBONYL_X_MIRROR");
    if (!flag || flag[0] == '\0' || flag[0] == '0') {
      return;
    }
    const char* display_env = std::getenv("DISPLAY");
    if (!display_env || !*display_env) {
      LOG(WARNING) << "CARBONYL_X_MIRROR set but DISPLAY unset";
      return;
    }
    display_ = XOpenDisplay(display_env);
    if (!display_) {
      LOG(WARNING) << "CARBONYL_X_MIRROR: XOpenDisplay(" << display_env
                   << ") failed";
      return;
    }
    enabled_ = true;
    LOG(INFO) << "CARBONYL_X_MIRROR enabled on DISPLAY=" << display_env;
  }

  // Process-lifetime; no explicit cleanup. X server reclaims on exit.
  ~XMirrorState() = default;

  bool enabled_ = false;
  // Xlib-owned handles; lifetime managed by the X server / libX11, not by
  // this process. RAW_PTR_EXCLUSION opts these fields out of the
  // chromium-rawptr plugin (raw_ptr<T> assumes Chromium-style ownership).
  RAW_PTR_EXCLUSION Display* display_ = nullptr;
  Window window_ = 0;
  Atom wm_delete_window_ = 0;
  GC gc_ = nullptr;
  RAW_PTR_EXCLUSION Visual* visual_ = nullptr;
  int depth_ = 24;
  RAW_PTR_EXCLUSION XImage* image_ = nullptr;
  int width_ = 0;
  int height_ = 0;
  int window_width_ = 0;
  int window_height_ = 0;
  std::vector<uint8_t> frame_;
  bool has_frame_ = false;
  bool event_pump_scheduled_ = false;
};

}  // namespace

bool Enabled() {
  return XMirrorState::Get().enabled();
}

void EnsureSize(int width, int height) {
  XMirrorState::Get().EnsureSize(width, height);
}

void Blit(const uint8_t* pixels, int damage_x, int damage_y,
          int damage_w, int damage_h) {
  XMirrorState::Get().Blit(pixels, damage_x, damage_y, damage_w, damage_h);
}

#else  // !BUILDFLAG(IS_LINUX)

bool Enabled() { return false; }
void EnsureSize(int, int) {}
void Blit(const uint8_t*, int, int, int, int) {}

#endif  // BUILDFLAG(IS_LINUX)

}  // namespace carbonyl::x_mirror
