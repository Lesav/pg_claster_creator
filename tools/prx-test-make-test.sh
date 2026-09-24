#!/usr/bin/env bash
# Purpose: non-destructive launcher checks; NEVER approve a real test run.
# Usage: bash tools/prx-test-make-test.sh REPO
# Environment: no required variables; this checks only the local Bash runner.
# Output: PASS messages; all temporary fixtures are removed on exit.
set -Eeuo pipefail
repo="$(realpath "$1")"
runner="$repo/tools/make-test.sh"
work="$(mktemp -d /tmp/pgcc-launcher.XXXXXXXX)"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/source tree" "$work/bin"
printf 'readonly SCRIPT_VERSION="2.5.7"\n' >"$work/source tree/create-claster.sh"
printf '## Начало тестирования\n' >"$work/source tree/TEST.md"
bash -n "$runner"
sed -n '/^default_test_output() {/,/^}/p' "$runner" >"$work/default-output.sh"
(
    source "$work/default-output.sh"
    unset WSL_DISTRO_NAME
    release=2.5.7
    [[ "$(default_test_output)" == /tmp/pg_claster_creator/TEST-2.5.7 ]]
)
printf 'PASS native Linux results default to /tmp\n'
# The automated stand must not inherit a controlling terminal: timeout creates
# another process group and APT may otherwise stop on terminal ioctls.
grep -Fq 'step stand setsid --wait bash ' "$runner"
setsid --wait bash -c 'if (: </dev/tty) 2>/dev/null; then exit 1; fi' </dev/null
printf 'PASS automated stand has no controlling terminal\n'
bash "$runner" --help >"$work/help"
for answer in '' N n no yes invalid; do
    printf '%s\n' "$answer" | bash "$runner" --local --repo "$work/source tree" >"$work/cancel"
    grep -Fq 'Продолжить? [N/y]:' "$work/cancel"
    grep -q 'Тестирование отменено' "$work/cancel"
done
bash "$runner" --local --repo "$work/source tree" </dev/null >"$work/eof"
grep -q 'Тестирование отменено' "$work/eof"
[[ "$(find "$work/source tree" -mindepth 1 -maxdepth 1 | wc -l)" == 2 ]]
for args in '--unknown' '--wsl' '--wsl test' 'test-distro' '--port 5432' '--local --wsl test'; do
    read -r -a argv <<<"$args"
    rc=0
    bash "$runner" "${argv[@]}" >"$work/error" 2>&1 || rc=$?
    [[ "$rc" == 2 ]]
