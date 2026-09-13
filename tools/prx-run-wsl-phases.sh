#!/usr/bin/env bash
# Path note: If /mnt/d/Ai/pg_claster_creator or
# /mnt/d/Ai/pg_claster_creator.backup does not match your filesystem,
# adjust the paths before running. Set PGCC_TEST_REPO to the actual project
# path and PGCC_TEST_OUTPUT to the actual per-release evidence directory.
# Purpose: run sequential live regression phases.
# Usage: PGCC_TEST_RUN=RUN PGCC_TEST_REPO=REPO PGCC_TEST_RELEASE=VERSION bash tools/prx-run-wsl-phases.sh DISTRO PACKAGE MAJOR FAMILY PORT [prepared]
# Args: RUN is a unique run identifier; REPO and VERSION select the source/release.
#   PGCC_TEST_OUTPUT optionally selects the per-release evidence root.
# Output: per-WSL evidence; phases retain artifacts until the cleanup helper.
# Example: PGCC_TEST_RUN=run-example PGCC_TEST_RELEASE=2.5.1 bash tools/prx-run-wsl-phases.sh Astra postgresql-16 16 postgresql 60100
set -Eeuo pipefail
repo="${PGCC_TEST_REPO:-/mnt/d/Ai/pg_claster_creator}"
release="${PGCC_TEST_RELEASE:?release required}"; token="${release//./}"
[[ "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "${PGCC_TEST_RUN:-}" =~ ^run-[a-zA-Z0-9_-]+$ ]]
output="${PGCC_TEST_OUTPUT:-/mnt/d/Ai/pg_claster_creator.backup/TEST-$release}"
distro="$1"; package="$2"; v="$3"; family="$4"; port="$5"
[[ "$WSL_DISTRO_NAME" == "$distro" && "$port" =~ ^[0-9]{5}$ ]]
base="$output/$distro/$PGCC_TEST_RUN"
[[ -d "$base/packages" && ! -e "$base/phases.tsv" ]]
step() {
    local name="$1" rc; shift
    printf 'START %s %s\n' "$name" "$(date --iso-8601=seconds)"
    set +e; "$@" >"$base/$name-driver.log" 2>&1; rc=$?; set -e
    printf '%s\t%s\t%s\n' "$name" "$rc" "$(date --iso-8601=seconds)" | tee -a "$base/phases.tsv"
    return "$rc"
}
if [[ "${6:-}" != prepared ]]; then
    step bootstrap bash "$repo/tmp/full-${release}-packages.sh" "$distro" "$package" "$v" "$family" "$port" || exit 1
fi
buildsrc="/var/tmp/pgcc-buildsrc-$port"
[[ ! -e "$buildsrc" ]]; mkdir -m 0755 "$buildsrc"
cp -a "$repo/"create-claster*.sh "$repo/.new-claster.config" "$repo/man" "$buildsrc/"
find "$repo" -maxdepth 1 -type f -name '*.md' -exec cp -t "$buildsrc" -- {} +
export PGCC_LIVE_WORKSPACE=1 PGCC_PREFLIGHT_WORKSPACE=1
export PGCC_LIVE_BUILDER="$buildsrc/create-claster-deb.sh" PGCC_LIVE_BACKUP_ROOT="$base"
step preflight bash "$repo/tools/prx-test-wsl-preflight.sh" "$repo" "$base/preflight" "$release" || true
step fixtures bash "$repo/tmp/full-${release}-fixtures.sh" "$distro" || true
live() { bash "$repo/tools/prx-test-live-regression.sh" "$repo" "$distro" "$v" "$package" "$family" "$port" "$release" "$base" "$1"; }
if step core live core; then
    for phase in extra ports ui; do
        step "$phase" live "$phase" || true
        [[ -z "$(pg_lsclusters --no-header)" ]] || { echo 'STOP: phase left registered clusters'; exit 1; }
    done
    export PGCC_LIVE_EXTENSION="$repo/tools/prx-test-live-edges.sh"
    step edges live extension || true
    [[ -z "$(pg_lsclusters --no-header)" ]] || exit 1
    export PGCC_LIVE_EXTENSION="$repo/tmp/full-${release}-sql-module.sh"
    step sql live extension-r2 || true
    if [[ -z "$(pg_lsclusters --no-header)" ]]; then
        step dependencies bash "$repo/tmp/full-${release}-dependencies.sh" "$distro" "$package" "$v" "$family" "$port" || true
    fi
fi
printf 'PHASES FINISHED; final audit still required\n'
