#ifndef CARBONYL_SRC_EXTENSIONS_MANAGEMENT_H_
#define CARBONYL_SRC_EXTENSIONS_MANAGEMENT_H_

#include <cstddef>
#include <string>
#include <vector>

#include "url/gurl.h"

namespace content {
class BrowserContext;
class WebContents;
}  // namespace content

class PrefRegistrySimple;

namespace carbonyl {

inline constexpr char kExtensionManagementSwitch[] =
    "carbonyl-extension-management";
inline constexpr char kExtensionManagementUnavailable[] = "unavailable";
inline constexpr char kExtensionManagementReadOnly[] = "read-only";
inline constexpr char kExtensionManagementRestart[] = "restart";
inline constexpr char kExtensionMutationSwitch[] =
    "carbonyl-extension-mutation";
inline constexpr char kExtensionListSwitch[] = "carbonyl-extension-list";

struct ExtensionStatus {
  std::string id;
  std::string version;
  std::string source_path_sha256;
  std::string state;
  std::vector<std::string> api_permissions;
  size_t host_permission_count = 0;
};

struct ExtensionActionSnapshot {
  std::string id;
  std::string title;
  std::string badge;
  bool enabled = false;
  GURL popup_url;
  GURL options_url;
};

enum class ExtensionMutation { kLoad, kDisable, kEnable, kRemove };

std::string GetExtensionManagementMode();
std::vector<ExtensionStatus> GetExtensionStatuses(
    content::BrowserContext* browser_context);
std::vector<ExtensionActionSnapshot> GetExtensionActions(
    content::WebContents* web_contents);

// Dispatches a click and returns its constrained popup URL, if any.
GURL ActivateExtensionAction(content::WebContents* web_contents,
                             const std::string& extension_id,
                             std::string* error);

// Mutations are persisted only in explicit `restart` mode and take effect on
// the next launch. `error` is a stable policy/result code.
bool RequestExtensionMutation(content::BrowserContext* browser_context,
                              const std::string& extension_id,
                              ExtensionMutation mutation,
                              std::string* error);
bool ApplyCommandLineExtensionMutation(content::BrowserContext* browser_context,
                                       std::string* error);
void LogExtensionStatuses(content::BrowserContext* browser_context);

void RegisterExtensionManagementPrefs(PrefRegistrySimple* registry);
bool IsExtensionDisabledForRestart(content::BrowserContext* browser_context,
                                   const std::string& extension_id);
bool IsExtensionRemovedForRestart(content::BrowserContext* browser_context,
                                  const std::string& extension_id);

}  // namespace carbonyl

#endif  // CARBONYL_SRC_EXTENSIONS_MANAGEMENT_H_
