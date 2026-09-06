#!/usr/bin/env bash

# ==============================================================================
# Script: create-claster-backup.sh
# Author: Andrei Lesnykh (AO NIKIET) <lesnyx@ya.ru>
#
# Purpose:
#   Run a non-interactive hot backup of one PostgreSQL database through
#   create-claster.sh. The required positional arguments are PostgreSQL major
#   version, cluster name, and database name. The backup directory can be set
#   explicitly or inherited from .new-claster.config.
#
# Backup and retention behavior:
#   A normal invocation creates one custom-format hot backup. After a successful
#   backup only, optional retention removes older archives selected by the strict
#   VERSION/DATABASE/timestamp hot-backup filename mask. Archive contents and
#   backup-info.env are not read during rotation. --files-cnt and --files-size
#   are mutually exclusive.
#
# Cron behavior:
#   --cron installs or replaces one /etc/cron.d task for the selected database.
#   Schedule selection is deliberately interactive: hourly, daily, weekly,
#   monthly, or a custom five-field numeric cron expression. If no retention
#   option was supplied, the dialog also requires either a maximum file count or
#   a maximum total size. The generated task calls this script without --cron;
#   therefore cleanup happens only after create-claster.sh reports success.
#
# Command-line options:
#   -h, --help              Print detailed usage information and examples.
#   -v, --version           Print the script version.
#       --backup-dir DIR    Store backups in DIR; otherwise use the configured
#                           backup_dir or /.postgres/backup.
#       --files-cnt COUNT   Keep at most COUNT matching successful backups.
#       --files-size SIZE   Limit matching backups to SIZE. Accepted suffixes:
#                           B, K/KB/KiB, M/MB/MiB, G/GB/GiB, T/TB/TiB.
#       --cron              Interactively create or replace a cron task.
#
# Positional arguments:
#   VERSION                 PostgreSQL major version, for example 16.
#   CLUSTER                 Existing cluster name, for example subsys.
#   DATABASE                Existing database name, for example asvd.
#
# Exit and safety rules:
#   Help and version do not require privileges. Backup, cleanup, and cron setup
#   run as root (sudo is used when available). Concurrent runs of the same task
#   are rejected with a per-database lock. At least the newest matching backup is
#   retained even when that file alone exceeds --files-size.
# ==============================================================================

set -Eeuo pipefail

readonly SCRIPT_NAME="create-claster-backup.sh"
readonly SCRIPT_VERSION="2.0.2"
readonly SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd -P)"
readonly CONFIG_FILE="${SCRIPT_DIR}/.new-claster.config"
readonly DEFAULT_BACKUP_DIR="/.postgres/backup"

BACKUP_DIR=""
FILES_COUNT=""
FILES_SIZE=""
FILES_SIZE_BYTES=""
CREATE_CRON=0
CRON_TEMP_FILE=""
declare -a POSITIONAL_ARGS=()
declare -a TASK_BACKUPS=()

