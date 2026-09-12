#!/usr/bin/env bash

# ==============================================================================
# Script: create-claster-deb.sh
# Author: Andrei Lesnykh (AO NIKIET) <lesnyx@ya.ru>
#
# Purpose:
#   Build installable Debian packages for create-claster.sh. For every build,
#   the script creates a fresh root filesystem skeleton below tmp, populates it,
#   and removes it on exit. A tmp parent created by this run is removed only if
#   it is empty. Completed packages are written to dist unless another output
#   directory is requested. With no --mode argument, the script opens an
#   interactive mode selection menu. Modes 2-4 generate an idempotent postinst
#   deployment procedure; --mode 1 performs a direct scripts-only package build.
#   Control and data archives always use gzip for older Astra Linux dpkg readers.
#   Interactive steps clear the terminal; invalid input goes back one step.
#   Submenus offer 0 (back); invalid main-menu input and EOF exit without building.
#   After an interactive build is confirmed, create-claster-deb-last.sh is written
#   next to this builder, or below ~/tmp when the script directory is not writable.
#   The executable helper repeats the validated build without prompts.
#   Completion markers are accepted only while the target cluster is actually
#   registered; stale markers are cleared automatically before redeployment.
#   Forced redeployment delegates deletion to create-claster.sh, which validates
#   a stopped cluster and removes exact paths without pg_dropcluster/syslog reload.
#   Every package installs this builder below /usr/local/share/pg_claster_creator
#   but intentionally does not create a command symlink for it in /usr/local/bin.
#   All modes require the explicitly selected validation journal beside the builder
#   and install it into the same share directory with mode 0644. Missing release
#   evidence aborts the build. The 2.1.2 journal is historical; it does not
#   validate the new 2.4.3 features. See TEST.md for the current test scope.
#
# Package modes accepted by --mode:
#   1  Install scripts, configuration, documentation, and the command symlink.
#   2  Install the files and create an empty PostgreSQL cluster.
#   3  Install the files and restore a cluster from an embedded cold backup.
#   4  Install the files, create a cluster, and restore an embedded hot DB dump.
#
# Command-line options:
#   -h, --help                 Print detailed usage information.
#   -v, --version              Print the builder version.
#   -m, --mode MODE            Select package mode 1, 2, 3, or 4.
#       --pg-family FAMILY     postgresql, postgrespro-ent, tantor-free, tantor-se, tantor-be.
#       --pg-version VERSION   Set the PostgreSQL major version.
#       --cluster-name NAME    Set the target cluster name.
#       --port PORT            Set the target cluster TCP port.
#       --package PACKAGE      Set an exact PostgreSQL server package dependency.
#       --schema NAME          Set the schema and owner role for a new cluster.
#       --user NAME            Set the application login role for a new cluster.
#       --password PASSWORD    Set the password stored in the deployment plan.
#       --data-root DIRECTORY  Set a custom data root, for example /DATA.
#       --backup-file FILE     Select a cold (mode 3) or hot (mode 4) backup.
#       --backup-dir DIRECTORY Select the directory used by backup selection.
#       --database NAME        Set the target database name for mode 4.
#       --depends PACKAGES     Add comma-separated package dependencies; automatic
#                              Postgres Pro drops covered server dependencies.
#       --output-dir DIRECTORY Set the destination directory for the DEB file.
#   -i, --interactive          Explicitly enable the mode 2-4 configuration dialog.
#   -n, --non-interactive      Disable prompts and require complete arguments.
#   -f, --force                Allow replacement of an existing output package.
#
# Arguments and interactive defaults:
#   Positional arguments are not accepted. PostgreSQL, cluster, role, password,
#   and backup-directory defaults are loaded first from
#   /usr/local/shared/pg_claster_creator/.new-claster.config, otherwise from
#   .new-claster.config beside the resolved script. In modes
#   3 and 4, the interactive dialog lists backups by number, detects hot/cold
#   type, shows the aligned archive size obtained via stat without opening the
#   archive, reads backup-info.env without executing it, and lets the operator
#   confirm or change supported target values before the package is created.
#   In mode 4, an implicit postgrespro-ent package treats --pg-version as the
#   minimum target major. The generated contrib alternatives prefer PostgreSQL
#   Pro 18, then 17, down to that minimum; contrib pulls the matching server.
#   An explicit --package keeps exact behavior.
#
# Package-install environment:
#   CLASTER_FORCE_INSTALL=1     Remove an existing target cluster without a
#                               backup, then execute the complete mode 2-4 plan.
#   CLASTER_FORCE_DB_INSTALL=1  Mode 4 only: keep the existing cluster and
#                               overwrite the target DB from the hot dump.
#   The two force flags are mutually exclusive. Mode 3 cold restores support
#   only CLASTER_FORCE_INSTALL.
#
# Output and dependencies:
#   Every package depends on postgresql-common. A cold-backup package depends on
#   the exact server package recorded in its metadata. Automatic PostgreSQL Pro
#   hot-backup mode uses ordered contrib alternatives, each of which pulls its
#   matching server; redundant covered server entries are omitted from --depends.
# ==============================================================================

set -Eeuo pipefail

readonly SCRIPT_NAME="create-claster-deb.sh"
readonly SCRIPT_VERSION="2.4.3"
# Bump this only when a new functional validation journal is available.
readonly TEST_JOURNAL_VERSION="2.1.2"
readonly TEST_JOURNAL_NAME="TEST-${TEST_JOURNAL_VERSION}-journal-passed.md"
readonly SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd -P)"
readonly INSTALLED_CONFIG_FILE="/usr/local/shared/pg_claster_creator/.new-claster.config"
CONFIG_FILE="${SCRIPT_DIR}/.new-claster.config"
# Use the same configuration priority as the cluster and backup commands.
if [[ -e "${INSTALLED_CONFIG_FILE}" || -L "${INSTALLED_CONFIG_FILE}" ]]; then
    CONFIG_FILE="${INSTALLED_CONFIG_FILE}"
fi
readonly CONFIG_FILE
readonly TMP_DIR="${SCRIPT_DIR}/tmp"
readonly INSTALL_DIR="/usr/local/share/pg_claster_creator"
readonly COMMAND_LINK="/usr/local/bin/create-claster.sh"
readonly BACKUP_COMMAND_LINK="/usr/local/bin/create-claster-backup.sh"
readonly POSTGRESPRO_MAX_AUTO_VERSION=18

MODE=""
OUTPUT_DIR="${SCRIPT_DIR}/dist"
BACKUP_FILE=""
BACKUP_DIR=""
SERVER_PACKAGE=""
DATA_ROOT=""
DATABASE_NAME=""
EXTRA_DEPENDENCIES_INPUT=""
INTERACTIVE_MODE="yes"
MOVE_AFTER_RESTORE="no"
PREFER_NEWEST_SERVER="no"
FORCE_BUILD=0
BUILD_WORK_DIR=""
TMP_DIR_CREATED=0
BUILD_ROOT=""
LAST_COMMAND_TMP=""
META_TEXT=""
META_BACKUP_TYPE=""
META_PG_FAMILY=""
META_PG_VERSION=""
META_CLUSTER_NAME=""
META_CLUSTER_PORT=""
META_PACKAGE=""
META_DATA_DIR=""
META_DATABASE_NAME=""

PG_FAMILY_SET=0
PG_VERSION_SET=0
CLUSTER_NAME_SET=0
CLUSTER_PORT_SET=0
PACKAGE_SET=0
SCHEMA_SET=0
USER_SET=0
PASSWORD_SET=0
DATA_ROOT_SET=0
DATABASE_SET=0
declare -a EXTRA_DEPENDENCIES=()

pg="postgresql"
pg_ver="16"
cls_pt="5432"
cls_nm="subsys"
cls_ch="subsys"
cls_us="subsys"
cls_pw="subsys"

