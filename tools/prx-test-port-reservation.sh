#!/usr/bin/env bash
# Usage: bash tools/prx-test-port-reservation.sh REPO
# Isolated port-range reservation tests; no listeners, packages or clusters.
set -Eeuo pipefail
repo="$(realpath "$1")"
work="$(mktemp -d /tmp/pgcc-ports.XXXXXXXX)"
trap 'rm -rf -- "$work"' EXIT
source "$repo/tools/prx-test-port.sh"
ss() { return 0; }
for i in {1..8}; do
    (
        reserve_test_port "$work/leases" "run-$i"
        printf '%s\n' "$port" >"$work/port-$i"
    ) &
done
wait
[[ "$(cat "$work/"port-* | sort -u | wc -l)" == 8 ]]
if reserve_test_port "$work/leases" ninth; then exit 1; fi
port_lease="$work/leases/$(cat "$work/port-1")"
if release_test_port wrong-owner; then exit 1; fi
release_test_port run-1
reserve_test_port "$work/leases" replacement "$(cat "$work/port-1")"
release_test_port replacement
ss() { printf 'LISTEN 0 100 0.0.0.0:60101 0.0.0.0:*\n'; }
if reserve_test_port "$work/busy" busy 60100; then exit 1; fi
[[ ! -e "$work/busy/60100" ]]
ss() { return 1; }
if reserve_test_port "$work/error" error 60100; then exit 1; fi
[[ ! -e "$work/error/60100" ]]
printf 'PASS eight concurrent distinct random ranges, exhaustion, owner guard, release, occupied ports and ss failure\n'
