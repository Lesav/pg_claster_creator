#!/usr/bin/env bash
# Purpose: isolated selection/keep-server regression; no real package/cluster changes.
# Usage: bash tools/prx-test-server-selection.sh REPO
# Environment: none; all system commands used by preparation are test-local stubs.
set -Eeuo pipefail
repo="$(realpath "$1")"
work="$(mktemp -d /tmp/pgcc-selection.XXXXXXXX)"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin" "$work/repo"
for function in package_to_fields server_family_priority; do
    sed -n "/^$function() {/,/^}/p" "$repo/create-claster.sh" >>"$work/repo/create-claster.sh"
done
cat >>"$work/repo/create-claster.sh" <<'SH'
package_available() { return 0; }
ensure_postgresql_common() { echo common >>"$QA_EVENTS"; }
install_package() { echo "install $1" >>"$QA_EVENTS"; }
SH
cat >"$work/bin/dpkg-query" <<'SH'
#!/usr/bin/env bash
[[ -z "$QA_PACKAGE" ]] || printf '%s\tinstalled\n' "$QA_PACKAGE"
exit 0
SH
cat >"$work/bin/pg_lsclusters" <<'SH'
#!/usr/bin/env bash
[[ "$QA_CLUSTER" == no ]] || printf '16 existing 5432 down postgres /data /log\n'
exit 0
SH
cat >"$work/bin/apt-cache" <<'SH'
#!/usr/bin/env bash
[[ -z "$QA_PACKAGE" ]] || exit 91
printf '%s\n' postgresql-18 tantor-free-server-16 tantor-be-server-18 tantor-se-server-16 postgrespro-ent-17-server
SH
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH" QA_EVENTS="$work/events" QA_PACKAGE=tantor-free-server-16 QA_CLUSTER=yes
: >"$QA_EVENTS"
bash "$repo/tools/prx-prepare-test-server.sh" "$work/repo" "$work/existing"
grep -Fxq $'tantor-free-server-16\ttantor-free\t16\t1' "$work/existing/selection.tsv"
[[ ! -s "$QA_EVENTS" ]]
export QA_CLUSTER=no
bash "$repo/tools/prx-prepare-test-server.sh" "$work/repo" "$work/empty"
grep -Fxq $'tantor-free-server-16\ttantor-free\t16\t0' "$work/empty/selection.tsv"
[[ ! -s "$QA_EVENTS" ]]
export QA_PACKAGE=tantor-free-server-16-server QA_CLUSTER=yes
bash "$repo/tools/prx-prepare-test-server.sh" "$work/repo" "$work/alias"
grep -Fxq $'tantor-free-server-16-server\ttantor-free\t16\t1' "$work/alias/selection.tsv"
[[ ! -s "$QA_EVENTS" ]]
export QA_PACKAGE='' QA_CLUSTER=no
bash "$repo/tools/prx-prepare-test-server.sh" "$work/repo" "$work/absent"
grep -Fxq $'postgrespro-ent-17-server\tpostgrespro-ent\t17\t1' "$work/absent/selection.tsv"
[[ "$(cat "$QA_EVENTS")" == $'common\ninstall postgrespro-ent-17-server' ]]
: >"$QA_EVENTS"
if bash "$repo/tools/prx-prepare-test-server.sh" "$work/repo" "$work/mismatch" postgresql-18; then exit 1; fi
[[ ! -s "$QA_EVENTS" ]]
printf 'PASS installed-first; cluster-based retention; both Tantor Free names; absent-server priority; mismatch before installation\n'
PGCC_TEST_KEEP_SERVER=1 PGCC_TEST_HOST=selection-test PGCC_TEST_RELEASE=2.5.7 \
    PGCC_TEST_RUN=run-selection PGCC_TEST_OUTPUT="$work/evidence" \
    bash "$repo/tools/prx-test-wsl-dependencies.sh" selection-test postgresql-16 16 postgresql 60800
grep -q '^SKIP dependency installation tests:' "$work/evidence/selection-test/run-selection/selection-test/dependencies/run.log"
[[ ! -s "$QA_EVENTS" ]]
printf 'PASS dependency-removal tests skipped before any package action\n'
