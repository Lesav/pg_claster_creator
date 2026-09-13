#!/usr/bin/env bash
# Path note: If /mnt/d/Ai/pg_claster_creator in the example does not match
# your filesystem, replace it with the actual project path before running.
# Purpose: test native-like rename, prefix safety, autostart and failure diagnostics.
# Usage: bash tools/prx-test-cluster-rename.sh REPO
# Args: REPO -- source directory containing create-claster.sh.
# Output: PASS assertions; no real cluster/service/package modifications.
# Example: bash tools/prx-test-cluster-rename.sh /mnt/d/Ai/pg_claster_creator
set -Eeuo pipefail
repo="$(realpath "$1")"
fixture="$(mktemp -d /tmp/pgcc-rename-test.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
source "$repo/create-claster.sh"
trap - ERR
trap 'rm -rf -- "$fixture"' EXIT
for fn in rename_cluster_checked restore_target_conflict cluster_service_file remove_cluster_service_files write_cluster_unit_file systemd_unit_dir validate_renamed_cluster_config; do
    eval "$(declare -f "$fn" | sed "s#/etc/#$fixture/etc/#g; s#/usr/lib/#$fixture/usr/lib/#g; s#\"/lib/#\"$fixture/lib/#g; s#/.postgres/#$fixture/.postgres/#g; s#/var/log/#$fixture/var/log/#g; s#/var/tmp/#$fixture/var/tmp/#g; s#/run/systemd/#$fixture/run/systemd/#g")"
done
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
timeout() { [[ "$1" != -k ]] || shift 2; shift; "$@"; }
run_parsec_aware() { "$@"; }
cluster_pg_home() { printf '%s/home\n' "$fixture"; }
pg_conftool() {
    [[ "$3" == set ]] || return 0
    put_postgresql_setting "$fixture/etc/postgresql/$1/$2/postgresql.conf" "$4" "'$5'"
}
systemctl() {
    if [[ "$1" == show ]]; then
        printf 'ActiveState=%s\nMainPID=%s\n' "${mock_state:-inactive}" "${mock_pid:-0}"
    else
        printf 'systemctl %s\n' "$*" >>"$fixture/events"
        [[ "${failure:-}" != reload ]]
    fi
}
stop_cluster_checked() {
    printf 'stop %s %s\n' "$1" "$2" >>"$fixture/events"
    [[ "${failure:-}" != stop ]] || die 'injected stop failure'
    printf down >"$fixture/state"
}
start_cluster_checked() {
    printf 'start %s %s\n' "$1" "$2" >>"$fixture/events"
    [[ "${failure:-}" != start ]] || die 'injected start failure'
    printf online >"$fixture/state"
}
setting() { sed -n "s/^$2 = '\(.*\)'$/\1/p" "$1"; }
pg_lsclusters() {
    local f
    for f in "$fixture/etc/postgresql/18/"*/postgresql.conf; do
        [[ -f "$f" ]] || continue
        printf '18 %s 5432 %s postgres %s /unused\n' "$(basename "${f%/*}")" "$(<"$fixture/state")" "$(setting "$f" data_directory)"
    done
}
runuser() {
    shift 3
    if [[ "$1" == */pg_ctl ]]; then
        [[ "${failure:-}" != status ]] || return 0
        return 3
    elif [[ "$1" == */postgres ]]; then
        [[ "${failure:-}" != config ]] || return 1
        setting "${5#config_file=}" "$7"
    else
        "$@"
    fi
}
pg_renamecluster() {
    printf 'rename %s %s %s\n' "$1" "$2" "$3" >>"$fixture/events"
    [[ "${PG_CLUSTER_CONF_ROOT:-}" == "$fixture/etc/postgresql" ]] || return 1
    [[ "${failure:-}" != native ]] || return 1
    # Native pg_renamecluster updates paths before returning, unlike the old mock.
    local f
    for f in "$fixture/etc/postgresql/$1/$2/"*.conf; do
        OLD="$2" NEW="$3" perl -pi -e 's/\b\Q$ENV{OLD}\E\b/$ENV{NEW}/g' "$f"
    done
    mv -- "$fixture/etc/postgresql/$1/$2" "$fixture/etc/postgresql/$1/$3"
    mv -- "$fixture/data/$2" "$fixture/data/$3"
}
mkdir -p "$fixture/etc/postgresql/18/old/conf.d" "$fixture/data/old" "$fixture/var/tmp" "$fixture/usr/lib/systemd/system" "$fixture/home/bin"
touch "$fixture/home/bin/pg_ctl" "$fixture/home/bin/postgres"
chmod +x "$fixture/home/bin/"*
printf "data_directory = '%s/data/old'\nhba_file = '%s/etc/postgresql/18/old/pg_hba.conf'\nident_file = '%s/etc/postgresql/18/old/pg_ident.conf'\n" "$fixture" "$fixture" "$fixture" >"$fixture/etc/postgresql/18/old/postgresql.conf"
touch "$fixture/etc/postgresql/18/old/pg_hba.conf" "$fixture/etc/postgresql/18/old/pg_ident.conf"
ln -s "$fixture/var/log/postgresql/postgresql-18-old.log" "$fixture/etc/postgresql/18/old/log"
printf "cluster_name = '18/old'\n" >"$fixture/data/old/postgresql.auto.conf"
printf '18\n' >"$fixture/data/old/PG_VERSION"
printf online >"$fixture/state"
printf 'ExecStart=/usr/bin/pg_ctlcluster 18-old start\n' >"$fixture/usr/lib/systemd/system/postgresql@18-old.service"
for target in etc/systemd/system/multi-user.target.wants run/systemd/system/custom.target.requires; do
    mkdir -p "$fixture/$target"
    ln -s "$fixture/usr/lib/systemd/system/postgresql@18-old.service" "$fixture/$target/postgresql@18-old.service"
