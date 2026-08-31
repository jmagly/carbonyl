#ifndef CARBONYL_SRC_BROWSER_OPERATOR_WINDOW_H_
#define CARBONYL_SRC_BROWSER_OPERATOR_WINDOW_H_

#include <memory>

#include "carbonyl/src/browser/export.h"

namespace content {
class WebContents;
}

namespace gfx {
class Size;
}

namespace carbonyl {

inline constexpr char kOperatorWindowSwitch[] = "carbonyl-operator-window";

// Experimental, X11-only Views host for an existing headless WebContents.
// The object owns only the native host; HeadlessWebContentsImpl remains the
// owner of the BrowserContext and WebContents.
class CARBONYL_OPERATOR_EXPORT OperatorWindow {
 public:
  static bool IsRequested();
  static std::unique_ptr<OperatorWindow> Create(
      content::WebContents* web_contents,
      const gfx::Size& initial_size);

  OperatorWindow(const OperatorWindow&) = delete;
  OperatorWindow& operator=(const OperatorWindow&) = delete;

  ~OperatorWindow();

 private:
  struct Impl;

  OperatorWindow();
  bool Initialize(content::WebContents* web_contents,
                  const gfx::Size& initial_size);

  std::unique_ptr<Impl> impl_;
};

}  // namespace carbonyl

#endif  // CARBONYL_SRC_BROWSER_OPERATOR_WINDOW_H_
