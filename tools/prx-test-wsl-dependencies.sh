#!/usr/bin/env bash
# Purpose: actual APT and dpkg+APT dependency installation, reusing approved removal wrapper.
# Usage: PGCC_TEST_RELEASE=VERSION PGCC_TEST_RUN=RUN bash tools/prx-test-wsl-dependencies.sh DISTRO PACKAGE MAJOR FAMILY PORT
# Args: exact WSL name, original server package, major, family and completed core run port.
# Output: dependency transactions and checks; removes packages and QA clusters on the selected disposable WSL.
# Example: PGCC_TEST_RELEASE=2.5.2 PGCC_TEST_RUN=qa-run bash tools/prx-test-wsl-dependencies.sh mint22-3 postgresql-16 16 postgresql 60800
# Path note: adjust /mnt/d/Ai/pg_claster_creator and /mnt/d/Ai/pg_claster_creator.backup if they do not match the actual workspace.
set -Eeuo pipefail
repo="${PGCC_TEST_REPO:-/mnt/d/Ai/pg_claster_creator}"
release="${PGCC_TEST_RELEASE:?release required}"; token="${release//./}"
base=/mnt/d/Ai/pg_claster_creator.backup/TEST-${release}
distro="$1"; package="$2"; v="$3"; family="$4"; port="$5"
[[ "$WSL_DISTRO_NAME" == "$distro" && "$port" =~ ^[0-9]+$ ]] || exit 2
[[ -z "${PGCC_TEST_RUN:-}" ]] || base="$base/$distro/$PGCC_TEST_RUN"
mkdir -p "$base/$distro"
logs="$base/$distro/dependencies"; [[ ! -e "$logs" ]]; mkdir "$logs"
exec >"$logs/run.log" 2>&1
core="/var/tmp/pgcc${token}-$port"; target="qa${token}_${port}m4"
deb="$(find "$core/debs" -maxdepth 1 -name "*-$target-*.deb" -print -quit)"
[[ -f "$deb" ]]; dpkg-deb -f "$deb" Depends >"$logs/depends.log"
[[ -z "$(pg_lsclusters --no-header)" ]] || exit 2
step() { local id="$1" expected="$2" rc; shift 2; set +e; "$@" >"$logs/$id.log" 2>&1; rc=$?; set -e; printf '%s\trc=%s expected=%s\n' "$id" "$rc" "$expected" | tee -a "$logs/results.tsv"; [[ "$rc" == "$expected" || ( "$expected" == nonzero && "$rc" != 0 && "$rc" != 124 && "$rc" != 137 ) ]]; }
cleanup() {
 local rc=$? clean=0; trap - EXIT; set +e
 if command -v pg_lsclusters >/dev/null && pg_lsclusters --no-header | awk -v n="$target" '$2==n {found=1} END {exit !found}'; then
   step cleanup 0 timeout -k 5 180 bash "$repo/create-claster.sh" --action delete "$v" "$target" --backup-before-delete no || clean=1
 fi
 step restore-product 0 timeout -k 5 180 dpkg --force-confold -i "$repo/dist/claster-creator-${release}.deb" || clean=1
 dpkg --audit >"$logs/audit.log"; [[ ! -s "$logs/audit.log" ]] || clean=1
 printf 'FINAL rc=%s cleanup=%s\n' "$rc" "$clean"
 ((rc==0 && clean==0))
}
trap cleanup EXIT
for method in apt dpkg; do
 attempt=resume3; [[ "$method" != dpkg ]] || attempt=resume4
 step "$method-remove" 0 env PGCC_BOOTSTRAP_REMOVE_ONLY=1 bash "$repo/tools/prx-bootstrap-wsl-postgres.sh" "$distro" "$package" "$v" "$family" "$port" "$attempt"
 if [[ "$method" == apt ]]; then
   step apt-install 0 timeout -k 10 900 env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y "$deb"
 else
   step dpkg-missing nonzero timeout -k 5 180 dpkg --force-confold -i "$deb"
   step dpkg-diagnostic 0 grep -Ei 'depend|зависим' "$logs/dpkg-missing.log"
   LC_ALL=C apt-get -s -f install >"$logs/apt-f-plan.log"
   ! grep -q '^Remv ' "$logs/apt-f-plan.log" || { echo 'REFUSE apt-f removal instead of dependency installation'; exit 2; }
   step apt-f-install 0 timeout -k 10 900 env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold -y -f install
 fi
 dpkg-query -W -f='${binary:Package}\t${Status}\t${Version}\n' postgresql-common postgresql-client-common "$package" claster-creator >"$logs/$method-installed.log"
 [[ "$(grep -c 'install ok installed' "$logs/$method-installed.log")" == 4 ]]
 step "$method-data" 0 runuser -u postgres -- psql --cluster "$v/$target" -X -Atqc 'SELECT count(*) FROM pgcc_owner.parent_control' qa_m4
 step "$method-count" 0 grep -x 100 "$logs/$method-data.log"
 step "$method-delete" 0 timeout -k 5 180 bash "$repo/create-claster.sh" --action delete "$v" "$target" --backup-before-delete no
 step "$method-product" 0 timeout -k 5 180 dpkg --force-confold -i "$repo/dist/claster-creator-${release}.deb"
done
