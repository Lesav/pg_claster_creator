#!/usr/bin/env bash
# Purpose: orchestrate the TEST.md preparation/test/cleanup workflow
# on ONE disposable Linux host or WSL distribution, using the existing helpers.
# Usage: bash tools/make-test.sh --local [OPTIONS]
# Windows entry point: tools/make-test.cmd --wsl DISTRO.
# Command-line options: --repo DIR (target-visible source tree), --package NAME
# (optional assertion of the installed/highest-priority server), --port 60100..60800 in steps
# of 100, --output-dir DIR (per-release evidence root), -h/--help.
# Environment interface: no public ENV overrides; inherited PGCC_* settings are
# cleared. Internal PGCC_TEST_REPO/RELEASE/RUN/OUTPUT/HOST are passed to helpers.
# PGCC_TEST_KEEP_SERVER is derived internally before deleting original clusters.
# Safety: two default-No confirmations; rejecting the second selects safe tests.
# Each run writes its journal inside its evidence directory, not the repo root.
# Existing journals are never overwritten. Automatic coverage is partial: the
# journal lists plan IDs as untested until their required variants are audited.
# Dependencies: Bash >=4.4, Debian-family Linux, root, systemd/APT/dpkg and the
# helper dependencies. This script runs locally; Windows dispatch is in .cmd.
# Exit codes: 0 completed automated chain or cancellation; 1 test/cleanup error;
# 2 invalid arguments, prerequisites or unsafe/ambiguous baseline.
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Использование:
  bash tools/make-test.sh --local [параметры]

  --repo КАТАЛОГ        Исходники на целевой машине (по умолчанию каталог проекта)
  --package ПАКЕТ       Проверить выбранный сервер; установленный имеет приоритет
  --port ПОРТ           Явный базовый порт: 60100..60800, шаг 100; по умолчанию случайный свободный диапазон
  --output-dir КАТАЛОГ  Корень результатов (вне WSL по умолчанию /tmp/pg_claster_creator/TEST-X.Y.Z)
  -h, --help            Справка без запуска и изменений

Два запроса [N/y]: проведение теста, затем разрешение разрушающего прогона.
Первый отказ отменяет запуск. Второй отказ сохраняет исходные кластеры/пакеты:
выполняются изолированные хелперы и SQL на временном test_<1–9> со свободным портом.
Только второе y/Y разрешает удаление ВСЕХ кластеров без сохранения данных
и переустановку PostgreSQL/Tantor и common-пакетов согласно TEST.md.
Разрушающий режим поддерживает один серверный комплект; иначе запуск запрещён.
Если исходный сервер имеет кластер, сервер/common не переустанавливаются.
Если сервера нет, устанавливается доступный с наивысшим приоритетом сценария.
Установленный claster-creator и его конфиг остаются предусловием полного прогона.
В безопасном SQL-тесте свободный порт выбирается автоматически.
Непроверенные варианты отмечаются «Не тестировалось», а не FAIL или PASS.
CLI/ENV тестируемых сценариев проверяются хелперами; PGCC_* вызывающей среды
не используются для настройки этого запуска. Полный ручной план не автоматизирован.
EOF
}
die() { printf 'ОШИБКА: %s\n' "$*" >&2; exit 2; }
default_test_output() {
    if [[ -z "${WSL_DISTRO_NAME:-}" ]]; then
        printf '/tmp/pg_claster_creator/TEST-%s\n' "$release"
    elif [[ -d /mnt/d/Ai ]]; then
        printf '/mnt/d/Ai/pg_claster_creator.backup/TEST-%s\n' "$release"
    else
        printf '%s.backup/TEST-%s\n' "$repo" "$release"
    fi
}
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
package="" port="" output="" selected=0
while (($#)); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --local) ((selected == 0)) || die 'ключ --local уже задан'; selected=1; shift ;;
        --repo|--package|--port|--output-dir)
            (($# >= 2)) && [[ -n "$2" && "$2" != -* ]] || die "$1 требует значение"
            case "$1" in --repo) repo="$2" ;; --package) package="$2" ;; --port) port="$2" ;; --output-dir) output="$2" ;; esac
            shift 2 ;;
        -*) die "неизвестный ключ $1" ;;
        *) die "лишний аргумент $1; для WSL используйте tools/make-test.cmd --wsl ИМЯ" ;;
    esac
