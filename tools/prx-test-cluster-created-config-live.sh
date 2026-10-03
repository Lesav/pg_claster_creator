#!/usr/bin/env bash
# Purpose: create one disposable cluster and verify generated config plus cold backup.
# Usage: sudo bash tools/prx-test-cluster-created-config-live.sh REPO [PACKAGE]
# Args: REPO -- project directory; PACKAGE -- installed server package.
# Output: PASS with the validated cold-backup path; removes all created test data.
set -Eeuo pipefail

repo="$(realpath "$1")"
package="${2:-postgrespro-ent-16-server}"
creator="$repo/create-claster.sh"
name="test_opt_$((1 + RANDOM % 9))_$$"
data_root="$(mktemp -d /tmp/pgcc-opt-data.XXXXXX)"
backup_dir="$(mktemp -d /tmp/pgcc-opt-backup.XXXXXX)"
port=""

cleanup() {
    local path
    if pg_lsclusters --no-header 2>/dev/null | awk -v n="$name" \
        '$1 == 16 && $2 == n { found=1 } END { exit !found }'; then
        "$creator" --action delete --package "$package" \
            --pg-version 16 --cluster-name "$name" --backup-before-delete no || true
    fi
    systemctl disable "postgresql@16-$name.service" >/dev/null 2>&1 || true
    rm -rf -- "/etc/postgresql/16/$name"
    rm -f -- \
        "/lib/systemd/system/postgresql@16-$name.service" \
        "/usr/lib/systemd/system/postgresql@16-$name.service" \
        "/etc/systemd/system/multi-user.target.wants/postgresql@16-$name.service" \
        "/.postgres/systemd/postgresql@16-$name.service" \
        "/.postgres/systemd/save/postgresql@16-$name.service"
    systemctl daemon-reload >/dev/null 2>&1 || true
    for path in "$data_root" "$backup_dir"; do
        case "$path" in
            /tmp/pgcc-opt-data.*|/tmp/pgcc-opt-backup.*) rm -rf -- "$path" ;;
        esac
    done
}
trap cleanup EXIT
chmod 0755 "$data_root"

while IFS= read -r candidate; do
    if ! ss -H -ltn | awk '{ print $4 }' | grep -Eq "(^|:)${candidate}$"; then
        port="$candidate"
        break
    fi
done < <(shuf -i 20000-59999 -n 50)
[[ -n "$port" ]]

printf 'TEST_CLUSTER=%s TEST_PORT=%s DATA_ROOT=%s BACKUP_DIR=%s\n' \
    "$name" "$port" "$data_root" "$backup_dir"
"$creator" --action install --package "$package" \
    --pg-version 16 --cluster-name "$name" --port "$port" --schema "$name" \
    --user "${name}_user" --password test_password --data-root "$data_root"

conf="/etc/postgresql/16/$name/conf.d"
cmp -s "$conf/optimize-claster.conf" <(printf '%s\n' \
    'max_wal_size = 4GB' \
    'min_wal_size = 1GB' \
    'shared_buffers = 2GB' \
    'max_worker_processes = 16')
grep -Eq "^shared_preload_libraries = '([^']*, )?pgpro_scheduler(, [^']*)?'$" \
    "$conf/lib_preloaded.conf"
grep -Fxq 'schedule.auto_enabled = on' "$conf/lib_preloaded.conf"

pg_home=/opt/pgpro/ent-16
runuser -u postgres -- "$pg_home/bin/psql" -h /tmp -p "$port" -d postgres \
    -XAtv ON_ERROR_STOP=1 \
    -c 'SHOW max_wal_size' \
    -c 'SHOW min_wal_size' \
    -c 'SHOW shared_buffers' \
    -c 'SHOW max_worker_processes' \
    -c 'SHOW schedule.auto_enabled'

"$creator" --action backup --pg-version 16 \
    --cluster-name "$name" --backup-type cold --clear-wal no \
    --backup-dir "$backup_dir"
archive="$(find "$backup_dir" -maxdepth 1 -type f \
    -name "16-$name-*.tar.gz" -print -quit)"
[[ -n "$archive" ]]
tar -tzf "$archive" | grep -Fx \
    "root/etc/postgresql/16/$name/conf.d/optimize-claster.conf" >/dev/null
tar -tzf "$archive" | grep -Fx \
    "root/etc/postgresql/16/$name/conf.d/lib_preloaded.conf" >/dev/null
tar -xOzf "$archive" \
    "root/etc/postgresql/16/$name/conf.d/optimize-claster.conf" | \
    cmp - "$conf/optimize-claster.conf"

printf 'PASS: live cluster tuning, pgpro_scheduler startup and cold config archive\n'
