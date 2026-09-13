#!/usr/bin/env bash
# Path note: If /mnt/d/Ai/pg_claster_creator or
# /mnt/d/Ai/pg_claster_creator.backup does not match your filesystem,
# adjust the paths before running. Set PGCC_TEST_REPO to the actual project
# path and PGCC_TEST_OUTPUT to the actual per-release evidence directory.
# Purpose: test real interactive default/custom cluster creation.
# Usage: PGCC_TEST_RUN=RUN PGCC_TEST_REPO=REPO PGCC_TEST_RELEASE=VERSION bash tools/prx-test-live-install.sh DISTRO MAJOR PORT
# Args: RUN is a unique run identifier; REPO and VERSION select the source/release.
#   PGCC_TEST_OUTPUT optionally selects the per-release evidence root.
# Output: per-WSL evidence; phases retain artifacts until the cleanup helper.
# Example: PGCC_TEST_RUN=run-example PGCC_TEST_RELEASE=2.5.1 bash tools/prx-test-live-install.sh Astra 16 60100
set -Eeuo pipefail
repo="${PGCC_TEST_REPO:-/mnt/d/Ai/pg_claster_creator}"
release="${PGCC_TEST_RELEASE:?release required}"; token="${release//./}"
[[ "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "${PGCC_TEST_RUN:-}" =~ ^run-[a-zA-Z0-9_-]+$ ]]
output="${PGCC_TEST_OUTPUT:-/mnt/d/Ai/pg_claster_creator.backup/TEST-$release}"
distro="$1"; v="$2"; port="$3"
[[ "$WSL_DISTRO_NAME" == "$distro" && "$port" =~ ^[0-9]{5}$ ]]
base="$output/$distro/$PGCC_TEST_RUN"
logs="$base/interactive"; [[ ! -e "$logs" ]]; mkdir "$logs"
work="$(mktemp -d /var/tmp/pgcc-interactive.XXXXXX)"
backup="$base/interactive-artifacts"; [[ ! -e "$backup" ]]; mkdir "$backup"
root="/DATA/pgcc-interactive-$port"; [[ ! -e "$root" && ! -L "$root" ]]
exec >"$logs/run.log" 2>&1
cp -a /usr/local/shared/pg_claster_creator/.new-claster.config "$work/config"
names=("qa${token}_${port}g1" "qa${token}_${port}g2")
[[ -z "$(pg_lsclusters --no-header)" ]]
cleanup() {
    local rc=$? clean=0 n; trap - EXIT; set +e
    for n in "${names[@]}"; do
        if pg_lsclusters --no-header | awk -v n="$n" '$2==n {found=1} END {exit !found}'; then
            timeout -k 5 180 bash "$repo/create-claster.sh" --action delete "$v" "$n" --backup-before-delete no || clean=1
        fi
    done
    cp -a "$work/config" /usr/local/shared/pg_claster_creator/.new-claster.config
    [[ ! -d "$root" ]] || find "$root" -depth -type d -empty -delete
    [[ ! -e "$root" && -z "$(pg_lsclusters --no-header)" ]] || clean=1
    [[ "$(realpath "$work")" == /var/tmp/pgcc-interactive.* ]] && rm -rf -- "$work"
    [[ "$(realpath "$backup")" == "$base/interactive-artifacts" ]] && rm -rf -- "$backup"
    printf 'FINAL rc=%s cleanup=%s\n' "$rc" "$clean"
    ((rc==0 && clean==0))
}
trap cleanup EXIT
for i in 0 1; do
    name="${names[$i]}"; selected_port="$((port+70+i))"
    data_choice=1; extra=''; [[ "$i" != 1 ]] || { data_choice=2; extra="$root"; }
    input="$(printf '2\n0\n%s\nBAD-NAME\n%s\nqag_owner\nqag_user\nPgcc-interactive!\n%s\n' "$selected_port" "$name" "$data_choice")"
    [[ -z "$extra" ]] || input+=$'\n'"$extra"
    input+=$'\ny\n\n0\n'
    set +e
    printf '%s' "$input" | timeout -k 5 180 script -q -e -c "env TERM=xterm PGCC_BACKUP_DIR=$backup bash $repo/create-claster.sh" /dev/null >"$work/menu.raw" 2>&1
    rc=$?; set -e
    sed -E '/(Pgcc-interactive|Пароль|password_hash)/I s/.*/[REDACTED credential line]/' "$work/menu.raw" >"$logs/create-$i.log"
    [[ "$rc" == 0 ]]
    row="$(pg_lsclusters --no-header | awk -v n="$name" '$2==n')"
    printf '%s\n' "$row"
    [[ "$(awk '{print $3,$4}' <<<"$row")" == "$selected_port online" ]]
    if [[ "$i" == 1 ]]; then [[ "$(awk '{print $6}' <<<"$row")" == "$root/pg_$v/$name" ]]; fi
    runuser -u postgres -- psql --cluster "$v/$name" -X -At -v ON_ERROR_STOP=1 -d "$name" -c "SHOW server_version; SHOW password_encryption; SHOW shared_preload_libraries; SHOW search_path; SELECT extname FROM pg_extension ORDER BY 1; SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='$name';" >"$logs/settings-$i.log"
    result="$(PGPASSWORD='Pgcc-interactive!' psql -h 127.0.0.1 -p "$selected_port" -U qag_user -d "$name" -X -Atqc 'SELECT current_user')"
    [[ "$result" == qag_user ]]
    expected=md5; ((v<=16)) || expected=scram-sha-256
    [[ "$(runuser -u postgres -- psql --cluster "$v/$name" -X -Atqc 'SHOW password_encryption' "$name")" == "$expected" ]]
    grep -q '^qag_owner$' "$logs/settings-$i.log"
    printf 'PASS interactive creation %s; invalid port/name retry; configured owner/login/encryption\n' "$i"
done
printf 'PASS interactive default/custom creation\n'
