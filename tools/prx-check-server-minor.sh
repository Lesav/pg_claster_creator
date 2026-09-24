#!/usr/bin/env bash
# Purpose: read-only baseline and repository minor-version gate before package tests.
# Environment: PGCC_TEST_KEEP_SERVER=1 skips repository/removal gates (no reinstall).
# Usage: bash tools/prx-check-server-minor.sh LOG_DIR
# Args: LOG_DIR -- new evidence directory on the requested per-WSL test path.
# Output: installed packages, gzip-compressed APT listing, server/repository versions and gate results.
# Example: bash tools/prx-check-server-minor.sh /mnt/d/test/Astra/packages
set -Eeuo pipefail
logs="$1"; [[ ! -e "$logs" ]]; mkdir -p "$logs"
exec >"$logs/run.log" 2>&1
date --iso-8601=seconds
pg_lsclusters >"$logs/clusters-before.log"
# Stream the listing into gzip; pipefail preserves APT and compression failures.
LC_ALL=ru_RU.UTF-8 apt list 2>"$logs/apt-stderr.log" | gzip -c >"$logs/apt-list.log.gz"
# Use machine-readable state: local Linux may not have the Russian APT locale.
dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\n' >"$logs/package-state.tsv"
awk -F '\t' '$2=="installed" && $1 ~ /(postg|tantor)/ {print $1}' \
    "$logs/package-state.tsv" >"$logs/removal-candidates.txt"
cp "$logs/removal-candidates.txt" "$logs/installed-selection.log"
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
    [[ "$available" == yes || "${PGCC_TEST_KEEP_SERVER:-0}" == 1 ]] || bad=1
done <"$logs/removal-candidates.txt"
[[ -s "$logs/server-minors.tsv" ]] || bad=1
for baseline_package in postgresql-common postgresql-client-common claster-creator; do
    if ! dpkg-query -W -f='${binary:Package}\t${Status}\t${Version}\n' "$baseline_package" 2>>"$logs/baseline-query.log"; then
        printf '%s\tnot installed\t-\n' "$baseline_package"
    fi
done >"$logs/baseline-packages.log"
mapfile -t removal_candidates <"$logs/removal-candidates.txt"
if [[ "${PGCC_TEST_KEEP_SERVER:-0}" == 1 ]]; then
    printf 'SKIP server package removal/reinstallation\n' >"$logs/removal-plan.log"
else
    LC_ALL=C apt-get -s remove -- "${removal_candidates[@]}" >"$logs/removal-plan.log" 2>&1 || bad=1
fi
dpkg --audit >"$logs/dpkg-audit.log"
pg_lsclusters >"$logs/clusters-after.log"
cmp "$logs/clusters-before.log" "$logs/clusters-after.log"
cat "$logs/server-minors.tsv"
printf 'READ-ONLY minor gate rc=%s; no packages/clusters changed\n' "$bad"
date --iso-8601=seconds
exit "$bad"
