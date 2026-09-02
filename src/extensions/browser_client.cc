#include "carbonyl/src/extensions/browser_client.h"

#include <memory>
#include <set>
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
#include "carbonyl/src/extensions/extension_system.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/web_contents_user_data.h"
#include "extensions/browser/api/core_extensions_browser_api_provider.h"
#include "extensions/browser/api/declarative_net_request/web_contents_helper.h"
#include "extensions/browser/api/extensions_api_client.h"
#include "extensions/browser/api/messaging/messaging_delegate.h"
#include "extensions/browser/api/runtime/runtime_api_delegate.h"
#include "extensions/browser/browser_context_keyed_service_factories.h"
#include "extensions/browser/extension_host_delegate.h"
#include "extensions/browser/extension_management_client.h"
#include "extensions/browser/extension_web_contents_observer.h"
#include "extensions/browser/extensions_browser_interface_binders.h"
#include "extensions/browser/extensions_browser_client.h"
#include "extensions/browser/kiosk/kiosk_delegate.h"
#include "extensions/browser/safe_browsing_delegate.h"
#include "extensions/browser/updater/null_extension_cache.h"
#include "extensions/browser/url_request_util.h"
#include "extensions/common/extension_id.h"
#include "extensions/common/manifest.h"
#include "extensions/common/permissions/permission_set.h"
#include "extensions/common/switches.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "net/http/http_response_headers.h"
#include "services/network/public/mojom/url_loader.mojom.h"

namespace extensions {
namespace {

class CarbonylMessagingDelegate final : public MessagingDelegate {
 public:
  CarbonylMessagingDelegate() = default;
  ~CarbonylMessagingDelegate() override = default;

  PolicyPermission IsNativeMessagingHostAllowed(
      content::BrowserContext*, const std::string&) override {
    return PolicyPermission::DISALLOW;
  }
  std::optional<base::DictValue> MaybeGetTabInfo(
      content::WebContents*) override {
    return std::nullopt;
  }
  content::WebContents* GetWebContentsByTabId(content::BrowserContext*,
                                              int) override {
    return nullptr;
  }
  std::unique_ptr<MessagePort> CreateReceiverForNativeApp(
      content::BrowserContext*,
      base::WeakPtr<MessagePort::ChannelDelegate>,
      content::RenderFrameHost*,
      const ExtensionId&,
      const PortId&,
      const std::string&,
      bool,
      std::string*) override {
    return nullptr;
  }
  void QueryIncognitoConnectability(
      content::BrowserContext*,
      const Extension*,
      content::WebContents*,
      const GURL&,
      base::OnceCallback<void(bool)> callback) override {
    std::move(callback).Run(false);
  }
};

class CarbonylExtensionsAPIClient final : public ExtensionsAPIClient {
 public:
  CarbonylExtensionsAPIClient() = default;
  ~CarbonylExtensionsAPIClient() override = default;

  MessagingDelegate* GetMessagingDelegate() override {
    return &messaging_delegate_;
  }

 private:
  CarbonylMessagingDelegate messaging_delegate_;
};

// Carbonyl deliberately does not provide browser-owned update, navigation, or
// device-restart surfaces to extensions. A concrete delegate is still
// required because RuntimeAPI owns and shuts it down unconditionally.
class CarbonylRuntimeAPIDelegate : public RuntimeAPIDelegate {
 public:
  CarbonylRuntimeAPIDelegate() = default;
  ~CarbonylRuntimeAPIDelegate() override = default;

  void AddUpdateObserver(UpdateObserver* observer) override {}
  void RemoveUpdateObserver(UpdateObserver* observer) override {}
  void ReloadExtension(const ExtensionId& extension_id) override {}
  bool CheckForUpdates(const ExtensionId& extension_id,
                       UpdateCheckCallback callback) override {
    return false;
  }
  void OpenURL(const GURL& uninstall_url) override {}
  bool GetPlatformInfo(api::runtime::PlatformInfo* info) override {
    return false;
  }
  bool RestartDevice(std::string* error_message) override {
    if (error_message) {
      *error_message = "device restart is unavailable in Carbonyl";
    }
    return false;
  }
};

class CarbonylExtensionManagementClient : public ExtensionManagementClient {
 public:
  CarbonylExtensionManagementClient() = default;
  ~CarbonylExtensionManagementClient() override = default;

