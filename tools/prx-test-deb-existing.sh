#!/usr/bin/env bash
# Purpose: isolated regression for existing-target SQL and explicit replacement.
# Usage: bash tools/prx-test-deb-existing.sh REPO LOG_DIR
# Safety: no real clusters/packages/services are changed; all postinst paths and
# external commands are redirected into an owned temporary Linux directory.
set -Eeuo pipefail
repo="$(realpath "$1")"; logs="$(realpath -m "$2")"
mkdir -p "$logs"
exec >"$logs/check.log" 2>&1
work="$(mktemp -d /tmp/pgcc-existing.XXXXXXXX)"
trap 'rm -rf -- "$work"' EXIT
export QA_SQL_WORK="$work"
cp "$repo"/create-claster*.sh "$repo/.new-claster.config" "$repo/LICENSE" "$work/"
cp -R "$repo/man" "$work/"
sed '/^main "\$@"$/d' "$work/create-claster-deb.sh" >"$work/builder.sh"
cp "$repo/create-claster.sh" "$work/real-creator.sh"
mkdir "$work/bin" "$work/empty"
printf 'SHOW server_version;\n' >"$work/input.sql"
tar -czf "$work/18-qa-20260924-010101-dmp.tar.gz" -C "$work/empty" .
for mode in 4 5 6; do
    (
        source "$work/builder.sh"; trap - EXIT
        parse_args --config "$work/.new-claster.config" --mode "$mode" --non-interactive \
            --pg-family tantor-be --pg-version 18 --cluster-name qa --database qa_db \
            --schema qa --user qa --password qa --package tantor-be-server-18
        select_config
        if [[ "$mode" == 4 ]]; then BACKUP_FILE="$work/18-qa-20260924-010101-dmp.tar.gz"; else SQL_FILE="$work/input.sql"; fi
        if [[ "$mode" != 6 ]]; then
            PGCC_CLUSTER_POLICY=replace; ENV_OPTIONS_LOADED=0
            parse_args --cluster-policy create; [[ "$CLUSTER_POLICY" == create ]]
            parse_args --cluster-policy replace
            wizard_step policy <<<1; [[ "$CLUSTER_POLICY" == create ]]
            wizard_step policy <<<2; [[ "$CLUSTER_POLICY" == replace ]]
            ! wizard_step policy <<<0
            ! wizard_step policy <<<bad
        fi
        validate_options
        if [[ "$mode" == 6 ]]; then
            [[ "$(dependency_list)" == postgresql-common ]]
            [[ -z "$cls_pw" && -z "$SERVER_PACKAGE" ]]
            if (CLUSTER_POLICY=replace; validate_options); then exit 1; fi
            wizard_screen() { :; }
            interactive_configuration <<<"$(printf '18\nqa\nqa_db\n%s\ny\n' "$work/input.sql")"
            [[ "$MODE" == 6 && "$DATABASE_NAME" == qa_db && "$SQL_FILE" == "$work/input.sql" ]]
        else
            [[ "$(package_basename)" == *-re-qa-qa_db* ]]
        fi
        OUTPUT_DIR="$work/out-$mode"; build_package
        dpkg-deb -x "$OUTPUT_DIR/$(package_basename).deb" "$work/payload-$mode"
        dpkg-deb -e "$OUTPUT_DIR/$(package_basename).deb" "$work/control-$mode"
        write_last_build_script
        grep -q -- '--database qa_db' "$work/create-claster-deb-last.sh"
        bash "$work/create-claster-deb-last.sh"
    )
    payload="$work/payload-$mode/usr/local/share/pg_claster_creator"
    sed "s|readonly creator_dir=.*|readonly creator_dir=\"$payload\"|; s|readonly state_dir=.*|readonly state_dir=\"$work/state-$mode\"|" "$work/control-$mode/postinst" >"$work/postinst-$mode"
    cat >"$payload/create-claster.sh" <<'SH'
#!/usr/bin/env bash
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    source "$QA_SQL_WORK/real-creator.sh"
    trap - EXIT
    cluster_pg_home() { printf '%s' "$QA_SQL_WORK"; }
    cluster_socket_directory() { printf /tmp; }
    create_database() { touch "$QA_SQL_WORK/db"; echo CREATE_DB >>"$QA_SQL_WORK/events"; }
    return
fi
case "$PGCC_ACTION" in
    install) touch "$QA_SQL_WORK/cluster"; echo INSTALL >>"$QA_SQL_WORK/events" ;;
    delete) [[ ! -e "$QA_SQL_WORK/fail-delete" ]] || exit 1; rm -f "$QA_SQL_WORK/cluster" "$QA_SQL_WORK/db"; echo DELETE >>"$QA_SQL_WORK/events" ;;
    restore) echo RESTORE >>"$QA_SQL_WORK/events" ;;
    *) exit 1 ;;
