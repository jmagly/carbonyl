#include "carbonyl/src/browser/operator_window.h"

#include <memory>
#include <utility>

#include "base/command_line.h"
#include "base/logging.h"
#include "build/build_config.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/ozone_buildflags.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"

#if BUILDFLAG(IS_LINUX) && BUILDFLAG(SUPPORTS_OZONE_X11)
#include "ui/aura/window.h"
#include "ui/aura/window_tree_host.h"
#include "ui/views/controls/webview/webview.h"
#include "ui/views/views_delegate.h"
#include "ui/views/widget/desktop_aura/desktop_native_widget_aura.h"
#include "ui/views/widget/widget.h"
#include "ui/wm/core/wm_state.h"
#endif

namespace carbonyl {

#if BUILDFLAG(IS_LINUX) && BUILDFLAG(SUPPORTS_OZONE_X11)
namespace {

class OperatorViewsDelegate final : public views::ViewsDelegate {
 public:
  OperatorViewsDelegate() = default;
  ~OperatorViewsDelegate() override = default;

  void OnBeforeWidgetInit(
      views::Widget::InitParams* params,
      views::internal::NativeWidgetDelegate* delegate) override {
    if (!params->native_widget) {
      params->native_widget = new views::DesktopNativeWidgetAura(delegate);
    }
  }
};

}  // namespace

struct OperatorWindow::Impl {
  // WMState and ViewsDelegate must outlive the Widget.
  std::unique_ptr<wm::WMState> wm_state;
  std::unique_ptr<views::ViewsDelegate> views_delegate;
  std::unique_ptr<views::Widget> widget;
};
#else
struct OperatorWindow::Impl {};
#endif

bool OperatorWindow::IsRequested() {
  return base::CommandLine::ForCurrentProcess()->HasSwitch(
      kOperatorWindowSwitch);
}

std::unique_ptr<OperatorWindow> OperatorWindow::Create(
    content::WebContents* web_contents,
    const gfx::Size& initial_size) {
  if (!IsRequested()) {
    return nullptr;
  }

  auto window = std::unique_ptr<OperatorWindow>(new OperatorWindow());
  if (!window->Initialize(web_contents, initial_size)) {
    return nullptr;
  }
  return window;
}

OperatorWindow::OperatorWindow() = default;

OperatorWindow::~OperatorWindow() = default;

bool OperatorWindow::Initialize(content::WebContents* web_contents,
                                const gfx::Size& initial_size) {
#if BUILDFLAG(IS_LINUX) && BUILDFLAG(SUPPORTS_OZONE_X11)
  if (!web_contents || initial_size.IsEmpty()) {
    LOG(ERROR) << "CARBONYL_OPERATOR_WINDOW invalid WebContents or size";
    return false;
  }
  if (views::ViewsDelegate::GetInstance()) {
    LOG(ERROR) << "CARBONYL_OPERATOR_WINDOW ViewsDelegate already installed";
    return false;
  }

  impl_ = std::make_unique<Impl>();
  impl_->wm_state = std::make_unique<wm::WMState>();
  impl_->views_delegate = std::make_unique<OperatorViewsDelegate>();
  impl_->widget = std::make_unique<views::Widget>();

  views::Widget::InitParams params(
      views::Widget::InitParams::CLIENT_OWNS_WIDGET,
      views::Widget::InitParams::TYPE_WINDOW_FRAMELESS);
  params.bounds = gfx::Rect(initial_size);
  params.name = "CarbonylOperatorWindow";
  params.wm_class_class = "carbonyl";
  params.wm_class_name = "Carbonyl";
  impl_->widget->Init(std::move(params));

  auto web_view =
      std::make_unique<views::WebView>(web_contents->GetBrowserContext());
  web_view->SetWebContents(web_contents);
  impl_->widget->SetContentsView(std::move(web_view));
  impl_->widget->Show();
  impl_->widget->Activate();
  web_contents->Focus();

  aura::Window* native_window = impl_->widget->GetNativeWindow();
  if (!native_window || !native_window->GetHost() ||
      native_window->GetHost()->GetAcceleratedWidget() ==
          gfx::kNullAcceleratedWidget) {
    LOG(ERROR) << "CARBONYL_OPERATOR_WINDOW missing accelerated widget";
    impl_.reset();
    return false;
  }

  LOG(INFO) << "CARBONYL_OPERATOR_WINDOW ready widget="
            << native_window->GetHost()->GetAcceleratedWidget()
            << " size=" << initial_size.ToString();
  return true;
#else
  LOG(ERROR) << "--" << kOperatorWindowSwitch
             << " requires a Linux build with Ozone X11 support";
  return false;
#endif
}

}  // namespace carbonyl
