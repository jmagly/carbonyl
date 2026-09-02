#!/usr/bin/env bash
# audit-extension-embedder.sh — verify the upstream surface assumed by ADR-005

set -euo pipefail

CARBONYL_ROOT="$(cd "$(dirname -- "$0")/.." && pwd)"
CHROMIUM_SRC="${CHROMIUM_SRC:-$CARBONYL_ROOT/chromium/src}"

usage() {
    echo "Usage: CHROMIUM_SRC=/path/to/chromium/src $0" >&2
}

if [ "$#" -ne 0 ]; then
    usage
    exit 2
fi

if [ ! -d "$CHROMIUM_SRC" ]; then
    echo "ERROR: Chromium source directory not found: $CHROMIUM_SRC" >&2
    exit 2
fi

required_files=(
    extensions/buildflags/buildflags.gni
    extensions/common/extensions_client.h
    extensions/browser/extensions_browser_client.h
    extensions/browser/extension_system.h
    extensions/renderer/extensions_renderer_client.h
    headless/BUILD.gn
    headless/lib/browser/headless_content_browser_client.cc
    headless/lib/browser/headless_browser_context_impl.cc
    headless/lib/renderer/headless_content_renderer_client.cc
)

carbonyl_files=(
    src/extensions/BUILD.gn
    src/extensions/common_client.h
    src/extensions/common_client.cc
    src/extensions/browser_client.h
    src/extensions/browser_client.cc
    src/extensions/content_browser_client_hooks.h
    src/extensions/content_browser_client_hooks.cc
    src/extensions/extension_loader.h
    src/extensions/extension_loader.cc
    src/extensions/extension_system.h
    src/extensions/extension_system.cc
    src/extensions/renderer_client.h
    src/extensions/renderer_client.cc
)

failures=0

pass() {
    printf 'PASS  %s\n' "$1"
}

fail() {
    printf 'FAIL  %s\n' "$1"
    failures=$((failures + 1))
}

contains() {
    local path=$1
    local pattern=$2
    rg -q -- "$pattern" "$CHROMIUM_SRC/$path"
}

expected_version=$(sed -n 's/.*src\.git@\([^\"]*\)".*/\1/p' \
    "$CARBONYL_ROOT/chromium/.gclient" | head -n 1)
if [ -n "$expected_version" ]; then
    pass "Carbonyl pins Chromium $expected_version"
else
    fail "could not read the Chromium version from chromium/.gclient"
fi

for path in "${required_files[@]}"; do
    if [ -f "$CHROMIUM_SRC/$path" ]; then
        pass "$path exists"
    else
        fail "$path is missing"
    fi
done

for path in "${carbonyl_files[@]}"; do
    if [ -f "$CARBONYL_ROOT/$path" ]; then
        pass "$path exists"
    else
        fail "$path is missing"
    fi
done

browser_client_source="$CARBONYL_ROOT/src/extensions/browser_client.cc"
client_create_line=$(rg -n -F \
    'extensions::g_client = new extensions::CarbonylExtensionsBrowserClient();' \
    "$browser_client_source" | cut -d: -f1)
client_set_line=$(rg -n -F \
    'extensions::ExtensionsBrowserClient::Set(extensions::g_client);' \
    "$browser_client_source" | cut -d: -f1)
factory_build_line=$(rg -n -F \
    'extensions::EnsureBrowserContextKeyedServiceFactoriesBuilt();' \
    "$browser_client_source" | cut -d: -f1)
if [[ -n "$client_create_line" && -n "$client_set_line" && \
      -n "$factory_build_line" ]] && \
    (( client_create_line < client_set_line && \
       client_set_line < factory_build_line )); then
    pass "ExtensionsBrowserClient is installed before keyed-service factories"
else
    fail "ExtensionsBrowserClient must precede keyed-service factory construction"
fi

if [ -e "$CHROMIUM_SRC/extensions/shell" ]; then
    fail "extensions/shell unexpectedly exists; review the ADR before reusing it"
else
    pass "extensions/shell is absent (Carbonyl must own the embedder)"
fi

if contains extensions/buildflags/buildflags.gni \
    'enable_extensions = !is_android && !is_ios'; then
    pass "desktop builds enable the extensions module by default"
else
    fail "enable_extensions desktop default changed"
fi

if contains extensions/common/extensions_client.h \
    'static void Set\(ExtensionsClient\* client\)'; then
    pass "common process client seam is present"