usage() {
    cat <<EOF
Использование:
  ${SCRIPT_NAME} [КЛЮЧИ] <версия> <кластер> <имя БД>

Создаёт горячий бэкап БД через неинтерактивный режим create-claster.sh.

Ключи:
  -h, --help              Показать эту справку
  -v, --version           Показать версию сценария
      --backup-dir ПУТЬ   Каталог бэкапов; по умолчанию значение backup_dir
                          из .new-claster.config либо ${DEFAULT_BACKUP_DIR}
      --files-cnt ЧИСЛО   Хранить не более указанного количества бэкапов задачи
      --files-size РАЗМЕР Ограничить общий размер бэкапов задачи
      --cron              Интерактивно создать/заменить задачу в /etc/cron.d

Размер задаётся целым положительным числом. Поддержаны суффиксы:
  B, K, KB, KiB, M, MB, MiB, G, GB, GiB, T, TB, TiB.
Без суффикса значение трактуется как байты.

--files-cnt и --files-size взаимоисключающие. Очистка выполняется только после
успешного бэкапа и только для архивов по строгой маске
{версия}-{БД}-YYYYMMDD-hhmmss-dmp.tar.gz. Содержимое архивов не читается.
Как минимум один, самый новый, бэкап всегда сохраняется.

С ключом --cron периодичность всегда запрашивается интерактивно. Если лимит не
передан ключом, сценарий также предложит выбрать ограничение количества или
общего размера файлов.

Примеры:
  sudo ${SCRIPT_NAME} 16 subsys asvd
  sudo ${SCRIPT_NAME} 16 subsys asvd --backup-dir /BACKUP/postgresql
  sudo ${SCRIPT_NAME} 16 subsys asvd --files-cnt 14
  sudo ${SCRIPT_NAME} 16 subsys asvd --files-size 20GiB
  sudo ${SCRIPT_NAME} 16 subsys asvd --cron --files-cnt 30
  sudo ${SCRIPT_NAME} 16 subsys asvd --cron
EOF
}

version() {
    printf '%s, версия %s\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
}

die() {
    printf 'ОШИБКА: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'ПРЕДУПРЕЖДЕНИЕ: %s\n' "$*" >&2
}

cleanup() {
    if [[ -n "${CRON_TEMP_FILE}" && "${CRON_TEMP_FILE}" == /etc/cron.d/.pg-claster-backup.* ]]; then
        rm -f -- "${CRON_TEMP_FILE}"
    fi
}

trap cleanup EXIT

option_value_required() {
    (($# >= 2)) && [[ -n "$2" ]] || die "для ключа $1 требуется значение"
}

parse_args() {
    while (($#)); do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -v|--version) version; exit 0 ;;
            --backup-dir) option_value_required "$@"; BACKUP_DIR="$2"; shift 2 ;;
            --backup-dir=*) BACKUP_DIR="${1#*=}"; shift ;;
            --files-cnt) option_value_required "$@"; FILES_COUNT="$2"; shift 2 ;;
            --files-cnt=*) FILES_COUNT="${1#*=}"; shift ;;
            --files-size) option_value_required "$@"; FILES_SIZE="$2"; shift 2 ;;
            --files-size=*) FILES_SIZE="${1#*=}"; shift ;;
            --cron) CREATE_CRON=1; shift ;;
            --) shift; POSITIONAL_ARGS+=("$@"); break ;;
            -*) die "неизвестный ключ: $1" ;;
            *) POSITIONAL_ARGS+=("$1"); shift ;;
        esac
    done
}

validate_pg_version() {
    [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 9 && 10#$1 <= 99))
}

validate_cluster_name() {
    [[ "$1" =~ ^[a-z_][a-z0-9_]*$ ]]
}

validate_database_name() {
    [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]]
}

