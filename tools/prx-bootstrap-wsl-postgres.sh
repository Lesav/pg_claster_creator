#!/usr/bin/env bash
# Purpose: task wrapper for approved package removal and first workspace install.
# Usage: PGCC_TEST_RELEASE=VERSION PGCC_TEST_RUN=RUN bash tools/prx-bootstrap-wsl-postgres.sh DISTRO PACKAGE MAJOR FAMILY PORT
# Args: exact WSL name, original package, major, family, unique QA port; optional sixth argument is a recovery attempt label.
# Example: PGCC_TEST_RELEASE=2.5.2 PGCC_TEST_RUN=qa-run bash tools/prx-bootstrap-wsl-postgres.sh mint22-3 postgresql-16 16 postgresql 60800
# Path note: adjust /mnt/d/Ai/pg_claster_creator and its .backup sibling if different.
# Output: per-WSL evidence; protected config baseline in /var/tmp; no autoremove/purge.
set -Eeuo pipefail
repo="${PGCC_TEST_REPO:-/mnt/d/Ai/pg_claster_creator}"
release="${PGCC_TEST_RELEASE:?release required}"; token="${release//./}"
distro="$1"; package="$2"; major="$3"; family="$4"; port="$5"
[[ "$distro" == "$WSL_DISTRO_NAME" && "$major" =~ ^[0-9]+$ && "$port" =~ ^[0-9]+$ ]]
base="/mnt/d/Ai/pg_claster_creator.backup/TEST-${release}/$distro"
[[ -z "${PGCC_TEST_RUN:-}" ]] || base="$base/$PGCC_TEST_RUN"
attempt="${6:-initial}"; [[ "$attempt" == initial || "$attempt" =~ ^recover[0-9]*$ || "$attempt" =~ ^resume[0-9]*$ ]]
logs="$base/bootstrap"; [[ "$attempt" == initial ]] || logs="$base/bootstrap-$attempt"
work="/var/tmp/pgcc-full-${release}${PGCC_TEST_RUN:+-$port}"
[[ ! -e "$logs" ]]
if [[ "$attempt" == initial ]]; then [[ ! -e "$work" ]]; else [[ -f "$work/config-share" && ( -f "$work/config-shared" || -f "$work/absent-shared" ) ]]; fi
mkdir -p "$logs" "$base/artifacts"
[[ "$attempt" != initial ]] || mkdir -m 700 "$work"
exec >"$logs/run.log" 2>&1
date --iso-8601=seconds
printf '%s\n' "$distro" "$package" "$major" "$family" "$port" >"$logs/target.txt"
sha256sum "$repo"/create-claster*.sh "$repo/.new-claster.config" >"$logs/source.sha256"
cat /etc/os-release >"$logs/os.log"
[[ ! -f /etc/astra/build_version ]] || cat /etc/astra/build_version >>"$logs/os.log"
if command -v pg_lsclusters >/dev/null; then pg_lsclusters --no-header >"$logs/clusters-before.log"; else find /etc/postgresql -name postgresql.conf >"$logs/clusters-before.log"; fi
[[ ! -s "$logs/clusters-before.log" ]] || { echo 'FAIL registry changed since empty preflight'; exit 1; }
if [[ "$attempt" == initial ]]; then
for location in share shared; do
    config="/usr/local/$location/pg_claster_creator/.new-claster.config"
    if [[ -f "$config" ]]; then cp -a "$config" "$work/config-$location"; else touch "$work/absent-$location"; fi
done
[[ -f "$work/config-share" ]]
if [[ ! -f "$work/config-shared" ]]; then
    install -d -m 0755 /usr/local/shared/pg_claster_creator
    install -m 0600 "$work/config-share" /usr/local/shared/pg_claster_creator/.new-claster.config
fi
fi
mapfile -t packages <"$base/packages/removal-candidates.txt"
if [[ "$distro" == alse-1.8.6 ]]; then
    filtered=()
    skipped_be=0
    for selected in "${packages[@]}"; do
        if [[ "${selected%%:*}" == tantor-be-server-18 ]]; then skipped_be=1; else filtered+=("$selected"); fi
    done
    packages=("${filtered[@]}")
    if ((skipped_be)); then printf 'SKIP removal of tantor-be-server-18 on alse-1.8.6: explicit user exception, not a failure\n'; fi
