#!/usr/bin/env bash
# Purpose: extend the existing live runner with real explicit-config propagation.
# Also checks real count/size ENV overrides, generated cron without inherited ENV,
# and fresh mode2/4 data roots. Rotation seeds are copies of this run's valid dump.
# Usage: PGCC_LIVE_EXTENSION=tools/prx-test-live-config-env.sh bash tools/prx-test-live-regression.sh REPO DISTRO MAJOR PACKAGE FAMILY PORT RELEASE LOG_ROOT extension
# Args: inherited validated parent context; no independent invocation.
# Output: parent logs and owned artifacts; parent deletes its QA clusters.
# Example: use an isolated LOG_ROOT and the extension phase after the main run.
# No fixed workspace path is required; paths come from the parent runner.
sql() { runuser -u postgres -- psql --cluster "$v/$1" -X --set=ON_ERROR_STOP=1 --dbname "$2" -Atqc "$3"; }
config="$work/preferred config.cfg"
cp -a "$work/config-shared" "$config"
printf '\nbackup_dir=%q\n' "$backup" >>"$config"
step CONFIG-CLI-OVER-ENV 0 timeout -k 5 900 env PGCC_CFG="$work/missing.cfg" "$creator" --config "$config" --action install --package "$package" --pg-version "$v" --cluster-name "$c" --port "$port" --schema pgcc_owner --user pgcc_user --password 'Pgcc-QA-config!'
step CONFIG-CREATE-DATA 0 sql "$c" "$c" 'CREATE TABLE public.config_probe(id integer PRIMARY KEY); INSERT INTO public.config_probe VALUES (42)'
config_defaults() { ( source "$1"; printf '%s\0' "$cls_nm" "$cls_pt" "$cls_ch" "$cls_us" "$cls_pw" ) | sha256sum; }
expected_defaults="$(config_defaults "$work/config-shared")"
step CONFIG-DEFAULTS-PRESERVED 0 test "$(config_defaults "$config")" = "$expected_defaults"
step CONFIG-SYSTEM-UNSELECTED 0 cmp "$work/config-shared" /usr/local/shared/pg_claster_creator/.new-claster.config
step WRAPPER-ENV-CONFIG 0 timeout -k 5 180 env PGCC_CFG="$config" PGCC_PG_VERSION="$v" PGCC_CLUSTER_NAME="$c" PGCC_DATABASE="$c" PGCC_FILES_CNT=2 "$wrapper"
hot="$(find "$backup" -maxdepth 1 -type f -name '*-dmp.tar.gz' -print -quit)"
step WRAPPER-ENV-ARCHIVE 0 test -s "$hot"
mkdir "$backup/override"
step WRAPPER-CLI-OVER-ENV 0 timeout -k 5 180 env PGCC_CFG="$work/missing.cfg" PGCC_PG_VERSION=999 PGCC_CLUSTER_NAME=wrong PGCC_DATABASE=wrong PGCC_BACKUP_DIR="$work/wrong" PGCC_FILES_CNT=9 "$wrapper" --config "$config" "$v" "$c" "$c" --backup-dir "$backup/override" --files-cnt 1
step WRAPPER-CLI-ARCHIVE 0 test "$(find "$backup/override" -type f -name '*-dmp.tar.gz' | wc -l)" = 1
step WRAPPER-NO-WRONG-DIR 0 test ! -e "$work/wrong"
# Distinguish retention limits using identical, valid archives with older names.
# Each directory is new and private to this run; foreign masks must survive.
seed_rotation() {
    rotation="$backup/$1"
    mkdir "$rotation"
    for n in 1 2 3 4 5; do
        cp -- "$hot" "$rotation/$v-$c-20000101-00000$n-dmp.tar.gz"
    done
    cp -- "$hot" "$rotation/999-$c-20000101-000001-dmp.tar.gz"
    printf 'keep\n' >"$rotation/sentinel.txt"
}
rotation_count() { find "$rotation" -maxdepth 1 -type f -name "$v-$c-????????-??????-dmp.tar.gz" | wc -l; }
for variant in count-env count-cli size-env size-cli; do
    seed_rotation "$variant"
    case "$variant" in
        count-env)
            step ROTATE-COUNT-ENV 0 timeout -k 5 180 env PGCC_CFG="$config" PGCC_BACKUP_DIR="$rotation" PGCC_FILES_CNT=3 "$wrapper" "$v" "$c" "$c"
            step ROTATE-COUNT-ENV-THREE 0 test "$(rotation_count)" = 3
            step ROTATE-COUNT-ENV-NEWEST-OLD 0 test -f "$rotation/$v-$c-20000101-000005-dmp.tar.gz"
            step ROTATE-COUNT-ENV-SECOND-OLD 0 test -f "$rotation/$v-$c-20000101-000004-dmp.tar.gz"
            ;;
        count-cli)
            step ROTATE-COUNT-CLI 0 timeout -k 5 180 env PGCC_CFG="$config" PGCC_BACKUP_DIR="$rotation" PGCC_FILES_CNT=9 "$wrapper" "$v" "$c" "$c" --files-cnt 1
            step ROTATE-COUNT-CLI-ONE 0 test "$(rotation_count)" = 1
            ;;
        size-env)
            step ROTATE-SIZE-ENV 0 timeout -k 5 180 env PGCC_CFG="$config" PGCC_BACKUP_DIR="$rotation" PGCC_FILES_SIZE=1B "$wrapper" "$v" "$c" "$c"
            step ROTATE-SIZE-ENV-NEWEST 0 test "$(rotation_count)" = 1
            ;;
        size-cli)
            step ROTATE-SIZE-CLI 0 timeout -k 5 180 env PGCC_CFG="$config" PGCC_BACKUP_DIR="$rotation" PGCC_FILES_SIZE=1B "$wrapper" "$v" "$c" "$c" --files-size 1GiB
            step ROTATE-SIZE-CLI-ALL 0 test "$(rotation_count)" = 6
            ;;
    esac
    step "ROTATE-FOREIGN-$variant" 0 cmp "$hot" "$rotation/999-$c-20000101-000001-dmp.tar.gz"
    step "ROTATE-SENTINEL-$variant" 0 grep -qx keep "$rotation/sentinel.txt"
