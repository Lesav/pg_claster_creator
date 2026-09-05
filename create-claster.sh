#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="create-claster.sh"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly CONFIG_FILE="${SCRIPT_DIR}/.new-claster.config"
readonly SEPARATOR="-------------------------------------------------------------------------------"

declare SELECTED_PACKAGE=""
declare PG_HOME=""
declare PG_EXT=""
declare DATA_BASE=""
declare CLEANUP_DIR=""
declare SELECTED_CLUSTER_ROW=""
declare NON_INTERACTIVE=0
declare ACTION=""
declare REQUESTED_PACKAGE=""
declare BACKUP_FILE=""
declare BACKUP_TYPE="cold"
declare DATABASE_NAME=""
declare BACKUP_BEFORE_DELETE="yes"
declare CLEAR_WAL="no"
declare OVERWRITE_EXISTING="no"
declare TARGET_NAME_SET=0
declare TARGET_PORT_SET=0
declare TARGET_VERSION_SET=0
declare TARGET_DATABASE_SET=0
declare SHOW_HELP=0
declare SHOW_VERSION=0
declare CONFIG_CLS_PT=""
declare CONFIG_CLS_NM=""
declare CONFIG_CLS_CH=""
declare CONFIG_CLS_US=""
declare CONFIG_CLS_PW=""
declare SELECTED_DATABASE=""
declare RESTORE_ADMIN_ROLE=""
declare DATA_DIRECTORY_SIZE_BYTES=""
declare DATA_DIRECTORY_SIZE_PRETTY=""
declare DATA_DIRECTORY_DU_SH=""
declare -a CLUSTER_DATABASES=()
declare -a CLUSTER_DATABASE_SIZE_BYTES=()
declare -a CLUSTER_DATABASE_SIZES=()

declare ARG_ACTION=""
declare ARG_PACKAGE=""
declare ARG_PG_FAMILY=""
declare ARG_PG_VERSION=""
declare ARG_CLUSTER_NAME=""
declare ARG_CLUSTER_PORT=""
declare ARG_SCHEMA=""
declare ARG_DB_USER=""
declare ARG_DB_PASSWORD=""
declare ARG_BACKUP_DIR=""
declare ARG_BACKUP_FILE=""
declare ARG_BACKUP_TYPE=""
declare ARG_DATABASE_NAME=""
declare ARG_BACKUP_BEFORE_DELETE=""
declare ARG_CLEAR_WAL=""
declare ARG_OVERWRITE=""
declare -a POSITIONAL_ARGS=()

usage() {
    cat <<EOF
Использование:
  ${SCRIPT_NAME} [КЛЮЧИ]
  ${SCRIPT_NAME} --action backup ВЕРСИЯ КЛАСТЕР [КЛЮЧИ]
  ${SCRIPT_NAME} --action delete ВЕРСИЯ КЛАСТЕР [КЛЮЧИ]

Без ключей сценарий работает интерактивно. Если указано действие через
--action или PGCC_ACTION, меню и подтверждения отключаются. Недостающий
обязательный параметр в таком режиме считается ошибкой.

Общие ключи:
  -h, --help                         Показать эту справку и выйти
  -v, --version                      Показать версию сценария и выйти
  -a, --action ДЕЙСТВИЕ              info|install|backup|restore|delete
      --package ПАКЕТ                Точный серверный пакет PostgreSQL
      --pg-family СЕМЕЙСТВО          postgresql|postgrespro-ent|tantor-free
      --pg-version ВЕРСИЯ            Версия PostgreSQL, например 16
      --cluster-name ИМЯ             Имя создаваемого или целевого кластера
      --port ПОРТ                    Порт создаваемого/восстанавливаемого кластера
      --schema ИМЯ                   Схема и владелец БД при установке
      --user ИМЯ                     Прикладной пользователь БД при установке
      --password ПАРОЛЬ              Пароль пользователя при установке
      --backup-dir КАТАЛОГ           Каталог резервных копий
      --backup-file ФАЙЛ             Архив restore: относительный или полный путь
      --backup-type ТИП              Тип backup: hot|cold или 1|2; по умолчанию cold
      --database ИМЯ                 База для горячего backup/restore
      --backup-before-delete ДА|НЕТ  Создать бэкап перед delete; по умолчанию да
      --clear-wal ДА|НЕТ              Выполнить pg_resetwal перед бэкапом; по умолчанию нет
      --overwrite ДА|НЕТ              Разрешить restore поверх кластера; по умолчанию нет

Для backup и delete поддерживается форма pg_ctlcluster: два позиционных
аргумента ВЕРСИЯ КЛАСТЕР после действия, например: backup 16 subsys.

Значения ДА|НЕТ: yes/no, y/n, true/false, 1/0.

Переменные окружения:
  PGCC_ACTION, PGCC_PACKAGE, PGCC_PG_FAMILY, PGCC_PG_VERSION,
  PGCC_CLUSTER_NAME, PGCC_CLUSTER_PORT, PGCC_SCHEMA, PGCC_DB_USER,
  PGCC_DB_PASSWORD, PGCC_BACKUP_DIR, PGCC_BACKUP_FILE,
  PGCC_BACKUP_TYPE, PGCC_DATABASE,
  PGCC_BACKUP_BEFORE_DELETE, PGCC_CLEAR_WAL, PGCC_OVERWRITE.

Примеры:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --version
  ${SCRIPT_NAME} --action info
  ${SCRIPT_NAME} --action install --package postgrespro-ent-16-server \\
    --cluster-name subsys --port 5432 --schema subsys --user subsys \\
    --password 'change-me'
  PGCC_ACTION=install PGCC_PACKAGE=postgrespro-ent-16-server \\
    PGCC_CLUSTER_NAME=subsys PGCC_CLUSTER_PORT=5432 \\
    PGCC_SCHEMA=subsys PGCC_DB_USER=subsys PGCC_DB_PASSWORD='change-me' \\
    ${SCRIPT_NAME}
  ${SCRIPT_NAME} --action backup --pg-version 16 --cluster-name subsys
  ${SCRIPT_NAME} --action backup 16 subsys --backup-type hot --database subsys
  ${SCRIPT_NAME} --action backup 16 subsys
  ${SCRIPT_NAME} --action restore --backup-file 16-subsys-20260904-152034.tar.gz \\
    --cluster-name subsys2 --port 54322
  ${SCRIPT_NAME} --action restore --backup-file 16-subsys-20260905-101112-dmp.tar.gz \\
    --pg-version 16 --cluster-name subsys2 --database targetdb --overwrite yes
  ${SCRIPT_NAME} --action delete --pg-version 16 --cluster-name subsys2 \\
    --backup-before-delete yes --clear-wal no
  ${SCRIPT_NAME} --action delete 16 subsys2 --backup-before-delete no

Пароль безопаснее передавать через PGCC_DB_PASSWORD: значение ключа
--password может быть видно другим пользователям в списке процессов.
EOF
}

version() {
    printf '%s, версия %s\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
}

option_value_required() {
    (($# >= 2)) && [[ -n "$2" ]] || die "для ключа $1 требуется значение"
}

parse_args() {
    while (($#)); do
        case "$1" in
            -h|--help) SHOW_HELP=1; shift ;;
            -v|--version) SHOW_VERSION=1; shift ;;
            -a|--action) option_value_required "$@"; ARG_ACTION="$2"; shift 2 ;;
            --action=*) ARG_ACTION="${1#*=}"; shift ;;
            --package) option_value_required "$@"; ARG_PACKAGE="$2"; shift 2 ;;
            --package=*) ARG_PACKAGE="${1#*=}"; shift ;;
            --pg-family) option_value_required "$@"; ARG_PG_FAMILY="$2"; shift 2 ;;
            --pg-family=*) ARG_PG_FAMILY="${1#*=}"; shift ;;
            --pg-version) option_value_required "$@"; ARG_PG_VERSION="$2"; shift 2 ;;
            --pg-version=*) ARG_PG_VERSION="${1#*=}"; shift ;;
            --cluster-name) option_value_required "$@"; ARG_CLUSTER_NAME="$2"; shift 2 ;;
            --cluster-name=*) ARG_CLUSTER_NAME="${1#*=}"; shift ;;
            --port) option_value_required "$@"; ARG_CLUSTER_PORT="$2"; shift 2 ;;
            --port=*) ARG_CLUSTER_PORT="${1#*=}"; shift ;;
            --schema) option_value_required "$@"; ARG_SCHEMA="$2"; shift 2 ;;
            --schema=*) ARG_SCHEMA="${1#*=}"; shift ;;
            --user) option_value_required "$@"; ARG_DB_USER="$2"; shift 2 ;;
            --user=*) ARG_DB_USER="${1#*=}"; shift ;;
            --password) option_value_required "$@"; ARG_DB_PASSWORD="$2"; shift 2 ;;
            --password=*) ARG_DB_PASSWORD="${1#*=}"; shift ;;
            --backup-dir) option_value_required "$@"; ARG_BACKUP_DIR="$2"; shift 2 ;;
            --backup-dir=*) ARG_BACKUP_DIR="${1#*=}"; shift ;;
            --backup-file) option_value_required "$@"; ARG_BACKUP_FILE="$2"; shift 2 ;;
            --backup-file=*) ARG_BACKUP_FILE="${1#*=}"; shift ;;
            --backup-type) option_value_required "$@"; ARG_BACKUP_TYPE="$2"; shift 2 ;;
            --backup-type=*) ARG_BACKUP_TYPE="${1#*=}"; shift ;;
            --database) option_value_required "$@"; ARG_DATABASE_NAME="$2"; shift 2 ;;
            --database=*) ARG_DATABASE_NAME="${1#*=}"; shift ;;
            --backup-before-delete) option_value_required "$@"; ARG_BACKUP_BEFORE_DELETE="$2"; shift 2 ;;
            --backup-before-delete=*) ARG_BACKUP_BEFORE_DELETE="${1#*=}"; shift ;;
            --clear-wal) option_value_required "$@"; ARG_CLEAR_WAL="$2"; shift 2 ;;
            --clear-wal=*) ARG_CLEAR_WAL="${1#*=}"; shift ;;
            --overwrite) option_value_required "$@"; ARG_OVERWRITE="$2"; shift 2 ;;
            --overwrite=*) ARG_OVERWRITE="${1#*=}"; shift ;;
            --) shift; POSITIONAL_ARGS+=("$@"); break ;;
            -*) die "неизвестный ключ: $1 (используйте --help)" ;;
            *) POSITIONAL_ARGS+=("$1"); shift ;;
        esac
    done
}

normalize_yes_no() {
    case "${1,,}" in
        y|yes|true|1|д|да) printf 'yes' ;;
        n|no|false|0|н|нет) printf 'no' ;;
        *) die "ожидалось значение yes/no, получено: $1" ;;
    esac
}

