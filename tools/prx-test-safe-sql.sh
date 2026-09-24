#!/usr/bin/env bash
# Purpose: live singl/struct-dirs SQL on a private, unregistered PostgreSQL
# instance. Never stop original clusters, install packages or change system config.
# Usage: bash tools/prx-test-safe-sql.sh REPO LOG_DIR [INSTALLED_SERVER_PACKAGE] [SQL_TREE]
# SQL_TREE defaults to sql-tests beside this helper; root 00.sql runs last as oracle.
# Environment: none required. Requires root, postgres user and installed binaries.
# Output: evidence and SKIP/PASS; missing/ambiguous server binaries are SKIP.
# The real server is named test_<random 1..9>, uses a free port and a private Unix
# socket only. A test-local registry adapter allows the product SQL guards to
# address it without writing /etc/postgresql; this is NOT a cluster-management test.
set -Eeuo pipefail
repo="$(realpath "$1")"; logs="$(realpath -m "$2")"; package="${3:-}"
fixture="$(realpath -e "${4:-$(dirname -- "${BASH_SOURCE[0]}")/sql-tests}")"
[[ -f "$fixture/00.sql" ]] || exit 2
[[ ! -e "$logs" ]] || exit 2
mkdir -p "$logs"
exec >"$logs/check.log" 2>&1
skip() { printf 'SKIP: %s\n' "$*"; exit 0; }
pg_lsclusters --no-header >"$logs/registry-before"
dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\t${Version}\n' >"$logs/packages-before"
id postgres >/dev/null 2>&1 || skip 'нет пользователя postgres'
mapfile -t packages < <(awk -F '\t' '$2=="installed" && $1 ~ /^(postgresql-|postgrespro-|tantor-)/ {print $1}' "$logs/packages-before")
binaries=()
for candidate in "${packages[@]}"; do
    [[ -z "$package" || "$candidate" == "$package" ]] || continue
    while IFS= read -r binary; do
        [[ "$binary" == */bin/postgres && -x "$binary" ]] || continue
        binaries+=("$binary")
    done < <(dpkg -L "$candidate")
