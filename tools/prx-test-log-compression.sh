#!/usr/bin/env bash
# Usage: bash tools/prx-test-log-compression.sh REPO
# Isolated filesystem fixtures; no packages, services or clusters are touched.
set -Eeuo pipefail
repo="$(realpath "$1")"
work="$(mktemp -d /tmp/pgcc-log-gzip.XXXXXXXX)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/logs/nested space"
truncate -s 102399 "$work/logs/small.log"
truncate -s 102400 "$work/logs/boundary.log"
truncate -s 102401 "$work/logs/nested space/large.log"
truncate -s 102401 "$work/outside.log"
truncate -s 102401 "$work/logs/untouched.txt"
ln -s "$work/outside.log" "$work/logs/link.log"
sha256sum "$work/logs/nested space/large.log" | cut -d ' ' -f1 >"$work/hash"
bash "$repo/tools/prx-compress-test-logs.sh" "$work/logs"
[[ -f "$work/logs/small.log" && -f "$work/logs/boundary.log" ]]
[[ ! -e "$work/logs/nested space/large.log" && -f "$work/logs/nested space/large.log.gz" ]]
gzip -t "$work/logs/nested space/large.log.gz"
[[ "$(gzip -cd "$work/logs/nested space/large.log.gz" | sha256sum | cut -d ' ' -f1)" == "$(cat "$work/hash")" ]]
[[ -L "$work/logs/link.log" && -f "$work/outside.log" && -f "$work/logs/untouched.txt" ]]
bash "$repo/tools/prx-compress-test-logs.sh" "$work/logs"
truncate -s 102401 "$work/logs/conflict.log"
printf 'existing archive' >"$work/logs/conflict.log.gz"
if bash "$repo/tools/prx-compress-test-logs.sh" "$work/logs" 2>"$work/error"; then exit 1; fi
[[ -f "$work/logs/conflict.log" && "$(cat "$work/logs/conflict.log.gz")" == 'existing archive' ]]
printf 'PASS compression threshold, recursion, content, symlinks, repeat and archive conflict\n'
