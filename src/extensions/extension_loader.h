#ifndef CARBONYL_SRC_EXTENSIONS_EXTENSION_LOADER_H_
#define CARBONYL_SRC_EXTENSIONS_EXTENSION_LOADER_H_

#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/memory/raw_ptr.h"
#include "carbonyl/src/extensions/management.h"
#include "extensions/browser/extension_registrar.h"

namespace content {
class BrowserContext;
}

namespace extensions {

// Loads only canonical, local, unpacked MV3 directories selected on the
// command line. Remote installation, updates, reload, and symlink traversal
// are deliberately unavailable.
class CarbonylExtensionLoader : public ExtensionRegistrar::Delegate {
 public:
  explicit CarbonylExtensionLoader(content::BrowserContext* browser_context);
  ~CarbonylExtensionLoader() override;

  CarbonylExtensionLoader(const CarbonylExtensionLoader&) = delete;
  CarbonylExtensionLoader& operator=(const CarbonylExtensionLoader&) = delete;

  bool LoadConfiguredExtensions(std::string* error);
  const std::vector<carbonyl::ExtensionStatus>& statuses() const {
    return statuses_;
  }

 private:
  bool LoadOne(const base::FilePath& path, std::string* error);

  void PreAddExtension(const Extension* extension,
                       const Extension* old_extension) override;
  void OnAddNewOrUpdatedExtension(const Extension* extension) override;
  void PostActivateExtension(scoped_refptr<const Extension> extension) override;
  void PostDeactivateExtension(
      scoped_refptr<const Extension> extension) override;
  void PreUninstallExtension(scoped_refptr<const Extension> extension) override;
  void PostUninstallExtension(scoped_refptr<const Extension> extension,
                              base::OnceClosure done_callback) override;
  void LoadExtensionForReload(const ExtensionId& extension_id,
                              const base::FilePath& path) override;
  void LoadExtensionForReloadWithQuietFailure(
      const ExtensionId& extension_id,
      const base::FilePath& path) override;
  void ShowExtensionDisabledError(const Extension* extension,
                                  bool is_remote_install) override;
  bool CanEnableExtension(const Extension* extension) override;
  bool CanDisableExtension(const Extension* extension) override;
  void GrantActivePermissions(const Extension* extension) override;
  void UpdateExternalExtensionAlert() override;
  void OnExtensionInstalled(const Extension* extension,
                            const syncer::StringOrdinal& page_ordinal,
                            int install_flags,
                            base::DictValue ruleset_install_prefs) override;

  raw_ptr<content::BrowserContext> browser_context_;
  raw_ptr<ExtensionRegistrar> registrar_;
  std::vector<carbonyl::ExtensionStatus> statuses_;
};

}  // namespace extensions

#endif  // CARBONYL_SRC_EXTENSIONS_EXTENSION_LOADER_H_
