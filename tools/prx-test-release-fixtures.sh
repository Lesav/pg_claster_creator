#!/usr/bin/env bash
# Purpose: run the existing isolated regression helpers for a release on one WSL.
# Usage: bash tools/prx-test-release-fixtures.sh REPO DISTRO VERSION LOG_ROOT
# Args: REPO -- source tree; DISTRO -- evidence label; VERSION -- expected version;
#   LOG_ROOT -- parent directory, existing fixture logs are never overwritten.
# Output: LOG_ROOT/DISTRO/fixtures/check.log; no actual cluster changes.
# Example: bash tools/prx-test-release-fixtures.sh /repo Astra 2.4.0 /repo/tmp/qa
set -Eeuo pipefail
repo="$1"; distro="$2"; version="$3"
logs="$4/$distro/fixtures"
[[ ! -e "$logs" ]] || exit 2
mkdir -p "$logs"
exec >"$logs/check.log" 2>&1
date --iso-8601=seconds
for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh; do
    bash -n "$repo/$name"
    bash "$repo/$name" --version | grep -F "версия $version"
    bash "$repo/$name" --help >/dev/null
done
for helper in prx-test-cluster-delete prx-test-cluster-rename prx-test-cluster-power prx-test-edit-menu prx-test-tantor-editions prx-test-deb-tmp-cleanup prx-test-config-priority; do
    printf '\nCHECK %s\n' "$helper"
    timeout -k 5 120 bash "$repo/tools/$helper.sh" "$repo"
done
date --iso-8601=seconds
printf 'PASS release checks\n'
