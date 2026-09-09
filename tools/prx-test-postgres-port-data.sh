#!/usr/bin/env bash
# Purpose: test TCP port round-trip and move PostgreSQL data with query comparison.
# Usage:
#   bash prx-test-postgres-port-data.sh VERSION CLUSTER OLD_PORT NEW_PORT DB [QUERY MOVE_ROOT RETURN_ROOT CREATOR]
# Args:
#   QUERY defaults to the pgcc control-table checksum; MOVE_ROOT defaults to /DATA/pgcc-move-test.
#   RETURN_ROOT defaults to /DATA/pgcc-deb-test; '-' keeps data at MOVE_ROOT.
#   CREATOR defaults to create-claster.sh. Requires a disposable online cluster.
# Output:
#   Port readiness, data path, query results and /var/log/pgcc-tests log; nonzero on failure.
# Example:
#   bash prx-test-postgres-port-data.sh 16 qa 55432 55433 asvd 'SELECT 1' /DATA - /opt/project/create-claster.sh

set -uo pipefail

pg_version="$1"
cluster_name="$2"
old_port="$3"
new_port="$4"
database_name="$5"
log_file="/var/log/pgcc-tests/pt-cc-09-10-${cluster_name}.log"
query="${6:-SELECT count(*), md5(string_agg(id::text || chr(58) || payload || chr(58) || qty::text, chr(44) ORDER BY id)) FROM ONLY pgcc_owner.parent_control}"
move_root="${7:-/DATA/pgcc-move-test}"
return_root="${8:-/DATA/pgcc-deb-test}"
creator="${9:-create-claster.sh}"

exec > >(tee "${log_file}") 2>&1

printf 'before='
baseline="$(runuser -u postgres -- psql --cluster "${pg_version}/${cluster_name}" \
    --dbname "${database_name}" -Atqc "${query}")" || exit $?
printf '%s\n' "$baseline"

timeout 180 "$creator" --action port --pg-version "${pg_version}" \
    --cluster-name "${cluster_name}" --port "${new_port}"
port_to_new_rc=$?
printf 'port_to_new_rc=%s\n' "${port_to_new_rc}"
((port_to_new_rc == 0)) || exit "${port_to_new_rc}"

pg_isready -h 127.0.0.1 -p "${old_port}"
old_ready_rc=$?
printf 'old_port_rc=%s\n' "$old_ready_rc"
((old_ready_rc == 2)) || exit 1
pg_isready -h 127.0.0.1 -p "${new_port}"
new_ready_rc=$?
printf 'new_port_rc=%s\n' "${new_ready_rc}"
((new_ready_rc == 0)) || exit "${new_ready_rc}"

timeout 180 "$creator" --action port --pg-version "${pg_version}" \
    --cluster-name "${cluster_name}" --port "${old_port}" || exit $?
printf 'port_back_rc=0\n'

timeout 300 "$creator" --action move-data --pg-version "${pg_version}" \
    --cluster-name "${cluster_name}" --data-root "$move_root" || exit $?
printf 'move_out_rc=0\n'
pg_lsclusters --no-header | awk -v v="${pg_version}" -v c="${cluster_name}" \
    '$1 == v && $2 == c'
printf 'after_move='
after="$(runuser -u postgres -- psql --cluster "${pg_version}/${cluster_name}" \
    --dbname "${database_name}" -Atqc "${query}")" || exit $?
printf '%s\n' "$after"
[[ "$after" == "$baseline" ]] || exit 1
actual_data="$(runuser -u postgres -- psql --cluster "${pg_version}/${cluster_name}" --dbname "$database_name" -Atqc 'SHOW data_directory')" || exit $?
[[ "$actual_data" == "$move_root/pg_$pg_version/$cluster_name" ]] || exit 1
[[ "$return_root" != - ]] || exit 0

timeout 300 "$creator" --action move-data --pg-version "${pg_version}" \
    --cluster-name "${cluster_name}" --data-root "$return_root" || exit $?
printf 'move_back_rc=0\n'
printf 'after_return='
runuser -u postgres -- psql --cluster "${pg_version}/${cluster_name}" \
    --dbname "${database_name}" -Atqc "${query}" || exit $?
pg_lsclusters --no-header | awk -v v="${pg_version}" -v c="${cluster_name}" \
    '$1 == v && $2 == c'
