#!/usr/bin/env bash
# Path note: If /mnt/d/Ai/pg_claster_creator or
# /mnt/d/Ai/pg_claster_creator.backup does not match your filesystem,
# adjust the paths before running. Set PGCC_TEST_REPO to the actual project
# path and PGCC_TEST_OUTPUT to the actual per-release evidence directory.
# Purpose: clean validated run-owned regression artifacts and audit baseline.
# Usage: PGCC_TEST_RUN=RUN PGCC_TEST_REPO=REPO PGCC_TEST_RELEASE=VERSION bash tools/prx-clean-wsl-regression.sh DISTRO PACKAGE MAJOR PORT
# Args: RUN is a unique run identifier; REPO and VERSION select the source/release.
#   PGCC_TEST_OUTPUT optionally selects the per-release evidence root.
# Output: per-WSL evidence; phases retain artifacts until the cleanup helper.
# Example: PGCC_TEST_RUN=run-example PGCC_TEST_RELEASE=2.5.1 bash tools/prx-clean-wsl-regression.sh Astra postgresql-16 16 60100
set -Eeuo pipefail
repo="${PGCC_TEST_REPO:-/mnt/d/Ai/pg_claster_creator}"
release="${PGCC_TEST_RELEASE:?release required}"; token="${release//./}"
[[ "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "${PGCC_TEST_RUN:-}" =~ ^run-[a-zA-Z0-9_-]+$ ]]
output="${PGCC_TEST_OUTPUT:-/mnt/d/Ai/pg_claster_creator.backup/TEST-$release}"
distro="$1"; package="$2"; v="$3"; port="$4"
[[ "$WSL_DISTRO_NAME" == "$distro" && "$port" =~ ^[0-9]{5}$ ]]
base="$output/$distro/$PGCC_TEST_RUN"
[[ -d "$base/packages" && ! -e "$base/final-cleanup.log" ]]
exec >"$base/final-cleanup.log" 2>&1
date --iso-8601=seconds
bad=0
mapfile -t rows < <(pg_lsclusters --no-header)
for row in "${rows[@]}"; do
    read -r major name cluster_port status owner data log <<<"$row"
    # A new non-test cluster would mean concurrent user work: never erase it silently.
    case "$name" in qa${token}_"$port"*|qa${token}_boot|qadel_"$port"*) ;; *) echo "REFUSE concurrent cluster: $major/$name"; exit 2 ;; esac
    timeout -k 5 180 bash "$repo/create-claster.sh" --action delete "$major" "$name" --backup-before-delete no || exit 1
done
[[ -z "$(pg_lsclusters --no-header)" ]]
if pgrep -x postgres; then echo 'FAIL postgres processes remain'; exit 1; fi
find /run/lock -maxdepth 1 -type f -name "pg-claster-backup-*qa${token}_$port*.lock" -print -delete
dpkg --audit >"$base/final-dpkg-audit.log"
[[ ! -s "$base/final-dpkg-audit.log" ]] || bad=1
dpkg-query -W -f='${binary:Package}\t${Status}\t${Version}\n' >"$base/final-packages.tsv"
for p in postgresql-common postgresql-client-common claster-creator "$package"; do
    [[ "$(dpkg-query -W -f='${Status}' "$p")" == 'install ok installed' ]] || bad=1
done
binary="$(dpkg -L "$package" | grep '/bin/postgres$' | head -n 1)"
"$binary" --version >"$base/final-server-version.log"
actual="$(grep -oE '[0-9]+\.[0-9]+' "$base/final-server-version.log" | head -n 1)"
expected="$(awk -F '\t' -v p="$package" '$1==p {print $2}' "$base/packages/server-minors.tsv")"
[[ "$actual" == "$expected" ]] || { echo "FAIL minor $expected -> $actual"; bad=1; }
boot="/var/tmp/pgcc-full-$release-$port"
core="/var/tmp/pgcc${token}-$port"
for location in shared share; do
    current="/usr/local/$location/pg_claster_creator/.new-claster.config"
    if [[ -f "$boot/config-$location" ]]; then
        if [[ -f "$core/config-$location" ]] && cmp -s "$core/config-$location" "$current"; then
            cp -a "$boot/config-$location" "$current"
            cmp "$boot/config-$location" "$current"
            echo "RESTORED pre-test $location config"
        elif cmp -s "$boot/config-$location" "$current"; then echo "UNCHANGED $location config"
        else echo "FAIL changed $location config; preserved for review"; bad=1
        fi
    fi
