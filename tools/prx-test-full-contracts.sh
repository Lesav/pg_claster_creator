#!/usr/bin/env bash
# Purpose: fill full-plan argument/dependency/size contract gaps with isolated fixtures.
# Usage: bash tools/prx-test-full-contracts.sh REPO LOG_DIR
# Args: REPO -- unchanged product sources; LOG_DIR -- fresh results directory.
# Output: results.tsv and individual logs; no database, package or service changes.
# Example: bash tools/prx-test-full-contracts.sh /repo /repo/tmp/contracts
set -Eeuo pipefail
repo="$1"; logs="$2"
[[ ! -e "$logs" ]]; mkdir -p "$logs"
work="$(mktemp -d /tmp/pgcc-contracts.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
sed '/^main "\$@"$/d' "$repo/create-claster-deb.sh" >"$work/builder.sh"
touch "$work/content"
printf 'SELECT 42;\n' >"$work/schema.sql"
tar -czf "$work/16-qa-20260912-010101.tar.gz" -C "$work" content
cp "$work/16-qa-20260912-010101.tar.gz" "$work/16-qa-20260912-010101-dmp.tar.gz"
check() {
    local id="$1" expected="$2" rc; shift 2
    printf 'START %s %s\n' "$id" "$(date --iso-8601=seconds)" >>"$logs/run.log"
    { printf 'COMMAND '; printf '%q ' "$@"; printf '\n'; } >>"$logs/run.log"
    set +e
    (set -e; "$@") >"$logs/$id.log" 2>&1; rc=$?
    set -e
    printf 'END %s rc=%s %s\n' "$id" "$rc" "$(date --iso-8601=seconds)" >>"$logs/run.log"
    if [[ "$expected" == nonzero && "$rc" != 0 ]] || [[ "$expected" == "$rc" ]]; then
        printf '%s\tPASS\trc=%s\n' "$id" "$rc" >>"$logs/results.tsv"
    else
        printf '%s\tFAIL\trc=%s\n' "$id" "$rc" >>"$logs/results.tsv"
    fi
}
builder_defaults() {
    source "$work/builder.sh"
    MODE=2; pg=postgrespro-ent; pg_ver=16; cls_nm=qa; cls_pt=55432
    cls_ch=pgcc_owner; cls_us=pgcc_user; cls_pw=fixture_only
    SERVER_PACKAGE=postgrespro-ent-16-server; PACKAGE_SET=1
    EXTRA_DEPENDENCIES_INPUT=""; EXTRA_DEPENDENCIES=(); PREFER_NEWEST_SERVER=no
    DATA_ROOT=""; DATABASE_NAME=qa; BACKUP_FILE=""
}
dependencies() {
    builder_defaults
    parse_args --depends 'curl, jq,curl' --depends wget
    normalize_extra_dependencies
    [[ "${EXTRA_DEPENDENCIES[*]}" == 'curl jq wget' ]]
    [[ "$(dependency_list)" == 'postgresql-common, postgrespro-ent-16-server, postgrespro-ent-16-contrib, curl, jq, wget' ]]
    EXTRA_DEPENDENCIES=(); MODE=3
    [[ "$(dependency_list)" == 'postgresql-common, postgrespro-ent-16-server' ]]
    MODE=4; PREFER_NEWEST_SERVER=yes
    [[ "$(dependency_list)" == 'postgresql-common, postgrespro-ent-18-contrib | postgrespro-ent-17-contrib | postgrespro-ent-16-contrib' ]]
    for pg_ver in 14 16 17 18; do
        deps="$(dependency_list)"; printf '%s: %s\n' "$pg_ver" "$deps"
        [[ "$deps" == *"postgrespro-ent-$pg_ver-contrib" ]]
    done
    pg_ver=16; EXTRA_DEPENDENCIES_INPUT='postgrespro-ent-16-server,curl'
    normalize_extra_dependencies; filter_auto_postgrespro_dependencies
    [[ "${EXTRA_DEPENDENCIES[*]}" == curl ]]
}
dependency_bad() { builder_defaults; EXTRA_DEPENDENCIES_INPUT="$1"; normalize_extra_dependencies || exit 1; }
mode1_dep() { builder_defaults; MODE=1; EXTRA_DEPENDENCIES_INPUT=curl; validate_options; }
builder_valid() {
    builder_defaults; MODE="$1"
    [[ "$MODE" != 3 ]] || BACKUP_FILE="$work/16-qa-20260912-010101.tar.gz"
    [[ "$MODE" != 4 ]] || BACKUP_FILE="$work/16-qa-20260912-010101-dmp.tar.gz"
    [[ "$MODE" != 5 ]] || SQL_FILE="$work/schema.sql"
    [[ "${2:-}" != relative ]] || { cd "$work"; BACKUP_FILE="${BACKUP_FILE##*/}"; }
    validate_options
    printf 'VALID %s %s\n' "$MODE" "$(package_basename)"
}
builder_bad() {
    builder_defaults; MODE="$1"
    [[ "$MODE" != 3 ]] || BACKUP_FILE="$work/16-qa-20260912-010101.tar.gz"
    [[ "$MODE" != 4 ]] || BACKUP_FILE="$work/16-qa-20260912-010101-dmp.tar.gz"
    [[ "$MODE" != 5 ]] || SQL_FILE="$work/schema.sql"
    printf -v "$2" '%s' "$3"
    validate_options
}
sizes() {
    source "$repo/create-claster-backup.sh"
    [[ "$(size_to_bytes 1B)" == 1 && "$(size_to_bytes 1KiB)" == 1024 ]]
    [[ "$(size_to_bytes 1MiB)" == 1048576 && "$(size_to_bytes 1GiB)" == 1073741824 && "$(size_to_bytes 1TiB)" == 1099511627776 ]]
    for bad in 0 0B -1 1.5M BAD 9223372036854775808B 8388608TiB; do ! size_to_bytes "$bad"; done
}
display_sizes() {
    builder_defaults
    for bytes in 1 1024 1023995 1048576 1073741824; do
        truncate -s "$bytes" "$work/sparse"
        label="$(backup_file_size_label "$work/sparse")"
        printf '%s -> %s\n' "$bytes" "$label"
        [[ "${#label}" -le 9 && "$label" =~ ^[0-9]+[.][0-9]{2}\ [A-Z][a-z]$ && "$label" != 1000.00* ]]
    done
}
main_precedence() {
    source "$repo/create-claster.sh"
    # source inside a function makes declare variables local; do not run the
    # product EXIT cleanup after that function scope has ended.
    trap - EXIT
    pg=postgresql; pg_ver=13; cls_nm=config_qa; cls_pt=55001
    PGCC_ACTION=info; PGCC_PG_VERSION=14; PGCC_CLUSTER_NAME=env_qa; PGCC_CLUSTER_PORT=55002
    parse_args --action backup --pg-version 16 --cluster-name cli_qa --port 55003
    apply_runtime_options
    [[ "$ACTION" == backup && "$pg_ver" == 16 && "$cls_nm" == cli_qa && "$cls_pt" == 55003 ]]
    ARG_ACTION=""; ARG_PG_VERSION=""; ARG_CLUSTER_NAME=""; ARG_CLUSTER_PORT=""
    apply_runtime_options
    [[ "$ACTION" == info && "$pg_ver" == 14 && "$cls_nm" == env_qa && "$cls_pt" == 55002 ]]
}
main_action() {
    source "$repo/create-claster.sh"; trap - EXIT
    local requested="$1"
    PGCC_ACTION=info; PGCC_PG_VERSION=14; PGCC_CLUSTER_NAME=env_qa; PGCC_CLUSTER_PORT=55002
    parse_args --action "$requested" --pg-version 16 --cluster-name cli_qa --port 55003
    apply_runtime_options
    [[ "$ACTION" == "$requested" && "$pg_ver" == 16 && "$cls_nm" == cli_qa && "$cls_pt" == 55003 && "$NON_INTERACTIVE" == 1 ]]
    ARG_ACTION=""; ARG_PG_VERSION=""; ARG_CLUSTER_NAME=""; ARG_CLUSTER_PORT=""
    PGCC_ACTION="$requested"; apply_runtime_options
    [[ "$ACTION" == "$requested" && "$pg_ver" == 14 && "$cls_nm" == env_qa && "$cls_pt" == 55002 ]]
}
main_positional() {
    source "$repo/create-claster.sh"; trap - EXIT
    parse_args --action "$1" 16 qa_positional
    apply_runtime_options
    [[ "$pg_ver" == 16 && "$cls_nm" == qa_positional ]]
}
main_bad() {
    source "$repo/create-claster.sh"; trap - EXIT
    parse_args "$@"; apply_runtime_options
}
check DEB-DEPS 0 dependencies
for bad in 'curl (>= 1)' 'curl;id' 'Bad' 'curl,,jq' '/tmp/x'; do check "DEB-DEP-BAD-$(printf '%s' "$bad" | cksum | cut -d' ' -f1)" nonzero dependency_bad "$bad"; done
check DEB-DEP-MODE1 nonzero mode1_dep
for mode in 2 3 4 5; do
    check "DEB-VALID-$mode" 0 builder_valid "$mode"
    for field in pg pg_ver cls_nm cls_ch cls_us cls_pw cls_pt; do check "DEB-EMPTY-$mode-$field" nonzero builder_bad "$mode" "$field" ''; done
    check "DEB-DATA-RELATIVE-$mode" nonzero builder_bad "$mode" DATA_ROOT relative/path