usage() {
    cat <<EOF
Использование:
  ${SCRIPT_NAME} [КЛЮЧИ]

Без --mode открывается интерактивный выбор режима сборки.
Для прямой сборки пакета со сценариями используется --mode 1.
В подменю 0 — назад; неверный ввод возвращает на предыдущий шаг.
В главном меню 0 или неверный ввод — выход. Enter принимает показанный вариант.

Режимы:
  1  Установить сценарии
  2  Установить сценарии и создать пустой кластер
  3  Установить сценарии и восстановить кластер из холодного бэкапа
  4  Установить сценарии, создать кластер и восстановить горячий бэкап БД

Ключи:
  -h, --help                  Показать эту справку и выйти
  -v, --version               Показать версию и выйти
  -m, --mode РЕЖИМ            Явно выбрать режим сборки 1|2|3|4
      --pg-family СЕМЕЙСТВО   postgresql|postgrespro-ent|tantor-free|tantor-se|tantor-be
      --pg-version ВЕРСИЯ     Основная версия PostgreSQL; минимум для
                              postgrespro-ent в режиме 4 без --package
      --cluster-name ИМЯ      Имя создаваемого/восстанавливаемого кластера
      --port ПОРТ             TCP-порт кластера
      --package ПАКЕТ         Точный серверный пакет; по умолчанию вычисляется
      --schema ИМЯ            Схема и роль-владелец при создании кластера
      --user ИМЯ              Прикладной пользователь при создании кластера
      --password ПАРОЛЬ       Пароль создаваемых ролей
      --data-root КАТАЛОГ     Пользовательский корень данных, например /DATA
      --backup-file ФАЙЛ      Холодный бэкап для режима 3 или горячий для режима 4
      --backup-dir КАТАЛОГ    Каталог выбора бэкапов; по умолчанию из конфига
      --database ИМЯ          Целевая БД для режима 4
      --depends ПАКЕТЫ        Дополнительные зависимости через запятую;
                              ключ можно указывать несколько раз (режимы 2–4);
                              server, покрытый автоальтернативой contrib, исключается
      --output-dir КАТАЛОГ    Каталог результата; по умолчанию ${SCRIPT_DIR}/dist
  -i, --interactive           Явно включить диалог режимов 2–4
  -n, --non-interactive       Отключить диалог и требовать параметры в ключах
  -f, --force                 Разрешить замену уже существующего файла пакета

Для всех режимов требуется ${TEST_JOURNAL_NAME} рядом со сборщиком;
он устанавливается в ${INSTALL_DIR}/ с правами 0644.

Значения по умолчанию для PostgreSQL и кластера читаются из
${CONFIG_FILE}.
Приоритет: /usr/local/shared/pg_claster_creator/.new-claster.config;
при отсутствии — .new-claster.config рядом с разрешённым сценарием.
Без --mode сначала выводится интерактивный список режимов. В режимах 2–4
диалог включён по умолчанию. Для автоматизации используется --non-interactive.
В диалоге выбирается бэкап, рядом с типом показывается выровненный размер
файла, затем выводятся его метаданные и уточняются параметры целевого кластера,
БД и размещения данных. Для построения списка архивы не распаковываются.

Для режима 4 с семейством postgrespro-ent и без явного --package значение
--pg-version является минимальной версией сервера. В Depends записываются
альтернативы contrib от PostgreSQL Pro 18 до указанной версии, новые раньше
старых; каждый contrib устанавливает сервер той же версии. Соответствующие
postgrespro-ent-*-server из --depends исключаются как избыточные.
Если подходящий полный комплект уже установлен, он сохраняется. Явный --package
отключает автоматический выбор и фиксирует точный пакет.
Для холодного бэкапа режима 3 всегда записывается только точный серверный пакет
из метаданных архива: физический бэкап нельзя переносить на другую основную
версию PostgreSQL.

Имена результатов:
  claster-creator-${SCRIPT_VERSION}.deb
  claster-creator-${SCRIPT_VERSION}-<pg>-<версия>-<кластер>-empty.deb
  claster-creator-${SCRIPT_VERSION}-<pg>-<версия>-<кластер>-full.deb
  claster-creator-${SCRIPT_VERSION}-<pg>-<версия>-<кластер>-<БД>.deb

Примеры:
  ./${SCRIPT_NAME}                         # интерактивный выбор режима
  ./${SCRIPT_NAME} --mode 1                # прямой пакет только со сценариями
  ./${SCRIPT_NAME} --mode 2 --pg-family postgrespro-ent --pg-version 16 --cluster-name subsys --port 5432
  ./${SCRIPT_NAME} --mode 2 --non-interactive --cluster-name subsys --depends postgis,pgbouncer
  ./${SCRIPT_NAME} --mode 3 --interactive
  ./${SCRIPT_NAME} --mode 3 --pg-family postgrespro-ent --pg-version 16 --cluster-name subsys --port 5432 --backup-file /.postgres/backup/16-subsys-20260905-085245.tar.gz
  ./${SCRIPT_NAME} --mode 4 --pg-family postgrespro-ent --pg-version 16 --cluster-name subsys --database asvd --backup-file /.postgres/backup/16-asvd-20260905-105802-dmp.tar.gz

Устанавливать результат рекомендуется через apt:
  apt install ./dist/ИМЯ_ПАКЕТА.deb

Именно apt разрешает альтернативы и загружает отсутствующие зависимости.
Один dpkg -i не скачивает серверные пакеты; после него потребовался бы apt -f install.

После подтверждённой интерактивной сборки рядом со сборщиком создаётся
исполняемый create-claster-deb-last.sh с правами 0755. Если каталог сборщика
недоступен для записи, используется ~/tmp/create-claster-deb-last.sh, а каталог
~/tmp при необходимости создаётся. Файл повторяет сборку без интерактива и с
заменой прежнего результата. Ключ --non-interactive отключает его создание и
изменение.

Переменные для принудительной установки готового пакета:
  CLASTER_FORCE_INSTALL=1     Удалить существующий кластер без бэкапа и
                              выполнить полный план режимов 2, 3 или 4
  CLASTER_FORCE_DB_INSTALL=1  Только режим 4: сохранить кластер и заново
                              восстановить целевую БД из горячего дампа

Флаги взаимоисключающие. Для холодного бэкапа режима 3 поддерживается только
CLASTER_FORCE_INSTALL. Пример:
  CLASTER_FORCE_INSTALL=1 dpkg -i ./dist/ИМЯ_ПАКЕТА.deb
  CLASTER_FORCE_DB_INSTALL=1 dpkg -i ./dist/ИМЯ_ПАКЕТА.deb

Маркеры завершения в /var/lib/claster-creator учитываются только при фактическом
наличии целевого кластера. Если кластер удалён, устаревшие маркеры автоматически
сбрасываются и postinst повторяет план развёртывания.
EOF
}

version() {
    printf '%s, версия %s\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
}

die() {
    printf 'ОШИБКА: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "${BUILD_WORK_DIR}" && -n "${TMP_DIR}" && \
          "${BUILD_WORK_DIR}" == "${TMP_DIR}/create-claster-deb."* ]]; then
        rm -rf -- "${BUILD_WORK_DIR}"
    fi
    # Never recursively remove the shared parent or a directory owned by another run.
    if ((TMP_DIR_CREATED)) && [[ -d "${TMP_DIR}" && ! -L "${TMP_DIR}" ]]; then
        rmdir -- "${TMP_DIR}" 2>/dev/null || true
    fi
    if [[ -n "${LAST_COMMAND_TMP}" ]]; then
        case "${LAST_COMMAND_TMP}" in
            "${SCRIPT_DIR}/.create-claster-deb-last."*) rm -f -- "${LAST_COMMAND_TMP}" ;;
            "${HOME:-/nonexistent}/tmp/.create-claster-deb-last."*) rm -f -- "${LAST_COMMAND_TMP}" ;;
        esac
    fi
}

trap cleanup EXIT

option_value_required() {
    (($# >= 2)) && [[ -n "$2" ]] || die "для ключа $1 требуется значение"
}

load_defaults() {
    [[ -r "${CONFIG_FILE}" ]] || die "не найден конфиг ${CONFIG_FILE}"
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
    BACKUP_DIR="${backup_dir:-/.postgres/backup}"
}

handle_early_options() {
    (($# == 1)) || return 0
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -v|--version) version; exit 0 ;;
    esac
}

parse_args() {
    while (($#)); do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -v|--version) version; exit 0 ;;
            -m|--mode) option_value_required "$@"; MODE="$2"; shift 2 ;;
            --mode=*) MODE="${1#*=}"; shift ;;
            --pg-family) option_value_required "$@"; pg="$2"; PG_FAMILY_SET=1; shift 2 ;;
            --pg-family=*) pg="${1#*=}"; PG_FAMILY_SET=1; shift ;;
            --pg-version) option_value_required "$@"; pg_ver="$2"; PG_VERSION_SET=1; shift 2 ;;
            --pg-version=*) pg_ver="${1#*=}"; PG_VERSION_SET=1; shift ;;
            --cluster-name) option_value_required "$@"; cls_nm="$2"; CLUSTER_NAME_SET=1; shift 2 ;;
            --cluster-name=*) cls_nm="${1#*=}"; CLUSTER_NAME_SET=1; shift ;;
            --port) option_value_required "$@"; cls_pt="$2"; CLUSTER_PORT_SET=1; shift 2 ;;
            --port=*) cls_pt="${1#*=}"; CLUSTER_PORT_SET=1; shift ;;
            --package) option_value_required "$@"; SERVER_PACKAGE="$2"; PACKAGE_SET=1; shift 2 ;;
            --package=*) SERVER_PACKAGE="${1#*=}"; PACKAGE_SET=1; shift ;;
            --schema) option_value_required "$@"; cls_ch="$2"; SCHEMA_SET=1; shift 2 ;;
            --schema=*) cls_ch="${1#*=}"; SCHEMA_SET=1; shift ;;
            --user) option_value_required "$@"; cls_us="$2"; USER_SET=1; shift 2 ;;
            --user=*) cls_us="${1#*=}"; USER_SET=1; shift ;;
            --password) option_value_required "$@"; cls_pw="$2"; PASSWORD_SET=1; shift 2 ;;
            --password=*) cls_pw="${1#*=}"; PASSWORD_SET=1; shift ;;
            --data-root) option_value_required "$@"; DATA_ROOT="$2"; DATA_ROOT_SET=1; shift 2 ;;
            --data-root=*) DATA_ROOT="${1#*=}"; DATA_ROOT_SET=1; shift ;;
            --backup-file) option_value_required "$@"; BACKUP_FILE="$2"; shift 2 ;;
            --backup-file=*) BACKUP_FILE="${1#*=}"; shift ;;
            --backup-dir) option_value_required "$@"; BACKUP_DIR="$2"; shift 2 ;;
            --backup-dir=*) BACKUP_DIR="${1#*=}"; shift ;;
            --database) option_value_required "$@"; DATABASE_NAME="$2"; DATABASE_SET=1; shift 2 ;;
            --database=*) DATABASE_NAME="${1#*=}"; DATABASE_SET=1; shift ;;
            --depends)
                option_value_required "$@"
                EXTRA_DEPENDENCIES_INPUT+="${EXTRA_DEPENDENCIES_INPUT:+,}$2"
                shift 2
                ;;
            --depends=*)
                EXTRA_DEPENDENCIES_INPUT+="${EXTRA_DEPENDENCIES_INPUT:+,}${1#*=}"
                shift
                ;;
            --output-dir) option_value_required "$@"; OUTPUT_DIR="$2"; shift 2 ;;
            --output-dir=*) OUTPUT_DIR="${1#*=}"; shift ;;
            -i|--interactive) INTERACTIVE_MODE=yes; shift ;;
            -n|--non-interactive) INTERACTIVE_MODE=no; shift ;;
            -f|--force) FORCE_BUILD=1; shift ;;
            --) shift; (($# == 0)) || die "позиционные аргументы не поддерживаются" ;;
            -*) die "неизвестный ключ: $1 (используйте --help)" ;;
            *) die "неожиданный аргумент: $1 (используйте --help)" ;;
        esac
    done
}

validate_identifier() {
    [[ "$1" =~ ^[a-z][a-z0-9_]*$ ]]
}

