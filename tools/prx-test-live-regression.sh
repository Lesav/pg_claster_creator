#!/usr/bin/env bash
# Purpose: isolated live core regression, preserving pre-existing clusters and config.
# Usage: bash tools/prx-test-live-regression.sh REPO DISTRO PG_VERSION PACKAGE FAMILY PORT RELEASE LOG_ROOT [PHASE]
# Args: RELEASE -- scripts-only package version; LOG_ROOT -- new per-run evidence directory;
#   PHASE -- core, extra, ports, ui, tail, extension, extension-r2, cleanup-only or cleanup-ui.
#   For extension, PGCC_LIVE_EXTENSION names a trusted local sourced test module.
#   Other arguments identify the QA host/server; a failed phase is not a full-plan PASS.
# Output: per-step logs/results, isolated archives; only owned temporary clusters are deleted.
#   Full dump/role fingerprints and restored LOGIN are checked on hot/cold/DEB targets.
# Example: bash tools/prx-test-live-regression.sh /repo Astra 18 tantor-be-server-18 tantor-be 57210 2.4.0 /repo/tmp/run
set -Eeuo pipefail
repo="$1"; distro="$2"; v="$3"; package="$4"; family="$5"; port="$6"
release="$7"; log_root="$8"; phase="${9:-core}"
[[ "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$port" =~ ^[0-9]+$ ]] || exit 2
token="${release//./}"
c="qa${token}_${port}"
logs="$log_root/$distro/live"
work="/var/tmp/pgcc${token}-$port"
data_root="/DATA/pgcc${token}-$port"
backup="$work/backups"
core_work="$work"
core_c="$c"
if [[ "$phase" == extra ]]; then
    c="${c}e"; work="${work}-extra"; logs="${logs}-extra"; data_root="${data_root}-extra"; backup="$work/backups"
fi
if [[ "$phase" == ui || "$phase" == cleanup-ui ]]; then
    c="${c}u"; work="${work}-ui"; logs="${logs}-ui"; data_root="${data_root}-ui"; backup="$work/backups"
fi
if [[ "$phase" == tail ]]; then
    c="${c}t"; work="${work}-tail"; logs="${logs}-tail"; data_root="${data_root}-tail"; backup="$work/backups"
fi
if [[ "$phase" == ports ]]; then
    work="${work}-$phase"; logs="${logs}-$phase"; backup="$work/backups"
fi
if [[ "$phase" == extension || "$phase" == extension-r2 ]]; then
    [[ -f "${PGCC_LIVE_EXTENSION:-}" ]] || exit 2
    suffix=x; [[ "$phase" != extension-r2 ]] || suffix=x2
    c="${c}$suffix"; work="${work}-$phase"; logs="${logs}-$phase"; data_root="${data_root}-$phase"; backup="$work/backups"
fi
creator=/usr/local/bin/create-claster.sh
builder=/usr/local/share/pg_claster_creator/create-claster-deb.sh
wrapper=/usr/local/bin/create-claster-backup.sh
db_fingerprint() {
    runuser -u postgres -- pg_dump --cluster "$v/$1" -d "$2" --no-comments | sed '/^\\restrict /d; /^\\unrestrict /d' | sha256sum | awk '{print $1}'
}
role_fingerprint() {
    runuser -u postgres -- psql --cluster "$v/$1" -X -Atqc "SELECT rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls FROM pg_roles WHERE rolname LIKE 'pgcc_%' ORDER BY rolname" postgres | sha256sum | awk '{print $1}'
}
verify_reference() {
    local target="$1" db="$2" actual target_port
    actual="$(db_fingerprint "$target" "$db")" || return 1
    printf 'dump_sha=%s expected=%s\n' "$actual" "$(<"$core_work/source.dump.sha")"
    [[ "$actual" == "$(<"$core_work/source.dump.sha")" ]] || return 1
    [[ "$(role_fingerprint "$target")" == "$(<"$core_work/source.roles.sha")" ]] || return 1
    target_port="$(pg_lsclusters --no-header | awk -v v="$v" -v n="$target" '$1==v && $2==n {print $3}')"
    [[ "$(PGPASSWORD='Pgcc-ACL-2.1.1!' psql --cluster "$v/$target" -h 127.0.0.1 -p "$target_port" -U pgcc_acl_login -d "$db" -X -Atqc 'SELECT count(*) FROM pgcc_owner.parent_control')" == 100 ]]
}
if [[ "$phase" == cleanup-only || "$phase" == cleanup-ui ]]; then
    [[ -f "$work/original-clusters" && -f "$work/config-shared" && -f "$work/config-share" ]] || exit 2
