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
    fail "headless already links an extensions target; refresh the baseline"
else
    pass "headless BUILD.gn has no extensions module dependency"
fi

if rg -q -- 'Extensions(Browser|Renderer|Client|System)' \
    "$CHROMIUM_SRC/headless/lib/browser/headless_content_browser_client.cc" \
    "$CHROMIUM_SRC/headless/lib/renderer/headless_content_renderer_client.cc"; then
    fail "headless clients already initialize extensions; refresh the baseline"
else
    pass "headless content clients have no extension lifecycle hooks"
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
    if [ -n "$expected_commit" ] && [ "$actual_commit" = "$expected_commit" ]; then
        pass "checkout HEAD matches $expected_version"
    elif [ -n "$expected_commit" ]; then
        fail "checkout HEAD does not match $expected_version"
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
