#include "carbonyl/src/browser/operator_window.h"

#include <memory>
#include <utility>

#include "base/command_line.h"
#include "base/functional/callback.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/scoped_observation.h"
#include "base/task/sequenced_task_runner.h"
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
#include "ui/views/widget/widget_delegate.h"
#include "ui/views/widget/widget_observer.h"
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

// The Views WebView owns continuous content resizing and native event
// translation. This observer owns only window-lifecycle and focus policy; it
// deliberately does not synthesize or forward input events.
class OperatorWidgetObserver final : public views::WidgetObserver {
 public:
  OperatorWidgetObserver(views::Widget* widget,
                         content::WebContents* web_contents,
                         base::OnceClosure close_callback)
      : web_contents_(web_contents),
        close_callback_(std::move(close_callback)) {
    observation_.Observe(widget);
  }

  OperatorWidgetObserver(const OperatorWidgetObserver&) = delete;
  OperatorWidgetObserver& operator=(const OperatorWidgetObserver&) = delete;
  ~OperatorWidgetObserver() override = default;

  void OnWidgetActivationChanged(views::Widget*, bool active) override {
    if (!web_contents_) {
      return;
    }
    if (active) {
      web_contents_->RestoreFocus();
    } else {
      web_contents_->StoreFocus();
    }
  }

  void OnWidgetBoundsChanged(views::Widget* widget,
                             const gfx::Rect& new_bounds) override {
    // WebView::SetFastResize(false) keeps the hosted native view synchronized
    // continuously. Logging the client extent gives operators one coordinate
    // source of truth without opening a second resize path.
    VLOG(1) << "CARBONYL_OPERATOR_WINDOW geometry window="
            << new_bounds.size().ToString()
            << " content="
            << widget->GetClientAreaBoundsInScreen().size().ToString();
  }

  void OnWidgetShowStateChanged(views::Widget* widget) override {
    if (web_contents_ && !widget->IsMinimized() && widget->IsActive()) {
      web_contents_->RestoreFocus();
    }
  }

  void OnWidgetDestroyed(views::Widget*) override {
    observation_.Reset();
    web_contents_ = nullptr;
    if (close_callback_) {
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, std::move(close_callback_));
    }
  }

 private:
  raw_ptr<content::WebContents> web_contents_ = nullptr;
  base::OnceClosure close_callback_;
  base::ScopedObservation<views::Widget, views::WidgetObserver> observation_{
      this};
};

}  // namespace

struct OperatorWindow::Impl {
  // WMState and ViewsDelegate must outlive the Widget.
  std::unique_ptr<wm::WMState> wm_state;
  std::unique_ptr<views::ViewsDelegate> views_delegate;
  std::unique_ptr<views::WidgetDelegate> widget_delegate;
  std::unique_ptr<views::Widget> widget;
  // Declared after Widget so observation ends before an owner-driven Widget
  // destruction and cannot turn normal browser shutdown into a second close.
  std::unique_ptr<OperatorWidgetObserver> observer;
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
    const gfx::Size& initial_size,
    base::OnceClosure close_callback) {
  if (!IsRequested()) {
    return nullptr;
  }

  auto window = std::unique_ptr<OperatorWindow>(new OperatorWindow());
  if (!window->Initialize(web_contents, initial_size,
                          std::move(close_callback))) {
    return nullptr;
  }
  return window;
}

OperatorWindow::OperatorWindow() = default;

OperatorWindow::~OperatorWindow() = default;

bool OperatorWindow::Initialize(content::WebContents* web_contents,
                                const gfx::Size& initial_size,
                                base::OnceClosure close_callback) {
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

  auto web_view =
      std::make_unique<views::WebView>(web_contents->GetBrowserContext());
  web_view->SetWebContents(web_contents);
  web_view->SetFastResize(false);

  impl_->widget_delegate = std::make_unique<views::WidgetDelegate>();
  impl_->widget_delegate->SetContentsView(std::move(web_view));
  impl_->widget_delegate->SetHasWindowSizeControls(true);

  views::Widget::InitParams params(
      views::Widget::InitParams::CLIENT_OWNS_WIDGET);
  params.bounds = gfx::Rect(initial_size);
  params.delegate = impl_->widget_delegate.get();
  params.name = "CarbonylOperatorWindow";
  params.wm_class_class = "carbonyl";
  params.wm_class_name = "Carbonyl";
  impl_->widget->Init(std::move(params));
  impl_->observer = std::make_unique<OperatorWidgetObserver>(
      impl_->widget.get(), web_contents, std::move(close_callback));
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