apply_runtime_options() {
    ACTION="${ARG_ACTION:-${PGCC_ACTION:-}}"
    REQUESTED_PACKAGE="${ARG_PACKAGE:-${PGCC_PACKAGE:-}}"
    BACKUP_FILE="${ARG_BACKUP_FILE:-${PGCC_BACKUP_FILE:-}}"
    DATABASE_NAME="${ARG_DATABASE_NAME:-${PGCC_DATABASE:-}}"
    [[ -n "${DATABASE_NAME}" ]] && TARGET_DATABASE_SET=1

    if [[ -n "${PGCC_PG_FAMILY:-}" ]]; then pg="${PGCC_PG_FAMILY}"; fi
    if [[ -n "${PGCC_PG_VERSION:-}" ]]; then pg_ver="${PGCC_PG_VERSION}"; TARGET_VERSION_SET=1; fi
    if [[ -n "${PGCC_CLUSTER_NAME:-}" ]]; then cls_nm="${PGCC_CLUSTER_NAME}"; TARGET_NAME_SET=1; fi
    if [[ -n "${PGCC_CLUSTER_PORT:-}" ]]; then cls_pt="${PGCC_CLUSTER_PORT}"; TARGET_PORT_SET=1; fi
    if [[ -n "${PGCC_SCHEMA:-}" ]]; then cls_ch="${PGCC_SCHEMA}"; fi
    if [[ -n "${PGCC_DB_USER:-}" ]]; then cls_us="${PGCC_DB_USER}"; fi
    if [[ -n "${PGCC_DB_PASSWORD:-}" ]]; then cls_pw="${PGCC_DB_PASSWORD}"; fi
    if [[ -n "${PGCC_BACKUP_DIR:-}" ]]; then backup_dir="${PGCC_BACKUP_DIR}"; fi

    if [[ -n "${ARG_PG_FAMILY}" ]]; then pg="${ARG_PG_FAMILY}"; fi
    if [[ -n "${ARG_PG_VERSION}" ]]; then pg_ver="${ARG_PG_VERSION}"; TARGET_VERSION_SET=1; fi
    if [[ -n "${ARG_CLUSTER_NAME}" ]]; then cls_nm="${ARG_CLUSTER_NAME}"; TARGET_NAME_SET=1; fi
    if [[ -n "${ARG_CLUSTER_PORT}" ]]; then cls_pt="${ARG_CLUSTER_PORT}"; TARGET_PORT_SET=1; fi
    if [[ -n "${ARG_SCHEMA}" ]]; then cls_ch="${ARG_SCHEMA}"; fi
    if [[ -n "${ARG_DB_USER}" ]]; then cls_us="${ARG_DB_USER}"; fi
    if [[ -n "${ARG_DB_PASSWORD}" ]]; then cls_pw="${ARG_DB_PASSWORD}"; fi
    if [[ -n "${ARG_BACKUP_DIR}" ]]; then backup_dir="${ARG_BACKUP_DIR}"; fi

    BACKUP_BEFORE_DELETE="$(normalize_yes_no "${ARG_BACKUP_BEFORE_DELETE:-${PGCC_BACKUP_BEFORE_DELETE:-yes}}")"
    CLEAR_WAL="$(normalize_yes_no "${ARG_CLEAR_WAL:-${PGCC_CLEAR_WAL:-no}}")"
    OVERWRITE_EXISTING="$(normalize_yes_no "${ARG_OVERWRITE:-${PGCC_OVERWRITE:-no}}")"
    BACKUP_TYPE="${ARG_BACKUP_TYPE:-${PGCC_BACKUP_TYPE:-cold}}"
    case "${BACKUP_TYPE,,}" in
        1|hot|горячий) BACKUP_TYPE=hot ;;
        2|cold|холодный) BACKUP_TYPE=cold ;;
        *) die "неподдерживаемый тип бэкапа ${BACKUP_TYPE}; используйте hot|cold или 1|2" ;;
    esac

    if [[ -n "${ACTION}" ]]; then
        case "${ACTION,,}" in
            info|install|backup|restore|delete) ACTION="${ACTION,,}" ;;
            *) die "неподдерживаемое действие ${ACTION}; используйте info|install|backup|restore|delete" ;;
        esac
        NON_INTERACTIVE=1
    fi

    if ((${#POSITIONAL_ARGS[@]})); then
        case "${ACTION}" in
            backup|delete) ;;
            *) die "позиционные аргументы ВЕРСИЯ КЛАСТЕР поддерживаются только для backup и delete" ;;
        esac
        ((${#POSITIONAL_ARGS[@]} == 2)) || die \
            "для ${ACTION} позиционно укажите ровно два значения: ВЕРСИЯ КЛАСТЕР"
        [[ -z "${ARG_PG_VERSION}" && -z "${ARG_CLUSTER_NAME}" ]] || die \
            "не смешивайте ВЕРСИЯ КЛАСТЕР с --pg-version и --cluster-name"
        pg_ver="${POSITIONAL_ARGS[0]}"
        cls_nm="${POSITIONAL_ARGS[1]}"
        TARGET_VERSION_SET=1
        TARGET_NAME_SET=1
    fi
}

cleanup() {
    if [[ -n "${CLEANUP_DIR}" && "${CLEANUP_DIR}" == /tmp/create-claster.* && -d "${CLEANUP_DIR}" ]]; then
        rm -rf -- "${CLEANUP_DIR}"
    fi
}

on_error() {
    local status="$1" line="$2"
    printf '\nОШИБКА: выполнение прервано (строка %s, код %s).\n' "${line}" "${status}" >&2
    exit "${status}"
}

trap cleanup EXIT
trap 'on_error $? $LINENO' ERR

die() {
    printf '\nОШИБКА: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'ПРЕДУПРЕЖДЕНИЕ: %s\n' "$*" >&2
}

header() {
    ((NON_INTERACTIVE)) || clear 2>/dev/null || true
    printf '%s, версия %s\n%s\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}" "${SEPARATOR}"
}

step() {
    printf '%s\n%s\n' "$1" "${SEPARATOR}"
}

pause() {
    ((NON_INTERACTIVE)) && return 0
    read -r -p "Нажмите Enter, чтобы продолжить... " _ || true
}

is_wsl_without_parsec() {
    [[ -r /proc/sys/kernel/osrelease ]] &&
        grep -qi microsoft /proc/sys/kernel/osrelease &&
        [[ ! -e /dev/parsec ]]
}

run_parsec_aware() {
    local error_file status line
    if ! is_wsl_without_parsec; then
        "$@"
        return
    fi
    error_file="$(mktemp /tmp/create-claster.stderr.XXXXXX)"
    if "$@" 2>"${error_file}"; then
        status=0
    else
        status=$?
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == "Не удается открыть файл управления PARSEC." ]] || printf '%s\n' "${line}" >&2
    done <"${error_file}"
    rm -f -- "${error_file}"
    return "${status}"
}

confirm() {
    local prompt="$1" default="${2:-Y}" answer
    if ((NON_INTERACTIVE)); then
        [[ "${default}" == "Y" ]]
        return
    fi
    if [[ "${default}" == "Y" ]]; then
        read -r -p "${prompt} [Y/n]: " answer || return 1
        answer="${answer:-Y}"
    else
        read -r -p "${prompt} [y/N]: " answer || return 1
        answer="${answer:-N}"
    fi
    [[ "${answer}" =~ ^[YyДд]$ ]]
}

require_root() {
    if (( EUID != 0 )); then
        command -v sudo >/dev/null 2>&1 || die "сценарий нужно запускать от root"
        exec sudo -- bash "${BASH_SOURCE[0]}" "$@"
    fi
}

load_config() {
    [[ -r "${CONFIG_FILE}" ]] || die "не найден конфиг ${CONFIG_FILE}"
    chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
    : "${LANG:=ru_RU.utf8}" "${LC_ALL:=ru_RU.utf8}"
    : "${pg:=postgresql}" "${pg_ver:=16}"
    : "${cls_pt:=5432}" "${cls_nm:=subsys}" "${cls_ch:=subsys}"
    : "${cls_us:=subsys}" "${cls_pw:=subsys}"
    : "${backup_dir:=/.postgres/backup}"
    CONFIG_CLS_PT="${cls_pt}"
    CONFIG_CLS_NM="${cls_nm}"
    CONFIG_CLS_CH="${cls_ch}"
    CONFIG_CLS_US="${cls_us}"
    CONFIG_CLS_PW="${cls_pw}"
    export LANG LC_ALL
}

save_config() {
    local tmp
    tmp="$(mktemp "${CONFIG_FILE}.XXXXXX")"
    {
        printf 'export LANG=%q\n' "${LANG}"
        printf 'export LC_ALL=%q\n\n' "${LC_ALL}"
        printf 'export pg=%q\n' "${pg}"
        printf 'export pg_ver=%q\n\n' "${pg_ver}"
        printf 'export cls_pt=%q\n' "${CONFIG_CLS_PT}"
        printf 'export cls_nm=%q\n' "${CONFIG_CLS_NM}"
        printf 'export cls_ch=%q\n' "${CONFIG_CLS_CH}"
        printf 'export cls_us=%q\n' "${CONFIG_CLS_US}"
        printf 'export cls_pw=%q\n\n' "${CONFIG_CLS_PW}"
        printf 'export backup_dir=%q\n' "${backup_dir}"
    } >"${tmp}"
    chmod 600 "${tmp}"
    mv -f -- "${tmp}" "${CONFIG_FILE}"
}

package_installed() {
    dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii '
}

server_package_installed() {
    local package="$1" base
    if [[ "${package}" =~ ^postgrespro-ent-[0-9]+-server$ ]]; then
        base="${package%-server}"
        package_installed "${package}" && package_installed "${base}-contrib"
    else
        package_installed "${package}"
    fi
}

package_available() {
    local candidate
    candidate="$(LC_ALL=C apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {candidate=$2} END {print candidate}')"
    [[ -n "${candidate}" && "${candidate}" != "(none)" ]]
}

install_package() {
    local package="$1" simulation removals
    local -a targets=("${package}")
    printf '\nУстановка пакета %s\n%s\n' "${package}" "${SEPARATOR}"
    unmask_vendor_service "${package}"

    if [[ "${package}" =~ ^postgrespro-ent-[0-9]+-server$ ]]; then
        targets+=("${package%-server}-contrib")
        printf 'Дополнительно будет установлен пакет расширений %s.\n' "${package%-server}-contrib"
    fi

    simulation="$(LC_ALL=C apt-get -s install -- "${targets[@]}")" || die "APT не смог рассчитать установку ${package}"
    removals="$(awk '$1 == "Remv" {if (list) list=list ", "; list=list $2} END {print list}' <<<"${simulation}")"
    if [[ -n "${removals}" ]]; then
        die "APT планирует удалить установленные пакеты: ${removals}. Автоматическая установка отменена"
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y -- "${targets[@]}" || die "не удалось установить пакет ${package}"
    if [[ "${package}" == postgresql-common ]]; then
        package_installed "${package}" || die "пакет ${package} не отмечен как установленный"
    else
        server_package_installed "${package}" || die "серверный пакет ${package} не отмечен как установленный"
    fi
}

ensure_postgresql_common() {
    if package_installed postgresql-common; then
        ((NON_INTERACTIVE)) || printf 'Обязательный пакет postgresql-common уже установлен.\n'
        return
    fi
    package_available postgresql-common || {
        printf 'Обновление сведений о репозиториях...\n'
        apt-get update || die "не удалось обновить сведения о репозиториях"
    }
    package_available postgresql-common || die "postgresql-common отсутствует в подключённых репозиториях"
    install_package postgresql-common
}

package_to_fields() {
    local package="$1"
    if [[ "${package}" =~ ^postgrespro-ent-([0-9]+)-server$ ]]; then
        printf 'postgrespro-ent|%s\n' "${BASH_REMATCH[1]}"
    elif [[ "${package}" =~ ^postgresql-([0-9]+)-server$ ]]; then
        printf 'postgresql|%s\n' "${BASH_REMATCH[1]}"
    elif [[ "${package}" =~ ^tantor-free-server-([0-9]+)(-server)?$ ]]; then
        printf 'tantor-free|%s\n' "${BASH_REMATCH[1]}"
    else
        return 1
    fi
}

server_packages() {
    apt-cache pkgnames 2>/dev/null |
        grep -E '^(postgrespro-ent-[0-9]+-server|postgresql-[0-9]+-server|tantor-free-server-[0-9]+(-server)?)$' |
        sort -u
}

installed_server_packages() {
    local package
    while IFS= read -r package; do
        server_package_installed "${package}" && printf '%s\n' "${package}"
    done < <(
        dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null |
            awk '$2 == "ii" {sub(/:.*/, "", $1); print $1}' |
            grep -E '^(postgrespro-ent-[0-9]+-server|postgresql-[0-9]+-server|tantor-free-server-[0-9]+(-server)?)$' |
            sort -u || true
    )
}

choose_from_packages() {
    local title="$1" choice fields package version previous index version_priority invalid=0
    shift
    local -a packages=("$@") ordered=()
    mapfile -t ordered < <(
        for package in "${packages[@]}"; do
            fields="$(package_to_fields "${package}")" || continue
            version="${fields#*|}"
            printf '%s|%s\n' "${version}" "${package}"
        done | sort -t'|' -k1,1Vr -k2,2 | cut -d'|' -f2-
    )
    ((${#ordered[@]})) || return 1

    while true; do
        if ((invalid)); then
            header
            step "Подготовка пакетов"
            warn "неверный номер"
        fi
        printf '\n%s\n' "${title}"
        previous=""
        index=0
        version_priority=0
        for package in "${ordered[@]}"; do
            fields="$(package_to_fields "${package}")"
            version="${fields#*|}"
            if [[ "${version}" != "${previous}" ]]; then
                ((version_priority += 1))
                printf '\nPostgreSQL %s:\n' "${version}"
                previous="${version}"
            fi
            ((index += 1))
            printf '  %d - %s (приоритет %s)\n' "${index}" "${package}" "${version_priority}"
        done
        printf '  0 - Выход\n'
        read -r -p "Выберите пакет: " choice || exit 0
        [[ "${choice}" == "0" ]] && exit 0
        if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ordered[@]} )); then
            SELECTED_PACKAGE="${ordered[choice-1]}"
            return 0
        fi
        invalid=1
    done
}

configure_selected_package() {
    local fields
    fields="$(package_to_fields "${SELECTED_PACKAGE}")" || die "неподдерживаемый пакет ${SELECTED_PACKAGE}"
    pg="${fields%%|*}"
    pg_ver="${fields#*|}"
    case "${pg}" in
        postgrespro-ent)
            PG_HOME="/opt/pgpro/ent-${pg_ver}"
            PG_EXT="${PG_HOME}/lib"
            DATA_BASE="/var/lib/postgresql/${pg_ver}"
            ;;
        tantor-free)
            PG_HOME="/opt/tantor/db/${pg_ver}"
            PG_EXT="${PG_HOME}/lib/postgresql"
            DATA_BASE="/var/lib/postgresql/tantor-free-${pg_ver}"
            ;;
        postgresql)
            PG_HOME="/usr/lib/postgresql/${pg_ver}"
            PG_EXT="${PG_HOME}/lib"
            DATA_BASE="/var/lib/postgresql/${pg_ver}"
            ;;
    esac
    [[ -x "${PG_HOME}/bin/postgres" ]] || die "в пакете ${SELECTED_PACKAGE} не найден ${PG_HOME}/bin/postgres"
    save_config
}

