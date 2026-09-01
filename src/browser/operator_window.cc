#include "carbonyl/src/browser/operator_window.h"

#include <memory>
#include <utility>

#include "base/command_line.h"
#include "base/functional/callback.h"
#include "base/logging.h"
#include "build/build_config.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/ozone_buildflags.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"

#if BUILDFLAG(IS_LINUX) && BUILDFLAG(SUPPORTS_OZONE_X11)
#include <string>
#include <string_view>
#include <tuple>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/process/termination_status.h"
#include "base/scoped_observation.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "carbonyl/src/browser/operator_controls_model.h"
#include "components/url_formatter/url_fixer.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/ssl_status.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/common/page_type.h"
#include "content/public/common/referrer.h"
#include "net/base/url_util.h"
#include "net/cert/cert_status_flags.h"
#include "ui/aura/window.h"
#include "ui/aura/window_tree_host.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/base/accelerators/accelerator_manager.h"
#include "ui/base/page_transition_types.h"
#include "ui/events/event.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "ui/gfx/geometry/insets.h"
#include "ui/gfx/text_constants.h"
#include "ui/views/controls/button/md_text_button.h"
#include "ui/views/controls/label.h"
#include "ui/views/controls/textfield/textfield.h"
#include "ui/views/controls/textfield/textfield_controller.h"
#include "ui/views/controls/webview/webview.h"
#include "ui/views/focus/focus_manager.h"
#include "ui/views/layout/box_layout.h"
#include "ui/views/layout/layout_provider.h"
#include "ui/views/view.h"
#include "ui/views/views_delegate.h"
#include "ui/views/widget/desktop_aura/desktop_native_widget_aura.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_delegate.h"
#include "ui/views/widget/widget_observer.h"
#include "ui/wm/core/wm_state.h"
#include "url/gurl.h"
#include "url/origin.h"
#include "url/url_constants.h"
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

