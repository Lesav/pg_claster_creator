#!/usr/bin/env bash
# Purpose: verify main/edit menu dispatch without changing clusters.
# Usage: bash tools/prx-test-edit-menu.sh REPO
# Args: REPO -- source directory containing create-claster.sh.
# Output: PASS for selected server heading, nesting, numbering, back and EOF.
# Example: bash tools/prx-test-edit-menu.sh /mnt/d/Ai/pg_claster_creator
set -Eeuo pipefail
repo="$(realpath "$1")"
fixture="$(mktemp -d /tmp/pgcc-edit-menu.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
source "$repo/create-claster.sh"
# Sourcing the product installs its EXIT trap; restore ownership of this fixture.
trap 'rm -rf -- "$fixture"' EXIT
header() { printf 'SCREEN\n'; }
step() { printf '%s\n' "$1"; }
# The heading must use the current selection, without querying installed packages.
installed_server_packages() { printf 'unexpected query\n' >>"$fixture/queries"; }
SELECTED_PACKAGE=tantor-se-server-17
rename_cluster_menu() { printf 'rename\n' >>"$fixture/events"; }
change_port_menu() { printf 'port\n' >>"$fixture/events"; }
move_cluster_data_menu() { printf 'data\n' >>"$fixture/events"; }
execute_sql_menu() { printf 'sql\n' >>"$fixture/events"; }
backup_menu() { printf 'backup\n' >>"$fixture/events"; }
restore_menu() { printf 'restore\n' >>"$fixture/events"; }
delete_menu() { printf 'delete\n' >>"$fixture/events"; }
(main_menu <<<$'4\n1\n2\n3\n4\n0\n5\n6\n7\n0') >"$fixture/output"
[[ "$(<"$fixture/events")" == $'rename\nport\ndata\nsql\nbackup\nrestore\ndelete' ]]
grep -q '^4 - Кластер: Изменить$' "$fixture/output"
grep -Fxq 'Выбор действия: <tantor-se-server-17>' "$fixture/output"
! grep -q '^8 - ' "$fixture/output"
[[ "$(grep -c '^Кластер: Изменить$' "$fixture/output")" == 5 ]]
for input in 0 9 invalid ''; do
    change_cluster_menu <<<"$input" >/dev/null
done
change_cluster_menu </dev/null >/dev/null
[[ "$(wc -l <"$fixture/events")" == 7 ]]
SELECTED_PACKAGE=tantor-free-server-16
(main_menu <<<0) >"$fixture/output"
grep -Fxq 'Выбор действия: <tantor-free-server-16>' "$fixture/output"
restore_menu() { SELECTED_PACKAGE=postgrespro-ent-16-server; }
(main_menu <<<$'6\n0') >"$fixture/output"
grep -Fxq 'Выбор действия: <tantor-free-server-16>' "$fixture/output"
grep -Fxq 'Выбор действия: <postgrespro-ent-16-server>' "$fixture/output"
SELECTED_PACKAGE=""
(main_menu <<<0) >"$fixture/output"
grep -Fxq 'Выбор действия: <сервер не выбран>' "$fixture/output"
[[ ! -e "$fixture/queries" ]]
bash -n "$repo/create-claster.sh"
printf 'PASS: selected server heading, refreshed selection, no package queries, main/edit routing, back, invalid input, EOF\n'
