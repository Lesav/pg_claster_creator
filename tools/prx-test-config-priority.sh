#!/usr/bin/env bash
# Path note: If /mnt/d/Ai/pg_claster_creator in the example does not match
# your filesystem, replace it with the actual project path before running.
# Purpose: test CLI/ENV/system/local config priority, validation and save isolation.
# Usage: bash tools/prx-test-config-priority.sh REPO
# Args: REPO -- source directory.
# Output: PASS per script; no changes to system configs or PostgreSQL clusters.
# Example: bash tools/prx-test-config-priority.sh /mnt/d/Ai/pg_claster_creator
set -Eeuo pipefail
unset PGCC_CFG
repo="$1"
fixture="$(mktemp -d /tmp/pgcc-config.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/scripts" "$fixture/bin" "$fixture/cwd" "$fixture/system"
preferred="$fixture/system/.new-claster.config"
local_config="$fixture/scripts/.new-claster.config"
for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh; do
    # Substitute only the fixed system path; do not touch real system files.
    # Suppress builder's unconditional main and exercise its actual load code.
    sed -e "s@/usr/local/shared/pg_claster_creator/.new-claster.config@$preferred@g" \
        -e '/^main "\$@"$/d' "$repo/$name" > "$fixture/scripts/$name"
    ln -s "../scripts/$name" "$fixture/bin/$name"
    printf 'backup_dir=/local\npg=postgresql\npg_ver=16\n' > "$local_config"
    printf 'backup_dir=/wrong-cwd\n' > "$fixture/cwd/.new-claster.config"
    rm -f -- "$preferred"
    (cd "$fixture/cwd"; source "$fixture/bin/$name"; [[ "$CONFIG_FILE" == "$local_config" ]])
    printf 'backup_dir=/system\npg=postgresql\npg_ver=16\n' > "$preferred"
    (
        cd "$fixture/cwd"
        source "$fixture/bin/$name"
        [[ "$CONFIG_FILE" == "$preferred" ]]
        case "$name" in
            create-claster.sh)
                before="$(sha256sum "$local_config")"
                load_config
                [[ "$backup_dir" == /system ]]
                backup_dir=/saved
                save_config
                [[ "$(sha256sum "$local_config")" == "$before" ]]
                grep -q '^export backup_dir=/saved$' "$preferred"
                ;;
            create-claster-backup.sh) [[ "$(configured_backup_dir)" == /system ]] ;;
            create-claster-deb.sh) load_defaults; [[ "$BACKUP_DIR" == /system ]] ;;
        esac
    )
    rm -f -- "$preferred"
    ln -s "$fixture/missing" "$preferred"
    (source "$fixture/bin/$name"; [[ "$CONFIG_FILE" == "$preferred" ]])
    if (source "$fixture/bin/$name"; case "$name" in create-claster-backup.sh) configured_backup_dir ;; create-claster-deb.sh) load_defaults ;; *) load_config ;; esac) >/dev/null 2>&1; then
        printf 'FAIL broken preferred config was accepted: %s\n' "$name"
        exit 1
    fi
    printf 'PASS %s: system priority, local fallback, symlink, cwd independence, broken preferred refusal\n' "$name"
    explicit="$fixture/explicit config"; mkdir -p "$explicit"
    printf 'backup_dir=/env\npg=postgresql\npg_ver=15\n' >"$explicit/env.config"
    printf 'backup_dir=/cli\npg=tantor-be\npg_ver=18\n' >"$explicit/cli.config"
    for input in env cli equals relative; do
        (
            cd "$fixture"
            export PGCC_CFG="$explicit/env.config"
            source "$fixture/bin/$name"
            trap - EXIT
            expected="$explicit/cli.config"
            case "$input" in
                env) expected="$explicit/env.config" ;;
                cli) parse_args --config "$explicit/cli.config" ;;
                equals) parse_args "--config=$explicit/cli.config" ;;
                relative) parse_args --config 'explicit config/cli.config' ;;
            esac
            select_config
            [[ "$CONFIG_FILE" == "$expected" && "$PGCC_CFG" == "$expected" ]]
            case "$name" in
                create-claster.sh)
                    load_config; expected_dir=/cli; [[ "$input" != env ]] || expected_dir=/env
                    [[ "$backup_dir" == "$expected_dir" ]]
                    before_env="$(sha256sum "$explicit/env.config")"
                    before_cli="$(sha256sum "$explicit/cli.config")"
                    save_config
                    if [[ "$input" == env ]]; then [[ "$(sha256sum "$explicit/cli.config")" == "$before_cli" ]]; else [[ "$(sha256sum "$explicit/env.config")" == "$before_env" ]]; fi
                    ;;
                create-claster-deb.sh)
                    parse_args --pg-version 17 --pg-family postgresql --cluster-name from_cli --port 5555 --schema own --user usr --password test --backup-dir /argument
                    load_defaults
                    [[ "$pg_ver/$pg/$cls_nm/$cls_pt/$cls_ch/$cls_us/$cls_pw/$BACKUP_DIR" == 17/postgresql/from_cli/5555/own/usr/test//argument ]]
                    ;;
                *) expected_dir=/cli; [[ "$input" != env ]] || expected_dir=/env; [[ "$(configured_backup_dir)" == "$expected_dir" ]] ;;
            esac
        )
        printf 'PASS %s: explicit %s priority/path/values\n' "$name" "$input"
    done
    ln -sf "$explicit/cli.config" "$explicit/link.config"
    (export PGCC_CFG="$explicit/link.config"; source "$fixture/bin/$name"; trap - EXIT; select_config; [[ "$CONFIG_FILE" == "$explicit/cli.config" ]])
    for invalid in "$fixture/missing.config" "$explicit"; do
        if (export PGCC_CFG="$invalid"; source "$fixture/bin/$name"; trap - EXIT; select_config; case "$name" in create-claster.sh) load_config ;; create-claster-deb.sh) load_defaults ;; *) configured_backup_dir ;; esac) >/dev/null 2>&1; then
            echo "FAIL invalid explicit config accepted: $name"; exit 1
        fi
    done
    for args in empty missing; do
        if (source "$fixture/bin/$name"; trap - EXIT; if [[ "$args" == empty ]]; then parse_args --config=; else parse_args --config; fi) >/dev/null 2>&1; then
            echo "FAIL missing --config value accepted: $name"; exit 1
        fi
    done
    # Help must not source an explicit config (which is executable shell input).
    printf 'touch %q\n' "$fixture/config-executed" >"$explicit/help.config"
    env PGCC_CFG="$explicit/help.config" bash "$repo/$name" --help >/dev/null
    [[ ! -e "$fixture/config-executed" ]]
    printf 'PASS %s: explicit symlink, invalid file/value refusal, help without source\n' "$name"
