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
    [[ "${2:-}" != relative ]] || { cd "$work"; BACKUP_FILE="${BACKUP_FILE##*/}"; }
    validate_options
    printf 'VALID %s %s\n' "$MODE" "$(package_basename)"
}
builder_bad() {
    builder_defaults; MODE="$1"
    [[ "$MODE" != 3 ]] || BACKUP_FILE="$work/16-qa-20260912-010101.tar.gz"
    [[ "$MODE" != 4 ]] || BACKUP_FILE="$work/16-qa-20260912-010101-dmp.tar.gz"
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
for mode in 2 3 4; do
    check "DEB-VALID-$mode" 0 builder_valid "$mode"
    for field in pg pg_ver cls_nm cls_ch cls_us cls_pw cls_pt; do check "DEB-EMPTY-$mode-$field" nonzero builder_bad "$mode" "$field" ''; done
    check "DEB-DATA-RELATIVE-$mode" nonzero builder_bad "$mode" DATA_ROOT relative/path
done
for mode in 3 4; do
    check "DEB-RELATIVE-ARCHIVE-$mode" 0 builder_valid "$mode" relative
    check "DEB-NO-ARCHIVE-$mode" nonzero builder_bad "$mode" BACKUP_FILE ''
done
check DEB-NO-DATABASE-4 nonzero builder_bad 4 DATABASE_NAME ''
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
! grep -q $'\tFAIL\t' "$logs/results.tsv"
