#include "carbonyl/src/extensions/common_client.h"

#include <memory>
#include <string>

#include "base/command_line.h"
#include "extensions/common/core_extensions_api_provider.h"
#include "extensions/common/extensions_client.h"
#include "extensions/common/permissions/permission_message_provider.h"
#include "extensions/common/permissions/permission_set.h"
#include "extensions/common/url_pattern_set.h"
#include "url/gurl.h"

namespace extensions {
namespace {

class CarbonylPermissionMessageProvider : public PermissionMessageProvider {
 public:
  PermissionMessages GetPermissionMessages(
      const PermissionIDSet& permissions) const override {
    return PermissionMessages();
  }

  bool IsPrivilegeIncrease(const PermissionSet& granted_permissions,
                           const PermissionSet& requested_permissions,
                           Manifest::Type extension_type) const override {
    // This client is installed by the no-load linkage slice. Treat every
    // permission transition as an increase until #289 supplies an explicit
    // grant policy.
    return true;
  }

  PermissionIDSet GetAllPermissionIDs(
      const PermissionSet& permissions,
      Manifest::Type extension_type) const override {
    return PermissionIDSet();
  }
};

class CarbonylExtensionsClient : public ExtensionsClient {
 public:
  CarbonylExtensionsClient() {
    AddAPIProvider(std::make_unique<CoreExtensionsAPIProvider>());
  }

  void Initialize() override {}
  void InitializeWebStoreUrls(base::CommandLine* command_line) override {}

  const PermissionMessageProvider& GetPermissionMessageProvider()
      const override {
    return permission_message_provider_;
  }

  const std::string GetProductName() override { return "Carbonyl"; }

  void FilterHostPermissions(const URLPatternSet& hosts,
                             URLPatternSet* new_hosts,
                             PermissionIDSet* permissions) const override {
    *new_hosts = URLPatternSet();
    *permissions = PermissionIDSet();
  }

  void SetScriptingAllowlist(const ScriptingAllowlist& allowlist) override {
    // The no-load client never grants the global scripting exception.
    scripting_allowlist_.clear();
  }

  const ScriptingAllowlist& GetScriptingAllowlist() const override {
    return scripting_allowlist_;
  }

  URLPatternSet GetPermittedChromeSchemeHosts(
      const Extension* extension,
      const APIPermissionSet& api_permissions) const override {
    return URLPatternSet();
  }

  bool IsScriptableURL(const GURL& url, std::string* error) const override {
    if (error) {
      *error = "Carbonyl extension execution is disabled";
    }
    return false;
  }

  const GURL& GetWebstoreBaseURL() const override { return empty_url_; }
  const GURL& GetNewWebstoreBaseURL() const override { return empty_url_; }
  const GURL& GetWebstoreUpdateURL() const override { return empty_url_; }
  bool IsBlocklistUpdateURL(const GURL& url) const override { return false; }

 private:
  CarbonylPermissionMessageProvider permission_message_provider_;
  ScriptingAllowlist scripting_allowlist_;
  GURL empty_url_;
};

}  // namespace
}  // namespace extensions

namespace carbonyl {

void InstallExtensionsCommonClient() {
  // ExtensionsClient is intentionally process-global and has no reset path.
  // Leak the singleton so child/zygote shutdown cannot observe a dangling
  // pointer during global teardown.
  static auto* const client = new extensions::CarbonylExtensionsClient();
  extensions::ExtensionsClient::Set(client);
}

}  // namespace carbonyl
