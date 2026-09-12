#!/usr/bin/env bash
# Purpose: archive owned deployment markers and verify the live runner's final baseline.
# Usage: bash tools/prx-audit-live-regression.sh REPO DISTRO PORT RELEASE LOG_ROOT [LABEL]
# Args: PORT/RELEASE identify the existing prx-test-live-regression work directory.
#   LABEL optionally distinguishes a later audit without replacing previous evidence.
# Output: fresh final-audit[-LABEL].log, protected recoverable markers, nonzero on audit failure.
# Example: bash tools/prx-audit-live-regression.sh /repo Astra 57210 2.4.0 /repo/tmp/run
set -Eeuo pipefail
repo="$1"; distro="$2"; port="$3"; release="$4"; token="${4//./}"
[[ "$port" =~ ^[0-9]+$ && "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
work="/var/tmp/pgcc$token-$port"
logs="$5/$distro"
[[ -f "$work/original-clusters" && -d "$logs" ]]
label="${6:-}"
[[ -z "$label" || "$label" =~ ^[a-z0-9-]+$ ]] || exit 2
audit="$logs/final-audit${label:+-$label}.log"
[[ ! -e "$audit" ]]
exec >"$audit" 2>&1
date --iso-8601=seconds
recovery="$work/retained-markers"
if [[ -e "$recovery" ]]; then
    [[ -d "$recovery" && ! -L "$recovery" && "$(stat -c '%a %u' "$recovery")" == '700 0' ]] || exit 2
else
    mkdir -m 700 "$recovery"
fi
while IFS= read -r deb; do
    plan="${deb##*/}"; plan="${plan%.deb}"
    [[ "$plan" == claster-creator-"$release"-*qa"${token}_${port}"* ]] || exit 2
    for suffix in done cluster-created data-moved; do
        marker="/var/lib/claster-creator/$plan.$suffix"
        if [[ -f "$marker" && ! -L "$marker" ]]; then
            [[ ! -e "$recovery/${marker##*/}" ]]
            mv -- "$marker" "$recovery/"
            printf 'ARCHIVED owned marker %s\n' "$marker"
        fi
    done
done < <(find "$work/debs" "$work-extra/debs" -maxdepth 1 -type f -name '*.deb' 2>/dev/null)
bad=0
pg_lsclusters --no-header >"$work/final-audit-clusters"
if cmp "$work/original-clusters" "$work/final-audit-clusters"; then
    printf 'PASS original registry preserved\n'
else
    printf 'CHANGED registry since baseline; do not alter non-test clusters\n'
    bad=1
fi
cat "$work/final-audit-clusters"
cmp "$work/config-shared" /usr/local/shared/pg_claster_creator/.new-claster.config && printf 'PASS config-shared\n' || { printf 'CHANGED config-shared since baseline\n'; bad=1; }
cmp "$work/config-share" /usr/local/share/pg_claster_creator/.new-claster.config && printf 'PASS config-share\n' || { printf 'CHANGED config-share since baseline\n'; bad=1; }
sha256sum -c "$work/project-config.sha"
for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh; do
    cmp "$repo/$name" "/usr/local/share/pg_claster_creator/$name"
    sha256sum "/usr/local/share/pg_claster_creator/$name"
done
printf 'PASS installed scripts equal tested sources\n'
dpkg-query -W -f='${Status} ${Version}\n' claster-creator
dpkg --audit
[[ -z "$(dpkg --audit)" ]] || bad=1
[[ "$(dpkg-query -W -f='${Version}' claster-creator)" == "$release" ]] || bad=1
printf '\nRemaining test-related paths (logs and protected archives are retained):\n'
for root in /etc/postgresql /etc/systemd/system /usr/lib/systemd/system /lib/systemd/system /DATA /.postgres; do
    [[ ! -d "$root" ]] || find "$root" -maxdepth 4 \( -name "*qa${token}_${port}*" -o -name "pgcc${token}-$port*" \) -ls
done
printf '\nConvenience links:\n'
find /.postgres -maxdepth 1 -type l -printf '%p -> %l\n'
printf '\nProcesses relevant to interrupted operations:\n'
ps -eo pid,ppid,stat,comm | grep -E 'postgres|pg_dropcluster|syslog-ng-ctl' || true
for phase in '' -extra -ports -ui -tail -extension -extension-r2; do
    owned="$work$phase"
    [[ ! -d "$owned" ]] || { stat -c '%a %U:%G %n' "$owned"; find "$owned" -maxdepth 3 -type f \( -name '*.deb' -o -name '*.tar.gz' \) -exec sha256sum {} +; }
done
printf '\nDisk space:\n'
df -h / /mnt/d
date --iso-8601=seconds
printf 'FINAL AUDIT rc=%s\n' "$bad"
exit "$bad"
