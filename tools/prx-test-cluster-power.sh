#!/usr/bin/env bash
# Path note: If /mnt/d/Ai/pg_claster_creator in the example does not match
# your filesystem, replace it with the actual project path before running.
# Purpose: test start/stop menus and stop notifications without touching real clusters.
# Usage: bash tools/prx-test-cluster-power.sh REPO
# Args: REPO -- directory containing create-claster.sh.
# Output: PASS for state, selection, confirmation, cancellation and race handling.
# Example: bash tools/prx-test-cluster-power.sh /mnt/d/Ai/pg_claster_creator
set -Eeuo pipefail
repo="$(realpath "$1")"
fixture="$(mktemp -d /tmp/pgcc-power-test.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
source "$repo/create-claster.sh"
real_stop_function="$(declare -f stop_cluster_checked)"
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
(
    eval "$real_stop_function"
    NON_INTERACTIVE=1
    cluster_online() { [[ "$(<"$fixture/state")" == online ]]; }
    run_parsec_aware() { printf 'STOP COMMAND\n' >&2; printf down >"$fixture/state"; }
    timeout() { :; }
    for initial in online down; do
        printf '%s' "$initial" >"$fixture/state"
        stop_cluster_checked 18 demo </dev/null >"$fixture/stop-stdout" 2>"$fixture/stop-stderr"
        [[ ! -s "$fixture/stop-stdout" ]]
        [[ "$(head -n 1 "$fixture/stop-stderr")" == 'Будет остановлен кластер 18/demo.' ]]
        grep -q '^STOP COMMAND$' "$fixture/stop-stderr"
    done
    vendor_service_name() { echo vendor-fixture.service; }
    timeout() {
        case "$3" in
            is-active) echo active ;;
            is-enabled) echo disabled ;;
            stop) grep -q '^Будет остановлена штатная служба PostgreSQL: vendor-fixture.service.$' "$fixture/vendor-stderr"; touch "$fixture/vendor-stopped" ;;
            *) return 1 ;;
        esac
    }
    stop_disable_vendor_service fixture </dev/null >"$fixture/vendor-stdout" 2>"$fixture/vendor-stderr"
    [[ ! -s "$fixture/vendor-stdout" && -f "$fixture/vendor-stopped" ]]
)
printf 'PASS: cluster/vendor stop announced before commands, stderr only, no stdin required\n'
