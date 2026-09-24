#!/usr/bin/env bash
# Path note: If /mnt/d/Ai/pg_claster_creator in the example does not match
# your filesystem, replace it with the actual project path before running.
# Purpose: collect WSL/package baseline and test informational CLI/man without cluster changes.
# Usage: bash tools/prx-test-wsl-preflight.sh REPO LOG_DIR VERSION
# Args: REPO -- source tree; LOG_DIR -- new output directory; VERSION -- expected release.
#   PGCC_PREFLIGHT_WORKSPACE=1 checks working scripts/man instead of installed bytes.
# Output: full per-command logs and results.tsv (checks are partial plan evidence).
# Example: bash tools/prx-test-wsl-preflight.sh /mnt/d/Ai/pg_claster_creator /tmp/qa-env 2.3.5
set -uo pipefail
repo="$(realpath "$1")"; logs="$2"; version="$3"
[[ ! -e "$logs" ]] || { echo 'Refusing to overwrite existing logs' >&2; exit 1; }
mkdir -p "$logs"
exec >"$logs/preflight.log" 2>&1
check() {
    local id="$1" expected="$2" rc; shift 2
    printf '\nSTART %s %s\n' "$id" "$(date --iso-8601=seconds)"
    printf 'COMMAND '; printf '%q ' "$@"; printf '\n'
    timeout -k 2 30 "$@" >"$logs/$id.log" 2>&1; rc=$?
    cat "$logs/$id.log"
    printf 'END %s rc=%s %s\n' "$id" "$rc" "$(date --iso-8601=seconds)"
    if [[ "$expected" == nonzero && "$rc" != 0 && "$rc" != 124 && "$rc" != 137 ]] || [[ "$rc" == "$expected" ]]; then
        printf '%s\tPASS\trc=%s\n' "$id" "$rc" >>"$logs/results.tsv"
    else
        printf '%s\tFAIL\trc=%s\n' "$id" "$rc" >>"$logs/results.tsv"
    fi
}
os_files=(/etc/os-release)
[[ ! -f /etc/astra/build_version ]] || os_files+=(/etc/astra/build_version)
check os 0 cat "${os_files[@]}"
check kernel 0 uname -a
check systemd 0 systemctl --version
check bash 0 bash --version
check apt 0 apt-get --version
check dpkg 0 dpkg --version
check locale 0 locale
check timezone 0 date --iso-8601=seconds
check space 0 df -h / "$repo"
check audit 0 dpkg --audit
check clusters 0 pg_lsclusters
check services 0 systemctl list-units --all --no-pager 'postgres*' 'tantor*'
check mounts 0 findmnt
check policy 0 apt-cache policy postgresql-common
check packages 0 dpkg-query -l
check available 0 apt-cache pkgnames
check config-hashes 0 sha256sum /usr/local/shared/pg_claster_creator/.new-claster.config /usr/local/share/pg_claster_creator/.new-claster.config "$repo/.new-claster.config"
check script-hashes 0 sha256sum "$repo/create-claster.sh" "$repo/create-claster-backup.sh" "$repo/create-claster-deb.sh"
for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh; do
    file="/usr/local/share/pg_claster_creator/$name"
    if [[ "${PGCC_PREFLIGHT_WORKSPACE:-0}" == 1 ]]; then
        sha256sum "$repo/$name" "$file" >"$logs/$name-source-installed-sha.log"
        file="$repo/$name"
    else
        check "$name-bytes" 0 cmp "$repo/$name" "$file"
    fi
    check "$name-syntax" 0 bash -n "$file"
    for option in -h --help -v --version; do
        check "$name-$option" 0 bash "$file" "$option"
    done
    check "$name-unknown" nonzero bash "$file" --unknown
    check "$name-nobody-help" 0 runuser -u nobody -- bash "$file" --help
    check "$name-nobody-version" 0 runuser -u nobody -- bash "$file" --version
    check "$name-version-match" 0 grep -F "версия $version" "$logs/$name---version.log"
    for lang in en ru; do
        man_dir=/usr/share/man/man1
        [[ "$lang" != ru ]] || man_dir=/usr/share/man/ru/man1
        man_file="$man_dir/$name.1.gz"
        [[ "${PGCC_PREFLIGHT_WORKSPACE:-0}" != 1 ]] || man_file="$repo/man/$lang/man1/$name.1"
        check "$name-man-$lang" 0 env MANWIDTH=120 MANPAGER=cat man -l "$man_file"
    done
done
check clusters-after 0 pg_lsclusters
check clusters-unchanged 0 cmp "$logs/clusters.log" "$logs/clusters-after.log"
date --iso-8601=seconds
! grep -q $'\tFAIL\t' "$logs/results.tsv"