done

# Exercise wrapper delegation with a creator double; no archive or cluster is made.
cat >"$fixture/creator.sh" <<'SH'
#!/usr/bin/env bash
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    cluster_backup_version() { echo 17; }
    return
fi
[[ "$1" == --config && "$2" == "$PGCC_CFG" ]] || exit 1
printf '%s\n' "$2" >"$QA_CONFIG_CAPTURE"
SH
chmod +x "$fixture/creator.sh"
(
    export PGCC_CFG="$explicit/env.config" QA_CONFIG_CAPTURE="$fixture/forwarded"
    source "$fixture/scripts/create-claster-backup.sh"
    trap - EXIT
    require_root() { :; }
    acquire_task_lock() { :; }
    resolve_creator() { printf '%s' "$fixture/creator.sh"; }
    pg_lsclusters() { echo '17 qa 5432 online postgres /fixture/data /fixture/log'; }
    apply_retention() { :; }
    main --config "$explicit/cli.config" --backup-dir "$fixture/backups" 17 qa qa
    [[ "$(<"$fixture/forwarded")" == "$explicit/cli.config" ]]
)
printf 'PASS wrapper: CLI-selected config forwarded to creator and exported over ENV\n'

# Inspect the real cron writer, remapping only its own paths and terminal guard.
mkdir "$fixture/cron"
(
    source "$fixture/scripts/create-claster-backup.sh"
    trap - EXIT
    parse_args --config "$explicit/cli.config"
    select_config
    prompt_schedule() { CRON_SCHEDULE='0 1 * * *'; }
    prompt_retention() { FILES_COUNT=2; }
    eval "$(declare -f install_cron_task | sed -e '/\[\[ -t 0 \]\]/d' -e "s@/etc/cron.d@$fixture/cron@g" -e "s@/var/log/@$fixture/@g")"
    install_cron_task 17 qa qa "$fixture/backups" <<<y
    grep -F -- "--config $(shell_quote "$CONFIG_FILE")" "$fixture/cron/pg-claster-backup-"*
)
printf 'PASS wrapper: cron persists shell-quoted explicit config\n'

# A non-root process sees a sudo double that reports arguments, never elevates.
cat >"$fixture/bin/sudo" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@"
SH
chmod 755 "$fixture" "$fixture/bin" "$fixture/scripts" "$fixture/bin/sudo" "$explicit"
chmod 644 "$fixture/scripts/"*.sh
for name in create-claster.sh create-claster-backup.sh; do
    actual="$(runuser -u nobody -- env PATH="$fixture/bin:$PATH" PGCC_CFG="$explicit/cli.config" PGCC_DATABASE=env_db PGCC_DB_PASSWORD=fixture_only PGCC_FILES_CNT=2 bash -c '
        source "$1"; trap - EXIT; select_config; require_root --config "$PGCC_CFG"
    ' _ "$fixture/scripts/$name")"
    grep -Fx -- "PGCC_CFG=$explicit/cli.config" <<<"$actual"
    grep -Fxq -- 'PGCC_DATABASE=env_db' <<<"$actual"
    if [[ "$name" == create-claster.sh ]]; then
        grep -Fxq -- 'PGCC_DB_PASSWORD=fixture_only' <<<"$actual"
        ! grep -q 'PGCC_FILES_CNT=' <<<"$actual"
    else
        grep -Fxq -- 'PGCC_FILES_CNT=2' <<<"$actual"
        ! grep -q 'PGCC_DB_PASSWORD=' <<<"$actual"
    fi
    printf 'PASS %s: sudo receives explicit config even when ENV is filtered\n' "$name"
done
chmod 600 "$explicit/cli.config"
for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh; do
    if runuser -u nobody -- env PGCC_CFG="$explicit/cli.config" bash -c '
        source "$1"; trap - EXIT; select_config
        case "$1" in *backup.sh) configured_backup_dir ;; *deb.sh) load_defaults ;; *) load_config ;; esac
    ' _ "$fixture/scripts/$name" >/dev/null 2>&1; then
        echo "FAIL unreadable explicit config accepted: $name"; exit 1
    fi
done
printf 'PASS all scripts: unreadable explicit config refused without fallback\n'
