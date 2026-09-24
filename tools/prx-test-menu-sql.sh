#!/usr/bin/env bash
# Purpose: exercise interactive SQL navigation and target/file guards with isolated commands.
# Usage: bash tools/prx-test-menu-sql.sh REPO LOG_DIR
# Args: REPO -- source root; LOG_DIR -- new evidence directory.
# Output: check.log and case logs; no real database or package changes.
# Example: bash tools/prx-test-menu-sql.sh /repo /repo/tmp/sql-menu
set -Eeuo pipefail
repo="$(realpath "$1")"; logs="$2"
[[ ! -e "$logs" ]]; mkdir -p "$logs"
exec >"$logs/check.log" 2>&1
fixture="$(mktemp -d /tmp/pgcc-menu-sql.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
source "$repo/create-claster.sh"
trap 'rm -rf -- "$fixture"' EXIT
NON_INTERACTIVE=0; backup_dir="$fixture/backups"
mkdir "$backup_dir"
printf 'SHOW server_version;\n' >"$backup_dir/a file.sql"
ln -s 'a file.sql' "$backup_dir/b.sql"
ln -s absent.sql "$backup_dir/broken.sql"
mkdir "$backup_dir/directory.sql"
header() { printf 'SCREEN\n'; }
pause() { :; }
pg_lsclusters() { [[ "${REGISTRY_FAIL:-0}" == 0 ]] || return 1; printf '18 qa %s %s postgres /fixture/data /fixture/log\n' "${MOCK_PORT:-59436}" "${MOCK_STATUS:-online}"; }
cluster_pg_home() { printf /fixture; }
cluster_socket_directory() { printf /tmp; }
print_cluster_databases() { CLUSTER_DATABASES=(qa postgres); printf '1 - qa\n2 - postgres\n0 - Вернуться назад\n'; }
database_exists() { [[ "${DATABASE_FAIL:-0}" == 0 ]]; }
runuser() {
    printf '%s\n' "$*" >>"$fixture/events"
    [[ "$*" == '-u postgres -- /fixture/bin/psql -X --no-password -h /tmp -p 59436 -d qa --set=ON_ERROR_STOP=1 --file=-' ]] || return 91
    cmp - "$backup_dir/a file.sql" || return 92
    printf 'server_version\n18.1\n'
    return "${SQL_RC:-0}"
}
check_menu() {
    local id="$1" input="$2" expected="$3" count=0
    : >"$fixture/events"
    execute_sql_menu <<<"$input" >"$logs/$id.log" 2>&1
    count="$(wc -l <"$fixture/events")"
    [[ "$count" == "$expected" ]] || { echo "FAIL $id executions=$count"; exit 1; }
    printf 'PASS %s\n' "$id"
}
check_menu yes $'1\n1\n1\ny' 1
grep -q 'успешно выполнен' "$logs/yes.log"
check_menu default-no $'1\n1\n1\n' 0
check_menu explicit-no $'1\n1\n1\nN' 0
check_menu invalid-confirm $'1\n1\n1\nyes' 0
check_menu cluster-name $'qa\nqa\n1\nY' 1
check_menu file-symlink $'1\n1\n2\ny' 1
check_menu back-confirm $'1\n1\n1\n0\n1\ny' 1
check_menu back-file $'1\n1\n0\n1\n1\ny' 1
check_menu back-database $'1\n0\n1\n1\n1\ny' 1
check_menu back-cluster 0 0
check_menu absolute "$(printf '1\n1\n%s\ny' "$backup_dir/a file.sql")" 1
cd "$fixture"
check_menu relative $'1\n1\nbackups/a file.sql\ny' 1
check_menu backup-relative $'1\n1\na file.sql\ny' 1
for stage in '' $'1' $'1\n1' $'1\n1\n1'; do
    : >"$fixture/events"
    printf '%s\n' "$stage" | execute_sql_menu >/dev/null
    [[ ! -s "$fixture/events" ]]
