#!/usr/bin/env bash
# Purpose: create and inspect a hot or cold PostgreSQL backup via cluster creator.
# Usage:
#   bash prx-test-postgres-backups.sh VERSION CLUSTER TYPE [DB BACKUP_DIR CREATOR]
# Args:
#   TYPE: hot or cold; DB defaults to CLUSTER; BACKUP_DIR defaults to /BACKUP/pgcc-test.
#   CREATOR defaults to /usr/local/bin/create-claster.sh. Cold backup stops/restarts the cluster.
# Output:
#   Archive, metadata, archive-read checks and /var/log/pgcc-tests log; nonzero on failure.
# Example:
#   bash prx-test-postgres-backups.sh 16 qa hot asvd /BACKUP/qa /opt/project/create-claster.sh
set -Eeuo pipefail

pg_version="$1"
cluster_name="$2"
backup_type="$3"
backup_dir="${5:-/BACKUP/pgcc-test}"
database_name="${4:-$cluster_name}"
creator="${6:-/usr/local/bin/create-claster.sh}"
log_dir=/var/log/pgcc-tests
mkdir -p "${log_dir}" "${backup_dir}"
exec > >(tee "${log_dir}/pt-cc-backup-${backup_type}-${cluster_name}.log") 2>&1

printf 'started=%s\n' "$(date --iso-8601=seconds)"
if [[ "${backup_type}" == hot ]]; then
    timeout 900 "$creator" --action backup \
        --pg-version "${pg_version}" --cluster-name "${cluster_name}" \
        --backup-type hot --database "${database_name}" --backup-dir "${backup_dir}"
    mask="${pg_version}-${database_name}-????????-??????-dmp.tar.gz"
else
    timeout 900 "$creator" --action backup \
        --pg-version "${pg_version}" --cluster-name "${cluster_name}" \
        --backup-type cold --clear-wal no --backup-dir "${backup_dir}"
    mask="${pg_version}-${cluster_name}-????????-??????.tar.gz"
fi
rc=$?
printf 'backup_rc=%s\n' "${rc}"
archive="$(find "${backup_dir}" -maxdepth 1 -type f -name "${mask}" -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)"
printf 'archive=%s\n' "${archive}"
stat -c 'archive_stat=%a %U:%G %s %n' "${archive}"
printf '%s\n' '-- archive members --'
tar -tzf "${archive}"
printf '%s\n' '-- metadata --'
metadata_member="$(tar -tzf "${archive}" | grep -E '(^|/)backup-info\.env$' | head -1)"
tar -xOf "${archive}" "${metadata_member}" | sed -E '/(password|cls_pw|PGPASSWORD)/I s/.*/[REDACTED credential metadata]/'
if [[ "${backup_type}" == hot ]]; then
    work_dir="$(mktemp -d)"
    trap 'rm -rf -- "${work_dir}"' EXIT
    tar -xzf "${archive}" -C "${work_dir}"
    dump="$(find "${work_dir}" -type f -name '*.backup' -print -quit)"
    "/usr/lib/postgresql/${pg_version}/bin/pg_restore" --list "${dump}" >/dev/null
    printf 'pg_restore_list_rc=%s\n' "$?"
fi
pg_lsclusters
printf 'finished=%s\n' "$(date --iso-8601=seconds)"
exit "${rc}"