done
sha256sum "$repo/.new-claster.config" >"$base/final-project-config.sha"
expected_config="$(awk '$2 ~ /\/\.new-claster.config$/ {print $1; exit}' "$base/bootstrap/source.sha256")"
[[ -n "$expected_config" && "$(awk '{print $1}' "$base/final-project-config.sha")" == "$expected_config" ]] || bad=1
# Remove exact run-owned plan markers; retain only their names as evidence.
if [[ -d /var/lib/claster-creator ]]; then
    find /var/lib/claster-creator -maxdepth 1 -type f -name "*qa${token}_$port*" -print -delete
fi
for suffix in '' -extra -ports -ui -tail -extension -extension-r2; do
    target="/var/tmp/pgcc${token}-$port$suffix"
    [[ ! -L "$target" ]]
    if [[ -d "$target" ]]; then
        [[ "$(realpath "$target")" == "$target" ]]
        rm -rf -- "$target"
    fi
    target="/DATA/pgcc${token}-$port$suffix"
    if [[ -d "$target" && ! -L "$target" ]]; then
        # Never recursively erase a data root: only empty directories are removed.
        find "$target" -depth -type d -empty -delete
        [[ ! -e "$target" ]] || { echo "FAIL remaining data: $target"; bad=1; }
    fi
done
for target in "/var/tmp/pgcc-buildsrc-$port" "$boot"; do
    if [[ -d "$target" && ! -L "$target" ]]; then
        [[ "$(realpath "$target")" == "$target" ]]
        if ((bad == 0)); then rm -rf -- "$target"; else echo "RETAIN recovery work: $target"; fi
    fi
done
rename_log="$base/rename-delete/$distro/live.log"
if [[ -f "$rename_log" ]]; then
    target="$(sed -n 's/^work=//p' "$rename_log" | head -n 1)"
    if [[ "$target" == /var/tmp/pgcc-delete-live.* && -d "$target" && ! -L "$target" ]]; then
        [[ "$(realpath "$target")" == "$target" ]]
        grep -q 'PASS original registry/config preserved' "$rename_log" && rm -rf -- "$target"
    fi
fi
for target in "$base/artifacts" "$base/$distro/artifacts"; do
    if [[ -d "$target" && ! -L "$target" ]]; then
        [[ "$(realpath "$target")" == "$target" ]]
        rm -rf -- "$target"
    fi
done
find "$base" -type f \( -name '*.deb' -o -name '*.tar.gz' \) -print -delete
if [[ "$distro" == alse-1.8.6 ]]; then
    while IFS= read -r target; do
        [[ "$target" =~ ^/root/pg-wsl-remove\.[A-Za-z0-9]+$ && -d "$target" && ! -L "$target" ]] || continue
        [[ "$(realpath "$target")" == "$target" ]]
        evidence="$base/offline-removal-${target##*.}"
        mkdir -p "$evidence"
        find "$target" -maxdepth 1 -type f \( -name '*.log' -o -name '*.tsv' -o -name '*.txt' -o -name '*before' -o -name '*after' -o -name '*.sha' \) -exec cp -t "$evidence" -- {} +
        if grep -q 'PASS approved packages removed' "$target/run.log"; then rm -rf -- "$target"; else echo "RETAIN failed removal recovery $target"; bad=1; fi
    done < <(find "$base" -name remove.log -type f -exec sed -n 's/^BACKUP_DIR=//p' {} +)
fi
pg_lsclusters >"$base/final-clusters.log"
ps -eo pid,ppid,stat,comm >"$base/final-processes.log"
date --iso-8601=seconds
printf 'FINAL CLEANUP rc=%s; registry empty; minor expected=%s actual=%s\n' "$bad" "$expected" "$actual"
exit "$bad"