else
    fail "ExtensionsClient::Set seam changed"
fi

if contains extensions/browser/extensions_browser_client.h \
    'static void Set\(ExtensionsBrowserClient\* client\)'; then
    pass "browser process client seam is present"
else
    fail "ExtensionsBrowserClient::Set seam changed"
fi

if contains extensions/browser/extension_system.h \
    'InitForRegularProfile\(bool extensions_enabled\)'; then
    pass "per-BrowserContext ExtensionSystem initialization seam is present"
else
    fail "ExtensionSystem initialization seam changed"
fi

if contains extensions/renderer/extensions_renderer_client.h \
    'static void Set\(ExtensionsRendererClient\* client\)'; then
    pass "renderer process client seam is present"
else
    fail "ExtensionsRendererClient::Set seam changed"
fi

if rg -q -- '//extensions/(browser|common|renderer)' \
    "$CHROMIUM_SRC/headless/BUILD.gn"; then
    fail "headless directly links an upstream extensions target"
else
    pass "headless BUILD.gn reaches extensions only through Carbonyl clients"
fi

if rg -q -- 'extensions::(ExtensionsClient|ExtensionsBrowserClient|ExtensionsRendererClient|ExtensionSystem)' \
    "$CHROMIUM_SRC/headless/lib/headless_content_main_delegate.cc" \
    "$CHROMIUM_SRC/headless/lib/browser/headless_content_browser_client.cc" \
    "$CHROMIUM_SRC/headless/lib/browser/headless_browser_impl.cc" \
    "$CHROMIUM_SRC/headless/lib/renderer/headless_content_renderer_client.cc"; then
    fail "headless contains a direct upstream extension lifecycle call"
else
    pass "headless delegates extension lifecycle only to Carbonyl-owned hooks"
fi

