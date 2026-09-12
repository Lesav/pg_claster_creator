#!/usr/bin/env bash
# Purpose: create and delete two disposable empty clusters using the real deletion path.
# Usage: bash tools/prx-test-cluster-delete-live.sh REPO DISTRO VERSION PORT DEFAULT_DATA_ROOT [RESUME_WORK]
# Args: VERSION/PORT/DEFAULT_DATA_ROOT identify a disposable empty fixture; RESUME_WORK optional.
# Set PGCC_DELETE_LOG_ROOT to a fresh output directory for a subsequent run.
# Set PGCC_TEST_RENAME=yes to check prefix/reverse rename before each deletion.
# Rename variant also checks SQL, state, effective paths and autostart links;
# the down fixture uses a fixed custom data path which rename must preserve.
# Output: per-WSL logs; no installed scripts/config changes; preserves pre-existing clusters.
# Example: PGCC_DELETE_LOG_ROOT=/repo/tmp/delete bash tools/prx-test-cluster-delete-live.sh /repo Astra 18 58210 /var/lib/postgresql/tantor-be-18
set -Eeuo pipefail
repo="$1"; distro="$2"; v="$3"; port="$4"; default_root="$5"
resume="${6:-}"
work="${resume:-$(mktemp -d /var/tmp/pgcc-delete-live.XXXXXX)}"
logs="${PGCC_DELETE_LOG_ROOT:-$repo/tmp/delete-regression-20260912}/$distro"
[[ ! -e "$logs" || -n "$resume" ]]
mkdir -p "$logs"
exec >>"$logs/live.log" 2>&1
source "$repo/create-claster.sh"
if [[ -z "$resume" ]]; then
    pg_lsclusters --no-header >"$work/before"
    sha256sum /usr/local/shared/pg_claster_creator/.new-claster.config >"$work/config.sha"