done
step MAIN-ENV-CONFIG-RESTORE 0 timeout -k 5 180 env PGCC_CFG="$config" PGCC_ACTION=restore PGCC_PG_VERSION="$v" PGCC_CLUSTER_NAME="$c" PGCC_DATABASE=config_copy PGCC_BACKUP_FILE="$hot" "$creator"
step MAIN-RESTORED-ROW 0 test "$(sql "$c" config_copy 'SELECT id FROM public.config_probe')" = 42
step MAIN-ENV-CONFIG-COLD 0 timeout -k 5 180 env PGCC_CFG="$config" PGCC_ACTION=backup PGCC_PG_VERSION="$v" PGCC_CLUSTER_NAME="$c" PGCC_BACKUP_TYPE=cold "$creator"
cold="$(find "$backup" -maxdepth 1 -name "$v-$c-????????-??????.tar.gz" -print -quit)"
step MAIN-COLD-ARCHIVE 0 test -s "$cold"
mkdir "$work/debs"
printf 'CREATE TABLE public.config_sql(id integer); INSERT INTO public.config_sql VALUES (42);\n' >"$backup/install.sql"
for mode in 1 2 3 4 5; do
    args=(--config "$config" --mode "$mode" --non-interactive --output-dir "$work/debs")
    if ((mode > 1)); then args+=(--package "$package" --pg-family "$family" --pg-version "$v" --cluster-name "${c}m4" --port "$((port+7))"); fi
    case "$mode" in
        2) args+=(--schema pgcc_owner --user pgcc_user --password 'Pgcc-QA-config!' --data-root "$data_root") ;;
        3) args+=(--backup-file "$cold") ;;
        4) args+=(--backup-file "$hot" --database config_m4 --schema pgcc_owner --user pgcc_user --password 'Pgcc-QA-config!' --data-root "$data_root") ;;
        5) args+=(--sql-file "$backup/install.sql" --database config_m5 --schema pgcc_owner --user pgcc_user --password 'Pgcc-QA-config!') ;;
    esac
    step "BUILDER-CONFIG-$mode" 0 timeout -k 5 180 env PGCC_CFG="$work/missing.cfg" bash "$builder" "${args[@]}"
    deb="$(find "$work/debs" -maxdepth 1 -type f -name '*.deb' -print -quit)"
    mkdir "$work/unpack-$mode"
    step "PAYLOAD-EXTRACT-$mode" 0 dpkg-deb -x "$deb" "$work/unpack-$mode"
    step "PAYLOAD-CONFIG-$mode" 0 cmp "$config" "$work/unpack-$mode/usr/local/share/pg_claster_creator/.new-claster.config"
    step "PAYLOAD-SOURCE-$mode" 0 cmp "$repo/create-claster.sh" "$work/unpack-$mode/usr/local/share/pg_claster_creator/create-claster.sh"
    mv "$deb" "$work/mode-$mode.deb"
