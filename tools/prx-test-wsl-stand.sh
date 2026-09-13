#!/usr/bin/env bash
# Purpose: per-WSL run, with unconditional cleanup and timing.
# Usage: PGCC_TEST_RELEASE=VERSION PGCC_TEST_RUN=RUN bash tools/prx-test-wsl-stand.sh DISTRO PACKAGE MAJOR FAMILY PORT [prepared]
#   prepared resumes after a verified bootstrap recovery, keeping the initial stand.log.
# Args: exact WSL name, original server package, major, family and unique QA base port (60100..60800).
# Example: PGCC_TEST_RELEASE=2.5.2 PGCC_TEST_RUN=qa-run bash tools/prx-test-wsl-stand.sh mint22-3 postgresql-16 16 postgresql 60800
# Path note: adjust /mnt/d/Ai/pg_claster_creator and its .backup sibling if different.
# Output: distinct run evidence; no changes to product source or published DEB.
set -Eeuo pipefail
repo="${PGCC_TEST_REPO:-/mnt/d/Ai/pg_claster_creator}"
release="${PGCC_TEST_RELEASE:?release required}"; token="${release//./}"
export PGCC_TEST_RUN="${PGCC_TEST_RUN:?run required}" PGCC_TEST_RELEASE="$release"
export PGCC_TEST_REPO="$repo"
distro="$1"; package="$2"; v="$3"; family="$4"; port="$5"
[[ "$distro" == "$WSL_DISTRO_NAME" && "$port" =~ ^60[1-8]00$ ]]
base="/mnt/d/Ai/pg_claster_creator.backup/TEST-${release}/$distro/$PGCC_TEST_RUN"
prepared="${6:-}"; [[ -z "$prepared" || "$prepared" == prepared ]]
log="$base/stand${prepared:+-prepared}.log"
[[ -d "$base/packages" && ! -e "$log" ]]
exec >"$log" 2>&1
started="$(date --iso-8601=seconds)"; started_epoch="$(date +%s)"
printf 'START %s\n' "$started"
bad=0
finish() {
    local rc=$? clean=0 end end_epoch
    trap - EXIT; set +e
    bash "$repo/tools/prx-clean-wsl-regression.sh" "$distro" "$package" "$v" "$port" || clean=$?
    end="$(date --iso-8601=seconds)"; end_epoch="$(date +%s)"
    printf 'start\tend\telapsed_seconds\trunner_rc\tchecks_failed\tcleanup_rc\n%s\t%s\t%s\t%s\t%s\t%s\n' "$started" "$end" "$((end_epoch-started_epoch))" "$rc" "$bad" "$clean" >"$base/timing.tsv"
    printf 'END %s runner=%s bad=%s cleanup=%s\n' "$end" "$rc" "$bad" "$clean"
    ((rc==0 && bad==0 && clean==0))
}
trap finish EXIT
[[ -z "$(pg_lsclusters --no-header)" ]]
grep -q 'READ-ONLY minor gate rc=0' "$base/packages/run.log"
[[ "$distro" != alse-1.8.6 ]] || export PGCC_OFFLINE_REMOVE=1
bash "$repo/tools/prx-run-wsl-phases.sh" "$distro" "$package" "$v" "$family" "$port" "$prepared" || bad=1
[[ -z "$(pg_lsclusters --no-header)" ]] || exit 1
bash "$repo/tools/prx-test-live-install.sh" "$distro" "$v" "$port" || bad=1
[[ -z "$(pg_lsclusters --no-header)" ]] || exit 1
default_root="/var/lib/postgresql/$v"
[[ "$family" != tantor-* ]] || default_root="/var/lib/postgresql/$family-$v"
PGCC_TEST_RENAME=yes PGCC_DELETE_LOG_ROOT="$base/rename-delete" bash "$repo/tools/prx-test-cluster-delete-live.sh" "$repo" "$distro" "$v" "$port" "$default_root" || bad=1
bash "$repo/tools/prx-test-cluster-identity.sh" "$repo" "$base/name-pair" || bad=1
if [[ -f "$base/phases.tsv" ]]; then awk -F '\t' '$2!=0 {bad=1} END {exit bad}' "$base/phases.tsv" || bad=1; else bad=1; fi
exit "$bad"
