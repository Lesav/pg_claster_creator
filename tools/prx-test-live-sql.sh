#!/usr/bin/env bash
# Purpose: current full-run SQL menu and real mode5 deployment extension.
# Usage: PGCC_LIVE_EXTENSION=tools/prx-test-live-sql.sh (source through live regression runner)
# Args: use the calling run's validated per-WSL arguments and environment.
# Example: see tools/prx-test-wsl-stand.sh for the shared run environment.
# Path note: adjust /mnt/d/Ai/pg_claster_creator and its .backup sibling if different.
# Output: parent step evidence; targets use the parent's owned c/cm4 cleanup names.
sql() { runuser -u postgres -- psql --cluster "$v/$1" -X --set=ON_ERROR_STOP=1 --dbname "$2" -Atqc "$3"; }
mkdir "$work/debs"
printf 'CREATE SCHEMA qa_sql; CREATE TABLE qa_sql.probe(id integer PRIMARY KEY); INSERT INTO qa_sql.probe VALUES (42);\n' >"$backup/install.sql"
printf 'SHOW server_version;\n' >"$backup/version.sql"
step SQL-DEB-BUILD 0 timeout -k 5 180 env PGCC_MODE=5 PGCC_INTERACTIVE=no PGCC_PACKAGE="$package" PGCC_PG_FAMILY="$family" PGCC_PG_VERSION="$v" PGCC_CLUSTER_NAME="$c" PGCC_CLUSTER_PORT="$port" PGCC_SCHEMA=pgcc_owner PGCC_DB_USER=pgcc_user PGCC_DB_PASSWORD='Pgcc-QA-2.1.1!' PGCC_DATABASE=qa_sql PGCC_SQL_FILE="$backup/install.sql" PGCC_OUTPUT_DIR="$work/debs" bash "$builder"
deb="$(find "$work/debs" -name '*-cre-sql-*.deb' -print -quit)"
[[ -n "$deb" ]]; touch "$work/deployed-mode"
step SQL-DEB-INSTALL 0 timeout -k 5 900 env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y "$deb"
step SQL-DEB-ROW 0 test "$(sql "$c" qa_sql 'SELECT id FROM qa_sql.probe')" = 42
step SQL-DEB-OWNER 0 test "$(sql "$c" postgres "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='qa_sql'")" = pgcc_owner
step SQL-DEB-REPEAT 0 timeout -k 5 180 env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --reinstall "$deb"
step SQL-DEB-NO-REPLAY 0 test "$(sql "$c" qa_sql 'SELECT count(*) FROM qa_sql.probe')" = 1
index="$(pg_lsclusters --no-header | awk -v n="$c" '$2==n {print NR}')"
menu_sql() { printf '%s\n' "$1" | timeout -k 5 90 env PGCC_BACKUP_DIR="$backup" "$creator"; }
step SQL-MENU-PATH 0 menu_sql "$(printf '4\n4\n%s\nqa_sql\n%s\ny\n\n0\n0\n' "$index" "$backup/version.sql")"
step SQL-MENU-VERSION 0 grep -F server_version "$logs/SQL-MENU-PATH.log"
step SQL-MENU-CANCEL 0 menu_sql "$(printf '4\n4\n%s\nqa_sql\n%s\n\n0\n0\n' "$index" "$backup/install.sql")"
step SQL-MENU-CANCEL-PRESERVED 0 test "$(sql "$c" qa_sql 'SELECT count(*) FROM qa_sql.probe')" = 1
step SQL-MENU-PTY 0 script -q -e -c "env PGCC_BACKUP_DIR=$backup $creator" /dev/null <<<"$(printf '4\n4\n%s\nqa_sql\n2\ny\n\n0\n0\n' "$index")"
step SQL-MENU-PTY-VERSION 0 grep -F server_version "$logs/SQL-MENU-PTY.log"
step SQL-DEB-FORCE-CLUSTER 0 timeout -k 5 180 env CLASTER_FORCE_INSTALL=1 DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --reinstall "$deb"
step SQL-DEB-FORCE-ROW 0 test "$(sql "$c" qa_sql 'SELECT id FROM qa_sql.probe')" = 42
step SQL-DEB-FORCE-DB-REJECT nonzero timeout -k 5 180 env CLASTER_FORCE_DB_INSTALL=1 DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --reinstall "$deb"
step SQL-DEB-REPAIR 0 timeout -k 5 180 dpkg --force-confold -i "$deb"
step SQL-DEB-BOTH-FORCE-REJECT nonzero timeout -k 5 180 env CLASTER_FORCE_DB_INSTALL=1 CLASTER_FORCE_INSTALL=1 dpkg --force-confold -i "$deb"
step SQL-DEB-BOTH-FORCE-PRESERVED 0 test "$(sql "$c" qa_sql 'SELECT id FROM qa_sql.probe')" = 42
step SQL-DEB-BOTH-FORCE-REPAIR 0 timeout -k 5 180 dpkg --force-confold -i "$deb"
same="${c}m2"
step SQL-DEB-SAME-NAME-BUILD 0 timeout -k 5 180 bash "$builder" --mode 5 --non-interactive --package "$package" --pg-family "$family" --pg-version "$v" --cluster-name "$same" --port "$port" --schema pgcc_owner --user pgcc_user --password 'Pgcc-QA-2.1.1!' --database "$same" --sql-file "$backup/install.sql" --output-dir "$work/debs"
same_deb="$(find "$work/debs" -name "*-cre-sql-$same-*.deb" -print -quit)"
step SQL-DEB-SAME-NAME-INSTALL 0 timeout -k 5 180 dpkg --force-confold -i "$same_deb"
actual_port="$(pg_lsclusters --no-header | awk -v n="$same" '$2==n {print $3}')"
step SQL-DEB-OCCUPIED-PORT 0 test "$actual_port" != "$port"
step SQL-DEB-SAME-NAME-ROW 0 test "$(sql "$same" "$same" 'SELECT id FROM qa_sql.probe')" = 42
step SQL-DEB-SAME-NAME-READY 0 pg_isready -h 127.0.0.1 -p "$actual_port"
printf 'CREATE TABLE public.qa_partial(id integer); SELECT nonexistent_qa_column;\n' >"$backup/error.sql"
step SQL-DEB-ERROR-BUILD 0 timeout -k 5 180 bash "$builder" --mode 5 --non-interactive --package "$package" --pg-family "$family" --pg-version "$v" --cluster-name "${c}m4" --port "$((port+2))" --schema pgcc_owner --user pgcc_user --password 'Pgcc-QA-2.1.1!' --database qa_error --sql-file="$backup/error.sql" --output-dir "$work/debs"
bad_deb="$(find "$work/debs" -name "*-cre-sql-${c}m4-*.deb" -print -quit)"
step SQL-DEB-ERROR nonzero timeout -k 5 180 dpkg --force-confold -i "$bad_deb"
step SQL-DEB-PARTIAL 0 test "$(sql "${c}m4" qa_error "SELECT to_regclass('public.qa_partial') IS NOT NULL")" = t
step SQL-DEB-ERROR-NO-REPLAY nonzero timeout -k 5 180 dpkg --force-confold -i "$bad_deb"
step SQL-DEB-ERROR-DIAGNOSTIC 0 grep -F 'Автоматический повтор запрещён' "$logs/SQL-DEB-ERROR-NO-REPLAY.log"
printf 'SQL MODE5 AND MENU COMPLETED\n'