class OperatorControls final : public content::WebContentsObserver,
                               public views::TextfieldController,
                               public views::FocusChangeListener,
                               public ui::AcceleratorTarget {
 public:
  OperatorControls(content::WebContents* web_contents, views::WebView* web_view)
      : content::WebContentsObserver(web_contents), web_view_(web_view) {}

  OperatorControls(const OperatorControls&) = delete;
  OperatorControls& operator=(const OperatorControls&) = delete;

  ~OperatorControls() override {
    if (focus_manager_) {
      focus_manager_->RemoveFocusChangeListener(this);
      focus_manager_->UnregisterAccelerators(this);
    }
  }

  std::unique_ptr<views::View> BuildContentView(
      std::unique_ptr<views::WebView> web_view) {
    auto root = std::make_unique<views::View>();
    auto* root_layout =
        root->SetLayoutManager(std::make_unique<views::BoxLayout>(
            views::BoxLayout::Orientation::kVertical));

    auto toolbar = std::make_unique<views::View>();
    auto* toolbar_layout =
        toolbar->SetLayoutManager(std::make_unique<views::BoxLayout>(
            views::BoxLayout::Orientation::kHorizontal, gfx::Insets::VH(4, 6),
            4));

    back_button_ = toolbar->AddChildView(std::make_unique<views::MdTextButton>(
        base::BindRepeating(&OperatorControls::GoBack, base::Unretained(this)),
        u"Back"));
    back_button_->SetAccessibleName(u"Back");
    back_button_->SetPreferredSize(gfx::Size(64, 32));

    forward_button_ =
        toolbar->AddChildView(std::make_unique<views::MdTextButton>(
            base::BindRepeating(&OperatorControls::GoForward,
                                base::Unretained(this)),
            u"Forward"));
    forward_button_->SetAccessibleName(u"Forward");
    forward_button_->SetPreferredSize(gfx::Size(80, 32));

    reload_stop_button_ =
        toolbar->AddChildView(std::make_unique<views::MdTextButton>(
            base::BindRepeating(&OperatorControls::ReloadOrStop,
                                base::Unretained(this)),
            u"Reload"));
    reload_stop_button_->SetAccessibleName(u"Reload or stop");
    reload_stop_button_->SetPreferredSize(gfx::Size(72, 32));

    address_ = toolbar->AddChildView(std::make_unique<views::Textfield>());
    address_->SetController(this);
    address_->SetAccessibleName(u"Address and search");
    address_->SetPlaceholderText(u"Enter address or search");
    toolbar_layout->SetFlexForView(address_, 1, true);

    root->AddChildView(std::move(toolbar));

    origin_label_ = root->AddChildView(std::make_unique<views::Label>());
    origin_label_->SetAccessibleName(u"Committed origin security status");
    origin_label_->SetHorizontalAlignment(gfx::ALIGN_LEFT);
    origin_label_->SetElideBehavior(gfx::ELIDE_MIDDLE);

    views::WebView* added_web_view = root->AddChildView(std::move(web_view));
    CHECK_EQ(added_web_view, web_view_);
    root_layout->SetFlexForView(added_web_view, 1);
    UpdateState();
    return root;
  }

  void AttachToWidget(views::Widget* widget) {
    focus_manager_ = widget->GetFocusManager();
    CHECK(focus_manager_);
    focus_manager_->AddFocusChangeListener(this);

    RegisterAccelerator(ui::VKEY_L, ui::EF_CONTROL_DOWN);
    RegisterAccelerator(ui::VKEY_R, ui::EF_CONTROL_DOWN);
    RegisterAccelerator(ui::VKEY_F5, ui::EF_NONE);
    RegisterAccelerator(ui::VKEY_LEFT, ui::EF_ALT_DOWN);
    RegisterAccelerator(ui::VKEY_RIGHT, ui::EF_ALT_DOWN);
  }

  // content::WebContentsObserver:
  void DidFinishNavigation(
      content::NavigationHandle* navigation_handle) override {
    if (navigation_handle->HasCommitted() &&
        navigation_handle->IsInPrimaryMainFrame()) {
      renderer_failed_ = false;
      UpdateState();
    }
  }

  void NavigationEntryCommitted(const content::LoadCommittedDetails&) override {
    UpdateState();
  }

  void NavigationEntryChanged(const content::EntryChangedDetails&) override {
    UpdateState();
  }

  void DidStartLoading() override { UpdateState(); }
  void DidStopLoading() override { UpdateState(); }

  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override {
    renderer_failed_ = true;
    UpdateState();
  }

  // views::TextfieldController:
  bool HandleKeyEvent(views::Textfield* sender,
                      const ui::KeyEvent& event) override {
    if (sender != address_ || event.type() != ui::EventType::kKeyPressed) {
      return false;
    }
    if (event.key_code() == ui::VKEY_RETURN) {
      SubmitAddress();
      return true;
    }
    if (event.key_code() == ui::VKEY_ESCAPE) {
      RestoreAddressAndPageFocus();
      return true;
    }
    return false;
  }

  // views::FocusChangeListener:
  void OnDidChangeFocus(views::View* focused_before,
                        views::View* focused_now) override {
    if (focused_before == address_ && focused_now != address_) {
      UpdateState();
    }
  }

  void OnFocusManagerDestroying(views::FocusManager*) override {
    focus_manager_ = nullptr;
  }

  // ui::AcceleratorTarget:
  bool AcceleratorPressed(const ui::Accelerator& accelerator) override {
    if (accelerator == ui::Accelerator(ui::VKEY_L, ui::EF_CONTROL_DOWN)) {
      address_->RequestFocus();
      address_->SelectAll(false);
      return true;
    }
    if (accelerator == ui::Accelerator(ui::VKEY_R, ui::EF_CONTROL_DOWN) ||
        accelerator == ui::Accelerator(ui::VKEY_F5, ui::EF_NONE)) {
      ReloadOrStop();
      return true;
    }
    if (accelerator == ui::Accelerator(ui::VKEY_LEFT, ui::EF_ALT_DOWN)) {
      GoBack();
      return true;
    }
    if (accelerator == ui::Accelerator(ui::VKEY_RIGHT, ui::EF_ALT_DOWN)) {
      GoForward();
      return true;
    }
    return false;
  }

  bool CanHandleAccelerators() const override {
    return web_contents() != nullptr;
  }

 private:
  void RegisterAccelerator(ui::KeyboardCode key_code, int modifiers) {
    // These browser controls are the isolated case for high-priority
    // accelerators: a handled browser command must not also reach page script.
    focus_manager_->RegisterAccelerator(ui::Accelerator(key_code, modifiers),
                                        ui::AcceleratorManager::kHighPriority,
                                        this);
  }

  void GoBack() {
    if (web_contents() && web_contents()->GetController().CanGoBack()) {
      std::ignore = web_contents()->GetController().GoBack();
    }
  }

  void GoForward() {
    if (web_contents() && web_contents()->GetController().CanGoForward()) {
      std::ignore = web_contents()->GetController().GoForward();
    }
  }

  void ReloadOrStop() {
    if (!web_contents()) {
      return;
    }
    if (web_contents()->IsLoading()) {
      web_contents()->Stop();
    } else {
      web_contents()->GetController().Reload(content::ReloadType::NORMAL, true);
    }
  }

  void SubmitAddress() {
    if (!web_contents()) {
      return;
    }
    const GURL target = ResolveAddress(address_->GetText());
    if (!target.is_valid()) {
      RestoreAddressAndPageFocus();
      return;
    }
    web_contents()->GetController().LoadURL(
        target, content::Referrer(), ui::PAGE_TRANSITION_TYPED, std::string());
    web_view_->RequestFocus();
    address_->SetText(base::UTF8ToUTF16(target.spec()));
  }

  GURL ResolveAddress(std::u16string_view input) const {
    std::string typed = base::UTF16ToUTF8(input);
    base::TrimWhitespaceASCII(typed, base::TRIM_ALL, &typed);
    if (typed.empty()) {
      return GURL();
    }

    const GURL fixed = url_formatter::FixupURL(typed);
    const bool allowed = fixed.SchemeIsHTTPOrHTTPS() || fixed.SchemeIsFile() ||
                         fixed.SchemeIs(url::kAboutScheme) ||
                         fixed.SchemeIs("chrome");
    const std::string scheme_prefix = fixed.scheme() + ":";
    const bool explicit_scheme =
        !fixed.scheme().empty() &&
        base::StartsWith(typed, scheme_prefix,
                         base::CompareCase::INSENSITIVE_ASCII);
    if (!ShouldSearchOperatorAddress(typed, fixed.is_valid(), allowed,
                                     explicit_scheme, fixed.HostIsIPAddress(),
                                     fixed.host())) {
      return fixed;
    }
    return net::AppendQueryParameter(GURL("https://duckduckgo.com/"), "q",
                                     typed);
  }

  void RestoreAddressAndPageFocus() {
    UpdateState(/*force_address=*/true);
    web_view_->RequestFocus();
  }

  void UpdateState(bool force_address = false) {
    if (!web_contents() || !back_button_) {
      return;
    }
    content::NavigationController& controller = web_contents()->GetController();
    back_button_->SetEnabled(controller.CanGoBack());
    forward_button_->SetEnabled(controller.CanGoForward());
    reload_stop_button_->SetText(web_contents()->IsLoading() ? u"Stop"
                                                             : u"Reload");

    content::NavigationEntry* entry = controller.GetLastCommittedEntry();
    if (!entry) {
      origin_label_->SetText(u"Internal - no committed page");
      return;
    }
    if (force_address || !address_->HasFocus()) {
      address_->SetText(base::UTF8ToUTF16(entry->GetVirtualURL().spec()));
    }

    const GURL& committed_url = entry->GetURL();
    const content::SSLStatus& ssl = entry->GetSSL();
    const int insecure_content =
        content::SSLStatus::DISPLAYED_INSECURE_CONTENT |
        content::SSLStatus::RAN_INSECURE_CONTENT |
        content::SSLStatus::DISPLAYED_FORM_WITH_INSECURE_ACTION;
    const int certificate_content =
        content::SSLStatus::DISPLAYED_CONTENT_WITH_CERT_ERRORS |
        content::SSLStatus::RAN_CONTENT_WITH_CERT_ERRORS;

    OperatorSecuritySignals signals;
    signals.error_page =
        renderer_failed_ || entry->GetPageType() == content::PAGE_TYPE_ERROR;
    signals.file = committed_url.SchemeIsFile();
    signals.local = net::IsLocalhost(committed_url);
    signals.https = committed_url.SchemeIs(url::kHttpsScheme);
    signals.internal =
        !signals.file && !signals.local && !committed_url.SchemeIsHTTPOrHTTPS();
    signals.ssl_initialized = ssl.initialized;
    signals.certificate_error = net::IsCertStatusError(ssl.cert_status) ||
                                (ssl.content_status & certificate_content) != 0;
    signals.insecure_content = (ssl.content_status & insecure_content) != 0;

    const url::Origin origin = url::Origin::Create(committed_url);
    std::string committed_origin;
    if (signals.file) {
      committed_origin = "file://";
    } else if (!origin.opaque()) {
      committed_origin = origin.Serialize();
    } else if (committed_url.has_scheme()) {
      committed_origin = committed_url.scheme() + ":";
    }
    const OperatorSecurityPresentation presentation =
        BuildOperatorSecurityPresentation(signals, committed_origin);
    origin_label_->SetText(base::UTF8ToUTF16(presentation.label));
    VLOG(1) << "CARBONYL_OPERATOR_CONTROLS back=" << controller.CanGoBack()
            << " forward=" << controller.CanGoForward()
            << " loading=" << web_contents()->IsLoading()
            << " security=" << presentation.label;
  }

  raw_ptr<views::WebView> web_view_;
  raw_ptr<views::MdTextButton> back_button_ = nullptr;
  raw_ptr<views::MdTextButton> forward_button_ = nullptr;
  raw_ptr<views::MdTextButton> reload_stop_button_ = nullptr;
  raw_ptr<views::Textfield> address_ = nullptr;
  raw_ptr<views::Label> origin_label_ = nullptr;
  raw_ptr<views::FocusManager> focus_manager_ = nullptr;
  bool renderer_failed_ = false;
};