vendor_service_name() {
    local package="$1"
    case "${package}" in
        postgrespro-ent-*-server) printf '%s' "${package%-server}" ;;
        tantor-free-server-*-server) printf '%s' "${package%-server}" ;;
        tantor-free-server-*) printf '%s' "${package}" ;;
        *) return 1 ;;
    esac
}

unmask_vendor_service() {
    local unit
    unit="$(vendor_service_name "$1")" || return 0
    printf 'Снятие маски со штатной службы %s перед установкой...\n' "${unit}"
    systemctl unmask "${unit}" || die "не удалось снять маску со службы ${unit}"
}

stop_disable_vendor_service() {
    local unit
    unit="$(vendor_service_name "$1")" || return 0
    if ((NON_INTERACTIVE)); then
        systemctl stop "${unit}" >/dev/null 2>&1 || die "не удалось остановить службу ${unit}"
        systemctl disable "${unit}" >/dev/null 2>&1 || die "не удалось отключить автозапуск службы ${unit}"
    else
        systemctl stop "${unit}" || die "не удалось остановить службу ${unit}"
        systemctl disable "${unit}" || die "не удалось отключить автозапуск службы ${unit}"
        printf 'Штатная служба %s остановлена, её автозапуск отключён.\n' "${unit}"
    fi
}

