#!/usr/bin/env bash
# Purpose: read-only baseline and repository minor-version gate before package tests.
# Usage: bash tools/prx-check-server-minor.sh LOG_DIR
# Args: LOG_DIR -- new evidence directory on the requested per-WSL test path.
# Output: installed packages, server versions, repository versions and gate results.
# Example: bash tools/prx-check-server-minor.sh /mnt/d/test/Astra/packages
set -Eeuo pipefail
logs="$1"; [[ ! -e "$logs" ]]; mkdir -p "$logs"
exec >"$logs/run.log" 2>&1
date --iso-8601=seconds
pg_lsclusters >"$logs/clusters-before.log"
LC_ALL=ru_RU.UTF-8 apt list >"$logs/apt-list.log" 2>"$logs/apt-stderr.log"
grep -E '(postg|tantor)' "$logs/apt-list.log" | grep установлен >"$logs/installed-selection.log" || true
awk -F/ '{print $1}' "$logs/installed-selection.log" >"$logs/removal-candidates.txt"
[[ -s "$logs/removal-candidates.txt" ]] || { echo 'FAIL empty package list'; exit 1; }
bad=0
while IFS= read -r package; do
    [[ "$package" =~ ^[a-z0-9][a-z0-9.+:-]*$ ]] || exit 2
    binary="$(dpkg -L "$package" | grep '/bin/postgres$' | head -n 1 || true)"
    [[ -n "$binary" ]] || continue
    "$binary" --version >"$logs/$package-server-version.log"
    version="$(grep -oE '[0-9]+\.[0-9]+' "$logs/$package-server-version.log" | head -n 1)"
    apt-cache policy "$package" >"$logs/$package-policy.log"
    apt-cache madison "$package" >"$logs/$package-available.log"
    available=no
    while IFS='|' read -r _ candidate _; do
        candidate="${candidate//[[:space:]]/}"; candidate="${candidate#*:}"
        case "$candidate" in "$version"|"$version".*|"$version"-*|"$version"+*|"$version"~*) available=yes ;; esac
    done <"$logs/$package-available.log"
    printf '%s\t%s\t%s\n' "$package" "$version" "$available" >>"$logs/server-minors.tsv"
    [[ "$available" == yes ]] || bad=1
done <"$logs/removal-candidates.txt"
[[ -s "$logs/server-minors.tsv" ]] || bad=1
dpkg-query -W -f='${binary:Package}\t${Status}\t${Version}\n' postgresql-common postgresql-client-common claster-creator >"$logs/baseline-packages.log"
mapfile -t removal_candidates <"$logs/removal-candidates.txt"
LC_ALL=C apt-get -s remove -- "${removal_candidates[@]}" >"$logs/removal-plan.log" 2>&1 || bad=1
dpkg --audit >"$logs/dpkg-audit.log"
pg_lsclusters >"$logs/clusters-after.log"
cmp "$logs/clusters-before.log" "$logs/clusters-after.log"
cat "$logs/server-minors.tsv"
printf 'READ-ONLY minor gate rc=%s; no packages/clusters changed\n' "$bad"
date --iso-8601=seconds
exit "$bad"
