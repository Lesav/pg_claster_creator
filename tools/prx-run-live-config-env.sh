#!/usr/bin/env bash
# Purpose: isolated wrapper around the existing live runner's explicit-config extension.
# Usage: bash tools/prx-run-live-config-env.sh REPO DISTRO MAJOR PACKAGE FAMILY PORT RELEASE LOG_ROOT
# Args: same target arguments as prx-test-live-regression.sh; LOG_ROOT must be new.
# Output: redacted parent evidence plus supplementary timing; deletes owned artifacts.
# Example: use the actual per-release/per-WSL run directory followed by /config-env.
# Path note: adjust the /mnt/d/Ai/pg_claster_creator.backup validation below
# if the actual evidence root is mounted elsewhere.
set -Eeuo pipefail
repo="$1"; distro="$2"; v="$3"; package="$4"; family="$5"; port="$6"; release="$7"; output="$8"
[[ "$WSL_DISTRO_NAME" == "$distro" && "$port" =~ ^60[1-8]00$ && "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ ! -e "$output" && ( "$output" == /mnt/d/Ai/pg_claster_creator.backup/TEST-"$release"/"$distro"/run-*/config-env || "$output" == /mnt/d/Ai/pg_claster_creator.backup/TEST-"$release"/"$distro"/run-*/config-env-r2 ) ]]
[[ -z "$(pg_lsclusters --no-header)" ]]
token="${release//./}"
work="/var/tmp/pgcc${token}-$port-extension"
data="/DATA/pgcc${token}-$port-extension"
[[ ! -e "$work" && ! -L "$work" && ! -e "$data" && ! -L "$data" ]]
mkdir -p "$output"
build="$(mktemp -d /var/tmp/pgcc-config-build.XXXXXX)"
start="$(date --iso-8601=seconds)"; epoch="$(date +%s)"
exec >"$output/driver.log" 2>&1
finish() {
    local rc=$? clean=0 end end_epoch target
    trap - EXIT; set +e
    if [[ -n "$(pg_lsclusters --no-header)" ]]; then
        echo 'FAIL parent left clusters; preserving recovery files'; clean=1
    else
        for target in "$work" "$build" "$output/$distro/artifacts"; do
            if [[ -d "$target" && ! -L "$target" && "$(realpath "$target")" == "$target" ]]; then rm -rf -- "$target"; fi
        done
        if [[ -d "$data" && ! -L "$data" ]]; then find "$data" -depth -type d -empty -delete; fi
        [[ ! -e "$data" ]] || clean=1
        find /var/lib/claster-creator -maxdepth 1 -type f -name "*qa${token}_${port}x*" -print -delete
        find /run/lock -maxdepth 1 -type f -name "pg-claster-backup-*qa${token}_${port}x*.lock" -print -delete
    fi
    dpkg --audit >"$output/dpkg-audit.log"; [[ ! -s "$output/dpkg-audit.log" ]] || clean=1
    pg_lsclusters >"$output/final-clusters.log"
    end="$(date --iso-8601=seconds)"; end_epoch="$(date +%s)"
    printf 'start\tend\telapsed_seconds\trunner_rc\tcleanup_rc\n%s\t%s\t%s\t%s\t%s\n' "$start" "$end" "$((end_epoch-epoch))" "$rc" "$clean" >"$output/timing.tsv"
    ((rc==0 && clean==0))
}
trap finish EXIT
cp -a "$repo/"create-claster*.sh "$repo/.new-claster.config" "$repo/man" "$build/"
find "$repo" -maxdepth 1 -type f -name '*.md' -exec cp -t "$build" -- {} +
PGCC_LIVE_WORKSPACE=1 PGCC_LIVE_BUILDER="$build/create-claster-deb.sh" PGCC_LIVE_BACKUP_ROOT="$output" PGCC_LIVE_EXTENSION="$repo/tools/prx-test-live-config-env.sh" bash "$repo/tools/prx-test-live-regression.sh" "$repo" "$distro" "$v" "$package" "$family" "$port" "$release" "$output" extension
