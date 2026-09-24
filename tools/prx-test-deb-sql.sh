#!/usr/bin/env bash
# Purpose: test SQL-mode selection, explicit-config packaging and postinst, optionally on an owned raw server.
# Usage: bash tools/prx-test-deb-sql.sh REPO LOG_DIR [PG_HOME PORT]
# Args: REPO -- source tree; LOG_DIR -- new evidence directory; optional PG_HOME/PORT
#   additionally run the generated SQL deployment on a disposable real server.
# Output: assertion log; disposable Linux fixtures/DEBs/server are removed on exit.
# Example: bash tools/prx-test-deb-sql.sh /repo /repo/tmp/sql-check /opt/tantor/db/18 59435
set -Eeuo pipefail
repo="$(realpath "$1")"; logs="$2"
[[ ! -e "$logs" ]]; mkdir -p "$logs"
exec >"$logs/check.log" 2>&1
work="$(mktemp -d /tmp/pgcc-deb-sql.XXXXXX)"
pg_home="${3:-}"; real_port="${4:-59435}"; original_path="$PATH"
cleanup() {
    if [[ -f "$work/real-data/postmaster.pid" ]]; then
        PATH="$original_path" runuser -u postgres -- "$pg_home/bin/pg_ctl" -D "$work/real-data" -m immediate -w stop || return 1
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT
export QA_SQL_WORK="$work"
cp "$repo"/create-claster*.sh "$repo"/.new-claster.config "$repo/LICENSE" "$work/"
while IFS= read -r -d '' document; do
    cp -- "$document" "$work/${document##*/}"
done < <(find "$repo" -maxdepth 1 -type f -name '*.md' -print0)
cp -R "$repo/man" "$work/man"
cp "$work/.new-claster.config" "$work/custom config.cfg"
printf '\n# Explicit configuration packaging fixture.\n' >>"$work/custom config.cfg"
sed '/^main "\$@"$/d' "$work/create-claster-deb.sh" >"$work/builder.sh"
mkdir "$work/backups" "$work/bin"
printf 'CREATE TABLE qa_sql(id integer); INSERT INTO qa_sql VALUES (42);\n' >"$work/backups/schema file.sql"
touch "$work/backups/18-qa-20260912-010101.tar.gz" "$work/backups/18-qa-20260912-010101-dmp.tar.gz"
ln -s 'schema file.sql' "$work/backups/link.sql"
ln -s missing.sql "$work/backups/broken.sql"
mkdir "$work/backups/directory.sql"
(
    source "$work/builder.sh"
    trap - EXIT
    parse_args --config "$work/custom config.cfg"
    select_config
    MODE=5; pg=tantor-be; pg_ver=18; cls_nm=qa; cls_ch=qa; cls_us=qa; cls_pw=qa
    cls_pt=59435; DATABASE_NAME=qa_db; BACKUP_DIR="$work/backups"; SQL_FILE=""; SERVER_PACKAGE=tantor-be-server-18
    wizard_screen() { :; }
    select_mode_interactive <<<5; [[ "$MODE" == 5 ]]
    for mode in 3 4; do
        MODE="$mode"; BACKUP_FILE=""
        kind=cold; [[ "$mode" != 4 ]] || kind=hot
        select_backup_interactive "$kind" <<<1 >"$logs/select-$mode.log"
        [[ "$(backup_kind "$BACKUP_FILE")" == "$kind" ]]
        [[ "$(grep -c ' - \[' "$logs/select-$mode.log")" == 1 ]]
    done
    MODE=5; BACKUP_FILE=""; SQL_FILE=""
    select_sql_interactive <<<1 >"$logs/sql-list.log"
    [[ "$SQL_FILE" == "$work/backups/schema file.sql" ]]
    ! grep -q 'broken.sql\|directory.sql' "$logs/sql-list.log"
    SQL_FILE=""; select_sql_interactive <<<"$work/backups/schema file.sql"
    cd "$work"; SQL_FILE=""; select_sql_interactive <<<'backups/schema file.sql'
    SQL_FILE=""; select_sql_interactive <<<'schema file.sql'
    BACKUP_DIR="$work/absent"; SQL_FILE=""; select_sql_interactive <<<"$work/backups/schema file.sql"
    BACKUP_DIR="$work/backups"; SQL_FILE=""; ! select_sql_interactive <<<0
    ! select_sql_interactive <<<99999999999999999999999999
    ! select_sql_interactive </dev/null
    ! resolve_sql_file "$work/backups/broken.sql"
    if (SQL_FILE="$work/backups/directory.sql"; prepare_sql_files); then exit 1; fi
    ! resolve_sql_file "$work/backups/18-qa-20260912-010101.tar.gz"
    SQL_FILE="$work/backups/schema file.sql"
    validate_options
    for bad in postgres template0 template1 ''; do
        if (DATABASE_NAME="$bad"; validate_options); then exit 1; fi
    done
    if (SQL_FILE=''; validate_options); then exit 1; fi
    if (BACKUP_FILE=bad; validate_options); then exit 1; fi
    if (MODE=2; validate_options); then exit 1; fi
    # The complete wizard uses SQL, then the same parameter steps as mode 4.
    MODE=5; SQL_FILE=""; DATABASE_NAME=qa_db
    interactive_configuration <<<$'1\n1\n5\n18\n\n\n\n\n\n\n\n\n1\ny'
    [[ "$MODE" == 5 && "$DATABASE_NAME" == qa_db ]]
    validate_options
    write_last_build_script
    grep -F -- '--sql-file' "$work/create-claster-deb-last.sh"
    grep -F -- '--database qa_db' "$work/create-claster-deb-last.sh"
    grep -F -- "--config $(printf '%q' "$CONFIG_FILE")" "$work/create-claster-deb-last.sh"
    OUTPUT_DIR="$work/out"; build_package
    deb="$OUTPUT_DIR/$(package_basename).deb"
    [[ "$deb" == *-cre-sql-qa-qa_db.deb ]]
    dpkg-deb -x "$deb" "$work/payload"
    dpkg-deb -e "$deb" "$work/control"
    cmp "$CONFIG_FILE" "$work/payload/usr/local/share/pg_claster_creator/.new-claster.config"
    ! grep -F -- "$CONFIG_FILE" "$work/control/postinst"
    cmp "$SQL_FILE" "$work/payload/usr/local/share/pg_claster_creator/package-data/install.sql"
    [[ "$(stat -c '%a' "$work/payload/usr/local/share/pg_claster_creator/package-data/install.sql")" == 600 ]]
    bash -n "$work/control/postinst"
    bash "$work/create-claster-deb-last.sh" >"$logs/last.log" 2>&1
    [[ -f "$work/dist/$(package_basename).deb" ]]
    dpkg-deb -x "$work/dist/$(package_basename).deb" "$work/repeat-payload"
    cmp "$CONFIG_FILE" "$work/repeat-payload/usr/local/share/pg_claster_creator/.new-claster.config"
    printf 'PASS selection, filtering, paths, validation, wizard, explicit config payload, last.sh\n'
    # Exercise the release helper on this disposable source tree, never REPO/dist.
    PGCC_CFG="$CONFIG_FILE" bash "$repo/tools/prx-build-release-local.sh" "$work" "$SCRIPT_VERSION" >"$logs/release-config.log" 2>&1
    printf 'PASS release helper: PGCC_CFG selects distribution config despite system defaults\n'
    env PGCC_CFG="$CONFIG_FILE" PGCC_MODE=5 PGCC_PG_FAMILY="$pg" PGCC_PG_VERSION="$pg_ver" \
        PGCC_CLUSTER_NAME="$cls_nm" PGCC_CLUSTER_PORT="$cls_pt" PGCC_PACKAGE="$SERVER_PACKAGE" \
        PGCC_SCHEMA="$cls_ch" PGCC_DB_USER="$cls_us" PGCC_DB_PASSWORD="$cls_pw" \
        PGCC_SQL_FILE="$SQL_FILE" PGCC_DATABASE="$DATABASE_NAME" PGCC_INTERACTIVE=no \
        PGCC_FORCE=yes PGCC_OUTPUT_DIR="$work/env-out" \
        bash "$work/create-claster-deb.sh" >"$logs/env-build.log" 2>&1
    dpkg-deb -x "$work/env-out/$(package_basename).deb" "$work/env-payload"
    cmp "$SQL_FILE" "$work/env-payload/usr/local/share/pg_claster_creator/package-data/install.sql"
    cmp "$CONFIG_FILE" "$work/env-payload/usr/local/share/pg_claster_creator/.new-claster.config"
    printf 'PASS mode 5 built from ENV only, SQL/config payload verified\n'
)
# Remap only the generated deployment's own paths; all commands below are fixtures.
payload="$work/payload/usr/local/share/pg_claster_creator"
sed "s|readonly creator_dir=.*|readonly creator_dir=\"$payload\"|; s|readonly state_dir=.*|readonly state_dir=\"$work/state\"|" "$work/control/postinst" >"$work/postinst"
cat >"$payload/create-claster.sh" <<'SH'
#!/usr/bin/env bash
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    source "$QA_SQL_WORK/create-claster.sh"
    trap - EXIT
    cluster_pg_home() { printf '%s' "$QA_SQL_WORK"; }
    cluster_socket_directory() { printf /tmp; }
    create_database() { touch "$QA_SQL_WORK/db"; printf 'CREATE_DB %s owner=%s\n' "$4" "$5" >>"$QA_SQL_WORK/events"; }
    database_exists() { [[ -f "$QA_SQL_WORK/db" ]]; }
    return
fi
case "$PGCC_ACTION" in
    install) touch "$QA_SQL_WORK/cluster"; echo INSTALL >>"$QA_SQL_WORK/events" ;;
    delete) rm -f "$QA_SQL_WORK/cluster" "$QA_SQL_WORK/db"; echo DELETE >>"$QA_SQL_WORK/events" ;;
    *) exit 1 ;;
