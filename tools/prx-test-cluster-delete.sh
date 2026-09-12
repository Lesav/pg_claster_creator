#!/usr/bin/env bash
# Purpose: exercise direct deletion and refusal boundaries with isolated files/services.
# Usage: bash tools/prx-test-cluster-delete.sh REPO
# Args: REPO -- project source directory containing create-claster.sh.
# Output: PASS; never invokes real pg_dropcluster, syslog, services or databases.
# Example: bash tools/prx-test-cluster-delete.sh /mnt/d/Ai/pg_claster_creator
set -Eeuo pipefail
repo="$(realpath "$1")"
fixture="$(mktemp -d /tmp/pgcc-delete.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
source "$repo/create-claster.sh"
for fn in validate_cluster_delete_paths delete_cluster_checked remove_cluster_service_files; do
    eval "$(declare -f "$fn" | sed "s#/etc/#$fixture/etc/#g; s#/usr/lib/#$fixture/usr/lib/#g; s#\"/lib/#\"$fixture/lib/#g; s#/.postgres/#$fixture/.postgres/#g; s#/var/log/#$fixture/var/log/#g")"
done
die() { printf 'EXPECTED/ERROR: %s\n' "$*" >&2; exit 1; }
run_parsec_aware() { "$@"; }
timeout() { [[ "$1" == -k ]] && shift 2; shift; "$@"; }
runuser() { printf 'status\n' >>"$fixture/events"; return "${status_rc:-3}"; }
stop_cluster_checked() { printf 'stop\n' >>"$fixture/events"; [[ "${stop_rc:-0}" == 0 ]] || die 'stop failed'; }
systemctl() {
    printf 'systemctl %s\n' "$*" >>"$fixture/events"
    case "$1" in
        show) printf 'ActiveState=%s\nMainPID=%s\n' "${unit_state:-inactive}" "${unit_pid:-0}" ;;
        disable) return "${disable_rc:-0}" ;;
    esac
}
findmnt() { printf '%s\n' "${test_mount:-/}"; }
pg_lsclusters() {
    [[ "${registry_rc:-0}" == 0 ]] || return 1
    printf '18 chosen 58000 down postgres %s %s\n' "$data" "$log"
    printf '16 neighbour 58001 online postgres %s %s\n' "${mock_other_data:-$fixture/data/neighbour}" "${mock_other_log:-/unused}"
}
pg_dropcluster() { die 'pg_dropcluster must not be called'; }
data="$fixture/data/chosen"; conf="$fixture/etc/postgresql/18/chosen"
service=postgresql@18-chosen.service
log="$fixture/var/log/postgresql/tantor-be-18-chosen.log"
home="$fixture/server"
mkdir -p "$data" "$conf/conf.d" "$fixture/data/neighbour" "$home/bin" "${log%/*}" "$fixture/usr/lib/systemd/system" "$fixture/etc/syslog-ng/conf.d" "$fixture/external"
touch "$home/bin/pg_ctl"; chmod +x "$home/bin/pg_ctl"
printf '18\n' >"$data/PG_VERSION"
printf keep >"$fixture/data/neighbour/keep"
printf keep >"$fixture/external/keep"
printf config >"$conf/postgresql.conf"
printf service >"$fixture/usr/lib/systemd/system/$service"
printf syslog >"$fixture/etc/syslog-ng/conf.d/mod-astra-postgres-18-chosen.conf"
printf selected >"$log"; printf keep >"${log%/*}/neighbour.log"
ln -s "$fixture/external" "$data/pg_wal"
attempt() { delete_cluster_checked 18 chosen postgres "$data" "$log" "$home"; }
for rejection in stop status unknown timeout active pid registry shared parent mount; do
    (
        case "$rejection" in
            stop) stop_rc=1 ;; status) status_rc=0 ;; unknown) status_rc=1 ;; timeout) status_rc=124 ;;
            active) unit_state=active ;; pid) unit_pid=123 ;; disable) disable_rc=1 ;; registry) registry_rc=1 ;;
            shared) mock_other_data="$data" ;; parent) mock_other_data="${data%/*}" ;; mount) test_mount="$data/bound" ;;
        esac
        if (attempt) >"$fixture/$rejection.log" 2>&1; then echo "FAIL refusal $rejection"; exit 1; fi
        [[ -f "$data/PG_VERSION" && -f "$conf/postgresql.conf" && -f "$fixture/usr/lib/systemd/system/$service" && -f "$log" ]]
    )
    printf 'PASS refusal: %s preserves data/config/unit/log\n' "$rejection"
done
attempt
[[ ! -e "$data" && ! -e "$conf" && ! -e "$fixture/usr/lib/systemd/system/$service" && ! -e "$log" ]]
[[ ! -e "$fixture/etc/syslog-ng/conf.d/mod-astra-postgres-18-chosen.conf" ]]
[[ "$(cat "$fixture/data/neighbour/keep")" == keep && "$(cat "$fixture/external/keep")" == keep && "$(cat "${log%/*}/neighbour.log")" == keep ]]
printf 'PASS direct deletion, neighbour/external WAL preservation, no pg_dropcluster/syslog reload\n'
# Exact final symlinks are unlinked, never recursively followed.
ln -s "$fixture/external" "$data"
remove_cluster_directory_exact "$data" chosen data
[[ ! -L "$data" && -f "$fixture/external/keep" ]]
printf 'PASS symlink target preserved\n'
mkdir -p "$data" "$conf"
printf '18\n' >"$data/PG_VERSION"
printf shared >"$log"
mock_other_log="$log"
attempt
[[ ! -e "$data" && ! -e "$conf" && "$(cat "$log")" == shared ]]
printf 'PASS shared log preserved\n'