done
for mode in 3 4; do
    check "DEB-RELATIVE-ARCHIVE-$mode" 0 builder_valid "$mode" relative
    check "DEB-NO-ARCHIVE-$mode" nonzero builder_bad "$mode" BACKUP_FILE ''
done
check DEB-NO-DATABASE-4 nonzero builder_bad 4 DATABASE_NAME ''
check DEB-NO-DATABASE-5 nonzero builder_bad 5 DATABASE_NAME ''
check DEB-NO-SQL-5 nonzero builder_bad 5 SQL_FILE ''
check DEB-WRONG-HOT nonzero builder_bad 3 BACKUP_FILE "$work/16-qa-20260912-010101-dmp.tar.gz"
check DEB-WRONG-COLD nonzero builder_bad 4 BACKUP_FILE "$work/16-qa-20260912-010101.tar.gz"
check BK-SIZES 0 sizes
check DEB-DISPLAY-SIZES 0 display_sizes
check MAIN-PRECEDENCE 0 main_precedence
for action in info install port move-data backup restore delete; do check "MAIN-CLI-ENV-$action" 0 main_action "$action"; done
for action in backup delete; do
    check "MAIN-POSITIONAL-$action" 0 main_positional "$action"
    check "MAIN-POSITIONAL-SHORT-$action" nonzero main_bad --action "$action" 16
    check "MAIN-POSITIONAL-LONG-$action" nonzero main_bad --action "$action" 16 qa extra
    check "MAIN-POSITIONAL-MIXED-$action" nonzero main_bad --action "$action" --pg-version 16 16 qa