done
((${#binaries[@]} == 1)) || skip 'не найден единственный сервер; укажите --package для безопасного SQL-теста'
pgbin="${binaries[0]%/postgres}"
[[ -x "$pgbin/initdb" && -x "$pgbin/pg_ctl" && -x "$pgbin/psql" ]] || skip 'неполный комплект серверных утилит'
name=""
for digit in $(shuf -i 1-9); do
    candidate="test_$digit"
    if ! awk -v n="$candidate" '$2 ~ ("^" n) {found=1} END {exit !found}' "$logs/registry-before"; then
        name="$candidate"; break
    fi
done
[[ -n "$name" ]] || skip 'все префиксы test_1..test_9 заняты'
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
major="$("$pgbin/postgres" --version | sed -E 's/.* ([0-9]+)\..*/\1/')"
[[ "$major" =~ ^[0-9]+$ && "$port" =~ ^[0-9]+$ ]] || exit 2
work="$(mktemp -d /var/tmp/pgcc-safe-sql.XXXXXXXX)"
cleanup() {
    rc=$?; trap - EXIT; set +e
    if [[ -f "$work/data/postmaster.pid" ]]; then
        runuser -u postgres -- "$pgbin/pg_ctl" -D "$work/data" -m fast -w stop || rc=1
    fi
    [[ ! -f "$work/server.log" ]] || cp "$work/server.log" "$logs/server.log"
    pg_lsclusters --no-header >"$logs/registry-after" || rc=1
    cmp "$logs/registry-before" "$logs/registry-after" || rc=1
    dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\t${Version}\n' >"$logs/packages-after" || rc=1
    cmp "$logs/packages-before" "$logs/packages-after" || rc=1
    if [[ ! -f "$work/data/postmaster.pid" && "$work" == /var/tmp/pgcc-safe-sql.* && ! -L "$work" && "$(realpath "$work")" == "$work" ]]; then
        rm -rf -- "$work"
    else
        printf 'FAIL cleanup; retained: %s\n' "$work"; rc=1
    fi
    printf 'FINAL rc=%s; target=%s port=%s\n' "$rc" "$name" "$port"
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
chown postgres:postgres "$work"
runuser -u postgres -- "$pgbin/initdb" -D "$work/data" --auth=trust --no-locale
install -d -o postgres -g postgres -m 0700 "$work/socket"
runuser -u postgres -- "$pgbin/pg_ctl" -D "$work/data" -l "$work/server.log" \
    -o "-p $port -k $work/socket -c listen_addresses='' -c cluster_name=$name" -w start
printf 'TARGET name=%s port=%s; private Unix socket; registry adapter only\n' "$name" "$port"
printf 'CREATE TABLE probe(id integer); INSERT INTO probe VALUES (42);\n' >"$work/singl.sql"
mkdir -p "$work/struct-dirs/02 nested"
printf 'CREATE TABLE sequence_probe(id integer); INSERT INTO sequence_probe VALUES(1);\n' >"$work/struct-dirs/01.sql"
printf 'INSERT INTO sequence_probe VALUES(2);\n' >"$work/struct-dirs/02 nested/01.sql"
printf 'INSERT INTO sequence_probe VALUES(3);\n' >"$work/struct-dirs/10.sql"
(
    readonly safe_major="$major" safe_name="$name" safe_port="$port" safe_work="$work" safe_bin="$pgbin"
    source "$repo/create-claster.sh"
    trap - EXIT
    # Local adapter only; no changes to the host registry or existing services.
    pg_lsclusters() { printf '%s %s %s online postgres %s/data %s/server.log\n' "$safe_major" "$safe_name" "$safe_port" "$safe_work" "$safe_work"; }
    cluster_pg_home() { printf '%s' "${safe_bin%/bin}"; }
    cluster_socket_directory() { printf '%s/socket' "$safe_work"; }
    execute_sql_checked "$safe_major" "$safe_name" "$safe_port" "$safe_work/data" postgres "$safe_work/singl.sql"
    collect_sql_files "$safe_work/struct-dirs"
    execute_sql_files_checked "$safe_major" "$safe_name" "$safe_port" "$safe_work/data" postgres "${SELECTED_SQL_FILES[@]}"
    [[ "$(runuser -u postgres -- "$safe_bin/psql" -X -h "$safe_work/socket" -p "$safe_port" -d postgres -Atqc 'SELECT string_agg(id::text, chr(44) ORDER BY id) FROM sequence_probe')" == 1,2,3 ]]
    printf 'INSERT INTO sequence_probe VALUES(4); SELECT nonexistent_column;\n' >"$work/struct-dirs/02 nested/01.sql"
    # A separate batch: truncate so the failed second file has observable effects.
    printf 'TRUNCATE sequence_probe; INSERT INTO sequence_probe VALUES(1);\n' >"$work/struct-dirs/01.sql"
    if execute_sql_files_checked "$safe_major" "$safe_name" "$safe_port" "$safe_work/data" postgres "${SELECTED_SQL_FILES[@]}"; then exit 1; fi
    # Collect with the production sorter, then exclude only the control file.
    # The remaining relative-path ordering is exactly what the product returns.
    collect_sql_files "$fixture"
    tree_files=()
    for file in "${SELECTED_SQL_FILES[@]}"; do
        [[ "$file" == "$fixture/00.sql" ]] || tree_files+=("$file")
    done
    ((${#tree_files[@]} == 6))
    printf '%s\n' "${tree_files[@]#"$fixture/"}" >"$logs/sql-tree-order.log"
    execute_sql_files_checked "$safe_major" "$safe_name" "$safe_port" "$safe_work/data" postgres "${tree_files[@]}"
    # Check the oracle itself: wrong order and missing/extra rows must fail.
    negative_index=0
    for mutation in \
        'UPDATE public.pgcc_sql_order_probe SET expected_order = CASE expected_order WHEN 2 THEN 3 WHEN 3 THEN 2 ELSE expected_order END;' \
        'DELETE FROM public.pgcc_sql_order_probe WHERE expected_order=6;' \
        "INSERT INTO public.pgcc_sql_order_probe(expected_order,source_path) VALUES(6,'02_dir/11_dir/00.sql');"; do
        ((negative_index += 1))
        { printf 'BEGIN;\n%s\n' "$mutation"; cat "$fixture/00.sql"; printf '\nROLLBACK;\n'; } |
            runuser -u postgres -- "$safe_bin/psql" -X -v ON_ERROR_STOP=1 -h "$safe_work/socket" -p "$safe_port" -d postgres >"$logs/sql-tree-negative-$negative_index.log"
        grep -Fxq FAIL "$logs/sql-tree-negative-$negative_index.log"
        ! grep -Fxq PASS "$logs/sql-tree-negative-$negative_index.log"
    done
    execute_sql_checked "$safe_major" "$safe_name" "$safe_port" "$safe_work/data" postgres "$fixture/00.sql" >"$logs/sql-tree-result.log"
    cat "$logs/sql-tree-result.log"
    [[ "$(tail -n 1 "$logs/sql-tree-result.log")" == PASS ]]
)
# Older psql prints only the last result of a multi-statement -c argument.
# Separate -c arguments preserve both checks on PostgreSQL 13 as well.
actual="$(runuser -u postgres -- "$pgbin/psql" -X -h "$work/socket" -p "$port" -d postgres -Atq -c 'SELECT id FROM probe' -c 'SELECT string_agg(id::text, chr(44) ORDER BY id) FROM sequence_probe')"
[[ "$actual" == $'42\n1,4' ]]
printf 'PASS live singl/struct-dirs SQL and stop-on-error; original clusters and packages untouched\n'
