#ifndef CARBONYL_SRC_EXTENSIONS_EXTENSION_SYSTEM_H_
#define CARBONYL_SRC_EXTENSIONS_EXTENSION_SYSTEM_H_

#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/no_destructor.h"
#include "base/one_shot_event.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/extension_system_provider.h"

class PrefService;

namespace content {
class BrowserContext;
}

namespace value_store {
class ValueStoreFactory;
}

namespace extensions {

class CarbonylExtensionLoader;
class StateStore;

class CarbonylExtensionSystem : public ExtensionSystem {
 public:
  explicit CarbonylExtensionSystem(content::BrowserContext* browser_context);
  ~CarbonylExtensionSystem() override;

  CarbonylExtensionSystem(const CarbonylExtensionSystem&) = delete;
  CarbonylExtensionSystem& operator=(const CarbonylExtensionSystem&) = delete;

  bool LoadConfiguredExtensions(std::string* error);

  void Shutdown() override;
  void InitForRegularProfile(bool extensions_enabled) override;
  ExtensionService* extension_service() override;
  ManagementPolicy* management_policy() override;
  ServiceWorkerManager* service_worker_manager() override;
  UserScriptManager* user_script_manager() override;
  StateStore* state_store() override;
  StateStore* rules_store() override;
  StateStore* dynamic_user_scripts_store() override;
  scoped_refptr<value_store::ValueStoreFactory> store_factory() override;
  QuotaService* quota_service() override;
  AppSorting* app_sorting() override;
  const base::OneShotEvent& ready() const override;
  bool is_ready() const override;
  ContentVerifier* content_verifier() override;
  void InstallUpdate(const ExtensionId& extension_id,
                     const std::string& public_key,
                     const base::FilePath& unpacked_dir,
                     bool install_immediately,
                     InstallUpdateCallback install_update_callback) override;
  void PerformActionBasedOnOmahaAttributes(
      const ExtensionId& extension_id,
      const base::DictValue& attributes) override;

 private:
  raw_ptr<content::BrowserContext> browser_context_;
  std::unique_ptr<ManagementPolicy> management_policy_;
  std::unique_ptr<ServiceWorkerManager> service_worker_manager_;
  std::unique_ptr<UserScriptManager> user_script_manager_;
  std::unique_ptr<StateStore> state_store_;
  std::unique_ptr<StateStore> rules_store_;
  std::unique_ptr<StateStore> dynamic_user_scripts_store_;
  std::unique_ptr<QuotaService> quota_service_;
  std::unique_ptr<AppSorting> app_sorting_;
  std::unique_ptr<CarbonylExtensionLoader> loader_;
  scoped_refptr<value_store::ValueStoreFactory> store_factory_;
  base::OneShotEvent ready_;
};

class CarbonylExtensionSystemFactory : public ExtensionSystemProvider {
 public:
  static CarbonylExtensionSystemFactory* GetInstance();
  ExtensionSystem* GetForBrowserContext(
      content::BrowserContext* context) override;

 private:
  friend class base::NoDestructor<CarbonylExtensionSystemFactory>;
  CarbonylExtensionSystemFactory();
  ~CarbonylExtensionSystemFactory() override;

  std::unique_ptr<KeyedService> BuildServiceInstanceForBrowserContext(
      content::BrowserContext* context) const override;
  content::BrowserContext* GetBrowserContextToUse(
      content::BrowserContext* context) const override;
  bool ServiceIsCreatedWithBrowserContext() const override;
};

}  // namespace extensions

namespace carbonyl {

// Creates writable, profile-scoped extension preferences and associates them
// with a Headless BrowserContext. The returned object must outlive all keyed
// extension services for that context.
std::unique_ptr<PrefService> CreateExtensionProfilePrefs(
    content::BrowserContext* browser_context);

// Initializes and loads extensions selected by standard Chromium switches.
// Returns false and populates `error` on any fail-closed validation error.
bool InitializeExtensionContext(content::BrowserContext* browser_context,
                                std::string* error);

}  // namespace carbonyl

#endif  // CARBONYL_SRC_EXTENSIONS_EXTENSION_SYSTEM_H_
