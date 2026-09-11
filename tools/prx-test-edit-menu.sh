#!/usr/bin/env bash
# Purpose: verify main/edit menu dispatch without changing clusters.
# Usage: bash tools/prx-test-edit-menu.sh REPO
# Args: REPO -- source directory containing create-claster.sh.
# Output: PASS for nesting, numbering, back, invalid input and EOF.
# Example: bash tools/prx-test-edit-menu.sh /mnt/d/Ai/pg_claster_creator
set -Eeuo pipefail
repo="$(realpath "$1")"
fixture="$(mktemp -d /tmp/pgcc-edit-menu.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
source "$repo/create-claster.sh"
header() { printf 'SCREEN\n'; }
step() { printf '%s\n' "$1"; }
rename_cluster_menu() { printf 'rename\n' >>"$fixture/events"; }
change_port_menu() { printf 'port\n' >>"$fixture/events"; }
move_cluster_data_menu() { printf 'data\n' >>"$fixture/events"; }
backup_menu() { printf 'backup\n' >>"$fixture/events"; }
restore_menu() { printf 'restore\n' >>"$fixture/events"; }
delete_menu() { printf 'delete\n' >>"$fixture/events"; }
(main_menu <<<$'4\n1\n2\n3\n0\n5\n6\n7\n0') >"$fixture/output"
[[ "$(<"$fixture/events")" == $'rename\nport\ndata\nbackup\nrestore\ndelete' ]]
grep -q '^4 - Кластер: Изменить$' "$fixture/output"
! grep -q '^8 - ' "$fixture/output"
[[ "$(grep -c '^Кластер: Изменить$' "$fixture/output")" == 4 ]]
for input in 0 9 invalid ''; do
    change_cluster_menu <<<"$input" >/dev/null
done
change_cluster_menu </dev/null >/dev/null
[[ "$(wc -l <"$fixture/events")" == 6 ]]
bash -n "$repo/create-claster.sh"
printf 'PASS: main/edit menu routing, return after action, back, invalid input, EOF\n'