else
[[ ! -e "$work" && ! -e "$logs" ]] || exit 2
[[ "$phase" == ports || ( ! -e "$data_root" && ! -L "$data_root" ) ]] || exit 2
mkdir -p "$logs" "$work" "$backup"
chmod 700 "$work"
pg_lsclusters --no-header >"$work/original-clusters"
for name in "$c" "${c}ren" "${c}cold" "${c}m2" "${c}m3" "${c}m4"; do
    ! awk -v n="$name" '$2==n {found=1} END {exit !found}' "$work/original-clusters" || exit 2
    [[ ! -e "/etc/postgresql/$v/$name" ]] || exit 2
done
cp -a /usr/local/shared/pg_claster_creator/.new-claster.config "$work/config-shared"
cp -a /usr/local/share/pg_claster_creator/.new-claster.config "$work/config-share"
cp -a "$work/config-shared" "$work/last-config-shared"
cp -a "$work/config-share" "$work/last-config-share"
sha256sum "$repo/.new-claster.config" >"$work/project-config.sha"
fi
exec >>"$logs/run.log" 2>&1
step() {
    local id="$1" expected="$2" rc; shift 2
    printf 'START %s %s\n' "$id" "$(date --iso-8601=seconds)"
    # Store full command output, with credentials redacted before publication.
    printf 'COMMAND '; printf '%q ' "$@" | sed -E 's/Pgcc-[^ ]*/[REDACTED]/g'; printf '\n'
    set +e
    "$@" >"$work/current.log" 2>&1; rc=$?
    set -e
    sed -E '/(password_hash=|PASSWORD |PGPASSWORD=|--password|Пароль)/I s/.*/[REDACTED credential line]/' "$work/current.log" >"$logs/$id.log"
    printf 'END %s rc=%s %s\n' "$id" "$rc" "$(date --iso-8601=seconds)"
    pg_lsclusters >"$logs/$id-clusters.log"
    sha256sum /usr/local/shared/pg_claster_creator/.new-claster.config /usr/local/share/pg_claster_creator/.new-claster.config >"$logs/$id-config-sha.log"
    # Compare protected defaults as values; permitted family/locale/backup changes are excluded.
    protected_defaults() {
        ( source "$1"; printf '%s\0' "${cls_pt-}" "${cls_nm-}" "${cls_ch-}" "${cls_us-}" "${cls_pw-}" ) | sha256sum
    }
    if [[ "$(protected_defaults "$work/config-shared")" != "$(protected_defaults /usr/local/shared/pg_claster_creator/.new-claster.config)" ]]; then
        printf '%s-CONFIG-DEFAULTS\tFAIL\tprotected defaults changed\n' "$id" >>"$logs/results.tsv"
    fi
    cp -a /usr/local/shared/pg_claster_creator/.new-claster.config "$work/last-config-shared"
    cp -a /usr/local/share/pg_claster_creator/.new-claster.config "$work/last-config-share"
    systemctl list-units --all --no-pager 'postgres*' 'tantor*' >"$logs/$id-services.log" 2>&1 || true
    find "$work" -maxdepth 2 -type f -printf '%p %s bytes\n' >"$logs/$id-files.log"
    if [[ "$expected" == nonzero && "$rc" != 0 && "$rc" != 124 && "$rc" != 137 ]] || [[ "$rc" == "$expected" ]]; then
        printf '%s\tPASS\trc=%s\n' "$id" "$rc" >>"$logs/results.tsv"
        return 0
    fi
    printf '%s\tFAIL\trc=%s\n' "$id" "$rc" >>"$logs/results.tsv"
    return 1
}
cleanup() {
    local rc=$? name row data clean=0
    trap - EXIT
    set +e
    if declare -F cleanup_ui_artifacts >/dev/null; then cleanup_ui_artifacts || clean=1; fi
    if [[ -n "${listener:-}" ]]; then kill "$listener" 2>/dev/null; wait "$listener" 2>/dev/null; fi
    # Restrict deletion to names absent from the original registry, not all clusters.
    for name in "${c}m4" "${c}m3" "${c}m2" "${c}cold" "${c}ren" "$c"; do
        row="$(pg_lsclusters --no-header | awk -v n="$name" -v v="$v" '$1==v && $2==n')"
        [[ -n "$row" ]] || continue
        data="$(awk '{print $6}' <<<"$row")"
        case "$data" in /var/lib/postgresql/*/"$name"|"$data_root"/*/"$name") ;;
            *) printf 'Unsafe cleanup path: %s\n' "$data"; clean=1; continue ;;
        esac
        step "cleanup-$name" 0 timeout -k 5 180 "$creator" --action delete "$v" "$name" --backup-before-delete no || clean=1
    done
    # Restore scripts-only packaging after deployment-mode tests.
    if [[ -f "$work/deployed-mode" ]]; then
        step restore-mode1 0 timeout -k 5 180 dpkg --force-confdef --force-confold -i "$repo/dist/claster-creator-$release.deb" || clean=1
    fi
    for location in shared share; do
        if cmp -s "$work/last-config-$location" "/usr/local/$location/pg_claster_creator/.new-claster.config"; then
            cp -a "$work/config-$location" "/usr/local/$location/pg_claster_creator/.new-claster.config"
        else
            printf 'Concurrent config change detected in %s; NOT restoring baseline\n' "$location"
            clean=1
        fi
    done
    step config-shared-restored 0 cmp "$work/config-shared" /usr/local/shared/pg_claster_creator/.new-claster.config || clean=1
    step project-config-unchanged 0 sha256sum -c "$work/project-config.sha" || clean=1
    pg_lsclusters --no-header >"$work/final-clusters"
    step originals-preserved 0 cmp "$work/original-clusters" "$work/final-clusters" || clean=1
    # Keep protected archives and artifacts for diagnosis; remove only empty owned roots.
    rmdir "$data_root/pg_$v" "$data_root" 2>/dev/null || true
    find "$work" -maxdepth 3 -type f \( -name '*.tar.gz' -o -name '*.deb' \) -exec sha256sum {} + >"$logs/artifact-sha256.log"
    printf 'FINAL run_rc=%s cleanup_rc=%s artifacts=%s\n' "$rc" "$clean" "$work"
    ((rc==0 && clean==0))
}
trap cleanup EXIT
[[ "$phase" != cleanup-only && "$phase" != cleanup-ui ]] || exit 0
if [[ "$phase" == extension || "$phase" == extension-r2 ]]; then
    source "$PGCC_LIVE_EXTENSION"
    exit 0