select_or_install_server() {
    local package preferred="" fields
    local -a installed=() available=()

    if ((NON_INTERACTIVE)); then
        if [[ -n "${REQUESTED_PACKAGE}" ]]; then
            package="${REQUESTED_PACKAGE}"
            fields="$(package_to_fields "${package}")" || die "неподдерживаемый пакет ${package}"
        else
            [[ "${pg_ver}" =~ ^[0-9]+$ ]] || die "недопустимая версия PostgreSQL: ${pg_ver}"
            case "${pg}" in
                postgrespro-ent) package="postgrespro-ent-${pg_ver}-server" ;;
                postgresql) package="postgresql-${pg_ver}-server" ;;
                tantor-free)
                    package="tantor-free-server-${pg_ver}-server"
                    if ! server_package_installed "${package}" && ! package_available "${package}"; then
                        package="tantor-free-server-${pg_ver}"
                    fi
                    ;;
                *) die "неподдерживаемое семейство PostgreSQL: ${pg}" ;;
            esac
        fi
        SELECTED_PACKAGE="${package}"
        if server_package_installed "${SELECTED_PACKAGE}"; then
            ((NON_INTERACTIVE)) || printf 'Серверный пакет %s уже установлен.\n' "${SELECTED_PACKAGE}"
        else
            if ! package_available "${SELECTED_PACKAGE}"; then
                printf 'Обновление сведений о репозиториях...\n'
                apt-get update || die "не удалось обновить сведения о репозиториях"
            fi
            package_available "${SELECTED_PACKAGE}" || die \
                "пакет ${SELECTED_PACKAGE} отсутствует в подключённых репозиториях"
            install_package "${SELECTED_PACKAGE}"
        fi
        configure_selected_package
        stop_disable_vendor_service "${SELECTED_PACKAGE}"
        return 0
    fi

    mapfile -t installed < <(installed_server_packages)
    for package in "${installed[@]}"; do
        fields="$(package_to_fields "${package}")"
        if [[ "${fields%%|*}" == "${pg}" && "${fields#*|}" == "${pg_ver}" ]]; then
            preferred="${package}"
            break
        fi
    done
    if [[ -n "${preferred}" ]]; then
        SELECTED_PACKAGE="${preferred}"
        printf 'Серверный пакет %s уже установлен.\n' "${SELECTED_PACKAGE}"
    elif ((${#installed[@]} == 1)); then
        SELECTED_PACKAGE="${installed[0]}"
        printf 'Найден установленный серверный пакет %s.\n' "${SELECTED_PACKAGE}"
    elif ((${#installed[@]} > 1)); then
        choose_from_packages "Установлено несколько серверных пакетов:" "${installed[@]}"
    else
        mapfile -t available < <(server_packages)
        if ((${#available[@]} == 0)); then
            printf 'Серверные пакеты не найдены. Обновление сведений о репозиториях...\n'
            apt-get update || die "не удалось обновить сведения о репозиториях"
            mapfile -t available < <(server_packages)
        fi
        ((${#available[@]})) || die "подходящие серверные пакеты отсутствуют в репозиториях"
        choose_from_packages "Доступные серверные пакеты (приоритет 1 — самая новая версия):" "${available[@]}"
        install_package "${SELECTED_PACKAGE}"
    fi
    configure_selected_package
    stop_disable_vendor_service "${SELECTED_PACKAGE}"
}

ensure_symlink() {
    local target="$1" link="$2"
    mkdir -p -- "$(dirname -- "${link}")"
    if [[ -L "${link}" ]]; then
        ln -sfn -- "${target}" "${link}"
    elif [[ -e "${link}" ]]; then
        warn "${link} уже существует и не является симлинком; оставлен без изменения"
    else
        ln -s -- "${target}" "${link}"
    fi
}

prepare_postgres_root() {
    mkdir -p /.postgres/systemd/save /.postgres/tmp
    prepare_backup_directory
    ensure_symlink "/etc/postgresql/${pg_ver}" /.postgres/etc
    if [[ -d /.postgres/data && ! -L /.postgres/data ]]; then
        if [[ -L "${DATA_BASE}" && "$(readlink -f "${DATA_BASE}")" == "$(readlink -f /.postgres/data)" ]]; then
            ((NON_INTERACTIVE)) || printf 'Каталог данных используется через ссылку %s -> /.postgres/data.\n' "${DATA_BASE}"
        elif [[ ! -e "${DATA_BASE}" && ! -L "${DATA_BASE}" ]]; then
            ensure_symlink /.postgres/data "${DATA_BASE}"
        else
            warn "${DATA_BASE} не ссылается на существующий каталог /.postgres/data"
        fi
    else
        ensure_symlink "${DATA_BASE}" /.postgres/data
    fi
    ensure_symlink /var/run /.postgres/run
    local name
    for name in bin doc include lib man share; do
        ensure_symlink "${PG_HOME}/${name}" "/.postgres/${name}"
    done
    if [[ "${PG_HOME}" != "/usr/lib/postgresql/${pg_ver}" ]]; then
        mkdir -p /usr/lib/postgresql
        ensure_symlink "${PG_HOME}" "/usr/lib/postgresql/${pg_ver}"
    fi
}

prepare_backup_directory() {
    local access="${1:-read}" resolved
    if [[ -L "${backup_dir}" ]]; then
        resolved="$(readlink -f -- "${backup_dir}")" || die \
            "каталог бэкапов ${backup_dir} является повреждённой символьной ссылкой"
        [[ -d "${resolved}" ]] || die \
            "символьная ссылка ${backup_dir} указывает не на каталог: ${resolved}"
    elif [[ -e "${backup_dir}" ]]; then
        [[ -d "${backup_dir}" ]] || die "путь бэкапов не является каталогом: ${backup_dir}"
    else
        mkdir -p -- "${backup_dir}" || die "не удалось создать каталог бэкапов ${backup_dir}"
    fi
    [[ -r "${backup_dir}" && -x "${backup_dir}" ]] || die \
        "нет доступа к каталогу бэкапов ${backup_dir}"
    if [[ "${access}" == write && ! -w "${backup_dir}" ]]; then
        die "нет прав на запись в каталог бэкапов ${backup_dir}"
    fi
}

cluster_rows() {
    pg_lsclusters --no-header 2>/dev/null || true
}

cluster_exists() {
    local version="$1" name="$2"
    cluster_rows | awk -v v="${version}" -v n="${name}" '$1 == v && $2 == n {found=1} END {exit !found}'
}

cluster_online() {
    local version="$1" name="$2"
    cluster_rows | awk -v v="${version}" -v n="${name}" \
        '$1 == v && $2 == n && $4 ~ /^online/ {found=1} END {exit !found}'
}

start_cluster_checked() {
    local version="$1" name="$2" service state status
    service="postgresql@${version}-${name}.service"

    if cluster_online "${version}" "${name}"; then
        printf 'Кластер %s/%s уже запущен.\n' "${version}" "${name}"
        return 0
    fi

    # В WSL вызов pg_ctlcluster от root перенаправляется в systemctl. Если
    # systemd ещё находится в состоянии starting, такой вызов может ждать
    # бесконечно, хотя PostgreSQL способен штатно запуститься напрямую.
    if is_wsl_without_parsec; then
        if run_parsec_aware timeout --foreground 60s pg_ctlcluster \
            --skip-systemctl-redirect "${version}" "${name}" start; then
            status=0
        else
            status=$?
        fi
    elif run_parsec_aware timeout --foreground 60s pg_ctlcluster "${version}" "${name}" start; then
        status=0
    else
        status=$?
    fi

    if ((status == 0)) && cluster_online "${version}" "${name}"; then
        if is_wsl_without_parsec; then
            printf 'Кластер %s/%s запущен напрямую (без перенаправления в systemd WSL).\n' \
                "${version}" "${name}"
            return 0
        fi
        state="$(timeout 5s systemctl is-active "${service}" 2>/dev/null || true)"
        [[ "${state}" == active ]] || die \
            "кластер ${version}/${name} запущен, но служба ${service} не перешла в active (systemd=${state:-unknown})"
        return 0
    fi

    state="$(timeout 5s systemctl is-active "${service}" 2>/dev/null || true)"
    if ((status == 124)); then
        die "истекло время ожидания запуска ${version}/${name}; кластер=$(cluster_online "${version}" "${name}" && printf online || printf down), systemd=${state:-unknown}"
    fi
    die "не удалось подтвердить запуск ${version}/${name}: код=${status}, systemd=${state:-unknown}"
}

stop_cluster_checked() {
    local version="$1" name="$2" service status
    service="postgresql@${version}-${name}.service"
    if cluster_online "${version}" "${name}"; then
        if run_parsec_aware timeout --foreground 60s pg_ctlcluster \
            --skip-systemctl-redirect "${version}" "${name}" stop; then
            status=0
        else
            status=$?
        fi
        ((status == 0)) || die "не удалось остановить ${version}/${name}: код=${status}"
    fi
    run_parsec_aware timeout --foreground 15s systemctl stop "${service}" || true
    systemctl reset-failed "${service}" >/dev/null 2>&1 || true
    cluster_online "${version}" "${name}" && die "кластер ${version}/${name} остался запущен"
    return 0
}

port_in_use() {
    local port="$1"
    cluster_rows | awk -v p="${port}" '$3 == p {found=1} END {exit !found}'
}

port_in_use_by_other_cluster() {
    local port="$1" version="$2" name="$3"
    cluster_rows | awk -v p="${port}" -v v="${version}" -v n="${name}" \
        '$3 == p && !($1 == v && $2 == n) {found=1} END {exit !found}'
}

print_clusters_numbered() {
    local -a rows=()
    mapfile -t rows < <(cluster_rows)
    if ((${#rows[@]} == 0)); then
        printf 'Развёрнутых кластеров нет.\n'
        return 1
    fi
    local i
    for i in "${!rows[@]}"; do
        printf '%3d - %s\n' "$((i + 1))" "${rows[i]}"
    done
}

validate_identifier() {
    [[ "$1" =~ ^[a-z_][a-z0-9_]*$ ]]
}

prompt_value() {
    local label="$1" current="$2" value
    read -r -p "${label} [${current}]: " value || return 1
    printf '%s' "${value:-${current}}"
}

prompt_cluster_settings() {
    local old_name="${cls_nm}" new_port="${cls_pt}" new_name="${cls_nm}"
    local new_schema="${cls_ch}" new_user="${cls_us}" new_password="${cls_pw}" value
    while true; do
        value="$(prompt_value "Порт" "${new_port}")" || return 1
        [[ "${value}" =~ ^[0-9]+$ ]] && ((value >= 1 && value <= 65535)) || {
            warn "порт должен быть числом от 1 до 65535"
            continue
        }
        if port_in_use "${value}"; then
            warn "порт ${value} уже назначен развёрнутому кластеру"
            continue
        fi
        new_port="${value}"
        break
    done

    while true; do
        value="$(prompt_value "Имя кластера" "${new_name}")" || return 1
        validate_identifier "${value}" || { warn "используйте строчные латинские буквы, цифры и подчёркивание"; continue; }
        cluster_exists "${pg_ver}" "${value}" && { warn "кластер ${pg_ver}/${value} уже развёрнут"; continue; }
        new_name="${value}"
        break
    done
    if [[ "${new_name}" != "${old_name}" ]]; then
        new_schema="${new_name}"
        new_user="${new_name}"
        new_password="${new_name}"
    fi

    while true; do
        value="$(prompt_value "Схема/владелец БД" "${new_schema}")" || return 1
        validate_identifier "${value}" || { warn "недопустимое имя схемы"; continue; }
        new_schema="${value}"
        break
    done
    while true; do
        value="$(prompt_value "Пользователь БД" "${new_user}")" || return 1
        validate_identifier "${value}" || { warn "недопустимое имя пользователя"; continue; }
        new_user="${value}"
        break
    done
    while true; do
        value="$(prompt_value "Пароль пользователя" "${new_password}")" || return 1
        [[ -n "${value}" ]] || { warn "пароль не может быть пустым"; continue; }
        new_password="${value}"
        break
    done

    printf '\nПараметры:\n  пакет: %s\n  версия: %s\n  порт: %s\n  кластер: %s\n  схема/владелец: %s\n  пользователь: %s\n' \
        "${SELECTED_PACKAGE}" "${pg_ver}" "${new_port}" "${new_name}" "${new_schema}" "${new_user}"
    confirm "Создать кластер с этими параметрами?" Y || return 1

    cls_pt="${new_port}"
    cls_nm="${new_name}"
    cls_ch="${new_schema}"
    cls_us="${new_user}"
    cls_pw="${new_password}"
}

systemd_unit_dir() {
    [[ -d /usr/lib/systemd/system ]] && printf '/usr/lib/systemd/system' || printf '/lib/systemd/system'
}

write_cluster_unit() {
    local unit_dir service data_dir
    unit_dir="$(systemd_unit_dir)"
    service="postgresql@${pg_ver}-${cls_nm}.service"
    data_dir="${DATA_BASE}/${cls_nm}"
    cat >"${unit_dir}/${service}" <<EOF
[Unit]
Description=PostgreSQL Cluster ${pg_ver}-${cls_nm}
AssertPathExists=/etc/postgresql/${pg_ver}/${cls_nm}/postgresql.conf
RequiresMountsFor=/etc/postgresql/${pg_ver}/${cls_nm} ${data_dir}
PartOf=postgresql.service
ReloadPropagatedFrom=postgresql.service
Before=postgresql.service
After=network.target

[Service]
Type=forking
ExecStart=-/usr/bin/pg_ctlcluster --skip-systemctl-redirect ${pg_ver}-${cls_nm} start
TimeoutStartSec=0
ExecStop=/usr/bin/pg_ctlcluster --skip-systemctl-redirect -m fast ${pg_ver}-${cls_nm} stop
TimeoutStopSec=1h
ExecReload=/usr/bin/pg_ctlcluster --skip-systemctl-redirect ${pg_ver}-${cls_nm} reload
PIDFile=/run/postgresql/${pg_ver}-${cls_nm}.pid
SyslogIdentifier=postgresql@${pg_ver}-${cls_nm}
OOMScoreAdjust=-900

[Install]
WantedBy=multi-user.target
EOF
    cp -f -- "${unit_dir}/${service}" "/.postgres/systemd/save/${service}"
    ensure_symlink "${unit_dir}/${service}" "/.postgres/systemd/${service}"
    systemctl daemon-reload
    systemctl enable "${service}"
}

create_cluster() {
    local auth_method data_dir data_log conf_dir create_conf lib_preloaded="" pg_cron="" lib role password_sql
    auth_method=md5
    ((pg_ver > 16)) && auth_method=scram-sha-256
    data_dir="${DATA_BASE}/${cls_nm}"
    data_log="/var/log/postgresql/${pg}-${pg_ver}-${cls_nm}.log"
    conf_dir="/etc/postgresql/${pg_ver}/${cls_nm}"
    create_conf="/etc/postgresql-common/createcluster-pg-claster-creator.conf"

    cat >"${create_conf}" <<'EOF'
ssl = on
cluster_name = '%v/%c'
log_line_prefix = '%%m [%%p] %%q%%u@%%d '
add_include_dir = 'conf.d'
EOF
    mkdir -p -- "${data_dir}" /var/log/postgresql
    chown -R postgres:postgres "${data_dir}"
    run_parsec_aware pg_createcluster "${pg_ver}" "${cls_nm}" -p "${cls_pt}" --start-conf=auto \
        -d "${data_dir}" -l "${data_log}" --createclusterconf="${create_conf}"

    mkdir -p -- "${conf_dir}/conf.d"
    cat >>"${conf_dir}/pg_hba.conf" <<EOF

# Added by ${SCRIPT_NAME}
host    all             all             127.0.0.1/32           ${auth_method}
host    all             all             172.21.0.0/16          ${auth_method}
host    all             all             172.16.0.0/12          ${auth_method}
host    all             all             10.0.0.0/8             ${auth_method}
host    all             all             192.168.0.0/16         ${auth_method}
local   ${cls_nm}       cron_user                               trust
local   ${cls_nm},replication multimaster_user                  trust
EOF
    cat >"${conf_dir}/conf.d/cluster_name.conf" <<EOF
cluster_name = '${cls_nm}'
EOF
    cat >"${conf_dir}/conf.d/listen_port.conf" <<EOF
unix_socket_directories = '/tmp'
listen_addresses = '*'
port = ${cls_pt}
EOF
    for lib in plugin_debugger pg_stat_statements pgpro_scheduler pg_cron; do
        if [[ -f "${PG_EXT}/${lib}.so" ]]; then
            [[ -n "${lib_preloaded}" ]] && lib_preloaded+=", "
            lib_preloaded+="${lib}"
            [[ "${lib}" == "pg_cron" ]] && pg_cron="cron.database_name = '${cls_nm}'"
        fi
    done
    cat >"${conf_dir}/conf.d/lib_preloaded.conf" <<EOF
shared_preload_libraries = '${lib_preloaded}'
${pg_cron}
EOF
    printf "password_encryption = '%s'\n" "${auth_method}" >"${conf_dir}/conf.d/password_encryption.conf"
    chown -R postgres:postgres "${data_dir}" "${conf_dir}"

    write_cluster_unit
    rm -f -- "/tmp/.s.PGSQL.${cls_pt}" "/tmp/.s.PGSQL.${cls_pt}.lock" \
        "/var/run/postgresql/.s.PGSQL.${cls_pt}" "/var/run/postgresql/.s.PGSQL.${cls_pt}.lock"
    start_cluster_checked "${pg_ver}" "${cls_nm}"

    password_sql="${cls_pw//\'/\'\'}"
    for role in cron_user "${cls_ch}" "${cls_us}"; do
        if ! runuser -u postgres -- "${PG_HOME}/bin/psql" -h /tmp -p "${cls_pt}" -d postgres -Atqc \
            "SELECT 1 FROM pg_roles WHERE rolname='${role}'" | grep -qx 1; then
            if [[ "${role}" == "cron_user" ]]; then
                runuser -u postgres -- "${PG_HOME}/bin/psql" -h /tmp -p "${cls_pt}" -d postgres -v ON_ERROR_STOP=1 \
                    -c "CREATE ROLE cron_user WITH LOGIN PASSWORD 'cron_user' SUPERUSER CREATEDB CREATEROLE REPLICATION"
            else
                runuser -u postgres -- "${PG_HOME}/bin/psql" -h /tmp -p "${cls_pt}" -d postgres -v ON_ERROR_STOP=1 \
                    -c "CREATE ROLE ${role} WITH LOGIN PASSWORD '${password_sql}' SUPERUSER CREATEDB CREATEROLE REPLICATION"
            fi
        fi
    done
    runuser -u postgres -- "${PG_HOME}/bin/psql" -h /tmp -p "${cls_pt}" -d postgres -v ON_ERROR_STOP=1 \
        -c "CREATE DATABASE ${cls_nm} OWNER ${cls_ch}"
    runuser -u postgres -- "${PG_HOME}/bin/psql" -h /tmp -p "${cls_pt}" -d "${cls_nm}" -v ON_ERROR_STOP=1 \
        -c "CREATE SCHEMA IF NOT EXISTS ${cls_ch} AUTHORIZATION ${cls_us}"
    for role in postgres "${cls_ch}" "${cls_us}" cron_user; do
        runuser -u postgres -- "${PG_HOME}/bin/psql" -h /tmp -p "${cls_pt}" -d postgres -v ON_ERROR_STOP=1 \
            -c "ALTER ROLE ${role} SET search_path = ${cls_ch},public,extens,pg_catalog,pg_temp" \
            -c "ALTER ROLE ${role} SET lc_messages TO 'C'"
    done
    save_config
    printf '\nКластер %s/%s создан и запущен на порту %s.\n' "${pg_ver}" "${cls_nm}" "${cls_pt}"
}

install_menu() {
    header
    step "Кластер: Установить"
    print_clusters_numbered || true
    if ((NON_INTERACTIVE)); then
        [[ "${cls_pt}" =~ ^[0-9]+$ ]] && ((cls_pt >= 1 && cls_pt <= 65535)) || \
            die "порт должен быть числом от 1 до 65535"
        validate_identifier "${cls_nm}" || die "недопустимое имя кластера: ${cls_nm}"
        validate_identifier "${cls_ch}" || die "недопустимое имя схемы: ${cls_ch}"
        validate_identifier "${cls_us}" || die "недопустимое имя пользователя: ${cls_us}"
        [[ -n "${cls_pw}" ]] || die "пароль пользователя не может быть пустым"
        cluster_exists "${pg_ver}" "${cls_nm}" && die "кластер ${pg_ver}/${cls_nm} уже развёрнут"
        port_in_use "${cls_pt}" && die "порт ${cls_pt} уже назначен развёрнутому кластеру"
        printf '\nПараметры:\n  пакет: %s\n  версия: %s\n  порт: %s\n  кластер: %s\n  схема/владелец: %s\n  пользователь: %s\n' \
            "${SELECTED_PACKAGE}" "${pg_ver}" "${cls_pt}" "${cls_nm}" "${cls_ch}" "${cls_us}"
        create_cluster || die "ошибка установки кластера"
        return 0
    fi
    printf '\nВведите новые значения или нажмите Enter для значений по умолчанию.\n'
    if prompt_cluster_settings; then
        create_cluster || die "ошибка установки кластера"
    else
        warn "установка отменена"
    fi
    pause
}

select_cluster() {
    local prompt="$1" choice i
    local -a rows=()
    SELECTED_CLUSTER_ROW=""
    mapfile -t rows < <(cluster_rows)
    ((${#rows[@]})) || return 1
    if ((NON_INTERACTIVE)); then
        ((TARGET_NAME_SET)) || die "для действия ${ACTION} укажите --cluster-name или PGCC_CLUSTER_NAME"
        SELECTED_CLUSTER_ROW="$(printf '%s\n' "${rows[@]}" | awk -v v="${pg_ver}" -v n="${cls_nm}" \
            '$1 == v && $2 == n {print; exit}')"
        [[ -n "${SELECTED_CLUSTER_ROW}" ]] || die "кластер ${pg_ver}/${cls_nm} не найден"
        return 0
    fi
    for i in "${!rows[@]}"; do printf '%3d - %s\n' "$((i + 1))" "${rows[i]}"; done
    printf '  0 - Вернуться назад\n'
    read -r -p "${prompt}: " choice || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    ((choice == 0)) && return 1
    ((choice >= 1 && choice <= ${#rows[@]})) || return 1
    SELECTED_CLUSTER_ROW="${rows[choice-1]}"
}

cluster_pg_home() {
    local version="$1" data="$2"
    if [[ "${data}" == /var/lib/postgresql/tantor-free-* ]]; then
        printf '/opt/tantor/db/%s' "${version}"
    elif [[ -x "/opt/pgpro/ent-${version}/bin/postgres" ]]; then
        printf '/opt/pgpro/ent-%s' "${version}"
    else
        printf '/usr/lib/postgresql/%s' "${version}"
    fi
}

backup_archive_name() {
    local version="$1" name="$2" timestamp="${3:-$(date +%Y%m%d-%H%M%S)}"
    printf '%s-%s-%s.tar.gz' "${version}" "${name}" "${timestamp}"
}

hot_backup_archive_name() {
    local version="$1" database="$2" timestamp="${3:-$(date +%Y%m%d-%H%M%S)}"
    printf '%s-%s-%s-dmp.tar.gz' "${version}" "${database}" "${timestamp}"
}

hot_backup_dump_name() {
    local version="$1" database="$2" timestamp="$3"
    printf '%s-%s-%s-dmp.backup' "${version}" "${database}" "${timestamp}"
}

backup_filename_supported() {
    local filename="${1##*/}"
    [[ "${filename}" =~ ^[0-9]+-[a-z_][a-z0-9_]*-[0-9]{8}-[0-9]{6}\.tar\.gz$ ]] ||
        [[ "${filename}" =~ ^[0-9]+-[A-Za-z0-9_][A-Za-z0-9_.-]*-[0-9]{8}-[0-9]{6}-dmp\.tar\.gz$ ]]
}

list_supported_backup_files() {
    local file
    while IFS= read -r file; do
        if backup_filename_supported "${file}"; then
            printf '%s\n' "${file}"
        fi
    done < <(find -H "${backup_dir}" -maxdepth 1 -type f -name '*.tar.gz' -printf '%f\n' 2>/dev/null)
    return 0
}

cluster_socket_directory() {
    local port="$1" directory
    for directory in /tmp /var/run/postgresql; do
        [[ -S "${directory}/.s.PGSQL.${port}" ]] && { printf '%s' "${directory}"; return 0; }
    done
    return 1
}

database_exists() {
    local home="$1" socket_dir="$2" port="$3" database="$4" escaped
    escaped="${database//\'/\'\'}"
    runuser -u postgres -- "${home}/bin/psql" -h "${socket_dir}" -p "${port}" -d postgres -Atqc \
        "SELECT 1 FROM pg_database WHERE datname='${escaped}'" | grep -qx 1
}

validate_database_name() {
    [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]]
}

load_cluster_databases() {
    local home="$1" socket_dir="$2" port="$3" scope="${4:-selectable}"
    local output row database size_bytes size where_clause
    local -a database_rows=()
    CLUSTER_DATABASES=()
    CLUSTER_DATABASE_SIZE_BYTES=()
    CLUSTER_DATABASE_SIZES=()
    case "${scope}" in
        selectable) where_clause='WHERE datallowconn AND NOT datistemplate' ;;
        all) where_clause='' ;;
        *) return 1 ;;
    esac
    output="$(
        runuser -u postgres -- "${home}/bin/psql" -h "${socket_dir}" -p "${port}" \
            -d postgres -A -t -F $'\t' -q -c \
            "SELECT datname, size_bytes, pg_size_pretty(size_bytes) FROM (SELECT datname, pg_database_size(datname) AS size_bytes FROM pg_database ${where_clause}) AS database_sizes ORDER BY datname"
    )" || return 1
    [[ -n "${output}" ]] && mapfile -t database_rows <<<"${output}"
    for row in "${database_rows[@]}"; do
        IFS=$'\t' read -r database size_bytes size <<<"${row}"
        [[ -n "${database}" ]] || continue
        CLUSTER_DATABASES+=("${database}")
        CLUSTER_DATABASE_SIZE_BYTES+=("${size_bytes}")
        CLUSTER_DATABASE_SIZES+=("${size}")
    done
}

print_cluster_databases() {
    local home="$1" socket_dir="$2" port="$3" version="$4" cluster="$5"
    local database i=0 name_width=0 number_width
    load_cluster_databases "${home}" "${socket_dir}" "${port}" || return 1
    for database in "${CLUSTER_DATABASES[@]}"; do
        ((${#database} > name_width)) && name_width=${#database}
    done
    printf '\nБазы данных кластера %s/%s:\n' "${version}" "${cluster}"
    if ((${#CLUSTER_DATABASES[@]} == 0)); then
        printf '  доступные базы данных не найдены\n'
        return 0
    fi
    number_width=${#CLUSTER_DATABASES[@]}
    number_width=${#number_width}
    for database in "${CLUSTER_DATABASES[@]}"; do
        ((i += 1))
        printf '  %*d - %-*s  %s\n' \
            "${number_width}" "${i}" "${name_width}" "${database}" \
            "${CLUSTER_DATABASE_SIZES[i - 1]}"
    done
    printf '  %*d - Вернуться назад\n' "${number_width}" 0
}

write_database_inventory_metadata() {
    local i
    printf 'database_count=%q\n' "${#CLUSTER_DATABASES[@]}"
    for i in "${!CLUSTER_DATABASES[@]}"; do
        printf 'database_%d_name=%q\n' "$((i + 1))" "${CLUSTER_DATABASES[i]}"
        printf 'database_%d_size_bytes=%q\n' "$((i + 1))" "${CLUSTER_DATABASE_SIZE_BYTES[i]}"
        printf 'database_%d_size_pretty=%q\n' "$((i + 1))" "${CLUSTER_DATABASE_SIZES[i]}"
    done
}

write_common_backup_metadata() {
    local backup_type="$1" version="$2" cluster="$3" port="$4" version_text="$5"
    printf 'backup_format=2\n'
    printf 'backup_type=%q\n' "${backup_type}"
    printf 'created_at=%q\n' "$(date --iso-8601=seconds)"
    printf 'host_name=%q\n' "$(hostname)"
    printf 'pg_family=%q\n' "${pg}"
    printf 'pg_version=%q\n' "${version}"
    printf 'postgres_version_text=%q\n' "${version_text}"
    printf 'cluster_name=%q\n' "${cluster}"
    printf 'cluster_port=%q\n' "${port}"
}

write_hot_database_metadata() {
    local database="$1" database_index="$2"
    printf 'database_name=%q\n' "${database}"
    printf 'database_size_bytes=%q\n' "${CLUSTER_DATABASE_SIZE_BYTES[database_index]}"
    printf 'database_size_pretty=%q\n' "${CLUSTER_DATABASE_SIZES[database_index]}"
    printf 'database_count=1\n'
    printf 'database_1_name=%q\n' "${database}"
    printf 'database_1_size_bytes=%q\n' "${CLUSTER_DATABASE_SIZE_BYTES[database_index]}"
    printf 'database_1_size_pretty=%q\n' "${CLUSTER_DATABASE_SIZES[database_index]}"
}

measure_data_directory() {
    local data="$1" size_line bytes_line
    [[ -d "${data}" ]] || die "каталог данных не найден: ${data}"
    size_line="$(du -sh -- "${data}")" || die \
        "не удалось определить размер каталога данных ${data} командой du -sh"
    bytes_line="$(du -s --block-size=1 -- "${data}")" || die \
        "не удалось определить размер каталога данных ${data} в байтах"
    DATA_DIRECTORY_DU_SH="${size_line}"
    DATA_DIRECTORY_SIZE_PRETTY="${size_line%%[[:space:]]*}"
    DATA_DIRECTORY_SIZE_BYTES="${bytes_line%%[[:space:]]*}"
    [[ "${DATA_DIRECTORY_SIZE_BYTES}" =~ ^[0-9]+$ ]] || die \
        "получен некорректный размер каталога данных ${data}"
}

database_in_loaded_list() {
    local expected="$1" database
    for database in "${CLUSTER_DATABASES[@]}"; do
        [[ "${database}" == "${expected}" ]] && return 0
    done
    return 1
}

database_number_in_loaded_list() {
    local expected="$1" database number=0
    for database in "${CLUSTER_DATABASES[@]}"; do
        ((number += 1))
        if [[ "${database}" == "${expected}" ]]; then
            printf '%s' "${number}"
            return 0
        fi
    done
    return 1
}

select_existing_database() {
    local label="$1" default="$2" choice index
    SELECTED_DATABASE=""
    while true; do
        read -r -p "${label} [${default}]: " choice || return 1
        choice="${choice:-${default}}"
        if [[ "${choice}" =~ ^[0-9]+$ ]]; then
            ((choice == 0)) && return 1
            index=$((choice - 1))
            if ((index >= 0 && index < ${#CLUSTER_DATABASES[@]})); then
                SELECTED_DATABASE="${CLUSTER_DATABASES[index]}"
                return 0
            fi
            warn "неверный номер базы данных"
            continue
        fi
        validate_database_name "${choice}" || {
            warn "допустимы латинские буквы, цифры, точка, дефис и подчёркивание"
            continue
        }
        if database_in_loaded_list "${choice}"; then
            SELECTED_DATABASE="${choice}"
            return 0
        fi
        warn "база данных ${choice} отсутствует в выбранном кластере"
    done
}

select_restore_database() {
    local label="$1" default="$2" choice index
    SELECTED_DATABASE=""
    while true; do
        read -r -p "${label} [${default}]: " choice || return 1
        choice="${choice:-${default}}"
        if [[ "${choice}" =~ ^[0-9]+$ ]]; then
            ((choice == 0)) && return 1
            index=$((choice - 1))
            if ((index >= 0 && index < ${#CLUSTER_DATABASES[@]})); then
                SELECTED_DATABASE="${CLUSTER_DATABASES[index]}"
                return 0
            fi
            warn "неверный номер базы данных"
            continue
        fi
        validate_database_name "${choice}" || {
            warn "допустимы латинские буквы, цифры, точка, дефис и подчёркивание"
            continue
        }
        SELECTED_DATABASE="${choice}"
        return 0
    done
}

create_database() {
    local home="$1" socket_dir="$2" port="$3" database="$4" owner="${5:-postgres}"
    [[ -x "${home}/bin/createdb" ]] || die "не найден ${home}/bin/createdb"
    validate_database_name "${database}" || die "недопустимое имя базы данных: ${database}"
    validate_database_name "${owner}" || die "недопустимое имя роли-владельца: ${owner}"
    runuser -u postgres -- "${home}/bin/createdb" --host="${socket_dir}" \
        --port="${port}" --owner="${owner}" -- "${database}" || die \
        "не удалось создать базу данных ${database}"
}

role_exists() {
    local home="$1" socket_dir="$2" port="$3" role="$4" escaped
    escaped="${role//\'/\'\'}"
    runuser -u postgres -- "${home}/bin/psql" -h "${socket_dir}" -p "${port}" \
        -d postgres -Atqc "SELECT 1 FROM pg_roles WHERE rolname='${escaped}'" | grep -qx 1
}

create_restore_admin_role() {
    local home="$1" socket_dir="$2" port="$3" role="$4" role_sql password_sql
    validate_database_name "${role}" || die "недопустимое имя роли из дампа: ${role}"
    role_sql="${role//\"/\"\"}"
    password_sql="${role//\'/\'\'}"
    printf 'Создание отсутствующей роли администратора %s...\n' "${role}"
    runuser -u postgres -- "${home}/bin/psql" -h "${socket_dir}" -p "${port}" \
        -d postgres -v ON_ERROR_STOP=1 \
        -c "CREATE ROLE \"${role_sql}\" WITH LOGIN PASSWORD '${password_sql}' SUPERUSER CREATEDB CREATEROLE REPLICATION VALID UNTIL 'infinity'" || die \
        "не удалось создать роль администратора ${role}"
}

dump_owner_roles() {
    local home="$1" dump_file="$2" line role
    while IFS= read -r line; do
        [[ -n "${line}" && "${line}" != \;* ]] || continue
        # У записей без владельца pg_restore оставляет пробел в конце строки.
        [[ ! "${line}" =~ [[:space:]]$ ]] || continue
        role="${line##* }"
        validate_database_name "${role}" || continue
        printf '%s\n' "${role}"
    done < <("${home}/bin/pg_restore" --list "${dump_file}")
}

ensure_restore_roles() {
    local home="$1" socket_dir="$2" port="$3" dump_file="$4"
    local role
    local -a roles=()
    RESTORE_ADMIN_ROLE=""
    mapfile -t roles < <(dump_owner_roles "${home}" "${dump_file}" | sort -u)
    for role in "${roles[@]}"; do
        [[ "${role}" == postgres || "${role}" == pg_* ]] && continue
        if [[ -z "${RESTORE_ADMIN_ROLE}" ]]; then
            RESTORE_ADMIN_ROLE="${role}"
        fi
        role_exists "${home}" "${socket_dir}" "${port}" "${role}" && continue
        create_restore_admin_role "${home}" "${socket_dir}" "${port}" "${role}"
    done
}

resolve_backup_file() {
    local requested="$1" candidate
    if [[ "${requested}" == /* ]]; then
        candidate="${requested}"
    elif [[ -f "${requested}" ]]; then
        candidate="${PWD}/${requested}"
    else
        candidate="${backup_dir%/}/${requested}"
    fi
    [[ -f "${candidate}" ]] || return 1
    readlink -f -- "${candidate}"
}

validate_hot_backup_archive_contents() {
    local archive="$1" dump_name="$2" entry dump_entries=0 metadata_entries=0
    local -a entries=()
    mapfile -t entries < <(tar -tzf "${archive}")
    for entry in "${entries[@]}"; do
        case "${entry}" in
            "${dump_name}") ((dump_entries += 1)) ;;
            backup-info.env) ((metadata_entries += 1)) ;;
            *) die "недопустимый файл в горячем архиве: ${entry}" ;;
        esac
    done
    ((dump_entries == 1)) || die "в горячем архиве должен находиться файл ${dump_name}"
    ((metadata_entries <= 1)) || die "в горячем архиве найдено несколько файлов backup-info.env"
}

replace_literal_in_file() {
    local old_text="$1" new_text="$2" file="$3"
    [[ -f "${file}" ]] || return 0
    OLD_TEXT="${old_text}" NEW_TEXT="${new_text}" perl -pi -e \
        's/\Q$ENV{OLD_TEXT}\E/$ENV{NEW_TEXT}/g' -- "${file}"
}

set_postgresql_setting() {
    local file="$1" setting="$2" value="$3"
    [[ -f "${file}" ]] || return 0
    if grep -Eq "^[[:space:]]*${setting}[[:space:]]*=" "${file}"; then
        sed -i -E "s#^[[:space:]]*${setting}[[:space:]]*=.*#${setting} = ${value}#" "${file}"
    fi
}

put_postgresql_setting() {
    local file="$1" setting="$2" value="$3"
    [[ -f "${file}" ]] || die "не найден файл настроек ${file}"
    if grep -Eq "^[[:space:]]*${setting}[[:space:]]*=" "${file}"; then
        sed -i -E "s#^[[:space:]]*${setting}[[:space:]]*=.*#${setting} = ${value}#" "${file}"
    else
        printf '\n%s = %s\n' "${setting}" "${value}" >>"${file}"
    fi
}

make_cold_backup() {
    local version="$1" name="$2" port="$3" status="$4" owner="$5" data="$6" log="$7"
    local restart_after="${8:-no}" was_online=no
    local home reset_tool unit_dir service archive timestamp meta_tmp rel cluster_package version_text
    local socket_dir metadata_started=no
    local -a paths=()
    prepare_backup_directory write
    timestamp="$(date +%Y%m%d-%H%M%S)"
    archive="${backup_dir}/$(backup_archive_name "${version}" "${name}" "${timestamp}")"
    home="$(cluster_pg_home "${version}" "${data}")"
    unit_dir="$(systemd_unit_dir)"
    service="postgresql@${version}-${name}.service"

    if [[ "${status}" != online* ]]; then
        printf 'Кластер %s/%s временно запускается для записи имён и размеров БД...\n' \
            "${version}" "${name}"
        start_cluster_checked "${version}" "${name}"
        metadata_started=yes
    fi
    socket_dir="$(cluster_socket_directory "${port}")" || {
        [[ "${metadata_started}" == yes ]] && stop_cluster_checked "${version}" "${name}"
        die "не найден Unix-сокет кластера ${version}/${name} для сбора метаданных"
    }
    if ! load_cluster_databases "${home}" "${socket_dir}" "${port}" all; then
        [[ "${metadata_started}" == yes ]] && stop_cluster_checked "${version}" "${name}"
        die "не удалось получить имена и размеры БД кластера ${version}/${name}"
    fi
    if [[ "${metadata_started}" == yes ]]; then
        stop_cluster_checked "${version}" "${name}"
    fi

    if [[ "${status}" == online* ]]; then
        was_online=yes
        stop_cluster_checked "${version}" "${name}"
    elif [[ "${metadata_started}" != yes ]]; then
        printf 'Кластер %s/%s уже остановлен.\n' "${version}" "${name}"
    fi
    if { ((NON_INTERACTIVE)) && [[ "${CLEAR_WAL}" == yes ]]; } || \
        { ((!NON_INTERACTIVE)) && confirm "Очистить WAL с помощью pg_resetwal/pg_resetxlog? Это аварийная операция" N; }; then
        reset_tool=""
        [[ -x "${home}/bin/pg_resetwal" ]] && reset_tool="${home}/bin/pg_resetwal"
        [[ -z "${reset_tool}" && -x "${home}/bin/pg_resetxlog" ]] && reset_tool="${home}/bin/pg_resetxlog"
        [[ -n "${reset_tool}" ]] || die "не найден pg_resetwal или pg_resetxlog"
        runuser -u postgres -- "${reset_tool}" -f "${data}" || die "не удалось очистить WAL"
    fi

    measure_data_directory "${data}"
    printf '\nРазмер каталога данных перед холодным бэкапом (du -sh):\n  %s\n' \
        "${DATA_DIRECTORY_DU_SH}"

    [[ -e "/etc/postgresql/${version}/${name}" ]] && paths+=("etc/postgresql/${version}/${name}")
    rel="${data#/}"; [[ -e "${data}" ]] && paths+=("${rel}")
    rel="${log#/}"; [[ -e "${log}" ]] && paths+=("${rel}")
    [[ -e "${unit_dir}/${service}" ]] && paths+=("${unit_dir#/}/${service}")
    ((${#paths[@]})) || die "нечего помещать в резервную копию"

    if [[ "${data}" == /var/lib/postgresql/tantor-free-* ]]; then
        cluster_package="tantor-free-server-${version}-server"
        package_installed "${cluster_package}" || cluster_package="tantor-free-server-${version}"
    elif [[ "${home}" == /opt/pgpro/* ]]; then
        cluster_package="postgrespro-ent-${version}-server"
    else
        cluster_package="postgresql-${version}-server"
    fi
    version_text="$("${home}/bin/postgres" --version)"
    CLEANUP_DIR="$(mktemp -d /tmp/create-claster.backup.XXXXXX)"
    meta_tmp="${CLEANUP_DIR}"
    {
        write_common_backup_metadata cold "${version}" "${name}" "${port}" "${version_text}"
        printf 'package=%q\n' "${cluster_package}"
        printf 'cluster_owner=%q\n' "${owner}"
        printf 'data_dir=%q\n' "${data}"
        printf 'data_directory_size_bytes=%q\n' "${DATA_DIRECTORY_SIZE_BYTES}"
        printf 'data_directory_size_pretty=%q\n' "${DATA_DIRECTORY_SIZE_PRETTY}"
        printf 'data_directory_du_sh=%q\n' "${DATA_DIRECTORY_DU_SH}"
        printf 'log_file=%q\n' "${log}"
        printf 'service_file=%q\n' "${unit_dir}/${service}"
        write_database_inventory_metadata
    } >"${meta_tmp}/backup-info.env"
    tar --dereference -czf "${archive}" --transform='s,^,root/,' -C / "${paths[@]}" \
        -C "${meta_tmp}" backup-info.env || die "не удалось создать резервную копию"
    rm -rf -- "${meta_tmp}"
    CLEANUP_DIR=""
    printf 'Холодная резервная копия создана: %s\n' "${archive}"
    if [[ "${restart_after}" == yes && "${was_online}" == yes ]]; then
        start_cluster_checked "${version}" "${name}"
        printf 'Кластер %s/%s снова запущен.\n' "${version}" "${name}"
    fi
}

make_hot_backup() {
    local version="$1" cluster="$2" port="$3" status="$4" data="$5" database="$6"
    local database_verified="${7:-no}"
    local home socket_dir timestamp archive dump_name stage version_text database_number database_index
    prepare_backup_directory write
    [[ "${status}" == online* ]] || die "для горячего бэкапа кластер ${version}/${cluster} должен быть запущен"
    validate_database_name "${database}" || die "недопустимое имя базы данных: ${database}"
    home="$(cluster_pg_home "${version}" "${data}")"
    [[ -x "${home}/bin/pg_dump" ]] || die "не найден ${home}/bin/pg_dump"
    socket_dir="$(cluster_socket_directory "${port}")" || die \
        "не найден Unix-сокет запущенного кластера ${version}/${cluster} на порту ${port}"
    if [[ "${database_verified}" != yes ]]; then
        database_exists "${home}" "${socket_dir}" "${port}" "${database}" || die \
            "база данных ${database} отсутствует в кластере ${version}/${cluster}"
    fi

    timestamp="$(date +%Y%m%d-%H%M%S)"
    archive="${backup_dir}/$(hot_backup_archive_name "${version}" "${database}" "${timestamp}")"
    dump_name="$(hot_backup_dump_name "${version}" "${database}" "${timestamp}")"
    CLEANUP_DIR="$(mktemp -d /tmp/create-claster.hot-backup.XXXXXX)"
    stage="${CLEANUP_DIR}"
    chown postgres:postgres "${stage}"
    printf 'Создание горячего дампа базы %s из кластера %s/%s...\n' \
        "${database}" "${version}" "${cluster}"
    runuser -u postgres -- "${home}/bin/pg_dump" --format=custom --verbose \
        --host="${socket_dir}" --port="${port}" --dbname="${database}" \
        --file="${stage}/${dump_name}" || die "не удалось создать горячий дамп базы ${database}"
    [[ -s "${stage}/${dump_name}" ]] || die "pg_dump создал пустой файл ${dump_name}"
    load_cluster_databases "${home}" "${socket_dir}" "${port}" || die \
        "не удалось получить размер базы данных ${database}"
    database_number="$(database_number_in_loaded_list "${database}")" || die \
        "база данных ${database} отсутствует после создания дампа"
    database_index=$((database_number - 1))
    version_text="$("${home}/bin/postgres" --version)"
    {
        write_common_backup_metadata hot "${version}" "${cluster}" "${port}" "${version_text}"
        write_hot_database_metadata "${database}" "${database_index}"
    } >"${stage}/backup-info.env"
    tar -czf "${archive}" -C "${stage}" "${dump_name}" backup-info.env || die \
        "не удалось упаковать горячий дамп"
    rm -rf -- "${stage}"
    CLEANUP_DIR=""
    printf 'Горячая резервная копия создана: %s\n' "${archive}"
    printf 'Файл дампа в архиве: %s\n' "${dump_name}"
    printf 'Метаданные в архиве: backup-info.env\n'
}

backup_menu() {
    local row version name port status owner data log choice database home socket_dir
    header
    step "Кластер: Бэкап"
    if ((NON_INTERACTIVE)); then
        choice="${BACKUP_TYPE}"
    else
        printf '%s\n' \
            '1 - Горячий бэкап базы данных' \
            '2 - Холодный бэкап кластера' \
            '0 - Вернуться назад'
        read -r -p "Выберите тип бэкапа [2]: " choice || return 0
        choice="${choice:-2}"
        case "${choice}" in
            1) choice=hot ;;
            2) choice=cold ;;
            0) return 0 ;;
            *) warn "неверный тип бэкапа"; pause; return 0 ;;
        esac
    fi
    select_cluster "Выберите кластер" || return 0
    row="${SELECTED_CLUSTER_ROW}"
    read -r version name port status owner data log <<<"${row}"
    printf '\nВыбран кластер %s/%s, данные: %s\n' "${version}" "${name}" "${data}"
    if [[ "${choice}" == hot ]]; then
        if [[ "${status}" != online* ]]; then
            if ((NON_INTERACTIVE)); then
                die "для горячего бэкапа кластер ${version}/${name} должен быть запущен"
            fi
            warn "для горячего бэкапа кластер ${version}/${name} должен быть запущен"
            pause
            return 0
        fi
        if ((NON_INTERACTIVE)); then
            ((TARGET_DATABASE_SET)) || die \
                "для горячего backup укажите --database или PGCC_DATABASE"
            database="${DATABASE_NAME}"
        else
            home="$(cluster_pg_home "${version}" "${data}")"
            socket_dir="$(cluster_socket_directory "${port}")" || {
                warn "не найден Unix-сокет кластера ${version}/${name} на порту ${port}"
                pause
                return 0
            }
            print_cluster_databases "${home}" "${socket_dir}" "${port}" "${version}" "${name}"
            ((${#CLUSTER_DATABASES[@]})) || { warn "в кластере нет доступных баз данных"; pause; return 0; }
            if ! database="$(database_number_in_loaded_list "${name}")"; then
                database=1
            fi
            select_existing_database "Выберите БД (номер из списка или точное имя)" \
                "${database}" || return 0
            database="${SELECTED_DATABASE}"
        fi
        if confirm "Создать горячий бэкап базы ${database}?" Y; then
            if ((NON_INTERACTIVE)); then
                make_hot_backup "${version}" "${name}" "${port}" "${status}" "${data}" "${database}"
            else
                make_hot_backup "${version}" "${name}" "${port}" "${status}" "${data}" "${database}" yes
            fi
        else
            warn "создание бэкапа отменено"
        fi
    elif confirm "Создать холодный бэкап выбранного кластера?" Y; then
        make_cold_backup "${version}" "${name}" "${port}" "${status}" "${owner}" "${data}" "${log}" yes
    else
        warn "создание бэкапа отменено"
    fi
    pause
}

delete_menu() {
    local row version name port status owner data log unit_dir service
    header
    step "Удаление: Выбор цели для удаления"
    select_cluster "Выберите кластер" || return 0
    row="${SELECTED_CLUSTER_ROW}"
    read -r version name port status owner data log <<<"${row}"
    printf '\nВыбран кластер %s/%s, данные: %s\n' "${version}" "${name}" "${data}"
    if ((NON_INTERACTIVE)) && [[ "${BACKUP_BEFORE_DELETE}" == yes ]]; then
        make_cold_backup "${version}" "${name}" "${port}" "${status}" "${owner}" "${data}" "${log}" no
    elif ((NON_INTERACTIVE)); then
        printf 'Удаление выполняется без резервной копии по заданным параметрам.\n'
    elif confirm "Сделать холодный бэкап перед удалением?" Y; then
        make_cold_backup "${version}" "${name}" "${port}" "${status}" "${owner}" "${data}" "${log}" no
    elif ! confirm "Удалить кластер БЕЗ резервной копии?" N; then
        warn "удаление отменено"
        pause
        return 0
    fi
    printf 'Удаляется только журнал выбранного кластера: %s\n' "${log}"
    printf 'Каталог /var/log/postgresql и журналы других кластеров сохраняются.\n'
    run_parsec_aware pg_dropcluster --stop "${version}" "${name}"
    unit_dir="$(systemd_unit_dir)"
    service="postgresql@${version}-${name}.service"
    systemctl disable "${service}" >/dev/null 2>&1 || true
    rm -f -- "${unit_dir}/${service}" "/.postgres/systemd/${service}" "/.postgres/systemd/save/${service}"
    systemctl daemon-reload
    printf 'Кластер %s/%s удалён.\n' "${version}" "${name}"
    pause
}

restore_hot_backup() {
    local archive="$1" filename source_version source_database timestamp dump_name
    local row version name port status owner data log home socket_dir target_database stage
    local create_target_database=no
    filename="${archive##*/}"
    if [[ "${filename}" =~ ^([0-9]+)-([A-Za-z0-9_][A-Za-z0-9_.-]*)-([0-9]{8})-([0-9]{6})-dmp\.tar\.gz$ ]]; then
        source_version="${BASH_REMATCH[1]}"
        source_database="${BASH_REMATCH[2]}"
        timestamp="${BASH_REMATCH[3]}-${BASH_REMATCH[4]}"
    else
        die "недопустимое имя горячего бэкапа: ${filename}"
    fi
    dump_name="$(hot_backup_dump_name "${source_version}" "${source_database}" "${timestamp}")"
    printf 'Горячий бэкап: PostgreSQL %s, база %s, файл %s\n' \
        "${source_version}" "${source_database}" "${dump_name}"

    select_cluster "Выберите целевой кластер" || return 0
    row="${SELECTED_CLUSTER_ROW}"
    read -r version name port status owner data log <<<"${row}"
    if [[ "${status}" != online* ]]; then
        if ((NON_INTERACTIVE)); then
            die "целевой кластер ${version}/${name} должен быть запущен"
        fi
        warn "целевой кластер ${version}/${name} должен быть запущен"
        pause
        return 0
    fi
    home="$(cluster_pg_home "${version}" "${data}")"
    [[ -x "${home}/bin/pg_restore" ]] || die "не найден ${home}/bin/pg_restore"
    socket_dir="$(cluster_socket_directory "${port}")" || die \
        "не найден Unix-сокет целевого кластера ${version}/${name} на порту ${port}"

    if ((NON_INTERACTIVE)); then
        ((TARGET_DATABASE_SET)) || die \
            "для горячего restore укажите --database или PGCC_DATABASE"
        target_database="${DATABASE_NAME}"
        validate_database_name "${target_database}" || die "недопустимое имя базы данных: ${target_database}"
        database_exists "${home}" "${socket_dir}" "${port}" "${target_database}" || \
            create_target_database=yes
    else
        print_cluster_databases "${home}" "${socket_dir}" "${port}" "${version}" "${name}"
        if ! target_database="$(database_number_in_loaded_list "${source_database}")"; then
            target_database="${source_database}"
        fi
        select_restore_database \
            "Выберите целевую БД (номер из списка либо имя существующей или новой БД)" \
            "${target_database}" || return 0
        target_database="${SELECTED_DATABASE}"
        if ! database_in_loaded_list "${target_database}"; then
            warn "база данных ${target_database} отсутствует в кластере ${version}/${name}; она будет создана"
            create_target_database=yes
        fi
    fi
    if [[ "${create_target_database}" == yes ]]; then
        printf 'Цель: кластер %s/%s, новая база %s, порт %s\n' \
            "${version}" "${name}" "${target_database}" "${port}"
    else
        printf 'Цель: кластер %s/%s, существующая база %s, порт %s\n' \
            "${version}" "${name}" "${target_database}" "${port}"
    fi
    if ((NON_INTERACTIVE)) && [[ "${create_target_database}" == no ]]; then
        [[ "${OVERWRITE_EXISTING}" == yes ]] || die \
            "для горячего restore поверх существующей БД задайте --overwrite yes или PGCC_OVERWRITE=yes"
    elif ((NON_INTERACTIVE)); then
        :
    elif [[ "${create_target_database}" == yes ]]; then
        confirm "Создать базу ${target_database} и восстановить горячий бэкап?" Y || return 0
    else
        confirm "Очистить существующие объекты и восстановить горячий бэкап?" N || return 0
    fi

    validate_hot_backup_archive_contents "${archive}" "${dump_name}"
    CLEANUP_DIR="$(mktemp -d /tmp/create-claster.hot-restore.XXXXXX)"
    stage="${CLEANUP_DIR}"
    tar -xzf "${archive}" -C "${stage}" -- "${dump_name}" || die "не удалось извлечь горячий дамп"
    [[ -f "${stage}/${dump_name}" && ! -L "${stage}/${dump_name}" ]] || die \
        "извлечённый дамп не является обычным файлом"
    chown -R postgres:postgres "${stage}"
    ensure_restore_roles "${home}" "${socket_dir}" "${port}" "${stage}/${dump_name}"
    if [[ "${create_target_database}" == yes ]]; then
        printf 'Создание базы данных %s в кластере %s/%s...\n' \
            "${target_database}" "${version}" "${name}"
        create_database "${home}" "${socket_dir}" "${port}" "${target_database}" \
            "${RESTORE_ADMIN_ROLE:-postgres}"
    fi
    printf 'Восстановление базы %s в кластере %s/%s...\n' \
        "${target_database}" "${version}" "${name}"
    if [[ "${create_target_database}" == yes ]]; then
        runuser -u postgres -- "${home}/bin/pg_restore" --verbose --exit-on-error \
            --host="${socket_dir}" --port="${port}" --dbname="${target_database}" \
            "${stage}/${dump_name}" || die \
            "не удалось восстановить горячий бэкап в базу ${target_database}"
    else
        runuser -u postgres -- "${home}/bin/pg_restore" --verbose --exit-on-error \
            --clean --if-exists --host="${socket_dir}" --port="${port}" \
            --dbname="${target_database}" "${stage}/${dump_name}" || die \
            "не удалось восстановить горячий бэкап в базу ${target_database}"
    fi
    rm -rf -- "${stage}"
    CLEANUP_DIR=""
    printf 'Горячий бэкап восстановлен в %s/%s, база %s.\n' \
        "${version}" "${name}" "${target_database}"
    pause
}

restore_menu() {
    local choice archive stage info service_file version name package entry
    local cluster_name cluster_port pg_version data_dir log_file
    local original_name original_port original_data_dir original_conf_dir
    local restore_name restore_port restore_data_dir restore_conf_dir restore_service_file file
    local -a backups=()
    local -a transform_args=()
    header
    step "Кластер: Рестори"
    prepare_backup_directory read
    if ((NON_INTERACTIVE)); then
        [[ -n "${BACKUP_FILE}" ]] || die \
            "для restore укажите --backup-file или PGCC_BACKUP_FILE"
        archive="$(resolve_backup_file "${BACKUP_FILE}")" || die \
            "резервная копия не найдена: ${BACKUP_FILE} (проверены текущий каталог и ${backup_dir})"
        backup_filename_supported "${archive}" || die "неподдерживаемое имя файла бэкапа: ${archive##*/}"
    else
        mapfile -t backups < <(list_supported_backup_files | sort -r)
        if ((${#backups[@]} == 0)); then
            warn "в ${backup_dir} нет резервных копий"
            pause
            return 0
        fi
        local i
        for i in "${!backups[@]}"; do printf '%3d - %s\n' "$((i + 1))" "${backups[i]}"; done
        printf '  0 - Вернуться назад\n'
        read -r -p "Выберите резервную копию: " choice || return 0
        [[ "${choice}" =~ ^[0-9]+$ ]] || return 0
        ((choice == 0)) && return 0
        ((choice >= 1 && choice <= ${#backups[@]})) || return 0
        archive="${backup_dir}/${backups[choice-1]}"
    fi
    if [[ "${archive##*/}" == *-dmp.tar.gz ]]; then
        restore_hot_backup "${archive}"
        return 0
    fi
    info="$(tar -xOzf "${archive}" root/backup-info.env 2>/dev/null)" || die "в архиве нет метаданных"
    CLEANUP_DIR="$(mktemp -d /tmp/create-claster.restore.XXXXXX)"
    stage="${CLEANUP_DIR}"
    printf '%s\n' "${info}" >"${stage}/backup-info.env"
    # shellcheck source=/dev/null
    source "${stage}/backup-info.env"
    version="${pg_version:?}"
    original_name="${cluster_name:?}"
    original_port="${cluster_port:?}"
    original_data_dir="${data_dir:?}"
    package="${package:?}"
    original_conf_dir="/etc/postgresql/${version}/${original_name}"
    validate_identifier "${original_name}" || die "в метаданных бэкапа недопустимое имя кластера"
    [[ "${original_data_dir}" == */"${original_name}" ]] || die "каталог данных в бэкапе не соответствует имени кластера"

    printf 'Бэкап: PostgreSQL %s, кластер %s, порт %s, пакет %s\n' \
        "${version}" "${original_name}" "${original_port}" "${package}"
    if ((NON_INTERACTIVE)); then
        if ((TARGET_NAME_SET)); then restore_name="${cls_nm}"; else restore_name="${original_name}"; fi
        if ((TARGET_PORT_SET)); then restore_port="${cls_pt}"; else restore_port="${original_port}"; fi
        validate_identifier "${restore_name}" || die "недопустимое имя кластера: ${restore_name}"
        [[ "${restore_port}" =~ ^[0-9]+$ ]] && ((restore_port >= 1 && restore_port <= 65535)) || \
            die "порт должен быть числом от 1 до 65535"
        port_in_use_by_other_cluster "${restore_port}" "${version}" "${restore_name}" && \
            die "порт ${restore_port} уже назначен другому кластеру"
    else
        while true; do
            restore_name="$(prompt_value "Имя восстанавливаемого кластера" "${original_name}")" || return 0
            validate_identifier "${restore_name}" || {
                warn "используйте строчные латинские буквы, цифры и подчёркивание"
                continue
            }
            break
        done
        while true; do
            restore_port="$(prompt_value "Порт восстанавливаемого кластера" "${original_port}")" || return 0
            [[ "${restore_port}" =~ ^[0-9]+$ ]] && ((restore_port >= 1 && restore_port <= 65535)) || {
                warn "порт должен быть числом от 1 до 65535"
                continue
            }
            if port_in_use_by_other_cluster "${restore_port}" "${version}" "${restore_name}"; then
                warn "порт ${restore_port} уже назначен другому кластеру"
                continue
            fi
            break
        done
    fi
    name="${restore_name}"
    restore_data_dir="${original_data_dir%/${original_name}}/${restore_name}"
    restore_conf_dir="/etc/postgresql/${version}/${restore_name}"
    printf 'Цель: PostgreSQL %s, кластер %s, порт %s\n' "${version}" "${restore_name}" "${restore_port}"

    if cluster_exists "${version}" "${restore_name}"; then
        warn "кластер ${version}/${restore_name} уже существует"
        if ((NON_INTERACTIVE)); then
            [[ "${OVERWRITE_EXISTING}" == yes ]] || die \
                "для перезаписи существующего кластера задайте --overwrite yes или PGCC_OVERWRITE=yes"
        else
            confirm "Остановить его и перезаписать файлы из бэкапа?" N || return 0
        fi
        stop_cluster_checked "${version}" "${restore_name}"
    elif ((!NON_INTERACTIVE)); then
        confirm "Восстановить кластер с указанными именем и портом?" Y || return 0
    fi
    server_package_installed "${package}" || install_package "${package}"
    SELECTED_PACKAGE="${package}"
    configure_selected_package
    stop_disable_vendor_service "${SELECTED_PACKAGE}"
    prepare_postgres_root
    while IFS= read -r entry; do
        [[ "${entry}" == root/* ]] || die "недопустимый путь в архиве: ${entry}"
        [[ "${entry}" != *'/../'* && "${entry}" != *'/..' && "${entry}" != root/.. ]] || \
            die "выход за корень в пути архива: ${entry}"
    done < <(tar -tzf "${archive}")
    if [[ "${restore_name}" != "${original_name}" ]]; then
        transform_args+=(--transform "s#/${original_name}/#/${restore_name}/#g")
        transform_args+=(--transform "s#/${original_name}\$#/${restore_name}#")
        transform_args+=(--transform "s#-${original_name}\\.service\$#-${restore_name}.service#")
        transform_args+=(--transform "s#-${original_name}\\.log\$#-${restore_name}.log#")
    fi
    tar "${transform_args[@]}" --keep-directory-symlink -xzf "${archive}" -C / --strip-components=1 \
        --exclude='root/backup-info.env'

    while IFS= read -r -d '' file; do
        replace_literal_in_file "${original_data_dir}" "${restore_data_dir}" "${file}"
        replace_literal_in_file "${original_conf_dir}" "${restore_conf_dir}" "${file}"
    done < <(find "${restore_conf_dir}" -type f -print0)
    mkdir -p "${restore_conf_dir}/conf.d"
    printf "cluster_name = '%s'\n" "${restore_name}" >"${restore_conf_dir}/conf.d/cluster_name.conf"
    cat >"${restore_conf_dir}/conf.d/listen_port.conf" <<EOF
unix_socket_directories = '/tmp'
listen_addresses = '*'
port = ${restore_port}
EOF
    set_postgresql_setting "${restore_data_dir}/postgresql.auto.conf" port "${restore_port}"
    set_postgresql_setting "${restore_data_dir}/postgresql.auto.conf" cluster_name "'${restore_name}'"
    set_postgresql_setting "${restore_conf_dir}/postgresql.conf" port "${restore_port}"
    set_postgresql_setting "${restore_conf_dir}/postgresql.conf" cluster_name "'${version}/${restore_name}'"
    put_postgresql_setting "${restore_conf_dir}/postgresql.conf" external_pid_file \
        "'/run/postgresql/${version}-${restore_name}.pid'"

    service_file="${service_file:-$(systemd_unit_dir)/postgresql@${version}-${original_name}.service}"
    restore_service_file="$(dirname -- "${service_file}")/postgresql@${version}-${restore_name}.service"
    replace_literal_in_file "${original_data_dir}" "${restore_data_dir}" "${restore_service_file}"
    replace_literal_in_file "${original_conf_dir}" "${restore_conf_dir}" "${restore_service_file}"
    replace_literal_in_file "${version}-${original_name}" "${version}-${restore_name}" "${restore_service_file}"
    cp -f -- "${restore_service_file}" "/.postgres/systemd/save/$(basename -- "${restore_service_file}")"
    ensure_symlink "${restore_service_file}" "/.postgres/systemd/$(basename -- "${restore_service_file}")"
    systemctl daemon-reload
    systemctl enable "$(basename -- "${restore_service_file}")"
    start_cluster_checked "${version}" "${restore_name}"
    cls_nm="${restore_name}"
    cls_pt="${restore_port}"
    save_config
    rm -rf -- "${stage}"
    CLEANUP_DIR=""
    printf 'Кластер %s/%s восстановлен на порту %s и запущен.\n' \
        "${version}" "${restore_name}" "${restore_port}"
    pause
}

info_menu() {
    header
    step "Информация: о развернутых кластерах"
    pg_lsclusters || true
    ((NON_INTERACTIVE)) && return 0
    printf '\n0 - Вернуться назад\n'
    read -r -p "Выбор: " _ || true
}

main_menu() {
    local choice
    while true; do
        header
        step "Выбор действия"
        printf '%s\n' \
            '0 - Выход' \
            '1 - Информация: о развернутых кластерах' \
            '2 - Кластер: Установить' \
            '3 - Кластер: Бэкап' \
            '4 - Кластер: Рестори' \
            '5 - Кластер: Удалить'
        read -r -p "Выбор: " choice || exit 0
        case "${choice}" in
            0) exit 0 ;;
            1) info_menu ;;
            2) install_menu ;;
            3) backup_menu ;;
            4) restore_menu ;;
            5) delete_menu ;;
            *) clear 2>/dev/null || true; exit 0 ;;
        esac
    done
}

main() {
    parse_args "$@"
    if ((SHOW_HELP)); then
        usage
        exit 0
    fi
    if ((SHOW_VERSION)); then
        version
        exit 0
    fi
    require_root "$@"
    load_config
    apply_runtime_options
    if ((!NON_INTERACTIVE)); then
        header
        step "Подготовка пакетов"
    fi
    command -v apt-get >/dev/null 2>&1 || die "поддерживается система пакетов APT"
    ensure_postgresql_common
    if [[ "${ACTION}" == info && "${NON_INTERACTIVE}" == 1 ]]; then
        command -v pg_lsclusters >/dev/null 2>&1 || die "не найдена команда pg_lsclusters"
        info_menu
        return 0
    fi
    if [[ "${ACTION}" != restore || "${NON_INTERACTIVE}" == 0 ]]; then
        select_or_install_server
        prepare_postgres_root
    fi
    if ((NON_INTERACTIVE)); then
        case "${ACTION}" in
            info) info_menu ;;
            install) install_menu ;;
            backup) backup_menu ;;
            restore) restore_menu ;;
            delete) delete_menu ;;
        esac
    else
        main_menu
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
