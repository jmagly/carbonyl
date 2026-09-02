#!/usr/bin/env bash

set -euo pipefail

CARBONYL_ROOT="$(cd "$(dirname -- "$0")/.." && pwd)"
FIXTURE="$CARBONYL_ROOT/tests/fixtures/extensions/mv3-runtime"

node -e '
  const fs = require("fs");
  for (const file of process.argv.slice(1)) JSON.parse(fs.readFileSync(file));
' "$FIXTURE/manifest.json" "$FIXTURE/rules.json"

required_source_checks=(
  'src/extensions/browser_client.cc:kDisableExtensions'
  'src/extensions/browser_client.cc:kLoadExtension'
  'src/extensions/extension_loader.cc:kDisableExtensionsExcept'
  'src/extensions/extension_loader.cc:NormalizeFilePath'
  'src/extensions/extension_loader.cc:SHOW_SYM_LINKS'
  'src/extensions/extension_loader.cc:manifest_version() != 3'
  'src/extensions/extension_system.cc:DISALLOWED_BY_POLICY'
  'src/extensions/extension_system.cc:Extension Preferences'
  'src/extensions/extension_system.cc:StateStore::BackendType::RULES'
  'src/extensions/extension_loader.cc:IndexAndPersistRulesOnInstall'
  'src/extensions/extension_loader.cc:PermissionsUpdater'
  'src/extensions/extension_loader.cc:CARBONYL_EXTENSION_DIAGNOSTIC'
  'src/extensions/extension_loader.cc:unsupported_permission'
  'src/extensions/extension_loader.cc:remote_update_forbidden'
  'src/extensions/extension_loader.cc:unsupported_host_scheme'
  'src/extensions/browser_client.cc:CarbonylRuntimeAPIDelegate'
  'src/extensions/browser_client.cc:CarbonylExtensionManagementClient'
  'src/extensions/browser_client.cc:CarbonylExtensionWebContentsObserver'
  'src/extensions/renderer_client.cc:RunScriptsAtDocumentStart'
  'src/extensions/renderer_client.cc:CarbonylRenderFrameObserver'
  'src/extensions/renderer_client.cc:ExtensionsWillEvaluateServiceWorker'
  'src/extensions/renderer_client.cc:ExtensionsWillDestroyServiceWorker'
  'src/extensions/renderer_client.cc:kEnableExtensionsRendererSwitch'
  'src/extensions/renderer_client.cc:ExtensionsWebViewCreated'
  'src/extensions/content_browser_client_hooks.cc:CreateExtensionWorkerMainResourceURLLoaderFactory'
  'src/extensions/content_browser_client_hooks.cc:RegisterExtensionAssociatedServiceWorkerBinders'
  'src/extensions/content_browser_client_hooks.cc:MaybeProxyExtensionURLLoaderFactory'
  'src/extensions/content_browser_client_hooks.cc:AddExtensionNavigationThrottle'
  'src/extensions/content_browser_client_hooks.cc:kEnableExtensionsRendererSwitch'
  'src/extensions/content_browser_client_hooks.cc:CanCommitExtensionURL'
)

for check in "${required_source_checks[@]}"; do
  path=${check%%:*}
  pattern=${check#*:}
  rg -q --fixed-strings -- "$pattern" "$CARBONYL_ROOT/$path"
done

for runtime_resource in headless_lib_data.pak headless_lib_strings.pak; do
  rg -q --fixed-strings -- \
    "cp \"\$src/$runtime_resource\" ." \
    "$CARBONYL_ROOT/scripts/copy-binaries.sh"
done

rg -q --fixed-strings -- \
  'extensions/strings/extensions_strings_en-US.pak' \
  "$CARBONYL_ROOT/chromium/patches/chromium/0041-carbonyl-include-extension-strings-in-headless-pack.patch"

rg -q --fixed-strings -- \
  'DestroyBrowserContextServices' \
  "$CARBONYL_ROOT/chromium/patches/chromium/0042-carbonyl-complete-extension-worker-lifecycle.patch"

for fixture_contract in \
  'content_script.js:chrome.runtime.sendMessage' \
  'content_script.js:chrome.runtime.connect' \
  'service_worker.js:chrome.runtime.onMessage' \
  'service_worker.js:chrome.runtime.onConnect' \
  'service_worker.js:chrome.storage.local' \
  'manifest.json:declarativeNetRequest' \
  'rules.json:carbonyl-extension-blocked'; do
  file=${fixture_contract%%:*}
  pattern=${fixture_contract#*:}
  rg -q --fixed-strings -- "$pattern" "$FIXTURE/$file"
done

if rg -q -- '(ChromeWebstore|FOLLOW_SYMLINKS|native_message|NativeMessage)' \
  "$CARBONYL_ROOT/src/extensions"; then
  echo "unexpected remote, symlink-following, or native-messaging surface" >&2
  exit 1
fi

echo "PASS: extension runtime contract and MV3 fixture"
