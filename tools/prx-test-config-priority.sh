#!/usr/bin/env bash
# Purpose: test config priority and save isolation using temporary path fixtures.
# Usage: bash tools/prx-test-config-priority.sh REPO
# Args: REPO -- source directory.
# Output: PASS per script; no changes to system configs or PostgreSQL clusters.
# Example: bash tools/prx-test-config-priority.sh /mnt/d/Ai/pg_claster_creator
set -Eeuo pipefail
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
done