fi
cp "$work/before" "$logs/before.log"
date --iso-8601=seconds
sha256sum "$repo/create-claster.sh"
printf 'work=%s\n' "$work"
for scenario in online down; do
    name="qadel_${port}_${scenario}"
    root="$default_root"
    [[ "$scenario" != down ]] || root="/DATA/pgcc-delete-$port"
    data="$root/$name"; conf="/etc/postgresql/$v/$name"
    if [[ "${PGCC_TEST_RENAME:-no}" == yes && "$scenario" == down ]]; then data="$root/fixed"; fi
    log="/var/log/postgresql/postgresql-$v-$name.log"
    service="postgresql@$v-$name.service"
    unit="$(systemd_unit_dir)/$service"
    if [[ -n "$resume" && -d "$conf" ]]; then
        [[ "$(pg_lsclusters --no-header | awk -v n="$name" '$2==n {print $6}')" == "$data" ]]
        printf 'RESUME owned empty cluster %s\n' "$name"
    else
    ! pg_lsclusters --no-header | awk -v n="$name" '$2==n {found=1} END {exit !found}'
    [[ ! -e "$data" && ! -L "$data" && ! -e "$conf" && ! -L "$conf" ]]
    [[ ! -e "$unit" && ! -L "$unit" && ! -e "/etc/systemd/system/$service" ]]
    printf 'CREATE scenario=%s version=%s name=%s port=%s data=%s\n' "$scenario" "$v" "$name" "$port" "$data"
    timeout -k 5 120 pg_createcluster "$v" "$name" --port "$port" --datadir "$data" --logfile "$log" --start-conf=manual --createclusterconf=/dev/null
    write_cluster_unit_file "$unit" "$v" "$name" "$data"
    fi
    # Older postgresql-common defaults inject a setting removed in PostgreSQL 15.
    # Only the named disposable fixture is modified when resuming its preparation.
    if ((v >= 15)); then pg_conftool "$v" "$name" remove stats_temp_directory; fi
    timeout -k 5 30 systemctl daemon-reload
    # Build the exact disposable autostart link directly: affected WSL may reject
    # systemctl enable with a D-Bus reset independently of the deletion under test.
    if [[ ! -L "/etc/systemd/system/multi-user.target.wants/$service" ]]; then
        ln -s -- "$unit" "/etc/systemd/system/multi-user.target.wants/$service"
    fi
    start_cluster_checked "$v" "$name"
    if [[ "${PGCC_TEST_RENAME:-no}" == yes ]]; then
        runuser -u postgres -- psql --cluster "$v/$name" -X -v ON_ERROR_STOP=1 -d postgres -c 'CREATE TABLE public.rename_control AS SELECT generate_series(1,25) AS id;'
        # Exercise disabled autostart separately without calling systemctl disable.
        if [[ "$scenario" == down ]]; then rm -- "/etc/systemd/system/multi-user.target.wants/$service"; fi
    fi
    if [[ "$scenario" == down ]]; then stop_cluster_checked "$v" "$name"; fi
    if [[ "${PGCC_TEST_RENAME:-no}" == yes ]]; then
        rename_cluster_checked "$v" "$name" "${name}_ren" "$data" "$scenario"
        renamed_data="$(renamed_cluster_path "$data" "$name" "${name}_ren")"
        expected_state=online; [[ "$scenario" != down ]] || expected_state=down
        [[ "$(cluster_power_state "$v" "${name}_ren")" == "$expected_state" ]]
        validate_renamed_cluster_config "$v" "${name}_ren" "$renamed_data" "$(cluster_pg_home "$v" "$renamed_data")" postgres
        if [[ "$scenario" == online ]]; then
            [[ -e "/etc/systemd/system/multi-user.target.wants/postgresql@$v-${name}_ren.service" ]]
            [[ "$(runuser -u postgres -- psql --cluster "$v/${name}_ren" -X -Atqc 'SELECT sum(id) FROM public.rename_control' postgres)" == 325 ]]
        else
            [[ ! -L "/etc/systemd/system/multi-user.target.wants/postgresql@$v-${name}_ren.service" ]]
        fi
        rename_cluster_checked "$v" "${name}_ren" "$name" "$renamed_data" "$expected_state"
        [[ "$(cluster_power_state "$v" "$name")" == "$expected_state" ]]
        [[ ! -e "/etc/postgresql/$v/${name}_ren" && ! -e "$(systemd_unit_dir)/postgresql@$v-${name}_ren.service" ]]
        start_cluster_checked "$v" "$name"
        [[ "$(runuser -u postgres -- psql --cluster "$v/$name" -X -Atqc 'SELECT sum(id) FROM public.rename_control' postgres)" == 325 ]]
        if [[ "$scenario" == down ]]; then stop_cluster_checked "$v" "$name"; fi
        timeout -k 5s 15s systemctl show -p Version >/dev/null
        printf 'PASS prefix/reverse rename %s: SQL, config, unit, state, autostart, systemd response\n' "$scenario"
    fi
    pg_lsclusters
    NON_INTERACTIVE=1; TARGET_NAME_SET=1; pg_ver="$v"; cls_nm="$name"; BACKUP_BEFORE_DELETE=no
    if [[ "${PGCC_TEST_RENAME:-no}" == yes && "$scenario" == down ]]; then
        # The deletion guard intentionally requires basename == cluster name.
        # Move this owned fixed-path fixture using the normal move function.
        INSTALL_DATA_ROOT="$root"
        move_cluster_data_menu
        data="$root/pg_$v/$name"
    fi
    started=$SECONDS
    delete_cluster_menu
    printf 'DELETE rc=0 scenario=%s elapsed=%ss\n' "$scenario" "$((SECONDS-started))"
    [[ ! -e "$data" && ! -L "$data" && ! -e "$conf" && ! -e "$unit" && ! -e "$log" ]]
    [[ ! -e "/etc/syslog-ng/conf.d/mod-astra-postgres-$v-$name.conf" ]]
    ! pg_lsclusters --no-header | awk -v n="$name" '$2==n {found=1} END {exit !found}'
    printf 'PASS %s data/config/unit/log/syslog/registry removal\n' "$scenario"
    if [[ "$scenario" == down ]]; then
        if [[ "${PGCC_TEST_RENAME:-no}" == yes ]]; then rmdir -- "$root/pg_$v"; fi
        rmdir -- "$root"
    fi
done
pg_lsclusters --no-header >"$logs/after.log"
cmp "$work/before" "$logs/after.log"
sha256sum -c "$work/config.sha"
date --iso-8601=seconds
printf 'PASS original registry/config preserved\n'