size_to_bytes() {
    local value="$1" number suffix multiplier
    if [[ "${value}" =~ ^([0-9]+)([A-Za-z]*)$ ]]; then
        number="${BASH_REMATCH[1]}"
        suffix="${BASH_REMATCH[2],,}"
    else
        return 1
    fi
    ((10#${number} > 0)) || return 1
    case "${suffix}" in
        ''|b) multiplier=1 ;;
        k|kb|kib) multiplier=1024 ;;
        m|mb|mib) multiplier=$((1024 ** 2)) ;;
        g|gb|gib) multiplier=$((1024 ** 3)) ;;
        t|tb|tib) multiplier=$((1024 ** 4)) ;;
        *) return 1 ;;
    esac
    ((10#${number} <= 9223372036854775807 / multiplier)) || return 1
    printf '%s' "$((10#${number} * multiplier))"
}

configured_backup_dir() {
    if [[ -r "${CONFIG_FILE}" ]]; then
        (
            set +u
            # shellcheck source=/dev/null
            source "${CONFIG_FILE}"
            printf '%s' "${backup_dir:-${DEFAULT_BACKUP_DIR}}"
        )
    else
        printf '%s' "${DEFAULT_BACKUP_DIR}"
    fi
}

resolve_creator() {
    if [[ -x "${SCRIPT_DIR}/create-claster.sh" ]]; then
        printf '%s' "${SCRIPT_DIR}/create-claster.sh"
    elif [[ -x /usr/local/bin/create-claster.sh ]]; then
        printf '%s' /usr/local/bin/create-claster.sh
    else
        return 1
    fi
}

require_root() {
    if ((EUID == 0)); then
        return 0
    fi
    command -v sudo >/dev/null 2>&1 || die "требуются права root; sudo не найден"
    exec sudo -- "$0" "$@"
}

load_task_backups() {
    local backup_dir="$1" version="$2" database="$3" filename
    TASK_BACKUPS=()
    while IFS= read -r filename; do
        [[ -n "${filename}" ]] || continue
        TASK_BACKUPS+=("${backup_dir}/${filename}")
    done < <(find -H "${backup_dir}" -maxdepth 1 -type f \
        -name "${version}-${database}-????????-??????-dmp.tar.gz" -printf '%f\n' 2>/dev/null | sort -r)
}

remove_backup_file() {
    local archive="$1" backup_dir_real="$2" archive_real
    [[ -f "${archive}" && ! -L "${archive}" ]] || die "небезопасная цель очистки: ${archive}"
    archive_real="$(readlink -f -- "${archive}")" || die "не удалось определить путь ${archive}"
    [[ "${archive_real}" == "${backup_dir_real}/"* && "${archive_real}" != "${backup_dir_real}" ]] || die \
        "файл очистки находится вне каталога бэкапов: ${archive_real}"
    printf 'Удаление старого бэкапа задачи: %s\n' "${archive_real}"
    rm -f -- "${archive_real}"
}

apply_retention() {
    local backup_dir="$1" version="$2" database="$3"
    local backup_dir_real archive total=0 size i
    [[ -n "${FILES_COUNT}" || -n "${FILES_SIZE_BYTES}" ]] || return 0
    backup_dir_real="$(readlink -f -- "${backup_dir}")" || die \
        "не удалось определить каталог бэкапов ${backup_dir}"
    load_task_backups "${backup_dir_real}" "${version}" "${database}"
    if [[ -n "${FILES_COUNT}" ]]; then
        for ((i = FILES_COUNT; i < ${#TASK_BACKUPS[@]}; i++)); do
            remove_backup_file "${TASK_BACKUPS[i]}" "${backup_dir_real}"
        done
        printf 'Хранение по количеству: %s из %s файлов задачи.\n' \
            "$(( ${#TASK_BACKUPS[@]} < FILES_COUNT ? ${#TASK_BACKUPS[@]} : FILES_COUNT ))" "${FILES_COUNT}"
        return 0
    fi
    for archive in "${TASK_BACKUPS[@]}"; do
        size="$(stat -c '%s' -- "${archive}")" || die "не удалось определить размер ${archive}"
        total=$((total + size))
    done
    for ((i = ${#TASK_BACKUPS[@]} - 1; i >= 1 && total > FILES_SIZE_BYTES; i--)); do
        archive="${TASK_BACKUPS[i]}"
        size="$(stat -c '%s' -- "${archive}")" || die "не удалось определить размер ${archive}"
        remove_backup_file "${archive}" "${backup_dir_real}"
        total=$((total - size))
    done
    if ((total > FILES_SIZE_BYTES)); then
        warn "самый новый бэкап превышает лимит ${FILES_SIZE}; он сохранён как единственная актуальная копия"
    fi
    printf 'Хранение по размеру: %s байт при лимите %s байт.\n' "${total}" "${FILES_SIZE_BYTES}"
}

prompt_schedule() {
    local choice custom
    while true; do
        printf '%s\n' \
            'Периодичность запуска:' \
            '  1 - Каждый час' \
            '  2 - Ежедневно в 02:00' \
            '  3 - Еженедельно в воскресенье в 02:00' \
            '  4 - Ежемесячно первого числа в 02:00' \
            '  5 - Своя cron-периодичность (пять полей)'
        read -r -p 'Выберите периодичность: ' choice || return 1
        case "${choice}" in
            1) CRON_SCHEDULE='0 * * * *'; return 0 ;;
            2) CRON_SCHEDULE='0 2 * * *'; return 0 ;;
            3) CRON_SCHEDULE='0 2 * * 0'; return 0 ;;
            4) CRON_SCHEDULE='0 2 1 * *'; return 0 ;;
            5)
                read -r -p 'Введите пять полей cron: ' custom || return 1
                if [[ "${custom}" =~ ^[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+$ ]]; then
                    CRON_SCHEDULE="${custom}"
                    return 0
                fi
                warn "требуется пять полей с цифрами и символами *, /, - или ,"
                ;;
            *) warn "неверный номер" ;;
        esac
    done
}

prompt_retention() {
    local choice value
    [[ -z "${FILES_COUNT}" && -z "${FILES_SIZE}" ]] || return 0
    while true; do
        printf '%s\n' \
            'Автоматическая очистка после успешного бэкапа:' \
            '  1 - Ограничить количество файлов этой задачи' \
            '  2 - Ограничить общий размер файлов этой задачи'
        read -r -p 'Выберите ограничение: ' choice || return 1
        case "${choice}" in
            1)
                read -r -p 'Максимальное количество файлов: ' value || return 1
                if [[ "${value}" =~ ^[1-9][0-9]*$ ]]; then
                    FILES_COUNT="${value}"
                    return 0
                fi
                warn "количество должно быть положительным целым числом"
                ;;
            2)
                read -r -p 'Максимальный общий размер (например 20GiB): ' value || return 1
                if FILES_SIZE_BYTES="$(size_to_bytes "${value}")"; then
                    FILES_SIZE="${value}"
                    return 0
                fi
                warn "укажите положительное целое число с поддерживаемым суффиксом"
                ;;
            *) warn "неверный номер" ;;
        esac
    done
}