esac
SH
cat >"$work/bin/pg_lsclusters" <<'SH'
#!/usr/bin/env bash
[[ ! -f "$QA_SQL_WORK/cluster" ]] || echo '18 qa 59435 online postgres /fixture/data /fixture/log'
SH
cat >"$work/bin/runuser" <<'SH'
#!/usr/bin/env bash
[[ "$1 $2 $3" == '-u postgres --' ]] || exit 1
shift 3
exec "$@"
SH
cat >"$work/bin/psql" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *'SELECT 1 FROM pg_database'* ]]; then
    if [[ -f "$QA_SQL_WORK/db" ]]; then echo 1; fi
else
    [[ "$*" == *'-X --no-password'* && "$*" == *'--set=ON_ERROR_STOP=1 --file=-'* ]] || exit 1
    cmp - "$QA_SQL_WORK/backups/schema file.sql" || exit 1
    echo SQL >>"$QA_SQL_WORK/events"
    [[ ! -f "$QA_SQL_WORK/fail-sql" ]] || exit 3
fi
SH
chmod +x "$work/bin/"* "$payload/create-claster.sh"
export PATH="$work/bin:$PATH"
bash "$work/postinst" configure
[[ "$(grep -c '^SQL$' "$work/events")" == 1 ]]
[[ "$(find "$work/state" -name '*.done' | wc -l)" == 1 ]]
bash "$work/postinst" configure
[[ "$(grep -c '^SQL$' "$work/events")" == 1 ]]
if CLASTER_FORCE_DB_INSTALL=1 bash "$work/postinst" configure; then exit 1; fi
touch "$work/fail-sql"
if CLASTER_FORCE_INSTALL=1 bash "$work/postinst" configure; then exit 1; fi
[[ "$(find "$work/state" -name '*.done' | wc -l)" == 0 ]]
before="$(wc -l <"$work/events")"
if bash "$work/postinst" configure; then exit 1; fi
[[ "$(wc -l <"$work/events")" == "$before" ]]
rm "$work/fail-sql"
CLASTER_FORCE_INSTALL=1 bash "$work/postinst" configure
[[ "$(find "$work/state" -name '*.done' | wc -l)" == 1 ]]
rm "$work/cluster" "$work/db"
bash "$work/postinst" configure
[[ "$(grep -c '^SQL$' "$work/events")" == 4 ]]
printf 'PASS postinst fresh/repeat/error/no-replay/force/stale markers; no real clusters changed\n'
if [[ -n "$pg_home" ]]; then
    # A raw disposable server is never registered in /etc or managed by systemd.
    [[ -x "$pg_home/bin/initdb" && "$real_port" =~ ^[0-9]+$ ]]
    export PATH="$original_path"
    chmod 755 "$work"
    mkdir "$work/real-data"
    chown postgres:postgres "$work/real-data"
    runuser -u postgres -- "$pg_home/bin/initdb" -D "$work/real-data" --auth=trust --no-locale
    runuser -u postgres -- "$pg_home/bin/pg_ctl" -D "$work/real-data" -l "$work/real-data/server.log" -o "-k /tmp -p $real_port -h ''" -w start
    runuser -u postgres -- "$pg_home/bin/psql" -X -h /tmp -p "$real_port" -d postgres -v ON_ERROR_STOP=1 -c 'CREATE ROLE qa LOGIN'
    cp "$repo/create-claster.sh" "$payload/create-claster.sh"
    # Only discovery is redirected to the owned raw server; SQL/client helpers are real.
    mkdir "$work/discovery"
    printf '#!/bin/sh\necho "18 qa %s online postgres %s/real-data %s/real-data/server.log"\n' "$real_port" "$work" "$work" >"$work/discovery/pg_lsclusters"
    chmod +x "$work/discovery/pg_lsclusters"
    export PATH="$work/discovery:$original_path"
    rm -f "$work/state/"*.done "$work/state/"*.sql-started
    bash "$work/postinst" configure
    [[ "$(runuser -u postgres -- "$pg_home/bin/psql" -X -h /tmp -p "$real_port" -d qa_db -Atqc 'SELECT id FROM qa_sql')" == 42 ]]
    [[ "$(runuser -u postgres -- "$pg_home/bin/psql" -X -h /tmp -p "$real_port" -d postgres -Atqc "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='qa_db'")" == qa ]]
    bash "$work/postinst" configure
    [[ "$(runuser -u postgres -- "$pg_home/bin/psql" -X -h /tmp -p "$real_port" -d qa_db -Atqc 'SELECT count(*) FROM qa_sql')" == 1 ]]
    runuser -u postgres -- "$pg_home/bin/createdb" -h /tmp -p "$real_port" --owner=qa qa
    sed -i 's/^database_name=qa_db$/database_name=qa/' "$payload/.package-install.env"
    rm -f "$work/state/"*.done "$work/state/"*.sql-started
    bash "$work/postinst" configure
    [[ "$(runuser -u postgres -- "$pg_home/bin/psql" -X -h /tmp -p "$real_port" -d qa -Atqc 'SELECT id FROM qa_sql')" == 42 ]]
    sed -i 's/^database_name=qa$/database_name=qa_db/' "$payload/.package-install.env"
    # Exercise the main script's SQL executor against the same owned live server.
    printf 'SHOW server_version;\n' >"$work/show-version.sql"
    (
        source "$repo/create-claster.sh"
        trap - EXIT
        execute_sql_checked 18 qa "$real_port" "$work/real-data" qa "$work/show-version.sql"
    ) >"$logs/main-sql-version.log"
    grep -q 'server_version' "$logs/main-sql-version.log"
    printf 'PASS main execute_sql_checked with SHOW server_version\n'
    # Real SQL error: do not write done or silently replay partial statements.
    runuser -u postgres -- "$pg_home/bin/dropdb" -h /tmp -p "$real_port" qa_db
    rm -f "$work/state/"*.done "$work/state/"*.sql-started
    printf 'CREATE TABLE partial_sql(id integer);\nSELECT * FROM nonexistent_sql_table;\nCREATE TABLE unreachable_sql(id integer);\n' >"$payload/package-data/install.sql"
    if bash "$work/postinst" configure; then exit 1; fi
    [[ "$(find "$work/state" -name '*.done' | wc -l)" == 0 ]]
    [[ "$(runuser -u postgres -- "$pg_home/bin/psql" -X -h /tmp -p "$real_port" -d qa_db -Atqc "SELECT to_regclass('partial_sql') IS NOT NULL AND to_regclass('unreachable_sql') IS NULL")" == t ]]
    if bash "$work/postinst" configure; then exit 1; fi
    printf 'PASS real SQL, owner, actual port, repeat, error-stop and no replay\n'
fi
