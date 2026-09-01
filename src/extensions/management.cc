#include "carbonyl/src/extensions/management.h"

#include <algorithm>
#include <memory>
#include <string_view>
#include <utility>

#include "base/command_line.h"
#include "base/logging.h"
#include "base/strings/string_util.h"
#include "base/values.h"
#include "carbonyl/src/extensions/extension_system.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"
#include "components/prefs/scoped_user_pref_update.h"
#include "components/user_prefs/user_prefs.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/event_router.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/common/extension.h"
#include "extensions/common/manifest_handlers/options_page_info.h"
#include "extensions/common/permissions/permission_set.h"
#include "extensions/common/permissions/permissions_data.h"

namespace carbonyl {
namespace {

constexpr char kDisabledExtensionsPref[] =
    "carbonyl.extensions.restart_disabled_ids";
constexpr char kRemovedExtensionsPref[] =
    "carbonyl.extensions.restart_removed_ids";

bool HasActionAccess(const extensions::Extension& extension,
                     content::WebContents* web_contents) {
  const auto& permissions = extension.permissions_data()->active_permissions();
  return (permissions.explicit_hosts().is_empty() &&
          permissions.scriptable_hosts().is_empty()) ||
         permissions.HasEffectiveAccessToURL(
             web_contents->GetLastCommittedURL());
}

bool IsOwnExtensionUrl(const GURL& url, const std::string& extension_id) {
  return url.is_empty() ||
         (url.SchemeIs("chrome-extension") && url.host() == extension_id);
}

bool ListContains(const base::ListValue& list, std::string_view id) {
  return std::ranges::any_of(list, [id](const base::Value& value) {
    return value.is_string() && value.GetString() == id;
  });
}

bool PrefContains(content::BrowserContext* context,
                  const char* name,
                  std::string_view id) {
  PrefService* prefs = user_prefs::UserPrefs::Get(context);
  return prefs && ListContains(prefs->GetList(name), id);
}

void SetPrefMembership(PrefService* prefs,
                       const char* name,
                       const std::string& id,
                       bool present) {
  ScopedListPrefUpdate update(prefs, name);
  base::ListValue& list = update.Get();
  list.EraseValue(base::Value(id));
  if (present) {
    list.Append(id);
  }
}

const char* ActionEventName(extensions::ActionInfo::Type type) {
  switch (type) {
    case extensions::ActionInfo::Type::kAction:
      return "action.onClicked";
    case extensions::ActionInfo::Type::kBrowser:
      return "browserAction.onClicked";
    case extensions::ActionInfo::Type::kPage:
      return "pageAction.onClicked";
  }
  return "action.onClicked";
}

extensions::events::HistogramValue ActionHistogram(
    extensions::ActionInfo::Type type) {
  switch (type) {
    case extensions::ActionInfo::Type::kAction:
      return extensions::events::ACTION_ON_CLICKED;
    case extensions::ActionInfo::Type::kBrowser:
      return extensions::events::BROWSER_ACTION_ON_CLICKED;
    case extensions::ActionInfo::Type::kPage:
      return extensions::events::PAGE_ACTION_ON_CLICKED;
  }
  return extensions::events::UNKNOWN;
}

}  // namespace

std::string GetExtensionManagementMode() {
  const std::string mode =
      base::CommandLine::ForCurrentProcess()->GetSwitchValueASCII(
          kExtensionManagementSwitch);
  if (mode == kExtensionManagementReadOnly ||
      mode == kExtensionManagementRestart) {
    return mode;
  }
  return kExtensionManagementUnavailable;
}

std::vector<ExtensionStatus> GetExtensionStatuses(
    content::BrowserContext* browser_context) {
  if (GetExtensionManagementMode() == kExtensionManagementUnavailable) {
    return {};
  }
  auto* system = static_cast<extensions::CarbonylExtensionSystem*>(
      extensions::ExtensionSystem::Get(browser_context));
  return system ? system->extension_statuses() : std::vector<ExtensionStatus>();
}

std::vector<ExtensionActionSnapshot> GetExtensionActions(
    content::WebContents* web_contents) {
  std::vector<ExtensionActionSnapshot> snapshots;
  if (!web_contents) {
    return snapshots;
  }
  content::BrowserContext* context = web_contents->GetBrowserContext();
  auto* manager = extensions::ExtensionActionManager::Get(context);
  auto* registry = extensions::ExtensionRegistry::Get(context);
  if (!manager || !registry) {
    return snapshots;
  }
  for (const auto& extension : registry->enabled_extensions()) {
    extensions::ExtensionAction* action =
        manager->GetExtensionAction(*extension);
    if (!action) {
      continue;
    }
    const int tab_id = extensions::ExtensionAction::kDefaultTabId;
    const bool has_action_access = HasActionAccess(*extension, web_contents);
    GURL popup_url = action->GetPopupUrl(tab_id);
    if (!IsOwnExtensionUrl(popup_url, extension->id())) {
      popup_url = GURL();
    }
    GURL options_url =
        extensions::OptionsPageInfo::GetOptionsPage(extension.get());
    if (!IsOwnExtensionUrl(options_url, extension->id())) {
      options_url = GURL();
    }
    snapshots.push_back({
        .id = extension->id(),
        .title = action->GetTitle(tab_id),
        .badge = action->GetDisplayBadgeText(tab_id),
        .enabled = action->GetIsVisible(tab_id) && has_action_access,
        .popup_url = std::move(popup_url),
        .options_url = std::move(options_url),
    });
  }
  std::ranges::sort(snapshots, {}, &ExtensionActionSnapshot::id);
  return snapshots;
}

GURL ActivateExtensionAction(content::WebContents* web_contents,
                             const std::string& extension_id,
                             std::string* error) {
  if (!web_contents) {
    *error = "no_web_contents";
    return {};
  }
  content::BrowserContext* context = web_contents->GetBrowserContext();
  auto* registry = extensions::ExtensionRegistry::Get(context);
  auto* manager = extensions::ExtensionActionManager::Get(context);
  if (!registry || !manager) {
    *error = "action_unavailable";
    return {};
  }
  const extensions::Extension* extension =
      registry->enabled_extensions().GetByID(extension_id);
  extensions::ExtensionAction* action =
      extension ? manager->GetExtensionAction(*extension) : nullptr;
  if (!action ||
      !action->GetIsVisible(extensions::ExtensionAction::kDefaultTabId) ||
      !HasActionAccess(*extension, web_contents)) {
    *error = "action_unavailable";
    return {};
  }
  const GURL popup =
      action->GetPopupUrl(extensions::ExtensionAction::kDefaultTabId);
  if (!popup.is_empty()) {
    if (!IsOwnExtensionUrl(popup, extension_id)) {
      *error = "popup_origin_denied";
      return {};
    }
    return popup;
  }

  base::DictValue tab;
  tab.Set("active", true);
  tab.Set("id", -1);
  tab.Set("windowId", -1);
  if (extension->permissions_data()
          ->active_permissions()
          .HasEffectiveAccessToURL(web_contents->GetLastCommittedURL())) {
    tab.Set("url", web_contents->GetLastCommittedURL().spec());
  }
  base::ListValue args;
  args.Append(std::move(tab));
  auto event = std::make_unique<extensions::Event>(
      ActionHistogram(action->action_type()),
      ActionEventName(action->action_type()), std::move(args), context,
      extensions::mojom::ContextType::kPrivilegedExtension);
  event->user_gesture = extensions::EventRouter::UserGestureState::kEnabled;
  auto* event_router = extensions::EventRouter::Get(context);
  if (!event_router) {
    *error = "action_unavailable";
    return {};
  }
  event_router->DispatchEventToExtension(extension_id, std::move(event));
  return {};
}

bool RequestExtensionMutation(content::BrowserContext* browser_context,
                              const std::string& extension_id,
                              ExtensionMutation mutation,
                              std::string* error) {
  const std::string mode = GetExtensionManagementMode();
  if (mode == kExtensionManagementUnavailable) {
    *error = "management_unavailable";
    return false;
  }
  if (mode != kExtensionManagementRestart) {
    *error = "management_read_only";
    return false;
  }
  auto* system = static_cast<extensions::CarbonylExtensionSystem*>(
      extensions::ExtensionSystem::Get(browser_context));
  if (!system) {
    *error = "management_unavailable";
    return false;
  }
  const std::vector<ExtensionStatus> statuses = system->extension_statuses();
  if (std::ranges::none_of(statuses, [&](const ExtensionStatus& status) {
        return status.id == extension_id;
      })) {
    *error = "extension_unknown";
    return false;
  }
  PrefService* prefs = user_prefs::UserPrefs::Get(browser_context);
  if (!prefs) {
    *error = "preferences_unavailable";
    return false;
  }
  switch (mutation) {
    case ExtensionMutation::kLoad:
    case ExtensionMutation::kEnable:
      SetPrefMembership(prefs, kDisabledExtensionsPref, extension_id, false);
      SetPrefMembership(prefs, kRemovedExtensionsPref, extension_id, false);
      break;
    case ExtensionMutation::kDisable:
      SetPrefMembership(prefs, kDisabledExtensionsPref, extension_id, true);
      break;
    case ExtensionMutation::kRemove:
      SetPrefMembership(prefs, kRemovedExtensionsPref, extension_id, true);
      break;
  }
  prefs->CommitPendingWrite();
  *error = "restart_required";
  return true;
}

bool ApplyCommandLineExtensionMutation(content::BrowserContext* browser_context,
                                       std::string* error) {
  const auto& command_line = *base::CommandLine::ForCurrentProcess();
  if (!command_line.HasSwitch(kExtensionMutationSwitch)) {
    return true;
  }
  const std::string value =
      command_line.GetSwitchValueASCII(kExtensionMutationSwitch);
  const size_t separator = value.find(':');
  if (separator == std::string::npos || separator == 0 ||
      separator + 1 == value.size()) {
    *error = "invalid_mutation";
    return false;
  }
  const std::string operation = value.substr(0, separator);
  const std::string extension_id = value.substr(separator + 1);
  ExtensionMutation mutation;
  if (operation == "load") {
    mutation = ExtensionMutation::kLoad;
  } else if (operation == "disable") {
    mutation = ExtensionMutation::kDisable;
  } else if (operation == "enable") {
    mutation = ExtensionMutation::kEnable;
  } else if (operation == "remove") {
    mutation = ExtensionMutation::kRemove;
  } else {
    *error = "invalid_mutation";
    return false;
  }
  const bool accepted =
      RequestExtensionMutation(browser_context, extension_id, mutation, error);
  if (accepted) {
    LOG(INFO) << "CARBONYL_EXTENSION_MUTATION operation=" << operation
              << " id=" << extension_id << " result=" << *error;
  }
  return accepted;
}

void LogExtensionStatuses(content::BrowserContext* browser_context) {
  if (!base::CommandLine::ForCurrentProcess()->HasSwitch(
          kExtensionListSwitch)) {
    return;
  }
  for (const ExtensionStatus& status : GetExtensionStatuses(browser_context)) {
    LOG(INFO) << "CARBONYL_EXTENSION_STATUS state=" << status.state
              << " id=" << status.id << " version=" << status.version
              << " source_path_sha256=" << status.source_path_sha256
              << " api_permissions="
              << base::JoinString(status.api_permissions, ",")
              << " host_permission_count=" << status.host_permission_count;
  }
}

void RegisterExtensionManagementPrefs(PrefRegistrySimple* registry) {
  registry->RegisterListPref(kDisabledExtensionsPref);
  registry->RegisterListPref(kRemovedExtensionsPref);
}

bool IsExtensionDisabledForRestart(content::BrowserContext* browser_context,
                                   const std::string& extension_id) {
  return PrefContains(browser_context, kDisabledExtensionsPref, extension_id);
}

bool IsExtensionRemovedForRestart(content::BrowserContext* browser_context,
                                  const std::string& extension_id) {
  return PrefContains(browser_context, kRemovedExtensionsPref, extension_id);
}

}  // namespace carbonyl
