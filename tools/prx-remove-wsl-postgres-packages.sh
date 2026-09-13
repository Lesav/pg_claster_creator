#!/usr/bin/env bash
# Purpose: remove an explicitly reviewed PostgreSQL package set on an empty WSL,
#   bypassing known online service hooks which crash Astra's systemd/PARSEC.
# Usage: sudo bash prx-remove-wsl-postgres-packages.sh DISTRO [--unit UNIT]... -- PACKAGE...
# Args: DISTRO must match WSL_DISTRO_NAME; UNIT is an explicit offline-disable target;
#   PACKAGE includes every allowed dependent removal. Review prerm/postrm beforehand.
# Output: /root/pg-wsl-remove.XXXXXX contains originals, patched hooks and evidence.
# Example: sudo bash prx-remove-wsl-postgres-packages.sh alse-1.8.6 --unit tantor-be-server-18.service -- tantor-be-server-18
# No purge, autoremove, data removal, online daemon-reload or package force flags.
set -Eeuo pipefail
[[ $# -ge 3 && "$EUID" == 0 ]] || exit 2
distro="$1"; shift
[[ "${WSL_DISTRO_NAME:-}" == "$distro" ]] || exit 2
grep -qi microsoft /proc/sys/kernel/osrelease || exit 2
units=()
while [[ "${1:-}" == --unit ]]; do
    [[ $# -ge 2 && "$2" =~ ^(postgresql|postgrespro-ent-[0-9]+|tantor-(be|se|free)-server-[0-9]+)\.service$ ]] || exit 2
    units+=("$2"); shift 2
done
[[ "${1:-}" == -- ]] || exit 2
shift
[[ $# -gt 0 ]] || exit 2
packages=("$@")
canonical=()
for package in "${packages[@]}"; do
    [[ "$package" =~ ^[a-z0-9][a-z0-9+.-]*(:[a-z0-9]+)?$ ]] || exit 2
    [[ "$(dpkg-query -W -f='${Status}' "$package")" == 'install ok installed' ]] || exit 2
    canonical+=("$(dpkg-query -W -f='${binary:Package}' "$package")")
done
clusters=$(pg_lsclusters --no-header)
[[ -z "$clusters" ]] || { echo 'REFUSE: clusters exist'; exit 2; }
process_rc=0
pgrep -a -x postgres || process_rc=$?
[[ "$process_rc" == 1 ]] || { echo 'REFUSE: postgres processes exist or check failed'; exit 2; }
backup=$(mktemp -d /root/pg-wsl-remove.XXXXXX)
printf 'BACKUP_DIR=%s\n' "$backup"
exec > >(tee "$backup/run.log") 2>&1
trap 'rc=$?; printf "END rc=%s; retain recovery directory %s\n" "$rc" "$backup"' EXIT
date --iso-8601=seconds
printf '%s\n' "${packages[@]}" | sort >"$backup/approved.txt"
printf '%s\n' "${canonical[@]}" | sort >"$backup/approved-canonical.txt"
LC_ALL=C apt-get -s remove -- "${packages[@]}" >"$backup/apt-plan.log"
awk '$1=="Remv" {print $2}' "$backup/apt-plan.log" | sort >"$backup/planned.txt"
cmp "$backup/approved.txt" "$backup/planned.txt"
dpkg --audit >"$backup/audit-before.log"
[[ ! -s "$backup/audit-before.log" ]]
dpkg-query -W -f='${binary:Package}\t${Status}\t${Version}\n' >"$backup/packages-before.tsv"
find / -maxdepth 1 -type f -name 'core.*' -printf '%T@ %s %p\n' | sort >"$backup/cores-before"
awk '{print $22}' /proc/1/stat >"$backup/pid1-before"
readlink /proc/1/ns/pid >"$backup/namespace-before"
config=/usr/local/shared/pg_claster_creator/.new-claster.config
if [[ -f "$config" ]]; then sha256sum "$config" >"$backup/config.sha"; fi
mkdir "$backup/originals" "$backup/patched"
hooks=()
for package in "${canonical[@]}"; do
    for phase in prerm postrm; do
        hook="/var/lib/dpkg/info/$package.$phase"
        if [[ -e "$hook" || -L "$hook" ]]; then
            [[ -f "$hook" && ! -L "$hook" ]] || exit 2
            cp -a "$hook" "$backup/originals/"
            hooks+=("$hook")
        fi
    done
done
for unit in "${units[@]}"; do
    timeout -k 2 10 systemctl --root=/ --no-reload disable "$unit"
done
for hook in "${hooks[@]}"; do
    # ':' keeps an if-body valid when all of its original commands are bypassed.
    sed -Ei 's@^([[:space:]]*)((/bin/)?systemctl[[:space:]]|deb-systemd-invoke[[:space:]]+stop[[:space:]]|invoke-rc.d[[:space:]]+--skip-systemd-native[[:space:]]+postgresql[[:space:]]+stop|/opt/pgpro/ent-[0-9]+/bin/pg-setup[[:space:]]+service[[:space:]]+(stop|disable))@\1: # WSL hook bypass: \2@' "$hook"
    sh -n "$hook"
    cp -a "$hook" "$backup/patched/"
done
timeout -k 5 180 env DEBIAN_FRONTEND=noninteractive apt-get -y --no-auto-remove remove -- "${packages[@]}"
dpkg --audit >"$backup/audit-after.log"
[[ ! -s "$backup/audit-after.log" ]]
dpkg-query -W -f='${binary:Package}\t${Status}\t${Version}\n' >"$backup/packages-after.tsv"
for package in "${packages[@]}"; do
    status=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)
    [[ "$status" != 'install ok installed' ]]
done
for when in before after; do
    awk -F '\t' 'NR==FNR {omit[$1]=1;next} !($1 in omit)' \
        "$backup/approved-canonical.txt" "$backup/packages-$when.tsv" >"$backup/other-$when.tsv"
done
cmp "$backup/other-before.tsv" "$backup/other-after.tsv"
awk '{print $22}' /proc/1/stat >"$backup/pid1-after"
readlink /proc/1/ns/pid >"$backup/namespace-after"
cmp "$backup/pid1-before" "$backup/pid1-after"
cmp "$backup/namespace-before" "$backup/namespace-after"
find / -maxdepth 1 -type f -name 'core.*' -printf '%T@ %s %p\n' | sort >"$backup/cores-after"
cmp "$backup/cores-before" "$backup/cores-after"
if [[ -f "$backup/config.sha" ]]; then sha256sum -c "$backup/config.sha"; fi
printf 'PASS approved packages removed, other packages/config unchanged, same PID1, audit clean\n'