done
[[ -z "$port" || "$port" =~ ^60[1-8]00$ ]] || die 'порт должен быть 60100..60800 с шагом 100'
[[ -z "$package" || "$package" =~ ^[a-z0-9][a-z0-9.+-]*$ ]] || die 'некорректный пакет'
[[ "$(uname -s)" == Linux ]] || die '--local требует Linux'
repo="$(realpath -e -- "$repo")" || die 'каталог исходников недоступен'
[[ -f "$repo/TEST.md" && -f "$repo/create-claster.sh" ]] || die 'не найден проект/TEST.md'
release="$(sed -n 's/^readonly SCRIPT_VERSION="\([0-9][0-9.]*\)"/\1/p' "$repo/create-claster.sh")"
[[ "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'не определена версия'
host="${WSL_DISTRO_NAME:-local-$(hostname)}"
[[ "$host" =~ ^[a-zA-Z0-9_.-]+$ ]] || die 'имя стенда нельзя использовать как имя каталога'
printf 'ВНИМАНИЕ: будет проведён тест согласно TEST.md «Начало тестирования».\n'
printf 'Стенд: %s; исходники: %s; версия: %s.\n' "$host" "$repo" "$release"
printf 'Пропуски не считаются ошибками. Разрушающие действия требуют отдельного разрешения.\n'
printf 'Продолжить? [N/y]: '
read -r answer || { printf '\nТестирование отменено.\n'; exit 0; }
[[ "$answer" =~ ^[Yy]$ ]] || { printf 'Тестирование отменено.\n'; exit 0; }
printf '\nВНИМАНИЕ: разрушающий прогон удаляет ВСЕ исходные кластеры и данные БЕЗ сохранения. Сервер с исходными кластерами не переустанавливается; без кластеров возможна переустановка PostgreSQL/Tantor и common-пакетов. При отсутствии сервера он будет установлен.\n'
printf 'Разрешить разрушающий прогон? [N/y]: '
destructive=no
if read -r answer && [[ "$answer" =~ ^[Yy]$ ]]; then destructive=yes; fi
mode_label='безопасный'; [[ "$destructive" != yes ]] || mode_label='разрушающий'
printf '\nРежим: %s (%s)\n' "$destructive" "$mode_label"
printf '%s\n' '-----------------------------------------------'
stage_name_width=14
[[ "$destructive" == yes ]] || stage_name_width=30
((EUID == 0)) || die 'локальный запуск требует sudo bash tools/make-test.sh --local'
for dependency in flock setsid gzip shuf apt-get apt-cache dpkg dpkg-query systemctl timeout python3 tar sha256sum ss; do
    command -v "$dependency" >/dev/null || die "нет команды $dependency"
done
if [[ "$destructive" == yes ]]; then
    systemctl show --property=Version --value >/dev/null || die 'systemd недоступен'
fi
# Prevent simultaneous chains on the same host, including other source checkouts.
exec 9>/run/lock/pgcc-make-test.lock
flock -n 9 || die 'на стенде уже работает make-test.sh'
for name in ${!PGCC_@}; do unset "$name"; done
unset CLASTER_FORCE_INSTALL CLASTER_FORCE_DB_INSTALL
# Keep launcher/helper diagnostics independent of malformed inherited LANG.
# Product scripts still load their explicit configuration when testing locales.
export LANG=C LC_ALL=C
if [[ -z "$output" ]]; then
    output="$(default_test_output)"
fi
output="$(realpath -m -- "$output")"
[[ "$output" != "$repo" && "$output" != "$repo/"* && "$output" != / ]] || die 'логи должны находиться вне дерева исходников'
run="run-$(date +%Y%m%d-%H%M%S)-$$"
base="$output/$host/$run"
journal="$base/TEST-$release-journal.md"
[[ ! -e "$base" ]] || die 'каталог запуска уже существует'
umask 077
mkdir -p -- "$base"
# Report the saved directory even if journal/launcher initialization fails.
trap 'rc=$?; printf "Каталог логов: %s\n" "$base"; exit "$rc"' EXIT
mkdir -- "$base/launcher"
started="$(date --iso-8601=seconds)"; epoch="$(date +%s)"
(set -o noclobber; printf '# Тестирование %s\n\nСтенд: `%s`; начало: %s.\n\nЛоги: `%s`.\n' "$release" "$host" "$started" "$base" >"$journal") || die 'журнал занят'
work="" mutated=0 stand_started=0
finish() {
    rc=$?; trap - EXIT INT TERM; set +e
    if [[ -n "${step_timer_pid:-}" ]]; then
        kill "$step_timer_pid" 2>/dev/null
        wait "$step_timer_pid" 2>/dev/null
        step_timer_pid=""
        [[ ! -t 1 ]] || printf '\r\033[K'
    fi
    [[ ! -f "$base/server-selection/provisioning-started" ]] || mutated=1
    case "$rc" in 0|2|130|143) ;; *) rc=1 ;; esac
    if [[ -n "${port_lease:-}" ]]; then
        if [[ "$rc" == 130 || "$rc" == 143 ]]; then
            printf '\nРезерв портов сохранён до проверки остановки потомков: `%s`.\n' "$port_lease" >>"$journal"
        elif ! release_test_port "$base"; then
            printf '\nFAIL: не удалось освободить резерв портов `%s`.\n' "$port_lease" >>"$journal"
            rc=1
        fi
    fi
    if ((mutated && !stand_started)); then
        printf '\nFAIL: цепочка прервана до штатной очистки; требуется проверка стенда.\n' >>"$journal"
        rc=1
    fi
    if [[ -n "$work" && "$work" == /var/tmp/pgcc-make-test.* && ! -L "$work" && "$(realpath -- "$work")" == "$work" ]]; then
        # Keep recovery files on failure; remove only this mktemp-owned copy.
        if ((rc == 0)); then rm -rf -- "$work"; else printf '\nРабочая копия для восстановления: `%s`.\n' "$work" >>"$journal"; fi
    fi
    # Compress only after helpers and the final audit have consumed plain logs.
    if ! bash "$repo/tools/prx-compress-test-logs.sh" "$base"; then
        printf '\nFAIL: не все большие логи удалось сжать; исходники сохранены.\n' >>"$journal"
        rc=1
    fi
    printf '\nЛоги .log больше 100 КиБ хранятся как .log.gz; к указанному пути лога при необходимости добавьте .gz.\n' >>"$journal"
    printf '\nОкончание: %s; длительность: %s с; код: %s.\n' "$(date --iso-8601=seconds)" "$(( $(date +%s)-epoch ))" "$rc" >>"$journal"
    printf '\n## Покрытие полного плана\n\nУспех хелпера не подтверждает все варианты ID. Требуется сверка доказательств.\n\n' >>"$journal"
    sed -n 's/^| \(PT-[A-Z0-9-]*\) —.*/\1/p' "$repo/TEST.md" | sort -u | while read -r id; do
        printf -- '- %s: Не тестировалось полностью — автоматические логи требуют проверки вариантов, включая живые singl/struct-dirs.\n' "$id"
    done >>"$journal"
    printf '%s\n' '-----------------------------------------------'
    printf 'Журнал: %s\nКаталог логов: %s\n' "$journal" "$base"
    exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
step() {
    local id="$1" rc=0 timer_start=$SECONDS timer_owner=$BASHPID; shift
    local started_ms ended_ms duration_ms status width="${stage_name_width:-14}"
    printf '%s start:  %-*s\n' "$(date --iso-8601=seconds)" "$width" "$id"
    # Keep the helper in the foreground (stdin/exit status unchanged). Only the
    # elapsed-time display runs in the background and never writes helper logs.
    (
        tick_pid=""
        trap '[[ -z "$tick_pid" ]] || { kill "$tick_pid" 2>/dev/null || true; wait "$tick_pid" 2>/dev/null || true; }; exit 0' TERM INT
        while :; do
            sleep 1 & tick_pid=$!
            wait "$tick_pid" || exit 0
            tick_pid=""
            kill -0 "$timer_owner" 2>/dev/null || exit 0
            elapsed=$((SECONDS-timer_start))
            ((elapsed > 5)) || continue
            if [[ -t 1 ]]; then
                printf '\r%s run:    %-*s  (прошло %d:%02d)\033[K' "$(date --iso-8601=seconds)" "$width" "$id" "$((elapsed/60))" "$((elapsed%60))"
            else
                printf '%s run:    %-*s  (прошло %d:%02d)\n' "$(date --iso-8601=seconds)" "$width" "$id" "$((elapsed/60))" "$((elapsed%60))"
            fi
        done
    ) &
    step_timer_pid=$!
    # Evidence stays private; helpers need normal traversal permissions for
    # PostgreSQL-owned data directories created below root-owned parents.
    started_ms="$(date +%s%3N)"
    (umask 022; "$@") >"$base/launcher/$id.log" 2>&1 || rc=$?
    ended_ms="$(date +%s%3N)"
    duration_ms=$((ended_ms-started_ms))
    ((duration_ms >= 0)) || duration_ms=0
    kill "$step_timer_pid" 2>/dev/null || true
    wait "$step_timer_pid" 2>/dev/null || true
    step_timer_pid=""
    [[ ! -t 1 ]] || printf '\r\033[K'
    printf -- '- %s: rc=%s; лог `%s/launcher/%s.log`.\n' "$id" "$rc" "$base" "$id" >>"$journal"
    status=PASS; ((rc == 0)) || status=FAIL
    printf '%s finish: %-*s  [%s] (выполнялся %d:%02d.%03d)\n' \
        "$(date --iso-8601=seconds)" "$width" "$id" "$status" \
        "$((duration_ms/60000))" "$((duration_ms/1000%60))" "$((duration_ms%1000))"
    if ((rc != 0)); then
        printf 'ОШИБКА этапа %s. Лог запуска: %s/launcher/%s.log; внутренние логи: %s\n' "$id" "$base" "$id" "$base" >&2
    fi
    return "$rc"
}
if [[ "$destructive" == no ]]; then
    printf '\nРазрушающие проверки удаления исходных кластеров, переустановки пакетов и реальной установки DEB: Не тестировалось — второе разрешение не дано.\n' >>"$journal"
    work="$(mktemp -d /var/tmp/pgcc-make-test.XXXXXXXX)"
    chmod 0755 "$work"
    cp -a "$repo/tools" "$repo/man" "$repo/LICENSE" "$repo/.new-claster.config" "$repo/"create-claster*.sh "$work/"
    find "$repo" -maxdepth 1 -type f -name '*.md' -exec cp -t "$work" -- {} +
    pg_lsclusters --no-header >"$base/safe-registry-before"
    dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\t${Version}\n' >"$base/safe-packages-before"
    result=0
    step fixtures bash "$work/tools/prx-test-release-fixtures.sh" "$work" "$host" "$release" "$base" || result=1
    for helper in prx-test-menu-sql prx-test-deb-sql prx-test-deb-existing prx-test-full-contracts prx-test-wsl-syslog; do
        step "$helper" bash "$work/tools/$helper.sh" "$work" "$base/$helper" || result=1
    done
    step safe-live-sql bash "$work/tools/prx-test-safe-sql.sh" "$work" "$base/safe-live-sql" "$package" "$work/tools/sql-tests" || result=1
    if [[ -f "$base/safe-live-sql/check.log" ]]; then
        grep '^SKIP:' "$base/safe-live-sql/check.log" >>"$journal" || true
    fi
    pg_lsclusters --no-header >"$base/safe-registry-after" || result=1
    dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\t${Version}\n' >"$base/safe-packages-after" || result=1
    cmp "$base/safe-registry-before" "$base/safe-registry-after" || result=1
    cmp "$base/safe-packages-before" "$base/safe-packages-after" || result=1
    exit "$result"
fi
[[ -f /usr/local/share/pg_claster_creator/.new-claster.config ]] || die 'не найден исходный установленный конфиг'
[[ "$(dpkg-query -W -f='${Status}' claster-creator)" == 'install ok installed' ]] || die 'исходный claster-creator не установлен'
source "$repo/tools/prx-test-port.sh"
reserve_test_port "$output/.port-reservations" "$base" "$port" || die 'не удалось зарезервировать свободный диапазон портов'
printf 'Тестовый диапазон PostgreSQL: %s–%s\n' "$port" "$((port+99))" | tee -a "$journal"
step select-server setsid --wait bash "$repo/tools/prx-prepare-test-server.sh" "$repo" "$base/server-selection" "$package" </dev/null
IFS=$'\t' read -r package family major keep_server <"$base/server-selection/selection.tsv"
export PGCC_TEST_KEEP_SERVER="$keep_server"
if [[ "$keep_server" == 1 ]]; then
    printf 'Сервер %s используется без переустановки. Проверки удаления/установки серверных пакетов: SKIP.\n' "$package" | tee -a "$journal"
fi
step baseline bash "$repo/tools/prx-check-server-minor.sh" "$base/packages"
mapfile -t servers < <(cut -f1 "$base/packages/server-minors.tsv")
((${#servers[@]} == 1)) || die 'требуется один исходный серверный комплект; многосерверная переустановка не автоматизирована'
[[ -z "$package" || "$package" == "${servers[0]}" ]] || die '--package не совпадает с исходным сервером'
package="${servers[0]}"
case "$package" in
    postgresql-*) family=postgresql; major="${package#postgresql-}"; major="${major%-server}" ;;
    postgrespro-ent-*-server) family=postgrespro-ent; major="${package#postgrespro-ent-}"; major="${major%-server}" ;;
    tantor-free-server-*) family=tantor-free; major="${package#tantor-free-server-}"; major="${major%-server}" ;;
    tantor-se-server-*|tantor-be-server-*) family="${package%-server-*}"; major="${package##*-}" ;;
    *) die "неподдерживаемый серверный пакет $package" ;;