// The Views WebView owns continuous content resizing and native event
// translation. This observer owns only window-lifecycle and focus policy; it
// deliberately does not synthesize or forward input events.
class OperatorWidgetObserver final : public views::WidgetObserver {
 public:
  OperatorWidgetObserver(views::Widget* widget,
                         content::WebContents* web_contents,
                         views::WebView* web_view,
                         base::OnceClosure close_callback)
      : web_contents_(web_contents->GetWeakPtr()),
        web_view_(web_view),
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
      if (web_view_->HasFocus()) {
        web_contents_->RestoreFocus();
      }
    } else if (web_view_->HasFocus()) {
      web_contents_->StoreFocus();
    }
  }

  void OnWidgetBoundsChanged(views::Widget* widget,
                             const gfx::Rect& new_bounds) override {
    // WebView::SetFastResize(false) keeps the hosted native view synchronized
    // continuously. Logging the client extent gives operators one coordinate
    // source of truth without opening a second resize path.
    VLOG(1) << "CARBONYL_OPERATOR_WINDOW geometry window="
            << new_bounds.size().ToString() << " content="
            << widget->GetClientAreaBoundsInScreen().size().ToString();
  }

  void OnWidgetShowStateChanged(views::Widget* widget) override {
    if (web_contents_ && web_view_->HasFocus() && !widget->IsMinimized() &&
        widget->IsActive()) {
      web_contents_->RestoreFocus();
    }
  }

  void OnWidgetDestroyed(views::Widget*) override {
    observation_.Reset();
    web_contents_.reset();
    if (close_callback_) {
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, std::move(close_callback_));
    }
  }

 private:
  // HeadlessBrowserImpl destroys BrowserContexts (and therefore WebContents)
  // before its posted quit task runs. Keep a weak handle so late native
  // activation/show-state notifications during that drain cannot dereference
  // a destroyed page.
  base::WeakPtr<content::WebContents> web_contents_;
  raw_ptr<views::WebView> web_view_;
  base::OnceClosure close_callback_;
  base::ScopedObservation<views::Widget, views::WidgetObserver> observation_{
      this};
};

}  // namespace

