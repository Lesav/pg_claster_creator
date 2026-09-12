#!/usr/bin/env bash
# Purpose: additional live negative/postinst tests using the core runner's isolated context.
# Usage: tools/prx-test-live-regression.sh REPO DISTRO PG_VERSION PACKAGE FAMILY PORT RELEASE LOG_ROOT extra
# Args: sourced module; all parameters come from prx-test-live-regression.sh.
# Output: live-extra logs/results; no source-cluster or server-package removal.
# Example: see prx-test-live-regression.sh, append extra.
sql() { runuser -u postgres -- psql --cluster "$v/$1" -X --set=ON_ERROR_STOP=1 --dbname "$2" -Atqc "$3"; }
query="SELECT count(*), md5(string_agg(id::text || ':' || payload || ':' || qty::text, ',' ORDER BY id)) FROM ONLY pgcc_owner.parent_control"
hot="$(find "$core_work/backups" -maxdepth 1 -name '*-dmp.tar.gz' -print -quit)"
cold="$(find "$core_work/backups" -maxdepth 1 -name "$v-$core_c-????????-??????.tar.gz" -print -quit)"
[[ -n "$hot" && -n "$cold" ]]
step EXTRA-SOURCE 0 timeout -k 5 900 "$creator" --action restore --backup-file "$cold" --cluster-name "$c" --port "$port" --backup-dir "$backup"
baseline="$(sql "$c" "$core_c" "$query")"
step NONROOT-ADMIN nonzero timeout -k 2 15 runuser -u nobody -- "$creator" --action info
step DUPLICATE-INSTALL nonzero timeout -k 5 120 "$creator" --action install --package "$package" --cluster-name "$c" --port "$port" --backup-dir "$backup"
step INVALID-PORT nonzero timeout -k 5 60 "$creator" --action port --pg-version "$v" --cluster-name "$c" --port 0
step MISSING-ARCHIVE nonzero timeout -k 5 60 "$creator" --action restore --backup-file "$backup/missing.tar.gz"
for invalid in 0 BAD; do
    step "INVALID-RETENTION-$invalid" nonzero timeout -k 5 60 "$wrapper" "$v" "$c" "$core_c" --backup-dir "$work/rotation" --files-cnt "$invalid"
done
step BOTH-RETENTION nonzero timeout -k 5 60 "$wrapper" "$v" "$c" "$core_c" --backup-dir "$work/rotation" --files-cnt 2 --files-size 1MiB
# Access-denied simulation uses /proc: do not fill the host filesystem to provoke ENOSPC.
step BACKUP-UNWRITABLE nonzero timeout -k 5 60 "$creator" --action backup --pg-version "$v" --cluster-name "$c" --backup-type hot --database "$core_c" --backup-dir /proc/pgcc-test-unwritable
step DOWN-STOP 0 timeout -k 5 60 pg_ctlcluster --skip-systemctl-redirect "$v" "$c" stop
step DOWN-COLD 0 timeout -k 5 900 bash "$repo/tools/prx-test-postgres-backups.sh" "$v" "$c" cold "$core_c" "$backup" "$creator"
step DOWN-PRESERVED 0 test "$(pg_lsclusters --no-header | awk -v n="$c" '$2==n {print $4}')" = down
step DOWN-START 0 timeout -k 5 60 pg_ctlcluster --skip-systemctl-redirect "$v" "$c" start
step SOURCE-CHECK 0 test "$(sql "$c" "$core_c" "$query")" = "$baseline"
# Exercise the actual menu and real services, not the isolated dispatch fixture.
menu_input() { printf '%s\n' "$1" | timeout -k 5 180 "$creator"; }
state() { pg_lsclusters --no-header | awk -v n="$c" '$2==n {print $4}'; }
step POWER-CANCEL 0 menu_input "$(printf '3\n%s\nn\n0\n' "$c")"
step POWER-CANCEL-STATE 0 test "$(state)" = online
step POWER-STOP 0 menu_input "$(printf '3\n%s\ny\n\n0\n' "$c")"
step POWER-DOWN 0 test "$(state)" = down
step POWER-START 0 menu_input "$(printf '3\n%s\ny\n\n0\n' "$c")"
step POWER-ONLINE 0 test "$(state)" = online
step POWER-SQL 0 test "$(sql "$c" "$core_c" "$query")" = "$baseline"
# Restore via a file symlink in a separate directory; never replace the shared backup link.
mkdir "$work/links"
ln -s "$hot" "$work/links/${hot##*/}"
step SYMLINK-HOT 0 timeout -k 5 900 "$creator" --action restore --backup-file "$work/links/${hot##*/}" --pg-version "$v" --cluster-name "$c" --database qa_links --backup-dir "$backup"
step SYMLINK-CHECK 0 test "$(sql "$c" qa_links "$query")" = "$baseline"
schema_fingerprint() {
    runuser -u postgres -- pg_dump --cluster "$v/$c" --dbname "$1" --schema-only --no-comments | sed '/^\\restrict /d; /^\\unrestrict /d' | sha256sum
}
step SCHEMA-ACL-COMPARE 0 test "$(schema_fingerprint "$core_c")" = "$(schema_fingerprint qa_links)"
data_fingerprint() {
    runuser -u postgres -- pg_dump --cluster "$v/$c" --dbname "$1" --data-only --no-comments | sed '/^\\restrict /d; /^\\unrestrict /d' | sha256sum
}
step ALL-ROWS-SEQUENCE-COMPARE 0 test "$(data_fingerprint "$core_c")" = "$(data_fingerprint qa_links)"
step LOGIN-RESTORED 0 env PGPASSWORD=Pgcc-ACL-2.1.1! psql --cluster "$v/$c" -h 127.0.0.1 -p "$port" -U pgcc_acl_login -d qa_links -X -Atqc 'SELECT count(*) FROM pgcc_owner.parent_control'
roles_query="SELECT rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls FROM pg_roles WHERE rolname LIKE 'pgcc_%' ORDER BY rolname"
step ROLE-INVENTORY 0 sql "$c" qa_links "$roles_query"
# Add sentinels to a private rotation directory and verify they survive.
mkdir "$work/rotation"
printf sentinel >"$work/rotation/99-otherdb-20000101-000000-dmp.tar.gz"
printf sentinel >"$work/rotation/keep.txt"
for n in 1 2 3; do
    step "COUNT-$n" 0 timeout -k 5 900 "$wrapper" "$v" "$c" "$core_c" --backup-dir "$work/rotation" --files-cnt 2
    sleep 1