done
if ((EUID == 0)); then
    # All child helpers are inert stubs; no real PostgreSQL/APT calls occur.
    mkdir "$work/source tree/tools" "$work/source tree/man"
    cp "$repo/tools/prx-compress-test-logs.sh" "$work/source tree/tools/"
    cp "$repo/tools/prx-test-port.sh" "$work/source tree/tools/"
    touch "$work/source tree/LICENSE" "$work/source tree/.new-claster.config"
    export QA_LAUNCHER_EVENTS="$work/events"
    for helper in prx-test-release-fixtures prx-test-menu-sql prx-test-deb-sql prx-test-deb-existing prx-test-full-contracts prx-test-wsl-syslog prx-test-safe-sql; do
        printf '#!/usr/bin/env bash\nprintf "SAFE %%s\\n" "${0##*/}" >>"$QA_LAUNCHER_EVENTS"\n' >"$work/source tree/tools/$helper.sh"
    done
    printf '#!/usr/bin/env bash\necho DESTRUCTIVE-GATE >>"$QA_LAUNCHER_EVENTS"\nexit 91\n' >"$work/source tree/tools/prx-check-server-minor.sh"
    printf '#!/usr/bin/env bash\nmkdir -p "$2"\nprintf "postgresql-16\\tpostgresql\\t16\\t0\\n" >"$2/selection.tsv"\n' >"$work/source tree/tools/prx-prepare-test-server.sh"
    sed "s|/run/lock/pgcc-make-test.lock|$work/launcher.lock|" "$runner" >"$work/runner.sh"
    printf 'Existing project journal: must remain unchanged\n' >"$work/source tree/TEST-2.5.7-journal.md"
    cp "$work/source tree/TEST-2.5.7-journal.md" "$work/original-journal"
    expected_journals=0
    for second in N '' invalid; do
        : >"$work/events"
        printf 'y\n%s\n' "$second" | bash "$work/runner.sh" --local --repo "$work/source tree" --output-dir "$work/evidence" >"$work/safe.log"
        [[ "$(grep -c '^SAFE ' "$work/events")" == 7 ]]
        ! grep -q DESTRUCTIVE "$work/events"
        grep -Fq 'Разрешить разрушающий прогон? [N/y]:' "$work/safe.log"
        ((expected_journals += 1))
        [[ "$(find "$work/evidence" -name TEST-2.5.7-journal.md -type f | wc -l)" == "$expected_journals" ]]
        cmp "$work/original-journal" "$work/source tree/TEST-2.5.7-journal.md"
        grep -q '^Каталог логов: ' "$work/safe.log"
    done
    : >"$work/events"
    rc=0
    printf 'y\ny\n' | bash "$work/runner.sh" --local --repo "$work/source tree" --output-dir "$work/evidence" >"$work/full.log" || rc=$?
    [[ "$rc" == 1 && "$(cat "$work/events")" == DESTRUCTIVE-GATE ]]
    grep -q '^Каталог логов: ' "$work/full.log"
    [[ "$(find "$work/evidence" -name TEST-2.5.7-journal.md -type f | wc -l)" == 4 ]]
    cmp "$work/original-journal" "$work/source tree/TEST-2.5.7-journal.md"
    # Run the real launcher step function with an inert helper that owns stand.log.
    sed -n '/^step() {/,/^}/p' "$runner" >"$work/step.sh"
    (
        source "$work/step.sh"
        base="$work/log-collision"; mkdir -p "$base/launcher"
        journal="$base/journal.md"
        stub_stand() { [[ ! -e "$base/stand.log" ]] || return 91; printf 'helper log\n' >"$base/stand.log"; }
        step stand stub_stand
        [[ -f "$base/stand.log" && -f "$base/launcher/stand.log" ]]
        umask 077
        step permissions bash -c 'test "$(umask)" = 0022'
        [[ "$(umask)" == 0077 ]]
        [[ "$(stat -c %a "$base/launcher/permissions.log")" == 600 ]]
        if step failure false 2>"$base/error"; then exit 1; fi
        grep -q 'ОШИБКА этапа failure' "$base/error"
        step quick true >"$base/quick-console"
        ! grep -q 'прошло' "$base/quick-console"
        timer_rc=0
        step slow bash -c 'sleep 7; exit 7' >"$base/slow-console" 2>"$base/slow-error" || timer_rc=$?
        [[ "$timer_rc" == 7 && -z "$step_timer_pid" ]]
        grep -Eq 'run:    slow +\(прошло 0:06\)' "$base/slow-console"
        grep -Eq 'finish: slow +\[FAIL\] \(выполнялся [0-9]+:[0-9]{2}\.[0-9]{3}\)' "$base/slow-console"
        grep -Eq 'finish: quick +\[PASS\] \(выполнялся [0-9]+:[0-9]{2}\.[0-9]{3}\)' "$base/quick-console"
        [[ "$(awk '/ start: / {print index($0,"quick")}' "$base/quick-console")" == "$(awk '/ finish: / {print index($0,"quick")}' "$base/quick-console")" ]]
        ! grep -q 'прошло' "$base/launcher/slow.log"
        printf 'PASS elapsed timer after five seconds; helper status/logs preserved\n'
    )
    printf 'PASS launcher/helper log separation and visible step errors\n'
    printf 'PASS distinct run journals in evidence directories; existing project journal preserved\n'
    printf 'PASS two confirmations: second No/empty/invalid selects only safe stubs; Yes reaches only the stub baseline gate\n'
fi
printf 'PASS local launcher help, obsolete WSL argument rejection, default-No/EOF/cancellation and no writes before consent\n'