validate_database_name() {
    [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]]
}

warn() {
    printf 'ПРЕДУПРЕЖДЕНИЕ: %s\n' "$*" >&2
}

prompt_value() {
    local label="$1" current="$2" value
    read -r -p "${label} [${current}]: " value || return 2
    printf '%s' "${value:-${current}}"
}

confirm() {
    local prompt="$1" answer
    read -r -p "${prompt} [Y/n]: " answer || return 2
    case "${answer,,}" in
        ''|y|yes|д|да) return 0 ;;
        *) return 1 ;;
    esac
}

backup_kind() {
    case "${1##*/}" in
        *-dmp.tar.gz) printf 'hot' ;;
        *.tar.gz) printf 'cold' ;;
        *) return 1 ;;
    esac
}

backup_kind_label() {
    case "$1" in
        hot) printf 'горячий' ;;
        cold) printf 'холодный' ;;
    esac
}

backup_file_size_label() {
    local backup_file="$1" bytes
    bytes="$(stat -Lc '%s' -- "${backup_file}" 2>/dev/null)" || return 1
    [[ "${bytes}" =~ ^[0-9]+$ ]] || return 1
    env LC_ALL=C awk -v bytes="${bytes}" 'BEGIN {
        split("Kb Mb Gb Tb Pb Eb", units, " ")
        value = bytes / 1024
        unit = 1
        while (unit < 6 && value >= 999.995) {
            value /= 1024
            unit++
        }
        printf "%.2f %s", value, units[unit]
    }'
}

backup_filename_supported() {
    [[ "${1##*/}" =~ ^[0-9]+-[A-Za-z0-9_][A-Za-z0-9_.-]*-[0-9]{8}-[0-9]{6}(-dmp)?\.tar\.gz$ ]]
}

resolve_backup_file() {
    local requested="$1" candidate
    if [[ "${requested}" == /* ]]; then
        candidate="${requested}"
    elif [[ -f "${requested}" ]]; then
        candidate="${requested}"
    else
        candidate="${BACKUP_DIR%/}/${requested}"
    fi
    realpath -e -- "${candidate}" 2>/dev/null
}

select_backup_interactive() {
    local required_kind="$1" selected kind kind_label size_label choice i
    local -a backups=()
    if [[ -n "${BACKUP_FILE}" ]]; then
        BACKUP_FILE="$(resolve_backup_file "${BACKUP_FILE}")" || {
            warn "бэкап не найден: ${BACKUP_FILE}"
            return 1
        }
        backup_filename_supported "${BACKUP_FILE}" || {
            warn "неподдерживаемое имя бэкапа: ${BACKUP_FILE##*/}"
            return 1
        }
        kind="$(backup_kind "${BACKUP_FILE}")"
        [[ "${kind}" == "${required_kind}" ]] || {
            warn "для режима ${MODE} требуется $(backup_kind_label "${required_kind}") бэкап"
            return 1
        }
        return 0
    fi

    [[ -d "${BACKUP_DIR}" ]] || {
        warn "каталог бэкапов не найден: ${BACKUP_DIR}"
        return 1
    }
    while IFS= read -r selected; do
        backup_filename_supported "${selected}" && backups+=("${selected}")
    # Include links to archive files; exclude broken links and directories.
    done < <(find -L "${BACKUP_DIR}" -maxdepth 1 -type f -name '*.tar.gz' -print 2>/dev/null | sort -r)
    ((${#backups[@]})) || {
        warn "в ${BACKUP_DIR} нет поддерживаемых бэкапов"
        return 1
    }

    while true; do
        printf '\nДоступные резервные копии:\n'
        for i in "${!backups[@]}"; do
            kind="$(backup_kind "${backups[i]}")"
            case "${kind}" in
                hot) kind_label='горячий ' ;;
                cold) kind_label='холодный' ;;
            esac
            size_label="$(backup_file_size_label "${backups[i]}")" || size_label='н/д'
            printf '%3d - [%s | %9s] %s\n' "$((i + 1))" "${kind_label}" "${size_label}" "${backups[i]##*/}"
        done
        printf '  0 - Назад\n'
        read -r -p "Выберите резервную копию: " choice || return 2
        [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
        ((choice == 0)) && return 1
        ((choice >= 1 && choice <= ${#backups[@]})) || return 1
        selected="${backups[choice-1]}"
        kind="$(backup_kind "${selected}")"
        if [[ "${kind}" != "${required_kind}" ]]; then
            warn "режим ${MODE} принимает только $(backup_kind_label "${required_kind}") бэкап"
            return 1
        fi
        BACKUP_FILE="$(realpath -e -- "${selected}")"
        return 0
    done
}

decode_metadata_value() {
    local value="$1"
    if [[ "${value}" == "''" ]]; then
        printf ''
    else
        printf '%s' "${value}" | sed -E 's/\\(.)/\1/g'
    fi
}

metadata_value() {
    local key="$1" line
    while IFS= read -r line; do
        if [[ "${line%%=*}" == "${key}" ]]; then
            decode_metadata_value "${line#*=}"
            return 0
        fi
    done <<<"${META_TEXT}"
    return 1
}

read_backup_metadata() {
    local kind="$1" metadata_path value
    if [[ "${kind}" == cold ]]; then metadata_path='root/backup-info.env'; else metadata_path='backup-info.env'; fi
    META_TEXT="$(tar -xOzf "${BACKUP_FILE}" "${metadata_path}" 2>/dev/null)" || \
        die "в бэкапе отсутствует метафайл ${metadata_path}"
    [[ -n "${META_TEXT}" ]] || die "метафайл бэкапа пуст"
    META_BACKUP_TYPE="$(metadata_value backup_type || true)"
    META_PG_FAMILY="$(metadata_value pg_family || true)"
    META_PG_VERSION="$(metadata_value pg_version || true)"
    META_CLUSTER_NAME="$(metadata_value cluster_name || true)"
    META_CLUSTER_PORT="$(metadata_value cluster_port || true)"
    META_PACKAGE="$(metadata_value package || true)"
    META_DATA_DIR="$(metadata_value data_dir || true)"
    META_DATABASE_NAME="$(metadata_value database_name || true)"
    [[ "${META_BACKUP_TYPE}" == "${kind}" ]] || die \
        "тип в метафайле (${META_BACKUP_TYPE:-не указан}) не совпадает с типом архива (${kind})"
    [[ "${META_PG_VERSION}" =~ ^[0-9]+$ ]] || die "в метафайле отсутствует корректная версия PostgreSQL"
    validate_identifier "${META_CLUSTER_NAME}" || die "в метафайле некорректное имя кластера"
    [[ "${META_CLUSTER_PORT}" =~ ^[0-9]+$ ]] || die "в метафайле некорректный порт кластера"
    if [[ "${kind}" == cold ]]; then
        [[ "${META_DATA_DIR}" == /*/"${META_CLUSTER_NAME}" ]] || die "в метафайле некорректный каталог данных"
        validate_package_name "${META_PACKAGE}" || die "в метафайле некорректный серверный пакет"
    else
        validate_database_name "${META_DATABASE_NAME}" || die "в метафайле некорректное имя БД"
    fi
    value="${BACKUP_FILE##*/}"
    [[ "${value}" == "${META_PG_VERSION}-"* ]] || die "версия в имени архива не совпадает с метафайлом"
}

print_backup_metadata() {
    local kind="$1" count i name size role_login
    printf '\nМетаданные выбранного бэкапа:\n'
    printf '  Тип:                 %s\n' "$(backup_kind_label "${kind}")"
    printf '  Файл:                %s\n' "${BACKUP_FILE}"
    printf '  Хост-источник:       %s\n' "$(metadata_value host_name || printf 'не указан')"
    printf '  Дата создания:       %s\n' "$(metadata_value created_at || printf 'не указана')"
    printf '  PostgreSQL:           %s\n' "$(metadata_value postgres_version_text || printf '%s' "${META_PG_VERSION}")"
    printf '  Семейство:           %s\n' "${META_PG_FAMILY:-не указано}"
    printf '  Кластер-источник:    %s\n' "${META_CLUSTER_NAME}"
    printf '  Порт источника:      %s\n' "${META_CLUSTER_PORT}"
    [[ -n "${META_PACKAGE}" ]] && printf '  Серверный пакет:     %s\n' "${META_PACKAGE}"
    [[ -n "${META_DATA_DIR}" ]] && printf '  Каталог данных:      %s\n' "${META_DATA_DIR}"
    size="$(metadata_value data_directory_du_sh || metadata_value data_directory_size_pretty || true)"
    [[ -n "${size}" ]] && printf '  Размер data:         %s\n' "${size}"
    [[ -n "${META_DATABASE_NAME}" ]] && printf '  База данных:         %s\n' "${META_DATABASE_NAME}"
    count="$(metadata_value database_count || printf '0')"
    if [[ "${count}" =~ ^[0-9]+$ ]] && ((count > 0)); then
        printf '  Базы данных:\n'
        for ((i = 1; i <= count; i++)); do
            name="$(metadata_value "database_${i}_name" || true)"
            size="$(metadata_value "database_${i}_size_pretty" || true)"
            printf '    %-24s %s\n' "${name}" "${size}"
        done
    fi
    count="$(metadata_value role_count || printf '0')"
    if [[ "${count}" =~ ^[0-9]+$ ]] && ((count > 0)); then
        printf '  Роли БД:\n'
        for ((i = 1; i <= count; i++)); do
            name="$(metadata_value "role_${i}_name" || true)"
            role_login="$(metadata_value "role_${i}_can_login" || true)"
            if [[ "${role_login}" == yes ]]; then role_login=LOGIN; else role_login=NOLOGIN; fi
            printf '    %-24s %s\n' "${name}" "${role_login}"
        done
        printf '  Хеши паролей ролей сохранены в метафайле и не выводятся.\n'
    fi
}

infer_family_from_package() {
    case "$1" in
        postgrespro-ent-*) printf 'postgrespro-ent' ;;
        tantor-free-*) printf 'tantor-free' ;;
        tantor-se-server-*) printf 'tantor-se' ;;
        tantor-be-server-*) printf 'tantor-be' ;;
        postgresql-*) printf 'postgresql' ;;
        *) return 1 ;;
    esac
}

