#!/usr/bin/env bash
# Purpose: final per-WSL audit; remove validated rename work and run-owned syslog backups.
# Usage: PGCC_TEST_RELEASE=VERSION PGCC_TEST_RUN=RUN bash tools/prx-verify-wsl-test-cleanup.sh DISTRO PORT [RENAME_LOG_GROUP] [LABEL]
# Args: DISTRO is the exact WSL name; PORT identifies owned QA paths; optional log group defaults to rename-delete.
#   LABEL optionally records a separate repeat without overwriting earlier evidence.
# Environment: PGCC_TEST_RELEASE and PGCC_TEST_RUN identify the completed run.
# Example: PGCC_TEST_RELEASE=2.5.2 PGCC_TEST_RUN=run-20260913-142600 bash tools/prx-verify-wsl-test-cleanup.sh mint22-3 60800
# Path note: adjust /mnt/d/Ai/pg_claster_creator.backup if it does not match the actual workspace.
# Output: final-verification.log; preserves historical evidence and unknown paths.
# Syslog backup deletion requires an exact path recorded by this run and a QA name.
set -Eeuo pipefail
distro="$1"; port="$2"
[[ "$WSL_DISTRO_NAME" == "$distro" && "$port" =~ ^60[1-8]00$ ]]
base="/mnt/d/Ai/pg_claster_creator.backup/TEST-${PGCC_TEST_RELEASE:?}/$distro/${PGCC_TEST_RUN:?}"
label="${4:-}"; [[ -z "$label" || "$label" =~ ^[a-z0-9-]+$ ]]
audit="$base/final-verification${label:+-$label}.log"
[[ -f "$base/timing.tsv" && ! -e "$audit" ]]
exec >"$audit" 2>&1
date --iso-8601=seconds
[[ -z "$(pg_lsclusters --no-header)" ]]
rc=0; pgrep -a -x postgres || rc=$?; [[ "$rc" == 1 ]]
[[ -z "$(dpkg --audit)" ]]
token="${PGCC_TEST_RELEASE//./}"
while IFS= read -r target; do
    [[ "$target" =~ ^/etc/syslog-ng/conf.d/\.pgcc-wsl-[0-9]+-(qa${token}_(boot|${port}[a-z0-9_]*)|qadel_${port}_[a-z0-9_]+)\.[A-Za-z0-9]+\.bak$ ]] || continue
    if [[ -e "$target" || -L "$target" ]]; then
        [[ -f "$target" && ! -L "$target" && "$(realpath "$target")" == "$target" ]]
        sha256sum "$target"
        rm -- "$target"
        printf 'Removed run-owned syslog backup %s\n' "$target"
    fi
done < <(find "$base" -type f -name '*.log' ! -name 'final-verification*' -exec sed -n 's/.*копия: \([^[:space:]]*\.bak\).*/\1/p' {} + | sort -u)
group="${3:-rename-delete}"; [[ "$group" =~ ^rename-delete(-r[0-9]+)?$ ]]
log="$base/$group/$distro/live.log"
work=""
[[ ! -f "$log" ]] || work="$(sed -n 's/^work=//p' "$log" | head -n 1)"
if [[ -e "$work" ]]; then
    [[ "$work" =~ ^/var/tmp/pgcc-delete-live\.[A-Za-z0-9]+$ && ! -L "$work" && "$(realpath "$work")" == "$work" ]]
    grep -q 'PASS original registry/config preserved' "$log"
    rm -rf -- "$work"
    printf 'Removed validated completed rename fixture %s\n' "$work"
fi
for root in /var/tmp /DATA /.postgres/systemd /run/lock; do
    [[ ! -d "$root" ]] || [[ -z "$(find "$root" -maxdepth 2 -name "*$port*" -print)" ]]
done
[[ -z "$(find "$base" -type f \( -name '*.deb' -o -name '*.tar.gz' -o -name '*.sql' -o -name '*.backup' \) -print)" ]]
printf 'PASS empty registry, no postgres processes, clean dpkg, current artifacts absent\n'
date --iso-8601=seconds