  bool UpdatesFromWebstore(const Extension& extension) override {
    return false;
  }
  bool IsInstallationExplicitlyAllowed(const ExtensionId& id) override {
    return false;
  }
  bool IsForceInstalledInLowTrustEnvironment(
      const Extension& extension) override {
    return false;
  }
  const URLPatternSet& GetPolicyBlockedHosts(
      const Extension* extension) override {
    return URLPatternSet::Empty();
  }
  const URLPatternSet& GetPolicyAllowedHosts(
      const Extension* extension) override {
    return URLPatternSet::Empty();
  }
  bool UsesDefaultPolicyHostRestrictions(const Extension* extension) override {
    return true;
  }
  bool BlocklistedByDefault() const override { return false; }
  GURL GetEffectiveUpdateURL(const Extension& extension) override { return {}; }
  bool IsExemptFromMV2DeprecationByPolicy(
      int manifest_version,
      const std::string& extension_id,
      Manifest::Type manifest_type) override {
    return false;
  }
  bool IsAllowedManifestVersion(int manifest_version,
                                const std::string& extension_id,
                                Manifest::Type manifest_type) override {
    return manifest_version == 3 && manifest_type == Manifest::Type::kExtension;
  }
  bool IsAllowedManifestVersion(const Extension* extension) override {
    return extension && extension->manifest_version() == 3 &&
           extension->is_extension();
  }
  bool IsAllowedManifestType(Manifest::Type manifest_type,
                             const std::string& extension_id) const override {
    return manifest_type == Manifest::Type::kExtension;
  }
  ManagedInstallationMode GetInstallationMode(
      const Extension* extension) override {
    return IsAllowedManifestVersion(extension)
               ? ManagedInstallationMode::kAllowed
               : ManagedInstallationMode::kBlocked;
  }
  ManagedInstallationMode GetInstallationMode(
      const ExtensionId& extension_id,
      const std::string& update_url) override {
    return ManagedInstallationMode::kBlocked;
  }
  bool IsInstallationExplicitlyBlocked(const ExtensionId& id) override {
    return false;
  }
  const std::string BlockedInstallMessage(const ExtensionId& id) override {
    return "Carbonyl accepts only explicit local unpacked MV3 directories";
  }
  bool IsPermissionSetAllowed(const Extension* extension,
                              const PermissionSet& perms) override {
    return IsAllowedManifestVersion(extension);
  }
  bool IsPermissionSetAllowed(const ExtensionId& extension_id,
                              const std::string& update_url,
                              const PermissionSet& perms) override {
    return false;
  }
};

class CarbonylExtensionWebContentsObserver
    : public ExtensionWebContentsObserver,
      public content::WebContentsUserData<
          CarbonylExtensionWebContentsObserver> {
 public:
  ~CarbonylExtensionWebContentsObserver() override = default;

  static void Create(content::WebContents* web_contents) {
    content::WebContentsUserData<CarbonylExtensionWebContentsObserver>::
        CreateForWebContents(web_contents);
    FromWebContents(web_contents)->Initialize();
  }

 private:
  friend class content::WebContentsUserData<
      CarbonylExtensionWebContentsObserver>;

  explicit CarbonylExtensionWebContentsObserver(
      content::WebContents* web_contents)
      : ExtensionWebContentsObserver(web_contents),
        content::WebContentsUserData<CarbonylExtensionWebContentsObserver>(
            *web_contents),
        dnr_helper_(web_contents) {}

  WEB_CONTENTS_USER_DATA_KEY_DECL();
  declarative_net_request::WebContentsHelper dnr_helper_;
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(CarbonylExtensionWebContentsObserver);

class CarbonylKioskDelegate final : public KioskDelegate {
 public:
  CarbonylKioskDelegate() = default;
  ~CarbonylKioskDelegate() override = default;

  bool IsAutoLaunchedKioskApp(const ExtensionId&) const override {
    return false;
  }
};

class CarbonylExtensionsBrowserClient : public ExtensionsBrowserClient {
 public:
  CarbonylExtensionsBrowserClient()
      : api_client_(std::make_unique<CarbonylExtensionsAPIClient>()),
        extension_cache_(std::make_unique<NullExtensionCache>()),
        safe_browsing_delegate_(std::make_unique<SafeBrowsingDelegate>()),
        management_client_(
            std::make_unique<CarbonylExtensionManagementClient>()) {
    AddAPIProvider(std::make_unique<CoreExtensionsBrowserAPIProvider>());
  }
  ~CarbonylExtensionsBrowserClient() override = default;

  void Init() override {}

  void StartTearDown() override { shutting_down_ = true; }

  bool IsShuttingDown() override { return shutting_down_; }

  bool AreExtensionsDisabled(const base::CommandLine& command_line,
                             content::BrowserContext* context) override {
    return shutting_down_ ||
           command_line.HasSwitch(switches::kDisableExtensions) ||
           !command_line.HasSwitch(switches::kLoadExtension);
  }

  bool IsValidContext(void* context) override {
    return !shutting_down_ &&
           contexts_.contains(static_cast<content::BrowserContext*>(context));
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

  content::BrowserContext* GetContextRedirectedToOriginalWithoutAshInternals(
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
    return !IsValidContext(context) ||
           AreExtensionsDisabled(*base::CommandLine::ForCurrentProcess(),
                                 context);
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
    bool allowed = false;
    if (url_request_util::AllowCrossRendererResourceLoad(
            request, destination, page_transition, child_id, is_incognito,
            extension, extensions, process_map, upstream_url, &allowed)) {
      return allowed;
    }
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

  std::unique_ptr<ExtensionHostDelegate> CreateExtensionHostDelegate()
      override {
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
    return CarbonylExtensionSystemFactory::GetInstance();
  }

  void RegisterBrowserInterfaceBindersForFrame(
      mojo::BinderMapWithContext<content::RenderFrameHost*>* binder_map,
      content::RenderFrameHost* render_frame_host,
      const Extension* extension) const override {
    PopulateExtensionFrameBinders(binder_map, render_frame_host, extension);
  }

  std::unique_ptr<RuntimeAPIDelegate> CreateRuntimeAPIDelegate(
      content::BrowserContext* context) const override {
    return std::make_unique<CarbonylRuntimeAPIDelegate>();
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

  ExtensionCache* GetExtensionCache() override {
    return extension_cache_.get();
  }
  bool IsBackgroundUpdateAllowed() override { return false; }
  bool IsMinBrowserVersionSupported(const std::string& min_version) override {
    return false;
  }

  void CreateExtensionWebContentsObserver(
      content::WebContents* web_contents) override {
    CarbonylExtensionWebContentsObserver::Create(web_contents);
  }

  ExtensionWebContentsObserver* GetExtensionWebContentsObserver(
      content::WebContents* web_contents) override {
    return CarbonylExtensionWebContentsObserver::FromWebContents(web_contents);
  }

  KioskDelegate* GetKioskDelegate() override { return &kiosk_delegate_; }
  SafeBrowsingDelegate* GetSafeBrowsingDelegate() override {
    return safe_browsing_delegate_.get();
  }
  UserScriptListener* GetUserScriptListener() override { return nullptr; }
  std::string GetApplicationLocale() override { return "en-US"; }

  ExtensionManagementClient* GetExtensionManagementClient(
      content::BrowserContext* context) override {
    return management_client_.get();
  }

  bool CanUseNonComponentExtensions(content::BrowserContext* context) override {
    return !AreExtensionsDisabledForContext(context);
  }

  void CanInstallExtensionByPolicy(
      content::BrowserContext* context,
      const ExtensionId& extension_id,
      const base::Version& extension_version,
      base::OnceCallback<void(bool, std::u16string)> callback) override {
    std::move(callback).Run(false, u"Carbonyl extension loading is disabled");
  }

  void RegisterContext(content::BrowserContext* context) {
    CHECK(context);
    CHECK(!shutting_down_);
    CHECK(contexts_.insert(context).second);
  }

  void UnregisterContext(content::BrowserContext* context) {
    contexts_.erase(context);
  }

 private:
  bool shutting_down_ = false;
  std::set<content::BrowserContext*> contexts_;
  std::unique_ptr<ExtensionsAPIClient> api_client_;
  std::unique_ptr<ExtensionCache> extension_cache_;
  std::unique_ptr<SafeBrowsingDelegate> safe_browsing_delegate_;
  std::unique_ptr<ExtensionManagementClient> management_client_;
  CarbonylKioskDelegate kiosk_delegate_;
};

CarbonylExtensionsBrowserClient* g_client = nullptr;

}  // namespace
}  // namespace extensions

namespace carbonyl {

void InstallExtensionsBrowserClient() {
  if (!extensions::g_client) {
    extensions::g_client = new extensions::CarbonylExtensionsBrowserClient();
    extensions::ExtensionsBrowserClient::Set(extensions::g_client);
    // Chromium 150 keyed-service factories consult the process-global
    // ExtensionsBrowserClient from their DependsOn() declarations. Install
    // Carbonyl's client before building those factories, matching Chrome's
    // pre-profile initialization order.
    extensions::EnsureBrowserContextKeyedServiceFactoriesBuilt();
    extensions::g_client->Init();
  }
}

void StartExtensionsBrowserClientTearDown() {
  if (extensions::g_client && !extensions::g_client->IsShuttingDown()) {
    extensions::g_client->StartTearDown();
  }
}

void RegisterExtensionContext(content::BrowserContext* context) {
  CHECK(extensions::g_client);
  extensions::g_client->RegisterContext(context);
}

void UnregisterExtensionContext(content::BrowserContext* context) {
  if (extensions::g_client) {
    extensions::g_client->UnregisterContext(context);
  }
}

void CreateExtensionWebContentsObserver(content::WebContents* web_contents) {
  CHECK(extensions::g_client);
  extensions::g_client->CreateExtensionWebContentsObserver(web_contents);
}

}  // namespace carbonyl
