#!/usr/bin/env bash
# audit-cross-layer.sh — Audit carbonyl patches for cross-layer blink/non-blink reaches
#
# Why: M135 build (#27) was broken by patch 0002 reaching into blink/renderer/core/*
# headers from a non-blink translation unit (content/renderer/render_frame_impl.cc),
# which triggered an Oilpan/cppgc cascade. This script catches similar patterns
# across all patches before they trip a future rebase.
#
# Categories:
#   A. blink/renderer/* includes added to non-blink TUs (the known-bad pattern)
#   B. blink/renderer/* includes removed from non-blink TUs (regression check)
#   C. carbonyl::* symbols referenced from blink TUs through non-public headers
#   D. Files patched by carbonyl that live under third_party/blink/ (informational)
#   E. Other layering violations (forward decls, static_casts, internal accessors)
#
# Usage: bash scripts/audit-cross-layer.sh [output-format]
#   Default output: markdown table to stdout
#
# See: roctinam/carbonyl#27 (cppgc cascade), #28 (Path A), #29 (this audit)

set -euo pipefail

CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && dirname -- "$(pwd)")"
PATCH_DIR="$CARBONYL_ROOT/chromium/patches/chromium"
cd "$CARBONYL_ROOT"

if [ ! -d "$PATCH_DIR" ]; then
    echo "ERROR: $PATCH_DIR not found. Run from carbonyl repo root." >&2
    exit 2
fi

# Non-blink directory regex — files under these prefixes should NOT include
# blink/renderer/* headers (the cppgc cascade trigger).
NON_BLINK_PREFIX='^(content|components|services|chrome|headless|cc|ui|gpu|net|mojo|base|build|skia)/'

# Blink-internal include patterns (NOT third_party/blink/public/*)
BLINK_INTERNAL='third_party/blink/renderer/(core|modules|platform/heap|platform/graphics)/'

declare -A FINDINGS
declare -A FILES_PATCHED

