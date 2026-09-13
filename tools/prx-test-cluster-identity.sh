#!/usr/bin/env bash
# Purpose: test version/name identity using explicit registry and creation doubles.
# Usage: bash tools/prx-test-cluster-identity.sh REPO NEW_LOG_DIR
# Args: REPO source tree; NEW_LOG_DIR isolated evidence, no real cluster mutations.
# Output: results.tsv and individual logs; nonzero if any expectation fails.
# Example: bash tools/prx-test-cluster-identity.sh /repo /tmp/name-pair-evidence
set -Eeuo pipefail
repo="$1"; logs="$2"; [[ ! -e "$logs" ]]; mkdir -p "$logs"
exec >"$logs/run.log" 2>&1
source "$repo/create-claster.sh"
trap - EXIT
header() { :; }; step() { :; }
pg_lsclusters() { printf '18 occupied 54999 online postgres /fixture/18/occupied /fixture/log\n'; }
print_clusters_numbered() { cluster_rows; }
select_noninteractive_install_port() { :; }
data_directory_available() { return 0; }
create_cluster() { printf 'FIXTURE CREATE REACHED: %s/%s\n' "$pg_ver" "$cls_nm"; }
systemctl() { printf 'ActiveState=inactive\nMainPID=0\n'; }
timeout() { shift; [[ "${1:-}" != 5s ]] || shift; [[ "${1:-}" != 15s ]] || shift; "$@"; }
NON_INTERACTIVE=1; pg_ver=17; cls_nm=occupied; cls_pt=54998
cls_ch=qa; cls_us=qa; cls_pw=fixture_only; DATA_BASE=/fixture/17; INSTALL_DATA_ROOT=''
SELECTED_PACKAGE=postgresql-17
bad=0
record() { local id="$1" expected="$2" rc; shift 2; rc=0; ("$@") >"$logs/$id.log" 2>&1 || rc=$?; local result=FAIL; [[ "$rc" == "$expected" ]] && result=PASS; printf '%s\t%s\trc=%s expected=%s\n' "$id" "$result" "$rc" "$expected" | tee -a "$logs/results.tsv"; [[ "$result" == PASS ]] || bad=1; }
date --iso-8601=seconds
printf 'Registry/creation/ports/data-availability/service status are doubled; no real PostgreSQL or service changes.\n'
record CC08-CROSS-MAJOR-INSTALL 0 install_menu
grep -q 'FIXTURE CREATE REACHED: 17/occupied' "$logs/CC08-CROSS-MAJOR-INSTALL.log" || bad=1
pg_ver=18
record CC08-SAME-PAIR-INSTALL 1 install_menu
! grep -q 'FIXTURE CREATE REACHED' "$logs/CC08-SAME-PAIR-INSTALL.log" || bad=1
# Conflict helper returns 1 for a free target, 0 with a diagnostic for a conflict.
record CC19-CROSS-MAJOR-RESTORE 1 restore_target_conflict 17 occupied /fixture/17/occupied
record CC25-CROSS-MAJOR-RENAME 1 restore_target_conflict 17 occupied /fixture/17/occupied rename
record CC19-SAME-PAIR-RESTORE 0 restore_target_conflict 18 occupied /fixture/18/occupied
record CC25-SAME-PAIR-RENAME 0 restore_target_conflict 18 occupied /fixture/18/occupied rename
pg_lsclusters() { return 1; }
record REGISTRY-ERROR-FAIL-CLOSED 0 restore_target_conflict 17 occupied /fixture/17/occupied
date --iso-8601=seconds
exit "$bad"