struct OperatorWindow::Impl {
  // WMState, LayoutProvider, ViewsDelegate, WidgetDelegate, and button
  // callbacks must outlive the Widget. Field order makes Widget destruction
  // invalidate the Views pointers and notify FocusManager teardown before
  // Controls is destroyed.
  std::unique_ptr<wm::WMState> wm_state;
  std::unique_ptr<views::LayoutProvider> layout_provider;
  std::unique_ptr<views::ViewsDelegate> views_delegate;
  std::unique_ptr<views::WidgetDelegate> widget_delegate;
  std::unique_ptr<OperatorControls> controls;
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
  if (!views::LayoutProvider::Get()) {
    impl_->layout_provider = std::make_unique<views::LayoutProvider>();
  }
  impl_->views_delegate = std::make_unique<OperatorViewsDelegate>();
  impl_->widget = std::make_unique<views::Widget>();

  auto web_view =
      std::make_unique<views::WebView>(web_contents->GetBrowserContext());
  web_view->SetWebContents(web_contents);
  web_view->SetFastResize(false);
  views::WebView* web_view_ptr = web_view.get();
  impl_->controls =
      std::make_unique<OperatorControls>(web_contents, web_view_ptr);

  impl_->widget_delegate = std::make_unique<views::WidgetDelegate>();
  impl_->widget_delegate->SetContentsView(
      impl_->controls->BuildContentView(std::move(web_view)));
  impl_->widget_delegate->SetHasWindowSizeControls(true);

  views::Widget::InitParams params(
      views::Widget::InitParams::CLIENT_OWNS_WIDGET);
  params.bounds = gfx::Rect(initial_size);
  params.delegate = impl_->widget_delegate.get();
  params.name = "CarbonylOperatorWindow";
  params.wm_class_class = "carbonyl";
  params.wm_class_name = "Carbonyl";
  impl_->widget->Init(std::move(params));
  impl_->controls->AttachToWidget(impl_->widget.get());
  impl_->observer = std::make_unique<OperatorWidgetObserver>(
      impl_->widget.get(), web_contents, web_view_ptr,
      std::move(close_callback));
  impl_->widget->Show();
  impl_->widget->Activate();
  // Enter the Views focus chain so WebView and the RenderWidgetHost agree on
  // the focused text-input client. Calling WebContents::Focus() directly
  // bypasses the FocusManager side of that contract.
  web_view_ptr->RequestFocus();

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
