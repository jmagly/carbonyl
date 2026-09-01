#!/usr/bin/env bash

set -euo pipefail

CARBONYL_ROOT="$(cd "$(dirname -- "$0")/.." && pwd)"

checks=(
  'src/extensions/management.h:carbonyl-extension-management'
  'src/extensions/management.h:carbonyl-extension-mutation'
  'src/extensions/management.cc:management_unavailable'
  'src/extensions/management.cc:management_read_only'
  'src/extensions/management.cc:restart_required'
  'src/extensions/management.cc:ACTION_ON_CLICKED'
  'src/extensions/management.cc:GetDisplayBadgeText'
  'src/extensions/extension_loader.cc:CARBONYL_EXTENSION_STATUS state=error'
  'src/browser/operator_window.cc:CARBONYL_EXTENSION_ACTION_STATE'
  'src/browser/operator_window.cc:CARBONYL_EXTENSION_SURFACE navigation_denied'
  'src/browser/operator_window.cc:Extension popup'
  'src/browser/operator_window.cc:Extension options'
  'scripts/test-extension-runtime-integration.sh:state=disabled_restart'
  'scripts/test-extension-runtime-integration.sh:state=removed_restart'
  'scripts/test-extension-actions.sh:guest-local Xorg :99'
  'docs/extensions.md:never mutate the live registry'
)

for check in "${checks[@]}"; do
  path=${check%%:*}
  pattern=${check#*:}
  rg -q --fixed-strings -- "$pattern" "$CARBONYL_ROOT/$path"
done

if rg -q -- '(cookie_value|storage_value|host_pattern=|source_path=)' \
  "$CARBONYL_ROOT/src/extensions/management.cc" \
  "$CARBONYL_ROOT/src/browser/operator_window.cc"; then
  echo "management diagnostics expose forbidden extension data" >&2
  exit 1
fi

echo "PASS: extension management, diagnostics, and operator-action contract"
