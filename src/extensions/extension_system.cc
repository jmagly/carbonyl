#include "carbonyl/src/extensions/extension_system.h"

#include <memory>
#include <utility>

#include "base/command_line.h"
#include "base/functional/callback.h"
#include "base/no_destructor.h"
#include "carbonyl/src/extensions/extension_loader.h"
#include "carbonyl/src/extensions/management.h"
#include "components/keyed_service/content/browser_context_dependency_manager.h"
#include "components/pref_registry/pref_registry_syncable.h"
#include "components/prefs/json_pref_store.h"
#include "components/prefs/pref_service.h"
#include "components/prefs/pref_service_factory.h"
#include "components/update_client/update_client.h"
#include "components/user_prefs/user_prefs.h"
#include "components/value_store/value_store_factory_impl.h"
#include "content/public/browser/browser_context.h"
#include "extensions/browser/api/web_request/web_request_event_router_factory.h"
#include "extensions/browser/extension_prefs.h"
#include "extensions/browser/extension_prefs_factory.h"
#include "extensions/browser/extension_registry_factory.h"
#include "extensions/browser/management_policy.h"
#include "extensions/browser/null_app_sorting.h"
#include "extensions/browser/permissions_manager.h"
#include "extensions/browser/quota_service.h"
#include "extensions/browser/service_worker_manager.h"
#include "extensions/browser/state_store.h"
#include "extensions/browser/user_script_manager.h"
#include "extensions/common/switches.h"

namespace extensions {

CarbonylExtensionSystem::CarbonylExtensionSystem(
    content::BrowserContext* browser_context)
    : browser_context_(browser_context),
      store_factory_(base::MakeRefCounted<value_store::ValueStoreFactoryImpl>(
          browser_context->GetPath().AppendASCII("Extension State"))) {}

CarbonylExtensionSystem::~CarbonylExtensionSystem() = default;

void CarbonylExtensionSystem::InitForRegularProfile(bool extensions_enabled) {
  management_policy_ = std::make_unique<ManagementPolicy>();
  state_store_ = std::make_unique<StateStore>(browser_context_, store_factory_,
                                              StateStore::BackendType::STATE,
                                              /*deferred_load=*/true);
  rules_store_ = std::make_unique<StateStore>(browser_context_, store_factory_,
                                              StateStore::BackendType::RULES,
                                              /*deferred_load=*/false);
  dynamic_user_scripts_store_ = std::make_unique<StateStore>(
      browser_context_, store_factory_, StateStore::BackendType::SCRIPTS,
      /*deferred_load=*/false);
  service_worker_manager_ =
      std::make_unique<ServiceWorkerManager>(browser_context_);
  user_script_manager_ = std::make_unique<UserScriptManager>(browser_context_);
  quota_service_ = std::make_unique<QuotaService>();
  app_sorting_ = std::make_unique<NullAppSorting>();
  if (extensions_enabled) {
    loader_ = std::make_unique<CarbonylExtensionLoader>(browser_context_);
  }
  ready_.Signal();
}

bool CarbonylExtensionSystem::LoadConfiguredExtensions(std::string* error) {
  return loader_ && loader_->LoadConfiguredExtensions(error);
}

std::vector<carbonyl::ExtensionStatus>
CarbonylExtensionSystem::extension_statuses() const {
  return loader_ ? loader_->statuses()
                 : std::vector<carbonyl::ExtensionStatus>();
}

void CarbonylExtensionSystem::Shutdown() {
  loader_.reset();
  user_script_manager_.reset();
  service_worker_manager_.reset();
  dynamic_user_scripts_store_.reset();
  rules_store_.reset();
  state_store_.reset();
}

ExtensionService* CarbonylExtensionSystem::extension_service() {
  return nullptr;
}
ManagementPolicy* CarbonylExtensionSystem::management_policy() {
  return management_policy_.get();
}
ServiceWorkerManager* CarbonylExtensionSystem::service_worker_manager() {
  return service_worker_manager_.get();
}
UserScriptManager* CarbonylExtensionSystem::user_script_manager() {
  return user_script_manager_.get();
}
StateStore* CarbonylExtensionSystem::state_store() {
  return state_store_.get();
}
StateStore* CarbonylExtensionSystem::rules_store() {
  return rules_store_.get();
}
StateStore* CarbonylExtensionSystem::dynamic_user_scripts_store() {
  return dynamic_user_scripts_store_.get();
}
scoped_refptr<value_store::ValueStoreFactory>
CarbonylExtensionSystem::store_factory() {
  return store_factory_;
}
QuotaService* CarbonylExtensionSystem::quota_service() {
  return quota_service_.get();
}
AppSorting* CarbonylExtensionSystem::app_sorting() {
  return app_sorting_.get();
}
const base::OneShotEvent& CarbonylExtensionSystem::ready() const {
  return ready_;
}
bool CarbonylExtensionSystem::is_ready() const {
  return ready_.is_signaled();
}
ContentVerifier* CarbonylExtensionSystem::content_verifier() {
  return nullptr;
}
void CarbonylExtensionSystem::InstallUpdate(
    const ExtensionId& extension_id,
    const std::string& public_key,
    const base::FilePath& unpacked_dir,
    bool install_immediately,
    InstallUpdateCallback install_update_callback) {
  std::move(install_update_callback)
      .Run(CrxInstallError(CrxInstallErrorType::DECLINED,
                           CrxInstallErrorDetail::DISALLOWED_BY_POLICY));
}
void CarbonylExtensionSystem::PerformActionBasedOnOmahaAttributes(
    const ExtensionId& extension_id,
    const base::DictValue& attributes) {}

ExtensionSystem* CarbonylExtensionSystemFactory::GetForBrowserContext(
    content::BrowserContext* context) {
  return static_cast<CarbonylExtensionSystem*>(
      GetInstance()->GetServiceForBrowserContext(context, true));
}

CarbonylExtensionSystemFactory* CarbonylExtensionSystemFactory::GetInstance() {
  static base::NoDestructor<CarbonylExtensionSystemFactory> instance;
  return instance.get();
}

CarbonylExtensionSystemFactory::CarbonylExtensionSystemFactory()
    : ExtensionSystemProvider("CarbonylExtensionSystem",
                              BrowserContextDependencyManager::GetInstance()) {
  DependsOn(ExtensionPrefsFactory::GetInstance());
  DependsOn(ExtensionRegistryFactory::GetInstance());
}
CarbonylExtensionSystemFactory::~CarbonylExtensionSystemFactory() = default;
std::unique_ptr<KeyedService>
CarbonylExtensionSystemFactory::BuildServiceInstanceForBrowserContext(
    content::BrowserContext* context) const {
  return std::make_unique<CarbonylExtensionSystem>(context);
}
content::BrowserContext* CarbonylExtensionSystemFactory::GetBrowserContextToUse(
    content::BrowserContext* context) const {
  return context;
}
bool CarbonylExtensionSystemFactory::ServiceIsCreatedWithBrowserContext()
    const {
  return true;
}

}  // namespace extensions