esac
[[ "$major" =~ ^[0-9]+$ ]] || die 'не определена major'
installed="$(dpkg-query -W -f='${Version}' "$package")"
candidate="$(LC_ALL=C apt-cache policy "$package" | awk '/Candidate:/ {print $2}')"
[[ "$keep_server" == 1 || "$installed" == "$candidate" ]] || die 'APT выберет другую версию сервера; зафиксируйте исходную версию до удаления'
source "$repo/tools/prx-package-identity.sh"
mapfile -t approved_packages <"$base/packages/removal-candidates.txt"
while read -r op removed rest; do
    [[ "$op" != Remv || "$removed" == claster-creator ]] && continue
    approved_removal "$removed" "${approved_packages[@]}" || die "APT удалит несогласованный пакет $removed"
done <"$base/packages/removal-plan.log"
ss -H -ltn >"$base/listeners.log"
awk -v lo="$port" -v hi="$((port+99))" '{n=split($4,a,":"); if(a[n]>=lo && a[n]<=hi) bad=1} END {exit bad}' "$base/listeners.log" || die 'QA-диапазон портов занят'
for path in "/var/tmp/pgcc-full-$release-$port" "/var/tmp/pgcc-buildsrc-$port" "/var/tmp/pgcc${release//./}-$port"; do
    [[ ! -e "$path" && ! -L "$path" ]] || die "остались файлы предыдущего теста: $path"
