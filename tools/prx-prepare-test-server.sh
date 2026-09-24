#!/usr/bin/env bash
# Purpose: prefer the installed server; provision by product priority only if absent.
# Usage: bash tools/prx-prepare-test-server.sh REPO LOG_DIR [EXPECTED_PACKAGE]
# Requires prior destructive-test consent. Never removes packages or clusters.
# Output: selection.tsv (package, family, major, keep-server), initial registry,
# package inventory and preparation.log. Existing product/config are prerequisites.
set -Eeuo pipefail
repo="$(realpath "$1")"; logs="$2"; expected="${3:-}"
[[ ! -e "$logs" ]]; mkdir -p "$logs"
exec >"$logs/preparation.log" 2>&1
source "$repo/create-claster.sh"
dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\n' >"$logs/packages-before.tsv"
servers=()
while IFS=$'\t' read -r candidate state; do
    [[ "$state" == installed ]] || continue
    candidate="${candidate%%:*}"
    if package_to_fields "$candidate" >/dev/null; then servers+=("$candidate"); fi
done <"$logs/packages-before.tsv"
((${#servers[@]} <= 1)) || { echo 'FAIL multiple installed servers: ambiguous destructive target'; exit 2; }
keep=0
if ((${#servers[@]})); then
    chosen="${servers[0]}"
    fields="$(package_to_fields "$chosen")"
    pg_lsclusters --no-header >"$logs/clusters-before.tsv"
    # With one installed server, a matching major identifies its registered clusters.
    if awk -v v="${fields#*|}" '$1==v {found=1} END {exit !found}' "$logs/clusters-before.tsv"; then keep=1; fi
else
    if command -v pg_lsclusters >/dev/null; then
        pg_lsclusters --no-header >"$logs/clusters-before.tsv"
        [[ ! -s "$logs/clusters-before.tsv" ]] || { echo 'FAIL cluster registry without installed server'; exit 2; }
    else
        # Do not infer an empty registry from a missing common-package command.
        [[ ! -d /etc/postgresql ]] || [[ -z "$(find /etc/postgresql -name postgresql.conf -print)" ]] || exit 2
        : >"$logs/clusters-before.tsv"
    fi
    available="$(apt-cache pkgnames)"
    : >"$logs/ranked.tsv"
    while read -r candidate; do
        fields="$(package_to_fields "$candidate")" || continue
        package_available "$candidate" || continue
        printf '%s\t%s\t%s\n' "$(server_family_priority "${fields%%|*}")" "${fields#*|}" "$candidate" >>"$logs/ranked.tsv"
    done <<<"$available"
    sort -t $'\t' -k1,1n -k2,2Vr -k3,3 "$logs/ranked.tsv" >"$logs/ordered.tsv"
    IFS=$'\t' read -r priority major chosen <"$logs/ordered.tsv" || { echo 'FAIL no available server'; exit 2; }
    [[ -z "$expected" || "$expected" == "$chosen" ]] || { echo 'FAIL --package differs from highest-priority server'; exit 2; }
    printf 'PROVISION highest-priority server: %s\n' "$chosen"
    touch "$logs/provisioning-started"
    NON_INTERACTIVE=1
    ensure_postgresql_common
    install_package "$chosen"
    fields="$(package_to_fields "$chosen")"
    keep=1 # Do not immediately remove the freshly provisioned server again.
fi
[[ -z "$expected" || "$expected" == "$chosen" ]] || { echo 'FAIL --package differs from installed server'; exit 2; }
printf '%s\t%s\t%s\t%s\n' "$chosen" "${fields%%|*}" "${fields#*|}" "$keep" >"$logs/selection.tsv"
printf 'SELECTED %s; keep-server=%s\n' "$chosen" "$keep"