namespace carbonyl {

std::unique_ptr<PrefService> CreateExtensionProfilePrefs(
    content::BrowserContext* browser_context) {
  const base::FilePath path =
      browser_context->GetPath().AppendASCII("Extension Preferences");
  auto store = base::MakeRefCounted<JsonPrefStore>(path);
  store->ReadPrefs();

  auto registry = base::MakeRefCounted<user_prefs::PrefRegistrySyncable>();
  extensions::ExtensionPrefs::RegisterProfilePrefs(registry.get());
  extensions::PermissionsManager::RegisterProfilePrefs(registry.get());
  update_client::RegisterProfilePrefs(registry.get());
  RegisterExtensionManagementPrefs(registry.get());

  PrefServiceFactory factory;
  factory.set_user_prefs(store);
  std::unique_ptr<PrefService> prefs = factory.Create(registry);
  user_prefs::UserPrefs::Set(browser_context, prefs.get());
  return prefs;
}

bool InitializeExtensionContext(content::BrowserContext* browser_context,
                                std::string* error) {
  // Carbonyl's network hook can lazily create WebRequestAPI. Chromium 150's
  // WebRequestAPI::Shutdown() unconditionally looks up the per-context
  // WebRequestEventRouter, so materialize that nominally eager dependency
  // before navigation and keep its shutdown ordering deterministic.
  CHECK(extensions::WebRequestEventRouterFactory::GetForBrowserContext(
      browser_context));
  auto* system = static_cast<extensions::CarbonylExtensionSystem*>(
      extensions::ExtensionSystem::Get(browser_context));
  system->InitForRegularProfile(/*extensions_enabled=*/true);
  if (!system->LoadConfiguredExtensions(error)) {
    return false;
  }
  LogExtensionStatuses(browser_context);
  return ApplyCommandLineExtensionMutation(browser_context, error);
}

}  // namespace carbonyl