shell_quote() {
    printf '%q' "$1"
}

install_cron_task() {
    local version="$1" cluster="$2" database="$3" backup_dir="$4" runner job_id
    local cron_file log_file command answer escaped_command safe_database job_hash
    [[ -t 0 ]] || die "--cron требует интерактивного терминала для выбора периодичности"
    prompt_schedule || die "настройка cron отменена"
    prompt_retention || die "настройка cron отменена"
    safe_database="${database//./_}"
    job_hash="$(printf '%s\0%s\0%s' "${version}" "${cluster}" "${database}" | cksum | awk '{print $1}')"
    job_id="${version}-${cluster}-${safe_database}-${job_hash}"
    cron_file="/etc/cron.d/pg-claster-backup-${job_id}"
    log_file="/var/log/pg-claster-backup-${job_id}.log"
    if [[ -x /usr/local/bin/create-claster-backup.sh ]]; then
        runner=/usr/local/bin/create-claster-backup.sh
    else
        runner="${SCRIPT_DIR}/${SCRIPT_NAME}"
    fi
    command="$(shell_quote "${runner}") $(shell_quote "${version}") $(shell_quote "${cluster}") $(shell_quote "${database}") --backup-dir $(shell_quote "${backup_dir}")"
    if [[ -n "${FILES_COUNT}" ]]; then
        command+=" --files-cnt $(shell_quote "${FILES_COUNT}")"
    else
        command+=" --files-size $(shell_quote "${FILES_SIZE}")"
    fi
    escaped_command="${command//%/\\%}"
    printf '\nЗадача: %s\nПериодичность: %s\nЛог: %s\n' "${job_id}" "${CRON_SCHEDULE}" "${log_file}"
    read -r -p 'Создать или заменить эту задачу? [Y/n]: ' answer || die "настройка cron отменена"
    case "${answer,,}" in ''|y|yes|д|да) ;; *) die "настройка cron отменена" ;; esac
    [[ -d /etc/cron.d ]] || die "каталог /etc/cron.d отсутствует; установите cron"
    CRON_TEMP_FILE="$(mktemp /etc/cron.d/.pg-claster-backup.XXXXXX)"
    {
        printf 'SHELL=/bin/bash\n'
        printf 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n'
        printf '%s root %s >> %s 2>&1\n' "${CRON_SCHEDULE}" "${escaped_command}" "$(shell_quote "${log_file}")"
    } >"${CRON_TEMP_FILE}"
    chmod 0644 "${CRON_TEMP_FILE}"
    mv -f -- "${CRON_TEMP_FILE}" "${cron_file}"
    CRON_TEMP_FILE=""
    printf 'Задача cron создана: %s\n' "${cron_file}"
    command -v cron >/dev/null 2>&1 || warn "команда cron не найдена; установите и запустите планировщик"
}