esac
SH
    chmod +x "$payload/create-claster.sh"
done
cat >"$work/bin/pg_lsclusters" <<'SH'
#!/usr/bin/env bash
[[ ! -e "$QA_SQL_WORK/fail-registry" ]] || exit 1
echo '17 qa 5555 online postgres /other/data /other/log'
[[ ! -e "$QA_SQL_WORK/cluster" ]] || echo "18 qa 59435 ${QA_STATUS:-online} postgres /fixture/data /fixture/log"
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
    [[ ! -e "$QA_SQL_WORK/fail-connection" ]] || exit 2
    if [[ -e "$QA_SQL_WORK/db" ]]; then echo 1; fi
else
    [[ "$*" == *'-p 59435'* && "$*" == *'-d qa_db'* && "$*" == *'ON_ERROR_STOP=1'* ]] || exit 1
    cmp - "$QA_SQL_WORK/input.sql" || exit 1
    echo SQL >>"$QA_SQL_WORK/events"
    [[ ! -e "$QA_SQL_WORK/fail-sql" ]] || exit 3
fi
SH
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
: >"$work/events"
for missing in cluster db; do
    [[ "$missing" != db ]] || touch "$work/cluster"
    bash "$work/postinst-6" configure
    [[ ! -s "$work/events" ]]
    [[ -z "$(find "$work/state-6" -type f)" ]]
done
touch "$work/db" "$work/fail-connection"
if bash "$work/postinst-6" configure; then exit 1; fi
rm "$work/fail-connection"
if QA_STATUS=down bash "$work/postinst-6" configure; then exit 1; fi
touch "$work/fail-registry"
if bash "$work/postinst-6" configure; then exit 1; fi
rm "$work/fail-registry"
if CLASTER_FORCE_INSTALL=1 bash "$work/postinst-6" configure; then exit 1; fi
touch "$work/fail-sql"
if bash "$work/postinst-6" configure; then exit 1; fi
[[ -z "$(find "$work/state-6" -name '*.done')" ]]
rm "$work/fail-sql"
if bash "$work/postinst-6" configure; then exit 1; fi
[[ "$(wc -l <"$work/events")" == 1 ]]
rm "$work/state-6/"*.sql-started
bash "$work/postinst-6" configure
bash "$work/postinst-6" configure
[[ "$(wc -l <"$work/events")" == 2 ]]
printf 'PASS mode6 missing cluster/DB, actual port, errors, no replay, repeat and no destructive actions\n'
for mode in 4 5; do
    : >"$work/events"; touch "$work/cluster" "$work/db" "$work/fail-delete"
    if bash "$work/postinst-$mode" configure; then exit 1; fi
    [[ ! -s "$work/events" ]]
    rm "$work/fail-delete"
    bash "$work/postinst-$mode" configure
    [[ "$(head -n 2 "$work/events")" == $'DELETE\nINSTALL' ]]
    before="$(wc -l <"$work/events")"
    bash "$work/postinst-$mode" configure
    [[ "$(wc -l <"$work/events")" == "$before" ]]
    rm -f "$work/state-$mode/"* "$work/cluster" "$work/db"
    : >"$work/events"
    bash "$work/postinst-$mode" configure
    [[ "$(head -n 1 "$work/events")" == INSTALL ]]
    ! grep -q DELETE "$work/events"
    printf 'PASS mode%s replacement order, absent exact target, other major preserved, repeat and deletion failure\n' "$mode"
done
(
    source "$work/real-creator.sh"; trap - EXIT
    cluster_pg_home() { printf '%s' "$QA_SQL_WORK"; }
    cluster_socket_directory() { printf /tmp; }
    PGCC_SQL_FILE=bad PGCC_IF_MISSING=error
    parse_args --action sql --pg-version 18 --cluster-name qa --database qa_db --sql-file "$work/input.sql" --if-missing skip
    apply_runtime_options
    [[ "$SQL_FILE" == "$work/input.sql" && "$SQL_IF_MISSING" == skip ]]
    execute_sql_noninteractive
    rm "$work/cluster"
    execute_sql_noninteractive
    SQL_IF_MISSING=error
    if execute_sql_noninteractive; then exit 1; fi
)
printf 'PASS SQL CLI/ENV precedence, strict and skip policies\n'
(
    source "$work/builder.sh"; trap - EXIT
    PGCC_MODE=6 PGCC_PG_VERSION=18 PGCC_CLUSTER_NAME=qa PGCC_DATABASE=qa_db PGCC_SQL_FILE="$work/input.sql" PGCC_INTERACTIVE=no
    parse_args
    validate_options
    [[ "$MODE" == 6 && "$DATABASE_NAME" == qa_db && "$SQL_FILE" == "$work/input.sql" && "$INTERACTIVE_MODE" == no ]]
)
printf 'PASS mode6 wizard and ENV-only options\n'