done
SQL_RC=3; check_menu sql-error $'1\n1\n1\ny' 1; unset SQL_RC
grep -q 'код 3' "$logs/sql-error.log"
! grep -q 'успешно выполнен' "$logs/sql-error.log"
MOCK_STATUS=down; check_menu down $'1\n0' 0; unset MOCK_STATUS
: >"$fixture/events"
for guard in port status registry database file; do
    case "$guard" in
        port) MOCK_PORT=59437 ;;
        status) MOCK_STATUS=down ;;
        registry) REGISTRY_FAIL=1 ;;
        database) DATABASE_FAIL=1 ;;
        file) mv "$backup_dir/a file.sql" "$backup_dir/hidden" ;;
    esac
    if execute_sql_checked 18 qa 59436 /fixture/data qa "$backup_dir/a file.sql"; then echo "FAIL guard $guard"; exit 1; fi
    unset MOCK_PORT MOCK_STATUS REGISTRY_FAIL DATABASE_FAIL
    [[ "$guard" != file ]] || mv "$backup_dir/hidden" "$backup_dir/a file.sql"
    printf 'PASS guard %s\n' "$guard"
done
[[ ! -s "$fixture/events" ]]
select_sql_file <<<1 >"$logs/files.log"
! grep -q 'broken.sql\|directory.sql' "$logs/files.log"
actual_backup="$backup_dir"; backup_dir="$fixture/missing"
select_sql_file <<<"$actual_backup/a file.sql"
[[ "$SELECTED_SQL_FILE" == "$actual_backup/a file.sql" ]]
backup_dir="$actual_backup"
for invalid in broken.sql directory.sql missing.sql anything.tar.gz 99999999999999999999999999; do
    if select_sql_file <<<"$invalid"; then echo "FAIL invalid $invalid"; exit 1; fi
done
printf 'PASS SQL menu: selections, paths, back/EOF, confirmation, errors and target guards\n'

# Directory plans use relative-path byte order, preserve spaces/newlines, and
# never follow symlinks. Each file is submitted separately to the same target.
tree="$fixture/sql tree"
mkdir -p "$tree/02 nested" "$tree/empty"
printf 'first\n' >"$tree/01.sql"
printf 'second\n' >"$tree/02 nested/01.sql"
printf 'third\n' >"$tree/02 nested/02 line"$'\n'"break.sql"
printf 'last\n' >"$tree/10.sql"
printf 'ignored\n' >"$tree/readme.txt"
ln -s ../backups "$tree/linked-directory"
ln -s 01.sql "$tree/linked.sql"
select_sql_file <<<"$tree"
[[ ${#SELECTED_SQL_FILES[@]} == 4 ]]
[[ "${SELECTED_SQL_FILES[0]}" == "$tree/01.sql" && "${SELECTED_SQL_FILES[1]}" == "$tree/02 nested/01.sql" && "${SELECTED_SQL_FILES[3]}" == "$tree/10.sql" ]]
runuser() {
    local contents
    contents="$(cat)"
    printf '%s\n' "$contents" >>"$fixture/events"
    [[ "${CHANGE_TARGET:-0}" == 0 ]] || MOCK_PORT=59437
    [[ "$contents" != "${FAIL_CONTENT:-never}" ]] || return 3
}
check_menu directory "$(printf '1\n1\n%s\ny' "$tree")" 4
printf 'first\nsecond\nthird\nlast\n' >"$fixture/expected"
cmp "$fixture/expected" "$fixture/events"
check_menu directory-cancel "$(printf '1\n1\n%s\nN' "$tree")" 0
FAIL_CONTENT=second
check_menu directory-error "$(printf '1\n1\n%s\ny' "$tree")" 2
grep -q 'код 3' "$logs/directory-error.log"
unset FAIL_CONTENT
CHANGE_TARGET=1
check_menu directory-target-changed "$(printf '1\n1\n%s\ny' "$tree")" 1
unset CHANGE_TARGET MOCK_PORT
select_sql_file <<<"sql tree"
[[ ${#SELECTED_SQL_FILES[@]} == 4 ]]
mkdir "$backup_dir/nested"
printf 'backup-relative\n' >"$backup_dir/nested/01.sql"
select_sql_file <<<"nested"
[[ "${SELECTED_SQL_FILES[0]}" == "$backup_dir/nested/01.sql" ]]
! collect_sql_files "$tree/empty"
select_sql_file <<<"$tree"
printf 'not-confirmed\n' >"$tree/99.sql"
: >"$fixture/events"
execute_sql_files_checked 18 qa 59436 /fixture/data qa "${SELECTED_SQL_FILES[@]}"
cmp "$fixture/expected" "$fixture/events"
rm -- "$tree/01.sql"
: >"$fixture/events"
! execute_sql_files_checked 18 qa 59436 /fixture/data qa "${SELECTED_SQL_FILES[@]}"
[[ ! -s "$fixture/events" ]]
printf 'PASS SQL directories: recursion, byte order, paths, symlink exclusion, cancellation, stop on error, target changes, frozen plan and disappeared file\n'