done
for suffix in '' -extra -ports -ui -tail -extension -extension-r2; do
    for path in "/var/tmp/pgcc${release//./}-$port$suffix" "/DATA/pgcc${release//./}-$port$suffix"; do
        [[ ! -e "$path" && ! -L "$path" ]] || die "занят тестовый путь: $path"
    done
done
[[ -f /usr/local/share/pg_claster_creator/.new-claster.config ]] || die 'не найден исходный установленный конфиг; bootstrap требует установленный claster-creator'
[[ "$(dpkg-query -W -f='${Status}' claster-creator)" == 'install ok installed' ]] || die 'исходный claster-creator не установлен'
work="$(mktemp -d /var/tmp/pgcc-make-test.XXXXXXXX)"
chmod 0755 "$work"
cp -a "$repo/tools" "$repo/man" "$repo/LICENSE" "$repo/.new-claster.config" "$repo/"create-claster*.sh "$work/"
find "$repo" -maxdepth 1 -type f -name '*.md' -exec cp -t "$work" -- {} +
export PGCC_TEST_REPO="$work" PGCC_TEST_RELEASE="$release" PGCC_TEST_RUN="$run" PGCC_TEST_OUTPUT="$output" PGCC_TEST_HOST="$host"
step build bash "$work/create-claster-deb.sh" --mode 1 --non-interactive --config "$work/.new-claster.config"
# Re-read the registry synchronously; a failed read is never treated as empty.
pg_lsclusters --no-header >"$base/clusters-to-delete.tsv"
mutated=1
while read -r version cluster rest; do
    [[ -n "$version" && -n "$cluster" ]] || continue
    step "delete-$version-$cluster" timeout -k 5 180 bash "$work/create-claster.sh" --action delete "$version" "$cluster" --backup-before-delete no
done <"$base/clusters-to-delete.tsv"
stand_started=1
result=0
# All stand inputs are scripted. A separate session prevents APT terminal ioctls
# under timeout from stopping the process with SIGTTOU in an interactive WSL run.
step stand setsid --wait bash "$work/tools/prx-test-wsl-stand.sh" "$host" "$package" "$major" "$family" "$port" </dev/null || result=1
step sql-struct-dirs bash "$work/tools/prx-test-safe-sql.sh" "$work" "$base/sql-struct-dirs" "$package" "$work/tools/sql-tests" || result=1
step final-audit bash "$work/tools/prx-verify-wsl-test-cleanup.sh" "$host" "$port" || result=1
exit "$result"