done
for action in info install port move-data restore; do check "MAIN-POSITIONAL-REFUSED-$action" nonzero main_bad --action "$action" 16 qa; done
check MAIN-UNKNOWN-ACTION nonzero main_bad --action invalid
for option in --action --package --pg-version --cluster-name --port --schema --user --password --data-root --backup-dir --backup-file --backup-type --database --overwrite; do
    check "MAIN-MISSING-${option#--}" nonzero main_bad "$option"
done
env_value() {
    local script="$1" option="$2" variable="$3" field="$4" value="$5"
    source "$script"; trap - EXIT
    printf -v "$variable" '%s' "$value"
    parse_args
    [[ "${!field}" == "$value" ]]
    parse_args "$option" cli_value
    [[ "${!field}" == cli_value ]]
}
while read -r option variable field; do
    check "DEB-ENV-$variable" 0 env_value "$work/builder.sh" "$option" "$variable" "$field" env_value
done <<'MAP'
--mode PGCC_MODE MODE
--cluster-policy PGCC_CLUSTER_POLICY CLUSTER_POLICY
--pg-family PGCC_PG_FAMILY pg
--pg-version PGCC_PG_VERSION pg_ver
--cluster-name PGCC_CLUSTER_NAME cls_nm
--port PGCC_CLUSTER_PORT cls_pt
--package PGCC_PACKAGE SERVER_PACKAGE
--schema PGCC_SCHEMA cls_ch
--user PGCC_DB_USER cls_us
--password PGCC_DB_PASSWORD cls_pw
--data-root PGCC_DATA_ROOT DATA_ROOT
--backup-file PGCC_BACKUP_FILE BACKUP_FILE
--sql-file PGCC_SQL_FILE SQL_FILE
--backup-dir PGCC_BACKUP_DIR BACKUP_DIR
--database PGCC_DATABASE DATABASE_NAME
--depends PGCC_DEPENDS EXTRA_DEPENDENCIES_INPUT
--output-dir PGCC_OUTPUT_DIR OUTPUT_DIR
MAP
for mapping in '--backup-dir PGCC_BACKUP_DIR BACKUP_DIR' '--files-cnt PGCC_FILES_CNT FILES_COUNT' '--files-size PGCC_FILES_SIZE FILES_SIZE'; do
    read -r option variable field <<<"$mapping"
    check "BK-ENV-$variable" 0 env_value "$repo/create-claster-backup.sh" "$option" "$variable" "$field" env_value
