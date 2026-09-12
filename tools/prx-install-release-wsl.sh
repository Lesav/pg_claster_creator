#!/usr/bin/env bash
# Purpose: install a scripts-only release and verify files while preserving cluster/config state.
# Usage: bash tools/prx-install-release-wsl.sh REPO DISTRO VERSION [JOURNAL_VERSION]
# Args: REPO -- project root; DISTRO -- evidence label; VERSION -- scripts-only release;
#   JOURNAL_VERSION -- packaged historical journal version (default: 2.1.2).
# Output: REPO/tmp/release-VERSION/DISTRO/install.log; root-only baseline under /var/tmp.
# Example: bash tools/prx-install-release-wsl.sh /mnt/d/Ai/pg_claster_creator Astra 2.4.2 2.1.2
set -Eeuo pipefail
repo="$1"; distro="$2"; version="$3"
journal_version="${4:-2.1.2}"
package="$repo/dist/claster-creator-$version.deb"
logs="$repo/tmp/release-$version/$distro"
[[ ! -e "$logs/install.log" ]] || { printf 'Installation log already exists: %s\n' "$logs/install.log" >&2; exit 2; }
work="$(mktemp -d /var/tmp/pgcc-install.XXXXXX)"
mkdir -p "$logs"
exec >"$logs/install.log" 2>&1
date --iso-8601=seconds
[[ "$(dpkg-deb -f "$package" Package)" == claster-creator && "$(dpkg-deb -f "$package" Version)" == "$version" ]]
dpkg-deb -e "$package" "$work/control"
[[ ! -f "$work/control/postinst" ]]
pg_lsclusters --no-header >"$work/clusters-before"
cp "$work/clusters-before" "$logs/clusters-before.log"
: >"$work/config.sha"
for config in /usr/local/shared/pg_claster_creator/.new-claster.config /usr/local/share/pg_claster_creator/.new-claster.config; do
    if [[ -e "$config" || -L "$config" ]]; then
        sha256sum "$config" >>"$work/config.sha"
    elif [[ "$config" == /usr/local/shared/* ]]; then
        touch "$work/shared-config-absent"
    fi
done
sha256sum "$package"
timeout -k 5 180 dpkg --force-confdef --force-confold -i "$package"
dpkg-query -W -f='${Status} ${Version}\n' claster-creator | tee "$work/status"
grep -Fx "install ok installed $version" "$work/status"
for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh; do
    cmp "$repo/$name" "/usr/local/share/pg_claster_creator/$name"
    bash "/usr/local/share/pg_claster_creator/$name" --version | grep -F "версия $version"
    bash -n "/usr/local/share/pg_claster_creator/$name"
done
for name in create-claster.sh create-claster-backup.sh; do
    [[ "$(readlink -f "/usr/local/bin/$name")" == "/usr/local/share/pg_claster_creator/$name" ]]
done
cmp "$repo/TEST-$journal_version-journal-passed.md" "/usr/local/share/pg_claster_creator/TEST-$journal_version-journal-passed.md"
[[ ! -s "$work/config.sha" ]] || sha256sum -c "$work/config.sha"
if [[ -f "$work/shared-config-absent" ]]; then
    [[ ! -e /usr/local/shared/pg_claster_creator/.new-claster.config && ! -L /usr/local/shared/pg_claster_creator/.new-claster.config ]]
fi
pg_lsclusters --no-header >"$logs/clusters-after.log"
cmp "$work/clusters-before" "$logs/clusters-after.log"
dpkg --audit >"$work/audit"
cat "$work/audit"
[[ ! -s "$work/audit" ]]
date --iso-8601=seconds
printf 'PASS installation, scripts, symlinks, journal, configs and clusters preserved\n'
