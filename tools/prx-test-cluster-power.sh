#!/usr/bin/env bash
# Purpose: test interactive start/stop menus without touching real clusters.
# Usage: bash tools/prx-test-cluster-power.sh REPO
# Args: REPO -- directory containing create-claster.sh.
# Output: PASS for state, selection, confirmation, cancellation and race handling.
# Example: bash tools/prx-test-cluster-power.sh /mnt/d/Ai/pg_claster_creator
set -Eeuo pipefail
repo="$(realpath "$1")"
fixture="$(mktemp -d /tmp/pgcc-power-test.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
source "$repo/create-claster.sh"
# Sourcing the product installs its EXIT trap; restore ownership of this fixture.
trap 'rm -rf -- "$fixture"' EXIT
NON_INTERACTIVE=0
header() { :; }; step() { :; }; pause() { :; }
pg_lsclusters() {
    [[ ! -f "$fixture/fail" ]] || return 1
    printf '18 demo 5432 %s postgres /unused /unused\n' "$(<"$fixture/state")"
    [[ ! -f "$fixture/duplicate" ]] || printf '16 demo 5433 down postgres /unused2 /unused2\n'
    return 0
}
stop_cluster_checked() { printf 'stop %s/%s\n' "$1" "$2" >>"$fixture/events"; printf down >"$fixture/state"; }
start_cluster_checked() { printf 'start %s/%s\n' "$1" "$2" >>"$fixture/events"; printf online >"$fixture/state"; }
printf down >"$fixture/state"
cluster_power_menu <<<$'demo\n' >"$fixture/output"
[[ ! -e "$fixture/events" && "$(<"$fixture/state")" == down ]]
cluster_power_menu <<<$'demo\nn' >"$fixture/output"
[[ ! -e "$fixture/events" ]]
cluster_power_menu <<<$'demo\ny' >"$fixture/output"
[[ "$(<"$fixture/events")" == 'start 18/demo' && "$(<"$fixture/state")" == online ]]
cluster_power_menu <<<$'1\nn' >"$fixture/output"
[[ "$(wc -l <"$fixture/events")" == 1 ]]
cluster_power_menu <<<$'1\ny' >"$fixture/output"
[[ "$(<"$fixture/events")" == $'start 18/demo\nstop 18/demo' ]]
cluster_power_menu <<<$'demo\nn' >"$fixture/output"
cluster_power_menu <<<0 >"$fixture/output"
cluster_power_menu <<<9 >"$fixture/output"
cluster_power_menu <<<$'missing\ny' >"$fixture/output"
touch "$fixture/duplicate"
cluster_power_menu <<<$'demo\ny' >"$fixture/output"
rm -- "$fixture/duplicate"
[[ "$(wc -l <"$fixture/events")" == 2 ]]
touch "$fixture/fail"
! cluster_power_state 18 demo
cluster_power_menu <<<$'demo\ny' >"$fixture/output"
rm -- "$fixture/fail"
(
    confirm() { [[ "$2" == N ]]; printf online >"$fixture/state"; return 0; }
    cluster_power_menu <<<demo >"$fixture/output"
)
[[ "$(wc -l <"$fixture/events")" == 2 ]]
bash -n "$repo/create-claster.sh"
printf 'PASS: start/stop, name/index, y/N default, cancellation, ambiguous name, listing failure, state race\n'