done
builder_env_flags() {
    source "$work/builder.sh"; trap - EXIT
    PGCC_INTERACTIVE=no; PGCC_FORCE=yes; PGCC_DEPENDS=curl
    parse_args
    [[ "$(normalize_env_flag "$INTERACTIVE_MODE" test)" == no && "$(normalize_env_flag "$FORCE_BUILD" test)" == yes ]]
    parse_args --interactive --depends jq --depends wget
    [[ "$INTERACTIVE_MODE" == yes && "$EXTRA_DEPENDENCIES_INPUT" == jq,wget ]]
}
wrapper_env_target() {
    source "$repo/create-claster-backup.sh"; trap - EXIT
    PGCC_PG_VERSION=16; PGCC_CLUSTER_NAME=env_cluster; PGCC_DATABASE=env_db; PGCC_CRON=yes
    if [[ "$1" == cli ]]; then parse_args 17 cli_cluster cli_db; [[ "${POSITIONAL_ARGS[*]}" == '17 cli_cluster cli_db' ]];
    else parse_args; [[ "${POSITIONAL_ARGS[*]}" == '16 env_cluster env_db' ]]; fi
    [[ "$CREATE_CRON" == 1 ]]
}
wrapper_env_bad() {
    source "$repo/create-claster-backup.sh"; trap - EXIT
    if [[ "$1" == target ]]; then PGCC_PG_VERSION=16; else PGCC_CRON=invalid; fi
    parse_args
}
check DEB-ENV-FLAGS 0 builder_env_flags
check BK-ENV-TARGET 0 wrapper_env_target env
check BK-ENV-TARGET-CLI 0 wrapper_env_target cli
check BK-ENV-PARTIAL-TARGET nonzero wrapper_env_bad target
check BK-ENV-BAD-BOOL nonzero wrapper_env_bad boolean
main_env_value() {
    source "$repo/create-claster.sh"; trap - EXIT
    local option="$1" variable="$2" field="$3" value="$4" cli_value="$5"
    printf -v "$variable" '%s' "$value"
    apply_runtime_options
    [[ "${!field}" == "$value" ]]
    parse_args "$option" "$cli_value"
    apply_runtime_options
    [[ "${!field}" == "$cli_value" ]]
}
while read -r option variable field value cli_value; do
    check "MAIN-ENV-$variable" 0 main_env_value "$option" "$variable" "$field" "$value" "$cli_value"
done <<'MAP'
--action PGCC_ACTION ACTION info backup
--package PGCC_PACKAGE REQUESTED_PACKAGE postgresql-16 postgresql-17
--pg-family PGCC_PG_FAMILY pg postgresql tantor-be
--pg-version PGCC_PG_VERSION pg_ver 16 17
--cluster-name PGCC_CLUSTER_NAME cls_nm env_name cli_name
--port PGCC_CLUSTER_PORT cls_pt 5555 5556
--schema PGCC_SCHEMA cls_ch env_name cli_name
--user PGCC_DB_USER cls_us env_name cli_name
--password PGCC_DB_PASSWORD cls_pw env_value cli_value
--data-root PGCC_DATA_ROOT INSTALL_DATA_ROOT /env /cli
--backup-file PGCC_BACKUP_FILE BACKUP_FILE /env /cli
--backup-dir PGCC_BACKUP_DIR backup_dir /env /cli
--backup-type PGCC_BACKUP_TYPE BACKUP_TYPE hot cold
--database PGCC_DATABASE DATABASE_NAME env_name cli_name
--sql-file PGCC_SQL_FILE SQL_FILE /env.sql /cli.sql
--if-missing PGCC_IF_MISSING SQL_IF_MISSING error skip
--backup-before-delete PGCC_BACKUP_BEFORE_DELETE BACKUP_BEFORE_DELETE no yes
--clear-wal PGCC_CLEAR_WAL CLEAR_WAL no yes
--overwrite PGCC_OVERWRITE OVERWRITE_EXISTING no yes
MAP
! grep -q $'\tFAIL\t' "$logs/results.tsv"