done
step COUNT-LIMIT 0 test "$(find "$work/rotation" -name "$v-$core_c-*-dmp.tar.gz" | wc -l)" = 2
step SENTINEL 0 test "$(cat "$work/rotation/99-otherdb-20000101-000000-dmp.tar.gz")" = sentinel
step OTHER-FILE 0 test "$(cat "$work/rotation/keep.txt")" = sentinel
step SIZE-LIMIT 0 timeout -k 5 900 "$wrapper" "$v" "$c" "$core_c" --backup-dir "$work/rotation" --files-size 1B
step SIZE-COUNT 0 test "$(find "$work/rotation" -name "$v-$core_c-*-dmp.tar.gz" | wc -l)" = 1
step SIZE-SENTINEL 0 test "$(cat "$work/rotation/99-otherdb-20000101-000000-dmp.tar.gz")" = sentinel
mkdir "$work/debs"
for mode in 2 3 4; do
    target="${c}m$mode"
    args=(--mode "$mode" --non-interactive --pg-family "$family" --pg-version "$v" --package "$package" --cluster-name "$target" --port "$((port+mode+1))" --output-dir "$work/debs" --data-root "$data_root")
    case "$mode" in
        2) args+=(--schema pgcc_owner --user pgcc_user --password 'Pgcc-QA-2.1.1!') ;;
        3) args+=(--backup-file "$cold") ;;
        4) args+=(--backup-file "$hot" --database qa_m4 --schema pgcc_owner --user pgcc_user --password 'Pgcc-QA-2.1.1!') ;;
    esac
    step "BUILD-$mode" 0 timeout -k 5 900 bash "$builder" "${args[@]}"
    deb="$(find "$work/debs" -name "*-$target-*.deb" -print -quit)"
    touch "$work/deployed-mode"
    step "INSTALL-$mode" 0 timeout -k 5 900 env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --reinstall "$deb"
    case "$mode" in 2) db="$target" ;; 3) db="$core_c" ;; 4) db=qa_m4 ;; esac
    step "MUTATE-$mode" 0 sql "$target" "$db" 'CREATE TABLE public.qa_keep(id int); INSERT INTO public.qa_keep VALUES(235)'
    step "REINSTALL-$mode" 0 timeout -k 5 900 env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --reinstall "$deb"
    step "REINSTALL-PRESERVED-$mode" 0 test "$(sql "$target" "$db" 'SELECT id FROM public.qa_keep')" = 235
    step "FORCE-CLUSTER-$mode" 0 timeout -k 5 900 env CLASTER_FORCE_INSTALL=1 DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --reinstall "$deb"
    step "FORCE-RESET-$mode" 0 test "$(sql "$target" "$db" "SELECT to_regclass('public.qa_keep') IS NULL")" = t
    if [[ "$mode" != 2 ]]; then step "FORCE-FULL-$mode" 0 verify_reference "$target" "$db"; fi
    if [[ "$mode" == 4 ]]; then
        identifier="$(sql "$target" "$db" 'SELECT system_identifier FROM pg_control_system()')"
        step FORCE-DB-MUTATE 0 sql "$target" "$db" 'CREATE TABLE public.qa_force_stale(id int); UPDATE pgcc_owner.parent_control SET qty=qty+10'
        step FORCE-DB-NEIGHBOR 0 sql "$target" postgres 'CREATE TABLE public.qa_neighbor(id int); INSERT INTO public.qa_neighbor VALUES(242)'
        step FORCE-DB 0 timeout -k 5 900 env CLASTER_FORCE_DB_INSTALL=1 DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --reinstall "$deb"
        step FORCE-DB-CLUSTER-PRESERVED 0 test "$(sql "$target" "$db" 'SELECT system_identifier FROM pg_control_system()')" = "$identifier"
        step FORCE-DB-CHECK 0 test "$(sql "$target" "$db" "$query")" = "$baseline"
        step FORCE-DB-FULL 0 verify_reference "$target" "$db"
        step FORCE-DB-STALE-ABSENT 0 test "$(sql "$target" "$db" "SELECT to_regclass('public.qa_force_stale') IS NULL")" = t
        step FORCE-DB-NEIGHBOR-PRESERVED 0 test "$(sql "$target" postgres 'SELECT id FROM public.qa_neighbor')" = 242
        step BOTH-FORCE-REJECT nonzero timeout -k 5 120 env CLASTER_FORCE_INSTALL=1 CLASTER_FORCE_DB_INSTALL=1 DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --reinstall "$deb"
    fi
done
printf 'EXTENDED COMPLETED\n'