fi
if [[ "$phase" == ui || "$phase" == tail ]]; then
    source "$repo/tools/prx-test-live-ui.sh"
    exit 0
fi
if [[ "$phase" == extra ]]; then
    source "$repo/tools/prx-test-live-extra.sh"
    exit 0
fi
if [[ "$phase" == ports ]]; then
    source "$repo/tools/prx-test-live-ports.sh"
    exit 0
fi
step CREATE 0 timeout -k 5 900 "$creator" --action install --package "$package" --pg-version "$v" --cluster-name "$c" --port "$port" --schema pgcc_owner --user pgcc_user --password 'Pgcc-QA-2.1.1!' --backup-dir "$backup"
step DATA 0 timeout -k 5 180 bash "$repo/tools/prx-prepare-postgres-test-data.sh" "$v" "$c" "$port"
sql() { runuser -u postgres -- psql --cluster "$v/$1" -X --set=ON_ERROR_STOP=1 --dbname "$2" -Atqc "$3"; }
query="SELECT count(*), md5(string_agg(id::text || ':' || payload || ':' || qty::text, ',' ORDER BY id)) FROM ONLY pgcc_owner.parent_control"
baseline="$(sql "$c" "$c" "$query")"
db_fingerprint "$c" "$c" >"$work/source.dump.sha"
role_fingerprint "$c" >"$work/source.roles.sha"
step SOURCE-FULL 0 verify_reference "$c" "$c"
step INFO 0 timeout -k 5 30 "$creator" --action info
step HOT 0 timeout -k 5 900 bash "$repo/tools/prx-test-postgres-backups.sh" "$v" "$c" hot "$c" "$backup" "$creator"
step COLD 0 timeout -k 5 900 bash "$repo/tools/prx-test-postgres-backups.sh" "$v" "$c" cold "$c" "$backup" "$creator"
hot="$(find "$backup" -maxdepth 1 -name '*-dmp.tar.gz' -print -quit)"
cold="$(find "$backup" -maxdepth 1 -name "$v-$c-????????-??????.tar.gz" -print -quit)"
step HOT-RESTORE 0 timeout -k 5 900 "$creator" --action restore --backup-file "$hot" --pg-version "$v" --cluster-name "$c" --database qa_restore --backup-dir "$backup"
step HOT-CHECK 0 test "$(sql "$c" qa_restore "$query")" = "$baseline"
step HOT-FULL 0 verify_reference "$c" qa_restore
step HOT-MUTATE 0 sql "$c" qa_restore 'CREATE TABLE public.qa_stale(id int); UPDATE pgcc_owner.parent_control SET qty=qty+100'
changed="$(sql "$c" qa_restore "$query")"
step HOT-REFUSE nonzero timeout -k 5 120 "$creator" --action restore --backup-file "$hot" --pg-version "$v" --cluster-name "$c" --database qa_restore --backup-dir "$backup"
step HOT-REFUSE-PRESERVED 0 test "$(sql "$c" qa_restore "$query")" = "$changed"
step HOT-OVERWRITE 0 timeout -k 5 900 "$creator" --action restore --backup-file "$hot" --pg-version "$v" --cluster-name "$c" --database qa_restore --overwrite yes --backup-dir "$backup"
step HOT-OVERWRITE-CHECK 0 test "$(sql "$c" qa_restore "$query")" = "$baseline"
step HOT-STALE-REMOVED 0 test "$(sql "$c" qa_restore "SELECT to_regclass('public.qa_stale') IS NULL")" = t
step HOT-OVERWRITE-FULL 0 verify_reference "$c" qa_restore
step PORT-DATA 0 timeout -k 5 900 bash "$repo/tools/prx-test-postgres-port-data.sh" "$v" "$c" "$port" "$((port+50))" "$c" "$query" "$data_root" - "$creator"
step COLD-RESTORE 0 timeout -k 5 900 "$creator" --action restore --backup-file "$cold" --cluster-name "${c}cold" --port "$((port+1))" --data-root "$data_root" --backup-dir "$backup"
step COLD-CHECK 0 test "$(sql "${c}cold" "$c" "$query")" = "$baseline"
step COLD-FULL 0 verify_reference "${c}cold" "$c"
step COLD-CONFLICT nonzero timeout -k 5 120 "$creator" --action restore --backup-file "$cold" --cluster-name "${c}cold" --port "$((port+1))" --backup-dir "$backup"
for n in 1 2 3; do
    step "ROTATION-$n" 0 timeout -k 5 900 "$wrapper" "$v" "$c" "$c" --backup-dir "$work/rotation" --files-cnt 2
    sleep 1
