#!/usr/bin/env bash
# Purpose: exercise wrapper failure/lock/cron guards without a database or existing cron task.
# Usage: bash tools/prx-test-backup-guards.sh REPO DISTRO LOG_ROOT TOKEN
# Args: LOG_ROOT -- evidence root; TOKEN -- unique alphanumeric QA suffix.
# Output: logs/results; removes its exact cron/lock files and private fixture.
# Example: bash tools/prx-test-backup-guards.sh /repo Astra /repo/tmp/qa r240
set -Eeuo pipefail
repo="$1"; distro="$2"
logs="$3/$distro/guards"
[[ "$4" =~ ^[a-z0-9_]+$ ]] || exit 2
[[ ! -e "$logs" ]] || exit 2
mkdir "$logs"
work="$(mktemp -d /var/tmp/pgcc-guards.XXXXXX)"
wrapper=/usr/local/bin/create-claster-backup.sh
cluster="qa${4}_guards"; db="$cluster"; v=16
hash="$(printf '%s\0%s\0%s' "$v" "$cluster" "$db" | cksum | awk '{print $1}')"
cron="/etc/cron.d/pg-claster-backup-$v-$cluster-$db-$hash"
lock="/run/lock/pg-claster-backup-$v-$cluster-$db.lock"
[[ ! -e "$cron" && ! -e "$lock" ]] || exit 2
finish() {
    local rc=$?
    trap - EXIT
    rm -f -- "$cron" "$lock"
    rm -rf -- "$work"
    printf 'cleanup rc=%s cron_removed=%s lock_removed=%s\n' "$rc" "$([[ ! -e "$cron" ]] && echo yes)" "$([[ ! -e "$lock" ]] && echo yes)" >>"$logs/summary.log"
    exit "$rc"
}
trap finish EXIT
check() {
    local id="$1" expected="$2" rc; shift 2
    printf 'START %s %s\nCOMMAND ' "$id" "$(date --iso-8601=seconds)" >>"$logs/summary.log"
    printf '%q ' "$@" >>"$logs/summary.log"; printf '\n' >>"$logs/summary.log"
    set +e
    timeout -k 2 30 "$@" >"$logs/$id.log" 2>&1; rc=$?
    set -e
    printf 'END %s rc=%s %s\n' "$id" "$rc" "$(date --iso-8601=seconds)" >>"$logs/summary.log"
    if [[ "$expected" == nonzero && "$rc" != 0 && "$rc" != 124 && "$rc" != 137 ]] || [[ "$rc" == "$expected" ]]; then
        printf '%s\tPASS\trc=%s\n' "$id" "$rc" >>"$logs/results.tsv"
    else
        printf '%s\tFAIL\trc=%s\n' "$id" "$rc" >>"$logs/results.tsv"; return 1
    fi
}
printf sentinel >"$work/16-$db-20000101-000000-dmp.tar.gz"
printf sentinel >"$work/16-$db-20000102-000000-dmp.tar.gz"
check failed-backup nonzero "$wrapper" "$v" "$cluster" "$db" --backup-dir "$work" --files-cnt 1
check no-rotation 0 test "$(find "$work" -name '*.tar.gz' | wc -l)" = 2
exec 8>"$lock"
flock -n 8
check concurrent-lock nonzero "$wrapper" "$v" "$cluster" "$db" --backup-dir "$work" --files-cnt 1
check lock-message 0 grep -F 'уже выполняется' "$logs/concurrent-lock.log"
flock -u 8
exec 8>&-
check invalid-size nonzero "$wrapper" "$v" "$cluster" "$db" --backup-dir "$work" --files-size BAD
check mixed-limits nonzero "$wrapper" "$v" "$cluster" "$db" --backup-dir "$work" --files-cnt 1 --files-size 1MiB
check cron-no-tty nonzero "$wrapper" "$v" "$cluster" "$db" --backup-dir "$work" --files-cnt 2 --cron </dev/null
# A real PTY is required by --cron; all schedules are 02:00, outside this test window.
cron_cmd="$wrapper $v $cluster $db --backup-dir $work --files-cnt 2 --cron"
check cron-count 0 script -q -e -c "$cron_cmd" /dev/null <<<$'4\ny'
check cron-mode 0 test "$(stat -c '%a' "$cron")" = 644
check cron-path 0 grep -F /usr/local/bin/create-claster-backup.sh "$cron"
cp "$cron" "$logs/cron-count.txt"
check cron-repeat 0 script -q -e -c "$cron_cmd" /dev/null <<<$'4\ny'
check cron-idempotent 0 cmp "$cron" "$logs/cron-count.txt"
check cron-size 0 script -q -e -c "$wrapper $v $cluster $db --backup-dir $work --files-size 1MiB --cron" /dev/null <<<$'4\ny'
cp "$cron" "$logs/cron-size.txt"
check cron-prompt-limit 0 script -q -e -c "$wrapper $v $cluster $db --backup-dir $work --cron" /dev/null <<<$'bad\n4\n1\n2\ny'
cp "$cron" "$logs/cron-prompt.txt"
for schedule in 1 2 3 4 5; do
    input="$(printf '%s\ny\n' "$schedule")"
    [[ "$schedule" != 5 ]] || input=$'5\n17 3 2 1 *\ny'
    check "cron-schedule-$schedule" 0 script -q -e -c "$cron_cmd" /dev/null <<<"$input"
    cp "$cron" "$logs/cron-schedule-$schedule.txt"
done