linkage_checks=(
    'headless/BUILD.gn://carbonyl/src/extensions:common_client'
    'headless/BUILD.gn://carbonyl/src/extensions:browser_client'
    'headless/BUILD.gn://carbonyl/src/extensions:renderer_client'
    'headless/lib/headless_content_main_delegate.cc:InstallExtensionsCommonClient'
    'headless/lib/browser/headless_content_browser_client.cc:InstallExtensionsBrowserClient'
    'headless/lib/browser/headless_browser_impl.cc:StartExtensionsBrowserClientTearDown'
    'headless/lib/browser/headless_browser_context_impl.cc:InitializeExtensionContext'
    'headless/lib/browser/headless_web_contents_impl.cc:CreateExtensionWebContentsObserver'
    'headless/lib/browser/headless_content_browser_client.cc:RegisterExtensionAssociatedFrameBinders'
    'headless/lib/browser/headless_content_browser_client.cc:RegisterExtensionAssociatedServiceWorkerBinders'
    'headless/lib/browser/headless_content_browser_client.cc:MaybeProxyExtensionURLLoaderFactory'
    'headless/lib/browser/headless_content_browser_client.cc:AddExtensionNavigationThrottle'
    'headless/lib/browser/headless_content_browser_client.cc:CanCommitExtensionURL'
    'headless/lib/browser/headless_content_browser_client.cc:GetExtensionEffectiveURL'
    'headless/lib/browser/headless_content_browser_client.cc:ShouldUseExtensionProcessPerSite'
    'headless/lib/browser/headless_content_browser_client.cc:ShouldUseSpareProcessForExtensionURL'
    'headless/lib/browser/headless_content_browser_client.cc:DoesExtensionSiteRequireDedicatedProcess'
    'headless/lib/browser/headless_content_browser_client.cc:IsSuitableExtensionProcessHost'
    'headless/lib/browser/headless_content_browser_client.cc:AppendExtensionRendererCommandLineSwitches'
    'headless/lib/renderer/headless_content_renderer_client.cc:InstallExtensionsRendererClient'
    'headless/lib/renderer/headless_content_renderer_client.cc:ExtensionsRenderThreadStarted'
    'headless/lib/renderer/headless_content_renderer_client.cc:ExtensionsWebViewCreated'
    'headless/lib/renderer/headless_content_renderer_client.cc:RunExtensionScriptsAtDocumentStart'
)
for check in "${linkage_checks[@]}"; do
    path=${check%%:*}
    pattern=${check#*:}
    if contains "$path" "$pattern"; then
        pass "$path contains $pattern"
    else
        fail "$path is missing $pattern"
    fi
done

if rg -q -- '(//chrome/|#include "chrome/)' "$CARBONYL_ROOT/src/extensions"; then
    fail "Carbonyl extension clients import Chrome implementation code"
else
    pass "Carbonyl extension clients do not import Chrome implementation code"
fi

if rg -q -- '(//chrome/|#include "chrome/|FOLLOW_SYMLINKS|ChromeWebstore)' \
    "$CARBONYL_ROOT/src/extensions"; then
    fail "runtime imports Chrome, follows symlinks, or exposes Web Store code"
else
    pass "runtime stays Carbonyl-owned, local-only, and symlink rejecting"
fi

if rg -q -- 'kDisableExtensions' \
    "$CARBONYL_ROOT/src/extensions/browser_client.cc" && \
   rg -q -- 'kLoadExtension' \
    "$CARBONYL_ROOT/src/extensions/browser_client.cc" && \
   rg -q -- 'kDisableExtensionsExcept' \
    "$CARBONYL_ROOT/src/extensions/extension_loader.cc"; then
    pass "runtime is default-disabled and requires matching explicit paths"
else
    fail "runtime activation is missing a default-deny command-line gate"
fi

if rg -q -- 'DISALLOWED_BY_POLICY' \
    "$CARBONYL_ROOT/src/extensions/extension_system.cc" && \
   rg -q -- 'manifest_version\(\) != 3' \
    "$CARBONYL_ROOT/src/extensions/extension_loader.cc"; then
    pass "updates are denied and only unpacked MV3 is accepted"
else
    fail "runtime update or manifest-version policy drifted"
fi

runtime_contract_checks=(
    'src/extensions/browser_client.cc:CarbonylRuntimeAPIDelegate'
    'src/extensions/browser_client.cc:CarbonylKioskDelegate'
    'src/extensions/browser_client.cc:CarbonylExtensionWebContentsObserver'
    'src/extensions/extension_system.cc:StateStore::BackendType::RULES'
    'src/extensions/extension_system.cc:WebRequestEventRouterFactory::GetForBrowserContext'
    'src/extensions/extension_loader.cc:IndexAndPersistRulesOnInstall'
    'src/extensions/extension_loader.cc:PermissionsUpdater'
    'src/extensions/extension_loader.cc:CARBONYL_EXTENSION_DIAGNOSTIC'
)
for check in "${runtime_contract_checks[@]}"; do
    path=${check%%:*}
    pattern=${check#*:}
    if rg -q --fixed-strings -- "$pattern" "$CARBONYL_ROOT/$path"; then
        pass "$path contains $pattern"
    else
        fail "$path is missing $pattern"
    fi
done

render_thread_hook=$(sed -n \
    '/^void ExtensionsRenderThreadStarted()/,/^}/p' \
    "$CARBONYL_ROOT/src/extensions/renderer_client.cc")
if grep -q 'g_client->RenderThreadStarted();' <<<"$render_thread_hook" && \
   ! grep -q 'RuntimeEnabled' <<<"$render_thread_hook"; then
    pass "renderer process interface is registered before opt-in frame gates"
else
    fail "extensions.mojom.Renderer registration must not be opt-in gated"
fi

if contains headless/lib/browser/headless_browser_context_impl.cc \
    'DestroyBrowserContextServices'; then
    pass "BrowserContext keyed-service teardown seam is present"
else
    fail "BrowserContext teardown seam changed"
fi

if [ -d "$CHROMIUM_SRC/.git" ] && [ -n "$expected_version" ]; then
    expected_commit=$(git -C "$CHROMIUM_SRC" rev-list -n 1 "$expected_version" \
        2>/dev/null || true)
    actual_commit=$(git -C "$CHROMIUM_SRC" rev-parse HEAD 2>/dev/null || true)
    if [ -n "$expected_commit" ] && \
        git -C "$CHROMIUM_SRC" merge-base --is-ancestor \
            "$expected_commit" "$actual_commit"; then
        pass "checkout descends from $expected_version"
    elif [ -n "$expected_commit" ]; then
        fail "checkout is not based on $expected_version"
    else
        fail "checkout does not contain tag $expected_version"
    fi
fi

if [ "$failures" -ne 0 ]; then
    printf '\nExtension embedder audit failed: %d invariant(s) changed.\n' "$failures" >&2
    exit 1
fi

echo
echo "Extension embedder audit passed."