# Status convention for interactive steps: 0 forward, 1 back, 2 EOF/exit.
wizard_screen() {
    [[ ! -t 1 ]] || printf '\033[2J\033[H'
    printf '%s, версия %s\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
    printf '%s\n' '-------------------------------------------------------------------------------'
}

prompt_family() {
    local choice default_choice=1
    case "${pg}" in postgresql) default_choice=1 ;; postgrespro-ent) default_choice=2 ;; tantor-free) default_choice=3 ;; tantor-se) default_choice=4 ;; tantor-be) default_choice=5 ;; esac
    while true; do
        printf '\nСемейство PostgreSQL:\n1 - postgresql\n2 - postgrespro-ent\n3 - tantor-free\n4 - tantor-se (Special Edition)\n5 - tantor-be (Basic Edition)\n'
        printf '0 - Назад\n'
        read -r -p "Выбор [${default_choice}]: " choice || return 2
        choice="${choice:-${default_choice}}"
        case "${choice}" in
            1) pg=postgresql; return 0 ;;
            2) pg=postgrespro-ent; return 0 ;;
            3) pg=tantor-free; return 0 ;;
            4) pg=tantor-se; return 0 ;;
            5) pg=tantor-be; return 0 ;;
            *) return 1 ;;
        esac
    done
}

prompt_validated_value() {
    local target="$1" label="$2" current="$3" validator="$4" message="$5" value
    while true; do
        value="$(prompt_value "${label}" "${current}")" || return $?
        if "${validator}" "${value}"; then
            printf -v "${target}" '%s' "${value}"
            return 0
        fi
        warn "${message}"
        return 1
    done
}

validate_version() { [[ "$1" =~ ^[0-9]+$ ]]; }
validate_port() { [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }
validate_package_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]; }

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