fi
[[ " ${packages[*]} " == *' postgresql-common '* && " ${packages[*]} " == *' postgresql-client-common '* ]]
if [[ ! "$attempt" =~ ^recover ]]; then
LC_ALL=C apt-get -s remove -- "${packages[@]}" >"$logs/removal-plan.log" 2>&1
while read -r op removed rest; do
    [[ "$op" == Remv ]] || continue
    [[ "$removed" == claster-creator || " ${packages[*]} " == *" $removed "* ]] || { echo "REFUSE unexpected removal: $removed"; exit 2; }
done <"$logs/removal-plan.log"
if [[ "${PGCC_OFFLINE_REMOVE:-0}" == 1 ]]; then
    approved=("${packages[@]}")
    if grep -q '^Remv claster-creator ' "$logs/removal-plan.log"; then approved+=(claster-creator); fi
    offline_units=(--unit postgresql.service)
    if [[ "$family" == tantor-* ]]; then offline_units+=(--unit "$family-server-$major.service")
    elif [[ "$family" == postgrespro-ent ]]; then offline_units+=(--unit "postgrespro-ent-$major.service"); fi
    bash "$repo/tools/prx-remove-wsl-postgres-packages.sh" "$distro" "${offline_units[@]}" -- "${approved[@]}" >"$logs/remove.log" 2>&1
else
    timeout -k 10 600 env DEBIAN_FRONTEND=noninteractive apt-get -y remove -- "${packages[@]}" >"$logs/remove.log" 2>&1
fi
for removed in "${packages[@]}"; do
    state="$(dpkg-query -W -f='${db:Status-Status}' "$removed" 2>/dev/null || true)"
    [[ "$state" != installed ]] || { echo "FAIL still installed: $removed"; exit 1; }
done
printf 'PASS all selected packages including common removed\n'
if [[ "${PGCC_BOOTSTRAP_REMOVE_ONLY:-0}" == 1 ]]; then
    printf 'Removal-only prerequisite for the approved DEB dependency test; no manual preinstallation\n'
    exit 0
fi
else
    printf 'RECOVERY after vendor removal failure: server removal NOT passed; restore common/product for remaining independent tests\n'
    printf '%s install\n' "$package" | dpkg --set-selections
fi
set +e
timeout -k 10 900 bash "$repo/create-claster.sh" --action install --package "$package" --pg-family "$family" --pg-version "$major" --cluster-name qa${token}_boot --port "$port" --schema pgcc_owner --user pgcc_user --password 'Pgcc-QA-bootstrap!' --backup-dir "$base/artifacts" >"$work/install.raw" 2>&1
rc=$?
set -e
sed -E '/(password_hash=|PASSWORD |PGPASSWORD=|--password|Пароль)/I s/.*/[REDACTED credential line]/' "$work/install.raw" >"$logs/install.log"
printf '%s\n' "$rc" >"$logs/install.rc"
dpkg-query -W -f='${binary:Package}\t${Status}\t${Version}\n' postgresql-common postgresql-client-common "$package" >"$logs/installed-state.log" 2>&1 || true
if command -v pg_lsclusters >/dev/null; then pg_lsclusters >"$logs/clusters-after.log"; fi
if ((rc != 0)); then echo "FAIL workspace install rc=$rc; recovery required"; exit "$rc"; fi
grep -F 'install ok installed' "$logs/installed-state.log" | wc -l >"$logs/installed-count"
[[ "$(<"$logs/installed-count")" == 3 ]]
server_bin="$(dpkg -L "$package" | grep '/bin/postgres$' | head -n 1)"
"$server_bin" --version >"$logs/server-version.log"
actual="$(grep -oE '[0-9]+\.[0-9]+' "$logs/server-version.log" | head -n 1)"
expected="$(awk -F '\t' -v p="$package" '$1==p {print $2}' "$base/packages/server-minors.tsv")"
[[ "$actual" == "$expected" ]] || { echo "FAIL minor mismatch: $expected -> $actual"; exit 1; }
timeout -k 5 180 bash "$repo/create-claster.sh" --action delete "$major" qa${token}_boot --backup-before-delete no >"$logs/delete-bootstrap.log" 2>&1
timeout -k 5 180 dpkg --force-confdef --force-confold -i "$repo/dist/claster-creator-${release}.deb" >"$logs/restore-product.log" 2>&1
dpkg --audit >"$logs/audit.log"; [[ ! -s "$logs/audit.log" ]]
printf 'PASS common installation, server minor, bootstrap cluster create/delete, product restored\n'
date --iso-8601=seconds
