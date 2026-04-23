#include "carbonyl/src/browser/x_mirror.h"

#include <cstdlib>

#include "base/logging.h"

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
    static XMirrorState instance;
    return instance;
  }

  bool enabled() const { return enabled_; }

  void EnsureSize(int width, int height) {
    if (!enabled_ || width <= 0 || height <= 0) {
      return;
    }
    if (window_ != 0 && width == width_ && height == height_) {
      return;
    }

    int screen = DefaultScreen(display_);
    if (window_ == 0) {
      Window root = RootWindow(display_, screen);
      unsigned long black = BlackPixel(display_, screen);
      window_ = XCreateSimpleWindow(display_, root, 0, 0, width, height, 0,
                                    black, black);
      XStoreName(display_, window_, "Carbonyl");
      XSelectInput(display_, window_, ExposureMask);
      XMapWindow(display_, window_);
      gc_ = DefaultGC(display_, screen);
      visual_ = DefaultVisual(display_, screen);
      depth_ = DefaultDepth(display_, screen);
    } else {
      XResizeWindow(display_, window_, width, height);
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
    XFlush(display_);
  }

  void Blit(const uint8_t* pixels, int damage_x, int damage_y,
            int damage_w, int damage_h) {
    if (!enabled_ || !image_ || window_ == 0) {
      return;
    }
    image_->data = reinterpret_cast<char*>(const_cast<uint8_t*>(pixels));
    XPutImage(display_, window_, gc_, image_,
              damage_x, damage_y, damage_x, damage_y,
              static_cast<unsigned int>(damage_w),
              static_cast<unsigned int>(damage_h));
    image_->data = nullptr;
    XFlush(display_);
  }

 private:
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
  Display* display_ = nullptr;
  Window window_ = 0;
  GC gc_ = nullptr;
  Visual* visual_ = nullptr;
  int depth_ = 24;
  XImage* image_ = nullptr;
  int width_ = 0;
  int height_ = 0;
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
