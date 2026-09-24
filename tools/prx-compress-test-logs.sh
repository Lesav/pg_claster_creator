#!/usr/bin/env bash
# Purpose: compress completed test logs strictly larger than 100 KiB (102400 bytes).
# Usage: bash tools/prx-compress-test-logs.sh LOG_DIR
# Run only after all log readers/writers have finished. No ENV interface.
# Output: compressed paths; exit 1 on traversal/compression errors. Never overwrite
# existing archives or follow symlinks. gzip retains the original on failure.
set -Eeuo pipefail
root="$(realpath -e -- "$1")"
[[ -d "$root" && "$root" != / ]] || exit 2
list="$(mktemp)"
trap 'rm -f -- "$list"' EXIT
find "$root" -type f -name '*.log' -size +102400c -print0 >"$list"
rc=0
while IFS= read -r -d '' path; do
    if [[ -e "$path.gz" || -L "$path.gz" ]]; then
        printf 'ERROR archive already exists; original retained: %s\n' "$path" >&2
        rc=1
    elif gzip -- "$path" </dev/null; then
        printf '%s.gz\n' "$path"
    else
        printf 'ERROR could not compress: %s\n' "$path" >&2
        rc=1
    fi
done <"$list"
exit "$rc"
