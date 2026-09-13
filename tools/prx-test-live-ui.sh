#!/usr/bin/env bash
# Purpose: extend the live runner with real rename, ENV, cron and database deletion.
# Usage: tools/prx-test-live-regression.sh REPO DISTRO PG_VERSION PACKAGE FAMILY PORT RELEASE LOG_ROOT ui|tail
# Args: sourced module; all parameters come from prx-test-live-regression.sh.
# Output: per-step parent evidence; only the parent's disposable targets are changed.
# Example: see prx-test-live-regression.sh, append ui or tail.
sql() { runuser -u postgres -- psql --cluster "$v/$1" -X --set=ON_ERROR_STOP=1 --dbname "$2" -Atqc "$3"; }
cold="$(find "$core_backup" -maxdepth 1 -name "$v-$core_c-????????-??????.tar.gz" -print -quit)"
[[ -n "$cold" ]]
step UI-SOURCE 0 timeout -k 5 900 "$creator" --action restore --backup-file "$cold" --cluster-name "$c" --port "$port" --backup-dir "$backup"
query="SELECT count(*), md5(string_agg(id::text || ':' || payload || ':' || qty::text, ',' ORDER BY id)) FROM ONLY pgcc_owner.parent_control"
baseline="$(sql "$c" "$core_c" "$query")"
menu_input() { printf '%s\n' "$1" | timeout -k 5 180 env PGCC_BACKUP_DIR="$backup" "$creator"; }
index() { pg_lsclusters --no-header | awk -v n="$1" '$2==n {print NR}'; }
state() { pg_lsclusters --no-header | awk -v n="$1" '$2==n {print $4}'; }
if [[ "$phase" == ui ]]; then
step RENAME-CANCEL 0 menu_input "$(printf '4\n1\n%s\n0\n0\n0\n' "$(index "$c")")"
step RENAME-CANCEL-STATE 0 test "$(state "$c")" = online
step RENAME-ONLINE 0 menu_input "$(printf '4\n1\n%s\n%sren\ny\n\n0\n0\n' "$(index "$c")" "$c")"
step RENAMED-ONLINE 0 test "$(state "${c}ren")" = online
step RENAMED-SQL 0 test "$(sql "${c}ren" "$core_c" "$query")" = "$baseline"
step RENAMED-FULL 0 verify_reference "${c}ren" "$core_c"
step RENAMED-STOP 0 menu_input "$(printf '3\n%sren\ny\n\n0\n' "$c")"
step RENAME-DOWN 0 menu_input "$(printf '4\n1\n%s\n%s\ny\n\n0\n0\n' "$(index "${c}ren")" "$c")"
step RENAMED-DOWN 0 test "$(state "$c")" = down
else
    # Independent continuation after a recorded rename failure; not a rename PASS.
    step TAIL-STOP 0 menu_input "$(printf '3\n%s\ny\n\n0\n' "$c")"
    step TAIL-DOWN 0 test "$(state "$c")" = down
fi
step ENV-PORT-DOWN 0 timeout -k 5 120 env PGCC_ACTION=port PGCC_PG_VERSION="$v" PGCC_CLUSTER_NAME="$c" PGCC_CLUSTER_PORT="$((port+60))" "$creator"
step ENV-PORT-STATE 0 test "$(state "$c")" = down
step ENV-MOVE-DOWN 0 timeout -k 5 180 env PGCC_ACTION=move-data PGCC_PG_VERSION="$v" PGCC_CLUSTER_NAME="$c" PGCC_DATA_ROOT="$data_root" "$creator"
step ENV-MOVE-STATE 0 test "$(state "$c")" = down
step RENAMED-START 0 menu_input "$(printf '3\n%s\ny\n\n0\n' "$c")"
step RENAMED-DATA 0 test "$(sql "$c" "$core_c" "$query")" = "$baseline"
step ENV-INFO 0 env PGCC_ACTION=info "$creator"
mkdir "$backup/cron-backups"
hash="$(printf '%s\0%s\0%s' "$v" "$c" "$core_c" | cksum | awk '{print $1}')"
job_id="$v-$c-$core_c-$hash"
cron="/etc/cron.d/pg-claster-backup-$job_id"
cron_log="/var/log/pg-claster-backup-$job_id.log"
[[ ! -e "$cron" && ! -e "$cron_log" ]]
cleanup_ui_artifacts() {
    [[ "$cron" == /etc/cron.d/pg-claster-backup-"$v"-"$c"-* ]] || return 1
    rm -f -- "$cron"
    if [[ -f "$cron_log" ]]; then
        sed -E '/(PASSWORD |PGPASSWORD=|password_hash=)/I s/.*/[REDACTED]/' "$cron_log" >"$logs/generated-cron-command.log"
        rm -f -- "$cron_log"
    fi
}
step CRON-CREATE 0 script -q -e -c "$wrapper $v $c $core_c --backup-dir $backup/cron-backups --files-cnt 1 --cron" /dev/null <<<$'4\ny'
cp "$cron" "$logs/cron-task.txt"
cron_command="$(sed -n 's/^.* root //p' "$cron")"
[[ "$cron_command" == /usr/local/bin/create-claster-backup.sh* ]]
for attempt in 1 2; do
    step "CRON-EXECUTE-$attempt" 0 timeout -k 5 180 bash -c "$cron_command" </dev/null
    sleep 1
