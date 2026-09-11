#!/usr/bin/env bash
# Purpose: exercise rename orchestration with filesystem fixtures and fake services.
# Usage: bash tools/prx-test-cluster-rename.sh REPO
# Args: REPO -- source directory containing create-claster.sh.
# Output: PASS assertions; no real cluster, service, package or cron modifications.
# Example: bash tools/prx-test-cluster-rename.sh /mnt/d/Ai/pg_claster_creator
set -Eeuo pipefail
repo="$(realpath "$1")"
fixture="$(mktemp -d /tmp/pgcc-rename-test.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
source "$repo/create-claster.sh"
for fn in rename_cluster_checked restore_target_conflict cluster_service_file remove_cluster_service_files write_cluster_unit_file systemd_unit_dir; do
    eval "$(declare -f "$fn" | sed "s#/etc/#$fixture/etc/#g; s#/usr/lib/#$fixture/usr/lib/#g; s#\"/lib/#\"$fixture/lib/#g; s#/.postgres/#$fixture/.postgres/#g; s#/var/log/#$fixture/var/log/#g; s#/var/tmp/#$fixture/var/tmp/#g")"
done
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
pg_conftool() { return 0; }
systemctl() { printf 'systemctl %s\n' "$*" >>"$fixture/events"; return 0; }
run_parsec_aware() { "$@"; }
stop_cluster_checked() { printf 'stop %s %s\n' "$1" "$2" >>"$fixture/events"; }
start_cluster_checked() { printf 'start %s %s\n' "$1" "$2" >>"$fixture/events"; }
registered=old
pg_lsclusters() { printf '18 %s 5432 down postgres %s/data/%s /unused\n' "$registered" "$fixture" "$registered"; }
pg_renamecluster() {
    printf 'rename %s %s %s\n' "$1" "$2" "$3" >>"$fixture/events"
    mv -- "$fixture/etc/postgresql/$1/$2" "$fixture/etc/postgresql/$1/$3"
    mv -- "$fixture/data/$2" "$fixture/data/$3"
    registered="$3"
}
mkdir -p "$fixture/etc/postgresql/18/old/conf.d" "$fixture/data/old" "$fixture/var/tmp" "$fixture/usr/lib/systemd/system"
printf "data_directory = '%s/data/old'\n" "$fixture" >"$fixture/etc/postgresql/18/old/postgresql.conf"
printf "cluster_name = '18/old'\n" >"$fixture/data/old/postgresql.auto.conf"
printf '18\n' >"$fixture/data/old/PG_VERSION"
printf 'ExecStart=/usr/bin/pg_ctlcluster 18-old start\n' >"$fixture/usr/lib/systemd/system/postgresql@18-old.service"
# Invalid and globally duplicate names must fail before any stop/mutation.
! (rename_cluster_checked 18 old '../bad' "$fixture/data/old" online)
! (rename_cluster_checked 18 old old "$fixture/data/old" online)
[[ ! -e "$fixture/events" ]]
rename_cluster_checked 18 old renamed "$fixture/data/old" online
[[ -d "$fixture/data/renamed" && ! -e "$fixture/data/old" ]]
[[ -d "$fixture/etc/postgresql/18/renamed" ]]
[[ -f "$fixture/usr/lib/systemd/system/postgresql@18-renamed.service" ]]
[[ ! -e "$fixture/usr/lib/systemd/system/postgresql@18-old.service" ]]
grep -q '18-renamed start' "$fixture/usr/lib/systemd/system/postgresql@18-renamed.service"
grep -q '18/renamed' "$fixture/data/renamed/postgresql.auto.conf"
grep -q '/data/renamed' "$fixture/etc/postgresql/18/renamed/postgresql.conf"
[[ -L "$fixture/.postgres/systemd/postgresql@18-renamed.service" ]]
[[ "$(grep -E '^(stop|rename|start) ' "$fixture/events")" == $'stop 18 old\nrename 18 old renamed\nstart 18 renamed' ]]
printf '' >"$fixture/events"
rename_cluster_checked 18 renamed offline "$fixture/data/renamed" down
! grep -Eq '^(stop|start) ' "$fixture/events"
bash -n "$repo/create-claster.sh"
printf 'PASS: validation, online/down state, data/config/unit paths and operation order\n'