normalize_extra_dependencies() {
    local specification dependency existing
    local -a requested=()
    EXTRA_DEPENDENCIES=()
    [[ -n "${EXTRA_DEPENDENCIES_INPUT}" ]] || return 0
    IFS=',' read -r -a requested <<<"${EXTRA_DEPENDENCIES_INPUT}"
    for specification in "${requested[@]}"; do
        dependency="$(trim_whitespace "${specification}")"
        validate_package_name "${dependency}" || return 1
        for existing in "${EXTRA_DEPENDENCIES[@]}"; do
            [[ "${existing}" == "${dependency}" ]] && continue 2
        done
        EXTRA_DEPENDENCIES+=("${dependency}")
    done
    ((${#EXTRA_DEPENDENCIES[@]} > 0))
}

filter_auto_postgrespro_dependencies() {
    local dependency version maximum="${POSTGRESPRO_MAX_AUTO_VERSION}" joined=""
    local -a filtered=()
    [[ "${PREFER_NEWEST_SERVER}" == yes ]] || return 0
    ((pg_ver > maximum)) && maximum="${pg_ver}"
    for dependency in "${EXTRA_DEPENDENCIES[@]}"; do
        if [[ "${dependency}" =~ ^postgrespro-ent-([0-9]+)-server$ ]]; then
            version="${BASH_REMATCH[1]}"
            if ((version >= pg_ver && version <= maximum)); then
                warn "дополнительная зависимость ${dependency} исключена: сервер устанавливается через соответствующую альтернативу contrib"
                continue
            fi
        fi
        filtered+=("${dependency}")
    done
    EXTRA_DEPENDENCIES=("${filtered[@]}")
    if ((${#EXTRA_DEPENDENCIES[@]})); then
        joined="$(IFS=,; printf '%s' "${EXTRA_DEPENDENCIES[*]}")"
    fi
    EXTRA_DEPENDENCIES_INPUT="${joined}"
}

prompt_extra_dependencies() {
    local value
    while true; do
        value="$(prompt_value 'Дополнительные зависимости через запятую' "${EXTRA_DEPENDENCIES_INPUT:-нет}")" || return $?
        case "${value,,}" in
            нет|none|-) EXTRA_DEPENDENCIES_INPUT="" ;;
            *) EXTRA_DEPENDENCIES_INPUT="${value}" ;;
        esac
        if normalize_extra_dependencies; then
            return 0
        fi
        warn "используйте имена DEB-пакетов через запятую без условий версий"
        return 1
    done
}

default_target_data_path() {
    if [[ "${pg}" == tantor-free || "${pg}" == tantor-se || "${pg}" == tantor-be ]]; then
        printf '/var/lib/postgresql/%s-%s/%s' "${pg}" "${pg_ver}" "${cls_nm}"
    else
        printf '/var/lib/postgresql/%s/%s' "${pg_ver}" "${cls_nm}"
    fi
}

custom_target_data_path() {
    local root="${1%/}"
    [[ -n "${root}" ]] || root=/
    if [[ "${root}" == / ]]; then
        printf '/pg_%s/%s' "${pg_ver}" "${cls_nm}"
    else
        printf '%s/pg_%s/%s' "${root}" "${pg_ver}" "${cls_nm}"
    fi
}

# Mirror the creator's normalization of historical standard restore roots.
cold_target_data_path() {
    local base="${META_DATA_DIR%/${META_CLUSTER_NAME}}"
    if [[ "${base}" =~ ^/var/lib/postgresql/(tantor-(free|se|be)-)?[0-9]+$ ]]; then
        default_target_data_path
    else
        printf '%s/%s' "${base}" "${cls_nm}"
    fi
}

prompt_data_location() {
    local choice root default_choice=1 source_path requested_path
    if [[ "${MODE}" == 3 ]]; then
        source_path="$(cold_target_data_path)"
        ((DATA_ROOT_SET)) && default_choice=3
        while true; do
            printf '\nРазмещение восстановленного каталога данных:\n'
            printf '1 - Размещение после рестори: %s\n' "${source_path}"
            printf '2 - Дефолтное размещение выбранного сервера\n'
            printf '3 - Указать другой корневой каталог\n'
            printf '0 - Назад\n'
            read -r -p "Выбор [${default_choice}]: " choice || return 2
            choice="${choice:-${default_choice}}"
            case "${choice}" in
                1) MOVE_AFTER_RESTORE=no; DATA_ROOT=""; return 0 ;;
                2)
                    DATA_ROOT=""
                    if [[ "${source_path}" == "$(default_target_data_path)" ]]; then
                        MOVE_AFTER_RESTORE=no
                        printf 'Исходный путь уже является дефолтным; дополнительное перемещение не требуется.\n'
                    else
                        MOVE_AFTER_RESTORE=yes
                    fi
                    return 0
                    ;;
                3)
                    root="$(prompt_value 'Корневой каталог' "${DATA_ROOT:-/DATA}")" || return $?
                    [[ "${root}" == /* && "${root}" != *[[:space:]]* ]] || { warn "нужен абсолютный путь без пробелов"; return 1; }
                    requested_path="$(custom_target_data_path "${root}")"
                    if [[ "${source_path}" == "${requested_path}" ]]; then
                        MOVE_AFTER_RESTORE=no
                        DATA_ROOT=""
                        printf 'Исходный путь уже совпадает с выбранным; дополнительное перемещение не требуется.\n'
                    else
                        MOVE_AFTER_RESTORE=yes
                        DATA_ROOT="${root}"
                    fi
                    return 0
                    ;;
                *) return 1 ;;
            esac
        done
    fi
    [[ -n "${DATA_ROOT}" ]] && default_choice=2
    while true; do
        printf '\nРазмещение создаваемого каталога данных:\n'
        printf '1 - Дефолтное размещение выбранного сервера\n'
        printf '2 - Указать другой корневой каталог\n'
        printf '0 - Назад\n'
        read -r -p "Выбор [${default_choice}]: " choice || return 2
        choice="${choice:-${default_choice}}"
        case "${choice}" in
            1) DATA_ROOT=""; return 0 ;;
            2)
                root="$(prompt_value 'Корневой каталог' "${DATA_ROOT:-/DATA}")" || return $?
                [[ "${root}" == /* && "${root}" != *[[:space:]]* ]] || { warn "нужен абсолютный путь без пробелов"; return 1; }
                DATA_ROOT="${root}"; return 0
                ;;
            *) return 1 ;;
        esac
    done
}

target_data_path() {
    if [[ "${MODE}" == 3 && "${MOVE_AFTER_RESTORE}" == no ]]; then
        cold_target_data_path
    elif [[ -n "${DATA_ROOT}" ]]; then
        custom_target_data_path "${DATA_ROOT}"
    else
        default_target_data_path
    fi
}

select_mode_interactive() {
    local choice
    while true; do
        wizard_screen
        printf 'Выбор режима сборки DEB-пакета\n'
        printf '%s\n' '-------------------------------------------------------------------------------'
        printf '%s\n' \
            '0 - Выход' \
            '1 - Установить сценарии' \
            '2 - Установить сценарии и создать пустой кластер' \
            '3 - Установить сценарии и восстановить холодный бэкап' \
            '4 - Установить сценарии, создать кластер и восстановить горячий бэкап БД'
        read -r -p 'Выберите режим: ' choice || return 1
        case "${choice}" in
            0) return 1 ;;
            1|2|3|4) MODE="${choice}"; return 0 ;;
            *) return 1 ;;
        esac
    done
}

wizard_build_summary() {
    if [[ "${MODE}" == 1 ]]; then
        printf 'Будет создан пакет со сценариями, конфигурацией и документацией.\n'
        printf 'Результат: %s/%s.deb\n' "${OUTPUT_DIR}" "$(package_basename)"
        confirm 'Собрать пакет режима 1?'
        return $?
    fi
    printf '\nПараметры создаваемого DEB-пакета:\n'
    printf '  Режим:               %s\n' "${MODE}"
    printf '  Семейство:           %s\n' "${pg}"
    printf '  Версия PostgreSQL:   %s\n' "${pg_ver}"
    printf '  Серверный пакет:     %s\n' "${SERVER_PACKAGE}"
    if [[ "${MODE}" == 4 && "${pg}" == postgrespro-ent && "${PACKAGE_SET}" == 0 ]]; then
        printf '  Выбор сервера:       самый новый доступный, версия не ниже %s\n' "${pg_ver}"
    fi
    printf '  Доп. зависимости:   %s\n' "${EXTRA_DEPENDENCIES[*]:-нет}"
    printf '  Целевой кластер:     %s\n' "${cls_nm}"
    printf '  TCP-порт:            %s\n' "${cls_pt}"
    printf '  Каталог данных:      %s\n' "$(target_data_path)"
    [[ -n "${BACKUP_FILE}" ]] && printf '  Бэкап:               %s\n' "${BACKUP_FILE}"
    [[ "${MODE}" == 4 ]] && printf '  Целевая БД:          %s\n' "${DATABASE_NAME}"
    printf '  Результат:           %s/%s.deb\n' "${OUTPUT_DIR}" "$(package_basename)"
    confirm 'Собрать пакет с этими параметрами?'
}

wizard_step() {
    local step="$1" kind required_kind old_name password_value package_default
    case "${step}" in
        backup)
            if [[ "${MODE}" == 3 ]]; then required_kind=cold; else required_kind=hot; fi
            select_backup_interactive "${required_kind}" || return $?
            kind="$(backup_kind "${BACKUP_FILE}")"
            read_backup_metadata "${kind}"
            if [[ "${MODE}" == 3 ]]; then
                pg_ver="${META_PG_VERSION}"
                pg="${META_PG_FAMILY:-$(infer_family_from_package "${META_PACKAGE}" || true)}"
                SERVER_PACKAGE="${META_PACKAGE}"
                [[ -n "${pg}" && -n "${SERVER_PACKAGE}" ]] || return 1
            else
                ((PG_VERSION_SET)) || pg_ver="${META_PG_VERSION}"
                ((PG_FAMILY_SET)) || pg="${META_PG_FAMILY:-${pg}}"
            fi
            ((CLUSTER_NAME_SET)) || cls_nm="${META_CLUSTER_NAME}"
            ((CLUSTER_PORT_SET)) || cls_pt="${META_CLUSTER_PORT}"
            [[ "${MODE}" != 4 || "${DATABASE_SET}" != 0 ]] || DATABASE_NAME="${META_DATABASE_NAME}"
            ;;
        family)
            old_name="${pg}"
            prompt_family || return $?
            if [[ "${old_name}" != "${pg}" ]]; then SERVER_PACKAGE=""; PACKAGE_SET=0; fi
            ;;
        version)
            prompt_validated_value pg_ver 'Версия PostgreSQL' "${pg_ver}" validate_version 'версия должна быть целым числом' || return $?
            if [[ "${MODE}" == 4 && "${pg_ver}" != "${META_PG_VERSION}" ]]; then
                warn "горячий бэкап PostgreSQL ${META_PG_VERSION} нельзя развернуть в версию ${pg_ver}"
                return 1
            fi
            ;;
        package)
            package_default="$(default_server_package)"
            [[ -n "${SERVER_PACKAGE}" && "${PACKAGE_SET}" == 1 ]] || SERVER_PACKAGE="${package_default}"
            prompt_validated_value SERVER_PACKAGE 'Серверный пакет' "${SERVER_PACKAGE}" validate_package_name 'недопустимое имя пакета' || return $?
            [[ "${SERVER_PACKAGE}" == "${package_default}" ]] || PACKAGE_SET=1
            ;;
        dependencies) prompt_extra_dependencies || return $? ;;
        name)
            old_name="${cls_nm}"
            prompt_validated_value cls_nm 'Имя целевого кластера' "${cls_nm}" validate_identifier 'недопустимое имя кластера' || return $?
            if [[ "${MODE}" != 3 && "${cls_nm}" != "${old_name}" ]]; then
                ((SCHEMA_SET)) || cls_ch="${cls_nm}"
                ((USER_SET)) || cls_us="${cls_nm}"
                ((PASSWORD_SET)) || cls_pw="${cls_nm}"
            fi
            ;;
        port) prompt_validated_value cls_pt 'TCP-порт кластера' "${cls_pt}" validate_port 'порт должен быть числом от 1 до 65535' || return $? ;;
        schema) prompt_validated_value cls_ch 'Схема/роль-владелец' "${cls_ch}" validate_identifier 'недопустимое имя схемы' || return $? ;;
        user) prompt_validated_value cls_us 'Прикладной пользователь' "${cls_us}" validate_identifier 'недопустимое имя пользователя' || return $? ;;
        password)
            read -r -s -p 'Пароль ролей [Enter — оставить текущее значение]: ' password_value || return 2
            printf '\n'
            [[ -z "${password_value}" ]] || cls_pw="${password_value}"
            [[ -n "${cls_pw}" ]] || return 1
            ;;
        database) prompt_validated_value DATABASE_NAME 'Имя целевой БД' "${DATABASE_NAME}" validate_database_name 'недопустимое имя базы данных' || return $? ;;
        location) prompt_data_location || return $? ;;
        summary)
            PREFER_NEWEST_SERVER=no
            if [[ "${MODE}" == 4 && "${pg}" == postgrespro-ent && "${PACKAGE_SET}" == 0 ]]; then
                PREFER_NEWEST_SERVER=yes
                filter_auto_postgrespro_dependencies
            fi
            wizard_build_summary || return $?
            ;;
    esac
    return 0
}

interactive_configuration() {
    local index=0 result
    local -a steps=()
    while true; do
        if [[ -z "${MODE}" ]]; then
            select_mode_interactive || return 1
            index=0
        fi
        steps=()
        if [[ "${MODE}" != 1 ]]; then
            [[ "${MODE}" != 3 && "${MODE}" != 4 ]] || steps+=(backup)
            [[ "${MODE}" == 3 ]] || steps+=(family version package)
            steps+=(dependencies name port)
            [[ "${MODE}" == 3 ]] || steps+=(schema user password)
            [[ "${MODE}" != 4 ]] || steps+=(database)
            steps+=(location)
        fi
        steps+=(summary)
        wizard_screen
        printf 'Интерактивная сборка, режим %s; шаг %s/%s\n' "${MODE}" "$((index+1))" "${#steps[@]}"
        printf 'Неверный ввод — назад; конец ввода — выход.\n'
        if wizard_step "${steps[index]}"; then
            ((index += 1))
            ((index < ${#steps[@]})) || return 0
        else
            result=$?
            ((result != 2)) || return 1
            if ((index > 0)); then
                ((index -= 1))
            else
                MODE=""
            fi
        fi
    done
}

interactive_requested() {
    [[ "${MODE}" != 1 ]] || return 1
    case "${INTERACTIVE_MODE}" in
        yes) return 0 ;;
        no) return 1 ;;
        auto) [[ -t 0 && -t 1 ]] ;;
    esac
}

default_server_package() {
    case "${pg}" in
        postgresql) printf 'postgresql-%s-server' "${pg_ver}" ;;
        postgrespro-ent) printf 'postgrespro-ent-%s-server' "${pg_ver}" ;;
        tantor-free) printf 'tantor-free-server-%s-server' "${pg_ver}" ;;
        tantor-se|tantor-be) printf '%s-server-%s' "${pg}" "${pg_ver}" ;;
    esac
}

validate_options() {
    [[ "${MODE}" =~ ^[1-4]$ ]] || die "режим должен быть числом 1, 2, 3 или 4"
    if [[ "${MODE}" == 1 && -n "${EXTRA_DEPENDENCIES_INPUT}" ]]; then
        die "--depends поддерживается только в режимах 2, 3 и 4"
    fi
    normalize_extra_dependencies || die \
        "--depends принимает имена DEB-пакетов через запятую без условий версий"
    if [[ ! -e "${TMP_DIR}" && ! -L "${TMP_DIR}" ]]; then
        if mkdir -- "${TMP_DIR}" 2>/dev/null; then
            TMP_DIR_CREATED=1
        else
            # A concurrent build may have created the parent first; it is not ours.
            [[ -d "${TMP_DIR}" && ! -L "${TMP_DIR}" ]] || die \
                "не удалось создать служебный каталог ${TMP_DIR}"
        fi
    fi
    [[ -d "${TMP_DIR}" && ! -L "${TMP_DIR}" ]] || die \
        "служебный путь должен быть обычным каталогом: ${TMP_DIR}"
    command -v dpkg-deb >/dev/null 2>&1 || die "не найдена команда dpkg-deb"
    command -v tar >/dev/null 2>&1 || die "не найдена команда tar"
    command -v gzip >/dev/null 2>&1 || die "не найдена команда gzip для упаковки man-страниц"
    if [[ "${MODE}" == 3 && -n "${DATA_ROOT}" ]]; then
        MOVE_AFTER_RESTORE=yes
    fi

    if [[ "${MODE}" != 1 ]]; then
        case "${pg}" in
            postgresql|postgrespro-ent|tantor-free|tantor-se|tantor-be) ;;
            *) die "неподдерживаемое семейство PostgreSQL: ${pg}" ;;
        esac
        [[ "${pg_ver}" =~ ^[0-9]+$ ]] || die "версия PostgreSQL должна быть целым числом"
        validate_identifier "${cls_nm}" || die "недопустимое имя кластера: ${cls_nm}"
        validate_identifier "${cls_ch}" || die "недопустимое имя схемы: ${cls_ch}"
        validate_identifier "${cls_us}" || die "недопустимое имя пользователя: ${cls_us}"
        [[ -n "${cls_pw}" ]] || die "пароль не может быть пустым"
        [[ "${cls_pt}" =~ ^[0-9]+$ ]] && ((cls_pt >= 1 && cls_pt <= 65535)) || \
            die "порт должен быть числом от 1 до 65535"
        [[ -z "${DATA_ROOT}" || ("${DATA_ROOT}" == /* && "${DATA_ROOT}" != *[[:space:]]*) ]] || \
            die "--data-root должен быть абсолютным путём без пробельных символов"
        if [[ -z "${SERVER_PACKAGE}" ]]; then
            SERVER_PACKAGE="$(default_server_package)"
        fi
        [[ "${SERVER_PACKAGE}" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || \
            die "недопустимое имя серверного пакета: ${SERVER_PACKAGE}"
        if [[ "${pg}" == tantor-se || "${pg}" == tantor-be || "${SERVER_PACKAGE}" == tantor-se-* || "${SERVER_PACKAGE}" == tantor-be-* ]]; then
            [[ "${SERVER_PACKAGE}" == "${pg}-server-${pg_ver}" ]] || die \
                "пакет ${SERVER_PACKAGE} не соответствует семейству ${pg} и версии ${pg_ver}"
        fi
        if [[ "${MODE}" == 4 && "${pg}" == postgrespro-ent && "${PACKAGE_SET}" == 0 ]]; then
            PREFER_NEWEST_SERVER=yes
        fi
        filter_auto_postgrespro_dependencies
    fi

    case "${MODE}" in
        1|2)
            [[ -z "${BACKUP_FILE}" ]] || die "--backup-file применяется только в режимах 3 и 4"
            ;;
        3)
            [[ -n "${BACKUP_FILE}" ]] || die "для режима 3 требуется --backup-file с холодным бэкапом"
            ;;
        4)
            [[ -n "${BACKUP_FILE}" ]] || die "для режима 4 требуется --backup-file с горячим бэкапом"
            [[ -n "${DATABASE_NAME}" ]] || die "для режима 4 требуется --database"
            validate_database_name "${DATABASE_NAME}" || die "недопустимое имя базы данных: ${DATABASE_NAME}"
            ;;
    esac

    if [[ "${MODE}" == 3 || "${MODE}" == 4 ]]; then
        BACKUP_FILE="$(realpath -e -- "${BACKUP_FILE}" 2>/dev/null)" || die "не найден файл бэкапа"
        [[ -f "${BACKUP_FILE}" && ! -L "${BACKUP_FILE}" ]] || die "бэкап должен быть обычным файлом"
        tar -tzf "${BACKUP_FILE}" >/dev/null || die "не удалось прочитать архив ${BACKUP_FILE}"
        if [[ "${MODE}" == 3 ]]; then
            [[ "${BACKUP_FILE##*/}" =~ ^${pg_ver}-[A-Za-z0-9_][A-Za-z0-9_.-]*-[0-9]{8}-[0-9]{6}\.tar\.gz$ ]] || \
                die "для режима 3 требуется холодный бэкап PostgreSQL ${pg_ver}"
        else
            [[ "${BACKUP_FILE##*/}" =~ ^${pg_ver}-[A-Za-z0-9_][A-Za-z0-9_.-]*-[0-9]{8}-[0-9]{6}-dmp\.tar\.gz$ ]] || \
                die "для режима 4 требуется горячий бэкап PostgreSQL ${pg_ver}"
        fi
    fi
}

write_last_build_script() {
    local repeat_dir repeat_file builder output_dir dependency_spec="" line i actual_mode
    local -a lines=()
    repeat_dir="${SCRIPT_DIR}"
    repeat_file="${repeat_dir}/create-claster-deb-last.sh"
    builder="${SCRIPT_DIR}/${SCRIPT_NAME}"
    output_dir="$(realpath -m -- "${OUTPUT_DIR}")"

    if [[ ! -d "${repeat_dir}" || ! -w "${repeat_dir}" || \
          (-e "${repeat_file}" && ! -w "${repeat_file}") ]] || \
       ! LAST_COMMAND_TMP="$(mktemp "${repeat_dir}/.create-claster-deb-last.XXXXXX" 2>/dev/null)"; then
        LAST_COMMAND_TMP=""
        [[ -n "${HOME:-}" && "${HOME}" == /* ]] || die \
            "каталог сборщика недоступен для записи и не удалось определить домашний каталог"
        repeat_dir="${HOME}/tmp"
        repeat_file="${repeat_dir}/create-claster-deb-last.sh"
        mkdir -p -- "${repeat_dir}" || die "не удалось создать резервный каталог ${repeat_dir}"
        [[ -d "${repeat_dir}" ]] || die "путь ${repeat_dir} не является каталогом"
        LAST_COMMAND_TMP="$(mktemp "${repeat_dir}/.create-claster-deb-last.XXXXXX")" || die \
            "не удалось создать временный файл в ${repeat_dir}"
        warn "каталог ${SCRIPT_DIR} недоступен для записи; файл повтора будет сохранён в ${repeat_dir}"
    fi

    lines+=("--mode $(printf '%q' "${MODE}")")
    lines+=("--non-interactive")
    if [[ "${MODE}" != 1 ]]; then
        lines+=("--pg-family $(printf '%q' "${pg}")")
        lines+=("--pg-version $(printf '%q' "${pg_ver}")")
        if [[ "${PREFER_NEWEST_SERVER}" != yes ]]; then
            lines+=("--package $(printf '%q' "${SERVER_PACKAGE}")")
        fi
        lines+=("--cluster-name $(printf '%q' "${cls_nm}")")
        lines+=("--port $(printf '%q' "${cls_pt}")")
        if [[ "${MODE}" == 2 || "${MODE}" == 4 ]]; then
            lines+=("--schema $(printf '%q' "${cls_ch}")")
            lines+=("--user $(printf '%q' "${cls_us}")")
            lines+=("--password $(printf '%q' "${cls_pw}")")
        fi
        [[ -z "${DATA_ROOT}" ]] || lines+=("--data-root $(printf '%q' "${DATA_ROOT}")")
        if ((${#EXTRA_DEPENDENCIES[@]})); then
            dependency_spec="$(IFS=,; printf '%s' "${EXTRA_DEPENDENCIES[*]}")"
            lines+=("--depends $(printf '%q' "${dependency_spec}")")
        fi
        [[ -z "${BACKUP_FILE}" ]] || lines+=("--backup-file $(printf '%q' "${BACKUP_FILE}")")
        [[ "${MODE}" != 4 ]] || lines+=("--database $(printf '%q' "${DATABASE_NAME}")")
    fi
    lines+=("--output-dir $(printf '%q' "${output_dir}")")
    lines+=("--force")

    {
        printf '#!/usr/bin/env bash\n\n'
        printf '# Generated by %s %s.\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
        printf '# Repeats the most recently validated DEB build without prompts.\n'
        printf '# WARNING: modes 2 and 4 may contain the database password below.\n\n'
        printf 'set -Eeuo pipefail\n\n'
        printf 'exec %q' "${builder}"
        for ((i = 0; i < ${#lines[@]}; i += 1)); do
            line="${lines[i]}"
            printf ' \\\n  %s' "${line}"
        done
        printf '\n'
    } >"${LAST_COMMAND_TMP}"
    chmod 0755 "${LAST_COMMAND_TMP}" || die "не удалось назначить права 755"
    mv -f -- "${LAST_COMMAND_TMP}" "${repeat_file}" || die \
        "не удалось записать ${repeat_file}"
    LAST_COMMAND_TMP=""
    chmod 0755 "${repeat_file}" || die "не удалось назначить права 755 файлу ${repeat_file}"
    actual_mode="$(stat -c '%a' -- "${repeat_file}" 2>/dev/null || true)"
    [[ "${actual_mode}" == 755 ]] || warn \
        "файловая система сохранила для ${repeat_file} права ${actual_mode:-неизвестно} вместо 755"
    printf 'Команда повторной сборки: %s\n' "${repeat_file}"
}

package_basename() {
    case "${MODE}" in
        1) printf 'claster-creator-%s' "${SCRIPT_VERSION}" ;;
        2) printf 'claster-creator-%s-%s-%s-%s-empty' \
            "${SCRIPT_VERSION}" "${pg}" "${pg_ver}" "${cls_nm}" ;;
        3) printf 'claster-creator-%s-%s-%s-%s-full' \
            "${SCRIPT_VERSION}" "${pg}" "${pg_ver}" "${cls_nm}" ;;
        4) printf 'claster-creator-%s-%s-%s-%s-%s' \
            "${SCRIPT_VERSION}" "${pg}" "${pg_ver}" "${cls_nm}" "${DATABASE_NAME}" ;;
    esac
}

dependency_list() {
    local dependencies="postgresql-common" dependency
    if [[ "${MODE}" != 1 ]]; then
        if [[ "${PREFER_NEWEST_SERVER}" == yes ]]; then
            dependencies+=", $(postgrespro_alternative_dependencies)"
        else
            dependencies+=", ${SERVER_PACKAGE}"
            if [[ "${MODE}" != 3 && "${SERVER_PACKAGE}" =~ ^postgrespro-ent-([0-9]+)-server$ ]]; then
                dependencies+=", postgrespro-ent-${BASH_REMATCH[1]}-contrib"
            fi
        fi
    fi
    for dependency in "${EXTRA_DEPENDENCIES[@]}"; do
        dependencies+=", ${dependency}"
    done
    printf '%s' "${dependencies}"
}

postgrespro_alternative_dependencies() {
    local minimum="${pg_ver}" maximum="${POSTGRESPRO_MAX_AUTO_VERSION}" version
    local contrib_dependencies=""
    ((minimum > maximum)) && maximum="${minimum}"
    for ((version = maximum; version >= minimum; version -= 1)); do
        [[ -z "${contrib_dependencies}" ]] || contrib_dependencies+=' | '
        contrib_dependencies+="postgrespro-ent-${version}-contrib"
    done
    printf '%s' "${contrib_dependencies}"
}

write_plan_value() {
    local name="$1" value="$2"
    printf '%s=%q\n' "${name}" "${value}"
}

create_install_plan() {
    local package_base="$1" payload_dir="$2" backup_name=""
    local plan_file="${payload_dir}/.package-install.env"
    if [[ -n "${BACKUP_FILE}" ]]; then
        backup_name="${BACKUP_FILE##*/}"
        mkdir -p -- "${payload_dir}/package-data"
        install -m 0600 -- "${BACKUP_FILE}" "${payload_dir}/package-data/${backup_name}"
    fi
    {
        write_plan_value mode "${MODE}"
        write_plan_value plan_id "${package_base}"
        write_plan_value pg_family "${pg}"
        write_plan_value pg_version "${pg_ver}"
        write_plan_value cluster_name "${cls_nm}"
        write_plan_value cluster_port "${cls_pt}"
        write_plan_value schema_name "${cls_ch}"
        write_plan_value db_user "${cls_us}"
        write_plan_value db_password "${cls_pw}"
        write_plan_value data_root "${DATA_ROOT}"
        write_plan_value server_package "${SERVER_PACKAGE}"
        write_plan_value prefer_newest_server "${PREFER_NEWEST_SERVER}"
        write_plan_value database_name "${DATABASE_NAME}"
        write_plan_value backup_name "${backup_name}"
        write_plan_value move_after_restore "${MOVE_AFTER_RESTORE}"
    } >"${plan_file}"
    chmod 0600 "${plan_file}"
}

create_postinst() {
    local postinst="$1"
    cat >"${postinst}" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

readonly creator_dir="/usr/local/share/pg_claster_creator"
readonly creator="${creator_dir}/create-claster.sh"
readonly plan_file="${creator_dir}/.package-install.env"

[[ "${1:-configure}" == configure ]] || exit 0
[[ -x "${creator}" ]] || { printf 'Не найден %s\n' "${creator}" >&2; exit 1; }
[[ -r "${plan_file}" ]] || { printf 'Не найден %s\n' "${plan_file}" >&2; exit 1; }

# shellcheck disable=SC1090
source "${plan_file}"

postgrespro_package_installed() {
    local version="$1"
    dpkg-query -W -f='${db:Status-Abbrev}' "postgrespro-ent-${version}-server" 2>/dev/null | grep -q '^ii ' &&
        dpkg-query -W -f='${db:Status-Abbrev}' "postgrespro-ent-${version}-contrib" 2>/dev/null | grep -q '^ii '
}

select_postgrespro_runtime() {
    local minimum="$1" package version selected=""
    if postgrespro_package_installed "${minimum}"; then
        printf 'postgrespro-ent-%s-server|%s' "${minimum}" "${minimum}"
        return
    fi
    while IFS= read -r package; do
        package="${package%%:*}"
        [[ "${package}" =~ ^postgrespro-ent-([0-9]+)-server$ ]] || continue
        version="${BASH_REMATCH[1]}"
        ((version >= minimum)) || continue
        postgrespro_package_installed "${version}" || continue
        if [[ -z "${selected}" || version -gt ${selected##*|} ]]; then
            selected="${package}|${version}"
        fi
    done < <(
        dpkg-query -W -f='${binary:Package}\n' 'postgrespro-ent-*-server' 2>/dev/null || true
    )
    [[ -n "${selected}" ]] || return 1
    printf '%s' "${selected}"
}

if [[ "${prefer_newest_server:-no}" == yes ]]; then
    readonly requested_pg_version="${pg_version}"
    runtime_server="$(select_postgrespro_runtime "${requested_pg_version}")" || {
        printf 'ОШИБКА: не найден полный комплект postgrespro-ent версии %s или новее (server + contrib).\n' \
            "${requested_pg_version}" >&2
        exit 1
    }
    server_package="${runtime_server%%|*}"
    pg_version="${runtime_server##*|}"
    if [[ "${pg_version}" != "${requested_pg_version}" ]]; then
        printf 'Выбран PostgreSQL Pro %s — самая новая установленная версия не ниже %s.\n' \
            "${pg_version}" "${requested_pg_version}"
    fi
fi
readonly state_dir="/var/lib/claster-creator"
readonly done_marker="${state_dir}/${plan_id}.done"
readonly cluster_marker="${state_dir}/${plan_id}.cluster-created"
readonly data_moved_marker="${state_dir}/${plan_id}.data-moved"
readonly packaged_backup="${creator_dir}/package-data/${backup_name}"
readonly force_install="${CLASTER_FORCE_INSTALL:-0}"
readonly force_db_install="${CLASTER_FORCE_DB_INSTALL:-0}"
mkdir -p -- "${state_dir}"

cluster_already_exists() {
    command -v pg_lsclusters >/dev/null 2>&1 || return 1
    pg_lsclusters --no-header 2>/dev/null | awk \
        -v version="${pg_version}" -v cluster="${cluster_name}" \
        '$1 == version && $2 == cluster { found=1 } END { exit !found }'
}

cluster_current_port() {
    command -v pg_lsclusters >/dev/null 2>&1 || return 1
    pg_lsclusters --no-header 2>/dev/null | awk \
        -v version="${pg_version}" -v cluster="${cluster_name}" \
        '$1 == version && $2 == cluster && port == "" { port=$3 } END { if (port != "") print port }'
}

repeat_changed_port_notice() {
    local actual_port
    case "${mode}" in
        2|4) ;;
        *) return 0 ;;
    esac
    actual_port="$(cluster_current_port || true)"
    [[ -n "${actual_port}" && "${actual_port}" != "${cluster_port}" ]] || return 0
    printf '\nПРЕДУПРЕЖДЕНИЕ: запрошенный порт %s был занят; кластер %s/%s развёрнут на свободном порту %s.\n' \
        "${cluster_port}" "${pg_version}" "${cluster_name}" "${actual_port}"
    printf 'РЕКОМЕНДАЦИЯ: проверьте назначение порта; изменить его можно командой:\n'
    printf '  create-claster.sh --action port --pg-version %s --cluster-name %s --port СВОБОДНЫЙ_ПОРТ\n' \
        "${pg_version}" "${cluster_name}"
}

if [[ "${force_install}" == 1 && "${force_db_install}" == 1 ]]; then
    printf 'ОШИБКА: CLASTER_FORCE_INSTALL и CLASTER_FORCE_DB_INSTALL нельзя использовать одновременно.\n' >&2
    exit 2
elif [[ "${force_install}" == 1 ]]; then
    printf 'ПРИНУДИТЕЛЬНАЯ УСТАНОВКА: CLASTER_FORCE_INSTALL=1.\n'
    rm -f -- "${done_marker}" "${cluster_marker}" "${data_moved_marker}"
elif [[ "${force_db_install}" == 1 ]]; then
    if [[ "${mode}" != 4 ]]; then
        printf 'ОШИБКА: CLASTER_FORCE_DB_INSTALL поддерживается только пакетом режима 4.\n' >&2
        exit 2
    fi
    printf 'ПРИНУДИТЕЛЬНАЯ ПЕРЕУСТАНОВКА БД: CLASTER_FORCE_DB_INSTALL=1.\n'
    rm -f -- "${done_marker}"
else
    case "${mode}" in
        2|3|4)
            if cluster_already_exists; then
                [[ -e "${done_marker}" ]] && exit 0
            elif [[ -e "${done_marker}" || -e "${cluster_marker}" || -e "${data_moved_marker}" ]]; then
                printf 'ПРЕДУПРЕЖДЕНИЕ: маркеры прежней установки устарели: кластер %s/%s не зарегистрирован; план будет выполнен заново.\n' \
                    "${pg_version}" "${cluster_name}"
                rm -f -- "${done_marker}" "${cluster_marker}" "${data_moved_marker}"
            fi
            ;;
        *)
            [[ -e "${done_marker}" ]] && exit 0
            ;;
    esac
fi

remove_existing_cluster() {
    printf 'ПРЕДУПРЕЖДЕНИЕ: кластер %s/%s будет удалён без резервной копии и развёрнут заново.\n' \
        "${pg_version}" "${cluster_name}"
    PGCC_ACTION=delete \
    PGCC_PACKAGE="${server_package}" \
    PGCC_PG_FAMILY="${pg_family}" \
    PGCC_PG_VERSION="${pg_version}" \
    PGCC_CLUSTER_NAME="${cluster_name}" \
    PGCC_BACKUP_BEFORE_DELETE=no \
        "${creator}"
    if cluster_already_exists; then
        printf 'ОШИБКА: кластер %s/%s остался зарегистрирован после принудительного удаления.\n' \
            "${pg_version}" "${cluster_name}" >&2
        exit 1
    fi
}

case "${mode}" in
    2|3|4)
        if cluster_already_exists; then
            if [[ "${force_install}" == 1 ]]; then
                remove_existing_cluster
            elif [[ "${force_db_install}" == 1 ]]; then
                printf 'Кластер %s/%s сохранён; будет переустановлена только БД %s.\n' \
                    "${pg_version}" "${cluster_name}" "${database_name}"
                touch -- "${cluster_marker}"
            elif [[ -e "${cluster_marker}" ]]; then
                printf 'Продолжение незавершённой установки для кластера %s/%s.\n' \
                    "${pg_version}" "${cluster_name}"
            else
                printf 'ПРЕДУПРЕЖДЕНИЕ: кластер %s/%s уже развёрнут; действия postinst пропущены.\n' \
                    "${pg_version}" "${cluster_name}"
                touch -- "${done_marker}"
                exit 0
            fi
        elif [[ "${force_db_install}" == 1 ]]; then
            rm -f -- "${cluster_marker}"
        fi
        ;;
esac

install_cluster() {
    PGCC_ACTION=install \
    PGCC_PACKAGE="${server_package}" \
    PGCC_PG_FAMILY="${pg_family}" \
    PGCC_PG_VERSION="${pg_version}" \
    PGCC_CLUSTER_NAME="${cluster_name}" \
    PGCC_CLUSTER_PORT="${cluster_port}" \
    PGCC_SCHEMA="${schema_name}" \
    PGCC_DB_USER="${db_user}" \
    PGCC_DB_PASSWORD="${db_password}" \
    PGCC_DATA_ROOT="${data_root}" \
        "${creator}"
    cluster_already_exists || {
        printf 'ОШИБКА: сценарий установки завершился без зарегистрированного кластера %s/%s.\n' \
            "${pg_version}" "${cluster_name}" >&2
        exit 1
    }
    touch -- "${cluster_marker}"
}

restore_cold_backup() {
    PGCC_ACTION=restore \
    PGCC_BACKUP_FILE="${packaged_backup}" \
    PGCC_CLUSTER_NAME="${cluster_name}" \
    PGCC_CLUSTER_PORT="${cluster_port}" \
        "${creator}"
    cluster_already_exists || {
        printf 'ОШИБКА: холодный рестори завершился без зарегистрированного кластера %s/%s.\n' \
            "${pg_version}" "${cluster_name}" >&2
        exit 1
    }
}

restore_hot_backup() {
    PGCC_ACTION=restore \
    PGCC_BACKUP_FILE="${packaged_backup}" \
    PGCC_PG_VERSION="${pg_version}" \
    PGCC_CLUSTER_NAME="${cluster_name}" \
    PGCC_DATABASE="${database_name}" \
    PGCC_OVERWRITE=yes \
        "${creator}"
}

move_cluster_data() {
    if [[ -n "${data_root}" ]]; then
        PGCC_ACTION=move-data \
        PGCC_PACKAGE="${server_package}" \
        PGCC_PG_FAMILY="${pg_family}" \
        PGCC_PG_VERSION="${pg_version}" \
        PGCC_CLUSTER_NAME="${cluster_name}" \
        PGCC_DATA_ROOT="${data_root}" \
            "${creator}"
    else
        env -u PGCC_DATA_ROOT \
            PGCC_ACTION=move-data \
            PGCC_PACKAGE="${server_package}" \
            PGCC_PG_FAMILY="${pg_family}" \
            PGCC_PG_VERSION="${pg_version}" \
            PGCC_CLUSTER_NAME="${cluster_name}" \
            "${creator}"
    fi
    touch -- "${data_moved_marker}"
}

case "${mode}" in
    2)
        [[ -e "${cluster_marker}" ]] || install_cluster
        ;;
    3)
        [[ -f "${packaged_backup}" ]] || { printf 'Не найден встроенный холодный бэкап %s\n' "${packaged_backup}" >&2; exit 1; }
        if [[ ! -e "${cluster_marker}" ]]; then
            restore_cold_backup
            touch -- "${cluster_marker}"
        fi
        if [[ "${move_after_restore}" == yes && ! -e "${data_moved_marker}" ]]; then
            move_cluster_data
        fi
        ;;
    4)
        [[ -f "${packaged_backup}" ]] || { printf 'Не найден встроенный горячий бэкап %s\n' "${packaged_backup}" >&2; exit 1; }
        [[ -e "${cluster_marker}" ]] || install_cluster
        restore_hot_backup
        ;;
    *)
        printf 'Неподдерживаемый режим установки: %s\n' "${mode}" >&2
        exit 1
        ;;
