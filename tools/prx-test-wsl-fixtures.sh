#!/usr/bin/env bash
# Environment: PGCC_TEST_HOST overrides the WSL evidence label for local Linux;
# PGCC_TEST_OUTPUT overrides the per-release evidence root (also on local Linux).
# Purpose: run existing isolated suites for this full test without changing clusters.
# Usage: PGCC_TEST_RELEASE=VERSION PGCC_TEST_RUN=RUN bash tools/prx-test-wsl-fixtures.sh DISTRO
# Args: DISTRO must match WSL_DISTRO_NAME; release and run select fresh evidence directories.
# Output: per-suite logs and fixture-suites.tsv; test package artifacts need final cleanup.
# Example: PGCC_TEST_RELEASE=2.5.2 PGCC_TEST_RUN=qa-run bash tools/prx-test-wsl-fixtures.sh mint22-3
# Path note: adjust /mnt/d/Ai/pg_claster_creator and /mnt/d/Ai/pg_claster_creator.backup if they do not match the actual workspace.
set -uo pipefail
repo="${PGCC_TEST_REPO:-/mnt/d/Ai/pg_claster_creator}"
release="${PGCC_TEST_RELEASE:?release required}"; token="${release//./}"
base="${PGCC_TEST_OUTPUT:-/mnt/d/Ai/pg_claster_creator.backup/TEST-${release}}"
distro="$1"; [[ "${PGCC_TEST_HOST:-${WSL_DISTRO_NAME:-}}" == "$distro" ]] || exit 2
[[ -z "${PGCC_TEST_RUN:-}" ]] || base="$base/$distro/$PGCC_TEST_RUN"
mkdir -p "$base/$distro"
summary="$base/$distro/fixture-suites.tsv"
[[ ! -e "$summary" ]] || exit 2
run() { local id="$1"; shift; "$@"; local rc=$?; printf '%s\t%s\n' "$id" "$rc" >>"$summary"; }
run release bash "$repo/tools/prx-test-release-fixtures.sh" "$repo" "$distro" ${release} "$base"
run contracts bash "$repo/tools/prx-test-full-contracts.sh" "$repo" "$base/$distro/contracts"
run package-identity bash "$repo/tools/prx-test-package-identity.sh" "$repo"
run screen python3 "$repo/tools/prx-test-screen-log-permissions.py" "$repo" "$base/$distro/screen"
run menu-sql bash "$repo/tools/prx-test-menu-sql.sh" "$repo" "$base/$distro/menu-sql"
run deb-sql bash "$repo/tools/prx-test-deb-sql.sh" "$repo" "$base/$distro/deb-sql"
run deb-existing bash "$repo/tools/prx-test-deb-existing.sh" "$repo" "$base/$distro/deb-existing"
run markdown bash "$repo/tools/prx-test-package-journal.sh" "$repo" ${release} unused "$base/$distro/markdown"
run guards bash "$repo/tools/prx-test-backup-guards.sh" "$repo" "$distro" "$base" r${token}
run syslog bash "$repo/tools/prx-test-wsl-syslog.sh" "$repo" >"$base/$distro/syslog-fixture.log" 2>&1
! grep -v $'\t0$' "$summary"
