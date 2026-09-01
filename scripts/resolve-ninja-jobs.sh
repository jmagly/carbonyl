#!/usr/bin/env bash
# Resolve a bounded Ninja parallelism value for shared interactive builders.

set -euo pipefail

requested="${1:-}"
cores="${2:-$(nproc)}"
cap="${3:-4}"

for value_name in cores cap; do
    value="${!value_name}"
    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
        echo "error: ${value_name} must be a positive integer (got: ${value})" >&2
        exit 2
    fi
done

if [[ -n "$requested" ]]; then
    if [[ ! "$requested" =~ ^[1-9][0-9]*$ ]]; then
        echo "error: requested Ninja jobs must be a positive integer (got: ${requested})" >&2
        exit 2
    fi
    jobs="$requested"
else
    jobs=$((cores / 2))
    ((jobs >= 1)) || jobs=1
fi

if ((jobs > cap)); then
    echo "warning: capping Ninja parallelism from ${jobs} to ${cap}" >&2
    jobs="$cap"
fi

printf '%s\n' "$jobs"