esac

case "${mode}" in
    2|3|4)
        cluster_already_exists || {
            printf 'ОШИБКА: итоговый маркер не создан: кластер %s/%s не зарегистрирован.\n' \
                "${pg_version}" "${cluster_name}" >&2
            exit 1
        }
        ;;
esac
repeat_changed_port_notice
touch -- "${done_marker}"
exit 0
EOF
    chmod 0755 "${postinst}"
}

create_control() {
    local control_file="$1" dependencies="$2" installed_size="$3" description="$4"
    cat >"${control_file}" <<EOF
Package: claster-creator
Version: ${SCRIPT_VERSION}
Section: database
Priority: optional
Architecture: all
Depends: ${dependencies}
Maintainer: Andrei Lesnykh (AO NIKIET) <lesnyx@ya.ru>
Installed-Size: ${installed_size}
Description: PostgreSQL cluster creation and recovery utility
 ${description}
 Author: Andrei Lesnykh (AO NIKIET) <lesnyx@ya.ru>.
EOF
    chmod 0644 "${control_file}"
}

install_manual_pages() {
    local page language source_dir target_dir packed_source
    local -a pages=(create-claster.sh.1 create-claster-backup.sh.1 create-claster-deb.sh.1)
    for language in en ru; do
        source_dir="${SCRIPT_DIR}/man/${language}/man1"
        if [[ "${language}" == en ]]; then
            target_dir="${BUILD_ROOT}/usr/share/man/man1"
            packed_source="${SCRIPT_DIR}/../../../share/man/man1"
        else
            target_dir="${BUILD_ROOT}/usr/share/man/ru/man1"
            packed_source="${SCRIPT_DIR}/../../../share/man/ru/man1"
        fi
        mkdir -p -- "${target_dir}"
        for page in "${pages[@]}"; do
            if [[ -f "${source_dir}/${page}" ]]; then
                gzip -9n -c -- "${source_dir}/${page}" >"${target_dir}/${page}.gz"
            elif [[ -f "${packed_source}/${page}.gz" ]] && \
                 gzip -t -- "${packed_source}/${page}.gz"; then
                gzip -dc -- "${packed_source}/${page}.gz" | \
                    gzip -9n -c >"${target_dir}/${page}.gz"
            else
                die "не найдена man-страница ${source_dir}/${page} или ${packed_source}/${page}.gz"
            fi
            chmod 0644 "${target_dir}/${page}.gz"
        done
    done
}

