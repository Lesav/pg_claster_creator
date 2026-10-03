#!/usr/bin/env bash
# Purpose: verify generated cluster tuning and preload configuration fragments.
# Usage: bash tools/prx-test-cluster-created-config.sh REPO
# Args: REPO -- directory containing create-claster.sh.
# Output: PASS after checking tuning defaults and pgpro_scheduler activation.
set -Eeuo pipefail

repo="$(realpath "$1")"
fixture="$(mktemp -d /tmp/pgcc-created-config.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
source "$repo/create-claster.sh"
# Sourcing the product installs its EXIT trap; restore ownership of this fixture.
trap 'rm -rf -- "$fixture"' EXIT

PG_EXT="$fixture/extensions"
cls_nm=qa_config
mkdir -p "$PG_EXT" "$fixture/without-scheduler" "$fixture/with-scheduler"
touch "$PG_EXT/pg_stat_statements.so" "$PG_EXT/pg_cron.so"

write_cluster_generated_config "$fixture/without-scheduler" scram-sha-256
cmp -s "$fixture/without-scheduler/conf.d/optimize-claster.conf" <(printf '%s\n' \
    'max_wal_size = 4GB' \
    'min_wal_size = 1GB' \
    'shared_buffers = 2GB' \
    'max_worker_processes = 16')
grep -Fxq "shared_preload_libraries = 'pg_stat_statements, pg_cron'" \
    "$fixture/without-scheduler/conf.d/lib_preloaded.conf"
grep -Fxq "cron.database_name = 'qa_config'" \
    "$fixture/without-scheduler/conf.d/lib_preloaded.conf"
! grep -q '^schedule\.auto_enabled[[:space:]]*=' \
    "$fixture/without-scheduler/conf.d/lib_preloaded.conf"
grep -Fxq "password_encryption = 'scram-sha-256'" \
    "$fixture/without-scheduler/conf.d/password_encryption.conf"

touch "$PG_EXT/pgpro_scheduler.so"
write_cluster_generated_config "$fixture/with-scheduler" md5
grep -Fxq "shared_preload_libraries = 'pg_stat_statements, pgpro_scheduler, pg_cron'" \
    "$fixture/with-scheduler/conf.d/lib_preloaded.conf"
grep -Fxq 'schedule.auto_enabled = on' \
    "$fixture/with-scheduler/conf.d/lib_preloaded.conf"
[[ "$(grep -c '^schedule\.auto_enabled[[:space:]]*=' \
    "$fixture/with-scheduler/conf.d/lib_preloaded.conf")" == 1 ]]

# Cold backups add the complete per-cluster configuration directory, so every
# generated conf.d fragment is covered without maintaining a separate file list.
declare -f make_cold_backup | grep -Fq 'paths+=("etc/postgresql/${version}/${name}")'

bash -n "$repo/create-claster.sh" "$repo/tools/prx-test-cluster-created-config.sh"
printf 'PASS: tuning defaults, scheduler activation and complete cold-config archive path\n'