echo "# Cross-Layer Audit — carbonyl/chromium patches"
echo
echo "**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "**Patch count**: $(ls -1 "$PATCH_DIR"/*.patch 2>/dev/null | wc -l)"
echo "**Issue**: roctinam/carbonyl#29"
echo
echo "---"
echo

# ---------------------------------------------------------------------------
# Category A: blink/renderer includes ADDED to non-blink TUs
# ---------------------------------------------------------------------------
echo "## Category A — blink/renderer/* includes added to non-blink TUs"
echo
echo "These are the **known-bad** pattern. Each match is a candidate for the"
echo "Path A refactor (#28). The cppgc cascade fires whenever a non-blink TU"
echo "transitively pulls in \`garbage_collected.h\` and also instantiates"
echo "\`base::SequenceBound<T>\` with a void allocator."
echo
echo "| Patch | Target file | Added include |"
echo "|-------|-------------|---------------|"

A_COUNT=0
for patch in "$PATCH_DIR"/*.patch; do
    patch_name=$(basename "$patch" .patch)

    # Walk the patch and track current target file
    current_file=""
    while IFS= read -r line; do
        # Track --- a/path or +++ b/path lines to know which file we're in
        if [[ "$line" =~ ^\+\+\+\ b/(.*)$ ]]; then
            current_file="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^\+#include\ \"($BLINK_INTERNAL[^\"]*)\" ]]; then
            include_path="${BASH_REMATCH[1]}"
            # Is current_file under a non-blink prefix?
            if [[ -n "$current_file" ]] && [[ "$current_file" =~ $NON_BLINK_PREFIX ]]; then
                echo "| \`$patch_name\` | \`$current_file\` | \`$include_path\` |"
                A_COUNT=$((A_COUNT + 1))
            fi
        fi
    done < "$patch"
done

if [ "$A_COUNT" -eq 0 ]; then
    echo "| _(none — clean!)_ | | |"
fi
echo
echo "**Category A total**: $A_COUNT findings"
echo

# ---------------------------------------------------------------------------
# Category B: blink/renderer includes REMOVED from non-blink TUs
# ---------------------------------------------------------------------------
echo "## Category B — blink/renderer/* includes removed from non-blink TUs"
echo
echo "Inverse of Category A. Confirms we haven't undone someone's earlier"
echo "cleanup. Findings here are usually fine but worth noting."
echo
echo "| Patch | Target file | Removed include |"
echo "|-------|-------------|-----------------|"

B_COUNT=0
for patch in "$PATCH_DIR"/*.patch; do
    patch_name=$(basename "$patch" .patch)

    current_file=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^\+\+\+\ b/(.*)$ ]]; then
            current_file="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^\-#include\ \"($BLINK_INTERNAL[^\"]*)\" ]]; then
            include_path="${BASH_REMATCH[1]}"
            if [[ -n "$current_file" ]] && [[ "$current_file" =~ $NON_BLINK_PREFIX ]]; then
                echo "| \`$patch_name\` | \`$current_file\` | \`$include_path\` |"
                B_COUNT=$((B_COUNT + 1))
            fi
        fi
    done < "$patch"
done

if [ "$B_COUNT" -eq 0 ]; then
    echo "| _(none)_ | | |"
fi
echo
echo "**Category B total**: $B_COUNT findings"
echo

# ---------------------------------------------------------------------------
# Category C: carbonyl::* symbols referenced from blink TUs
# ---------------------------------------------------------------------------
echo "## Category C — \`carbonyl::*\` references in blink TUs"
echo
echo "Blink TUs that reference carbonyl symbols. These should go through the"
echo "public \`carbonyl/src/browser/bridge.h\` header (or another carbonyl"
echo "public header). Direct reaches into other carbonyl internals are a"
echo "smell."
echo
echo "| Patch | Blink file | Carbonyl reference |"
echo "|-------|------------|---------------------|"

C_COUNT=0
for patch in "$PATCH_DIR"/*.patch; do
    patch_name=$(basename "$patch" .patch)

    current_file=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^\+\+\+\ b/(.*)$ ]]; then
            current_file="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^\+.*carbonyl:: ]]; then
            # Only flag if current file is under third_party/blink/
            if [[ -n "$current_file" ]] && [[ "$current_file" == third_party/blink/* ]]; then
                # Strip leading + and excess whitespace
                ref=$(echo "$line" | sed 's/^+//' | sed 's/^[[:space:]]*//' | head -c 100)
                echo "| \`$patch_name\` | \`$current_file\` | \`${ref}\` |"
                C_COUNT=$((C_COUNT + 1))
            fi
        fi
    done < "$patch"
done

if [ "$C_COUNT" -eq 0 ]; then
    echo "| _(none)_ | | |"
fi
echo
echo "**Category C total**: $C_COUNT findings"
echo

# ---------------------------------------------------------------------------
# Category D: blink files patched by carbonyl (informational)
# ---------------------------------------------------------------------------
echo "## Category D — Files under \`third_party/blink/\` patched by carbonyl"
echo
echo "These are blink-side modifications. They get \`INSIDE_BLINK\` defined"
echo "automatically by their GN target. Listed here for situational awareness:"
echo "Path A (#28) needs to know which files are blink-side vs content-side."
echo
echo "| Patch | Blink file |"
echo "|-------|------------|"

D_COUNT=0
declare -A SEEN_BLINK_FILES
for patch in "$PATCH_DIR"/*.patch; do
    patch_name=$(basename "$patch" .patch)

    while IFS= read -r line; do
        if [[ "$line" =~ ^diff\ --git\ a/(third_party/blink/[^[:space:]]+)\ b/ ]]; then
            blink_file="${BASH_REMATCH[1]}"
            key="$patch_name|$blink_file"
            if [ -z "${SEEN_BLINK_FILES[$key]+x}" ]; then
                SEEN_BLINK_FILES[$key]=1
                echo "| \`$patch_name\` | \`$blink_file\` |"
                D_COUNT=$((D_COUNT + 1))
            fi
        fi
    done < "$patch"
done

if [ "$D_COUNT" -eq 0 ]; then
    echo "| _(none)_ | |"
fi
echo
echo "**Category D total**: $D_COUNT (file × patch) entries"
echo

# ---------------------------------------------------------------------------
# Category E: other layering violations
# ---------------------------------------------------------------------------
echo "## Category E — Other layering violations"
echo
echo "Patterns that don't trip the cppgc cascade today but are early warning"
echo "signs of future cross-layer creep:"
echo
echo "- Forward declarations of \`blink::*\` types in non-blink headers"
echo "- \`static_cast<blink::*>(...)\` from non-blink code"
echo "- Direct use of blink internal accessors (\`WebFrameWidgetImpl::GetMainFrameImpl\` etc.)"
echo

echo "### E1 — Forward declarations of blink types in non-blink files"
echo
echo "| Patch | Target file | Forward decl |"
echo "|-------|-------------|--------------|"

E1_COUNT=0
for patch in "$PATCH_DIR"/*.patch; do
    patch_name=$(basename "$patch" .patch)
    current_file=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^\+\+\+\ b/(.*)$ ]]; then
            current_file="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^\+namespace\ blink\ \{\ class ]]; then
            if [[ -n "$current_file" ]] && [[ "$current_file" =~ $NON_BLINK_PREFIX ]]; then
                ref=$(echo "$line" | sed 's/^+//' | head -c 80)
                echo "| \`$patch_name\` | \`$current_file\` | \`${ref}\` |"
                E1_COUNT=$((E1_COUNT + 1))
            fi
        fi
    done < "$patch"
done
if [ "$E1_COUNT" -eq 0 ]; then
    echo "| _(none)_ | | |"
fi
echo
echo "**E1 total**: $E1_COUNT findings"
echo

echo "### E2 — \`static_cast<blink::...>\` from non-blink files"
echo
echo "| Patch | Target file | Cast |"
echo "|-------|-------------|------|"

E2_COUNT=0
for patch in "$PATCH_DIR"/*.patch; do
    patch_name=$(basename "$patch" .patch)
    current_file=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^\+\+\+\ b/(.*)$ ]]; then
            current_file="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^\+.*static_cast\<blink:: ]]; then
            if [[ -n "$current_file" ]] && [[ "$current_file" =~ $NON_BLINK_PREFIX ]]; then
                ref=$(echo "$line" | sed 's/^+[[:space:]]*//' | head -c 100)
                echo "| \`$patch_name\` | \`$current_file\` | \`${ref}\` |"
                E2_COUNT=$((E2_COUNT + 1))
            fi
        fi
    done < "$patch"
done
if [ "$E2_COUNT" -eq 0 ]; then
    echo "| _(none)_ | | |"
fi
echo
echo "**E2 total**: $E2_COUNT findings"
echo

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "---"
echo
echo "## Summary"
echo
echo "| Category | Count | Severity |"
echo "|----------|-------|----------|"
echo "| A — blink includes added to non-blink | $A_COUNT | **Critical** if non-zero (cppgc cascade trigger) |"
echo "| B — blink includes removed from non-blink | $B_COUNT | Informational |"
echo "| C — carbonyl refs in blink TUs | $C_COUNT | Watch (route through public headers) |"
echo "| D — blink files patched by carbonyl | $D_COUNT | Informational |"
echo "| E1 — forward decls of blink in non-blink | $E1_COUNT | Watch (creep precursor) |"
echo "| E2 — static_cast to blink from non-blink | $E2_COUNT | Watch (creep precursor) |"
echo
echo "**Total findings**: $((A_COUNT + B_COUNT + C_COUNT + E1_COUNT + E2_COUNT))"
