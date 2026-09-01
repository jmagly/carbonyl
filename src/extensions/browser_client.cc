#include "carbonyl/src/extensions/browser_client.h"

#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "base/command_line.h"
#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/notreached.h"
#include "base/values.h"
#include "base/version.h"
#include "build/build_config.h"
#include "build/chromeos_buildflags.h"
#include "content/public/browser/browser_context.h"
#include "extensions/browser/api/runtime/runtime_api_delegate.h"
#include "extensions/browser/extension_host_delegate.h"
#include "extensions/browser/extensions_browser_client.h"
#include "extensions/common/extension_id.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "net/http/http_response_headers.h"
#include "services/network/public/mojom/url_loader.mojom.h"

namespace extensions {
namespace {

class CarbonylExtensionsBrowserClient : public ExtensionsBrowserClient {
 public:
  CarbonylExtensionsBrowserClient() = default;
  ~CarbonylExtensionsBrowserClient() override = default;

  void Init() override {}

  void StartTearDown() override { shutting_down_ = true; }

  bool IsShuttingDown() override { return shutting_down_; }

  bool AreExtensionsDisabled(const base::CommandLine& command_line,
                             content::BrowserContext* context) override {
    return true;
  }

  bool IsValidContext(void* context) override {
    return context != nullptr && !shutting_down_;
  }

  bool IsSameContext(content::BrowserContext* first,
                     content::BrowserContext* second) override {
    return first == second;
  }

  bool HasOffTheRecordContext(content::BrowserContext* context) override {
    return false;
  }

  content::BrowserContext* GetOffTheRecordContext(
      content::BrowserContext* context) override {
    return nullptr;
  }

  content::BrowserContext* GetOriginalContext(
      content::BrowserContext* context) override {
    return context;
  }

  content::BrowserContext* GetContextRedirectedToOriginal(
      content::BrowserContext* context) override {
    return context;
  }

  content::BrowserContext*
  GetContextRedirectedToOriginalWithoutAshInternals(
      content::BrowserContext* context) override {
    return context;
  }

  content::BrowserContext* GetContextOwnInstance(
      content::BrowserContext* context) override {
    return context;
  }

  content::BrowserContext* GetContextForOriginalOnly(
      content::BrowserContext* context) override {
    return context && !context->IsOffTheRecord() ? context : nullptr;
  }

  bool AreExtensionsDisabledForContext(
      content::BrowserContext* context) override {
    return true;
  }

#if BUILDFLAG(IS_CHROMEOS)
  bool IsActiveContext(
      content::BrowserContext* browser_context) const override {
    return false;
  }

  std::string GetUserIdHashFromContext(
      content::BrowserContext* context) override {
    return std::string();
  }
#endif

  bool IsGuestSession(content::BrowserContext* context) const override {
    return false;
  }

  bool IsExtensionIncognitoEnabled(
      const ExtensionId& extension_id,
      content::BrowserContext* context) const override {
    return false;
  }

  bool IsExtensionIncognitoEnabled(
      const Extension* extension,
      content::BrowserContext* context) const override {
    return false;
  }

  bool CanExtensionCrossIncognito(
      const Extension* extension,
      content::BrowserContext* context) const override {
    return false;
  }

  base::FilePath GetBundleResourcePath(
      const network::ResourceRequest& request,
      const base::FilePath& extension_resources_path,
      int* resource_id) const override {
    *resource_id = 0;
    return base::FilePath();
  }

  void LoadResourceFromResourceBundle(
      const network::ResourceRequest& request,
      mojo::PendingReceiver<network::mojom::URLLoader> loader,
      const base::FilePath& resource_relative_path,
      int resource_id,
      scoped_refptr<net::HttpResponseHeaders> headers,
      mojo::PendingRemote<network::mojom::URLLoaderClient> client) override {
    NOTREACHED() << "Carbonyl does not expose component extension resources";
  }

  bool AllowCrossRendererResourceLoad(
      const network::ResourceRequest& request,
      network::mojom::RequestDestination destination,
      ui::PageTransition page_transition,
      content::ChildProcessId child_id,
      bool is_incognito,
      const Extension* extension,
      const ExtensionSet& extensions,
      const ProcessMap& process_map,
      const GURL& upstream_url) override {
    return false;
  }