done
step ROTATION-COUNT 0 test "$(find "$work/rotation" -name '*-dmp.tar.gz' | wc -l)" = 2
step ROTATION-SIZE 0 timeout -k 5 900 "$wrapper" "$v" "$c" "$c" --backup-dir "$work/rotation" --files-size 1B
step ROTATION-MINIMUM 0 test "$(find "$work/rotation" -name '*-dmp.tar.gz' | wc -l)" = 1
mkdir "$work/debs"
for mode in 2 3 4; do
    args=(--mode "$mode" --non-interactive --pg-family "$family" --pg-version "$v" --package "$package" --cluster-name "${c}m$mode" --port "$((port+mode+1))" --output-dir "$work/debs" --data-root "$data_root")
    case "$mode" in
        2) args+=(--schema pgcc_owner --user pgcc_user --password 'Pgcc-QA-2.1.1!') ;;
        3) args+=(--backup-file "$cold") ;;
        4) args+=(--backup-file "$hot" --database qa_m4 --schema pgcc_owner --user pgcc_user --password 'Pgcc-QA-2.1.1!') ;;
    esac
    step "DEB-BUILD-$mode" 0 timeout -k 5 900 bash "$builder" "${args[@]}"
    deb="$(find "$work/debs" -name "*-${c}m$mode-*.deb" -print -quit)"
    [[ -n "$deb" ]]
    # dpkg reads the local package as root; APT can still fetch dependencies.
    touch "$work/deployed-mode"
    step "DEB-INSTALL-$mode" 0 timeout -k 5 900 env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --reinstall "$deb"
    step "DEB-ONLINE-$mode" 0 pg_isready -h 127.0.0.1 -p "$((port+mode+1))"
    case "$mode" in
        3) step DEB-COLD-CHECK 0 test "$(sql "${c}m3" "$c" "$query")" = "$baseline" ;;
        4) step DEB-HOT-CHECK 0 test "$(sql "${c}m4" qa_m4 "$query")" = "$baseline" ;;
    esac
    step "DEB-REINSTALL-$mode" 0 timeout -k 5 900 env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --reinstall "$deb"
    case "$mode" in
        3) step DEB-COLD-FULL 0 verify_reference "${c}m3" "$c" ;;
        4) step DEB-HOT-FULL 0 verify_reference "${c}m4" qa_m4 ;;
    esac
done
printf 'CORE COMPLETED\n'