done
step CRON-ROTATION 0 test "$(find "$backup/cron-backups" -name '*-dmp.tar.gz' | wc -l)" = 1
hot="$(find "$backup/cron-backups" -name '*-dmp.tar.gz' -print -quit)"
step ENV-RESTORE 0 timeout -k 5 180 env PGCC_ACTION=restore PGCC_PG_VERSION="$v" PGCC_CLUSTER_NAME="$c" PGCC_DATABASE=qa_cron PGCC_BACKUP_FILE="$hot" PGCC_BACKUP_DIR="$backup" "$creator"
step CRON-RESTORE-SQL 0 test "$(sql "$c" qa_cron "$query")" = "$baseline"
fingerprint() { runuser -u postgres -- pg_dump --cluster "$v/$c" -d "$1" --no-comments | sed '/^\\restrict /d; /^\\unrestrict /d' | sha256sum; }
step CRON-RESTORE-FULL 0 test "$(fingerprint "$core_c")" = "$(fingerprint qa_cron)"
step CRON-LOGIN 0 env PGPASSWORD=Pgcc-ACL-2.1.1! psql --cluster "$v/$c" -h 127.0.0.1 -p "$((port+60))" -U pgcc_acl_login -d qa_cron -X -Atqc 'SELECT count(*) FROM pgcc_owner.parent_control'
cleanup_ui_artifacts
mkdir "$backup/real-backups"
ln -s "$backup/real-backups" "$work/backup-link"
step ENV-HOT-DIRLINK 0 timeout -k 5 180 env PGCC_ACTION=backup PGCC_PG_VERSION="$v" PGCC_CLUSTER_NAME="$c" PGCC_DATABASE="$core_c" PGCC_BACKUP_TYPE=hot PGCC_BACKUP_DIR="$work/backup-link" "$creator"
step DB-DELETE-CANCEL 0 menu_input "$(printf '7\n2\n%s\nqa_cron\nn\nn\n\n0\n' "$(index "$c")")"
step DB-CANCEL-PRESERVED 0 test "$(sql "$c" qa_cron "$query")" = "$baseline"
step DB-DELETE-HOT 0 menu_input "$(printf '7\n2\n%s\nqa_cron\n\ny\n\n0\n' "$(index "$c")")"
step DB-ABSENT 0 test "$(sql "$c" postgres "SELECT count(*) FROM pg_database WHERE datname='qa_cron'")" = 0
step NEIGHBOR-DB-PRESERVED 0 test "$(sql "$c" "$core_c" "$query")" = "$baseline"
step ENV-DELETE 0 timeout -k 5 180 env PGCC_ACTION=delete PGCC_PG_VERSION="$v" PGCC_CLUSTER_NAME="$c" PGCC_BACKUP_BEFORE_DELETE=no "$creator"
step ENV-DELETE-ABSENT 0 test "$(state "$c")" = ''
step COLD-AFTER-DELETE 0 timeout -k 5 180 "$creator" --action restore --backup-file "$cold" --cluster-name "$c" --port "$port" --data-root "$data_root" --backup-dir "$backup"
step COLD-AFTER-DELETE-SQL 0 test "$(sql "$c" "$core_c" "$query")" = "$baseline"
step COLD-AFTER-DELETE-FULL 0 verify_reference "$c" "$core_c"
printf 'UI/ENV/CRON COMPLETED\n'