build_package() {
    local package_base output_file payload_dir dependencies installed_size description
    # Do not inherit a modern host's zstd default: Astra 1.6/1.7 cannot read it.
    local -a build_command=(dpkg-deb -Zgzip --uniform-compression --build)
    [[ -f "${SCRIPT_DIR}/${TEST_JOURNAL_NAME}" && -r "${SCRIPT_DIR}/${TEST_JOURNAL_NAME}" ]] || \
        die "не найден журнал успешного тестирования версии ${TEST_JOURNAL_VERSION}: ${SCRIPT_DIR}/${TEST_JOURNAL_NAME}"
    package_base="$(package_basename)"
    mkdir -p -- "${OUTPUT_DIR}"
    OUTPUT_DIR="$(realpath -m -- "${OUTPUT_DIR}")"
    output_file="${OUTPUT_DIR}/${package_base}.deb"
    if [[ -e "${output_file}" && "${FORCE_BUILD}" != 1 ]]; then
        die "файл уже существует: ${output_file}; используйте --force для замены"
    fi

    BUILD_WORK_DIR="$(mktemp -d "${TMP_DIR}/create-claster-deb.XXXXXX")"
    BUILD_ROOT="${BUILD_WORK_DIR}/rootFs"
    payload_dir="${BUILD_ROOT}${INSTALL_DIR}"
    mkdir -p -- "${payload_dir}" "${BUILD_ROOT}/usr/local/bin" "${BUILD_ROOT}/DEBIAN"
    chmod 0755 "${BUILD_ROOT}/DEBIAN"

    install -m 0600 -- "${CONFIG_FILE}" "${payload_dir}/.new-claster.config"
    install -m 0644 -- "${SCRIPT_DIR}/CHANGELOG.md" "${payload_dir}/CHANGELOG.md"
    install -m 0755 -- "${SCRIPT_DIR}/create-claster.sh" "${payload_dir}/create-claster.sh"
    install -m 0755 -- "${SCRIPT_DIR}/create-claster-backup.sh" "${payload_dir}/create-claster-backup.sh"
    install -m 0755 -- "${SCRIPT_DIR}/create-claster-deb.sh" "${payload_dir}/create-claster-deb.sh"
    install -m 0644 -- "${SCRIPT_DIR}/README.md" "${payload_dir}/README.md"
    install -m 0644 -- "${SCRIPT_DIR}/TEST.md" "${payload_dir}/TEST.md"
    install -m 0644 -- "${SCRIPT_DIR}/${TEST_JOURNAL_NAME}" "${payload_dir}/${TEST_JOURNAL_NAME}"
    ln -s -- "${INSTALL_DIR}/create-claster.sh" "${BUILD_ROOT}${COMMAND_LINK}"
    ln -s -- "${INSTALL_DIR}/create-claster-backup.sh" "${BUILD_ROOT}${BACKUP_COMMAND_LINK}"
    printf '%s\n' "${INSTALL_DIR}/.new-claster.config" >"${BUILD_ROOT}/DEBIAN/conffiles"

    case "${MODE}" in
        1) description="Installs PostgreSQL cluster management and scheduled-backup scripts, configuration and documentation." ;;
        2) description="Installs the scripts and creates PostgreSQL cluster ${pg_ver}/${cls_nm}." ;;
        3) description="Installs the scripts and restores PostgreSQL cluster ${pg_ver}/${cls_nm} from a cold backup." ;;
        4) description="Installs the scripts, creates cluster ${pg_ver}/${cls_nm} and restores database ${DATABASE_NAME}." ;;
    esac
    if [[ "${MODE}" != 1 ]]; then
        create_install_plan "${package_base}" "${payload_dir}"
        create_postinst "${BUILD_ROOT}/DEBIAN/postinst"
    fi
    install_manual_pages
    find "${BUILD_ROOT}" -type d -exec chmod 0755 {} +
    dependencies="$(dependency_list)"
    installed_size="$(du -sk -- "${BUILD_ROOT}" | awk '{print $1}')"
    create_control "${BUILD_ROOT}/DEBIAN/control" "${dependencies}" "${installed_size}" "${description}"

    if ((EUID != 0)); then
        command -v fakeroot >/dev/null 2>&1 || die \
            "для корректного владельца файлов запустите сценарий от root или установите fakeroot"
        build_command=(fakeroot "${build_command[@]}")
    fi
    if [[ -e "${output_file}" ]]; then
        rm -f -- "${output_file}"
    fi
    "${build_command[@]}" "${BUILD_ROOT}" "${output_file}"
    printf 'Создан пакет: %s\n' "${output_file}"
}

main() {
    local interactive_build=0
    handle_early_options "$@"
    load_defaults
    parse_args "$@"
    if [[ -z "${FAKEROOTKEY:-}" ]] && command -v fakeroot >/dev/null 2>&1; then
        exec fakeroot -- "$0" "$@"
    fi
    if interactive_requested; then
        interactive_build=1
        if ! interactive_configuration; then
            printf 'Сборка отменена.\n'
            exit 0
        fi
    fi
    validate_options
    if ((interactive_build)); then
        write_last_build_script
    fi
    build_package
}

main "$@"