done
step CONFIG-SYSTEM-STILL-UNSELECTED 0 cmp "$work/config-shared" /usr/local/shared/pg_claster_creator/.new-claster.config
# Exercise the newly built scripts-only DEB, not just a previously released DEB.
touch "$work/deployed-mode"
for attempt in 1 2; do
    step "CONFIG-MODE1-INSTALL-$attempt" 0 timeout -k 5 900 env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --reinstall "$work/mode-1.deb"
    step "CONFIG-MODE1-SOURCE-$attempt" 0 cmp "$repo/create-claster.sh" /usr/local/share/pg_claster_creator/create-claster.sh
    step "CONFIG-MODE1-DATA-$attempt" 0 test "$(sql "$c" "$c" 'SELECT id FROM public.config_probe')" = 42
done
mv "$config" "$work/config-offline"
touch "$work/deployed-mode"
step CONFIG-ABSENT-AT-DEPLOY 0 timeout -k 5 900 env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y "$work/mode-5.deb"
step CONFIG-DEPLOYED-SQL 0 test "$(sql "${c}m4" config_m5 'SELECT id FROM public.config_sql')" = 42
step CONFIG-DEPLOYED-SOURCE 0 cmp "$repo/create-claster.sh" /usr/local/share/pg_claster_creator/create-claster.sh
mv "$work/config-offline" "$config"
# Run the exact generated cron command with no inherited PGCC variables.
mkdir "$backup/cron"
hash="$(printf '%s\0%s\0%s' "$v" "$c" "$c" | cksum | awk '{print $1}')"
job_id="$v-$c-$c-$hash"
cron="/etc/cron.d/pg-claster-backup-$job_id"
cron_log="/var/log/pg-claster-backup-$job_id.log"
[[ ! -e "$cron" && ! -e "$cron_log" ]]
cleanup_ui_artifacts() {
    rm -f -- "$cron"
    if [[ -f "$cron_log" ]]; then
        sed -E '/(PASSWORD |PGPASSWORD=|password_hash=)/I s/.*/[REDACTED]/' "$cron_log" >"$logs/config-cron-execution.log"
        rm -- "$cron_log"
    fi
}
printf -v cron_setup 'env PGCC_CFG=%q PGCC_PG_VERSION=%q PGCC_CLUSTER_NAME=%q PGCC_DATABASE=%q PGCC_BACKUP_DIR=%q PGCC_FILES_CNT=1 PGCC_CRON=yes %q' "$config" "$v" "$c" "$c" "$backup/cron" "$wrapper"
step CONFIG-ENV-CRON-CREATE 0 script -q -e -c "$cron_setup" /dev/null <<<$'4\ny'
cp "$cron" "$logs/config-cron-task.txt"
step CONFIG-CRON-EXPLICIT 0 grep -F -- --config "$cron"
cron_command="$(sed -n 's/^.* root //p' "$cron")"
[[ "$cron_command" == /usr/local/bin/create-claster-backup.sh* ]]
for attempt in 1 2; do
    step "CONFIG-CRON-CLEAN-ENV-$attempt" 0 timeout -k 5 180 env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C bash -c "$cron_command" </dev/null
    sleep 1
done
step CONFIG-CRON-ROTATION 0 test "$(find "$backup/cron" -type f -name '*-dmp.tar.gz' | wc -l)" = 1
cron_hot="$(find "$backup/cron" -type f -name '*-dmp.tar.gz' -print -quit)"
step CONFIG-CRON-RESTORE 0 timeout -k 5 180 "$creator" --config "$config" --action restore --backup-file "$cron_hot" --pg-version "$v" --cluster-name "$c" --database config_cron
step CONFIG-CRON-ROW 0 test "$(sql "$c" config_cron 'SELECT id FROM public.config_probe')" = 42
cleanup_ui_artifacts
step CONFIG-DELETE-MODE5 0 timeout -k 5 180 "$creator" --action delete "$v" "${c}m4" --backup-before-delete no
for mode in 2 4; do
    step "ROOT-ABSENT-BEFORE-$mode" 0 test ! -e "$data_root"
    step "FRESH-ROOT-INSTALL-$mode" 0 timeout -k 5 900 env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y "$work/mode-$mode.deb"
    step "FRESH-ROOT-DATA-$mode" 0 test "$(sql "${c}m4" postgres 'SHOW data_directory')" = "$data_root/pg_$v/${c}m4"
    if ((mode == 4)); then step FRESH-ROOT-RESTORE-ROW 0 test "$(sql "${c}m4" config_m4 'SELECT id FROM public.config_probe')" = 42; fi
    step "FRESH-ROOT-DELETE-$mode" 0 timeout -k 5 180 "$creator" --action delete "$v" "${c}m4" --backup-before-delete no
    [[ ! -d "$data_root/pg_$v" ]] || rmdir "$data_root/pg_$v"
    [[ ! -d "$data_root" ]] || rmdir "$data_root"
done
printf 'EXPLICIT CONFIG LIVE CHECKS COMPLETE\n'