done
! (rename_cluster_checked 18 old '../bad' "$fixture/data/old" online)
! (rename_cluster_checked 18 old old "$fixture/data/old" online)
[[ ! -e "$fixture/events" ]]
printf 'STALE TARGET UNIT\n' >"$fixture/usr/lib/systemd/system/postgresql@18-old_new.service"
mock_state=active; mock_pid=999
! (rename_cluster_checked 18 old old_new "$fixture/data/old" online)
[[ ! -e "$fixture/events" ]]
mock_state=inactive; mock_pid=0
rename_cluster_checked 18 old old_new "$fixture/data/old" down
[[ -z "${PG_CLUSTER_CONF_ROOT:-}" ]]
grep -rq 'STALE TARGET UNIT' "$fixture/var/tmp"
[[ "$(setting "$fixture/etc/postgresql/18/old_new/postgresql.conf" data_directory)" == "$fixture/data/old_new" ]]
[[ "$(setting "$fixture/etc/postgresql/18/old_new/postgresql.conf" hba_file)" == "$fixture/etc/postgresql/18/old_new/pg_hba.conf" ]]
[[ "$(cluster_power_state 18 old_new)" == online ]]
[[ "$(readlink "$fixture/etc/postgresql/18/old_new/log")" == "$fixture/var/log/postgresql/postgresql-18-old_new.log" ]]
[[ "$(grep -E '^(stop|rename|start) ' "$fixture/events")" == $'stop 18 old\nrename 18 old old_new\nstart 18 old_new' ]]
[[ "$(grep -c '^systemctl daemon-reload$' "$fixture/events")" == 1 ]]
! grep -Eq '^systemctl (enable|disable)' "$fixture/events"
for target in etc/systemd/system/multi-user.target.wants run/systemd/system/custom.target.requires; do
    [[ ! -L "$fixture/$target/postgresql@18-old.service" && -e "$fixture/$target/postgresql@18-old_new.service" ]]
done
file="$fixture/etc/postgresql/18/old_new/postgresql.conf"
before="$(sha256sum "$file")"
rewrite_renamed_cluster_file "$file" "$fixture/etc/postgresql/18/old" "$fixture/etc/postgresql/18/old_new" "$fixture/data/old" "$fixture/data/old_new" 18-old 18-old_new
[[ "$before" == "$(sha256sum "$file")" ]]
printf down >"$fixture/state"
: >"$fixture/events"
rename_cluster_checked 18 old_new old "$fixture/data/old_new" online
[[ "$(cluster_power_state 18 old)" == down ]]
! grep -q '^start ' "$fixture/events"
for failure in stop status native config reload start; do
    case_fixture="$fixture/case-$failure"
    mkdir "$case_fixture"
    cp -a "$fixture/etc" "$fixture/data" "$fixture/usr" "$fixture/home" "$fixture/var" "$fixture/run" "$fixture/.postgres" "$case_fixture/"
    printf online >"$fixture/state"; : >"$fixture/events"
    set +e
    (set -e; rename_cluster_checked 18 old next "$fixture/data/old" online) >"$case_fixture/output" 2>&1
    rc=$?
    set -e
    [[ "$rc" != 0 ]]
    grep -q 'этап=' "$case_fixture/output"
    [[ "$failure" == start ]] || ! grep -q '^start ' "$fixture/events"
    [[ "$failure" != status && "$failure" != stop ]] || ! grep -q '^rename ' "$fixture/events"
    for part in etc data usr home var run .postgres; do rm -rf -- "$fixture/$part"; mv "$case_fixture/$part" "$fixture/$part"; done
done
unset failure
bash -n "$repo/create-claster.sh"
printf 'PASS: native-like prefix/reverse rename, idempotency, online/down, autostart, bounded reload and six safe-failure paths\n'
