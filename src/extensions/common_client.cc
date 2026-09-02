#include "carbonyl/src/extensions/common_client.h"

#include <memory>
#include <string>

#include "base/command_line.h"
#include "chrome/common/extensions/chrome_extensions_api_provider.h"
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
    // Loading a canonical directory through both opt-in switches is the
    // operator's explicit grant. Chromium's PermissionSet remains the
    // enforcement boundary for APIs and hosts after that grant.
    return false;
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
    // Chrome owns the generated schema for MV3 action.*. Carbonyl registers
    // only the two matching browser functions it supports; every other
    // Chrome-specific request remains unregistered and therefore fail-closed.
    AddAPIProvider(std::make_unique<ChromeExtensionsAPIProvider>());
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
    for (const URLPattern& host : hosts) {
      if (host.scheme() == "*" || host.scheme() == "http" ||
          host.scheme() == "https" || host.scheme() == "file") {
        new_hosts->AddPattern(host);
      }
    }
    *permissions = PermissionIDSet();
  }

  void SetScriptingAllowlist(const ScriptingAllowlist& allowlist) override {
    // Carbonyl never grants the global scripting exception.
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
    if (url.SchemeIsHTTPOrHTTPS() || url.SchemeIsFile()) {
      return true;
    }
    if (error) {
      *error =
          "Carbonyl extensions may script only http, https, and "
          "explicitly permitted file URLs";
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