  void GetEarlyExtensionPrefsObservers(
      content::BrowserContext* context,
      std::vector<EarlyExtensionPrefsObserver*>* observers) const override {}

  ProcessManagerDelegate* GetProcessManagerDelegate() const override {
    return nullptr;
  }

  mojo::PendingRemote<network::mojom::URLLoaderFactory>
  GetControlledFrameEmbedderURLLoader(
      const url::Origin& app_origin,
      content::FrameTreeNodeId frame_tree_node_id,
      content::BrowserContext* browser_context) override {
    return mojo::PendingRemote<network::mojom::URLLoaderFactory>();
  }

  std::unique_ptr<ExtensionHostDelegate>
  CreateExtensionHostDelegate() override {
    return nullptr;
  }

  bool DidVersionUpdate(content::BrowserContext* context) override {
    return false;
  }

  void PermitExternalProtocolHandler() override {}
  bool IsInDemoMode() override { return false; }
  bool IsScreensaverInDemoMode(const std::string& app_id) override {
    return false;
  }
  bool IsRunningInForcedAppMode() override { return false; }
  bool IsAppModeForcedForApp(const ExtensionId& extension_id) override {
    return false;
  }
  bool IsLoggedInAsPublicAccount() override { return false; }

  ExtensionSystemProvider* GetExtensionSystemFactory() override {
    return nullptr;
  }

  void RegisterBrowserInterfaceBindersForFrame(
      mojo::BinderMapWithContext<content::RenderFrameHost*>* binder_map,
      content::RenderFrameHost* render_frame_host,
      const Extension* extension) const override {}

  std::unique_ptr<RuntimeAPIDelegate> CreateRuntimeAPIDelegate(
      content::BrowserContext* context) const override {
    return nullptr;
  }

  const ComponentExtensionResourceManager*
  GetComponentExtensionResourceManager() override {
    return nullptr;
  }

  void BroadcastEventToRenderers(
      events::HistogramValue histogram_value,
      const std::string& event_name,
      base::ListValue args,
      bool dispatch_to_off_the_record_profiles) override {}

  ExtensionCache* GetExtensionCache() override { return nullptr; }
  bool IsBackgroundUpdateAllowed() override { return false; }
  bool IsMinBrowserVersionSupported(const std::string& min_version) override {
    return false;
  }

  void CreateExtensionWebContentsObserver(
      content::WebContents* web_contents) override {}

  ExtensionWebContentsObserver* GetExtensionWebContentsObserver(
      content::WebContents* web_contents) override {
    return nullptr;
  }

  KioskDelegate* GetKioskDelegate() override { return nullptr; }
  SafeBrowsingDelegate* GetSafeBrowsingDelegate() override { return nullptr; }
  UserScriptListener* GetUserScriptListener() override { return nullptr; }
  std::string GetApplicationLocale() override { return "en-US"; }

  ExtensionManagementClient* GetExtensionManagementClient(
      content::BrowserContext* context) override {
    return nullptr;
  }

  bool CanUseNonComponentExtensions(
      content::BrowserContext* context) override {
    return false;
  }

  void CanInstallExtensionByPolicy(
      content::BrowserContext* context,
      const ExtensionId& extension_id,
      const base::Version& extension_version,
      base::OnceCallback<void(bool, std::u16string)> callback) override {
    std::move(callback).Run(false, u"Carbonyl extension loading is disabled");
  }

 private:
  bool shutting_down_ = false;
};

CarbonylExtensionsBrowserClient* g_client = nullptr;

}  // namespace
}  // namespace extensions

namespace carbonyl {

void InstallExtensionsBrowserClient() {
  if (!extensions::g_client) {
    extensions::g_client = new extensions::CarbonylExtensionsBrowserClient();
    extensions::ExtensionsBrowserClient::Set(extensions::g_client);
    extensions::g_client->Init();
  }
}

void StartExtensionsBrowserClientTearDown() {
  if (extensions::g_client && !extensions::g_client->IsShuttingDown()) {
    extensions::g_client->StartTearDown();
  }
}

}  // namespace carbonyl
