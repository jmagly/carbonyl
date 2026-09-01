#include "carbonyl/src/extensions/extension_loader.h"

#include <set>
#include <string>
#include <utility>
#include <vector>

#include "base/command_line.h"
#include "base/files/file_enumerator.h"
#include "base/files/file_util.h"
#include "base/functional/callback_helpers.h"
#include "base/json/json_reader.h"
#include "base/logging.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "carbonyl/src/extensions/management.h"
#include "content/public/browser/browser_context.h"
#include "crypto/sha2.h"
#include "extensions/browser/api/declarative_net_request/install_index_helper.h"
#include "extensions/browser/extension_prefs.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/install_flag.h"
#include "extensions/browser/permissions/permissions_updater.h"
#include "extensions/common/extension.h"
#include "extensions/common/file_util.h"
#include "extensions/common/manifest.h"
#include "extensions/common/manifest_handlers/permissions_parser.h"
#include "extensions/common/permissions/permission_set.h"
#include "extensions/common/permissions/permissions_data.h"
#include "extensions/common/switches.h"

namespace extensions {
namespace {

bool Fail(std::string* error,
          std::string_view code,
          const std::string& message) {
  *error = "code=" + std::string(code) + " message=" + message;
  return false;
}

std::string PathDigest(const base::FilePath& path) {
  return base::HexEncode(crypto::SHA256HashString(path.AsUTF8Unsafe()));
}

std::string PrivacySafeSource(const base::FilePath& path) {
  return "source_path_sha256=" + PathDigest(path);
}

bool HasSymlink(const base::FilePath& root) {
  base::FileEnumerator entries(root, true,
                               base::FileEnumerator::FILES |
                                   base::FileEnumerator::DIRECTORIES |
                                   base::FileEnumerator::SHOW_SYM_LINKS);
  for (base::FilePath entry = entries.Next(); !entry.empty();
       entry = entries.Next()) {
    if (base::IsLink(entry)) {
      return true;
    }
  }
  return false;
}

std::vector<base::FilePath> PathsFromSwitch(const char* switch_name) {
  const base::CommandLine& command_line =
      *base::CommandLine::ForCurrentProcess();
  if (!command_line.HasSwitch(switch_name)) {
    return {};
  }

  std::vector<base::FilePath> paths;
  for (const auto& value :
       base::SplitString(command_line.GetSwitchValueNative(switch_name),
                         FILE_PATH_LITERAL(","), base::TRIM_WHITESPACE,
                         base::SPLIT_WANT_NONEMPTY)) {
    paths.emplace_back(value);
  }
  return paths;
}

bool ValidatePermissions(const Extension* extension, std::string* error) {
  const PermissionSet* permission_sets[] = {
      &PermissionsParser::GetRequiredPermissions(extension),
      &PermissionsParser::GetOptionalPermissions(extension)};
  for (const PermissionSet* permissions : permission_sets) {
    for (const std::string& permission : permissions->GetAPIsAsStrings()) {
      if (permission != "declarativeNetRequest" &&
          permission != "declarativeNetRequestWithHostAccess" &&
          permission != "storage") {
        return Fail(error, "unsupported_permission",
                    "unsupported API permission: " + permission);
      }
    }
    for (const URLPatternSet* patterns :
         {&permissions->explicit_hosts(), &permissions->scriptable_hosts()}) {
      for (const URLPattern& pattern : *patterns) {
        if (pattern.scheme() != "http" && pattern.scheme() != "https") {
          return Fail(error, "unsupported_host_scheme",
                      "host permissions are limited to http and https");
        }
      }
    }
  }
  return true;
}

}  // namespace

CarbonylExtensionLoader::CarbonylExtensionLoader(
    content::BrowserContext* browser_context)
    : browser_context_(browser_context),
      registrar_(ExtensionRegistrar::Get(browser_context)) {
  registrar_->Init(
      this, /*extensions_enabled=*/true, base::CommandLine::ForCurrentProcess(),
      browser_context_->GetPath().AppendASCII(kInstallDirectoryName),
      browser_context_->GetPath().AppendASCII(kUnpackedInstallDirectoryName));
}

CarbonylExtensionLoader::~CarbonylExtensionLoader() = default;

bool CarbonylExtensionLoader::LoadConfiguredExtensions(std::string* error) {
  const base::CommandLine& command_line =
      *base::CommandLine::ForCurrentProcess();
  if (command_line.HasSwitch(switches::kDisableExtensions)) {
    return true;
  }

  const std::vector<base::FilePath> configured =
      PathsFromSwitch(switches::kLoadExtension);
  if (configured.empty()) {
    return true;
  }
  const std::vector<base::FilePath> allowlisted =
      PathsFromSwitch(switches::kDisableExtensionsExcept);
  if (configured != allowlisted) {
    return Fail(error, "allowlist_mismatch",
                "--load-extension and --disable-extensions-except must "
                "contain the same ordered canonical paths");
  }

  std::set<base::FilePath> seen;
  for (const base::FilePath& path : configured) {
    if (!seen.insert(path).second) {
      return Fail(error, "duplicate_path",
                  "duplicate extension source " + PrivacySafeSource(path));
    }
    if (!LoadOne(path, error)) {
      statuses_.push_back({
          .source_path_sha256 = PathDigest(path),
          .state = "error",
      });
      LOG(ERROR) << "CARBONYL_EXTENSION_STATUS state=error "
                 << PrivacySafeSource(path) << " " << *error;
      return false;
    }
  }
  return true;
}

bool CarbonylExtensionLoader::LoadOne(const base::FilePath& path,
                                      std::string* error) {
  base::FilePath canonical;
  if (!path.IsAbsolute() || !base::DirectoryExists(path) ||
      !base::NormalizeFilePath(path, &canonical) || canonical != path) {
    return Fail(error, "path_not_canonical",
                "extension source must be an existing canonical directory " +
                    PrivacySafeSource(path));
  }
  if (HasSymlink(canonical)) {
    return Fail(error, "symlink_rejected",
                "extension source contains a symbolic link " +
                    PrivacySafeSource(canonical));
  }

  std::string manifest_contents;
  if (!base::ReadFileToString(canonical.AppendASCII("manifest.json"),
                              &manifest_contents)) {
    return Fail(error, "manifest_unreadable",
                "manifest is not readable " + PrivacySafeSource(canonical));
  }
  auto manifest_value = base::JSONReader::ReadAndReturnValueWithError(
      manifest_contents, base::JSON_PARSE_CHROMIUM_EXTENSIONS);
  if (!manifest_value.has_value() || !manifest_value->is_dict()) {
    return Fail(error, "invalid_manifest",
                "invalid extension manifest " + PrivacySafeSource(canonical));
  }
  if (manifest_value->GetDict().FindInt("manifest_version") != 3) {
    return Fail(error, "unsupported_manifest",
                "only unpacked Manifest V3 extensions are supported " +
                    PrivacySafeSource(canonical));
  }
  if (manifest_value->GetDict().contains("update_url")) {
    return Fail(error, "remote_update_forbidden",
                "manifest update_url is not supported");
  }

  std::u16string load_error;
  scoped_refptr<Extension> extension =
      file_util::LoadExtension(canonical, mojom::ManifestLocation::kCommandLine,
                               /*flags=*/0, &load_error);
  if (!extension) {
    return Fail(error, "invalid_manifest",
                "invalid extension manifest " + PrivacySafeSource(canonical));
  }
  if (extension->manifest_version() != 3 || !extension->is_extension()) {
    return Fail(error, "unsupported_manifest",
                "only unpacked Manifest V3 extensions are supported " +
                    PrivacySafeSource(canonical));
  }
  if (!ValidatePermissions(extension.get(), error)) {
    return false;
  }

  const PermissionSet& required =
      PermissionsParser::GetRequiredPermissions(extension.get());
  const std::set<std::string> required_api_permissions =
      required.GetAPIsAsStrings();
  carbonyl::ExtensionStatus status{
      .id = extension->id(),
      .version = extension->version().GetString(),
      .source_path_sha256 = PathDigest(canonical),
      .state = "configured",
      .api_permissions = std::vector<std::string>(
          required_api_permissions.begin(), required_api_permissions.end()),
      .host_permission_count =
          required.explicit_hosts().size() + required.scriptable_hosts().size(),
  };
  if (carbonyl::IsExtensionRemovedForRestart(browser_context_,
                                             extension->id())) {
    status.state = "removed_restart";
    statuses_.push_back(std::move(status));
    return true;
  }
  if (carbonyl::IsExtensionDisabledForRestart(browser_context_,
                                              extension->id())) {
    status.state = "disabled_restart";
    statuses_.push_back(std::move(status));
    return true;
  }

  auto ruleset_result = declarative_net_request::InstallIndexHelper::
      IndexAndPersistRulesOnInstall(*extension);
  if (!ruleset_result.has_value()) {
    return Fail(error, "invalid_dnr_ruleset", ruleset_result.error());
  }

  PermissionsUpdater permissions(browser_context_);
  permissions.InitializePermissions(extension.get());
  permissions.GrantActivePermissions(extension.get());
  registrar_->OnExtensionInstalled(extension.get(), syncer::StringOrdinal(),
                                   kInstallFlagInstallImmediately,
                                   std::move(ruleset_result.value()));
  if (!ExtensionRegistry::Get(browser_context_)
           ->enabled_extensions()
           .Contains(extension->id())) {
    return Fail(error, "policy_rejected",
                "extension was rejected by runtime policy " +
                    PrivacySafeSource(canonical));
  }

  status.state = "loaded";
  statuses_.push_back(status);

  std::vector<std::string> api_permissions_list;
  const PermissionSet& active =
      extension->permissions_data()->active_permissions();
  const std::set<std::string> api_permissions = active.GetAPIsAsStrings();
  api_permissions_list.insert(api_permissions_list.end(),
                              api_permissions.begin(), api_permissions.end());
  LOG(INFO) << "CARBONYL_EXTENSION_DIAGNOSTIC state=loaded id="
            << extension->id()
            << " version=" << extension->version().GetString()
            << " source_path_sha256=" << status.source_path_sha256
            << " manifest_sha256="
            << base::HexEncode(crypto::SHA256HashString(manifest_contents))
            << " worker_state=registration_requested api_permissions="
            << base::JoinString(api_permissions_list, ",")
            << " host_permission_count=" << active.explicit_hosts().size();
  return true;
}

void CarbonylExtensionLoader::PreAddExtension(const Extension* extension,
                                              const Extension* old_extension) {
  if (!old_extension) {
    ExtensionPrefs::Get(browser_context_)
        ->RemoveDisableReason(extension->id(), disable_reason::DISABLE_RELOAD);
  }
}

void CarbonylExtensionLoader::OnAddNewOrUpdatedExtension(
    const Extension* extension) {}
void CarbonylExtensionLoader::PostActivateExtension(
    scoped_refptr<const Extension> extension) {
  PermissionsUpdater(browser_context_).ApplyPolicyHostRestrictions(*extension);
}
void CarbonylExtensionLoader::PostDeactivateExtension(
    scoped_refptr<const Extension> extension) {}
void CarbonylExtensionLoader::PreUninstallExtension(
    scoped_refptr<const Extension> extension) {}
void CarbonylExtensionLoader::PostUninstallExtension(
    scoped_refptr<const Extension> extension,
    base::OnceClosure done_callback) {
  std::move(done_callback).Run();
}
void CarbonylExtensionLoader::LoadExtensionForReload(
    const ExtensionId& extension_id,
    const base::FilePath& path) {}
void CarbonylExtensionLoader::LoadExtensionForReloadWithQuietFailure(
    const ExtensionId& extension_id,
    const base::FilePath& path) {}
void CarbonylExtensionLoader::ShowExtensionDisabledError(
    const Extension* extension,
    bool is_remote_install) {}
bool CarbonylExtensionLoader::CanEnableExtension(const Extension* extension) {
  return true;
}
bool CarbonylExtensionLoader::CanDisableExtension(const Extension* extension) {
  return true;
}
void CarbonylExtensionLoader::GrantActivePermissions(
    const Extension* extension) {
  PermissionsUpdater(browser_context_).GrantActivePermissions(extension);
}
void CarbonylExtensionLoader::UpdateExternalExtensionAlert() {}
void CarbonylExtensionLoader::OnExtensionInstalled(
    const Extension* extension,
    const syncer::StringOrdinal& page_ordinal,
    int install_flags,
    base::DictValue ruleset_install_prefs) {
  registrar_->AddNewOrUpdatedExtension(extension, install_flags, page_ordinal,
                                       /*install_parameter=*/{},
                                       std::move(ruleset_install_prefs));
}

}  // namespace extensions
