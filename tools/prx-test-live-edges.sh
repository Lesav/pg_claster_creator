#!/usr/bin/env bash
# Purpose: test additional restore/info/ENV-install edges in the existing owned live context.
# Usage: PGCC_LIVE_EXTENSION=REPO/tools/prx-test-live-edges.sh bash tools/prx-test-live-regression.sh REPO DISTRO VERSION PACKAGE FAMILY PORT RELEASE LOG_ROOT extension
# Args: sourced module; only the parent runner's QA names, paths and archives are used.
# Output: live-extension evidence; parent cleans QA clusters and restores config.
# Example: PGCC_LIVE_EXTENSION=/repo/tools/prx-test-live-edges.sh bash /repo/tools/prx-test-live-regression.sh /repo Astra 18 tantor-be-server-18 tantor-be 59010 2.4.2 /repo/tmp/run extension
sql() { runuser -u postgres -- psql --cluster "$v/$1" -X --set=ON_ERROR_STOP=1 --dbname "$2" -Atqc "$3"; }
hot="$(find "$core_work/backups" -maxdepth 1 -name '*-dmp.tar.gz' -print -quit)"
cold="$(find "$core_work/backups" -maxdepth 1 -name "$v-$core_c-????????-??????.tar.gz" -print -quit)"
[[ -n "$hot" && -n "$cold" ]]
sha256sum "$hot" "$cold" >"$logs/input-sha.log"
step ENV-INSTALL 0 timeout -k 5 900 env PGCC_ACTION=install PGCC_PACKAGE="$package" PGCC_PG_VERSION="$v" PGCC_CLUSTER_NAME="$c" PGCC_CLUSTER_PORT="$port" PGCC_DATA_ROOT="$data_root" PGCC_SCHEMA=pgcc_owner PGCC_DB_USER=pgcc_user PGCC_DB_PASSWORD=Pgcc-QA-2.1.1! PGCC_BACKUP_DIR="$backup" "$creator"
step ROLES-ABSENT 0 test "$(sql "$c" postgres "SELECT count(*) FROM pg_roles WHERE rolname IN ('pgcc_acl_login','pgcc_alt_owner')")" = 0
ln -s "$hot" "$backup/${hot##*/}"
step HOT-SHORT-NAME 0 timeout -k 5 180 "$creator" --action restore --backup-dir "$backup" --backup-file "${hot##*/}" --pg-version "$v" --cluster-name "$c" --database qa_cross
step HOT-CROSS-FULL 0 verify_reference "$c" qa_cross
pg_before="$(db_fingerprint "$c" postgres)"
step PROTECTED-RESTORE nonzero timeout -k 5 120 "$creator" --action restore --backup-dir "$backup" --backup-file "${hot##*/}" --pg-version "$v" --cluster-name "$c" --database postgres --overwrite yes
step POSTGRES-PRESERVED 0 test "$(db_fingerprint "$c" postgres)" = "$pg_before"
ln -s "$work/absent.tar.gz" "$backup/$v-broken-20260912-010101-dmp.tar.gz"
step BROKEN-LINK nonzero timeout -k 5 60 "$creator" --action restore --backup-dir "$backup" --backup-file "$v-broken-20260912-010101-dmp.tar.gz"
printf invalid >"$backup/$v-corrupt-20260912-010101-dmp.tar.gz"
step CORRUPT-ARCHIVE nonzero timeout -k 5 60 "$creator" --action restore --backup-file "$backup/$v-corrupt-20260912-010101-dmp.tar.gz"
step BAD-ARCHIVES-SOURCE 0 verify_reference "$c" qa_cross
# Preserve exact original members/metadata; never repack an extracted parent tree.
mkdir "$work/legacy"
legacy="$work/legacy/${cold##*/}"
make_legacy() {
    # Refuse the erroneous parent-tree archives from older test attempts.
    # These shared directory entries are not emitted as roots by our backup.
    tar -tzf "$cold" >"$work/original-members" || return
    if grep -Eq '^root/?$|^root/(etc|etc/postgresql|var|var/lib|var/lib/postgresql|var/log|var/log/postgresql|usr|usr/lib|usr/lib/systemd|usr/lib/systemd/system|lib|lib/systemd|lib/systemd/system)/?$' "$work/original-members"; then
        printf 'Refusing repacked archive containing shared parent directory entries\n' >&2
        return 1
    fi
    gzip -dc "$cold" >"$work/legacy.tar" || return
    tar --delete --file "$work/legacy.tar" --wildcards '*.service' || return
    gzip -c "$work/legacy.tar" >"$legacy" || return
    tar -tzf "$cold" | grep -v '\.service$' | LC_ALL=C sort >"$work/expected-members"
    tar -tzf "$legacy" | LC_ALL=C sort >"$work/actual-members"
    cmp "$work/expected-members" "$work/actual-members" || return
    LC_ALL=C tar --full-time -tvzf "$cold" | grep -v '\.service$' >"$logs/legacy-expected-metadata.log"
    LC_ALL=C tar --full-time -tvzf "$legacy" >"$logs/legacy-actual-metadata.log"
    cmp "$logs/legacy-expected-metadata.log" "$logs/legacy-actual-metadata.log"
}
step LEGACY-ARCHIVE 0 make_legacy
parent_metadata() {
    local parent
    for parent in / /etc /etc/postgresql /var /var/lib /var/lib/postgresql /var/log /var/log/postgresql /usr /usr/lib /lib /lib/systemd /lib/systemd/system /usr/lib/systemd /usr/lib/systemd/system /.postgres /.postgres/systemd /.postgres/systemd/save; do
        [[ "$parent" != /var/log/postgresql ]] || continue
        [[ ! -e "$parent" ]] || stat -c '%a %u:%g %n' "$parent"
    done
}
parent_metadata >"$logs/parents-before.log"
stat -c '%a %U:%G %n' /var/log/postgresql >"$logs/log-parent-before.log"
restore_rc=0
step COLD-WITHOUT-UNIT 0 timeout -k 5 900 "$creator" --action restore --backup-file "$legacy" --cluster-name "${c}cold" --port "$((port+1))" --backup-dir "$backup" || restore_rc=$?
parent_metadata >"$logs/parents-after.log"
stat -c '%a %U:%G %n' /var/log/postgresql >"$logs/log-parent-after.log"
step PARENTS-UNCHANGED 0 cmp "$logs/parents-before.log" "$logs/parents-after.log"
((restore_rc == 0)) || exit "$restore_rc"
step LOG-PARENT-PERMISSIONS 0 test "$(stat -c '%a %U:%G' /var/log/postgresql)" = '1775 root:postgres'
step LEGACY-FULL 0 verify_reference "${c}cold" "$core_c"
unit_exists() { [[ -f "/usr/lib/systemd/system/postgresql@$v-${c}cold.service" || -f "/lib/systemd/system/postgresql@$v-${c}cold.service" ]]; }
step LEGACY-UNIT 0 unit_exists
step DELETE-WITH-COLD 0 timeout -k 5 900 "$creator" --action delete "$v" "${c}cold" --backup-before-delete yes --backup-dir "$backup"
step DELETE-NEIGHBOR-FULL 0 verify_reference "$c" qa_cross
step INFO-STOP 0 timeout -k 5 60 pg_ctlcluster --skip-systemctl-redirect "$v" "$c" stop
index="$(pg_lsclusters --no-header | awk -v n="$c" '$2==n {print NR}')"
menu_input() { printf '%s\n' "$1" | timeout -k 5 120 env PGCC_BACKUP_DIR="$backup" "$creator"; }
step INFO-DOWN-MENU 0 menu_input "$(printf '1\n%s\n\n0\n' "$index")"
step INFO-DOWN-STATE 0 test "$(pg_lsclusters --no-header | awk -v n="$c" '$2==n {print $4}')" = down
no_ansi() { ! LC_ALL=C grep -q $'\x1b' "$1"; }
step INFO-DOWN-NO-ANSI 0 no_ansi "$logs/INFO-DOWN-MENU.log"
step FINAL-START 0 timeout -k 5 60 pg_ctlcluster --skip-systemctl-redirect "$v" "$c" start
step FINAL-FULL 0 verify_reference "$c" qa_cross
step INPUTS-UNCHANGED 0 sha256sum -c "$logs/input-sha.log"