acquire_task_lock() {
    local version="$1" cluster="$2" database="$3" lock_file
    command -v flock >/dev/null 2>&1 || die "не найдена команда flock"
    mkdir -p /run/lock
    lock_file="/run/lock/pg-claster-backup-${version}-${cluster}-${database}.lock"
    exec 9>"${lock_file}"
    flock -n 9 || die "задача бэкапа ${version}/${cluster}/${database} уже выполняется"
}

main() {
    local version_value cluster database creator
    parse_args "$@"
    ((${#POSITIONAL_ARGS[@]} == 3)) || { usage >&2; die "требуются аргументы <версия> <кластер> <имя БД>"; }
    version_value="${POSITIONAL_ARGS[0]}"
    cluster="${POSITIONAL_ARGS[1]}"
    database="${POSITIONAL_ARGS[2]}"
    validate_pg_version "${version_value}" || die "некорректная версия PostgreSQL: ${version_value}"
    validate_cluster_name "${cluster}" || die "некорректное имя кластера: ${cluster}"
    validate_database_name "${database}" || die "некорректное имя БД: ${database}"
    [[ -z "${FILES_COUNT}" || -z "${FILES_SIZE}" ]] || die \
        "--files-cnt и --files-size нельзя использовать одновременно"
    if [[ -n "${FILES_COUNT}" ]]; then
        [[ "${FILES_COUNT}" =~ ^[1-9][0-9]*$ ]] || die "--files-cnt должен быть положительным целым числом"
        ((${#FILES_COUNT} <= 9)) || die "--files-cnt слишком велик"
        FILES_COUNT="$((10#${FILES_COUNT}))"
    fi
    if [[ -n "${FILES_SIZE}" ]]; then
        FILES_SIZE_BYTES="$(size_to_bytes "${FILES_SIZE}")" || die \
            "некорректный --files-size: ${FILES_SIZE}"
    fi
    [[ -n "${BACKUP_DIR}" ]] || BACKUP_DIR="$(configured_backup_dir)"
    [[ "${BACKUP_DIR}" == /* && "${BACKUP_DIR}" != / ]] || die \
        "каталог бэкапов должен быть абсолютным и не корневым: ${BACKUP_DIR}"
    require_root "$@"
    if ((CREATE_CRON)); then
        install_cron_task "${version_value}" "${cluster}" "${database}" "${BACKUP_DIR}"
        return 0
    fi
    acquire_task_lock "${version_value}" "${cluster}" "${database}"
    creator="$(resolve_creator)" || die "не найден create-claster.sh"
    "${creator}" --action backup "${version_value}" "${cluster}" \
        --backup-type hot --database "${database}" --backup-dir "${BACKUP_DIR}"
    apply_retention "${BACKUP_DIR}" "${version_value}" "${database}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
