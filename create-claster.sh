#!/usr/bin/env bash

# ==============================================================================
# Script: create-claster.sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Andrei Lesnykh
# License: See LICENSE distributed with this script.
# Author: Andrei Lesnykh (AO NIKIET) <lesnyx@ya.ru>
#
# Purpose:
#   Prepare a PostgreSQL server installed from APT repositories and manage
#   PostgreSQL clusters on Astra Linux and compatible Debian-based systems.
#   The script supports PostgreSQL, Postgres Pro Enterprise, and Tantor Free/SE/BE.
#   Vanilla Debian/Ubuntu/Mint servers use postgresql-N; legacy postgresql-N-server
#   layouts remain accepted. Client/contrib/meta/extension packages are not servers.
#   It can run as an interactive menu or as a fully non-interactive command.
#   Screen clearing is limited to stdout terminals with a usable TERM.
#   Edit menu item 4 executes a trusted SQL file on a selected existing database,
#   only after explicit confirmation. psql runs as postgres with ON_ERROR_STOP.
#   Cold restore resets only /var/log/postgresql to root:postgres 1775 after
#   extraction, before startup; existing log-file permissions are not changed.
#   The main menu heading shows the selected server package for new clusters.
#   Server package selection exits on 0, invalid/empty input or EOF without retrying.
#   Cluster deletion stops and verifies the server, then removes exact cluster
#   paths without pg_dropcluster or its potentially blocking syslog-ng reload.
#   On WSL without PARSEC, repair stock cluster syslog snippets that reference
#   missing Astra PostgreSQL parsers. Preserve the original, validate/rollback,
#   and collect the registered log as raw text; this is not structured Astra audit.
#   Valid/custom snippets and service/security settings are never replaced.
#   syslog-ng is not restarted/reloaded implicitly; print the required next step.
#   Cluster and vendor-service stop requests are announced on stderr before
#   execution, including unattended and cleanup calls, without extra prompts.
#   Displayed database and data-directory sizes use an aligned field of at most
#   nine characters, including a space and a two-letter binary size unit.
#   Every newly created backup contains a commented, shell-safe command that
#   rebuilds the corresponding mode 3 or mode 4 Debian package non-interactively.
#
# WSL syslog-ng troubleshooting:
#   This compatibility path is intended for functional testing on WSL; it is
#   inactive on ordinary physical and virtual Linux machines outside WSL.
#   Symptom: "Error resolving reference; content='parser', name='pgN_kv_parser'"
#   or 'pgN_audit_parser' in mod-astra-postgres-N-CLUSTER.conf. Astra's native
#   pg_createcluster generates these references even when the installed server
#   (for example Tantor SE) does not provide the matching Astra audit parsers.
#   The same template assumes PGDATA/pg_log, which may not be the real log path.
#   repair_wsl_cluster_syslog only handles WSL without /dev/parsec, exact native
#   templates with this diagnosed error, and unchanged PGCC-owned raw snippets.
#   It reads the registered cluster log instead, preserves raw messages in
#   /var/log/postgresql/syslog-ng-N-CLUSTER.log, and does NOT provide structured
#   Astra audit events. Valid native/custom configs and non-WSL hosts are skipped.
#   Backups: /etc/syslog-ng/conf.d/.pgcc-wsl-N-CLUSTER.*.bak (not included by *.conf).
#   A failed bounded `syslog-ng --syntax-only` check restores the previous file.
#   IMPORTANT: --syntax-only alone may accept unresolved parser references!
#   Use --preprocess-into to expand includes and verify pgN parser definitions;
#   the repair checks these references as well as syntax before accepting a file.
#   No automatic reload/restart, package-hook changes or global PARSEC changes.
#   Diagnose with `syslog-ng --syntax-only`, `systemctl cat syslog-ng.service`,
#   `journalctl -u syslog-ng.service -n 50`, and `pg_lsclusters` (effective log).
#   After reviewing a repair, explicitly apply it with a bounded service command
#   such as `timeout -k 5 30 systemctl restart syslog-ng.service`, then check
#   `systemctl is-active syslog-ng.service` and actual destination log delivery.
#   Configuration validity alone is
#   not proof that the running daemon has loaded the repaired configuration.
#   A separate WSL failure, "pdplinux_capability_set_apply() failed", can come
#   from syslog-ng-caps.conf / CapabilitiesParsec. This repair does not disable
#   that security drop-in. Also check the boot journal: unsupported Manager keys
#   such as Parsec=no/MAC=no can be ignored, not effective security switches.
#
# Actions accepted by --action / PGCC_ACTION:
#   info       Display registered clusters using pg_lsclusters.
#   install    Install and initialize a new cluster and application roles. In
#              non-interactive mode, a conflicting requested port is replaced
#              by the next free port and reported with a port-change command.
#   port       Change the TCP port of an existing cluster.
#   move-data  Move a cluster data directory to a default or custom location.
#   backup     Create a cold cluster backup or a hot database backup.
#   restore    Restore a cold cluster backup or a hot database dump.
#   delete     Delete a cluster or, interactively, one database. The menu offers
#              a cold cluster backup or hot database backup before deletion.
#   Interactive menu item 3 selects a cluster, then offers the opposite of its
#   current state with explicit y/N confirmation; no separate action selection.
#   Interactive menu item 4 opens the Edit submenu: rename, port, data location,
#   execute SQL. SQL execution is interactive only: no --action sql or --sql-file.
#   Renaming uses pg_renamecluster with child-scoped PG_CLUSTER_CONF_ROOT,
#   preserves state/autostart and rewrites complete paths only once. Effective
#   data/HBA/ident paths are checked before start; standard log links are updated.
#   No enable/disable is used; one bounded daemon-reload follows unit updates.
#   Partial failure reports a recovery manifest, without an automatic rollback.
#   Database/role names and external cron jobs are not renamed.
#
# Command-line options:
#       --config FILE          Select a trusted config; overrides PGCC_CFG.
#   -h, --help                         Print detailed usage information.
#   -v, --version                      Print the script version.
#   -a, --action ACTION                Select a non-interactive action.
#       --package PACKAGE              Select an exact PostgreSQL server package.
#       --pg-family FAMILY             postgresql, postgrespro-ent, tantor-free, tantor-se, tantor-be.
#       --pg-version VERSION           Select the PostgreSQL major version.
#       --cluster-name NAME            Set the source, target, or new cluster name.
#       --port PORT                    Set a cluster TCP port.
#       --schema NAME                  Set the application schema/owner role.
#       --user NAME                    Set the application login role.
#       --password PASSWORD            Set the application role password.
#       --data-root DIRECTORY          Set a custom root for install/move-data.
#       --backup-dir DIRECTORY         Set the backup storage/search directory.
#       --backup-file FILE             Select a relative or absolute restore file.
#       --backup-type TYPE             Select hot/cold (also accepts 1/2).
#       --database NAME                Select a database for hot backup/restore.
#       --backup-before-delete YES|NO  Control backup before cluster deletion.
#       --clear-wal YES|NO             Control emergency WAL reset before backup.
#       --overwrite YES|NO             Allow drop/recreate during hot restore.
#
# Positional arguments:
#   The backup and delete actions additionally accept VERSION CLUSTER after the
#   action, matching the familiar pg_ctlcluster addressing style:
#     create-claster.sh --action backup 16 subsys
#     create-claster.sh --action delete 16 subsys --backup-before-delete no
#
# Environment interface:
#   Functional CLI options have ENV equivalents listed below; CLI wins over ENV.
#   Supported ENV inputs survive the script's own sudo re-execution.
#   Help/version have no ENV aliases. Start/stop, rename and SQL remain menu-only.
#   PGCC_CFG selects a trusted configuration file; --config takes precedence.
#   Priority: --config > PGCC_CFG > existing per-system config > script-local config.
#   Relative paths use the invocation directory; empty PGCC_CFG means unset.
#   Missing, unreadable or non-file explicit configs fail without fallback.
#   PGCC_ACTION, PGCC_PACKAGE, PGCC_PG_FAMILY, PGCC_PG_VERSION,
#   PGCC_CLUSTER_NAME, PGCC_CLUSTER_PORT, PGCC_SCHEMA, PGCC_DB_USER,
#   PGCC_DB_PASSWORD, PGCC_DATA_ROOT, PGCC_BACKUP_DIR, PGCC_BACKUP_FILE,
#   PGCC_BACKUP_TYPE, PGCC_DATABASE, PGCC_BACKUP_BEFORE_DELETE,
#   PGCC_CLEAR_WAL, and PGCC_OVERWRITE mirror the command-line options.
#   PGCC_CLUSTER_PORT maps to --port; PGCC_DB_USER to --user;
#   PGCC_DB_PASSWORD to --password; PGCC_DATABASE to --database.
#   There is no PGCC_SQL_FILE input. Select the SQL file in the Edit menu.
#
# Configuration:
#   Without --config/PGCC_CFG, prefer the existing per-system file
#   /usr/local/shared/pg_claster_creator/.new-claster.config, otherwise use
#   .new-claster.config beside the resolved script. Saves update only the selected
#   file. Explicit selection is retained across sudo. An unreadable preferred
#   file is an error, not a reason to fall back to the project configuration.
#   Command-line arguments override environment variables, and environment
#   variables override configuration defaults. Run --help for complete examples.
# ==============================================================================

set -Eeuo pipefail

readonly SCRIPT_VERSION="2.5.6"
readonly SCRIPT_NAME="create-claster.sh"
readonly SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd -P)"
readonly LOCAL_CONFIG_FILE="${SCRIPT_DIR}/.new-claster.config"
readonly INSTALLED_CONFIG_FILE="/usr/local/shared/pg_claster_creator/.new-claster.config"
CONFIG_FILE="${LOCAL_CONFIG_FILE}"
if [[ -e "${INSTALLED_CONFIG_FILE}" || -L "${INSTALLED_CONFIG_FILE}" ]]; then
    CONFIG_FILE="${INSTALLED_CONFIG_FILE}"
fi
CONFIG_EXPLICIT=0
if [[ -n "${PGCC_CFG:-}" ]]; then
    CONFIG_FILE="${PGCC_CFG}"
    CONFIG_EXPLICIT=1
fi
readonly SEPARATOR="-------------------------------------------------------------------------------"

declare SELECTED_PACKAGE=""
declare PG_HOME=""
declare PG_EXT=""
declare DATA_BASE=""
declare DEFAULT_DATA_BASE=""
declare CLEANUP_DIR=""
declare SELECTED_CLUSTER_ROW=""
declare NON_INTERACTIVE=0
declare ACTION=""
declare REQUESTED_PACKAGE=""
declare INSTALL_DATA_ROOT=""
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
declare PRESERVE_NEXT_CLEAR=0
declare STARTUP_PREPARATION=0
declare -a CLUSTER_DATABASES=()
declare -a CLUSTER_DATABASE_SIZE_BYTES=()
declare -a CLUSTER_DATABASE_SIZES=()
declare -a BACKUP_ROLE_NAMES=()
declare -a BACKUP_ROLE_SUPERUSERS=()
declare -a BACKUP_ROLE_INHERITS=()
declare -a BACKUP_ROLE_CREATE_ROLES=()
declare -a BACKUP_ROLE_CREATE_DBS=()
declare -a BACKUP_ROLE_CAN_LOGINS=()
declare -a BACKUP_ROLE_REPLICATIONS=()
declare -a BACKUP_ROLE_BYPASS_RLS=()
declare -a BACKUP_ROLE_CONNECTION_LIMITS=()
declare -a BACKUP_ROLE_VALID_UNTILS=()
declare -a BACKUP_ROLE_PASSWORD_HASHES=()

declare ARG_ACTION=""
declare ARG_PACKAGE=""
declare ARG_PG_FAMILY=""
declare ARG_PG_VERSION=""
declare ARG_CLUSTER_NAME=""
declare ARG_CLUSTER_PORT=""
declare ARG_SCHEMA=""
declare ARG_DB_USER=""
declare ARG_DB_PASSWORD=""
declare ARG_DATA_ROOT=""
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
Интерактивный пункт 3 — Остановить/Запустить: кластер, действие по состоянию, y/N.
Для Debian/Ubuntu/Mint сервер — postgresql-N, например --package postgresql-16.
Совместимые имена postgresql-N-server также поддерживаются.
Интерактивный пункт 4 — Изменить: переименование, переключение порта, перенос данных,
выполнение SQL (подпункт 4). Выберите кластер, существующую БД, номер .sql в
каталоге бэкапов либо относительный/абсолютный путь. 0 — на предыдущий шаг.
SQL выполняется от postgres только после y/Y; Enter — отказ. При ошибке psql
останавливается, вывод остаётся до Enter; возможны частичные изменения.
SQL доступен только через меню: --action sql и --sql-file не поддерживаются.
Переименовать: проверка нового имени, остановка,
переименование регистрации/путей и служб; исходное состояние запуска сохраняется.
До запуска проверяются пути data/HBA/ident; автозапуск переносится без enable/disable.
При ошибке выводятся этап и /var/tmp/pgcc-rename.*/rename-state.env; автоотката нет.
Имена БД/ролей и задания cron не переименовываются.
Удаление кластера: подтверждённая остановка, удаление его данных, конфигурации
и службы без pg_dropcluster. Внешние цели ссылок WAL/tablespace сохраняются.
При неинтерактивном install занятый порт автоматически заменяется первым
следующим свободным; предупреждение показывает фактический порт и команду
для его последующей смены.
Размеры БД и каталогов данных показываются в выровненном поле шириной девять
символов: две цифры после точки, пробел и двухбуквенная единица измерения.

Конфиг: --config ФАЙЛ > PGCC_CFG > /usr/local/shared/pg_claster_creator/.new-claster.config,
при отсутствии — .new-claster.config рядом с разрешённым сценарием.
Явный путь — абсолютный или относительно текущего каталога; пустой PGCC_CFG не задан.
Явный файл должен существовать и читаться; fallback при ошибке запрещён.
Сохраняется только выбранный конфиг. Используйте доверенные файлы.
Одноимённые кластеры разных major допустимы; пути, службы и порты проверяются отдельно.

Общие ключи:
      --config ФАЙЛ                  Предпочтительный конфиг; переопределяет PGCC_CFG
  -h, --help                         Показать эту справку и выйти
  -v, --version                      Показать версию сценария и выйти
  -a, --action ДЕЙСТВИЕ              info|install|port|move-data|backup|restore|delete
      --package ПАКЕТ                Точный серверный пакет PostgreSQL
      --pg-family СЕМЕЙСТВО          postgresql|postgrespro-ent|tantor-free|tantor-se|tantor-be
      --pg-version ВЕРСИЯ            Версия PostgreSQL, например 16
      --cluster-name ИМЯ             Имя создаваемого или целевого кластера
      --port ПОРТ                    Новый порт при install, port или restore
      --schema ИМЯ                   Схема и владелец БД при установке
      --user ИМЯ                     Прикладной пользователь БД при установке
      --password ПАРОЛЬ              Пароль пользователя при установке
      --data-root КАТАЛОГ            Корень данных для install или move-data
      --backup-dir КАТАЛОГ           Каталог резервных копий
      --backup-file ФАЙЛ             Архив restore: относительный или полный путь
      --backup-type ТИП              Тип backup: hot|cold или 1|2; по умолчанию cold
      --database ИМЯ                 База для горячего backup/restore
      --backup-before-delete ДА|НЕТ  Создать бэкап перед delete; по умолчанию да
      --clear-wal ДА|НЕТ              Выполнить pg_resetwal перед бэкапом; по умолчанию нет
      --overwrite ДА|НЕТ              Удалить и заново создать существующую БД
                                      при горячем restore

Для backup и delete поддерживается форма pg_ctlcluster: два позиционных
аргумента ВЕРСИЯ КЛАСТЕР после действия, например: backup 16 subsys.

Значения ДА|НЕТ: yes/no, y/n, true/false, 1/0.

После холодного restore каталог /var/log/postgresql получает root:postgres 1775
без изменения прав вложенных лог-файлов; ошибка установки прав запрещает запуск.

Переменные окружения:
  PGCC_CFG — путь к предпочтительному конфигу (ниже приоритетом, чем --config).
  PGCC_ACTION, PGCC_PACKAGE, PGCC_PG_FAMILY, PGCC_PG_VERSION,
  PGCC_CLUSTER_NAME, PGCC_CLUSTER_PORT, PGCC_SCHEMA, PGCC_DB_USER,
  PGCC_DB_PASSWORD, PGCC_DATA_ROOT, PGCC_BACKUP_DIR, PGCC_BACKUP_FILE,
  PGCC_BACKUP_TYPE, PGCC_DATABASE,
  PGCC_BACKUP_BEFORE_DELETE, PGCC_CLEAR_WAL, PGCC_OVERWRITE.
Приоритет значений: ключи командной строки > PGCC_* > значения конфига.
PGCC_CLUSTER_PORT соответствует --port, PGCC_DB_USER — --user,
PGCC_DB_PASSWORD — --password, PGCC_DATABASE — --database.
Переменной PGCC_SQL_FILE нет; SQL-файл выбирается интерактивно.

Примеры:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --version
  ${SCRIPT_NAME} --action info
  ${SCRIPT_NAME} --action install --package postgrespro-ent-16-server \\
    --cluster-name subsys --port 5432 --schema subsys --user subsys \\
    --password 'change-me' --data-root /DATA
  ${SCRIPT_NAME} --action port --pg-version 16 --cluster-name subsys --port 5433
  ${SCRIPT_NAME} --action move-data --pg-version 16 --cluster-name subsys --data-root /DATA
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

select_config() {
    # Normalize an explicit path before sudo, cron or a repeat build changes context.
    # Do not read the file here: privilege escalation may be needed first.
    if ((CONFIG_EXPLICIT)); then
        CONFIG_FILE="$(realpath -m -- "${CONFIG_FILE}")" || die "не удалось разрешить путь конфига"
        export PGCC_CFG="${CONFIG_FILE}"
    fi
}

parse_args() {
    while (($#)); do
        case "$1" in
            --config) option_value_required "$@"; CONFIG_FILE="$2"; CONFIG_EXPLICIT=1; shift 2 ;;
            --config=*) CONFIG_FILE="${1#*=}"; [[ -n "${CONFIG_FILE}" ]] || die "для ключа --config требуется значение"; CONFIG_EXPLICIT=1; shift ;;
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
            --data-root) option_value_required "$@"; ARG_DATA_ROOT="$2"; shift 2 ;;
            --data-root=*) ARG_DATA_ROOT="${1#*=}"; shift ;;
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
    INSTALL_DATA_ROOT="${ARG_DATA_ROOT:-${PGCC_DATA_ROOT:-}}"
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
            change-port|switch-port) ACTION=port ;;
            move|relocate-data) ACTION=move-data ;;
            info|install|port|move-data|backup|restore|delete) ACTION="${ACTION,,}" ;;
            *) die "неподдерживаемое действие ${ACTION}; используйте info|install|port|move-data|backup|restore|delete" ;;
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
    ((STARTUP_PREPARATION)) && PRESERVE_NEXT_CLEAR=1
    return 0
}

startup_notice() {
    printf '%s\n' "$*"
    PRESERVE_NEXT_CLEAR=1
}

clear_screen() {
    # Interactive menus may also be piped to a log; never emit terminal controls there.
    [[ -t 1 ]] || return 0
    case "${TERM:-}" in ''|dumb|unknown) return 0 ;; esac
    clear 2>/dev/null || true
}

header() {
    if ((!NON_INTERACTIVE)); then
        if ((PRESERVE_NEXT_CLEAR)); then
            PRESERVE_NEXT_CLEAR=0
        else
            clear_screen
        fi
    fi
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

# Separate path/render helpers make the WSL-only repair testable without touching
# the host's configuration. They are internal functions, not an ENV interface.
wsl_syslog_config_dir() { printf '/etc/syslog-ng/conf.d\n'; }

render_stock_cluster_syslog() {
    local version="$1" name="$2" data="$3"
    cat <<EOF
source s_pg${version}_${name} {
    wildcard-file(
        base-dir("${data}/pg_log")
        recursive(no)
        filename-pattern("*.log")
        monitor-method(inotify)
        program-override("postgres")
        flags(no-hostname)
    );
};
log {
    source(s_pg${version}_${name});
    parser(pg${version}_kv_parser);
    parser(pg${version}_audit_parser);
    destination(astra_json_dst);
};
EOF
}

render_wsl_cluster_syslog() {
    local version="$1" name="$2" log="$3"
    cat <<EOF
# PGCC WSL raw PostgreSQL log v1
# Missing Astra parsers: preserve messages, not structured Astra audit events.
source s_pg${version}_${name} {
    file("${log}" follow-freq(1)
         program-override("postgres") flags(no-parse, no-hostname));
};
destination d_pg${version}_${name}_raw {
    file("/var/log/postgresql/syslog-ng-${version}-${name}.log"
         owner("root") group("postgres") perm(0640)
         template("\${MESSAGE}\\n"));
};
log { source(s_pg${version}_${name}); destination(d_pg${version}_${name}_raw); };
EOF
}

wsl_syslog_has_parser() {
    grep -Eq "^[[:space:]]*parser[[:space:]]+$2([[:space:]]|\\{)" "$1"
}

validate_wsl_syslog_pg_parsers() {
    local expanded="$1" parser bad=0
    while IFS= read -r parser; do
        if ! wsl_syslog_has_parser "$expanded" "$parser"; then
            printf 'WSL syslog: undefined PostgreSQL parser: %s\n' "$parser" >&2
            bad=1
        fi
    done < <(grep -oE 'parser[[:space:]]*\([[:space:]]*pg[0-9]+_(kv|audit)_parser[[:space:]]*\)' "$expanded" | sed -E 's/.*\([[:space:]]*//; s/[[:space:]]*\).*//' | sort -u || true)
    return "$bad"
}

repair_wsl_cluster_syslog() (
    local version="$1" name="$2" data="$3" log="$4" old_name="${5:-}" dir conf work backup candidate old_log owned=no
    is_wsl_without_parsec || return 0
    command -v syslog-ng >/dev/null 2>&1 || return 0
    [[ "$version" =~ ^[0-9]+$ && "$name" =~ ^[a-z_][a-z0-9_]*$ ]] || return 0
    dir="$(wsl_syslog_config_dir)"; conf="${dir}/mod-astra-postgres-${version}-${name}.conf"
    [[ -d "$dir" && ! -L "$dir" && -f "$conf" && ! -L "$conf" ]] || return 0
    # Never interpolate config metacharacters or read our own output in a loop.
    [[ "$log" == /* && "$data" == /* && "$log" != "/var/log/postgresql/syslog-ng-${version}-${name}.log" ]] || return 0
    case "$log$data" in *'"'*|*'\'*|*'$'*|*$'\n'*|*$'\r'*) warn 'WSL syslog: небезопасный путь; конфиг не изменён'; return 0 ;; esac
    [[ ! -e "$log" || ( -f "$log" && ! -L "$log" ) ]] || return 0
    work="$(mktemp -d /tmp/pgcc-syslog.XXXXXX)" || return 1
    trap 'rm -rf -- "$work"; [[ -z "${candidate:-}" ]] || rm -f -- "$candidate"' EXIT
    if grep -qxF '# PGCC WSL raw PostgreSQL log v1' "$conf"; then
        old_log="$(sed -n 's/^    file("\([^"]*\)" follow-freq(1)$/\1/p' "$conf")"
        [[ -n "$old_log" ]] || return 0
        render_wsl_cluster_syslog "$version" "$name" "$old_log" >"$work/owned"
        if [[ "$old_name" =~ ^[a-z_][a-z0-9_]*$ ]]; then
            # Astra pg_renamecluster changes source IDs but leaves this hyphenated
            # output filename unchanged. Accept only that exact native transition.
            replace_literal_in_file "/var/log/postgresql/syslog-ng-${version}-${name}.log" "/var/log/postgresql/syslog-ng-${version}-${old_name}.log" "$work/owned"
        fi
        cmp -s "$conf" "$work/owned" || return 0
        owned=yes
    else
        render_stock_cluster_syslog "$version" "$name" "$data" >"$work/stock"
        # Only the exact native template may be replaced; even local comments
        # or formatting changes are preserved as potentially intentional edits.
        cmp -s "$conf" "$work/stock" || return 0
        if ! timeout -k 2 15 syslog-ng --syntax-only --preprocess-into="$work/expanded" >"$work/check" 2>&1; then
            warn 'WSL syslog: ошибка синтаксиса; автоматическое исправление не выполняется'
            return 0
        fi
        [[ -s "$work/expanded" ]] || return 0
        if wsl_syslog_has_parser "$work/expanded" "pg${version}_kv_parser" &&
           wsl_syslog_has_parser "$work/expanded" "pg${version}_audit_parser"; then return 0; fi
    fi
    render_wsl_cluster_syslog "$version" "$name" "$log" >"$work/new"
    cmp -s "$conf" "$work/new" && return 0
    if [[ "$owned" == no && ( -e "/var/log/postgresql/syslog-ng-${version}-${name}.log" || -L "/var/log/postgresql/syslog-ng-${version}-${name}.log" ) ]]; then
        warn 'WSL syslog: целевой raw-журнал уже существует; конфиг не изменён'; return 0
    fi
    backup="$(mktemp "${dir}/.pgcc-wsl-${version}-${name}.XXXXXX.bak")" || return 1
    cp -p -- "$conf" "$backup" || return 1
    candidate="$(mktemp "${dir}/.pgcc-wsl-${version}-${name}.XXXXXX.new")" || return 1
    install -o root -g root -m 0644 "$work/new" "$candidate" || return 1
    mv -fT -- "$candidate" "$conf" || return 1
    candidate=""
    if ! timeout -k 2 15 syslog-ng --syntax-only --preprocess-into="$work/expanded" >"$work/check" 2>&1 ||
       [[ ! -s "$work/expanded" ]] ||
       ! validate_wsl_syslog_pg_parsers "$work/expanded" >>"$work/check" 2>&1; then
        cp -p -- "$backup" "$conf" || return 1
        warn "WSL syslog: проверка не прошла, исходный конфиг восстановлен; копия: ${backup}"
        cat "$work/check" >&2
        return 1
    fi
    warn "WSL syslog: ${version}/${name}: включён raw-журнал вместо отсутствующих Astra-парсеров; копия: ${backup}"
    warn 'Это не структурированный аудит Astra. Для применения выполните проверяемый reload/restart syslog-ng; сценарий его не вызывает.'
)

repair_wsl_registered_syslog() {
    local rows version name port status owner data log
    is_wsl_without_parsec || return 0
    command -v syslog-ng >/dev/null 2>&1 || return 0
    rows="$(pg_lsclusters --no-header)" || { warn 'WSL syslog: реестр недоступен; конфиги не изменены'; return 0; }
    while read -r version name port status owner data log; do
        [[ -n "$version" ]] || continue
        repair_wsl_cluster_syslog "$version" "$name" "$data" "$log" || warn "WSL syslog: не удалось исправить ${version}/${name}"
    done <<<"$rows"
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
        local variable
        local -a config_env=(env)
        # Forward only the documented interface when sudo filters the environment.
        for variable in PGCC_CFG PGCC_ACTION PGCC_PACKAGE PGCC_PG_FAMILY PGCC_PG_VERSION \
            PGCC_CLUSTER_NAME PGCC_CLUSTER_PORT PGCC_SCHEMA PGCC_DB_USER PGCC_DB_PASSWORD \
            PGCC_DATA_ROOT PGCC_BACKUP_DIR PGCC_BACKUP_FILE PGCC_BACKUP_TYPE PGCC_DATABASE \
            PGCC_BACKUP_BEFORE_DELETE PGCC_CLEAR_WAL PGCC_OVERWRITE; do
            [[ ! -v "$variable" ]] || config_env+=("$variable=${!variable}")
        done
        command -v sudo >/dev/null 2>&1 || die "сценарий нужно запускать от root"
        if [[ ! -t 0 || ! -t 2 || -n "${ARG_ACTION:-${PGCC_ACTION:-}}" ]]; then
            exec sudo -n -- "${config_env[@]}" bash "${BASH_SOURCE[0]}" "$@"
        fi
        exec sudo -- "${config_env[@]}" bash "${BASH_SOURCE[0]}" "$@"
    fi
}

load_config() {
    [[ -f "${CONFIG_FILE}" && -r "${CONFIG_FILE}" ]] || die \
        "выбранный конфиг отсутствует или недоступен для чтения: ${CONFIG_FILE}"
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
    ((NON_INTERACTIVE)) || PRESERVE_NEXT_CLEAR=1
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
        return
    fi
    package_available postgresql-common || {
        printf 'Обновление сведений о репозиториях...\n'
        apt-get update || die "не удалось обновить сведения о репозиториях"
    }
    package_available postgresql-common || die "postgresql-common отсутствует в подключённых репозиториях"
    install_package postgresql-common
}

vanilla_server_package() {
    local version="$1" candidate
    # Preserve an installed package layout; otherwise prefer Debian's canonical name.
    for candidate in "postgresql-${version}" "postgresql-${version}-server"; do
        package_installed "${candidate}" && { printf '%s' "${candidate}"; return 0; }
    done
    for candidate in "postgresql-${version}" "postgresql-${version}-server"; do
        package_available "${candidate}" && { printf '%s' "${candidate}"; return 0; }
    done
    printf 'postgresql-%s' "${version}"
}

package_to_fields() {
    local package="$1"
    if [[ "${package}" =~ ^postgrespro-ent-([0-9]+)-server$ ]]; then
        printf 'postgrespro-ent|%s\n' "${BASH_REMATCH[1]}"
    elif [[ "${package}" =~ ^postgresql-([0-9]+)(-server)?$ ]]; then
        printf 'postgresql|%s\n' "${BASH_REMATCH[1]}"
    elif [[ "${package}" =~ ^tantor-free-server-([0-9]+)(-server)?$ ]]; then
        printf 'tantor-free|%s\n' "${BASH_REMATCH[1]}"
    elif [[ "${package}" =~ ^tantor-(se|be)-server-([0-9]+)$ ]]; then
        printf 'tantor-%s|%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
        return 1
    fi
}

server_packages() {
    apt-cache pkgnames 2>/dev/null |
        grep -E '^(postgrespro-ent-[0-9]+-server|postgresql-[0-9]+(-server)?|tantor-free-server-[0-9]+(-server)?|tantor-(se|be)-server-[0-9]+)$' |
        sort -u
}

installed_server_packages() {
    local package
    while IFS= read -r package; do
        server_package_installed "${package}" && printf '%s\n' "${package}"
    done < <(
        dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null |
            awk '$2 == "ii" {sub(/:.*/, "", $1); print $1}' |
            grep -E '^(postgrespro-ent-[0-9]+-server|postgresql-[0-9]+(-server)?|tantor-free-server-[0-9]+(-server)?|tantor-(se|be)-server-[0-9]+)$' |
            sort -u || true
    )
}

# SE/Enterprise precede BE, then the shared Tantor Free / PostgreSQL tier.
# PostgresPro Enterprise shares the top tier with SE; explicit choices win.
server_family_priority() {
    case "$1" in
        tantor-se|postgrespro-ent) printf 1 ;;
        tantor-be) printf 2 ;;
        *) printf 3 ;;
    esac
}

choose_from_packages() {
    local title="$1" choice fields package version previous index version_priority
    shift
    local -a packages=("$@") ordered=()
    mapfile -t ordered < <(
        for package in "${packages[@]}"; do
            fields="$(package_to_fields "${package}")" || continue
            version="${fields#*|}"
            printf '%s|%s|%s\n' "$(server_family_priority "${fields%%|*}")" "${version}" "${package}"
        done | sort -t'|' -k1,1n -k2,2Vr -k3,3 | cut -d'|' -f3-
    )
    ((${#ordered[@]})) || return 1

    printf '\n%s\n' "${title}"
    previous=""
    index=0
    version_priority=0
    for package in "${ordered[@]}"; do
        fields="$(package_to_fields "${package}")"
        version="${fields#*|}"
        if [[ "$(server_family_priority "${fields%%|*}")|${version}" != "${previous}" ]]; then
            ((version_priority += 1))
            printf '\nPostgreSQL %s:\n' "${version}"
            previous="$(server_family_priority "${fields%%|*}")|${version}"
        fi
        ((index += 1))
        printf '  %d - %s (приоритет %s)\n' "${index}" "${package}" "${version_priority}"
    done
    printf '  0 - Выход\n'
    read -r -p "Выберите пакет: " choice || exit 0
    # Compare the displayed numbers as strings: malformed/huge input is never arithmetic.
    for index in "${!ordered[@]}"; do
        if [[ "${choice}" == "$((index + 1))" ]]; then
            SELECTED_PACKAGE="${ordered[index]}"
            return 0
        fi
    done
    exit 0
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
        tantor-free|tantor-se|tantor-be)
            PG_HOME="/opt/tantor/db/${pg_ver}"
            PG_EXT="${PG_HOME}/lib/postgresql"
            DATA_BASE="/var/lib/postgresql/${pg}-${pg_ver}"
            ;;
        postgresql)
            PG_HOME="/usr/lib/postgresql/${pg_ver}"
            PG_EXT="${PG_HOME}/lib"
            DATA_BASE="/var/lib/postgresql/${pg_ver}"
            ;;
    esac
    DEFAULT_DATA_BASE="${DATA_BASE}"
    [[ -x "${PG_HOME}/bin/postgres" ]] || die "в пакете ${SELECTED_PACKAGE} не найден ${PG_HOME}/bin/postgres"
    save_config
}

vendor_service_name() {
    local package="$1"
    case "${package}" in
        postgrespro-ent-*-server) printf '%s' "${package%-server}" ;;
        tantor-free-server-*-server) printf '%s' "${package%-server}" ;;
        tantor-free-server-*) printf '%s' "${package}" ;;
        tantor-se-server-*|tantor-be-server-*) printf '%s' "${package}" ;;
        *) return 1 ;;
    esac
}

unmask_vendor_service() {
    local unit state status
    unit="$(vendor_service_name "$1")" || return 0
    status=0
    state="$(timeout 15s systemctl is-enabled "${unit}" 2>/dev/null)" || status=$?
    ((status != 124 && status != 137)) || die "истекло время проверки службы ${unit}"
    # A not-yet-installed or already unmasked unit needs no mutation.
    case "${state}" in
        masked|masked-runtime) ;;
        enabled|enabled-runtime|disabled|static|indirect|generated|transient|linked|linked-runtime|not-found) return 0 ;;
        '')
            [[ "$(timeout 15s systemctl show "${unit}" -p LoadState --value 2>/dev/null)" == not-found ]] && return 0
            die "не удалось проверить наличие службы ${unit}" ;;
        *) die "не удалось определить состояние маски службы ${unit}: ${state}" ;;
    esac
    printf 'Снятие маски со штатной службы %s перед установкой...\n' "${unit}"
    timeout 30s systemctl unmask "${unit}" || die "не удалось снять маску со службы ${unit}"
}

stop_disable_vendor_service() {
    local unit output state
    unit="$(vendor_service_name "$1")" || return 0
    state="$(timeout 15s systemctl is-active "${unit}" 2>/dev/null || true)"
    if [[ "${state}" != inactive && "${state}" != failed ]]; then
        printf 'Будет остановлена штатная служба PostgreSQL: %s.\n' "${unit}" >&2
        if ! output="$(timeout 30s systemctl stop "${unit}" 2>&1)"; then
            [[ -n "${output}" ]] && printf '%s\n' "${output}" >&2
            die "не удалось остановить службу ${unit}"
        fi
    fi
    state="$(timeout 15s systemctl is-enabled "${unit}" 2>/dev/null || true)"
    # Avoid redundant SysV synchronization on older Astra/WSL systemd.
    if [[ "${state}" == disabled ]]; then
        return 0
    fi
    if ! output="$(timeout 30s systemctl disable "${unit}" 2>&1)"; then
        [[ -n "${output}" ]] && printf '%s\n' "${output}" >&2
        die "не удалось отключить автозапуск службы ${unit}"
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
                postgresql) package="$(vanilla_server_package "${pg_ver}")" ;;
                tantor-se|tantor-be) package="${pg}-server-${pg_ver}" ;;
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
            :
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
    elif ((${#installed[@]} == 1)); then
        SELECTED_PACKAGE="${installed[0]}"
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
        choose_from_packages "Доступные серверные пакеты (SE/Enterprise, BE, Free/PostgreSQL; затем версия):" "${available[@]}"
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
            ((NON_INTERACTIVE)) || startup_notice \
                "Каталог данных используется через ссылку ${DATA_BASE} -> /.postgres/data."
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

print_cluster_row() {
    local prefix="$1" row="$2" version name port status remainder color
    read -r version name port status remainder <<<"${row}"
    if [[ -t 1 ]]; then
        if [[ "${status}" == online* ]]; then
            color=32
        else
            color=31
        fi
        printf '%s\033[%sm%s\033[0m\n' "${prefix}" "${color}" "${row}"
    else
        printf '%s%s\n' "${prefix}" "${row}"
    fi
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
    # Announce every stop request, including cleanup and non-interactive calls.
    # Keep diagnostics off stdout and never add an unattended input prompt here.
    printf 'Будет остановлен кластер %s/%s.\n' "${version}" "${name}" >&2
    if cluster_online "${version}" "${name}"; then
        if run_parsec_aware timeout --foreground -k 5s 60s pg_ctlcluster \
            --skip-systemctl-redirect "${version}" "${name}" stop; then
            status=0
        else
            status=$?
        fi
        ((status == 0)) || die "не удалось остановить ${version}/${name}: код=${status}"
    fi
    run_parsec_aware timeout --foreground -k 5s 15s systemctl stop "${service}" || true
    timeout -k 5s 15s systemctl reset-failed "${service}" >/dev/null 2>&1 || true
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

tcp_port_listening() {
    local port="$1"
    command -v ss >/dev/null 2>&1 || return 1
    ss -H -ltn 2>/dev/null | awk -v p="${port}" '
        {
            address=$4
            sub(/^.*:/, "", address)
            if (address == p) found=1
        }
        END {exit !found}
    '
}

cluster_using_port() {
    local port="$1"
    cluster_rows | awk -v p="${port}" \
        '$3 == p && found == "" {found=$1 "/" $2} END {if (found != "") print found}'
}

find_free_cluster_port() {
    local requested="$1" first candidate
    first=$((10#${requested} + 1))
    ((first < 1024)) && first=1024
    for ((candidate = first; candidate <= 65535; candidate += 1)); do
        if ! port_in_use "${candidate}" && ! tcp_port_listening "${candidate}"; then
            printf '%s' "${candidate}"
            return 0
        fi
    done
    for ((candidate = 1024; candidate < first && candidate <= 65535; candidate += 1)); do
        ((candidate == 10#${requested})) && continue
        if ! port_in_use "${candidate}" && ! tcp_port_listening "${candidate}"; then
            printf '%s' "${candidate}"
            return 0
        fi
    done
    return 1
}

select_noninteractive_install_port() {
    local requested="${cls_pt}" conflict="" free_port
    if port_in_use "${requested}"; then
        conflict="кластером $(cluster_using_port "${requested}")"
    elif tcp_port_listening "${requested}"; then
        conflict="другим процессом"
    else
        return 0
    fi
    free_port="$(find_free_cluster_port "${requested}")" || die \
        "не найден свободный TCP-порт для кластера ${pg_ver}/${cls_nm}"
    cls_pt="${free_port}"
    warn "порт ${requested} уже используется ${conflict}; для кластера ${pg_ver}/${cls_nm} выбран свободный порт ${cls_pt}"
    warn "проверьте назначение порта; изменить его можно командой: ${SCRIPT_NAME} --action port --pg-version ${pg_ver} --cluster-name ${cls_nm} --port СВОБОДНЫЙ_ПОРТ"
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
        print_cluster_row "$(printf '%3d - ' "$((i + 1))")" "${rows[i]}"
    done
}

validate_identifier() {
    [[ "$1" =~ ^[a-z_][a-z0-9_]*$ ]]
}

normalize_data_root() {
    local root="$1"
    [[ "${root}" == /* ]] || return 1
    [[ "${root}" != *[$'\t\r\n ']* ]] || return 1
    realpath -ms -- "${root}"
}

install_data_base_from_root() {
    local root version="${2:-${pg_ver}}"
    root="$(normalize_data_root "$1")" || return 1
    if [[ "${root}" == / ]]; then
        printf '/pg_%s' "${version}"
    else
        printf '%s/pg_%s' "${root}" "${version}"
    fi
}

data_directory_available() {
    local directory="$1"
    [[ ! -e "${directory}" && ! -L "${directory}" ]] && return 0
    [[ -d "${directory}" ]] || return 1
    [[ -z "$(find "${directory}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}

ensure_data_base_directory() {
    local directory="$1"
    mkdir -p -- "${directory}" || die \
        "не удалось создать каталог размещения данных ${directory}"
    [[ -d "${directory}" ]] || die \
        "путь размещения данных ${directory} не является каталогом"
}

prompt_value() {
    local label="$1" current="$2" value
    read -r -p "${label} [${current}]: " value || return 1
    printf '%s' "${value:-${current}}"
}

prompt_cluster_settings() {
    local old_name="${cls_nm}" new_port="${cls_pt}" new_name="${cls_nm}"
    local new_schema="${cls_ch}" new_user="${cls_us}" new_password="${cls_pw}" value
    local new_data_base="${DEFAULT_DATA_BASE}" data_choice data_root data_dir
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

    while true; do
        printf '\nРасположение каталога данных:\n'
        printf '1 - Системный путь: %s/%s\n' "${DEFAULT_DATA_BASE}" "${new_name}"
        printf '2 - Указать другой корневой путь\n'
        printf '0 - Отменить установку\n'
        read -r -p "Выбор [1]: " data_choice || return 1
        data_choice="${data_choice:-1}"
        case "${data_choice}" in
            0) return 1 ;;
            1)
                new_data_base="${DEFAULT_DATA_BASE}"
                ;;
            2)
                read -r -p "Путь размещения данных (например /DATA): " data_root || return 1
                if ! new_data_base="$(install_data_base_from_root "${data_root}")"; then
                    warn "укажите абсолютный путь без пробельных символов"
                    continue
                fi
                ;;
            *)
                warn "выберите 0, 1 или 2"
                continue
                ;;
        esac
        data_dir="${new_data_base}/${new_name}"
        if ! data_directory_available "${data_dir}"; then
            warn "каталог ${data_dir} уже существует и не пуст либо не является каталогом"
            continue
        fi
        break
    done

    printf '\nПараметры:\n  пакет: %s\n  версия: %s\n  порт: %s\n  кластер: %s\n  каталог данных: %s\n  схема/владелец: %s\n  пользователь: %s\n' \
        "${SELECTED_PACKAGE}" "${pg_ver}" "${new_port}" "${new_name}" "${data_dir}" "${new_schema}" "${new_user}"
    confirm "Создать кластер с этими параметрами?" Y || return 1

    cls_pt="${new_port}"
    cls_nm="${new_name}"
    cls_ch="${new_schema}"
    cls_us="${new_user}"
    cls_pw="${new_password}"
    DATA_BASE="${new_data_base}"
}

systemd_unit_dir() {
    [[ -d /usr/lib/systemd/system ]] && printf '/usr/lib/systemd/system' || printf '/lib/systemd/system'
}

cluster_service_file() {
    local version="$1" name="$2" include_saved="${3:-yes}" service candidate
    service="postgresql@${version}-${name}.service"
    for candidate in \
        "/etc/systemd/system/${service}" \
        "/usr/lib/systemd/system/${service}" \
        "/lib/systemd/system/${service}" \
        "/.postgres/systemd/save/${service}"; do
        [[ "${include_saved}" == no && "${candidate}" == /.postgres/systemd/save/* ]] && continue
        if [[ -f "${candidate}" ]]; then
            printf '%s' "${candidate}"
            return 0
        fi
    done
    return 1
}

# Normalize historical standard roots to the actual server package; preserve
# custom locations. Cluster renaming alone must not retain another edition's root.
cold_restore_data_path() {
    local package="$1" source="$2" original="$3" target="$4" base fields family version
    base="${source%/${original}}"
    fields="$(package_to_fields "${package}")" || return 1
    family="${fields%%|*}"; version="${fields#*|}"
    if [[ "${base}" =~ ^/var/lib/postgresql/(tantor-(free|se|be)-)?[0-9]+$ ]]; then
        case "${family}" in
            tantor-*) base="/var/lib/postgresql/${family}-${version}" ;;
            *) base="/var/lib/postgresql/${version}" ;;
        esac
    fi
    printf '%s/%s' "${base}" "${target}"
}

restore_target_conflict() {
    local version="$1" name="$2" data_dir="$3" policy="${4:-strict}" service candidate rows existing_version unit_state
    service="postgresql@${version}-${name}.service"
    rows="$(pg_lsclusters --no-header 2>/dev/null)" || {
        printf 'не удалось проверить зарегистрированные кластеры'
        return 0
    }
    existing_version="$(awk -v v="${version}" -v n="${name}" '$1 == v && $2 == n {print $1}' <<<"${rows}")"
    if [[ -n "${existing_version}" ]]; then
        printf 'кластер %s/%s уже зарегистрирован; выберите другое имя для этой версии PostgreSQL' "${version}" "${name}"
        return 0
    fi
    if [[ "${policy}" == rename ]]; then
        unit_state="$(timeout -k 5s 15s systemctl show "${service}" -p ActiveState -p MainPID 2>/dev/null)" || {
            printf 'не удалось проверить состояние службы %s' "${service}"; return 0;
        }
        if ! grep -Eq '^ActiveState=(inactive|failed)$' <<<"${unit_state}" || ! grep -qx 'MainPID=0' <<<"${unit_state}"; then
            printf 'служба %s работает или её состояние небезопасно для замены' "${service}"
            return 0
        fi
    fi
    for candidate in \
        "/etc/postgresql/${version}/${name}" \
        "${data_dir}" \
        "/etc/systemd/system/${service}" \
        "/usr/lib/systemd/system/${service}" \
        "/lib/systemd/system/${service}" \
        "/.postgres/systemd/${service}"; do
        # systemd/save is a cache, never a live restore target.
        # The convenience link is recreated by ensure_symlink after restore.
        # Keep conflicts for real files, live links and all other destinations.
        if [[ "${candidate}" == "/.postgres/systemd/${service}" && -L "${candidate}" && ! -e "${candidate}" ]]; then
            continue
        fi
        if [[ -e "${candidate}" || -L "${candidate}" ]]; then
            if [[ "${policy}" == rename && "${candidate}" != "${data_dir}" && "${candidate}" != "/etc/postgresql/${version}/${name}" ]]; then
                # An unregistered, inactive unit is residue, not a name conflict.
                continue
            fi
            printf 'целевой путь уже существует: %s' "${candidate}"
            return 0
        fi
    done
    return 1
}

write_cluster_unit_file() {
    local unit_file="$1" version="$2" name="$3" data_dir="$4"
    cat >"${unit_file}" <<EOF
[Unit]
Description=PostgreSQL Cluster ${version}-${name}
AssertPathExists=/etc/postgresql/${version}/${name}/postgresql.conf
RequiresMountsFor=/etc/postgresql/${version}/${name} ${data_dir}
PartOf=postgresql.service
ReloadPropagatedFrom=postgresql.service
Before=postgresql.service
After=network.target

[Service]
Type=forking
ExecStart=-/usr/bin/pg_ctlcluster --skip-systemctl-redirect ${version}-${name} start
TimeoutStartSec=0
ExecStop=/usr/bin/pg_ctlcluster --skip-systemctl-redirect -m fast ${version}-${name} stop
TimeoutStopSec=1h
ExecReload=/usr/bin/pg_ctlcluster --skip-systemctl-redirect ${version}-${name} reload
PIDFile=/run/postgresql/${version}-${name}.pid
SyslogIdentifier=postgresql@${version}-${name}
OOMScoreAdjust=-900

[Install]
WantedBy=multi-user.target
EOF
}

write_cluster_unit() {
    local unit_dir service data_dir
    unit_dir="$(systemd_unit_dir)"
    service="postgresql@${pg_ver}-${cls_nm}.service"
    data_dir="${DATA_BASE}/${cls_nm}"
    write_cluster_unit_file "${unit_dir}/${service}" "${pg_ver}" "${cls_nm}" "${data_dir}"
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
    ensure_data_base_directory "${DATA_BASE}"
    mkdir -p -- "${data_dir}" /var/log/postgresql
    chown -R postgres:postgres "${data_dir}"
    run_parsec_aware pg_createcluster "${pg_ver}" "${cls_nm}" -p "${cls_pt}" --start-conf=auto \
        -d "${data_dir}" -l "${data_log}" --createclusterconf="${create_conf}" \
        -- --auth-local=peer --auth-host="${auth_method}"
    repair_wsl_cluster_syslog "$pg_ver" "$cls_nm" "$data_dir" "$data_log" || warn 'WSL syslog: требуется ручная проверка конфигурации'

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
        if [[ -n "${INSTALL_DATA_ROOT}" ]]; then
            DATA_BASE="$(install_data_base_from_root "${INSTALL_DATA_ROOT}")" || \
                die "--data-root должен содержать абсолютный путь без пробельных символов"
        fi
        [[ "${cls_pt}" =~ ^[0-9]+$ ]] && ((cls_pt >= 1 && cls_pt <= 65535)) || \
            die "порт должен быть числом от 1 до 65535"
        validate_identifier "${cls_nm}" || die "недопустимое имя кластера: ${cls_nm}"
        validate_identifier "${cls_ch}" || die "недопустимое имя схемы: ${cls_ch}"
        validate_identifier "${cls_us}" || die "недопустимое имя пользователя: ${cls_us}"
        [[ -n "${cls_pw}" ]] || die "пароль пользователя не может быть пустым"
        cluster_exists "${pg_ver}" "${cls_nm}" && die "кластер ${pg_ver}/${cls_nm} уже развёрнут"
        select_noninteractive_install_port
        data_directory_available "${DATA_BASE}/${cls_nm}" || \
            die "каталог ${DATA_BASE}/${cls_nm} уже существует и не пуст либо не является каталогом"
        printf '\nПараметры:\n  пакет: %s\n  версия: %s\n  порт: %s\n  кластер: %s\n  каталог данных: %s\n  схема/владелец: %s\n  пользователь: %s\n' \
            "${SELECTED_PACKAGE}" "${pg_ver}" "${cls_pt}" "${cls_nm}" "${DATA_BASE}/${cls_nm}" "${cls_ch}" "${cls_us}"
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

set_cluster_port() {
    local version="$1" name="$2" data="$3" new_port="$4"
    local conf_dir file configured_port
    conf_dir="/etc/postgresql/${version}/${name}"
    [[ -f "${conf_dir}/postgresql.conf" ]] || die \
        "не найден файл настроек ${conf_dir}/postgresql.conf"
    command -v pg_conftool >/dev/null 2>&1 || die "не найдена команда pg_conftool"

    pg_conftool "${version}" "${name}" set port "${new_port}" || die \
        "не удалось изменить порт в postgresql.conf кластера ${version}/${name}"
    if [[ -d "${conf_dir}/conf.d" ]]; then
        while IFS= read -r -d '' file; do
            set_postgresql_setting "${file}" port "${new_port}"
        done < <(find "${conf_dir}/conf.d" -type f -name '*.conf' -print0)
    fi
    set_postgresql_setting "${data}/postgresql.auto.conf" port "${new_port}"

    configured_port="$(pg_conftool -s "${version}" "${name}" show port 2>/dev/null || true)"
    [[ "${configured_port}" == "${new_port}" ]] || die \
        "проверка настроек вернула порт ${configured_port:-не определён} вместо ${new_port}"
}

change_port_menu() {
    local row version name old_port status owner data log new_port was_online=no
    header
    step "Кластер: Переключить порт"
    if ! cluster_rows | grep -q .; then
        warn "развёрнутых кластеров нет"
        pause
        return 0
    fi
    select_cluster "Выберите кластер" || return 0
    row="${SELECTED_CLUSTER_ROW}"
    read -r version name old_port status owner data log <<<"${row}"

    if ((NON_INTERACTIVE)); then
        ((TARGET_PORT_SET)) || die \
            "для действия port укажите --port или PGCC_CLUSTER_PORT"
        new_port="${cls_pt}"
    else
        while true; do
            new_port="$(prompt_value "Новый TCP-порт" "${old_port}")" || return 0
            [[ "${new_port}" =~ ^[0-9]+$ ]] && ((new_port >= 1 && new_port <= 65535)) || {
                warn "порт должен быть числом от 1 до 65535"
                continue
            }
            [[ "${new_port}" != "${old_port}" ]] || {
                warn "порт ${new_port} уже используется выбранным кластером"
                continue
            }
            if port_in_use_by_other_cluster "${new_port}" "${version}" "${name}"; then
                warn "порт ${new_port} уже назначен другому кластеру"
                continue
            fi
            if tcp_port_listening "${new_port}"; then
                warn "TCP-порт ${new_port} уже занят другим процессом"
                continue
            fi
            break
        done
        printf '\nКластер %s/%s: порт %s -> %s.\n' \
            "${version}" "${name}" "${old_port}" "${new_port}"
        if [[ "${status}" == online* ]]; then
            confirm "Будет остановлен кластер при переключении порта. Продолжить?" Y || return 0
        else
            confirm "Переключить порт выбранного кластера?" Y || return 0
        fi
    fi

    [[ "${new_port}" =~ ^[0-9]+$ ]] && ((new_port >= 1 && new_port <= 65535)) || \
        die "порт должен быть числом от 1 до 65535"
    [[ "${new_port}" != "${old_port}" ]] || die \
        "порт ${new_port} уже используется кластером ${version}/${name}"
    port_in_use_by_other_cluster "${new_port}" "${version}" "${name}" && die \
        "порт ${new_port} уже назначен другому кластеру"
    tcp_port_listening "${new_port}" && die "TCP-порт ${new_port} уже занят другим процессом"

    [[ "${status}" == online* ]] && was_online=yes
    if [[ "${was_online}" == yes ]]; then
        stop_cluster_checked "${version}" "${name}"
    fi
    set_cluster_port "${version}" "${name}" "${data}" "${new_port}"
    if [[ "${was_online}" == yes ]]; then
        printf 'Запуск кластера %s/%s на порту %s...\n' "${version}" "${name}" "${new_port}"
        start_cluster_checked "${version}" "${name}"
    fi
    printf 'Порт кластера %s/%s переключён: %s -> %s. Состояние: %s.\n' \
        "${version}" "${name}" "${old_port}" "${new_port}" \
        "$(cluster_online "${version}" "${name}" && printf online || printf down)"
    pause
}

default_cluster_data_base() {
    local version="$1" data="$2" home package fields
    home="$(cluster_pg_home "${version}" "${data}")"
    if [[ "${home}" == /opt/tantor/db/* ]]; then
        package="$(cluster_server_package "${version}" "${home}" "${data}")" || return 1
        fields="$(package_to_fields "${package}")" || return 1
        printf '/var/lib/postgresql/%s-%s' "${fields%%|*}" "${version}"
    else
        printf '/var/lib/postgresql/%s' "${version}"
    fi
}

validate_cluster_move_destination() {
    local source="$1" destination="$2" name="$3"
    local normalized source_real destination_real parent
    [[ -d "${source}" ]] || return 1
    [[ ! -L "${source}" ]] || return 1
    normalized="$(realpath -ms -- "${destination}")" || return 1
    parent="$(dirname -- "${normalized}")"
    [[ "${normalized}" == /* && "$(basename -- "${normalized}")" == "${name}" && "${parent}" != / ]] || return 1
    [[ ! -L "${normalized}" ]] || return 1
    data_directory_available "${normalized}" || return 1
    source_real="$(readlink -f -- "${source}")" || return 1
    destination_real="$(realpath -m -- "${normalized}")" || return 1
    [[ "${destination_real}" != "${source_real}" && "${destination_real}" != "${source_real}/"* ]] || return 1
}

update_cluster_data_path() {
    local version="$1" name="$2" old_data="$3" new_data="$4"
    local conf_dir service candidate resolved reported_data=""
    local -a unit_candidates=()
    conf_dir="/etc/postgresql/${version}/${name}"
    [[ -d "${conf_dir}" ]] || die "не найден каталог конфигурации ${conf_dir}"
    while IFS= read -r -d '' candidate; do
        replace_literal_in_file "${old_data}" "${new_data}" "${candidate}"
    done < <(find "${conf_dir}" -type f -print0)
    command -v pg_conftool >/dev/null 2>&1 || die "не найдена команда pg_conftool"
    pg_conftool "${version}" "${name}" set data_directory "${new_data}" || die \
        "не удалось записать новый каталог данных в конфигурацию ${version}/${name}"
    replace_literal_in_file "${old_data}" "${new_data}" "${new_data}/postgresql.auto.conf"
    replace_literal_in_file "${old_data}" "${new_data}" "${new_data}/postmaster.opts"

    service="postgresql@${version}-${name}.service"
    unit_candidates=(
        "/etc/systemd/system/${service}"
        "/usr/lib/systemd/system/${service}"
        "/lib/systemd/system/${service}"
        "/.postgres/systemd/${service}"
        "/.postgres/systemd/save/${service}"
    )
    for candidate in "${unit_candidates[@]}"; do
        [[ -f "${candidate}" ]] || continue
        resolved="$(readlink -f -- "${candidate}")" || continue
        replace_literal_in_file "${old_data}" "${new_data}" "${resolved}"
    done
    systemctl daemon-reload

    reported_data="$(cluster_rows | awk -v v="${version}" -v n="${name}" \
        '$1 == v && $2 == n {print $6; exit}')"
    [[ -n "${reported_data}" ]] || die \
        "после переноса кластер ${version}/${name} не найден в pg_lsclusters"
    [[ "$(realpath -m -- "${reported_data}")" == "$(realpath -m -- "${new_data}")" ]] || die \
        "pg_lsclusters показывает каталог ${reported_data} вместо ${new_data}"
}

# Read state without treating a failed listing as an offline cluster.
cluster_power_state() {
    local version="$1" name="$2" listing state
    listing="$(pg_lsclusters --no-header)" || return 1
    state="$(awk -v v="${version}" -v n="${name}" '$1==v && $2==n {print $4}' <<<"${listing}")"
    case "${state}" in
        online|online,*) printf online ;;
        down|down,*) printf down ;;
        *) return 1 ;;
    esac
}

cluster_power_menu() {
    local action desired verb version name port status owner data log state
    header
    step "Кластер: Остановить/Запустить"
    select_cluster 'Введите имя кластера или номер из списка' name-or-number || return 0
    read -r version name port status owner data log <<<"${SELECTED_CLUSTER_ROW}"
    state="$(cluster_power_state "${version}" "${name}")" || { warn "не удалось определить текущее состояние ${version}/${name}"; pause; return 0; }
    case "${state}" in
        online) action=stop; desired=down; verb=Остановить ;;
        down) action=start; desired=online; verb=Запустить ;;
    esac
    printf 'Кластер %s/%s, порт %s, состояние %s.\n' "${version}" "${name}" "${port}" "${state}"
    confirm "${verb} кластер ${version}/${name}?" N || return 0
    # Recheck state, but keep the confirmed action rather than toggling again.
    state="$(cluster_power_state "${version}" "${name}")" || { warn "не удалось повторно проверить состояние; действие отменено"; pause; return 0; }
    if [[ "${state}" != "${desired}" ]]; then
        case "${action}" in
            stop) stop_cluster_checked "${version}" "${name}" ;;
            start) start_cluster_checked "${version}" "${name}" ;;
        esac
    fi
    state="$(cluster_power_state "${version}" "${name}")" || die "не удалось проверить результат ${action} ${version}/${name}"
    [[ "${state}" == "${desired}" ]] || die "кластер ${version}/${name} остался в состоянии ${state}"
    printf 'Кластер %s/%s: %s.\n' "${version}" "${name}" "${state}"
    pause
}

# Match pg_renamecluster's word-boundary path replacement exactly.
renamed_cluster_path() {
    perl -e 'my ($s,$old,$new)=@ARGV; $s =~ s/\b\Q$old\E\b/$new/g; print $s' -- "$1" "$2" "$3"
}

# Rewrite only complete old paths/identifiers, in a single pass. pg_renamecluster
# may already have updated a file; old -> old_new must not become old_new_new.
# Keep the generic literal replacement used by restore/move-data unchanged.
rewrite_renamed_cluster_file() {
    local file="$1" old_conf="$2" new_conf="$3" old_data="$4" new_data="$5" old_id="$6" new_id="$7"
    [[ -f "${file}" && ! -L "${file}" ]] || return 0
    OLD_CONF="${old_conf}" NEW_CONF="${new_conf}" OLD_DATA="${old_data}" NEW_DATA="${new_data}" \
        OLD_ID="${old_id}" NEW_ID="${new_id}" perl -pi -e '
        BEGIN { %to = ($ENV{OLD_CONF} => $ENV{NEW_CONF}, $ENV{OLD_DATA} => $ENV{NEW_DATA}, $ENV{OLD_ID} => $ENV{NEW_ID}); }
        s{(\Q$ENV{OLD_CONF}\E(?=/|[\s\x27\x22]|$)|\Q$ENV{OLD_DATA}\E(?=/|[\s\x27\x22]|$)|(?<![A-Za-z0-9_])\Q$ENV{OLD_ID}\E(?![A-Za-z0-9_-]))}{$to{$1}}ge;
        ' -- "${file}"
}

# Parse the effective configuration (including auto.conf/includes) without
# starting PostgreSQL. Do not mistake a plausible registry row for a usable DB.
validate_renamed_cluster_config() {
    local version="$1" name="$2" data="$3" home="$4" owner="$5" setting value
    for setting in data_directory hba_file ident_file; do
        value="$(run_parsec_aware timeout -k 5s 15s runuser -u "${owner}" -- "${home}/bin/postgres" \
            -D "${data}" -c "config_file=/etc/postgresql/${version}/${name}/postgresql.conf" -C "${setting}")" || return 1
        if [[ "${setting}" == data_directory ]]; then
            [[ "$(realpath -m -- "${value}")" == "$(realpath -m -- "${data}")" ]] || return 1
        else
            [[ "${value}" == /* && -f "${value}" ]] || return 1
            runuser -u "${owner}" -- test -r "${value}" || return 1
        fi
    done
}

# Use a subshell so recovery diagnostics cannot replace the caller's EXIT trap.
rename_cluster_checked() (
    local version="$1" name="$2" new_name="$3" data="$4" status="$5"
    local new_data conflict service old_unit new_unit conf new_conf candidate recovery rows reported
    local old_log new_log file was_online=no stats new_stats backup_index=0 home owner status_rc=0 phase=preflight
    local old_service="postgresql@${version}-${name}.service" new_service="postgresql@${version}-${new_name}.service" link
    local -a enabled_links=()
    validate_identifier "${new_name}" && ((${#new_name} <= 63)) || die "недопустимое новое имя кластера"
    [[ "${name}" != "${new_name}" ]] || die "новое имя совпадает с текущим"
    command -v pg_renamecluster >/dev/null || die "не найдена команда pg_renamecluster"
    new_data="$(renamed_cluster_path "${data}" "${name}" "${new_name}")" || die "не удалось определить новый путь данных"
    [[ "${data}" == /* && "${data}" != / && -d "${data}" && ! -L "${data}" ]] || die "небезопасный исходный каталог данных"
    [[ -d "${new_data%/*}" ]] || die "родительский каталог нового пути не существует: ${new_data%/*}"
    # Name conflicts are scoped to the PostgreSQL major. An unchanged custom
    # data directory belongs to this source cluster, not a foreign target.
    if [[ "${new_data}" == "${data}" ]]; then
        conflict="$(restore_target_conflict "${version}" "${new_name}" "/etc/postgresql/${version}/${new_name}" rename)" && die "${conflict}"
    else
        conflict="$(restore_target_conflict "${version}" "${new_name}" "${new_data}" rename)" && die "${conflict}"
    fi
    conf="/etc/postgresql/${version}/${name}"
    new_conf="/etc/postgresql/${version}/${new_name}"
    [[ -d "${conf}" && ! -L "${conf}" ]] || die "небезопасный каталог конфигурации ${conf}"
    [[ -f "${data}/PG_VERSION" ]] || die "в каталоге данных отсутствует PG_VERSION"
    home="$(cluster_pg_home "${version}" "${data}")"
    owner="$(stat -c '%U' "${data}")"
    [[ -x "${home}/bin/pg_ctl" && -x "${home}/bin/postgres" ]] || die "не найдены серверные утилиты кластера"
    stats="$(pg_conftool "${version}" "${name}" show stats_temp_directory 2>/dev/null | sed -n "s/^stats_temp_directory = '//; s/'$//p" || true)"
    if [[ -n "${stats}" && -d "${stats}" ]]; then
        new_stats="$(renamed_cluster_path "${stats}" "${name}" "${new_name}")"
        [[ "${stats}" == "${new_stats}" || (! -e "${new_stats}" && ! -L "${new_stats}") ]] || die "целевой каталог статистики уже существует: ${new_stats}"
    fi
    for candidate in "/etc/systemd/system/postgresql@${version}-${new_name}.service.d" "/etc/syslog-ng/conf.d/mod-astra-postgres-${version}-${new_name}.conf"; do
        [[ ! -e "${candidate}" && ! -L "${candidate}" ]] || die "целевой путь уже существует: ${candidate}"
    done
    # pg_renamecluster can rename rotated logs as well; refuse overwrites.
    for old_log in /var/log/postgresql/postgresql-"${version}"-"${name}".log*; do
        [[ -e "${old_log}" || -L "${old_log}" ]] || continue
        new_log="$(renamed_cluster_path "${old_log}" "${name}" "${new_name}")"
        [[ ! -e "${new_log}" && ! -L "${new_log}" ]] || die "целевой лог уже существует: ${new_log}"
    done
    recovery="$(mktemp -d /var/tmp/pgcc-rename.XXXXXX)" || die "не удалось создать каталог страховочной копии"
    trap 'rename_rc=$?; if ((rename_rc != 0)); then printf "phase=%q\nexit_code=%q\n" "$phase" "$rename_rc" >>"$recovery/rename-state.env"; printf "ОШИБКА: переименование не завершено, этап=%s, код=%s. Состояние и пути: %s/rename-state.env; страховочная копия: %s. Автоматический откат не выполнялся; перед повтором проверьте реестр, каталоги и службы.\n" "$phase" "$rename_rc" "$recovery" "$recovery" >&2; fi' EXIT
    {
        printf 'version=%q\nold_name=%q\nnew_name=%q\nold_data=%q\nnew_data=%q\nold_conf=%q\nnew_conf=%q\n' \
            "${version}" "${name}" "${new_name}" "${data}" "${new_data}" "${conf}" "${new_conf}"
    } >"${recovery}/rename-state.env"
    cp -a -- "${conf}" "${recovery}/config" || die "не удалось сохранить конфигурацию"
    for candidate in "/etc/systemd/system/${old_service}.d" "/etc/syslog-ng/conf.d/mod-astra-postgres-${version}-${name}.conf"; do
        if [[ -e "${candidate}" || -L "${candidate}" ]]; then
            cp -a -- "${candidate}" "${recovery}/vendor-${backup_index}" || die "не удалось сохранить ${candidate}"
            printf '%s\t%s\n' "vendor-${backup_index}" "${candidate}" >>"${recovery}/unit-paths.txt"
            ((backup_index += 1))
        fi
    done
    old_unit="$(cluster_service_file "${version}" "${name}" || true)"
    [[ -z "${old_unit}" ]] || cp -- "${old_unit}" "${recovery}/unit.service" || die "не удалось сохранить unit"
    for candidate in "/etc/systemd/system/postgresql@${version}-${name}.service" "/usr/lib/systemd/system/postgresql@${version}-${name}.service" "/lib/systemd/system/postgresql@${version}-${name}.service" "/.postgres/systemd/save/postgresql@${version}-${name}.service"; do
        if [[ -e "${candidate}" || -L "${candidate}" ]]; then
            cp -a -- "${candidate}" "${recovery}/original-unit-${backup_index}" || die "не удалось сохранить ${candidate}"
            printf '%s\t%s\n' "original-unit-${backup_index}" "${candidate}" >>"${recovery}/unit-paths.txt"
            ((backup_index += 1))
        fi
    done
    # Preserve exact persistent/runtime Wants/Requires links without enable or
    # disable, which can crash systemd on Astra WSL/PARSEC for instance units.
    for candidate in /etc/systemd/system/*.wants/"${old_service}" /etc/systemd/system/*.requires/"${old_service}" \
        /run/systemd/system/*.wants/"${old_service}" /run/systemd/system/*.requires/"${old_service}"; do
        [[ -e "${candidate}" || -L "${candidate}" ]] || continue
        [[ -L "${candidate}" ]] || die "ссылка автозапуска не является симлинком: ${candidate}"
        enabled_links+=("${candidate}")
        cp -a -- "${candidate}" "${recovery}/autostart-${backup_index}"
        printf '%s\t%s\n' "autostart-${backup_index}" "${candidate}" >>"${recovery}/unit-paths.txt"
        ((backup_index += 1))
        link="${candidate%/*}/${new_service}"
        if [[ -e "${link}" || -L "${link}" ]]; then
            [[ -L "${link}" ]] || die "занят целевой файл автозапуска: ${link}"
            cp -a -- "${link}" "${recovery}/target-autostart-${backup_index}"
            printf '%s\t%s\n' "target-autostart-${backup_index}" "${link}" >>"${recovery}/unit-paths.txt"
            ((backup_index += 1))
        fi
    done
    # Preserve target-name residue as well; it will be replaced, not reused.
    for candidate in "/etc/systemd/system/postgresql@${version}-${new_name}.service" "/usr/lib/systemd/system/postgresql@${version}-${new_name}.service" "/lib/systemd/system/postgresql@${version}-${new_name}.service" "/etc/systemd/system/multi-user.target.wants/postgresql@${version}-${new_name}.service" "/.postgres/systemd/postgresql@${version}-${new_name}.service" "/.postgres/systemd/save/postgresql@${version}-${new_name}.service"; do
        if [[ -e "${candidate}" || -L "${candidate}" ]]; then
            cp -a -- "${candidate}" "${recovery}/orphan-unit-${backup_index}" || die "не удалось сохранить ${candidate}"
            printf '%s\t%s\n' "orphan-unit-${backup_index}" "${candidate}" >>"${recovery}/unit-paths.txt"
            ((backup_index += 1))
        fi
    done
    printf 'Страховочная копия конфигурации и unit: %s (данные БД не копируются).\n' "${recovery}"
    # Recheck immediately before any service or cluster changes.
    candidate="${new_data}"
    [[ "${new_data}" != "${data}" ]] || candidate="${new_conf}"
    conflict="$(restore_target_conflict "${version}" "${new_name}" "${candidate}" rename)" && die "${conflict}"
    phase=stop
    status="$(cluster_power_state "${version}" "${name}")" || die "не удалось повторно проверить исходный кластер"
    [[ "${status}" != online ]] || was_online=yes
    printf 'was_online=%q\n' "${was_online}" >>"${recovery}/rename-state.env"
    stop_cluster_checked "${version}" "${name}"
    run_parsec_aware timeout -k 5s 15s runuser -u "${owner}" -- "${home}/bin/pg_ctl" -D "${data}" status || status_rc=$?
    [[ "${status_rc}" == 3 ]] || die "не подтверждён останов кластера (pg_ctl status=${status_rc}); переименование отменено"
    phase=rename
    # Explicit confroot is scoped to this child only. It suppresses the native
    # helper's systemd reload; this function reloads once after validating paths.
    if ! PG_CLUSTER_CONF_ROOT=/etc/postgresql run_parsec_aware timeout -k 5s 60s pg_renamecluster "${version}" "${name}" "${new_name}"; then
        die "pg_renamecluster завершился ошибкой; возможны частичные изменения. Кластер не запускается автоматически. Копия: ${recovery}"
    fi
    [[ -d "${new_conf}" && -d "${new_data}" ]] || die "после переименования нет ожидаемых каталогов; копия: ${recovery}"
    phase=configuration
    # Native helpers move standard log files but can leave conf/log pointing
    # at the old name; the next start would recreate that old log. Preserve
    # custom external log destinations and update only the exact standard link.
    if [[ -L "${new_conf}/log" && "$(readlink -- "${new_conf}/log")" == "/var/log/postgresql/postgresql-${version}-${name}.log" ]]; then
        ln -sfn -- "/var/log/postgresql/postgresql-${version}-${new_name}.log" "${new_conf}/log" || die "не удалось обновить ссылку журнала"
    fi
    while IFS= read -r -d '' file; do
        rewrite_renamed_cluster_file "${file}" "${conf}" "${new_conf}" "${data}" "${new_data}" "${version}-${name}" "${version}-${new_name}"
    done < <(find "${new_conf}" -type f -print0)
    for file in "${new_data}/postgresql.auto.conf" "${new_data}/postmaster.opts"; do
        rewrite_renamed_cluster_file "${file}" "${conf}" "${new_conf}" "${data}" "${new_data}" "${version}-${name}" "${version}-${new_name}"
    done
    mkdir -p "${new_conf}/conf.d"
    if [[ -d "/etc/systemd/system/${new_service}.d" && ! -L "/etc/systemd/system/${new_service}.d" ]]; then
        while IFS= read -r -d '' file; do
            rewrite_renamed_cluster_file "${file}" "${conf}" "${new_conf}" "${data}" "${new_data}" "${version}-${name}" "${version}-${new_name}"
        done < <(find "/etc/systemd/system/${new_service}.d" -type f -print0)
    fi
    printf "cluster_name = '%s/%s'\n" "${version}" "${new_name}" >"${new_conf}/conf.d/cluster_name.conf"
    set_postgresql_setting "${new_data}/postgresql.auto.conf" cluster_name "'${version}/${new_name}'"
    pg_conftool "${version}" "${new_name}" set data_directory "${new_data}" || die "не удалось записать каталог данных"
    validate_renamed_cluster_config "${version}" "${new_name}" "${new_data}" "${home}" "${owner}" || die "неверные эффективные пути data/HBA/ident после переименования; кластер не запускается"
    rows="$(pg_lsclusters --no-header)" || die "не удалось проверить переименованный кластер; копия: ${recovery}"
    reported="$(awk -v v="${version}" -v n="${new_name}" '$1==v && $2==n {print $6}' <<<"${rows}")"
    [[ "${reported}" == "${new_data}" ]] || die "неожиданный путь после переименования: ${reported}; копия: ${recovery}"
    new_log="$(awk -v v="$version" -v n="$new_name" '$1==v && $2==n {print $7}' <<<"$rows")"
    repair_wsl_cluster_syslog "$version" "$new_name" "$new_data" "$new_log" "$name" || warn 'WSL syslog: требуется ручная проверка после переименования'
    service="postgresql@${version}-${new_name}.service"
    phase=service
    remove_cluster_service_files "${version}" "${new_name}" defer
    new_unit="$(systemd_unit_dir)/${service}"
    if [[ -f "${recovery}/unit.service" ]]; then
        cp -- "${recovery}/unit.service" "${new_unit}" || die "не удалось записать новый unit"
        rewrite_renamed_cluster_file "${new_unit}" "${conf}" "${new_conf}" "${data}" "${new_data}" "${version}-${name}" "${version}-${new_name}"
    else
        write_cluster_unit_file "${new_unit}" "${version}" "${new_name}" "${new_data}"
    fi
    remove_cluster_service_files "${version}" "${name}" defer
    for candidate in "${enabled_links[@]}"; do
        link="${candidate%/*}/${new_service}"
        [[ ! -e "${link}" && ! -L "${link}" || -L "${link}" ]] || die "целевой автозапуск изменился: ${link}"
        rm -f -- "${candidate}" "${link}"
        ln -s -- "${new_unit}" "${link}" || die "не удалось перенести автозапуск: ${link}"
    done
    mkdir -p /.postgres/systemd/save
    cp --remove-destination -- "${new_unit}" "/.postgres/systemd/save/${service}" || die "не удалось обновить копию unit"
    ensure_symlink "${new_unit}" "/.postgres/systemd/${service}"
    phase=daemon-reload
    timeout -k 5s 15s systemctl daemon-reload || die "не удалось перечитать systemd"
    phase=start
    if [[ "${was_online}" == yes ]]; then start_cluster_checked "${version}" "${new_name}"; fi
    [[ "$(cluster_power_state "${version}" "${new_name}")" == "${status}" ]] || die "итоговое состояние кластера не совпало с исходным"
    printf 'phase=complete\n' >>"${recovery}/rename-state.env"
    printf 'Кластер %s/%s переименован в %s/%s. Каталог данных: %s.\n' "${version}" "${name}" "${version}" "${new_name}" "${new_data}"
    warn "задания cron и внешние подключения со старым именем проверьте отдельно; имена БД и ролей не изменены"
)

rename_cluster_menu() {
    local version name port status owner data log new_name conflict new_data
    header
    step "Кластер: Переименовать"
    select_cluster "Выберите кластер" || return 0
    read -r version name port status owner data log <<<"${SELECTED_CLUSTER_ROW}"
    while true; do
        read -r -p "Новое имя кластера (0 — назад): " new_name || return 0
        [[ "${new_name}" != 0 ]] || return 0
        validate_identifier "${new_name}" && ((${#new_name} <= 63)) || { warn "имя: 1–63 символа, строчные латинские буквы, цифры и подчёркивание; не начинается с цифры"; continue; }
        [[ "${new_name}" != "${name}" ]] || { warn "новое имя совпадает с текущим"; continue; }
        new_data="$(renamed_cluster_path "${data}" "${name}" "${new_name}")"
        if conflict="$(restore_target_conflict "${version}" "${new_name}" "$([[ "${data}" == "${new_data}" ]] && printf '/etc/postgresql/%s/%s' "${version}" "${new_name}" || printf '%s' "${new_data}")" rename)"; then
            warn "${conflict}"; continue
        fi
        break
    done
    printf 'Кластер: %s/%s -> %s/%s\nДанные: %s -> %s\n' "${version}" "${name}" "${version}" "${new_name}" "${data}" "${new_data}"
    confirm "Остановить кластер и переименовать?" Y || return 0
    rename_cluster_checked "${version}" "${name}" "${new_name}" "${data}" "${status}"
    pause
}

move_cluster_data_menu() {
    local row version name port status owner data log default_base target_base target_data
    local choice target_root was_online=no
    header
    step "Кластер: Переместить данные"
    if ! cluster_rows | grep -q .; then
        warn "развёрнутых кластеров нет"
        pause
        return 0
    fi
    select_cluster "Выберите кластер" || return 0
    row="${SELECTED_CLUSTER_ROW}"
    read -r version name port status owner data log <<<"${row}"
    default_base="$(default_cluster_data_base "${version}" "${data}")"

    if ((NON_INTERACTIVE)); then
        if [[ -n "${INSTALL_DATA_ROOT}" ]]; then
            target_base="$(install_data_base_from_root "${INSTALL_DATA_ROOT}" "${version}")" || \
                die "--data-root должен содержать абсолютный путь без пробельных символов"
        else
            target_base="${default_base}"
        fi
    else
        while true; do
            printf '\nНовое расположение каталога данных:\n'
            printf '1 - Дефолтное размещение: %s/%s\n' "${default_base}" "${name}"
            printf '2 - Указать другой корневой каталог\n'
            printf '0 - Вернуться назад\n'
            read -r -p "Выбор [1]: " choice || return 0
            choice="${choice:-1}"
            case "${choice}" in
                0) return 0 ;;
                1) target_base="${default_base}" ;;
                2)
                    read -r -p "Полный путь корневого каталога (например /DATA): " target_root || return 0
                    if ! target_base="$(install_data_base_from_root "${target_root}" "${version}")"; then
                        warn "укажите абсолютный путь без пробельных символов"
                        continue
                    fi
                    ;;
                *) warn "выберите 0, 1 или 2"; continue ;;
            esac
            target_data="${target_base}/${name}"
            if ! validate_cluster_move_destination "${data}" "${target_data}" "${name}"; then
                warn "целевой каталог ${target_data} занят, совпадает с текущим либо небезопасен"
                continue
            fi
            break
        done
    fi

    target_data="${target_base}/${name}"
    validate_cluster_move_destination "${data}" "${target_data}" "${name}" || die \
        "целевой каталог ${target_data} занят, совпадает с текущим либо небезопасен"
    printf '\nКластер %s/%s:\n  текущий каталог: %s\n  новый каталог:   %s\n' \
        "${version}" "${name}" "${data}" "${target_data}"
    if ((!NON_INTERACTIVE)); then
        confirm "Остановить кластер и переместить данные?" Y || return 0
    fi

    [[ "${status}" == online* ]] && was_online=yes
    if [[ "${was_online}" == yes ]]; then
        printf 'Остановка кластера %s/%s...\n' "${version}" "${name}"
        stop_cluster_checked "${version}" "${name}"
    fi
    ensure_data_base_directory "${target_base}"
    if [[ -d "${target_data}" ]]; then
        rmdir -- "${target_data}" || die "не удалось удалить пустой целевой каталог ${target_data}"
    fi
    printf 'Перемещение %s -> %s...\n' "${data}" "${target_data}"
    mv -- "${data}" "${target_data}" || die "не удалось переместить каталог данных"
    update_cluster_data_path "${version}" "${name}" "${data}" "${target_data}"
    if [[ "${was_online}" == yes ]]; then
        printf 'Запуск кластера %s/%s из нового каталога...\n' "${version}" "${name}"
        start_cluster_checked "${version}" "${name}"
    fi
    printf 'Данные кластера %s/%s перемещены в %s. Состояние: %s.\n' \
        "${version}" "${name}" "${target_data}" \
        "$(cluster_online "${version}" "${name}" && printf online || printf down)"
    pause
}

select_cluster() {
    local prompt="$1" selection_mode="${2:-number}" choice i listing message
    local -a rows=()
    SELECTED_CLUSTER_ROW=""
    if ! listing="$(pg_lsclusters --no-header)"; then
        message="не удалось получить список кластеров командой pg_lsclusters; проверьте её сообщения выше"
    elif [[ -z "${listing//[[:space:]]/}" ]]; then
        message="развёрнутые кластеры PostgreSQL не найдены. Сначала создайте кластер (пункт 2: Кластер: Установить). Для горячего рестори требуется существующий запущенный кластер"
    else
        mapfile -t rows <<<"${listing}"
    fi
    if [[ -n "${message:-}" ]]; then
        if ((NON_INTERACTIVE)); then
            die "${message}"
        fi
        printf '\nОШИБКА: %s\n' "${message}" >&2
        pause
        return 1
    fi
    if ((NON_INTERACTIVE)); then
        ((TARGET_NAME_SET)) || die "для действия ${ACTION} укажите --cluster-name или PGCC_CLUSTER_NAME"
        SELECTED_CLUSTER_ROW="$(printf '%s\n' "${rows[@]}" | awk -v v="${pg_ver}" -v n="${cls_nm}" \
            '$1 == v && $2 == n {print; exit}')"
        [[ -n "${SELECTED_CLUSTER_ROW}" ]] || die "кластер ${pg_ver}/${cls_nm} не найден"
        return 0
    fi
    for i in "${!rows[@]}"; do
        print_cluster_row "$(printf '%3d - ' "$((i + 1))")" "${rows[i]}"
    done
    printf '  0 - Вернуться назад\n'
    read -r -p "${prompt}: " choice || return 1
    if [[ "${selection_mode}" == name-or-number && ! "${choice}" =~ ^[0-9]+$ ]]; then
        local -a matches=()
        mapfile -t matches < <(printf '%s\n' "${rows[@]}" | awk -v n="${choice}" '$2==n {print}')
        if ((${#matches[@]} == 1)); then
            SELECTED_CLUSTER_ROW="${matches[0]}"
            return 0
        fi
        warn "имя не найдено или неоднозначно; выберите кластер по номеру"
        return 1
    fi
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    ((choice == 0)) && return 1
    ((choice >= 1 && choice <= ${#rows[@]})) || return 1
    SELECTED_CLUSTER_ROW="${rows[choice-1]}"
}

cluster_pg_home() {
    local version="$1" data="$2" postgres_command="" detected_home=""
    if [[ -r "${data}/postmaster.opts" ]]; then
        read -r postgres_command _ <"${data}/postmaster.opts" || true
        postgres_command="${postgres_command#\"}"
        postgres_command="${postgres_command%\"}"
        if [[ "${postgres_command}" == */bin/postgres && -x "${postgres_command}" ]]; then
            detected_home="${postgres_command%/bin/postgres}"
            readlink -f -- "${detected_home}"
            return 0
        fi
    fi
    if [[ "${data}" == /var/lib/postgresql/tantor-free-* || "${data}" == /var/lib/postgresql/tantor-se-* || "${data}" == /var/lib/postgresql/tantor-be-* ]]; then
        printf '/opt/tantor/db/%s' "${version}"
    elif [[ -L "/usr/lib/postgresql/${version}" && -x "/usr/lib/postgresql/${version}/bin/postgres" ]]; then
        readlink -f -- "/usr/lib/postgresql/${version}"
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
    # Follow file symlinks as well as a symlink used for the backup directory.
    # Broken links and links to directories do not satisfy -type f.
    done < <(find -L "${backup_dir}" -maxdepth 1 -type f -name '*.tar.gz' -printf '%f\n' 2>/dev/null)
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

human_size_label() {
    local bytes="$1"
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
            "SELECT datname, pg_database_size(datname) FROM pg_database ${where_clause} ORDER BY datname"
    )" || return 1
    [[ -n "${output}" ]] && mapfile -t database_rows <<<"${output}"
    for row in "${database_rows[@]}"; do
        IFS=$'\t' read -r database size_bytes <<<"${row}"
        [[ -n "${database}" ]] || continue
        size="$(human_size_label "${size_bytes}")" || return 1
        CLUSTER_DATABASES+=("${database}")
        CLUSTER_DATABASE_SIZE_BYTES+=("${size_bytes}")
        CLUSTER_DATABASE_SIZES+=("${size}")
    done
}

print_cluster_databases() {
    local home="$1" socket_dir="$2" port="$3" version="$4" cluster="$5" scope="${6:-selectable}"
    local database i=0 name_width=0 number_width
    load_cluster_databases "${home}" "${socket_dir}" "${port}" "${scope}" || return 1
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
        printf '  %*d - %-*s  %9s\n' \
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
    local backup_family="${6:-${pg}}"
    printf 'backup_format=2\n'
    printf 'backup_type=%q\n' "${backup_type}"
    printf 'created_at=%q\n' "$(date --iso-8601=seconds)"
    printf 'host_name=%q\n' "$(hostname)"
    printf 'pg_family=%q\n' "${backup_family}"
    printf 'pg_version=%q\n' "${version}"
    printf 'postgres_version_text=%q\n' "${version_text}"
    printf 'cluster_name=%q\n' "${cluster}"
    printf 'cluster_port=%q\n' "${port}"
}

cluster_server_package() {
    local version="$1" home="$2" data="$3" package owner fields
    local -a owners=()
    if [[ "${home}" == /opt/tantor/* ]]; then
        # Editions share BINDIR. Identify its actual owner, never the preferred edition.
        while IFS= read -r owner; do
            package="${owner%%: /*}"
            package="${package%%:*}"
            fields="$(package_to_fields "${package}")" || continue
            [[ "${fields}" == tantor-*"|${version}" ]] || continue
            package_installed "${package}" || continue
            owners+=("${package}")
        done < <(dpkg-query -S "${home}/bin/postgres" 2>/dev/null | sort -u || true)
        if ((${#owners[@]} != 1)); then
            warn "не удалось однозначно определить пакет-владелец ${home}/bin/postgres"
            return 1
        fi
        package="${owners[0]}"
    elif [[ "${home}" == /opt/pgpro/* ]]; then
        package="postgrespro-ent-${version}-server"
    else
        # Record the installed binary owner, never an invented -server package.
        while IFS= read -r owner; do
            package="${owner%%: /*}"
            package="${package%%:*}"
            fields="$(package_to_fields "${package}")" || continue
            [[ "${fields}" == "postgresql|${version}" ]] || continue
            package_installed "${package}" || continue
            owners+=("${package}")
        done < <(dpkg-query -S "${home}/bin/postgres" 2>/dev/null | sort -u || true)
        if ((${#owners[@]} != 1)); then
            warn "не удалось однозначно определить пакет-владелец ${home}/bin/postgres"
            return 1
        fi
        package="${owners[0]}"
    fi
    printf '%s' "${package}"
}

cluster_data_root_for_builder() {
    local version="$1" cluster="$2" data="$3" suffix root
    suffix="/pg_${version}/${cluster}"
    [[ "${data}" == *"${suffix}" ]] || return 1
    root="${data%"${suffix}"}"
    printf '%s' "${root:-/}"
}

write_deb_rebuild_command() {
    local mode="$1" family="$2" version="$3" package="$4" cluster="$5"
    local port="$6" data="$7" archive="$8" database="${9:-}" data_root=""
    archive="$(realpath -ms -- "${archive}")"
    data_root="$(cluster_data_root_for_builder "${version}" "${cluster}" "${data}" || true)"

    printf '# ./create-claster-deb.sh \\\n'
    printf '#   --mode %q \\\n' "${mode}"
    printf '#   --non-interactive \\\n'
    printf '#   --pg-family %q \\\n' "${family}"
    printf '#   --pg-version %q \\\n' "${version}"
    printf '#   --package %q \\\n' "${package}"
    printf '#   --cluster-name %q \\\n' "${cluster}"
    printf '#   --port %q \\\n' "${port}"
    if [[ -n "${data_root}" ]]; then
        printf '#   --data-root %q \\\n' "${data_root}"
    fi
    printf '#   --backup-file %q' "${archive}"
    if [[ -n "${database}" ]]; then
        printf ' \\\n'
        printf '#   --database %q\n' "${database}"
    else
        printf '\n'
    fi
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

load_hot_backup_roles() {
    local home="$1" socket_dir="$2" port="$3" database="$4"
    local database_sql output row name superuser inherit create_role create_db can_login
    local replication bypass_rls connection_limit valid_until password_hash
    local -a role_rows=()
    database_sql="${database//\'/\'\'}"
    BACKUP_ROLE_NAMES=()
    BACKUP_ROLE_SUPERUSERS=()
    BACKUP_ROLE_INHERITS=()
    BACKUP_ROLE_CREATE_ROLES=()
    BACKUP_ROLE_CREATE_DBS=()
    BACKUP_ROLE_CAN_LOGINS=()
    BACKUP_ROLE_REPLICATIONS=()
    BACKUP_ROLE_BYPASS_RLS=()
    BACKUP_ROLE_CONNECTION_LIMITS=()
    BACKUP_ROLE_VALID_UNTILS=()
    BACKUP_ROLE_PASSWORD_HASHES=()
    output="$(
        runuser -u postgres -- "${home}/bin/psql" -h "${socket_dir}" -p "${port}" \
            -d postgres -A -t -F '|' -q -c \
            "WITH target_database AS (
                 SELECT oid, datdba FROM pg_database WHERE datname='${database_sql}'
             ), referenced_roles AS (
                 SELECT datdba AS role_oid FROM target_database
                 UNION
                 SELECT dependency.refobjid
                   FROM pg_shdepend AS dependency
                   CROSS JOIN target_database
                  WHERE dependency.refclassid='pg_authid'::regclass
                    AND (dependency.dbid=target_database.oid
                         OR (dependency.dbid=0
                             AND dependency.classid='pg_database'::regclass
                             AND dependency.objid=target_database.oid))
             )
             SELECT role.rolname,
                    CASE WHEN role.rolsuper THEN 'yes' ELSE 'no' END,
                    CASE WHEN role.rolinherit THEN 'yes' ELSE 'no' END,
                    CASE WHEN role.rolcreaterole THEN 'yes' ELSE 'no' END,
                    CASE WHEN role.rolcreatedb THEN 'yes' ELSE 'no' END,
                    CASE WHEN role.rolcanlogin THEN 'yes' ELSE 'no' END,
                    CASE WHEN role.rolreplication THEN 'yes' ELSE 'no' END,
                    CASE WHEN role.rolbypassrls THEN 'yes' ELSE 'no' END,
                    role.rolconnlimit,
                    COALESCE(role.rolvaliduntil::text, ''),
                    COALESCE(role.rolpassword, '')
               FROM pg_authid AS role
               JOIN referenced_roles ON referenced_roles.role_oid=role.oid
              WHERE role.rolname <> 'postgres' AND role.rolname !~ '^pg_'
              ORDER BY role.rolname"
    )" || return 1
    [[ -n "${output}" ]] && mapfile -t role_rows <<<"${output}"
    for row in "${role_rows[@]}"; do
        IFS='|' read -r name superuser inherit create_role create_db can_login \
            replication bypass_rls connection_limit valid_until password_hash <<<"${row}"
        [[ -n "${name}" ]] || continue
        BACKUP_ROLE_NAMES+=("${name}")
        BACKUP_ROLE_SUPERUSERS+=("${superuser}")
        BACKUP_ROLE_INHERITS+=("${inherit}")
        BACKUP_ROLE_CREATE_ROLES+=("${create_role}")
        BACKUP_ROLE_CREATE_DBS+=("${create_db}")
        BACKUP_ROLE_CAN_LOGINS+=("${can_login}")
        BACKUP_ROLE_REPLICATIONS+=("${replication}")
        BACKUP_ROLE_BYPASS_RLS+=("${bypass_rls}")
        BACKUP_ROLE_CONNECTION_LIMITS+=("${connection_limit}")
        BACKUP_ROLE_VALID_UNTILS+=("${valid_until}")
        BACKUP_ROLE_PASSWORD_HASHES+=("${password_hash}")
    done
}

write_hot_backup_role_metadata() {
    local i
    printf 'role_count=%q\n' "${#BACKUP_ROLE_NAMES[@]}"
    for i in "${!BACKUP_ROLE_NAMES[@]}"; do
        printf 'role_%d_name=%q\n' "$((i + 1))" "${BACKUP_ROLE_NAMES[i]}"
        printf 'role_%d_superuser=%q\n' "$((i + 1))" "${BACKUP_ROLE_SUPERUSERS[i]}"
        printf 'role_%d_inherit=%q\n' "$((i + 1))" "${BACKUP_ROLE_INHERITS[i]}"
        printf 'role_%d_create_role=%q\n' "$((i + 1))" "${BACKUP_ROLE_CREATE_ROLES[i]}"
        printf 'role_%d_create_db=%q\n' "$((i + 1))" "${BACKUP_ROLE_CREATE_DBS[i]}"
        printf 'role_%d_can_login=%q\n' "$((i + 1))" "${BACKUP_ROLE_CAN_LOGINS[i]}"
        printf 'role_%d_replication=%q\n' "$((i + 1))" "${BACKUP_ROLE_REPLICATIONS[i]}"
        printf 'role_%d_bypass_rls=%q\n' "$((i + 1))" "${BACKUP_ROLE_BYPASS_RLS[i]}"
        printf 'role_%d_connection_limit=%q\n' "$((i + 1))" "${BACKUP_ROLE_CONNECTION_LIMITS[i]}"
        printf 'role_%d_valid_until=%q\n' "$((i + 1))" "${BACKUP_ROLE_VALID_UNTILS[i]}"
        printf 'role_%d_password_hash=%q\n' "$((i + 1))" "${BACKUP_ROLE_PASSWORD_HASHES[i]}"
    done
}

measure_data_directory() {
    local data="$1" size_line bytes_line
    [[ -d "${data}" ]] || die "каталог данных не найден: ${data}"
    size_line="$(du -sh -- "${data}")" || die \
        "не удалось определить размер каталога данных ${data} командой du -sh"
    bytes_line="$(du -s --block-size=1 -- "${data}")" || die \
        "не удалось определить размер каталога данных ${data} в байтах"
    DATA_DIRECTORY_DU_SH="${size_line}"
    DATA_DIRECTORY_SIZE_BYTES="${bytes_line%%[[:space:]]*}"
    [[ "${DATA_DIRECTORY_SIZE_BYTES}" =~ ^[0-9]+$ ]] || die \
        "получен некорректный размер каталога данных ${data}"
    DATA_DIRECTORY_SIZE_PRETTY="$(human_size_label "${DATA_DIRECTORY_SIZE_BYTES}")" || die \
        "не удалось преобразовать размер каталога данных ${data}"
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

database_owner() {
    local home="$1" socket_dir="$2" port="$3" database="$4" escaped owner
    validate_database_name "${database}" || die "недопустимое имя базы данных: ${database}"
    escaped="${database//\'/\'\'}"
    owner="$(
        runuser -u postgres -- "${home}/bin/psql" -h "${socket_dir}" -p "${port}" \
            -d postgres -Atqc \
            "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='${escaped}'"
    )" || die "не удалось определить владельца базы данных ${database}"
    [[ -n "${owner}" ]] || die "база данных ${database} отсутствует"
    validate_database_name "${owner}" || die \
        "владелец базы данных ${database} имеет неподдерживаемое имя: ${owner}"
    printf '%s' "${owner}"
}

replace_database_for_restore() {
    local home="$1" socket_dir="$2" port="$3" database="$4" owner="$5"
    validate_database_name "${database}" || die "недопустимое имя базы данных: ${database}"
    case "${database}" in
        postgres|template0|template1)
            die "служебную базу ${database} нельзя заменить при горячем restore"
            ;;
    esac
    validate_database_name "${owner}" || die "недопустимое имя роли-владельца: ${owner}"
    [[ -x "${home}/bin/dropdb" ]] || die "не найден ${home}/bin/dropdb"
    [[ -x "${home}/bin/createdb" ]] || die "не найден ${home}/bin/createdb"
    printf 'Удаление существующей базы данных %s...\n' "${database}"
    runuser -u postgres -- "${home}/bin/dropdb" --force \
        --host="${socket_dir}" --port="${port}" --username=postgres -- "${database}" || die \
        "не удалось удалить существующую базу данных ${database}"
    printf 'Повторное создание базы данных %s с владельцем %s...\n' "${database}" "${owner}"
    create_database "${home}" "${socket_dir}" "${port}" "${database}" "${owner}"
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

decode_backup_metadata_value() {
    local value="$1"
    if [[ "${value}" == "''" ]]; then
        printf ''
    else
        printf '%s' "${value}" | sed -E 's/\\(.)/\1/g'
    fi
}

backup_metadata_file_value() {
    local metadata_file="$1" key="$2" line
    [[ -f "${metadata_file}" && ! -L "${metadata_file}" ]] || return 1
    while IFS= read -r line; do
        if [[ "${line%%=*}" == "${key}" ]]; then
            decode_backup_metadata_value "${line#*=}"
            return 0
        fi
    done <"${metadata_file}"
    return 1
}

create_restore_role_from_metadata() {
    local home="$1" socket_dir="$2" port="$3" role="$4" superuser="$5" inherit="$6"
    local create_role="$7" create_db="$8" can_login="$9" replication="${10}"
    local bypass_rls="${11}" connection_limit="${12}" valid_until="${13}" password_hash="${14}"
    local role_sql password_sql valid_until_sql password_clause="" valid_until_clause=""
    local superuser_option inherit_option create_role_option create_db_option login_option
    local replication_option bypass_rls_option
    validate_database_name "${role}" || die "недопустимое имя роли в метаданных: ${role}"
    [[ "${connection_limit}" =~ ^-?[0-9]+$ ]] || die \
        "некорректный лимит подключений роли ${role} в метаданных"
    case "${superuser}" in yes) superuser_option=SUPERUSER ;; no) superuser_option=NOSUPERUSER ;; *) die "некорректный признак superuser роли ${role}" ;; esac
    case "${inherit}" in yes) inherit_option=INHERIT ;; no) inherit_option=NOINHERIT ;; *) die "некорректный признак inherit роли ${role}" ;; esac
    case "${create_role}" in yes) create_role_option=CREATEROLE ;; no) create_role_option=NOCREATEROLE ;; *) die "некорректный признак create_role роли ${role}" ;; esac
    case "${create_db}" in yes) create_db_option=CREATEDB ;; no) create_db_option=NOCREATEDB ;; *) die "некорректный признак create_db роли ${role}" ;; esac
    case "${can_login}" in yes) login_option=LOGIN ;; no) login_option=NOLOGIN ;; *) die "некорректный признак can_login роли ${role}" ;; esac
    case "${replication}" in yes) replication_option=REPLICATION ;; no) replication_option=NOREPLICATION ;; *) die "некорректный признак replication роли ${role}" ;; esac
    case "${bypass_rls}" in yes) bypass_rls_option=BYPASSRLS ;; no) bypass_rls_option=NOBYPASSRLS ;; *) die "некорректный признак bypass_rls роли ${role}" ;; esac
    role_sql="${role//\"/\"\"}"
    if [[ -n "${password_hash}" ]]; then
        [[ "${password_hash}" =~ ^md5[0-9a-fA-F]{32}$ || \
           "${password_hash}" =~ ^SCRAM-SHA-256\$[0-9]+:[A-Za-z0-9+/=]+\$[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]+$ ]] || die \
            "неподдерживаемый формат хеша пароля роли ${role}"
        password_sql="${password_hash//\'/\'\'}"
        password_clause=" PASSWORD '${password_sql}'"
    fi
    if [[ -n "${valid_until}" ]]; then
        valid_until_sql="${valid_until//\'/\'\'}"
        valid_until_clause=" VALID UNTIL '${valid_until_sql}'"
    fi
    printf 'Создание отсутствующей роли %s из метаданных бэкапа...\n' "${role}"
    runuser -u postgres -- "${home}/bin/psql" -h "${socket_dir}" -p "${port}" \
        -d postgres -v ON_ERROR_STOP=1 -c \
        "CREATE ROLE \"${role_sql}\" WITH ${login_option} ${superuser_option} ${inherit_option} ${create_role_option} ${create_db_option} ${replication_option} ${bypass_rls_option} CONNECTION LIMIT ${connection_limit}${password_clause}${valid_until_clause}" || die \
        "не удалось создать роль ${role} из метаданных бэкапа"
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
    local home="$1" socket_dir="$2" port="$3" dump_file="$4" metadata_file="${5:-}"
    local role count i superuser inherit create_role create_db can_login replication bypass_rls
    local connection_limit valid_until password_hash
    local -a roles=()
    RESTORE_ADMIN_ROLE=""
    mapfile -t roles < <(dump_owner_roles "${home}" "${dump_file}" | sort -u)
    for role in "${roles[@]}"; do
        [[ "${role}" == postgres || "${role}" == pg_* ]] && continue
        if [[ -z "${RESTORE_ADMIN_ROLE}" ]]; then
            RESTORE_ADMIN_ROLE="${role}"
        fi
    done
    if [[ -n "${metadata_file}" ]]; then
        count="$(backup_metadata_file_value "${metadata_file}" role_count || printf '0')"
        [[ "${count}" =~ ^[0-9]+$ ]] && ((count <= 10000)) || die \
            "некорректное количество ролей в метаданных горячего бэкапа"
        for ((i = 1; i <= count; i++)); do
            role="$(backup_metadata_file_value "${metadata_file}" "role_${i}_name" || true)"
            [[ -n "${role}" ]] || die "в метаданных отсутствует имя роли ${i}"
            [[ "${role}" == postgres || "${role}" == pg_* ]] && continue
            role_exists "${home}" "${socket_dir}" "${port}" "${role}" && continue
            superuser="$(backup_metadata_file_value "${metadata_file}" "role_${i}_superuser" || true)"
            inherit="$(backup_metadata_file_value "${metadata_file}" "role_${i}_inherit" || true)"
            create_role="$(backup_metadata_file_value "${metadata_file}" "role_${i}_create_role" || true)"
            create_db="$(backup_metadata_file_value "${metadata_file}" "role_${i}_create_db" || true)"
            can_login="$(backup_metadata_file_value "${metadata_file}" "role_${i}_can_login" || true)"
            replication="$(backup_metadata_file_value "${metadata_file}" "role_${i}_replication" || true)"
            bypass_rls="$(backup_metadata_file_value "${metadata_file}" "role_${i}_bypass_rls" || true)"
            connection_limit="$(backup_metadata_file_value "${metadata_file}" "role_${i}_connection_limit" || true)"
            valid_until="$(backup_metadata_file_value "${metadata_file}" "role_${i}_valid_until" || true)"
            password_hash="$(backup_metadata_file_value "${metadata_file}" "role_${i}_password_hash" || true)"
            create_restore_role_from_metadata "${home}" "${socket_dir}" "${port}" "${role}" \
                "${superuser}" "${inherit}" "${create_role}" "${create_db}" "${can_login}" \
                "${replication}" "${bypass_rls}" "${connection_limit}" "${valid_until}" "${password_hash}"
        done
    fi
    for role in "${roles[@]}"; do
        [[ "${role}" == postgres || "${role}" == pg_* ]] && continue
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

# Registration labels are addresses, not evidence of the physical data version.
cluster_backup_version() {
    local registered="$1" data="$2" actual
    IFS= read -r actual <"${data}/PG_VERSION" || return 1
    [[ "${actual}" =~ ^[0-9]+$ ]] || return 1
    if [[ "${actual}" != "${registered}" ]]; then
        warn "кластер зарегистрирован как PostgreSQL ${registered}, данные имеют версию ${actual}; бэкап создаётся для PostgreSQL ${actual}"
    fi
    printf '%s' "${actual}"
}

make_cold_backup() {
    local version="$1" name="$2" port="$3" status="$4" owner="$5" data="$6" log="$7"
    local restart_after="${8:-no}" was_online=no
    local home reset_tool service_file archive timestamp meta_tmp rel cluster_package version_text
    local backup_family backup_version
    local socket_dir metadata_started=no
    local -a paths=()
    prepare_backup_directory write
    timestamp="$(date +%Y%m%d-%H%M%S)"
    backup_version="$(cluster_backup_version "${version}" "${data}")" || die "не удалось определить версию данных кластера"
    archive="${backup_dir}/$(backup_archive_name "${backup_version}" "${name}" "${timestamp}")"
    home="$(cluster_pg_home "${version}" "${data}")"
    cluster_package="$(cluster_server_package "${backup_version}" "${home}" "${data}")" || die "не определён серверный пакет кластера"
    service_file="$(cluster_service_file "${version}" "${name}" || true)"

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
    printf '\nРазмер каталога данных перед холодным бэкапом:\n  %9s  %s\n' \
        "${DATA_DIRECTORY_SIZE_PRETTY}" "${data}"

    [[ -e "/etc/postgresql/${version}/${name}" ]] && paths+=("etc/postgresql/${version}/${name}")
    rel="${data#/}"; [[ -e "${data}" ]] && paths+=("${rel}")
    rel="${log#/}"; [[ -e "${log}" ]] && paths+=("${rel}")
    [[ -n "${service_file}" ]] && paths+=("${service_file#/}")
    ((${#paths[@]})) || die "нечего помещать в резервную копию"

    IFS='|' read -r backup_family _ < <(package_to_fields "${cluster_package}") || die \
        "не удалось определить семейство серверного пакета ${cluster_package}"
    version_text="$("${home}/bin/postgres" --version)"
    CLEANUP_DIR="$(mktemp -d /tmp/create-claster.backup.XXXXXX)"
    meta_tmp="${CLEANUP_DIR}"
    {
        write_deb_rebuild_command 3 "${backup_family}" "${backup_version}" "${cluster_package}" \
            "${name}" "${port}" "${data}" "${archive}"
        write_common_backup_metadata cold "${backup_version}" "${name}" "${port}" "${version_text}" \
            "${backup_family}"
        printf 'registered_pg_version=%q\n' "${version}"
        printf 'package=%q\n' "${cluster_package}"
        printf 'cluster_owner=%q\n' "${owner}"
        printf 'data_dir=%q\n' "${data}"
        printf 'data_directory_size_bytes=%q\n' "${DATA_DIRECTORY_SIZE_BYTES}"
        printf 'data_directory_size_pretty=%q\n' "${DATA_DIRECTORY_SIZE_PRETTY}"
        printf 'data_directory_du_sh=%q\n' "${DATA_DIRECTORY_DU_SH}"
        printf 'log_file=%q\n' "${log}"
        printf 'service_file=%q\n' "${service_file}"
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
    local home socket_dir timestamp archive dump_name stage version_text database_number database_index archive_mode
    local cluster_package backup_family backup_version
    prepare_backup_directory write
    [[ "${status}" == online* ]] || die "для горячего бэкапа кластер ${version}/${cluster} должен быть запущен"
    validate_database_name "${database}" || die "недопустимое имя базы данных: ${database}"
    home="$(cluster_pg_home "${version}" "${data}")"
    [[ -x "${home}/bin/pg_dump" ]] || die "не найден ${home}/bin/pg_dump"
    backup_version="$(cluster_backup_version "${version}" "${data}")" || die "не удалось определить версию данных кластера"
    cluster_package="$(cluster_server_package "${backup_version}" "${home}" "${data}")" || die "не определён серверный пакет кластера"
    socket_dir="$(cluster_socket_directory "${port}")" || die \
        "не найден Unix-сокет запущенного кластера ${version}/${cluster} на порту ${port}"
    if [[ "${database_verified}" != yes ]]; then
        database_exists "${home}" "${socket_dir}" "${port}" "${database}" || die \
            "база данных ${database} отсутствует в кластере ${version}/${cluster}"
    fi

    timestamp="$(date +%Y%m%d-%H%M%S)"
    archive="${backup_dir}/$(hot_backup_archive_name "${backup_version}" "${database}" "${timestamp}")"
    dump_name="$(hot_backup_dump_name "${backup_version}" "${database}" "${timestamp}")"
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
    load_hot_backup_roles "${home}" "${socket_dir}" "${port}" "${database}" || die \
        "не удалось получить роли базы данных ${database}"
    IFS='|' read -r backup_family _ < <(package_to_fields "${cluster_package}") || die \
        "не удалось определить семейство серверного пакета ${cluster_package}"
    version_text="$("${home}/bin/postgres" --version)"
    {
        write_deb_rebuild_command 4 "${backup_family}" "${backup_version}" "${cluster_package}" \
            "${cluster}" "${port}" "${data}" "${archive}" "${database}"
        write_common_backup_metadata hot "${backup_version}" "${cluster}" "${port}" "${version_text}" \
            "${backup_family}"
        printf 'registered_pg_version=%q\n' "${version}"
        printf 'package=%q\n' "${cluster_package}"
        printf 'data_dir=%q\n' "${data}"
        write_hot_database_metadata "${database}" "${database_index}"
        write_hot_backup_role_metadata
    } >"${stage}/backup-info.env"
    tar -czf "${archive}" -C "${stage}" "${dump_name}" backup-info.env || die \
        "не удалось упаковать горячий дамп"
    chmod 0600 "${archive}" || die "не удалось защитить файл горячего бэкапа ${archive}"
    archive_mode="$(stat -c '%a' -- "${archive}" 2>/dev/null || true)"
    [[ "${archive_mode}" == 600 ]] || warn \
        "файловая система не применила права 0600 к ${archive}; ограничьте доступ средствами файловой системы"
    rm -rf -- "${stage}"
    CLEANUP_DIR=""
    printf 'Горячая резервная копия создана: %s\n' "${archive}"
    printf 'Файл дампа в архиве: %s\n' "${dump_name}"
    printf 'Метаданные в архиве: backup-info.env\n'
    printf 'Роли в метаданных: %s\n' "${#BACKUP_ROLE_NAMES[@]}"
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
    elif confirm "Будет остановлен кластер при создании холодного бэкапа. Продолжить?" Y; then
        make_cold_backup "${version}" "${name}" "${port}" "${status}" "${owner}" "${data}" "${log}" yes
    else
        warn "создание бэкапа отменено"
    fi
    pause
}

validate_cluster_directory_removal() {
    local path="$1" name="$2" label="$3" expected_path="${4:-}"
    local normalized parent
    normalized="$(realpath -ms -- "${path}")" || die "не удалось нормализовать путь ${path}"
    parent="$(dirname -- "${normalized}")"
    [[ "${normalized}" == /* && "$(basename -- "${normalized}")" == "${name}" && "${parent}" != / ]] || \
        die "отказ от небезопасного удаления ${label}: ${normalized}"
    if [[ -n "${expected_path}" && "${normalized}" != "${expected_path}" ]]; then
        die "неожиданный путь ${label}: ${normalized}, ожидался ${expected_path}"
    fi
    [[ ! -e "${normalized}" || -d "${normalized}" || -L "${normalized}" ]] || \
        die "${label} ${normalized} существует, но не является каталогом"
}

remove_cluster_directory_exact() {
    local path="$1" name="$2" label="$3" expected_path="${4:-}" normalized
    validate_cluster_directory_removal "${path}" "${name}" "${label}" "${expected_path}"
    normalized="$(realpath -ms -- "${path}")" || die "не удалось нормализовать путь ${path}"

    if [[ -L "${normalized}" ]]; then
        rm -f -- "${normalized}" || die "не удалось удалить симлинк ${normalized}"
        printf '%s удалён: %s (симлинк, целевой каталог не затронут).\n' "${label}" "${normalized}"
    elif [[ -d "${normalized}" ]]; then
        rm -rf --one-file-system -- "${normalized}" || die "не удалось удалить ${label} ${normalized}"
        printf '%s удалён: %s.\n' "${label}" "${normalized}"
    elif [[ -e "${normalized}" ]]; then
        die "${label} ${normalized} существует, но не является каталогом"
    else
        printf '%s уже отсутствует: %s.\n' "${label}" "${normalized}"
    fi
    [[ ! -e "${normalized}" && ! -L "${normalized}" ]] || die \
        "после очистки сохранился ${label} ${normalized}"
}

remove_cluster_service_files() {
    local version="$1" name="$2" bounded="${3:-no}" service candidate
    service="postgresql@${version}-${name}.service"
    # Never call disable for instance units. Rename defers the single bounded
    # reload until the new config/unit and preserved autostart links are ready.
    for candidate in \
        "/etc/systemd/system/${service}" \
        "/etc/systemd/system/multi-user.target.wants/${service}" \
        "/usr/lib/systemd/system/${service}" \
        "/lib/systemd/system/${service}" \
        "/.postgres/systemd/${service}" \
        "/.postgres/systemd/save/${service}"; do
        rm -f -- "${candidate}"
    done
    if [[ "${bounded}" != defer ]]; then
        timeout -k 5s 15s systemctl daemon-reload || die "не удалось обновить systemd после удаления ${service}"
    fi
}

# Fail closed before direct deletion: validate the registry, resolved boundaries
# and mount points. External WAL/tablespaces and symlink targets are not followed.
validate_cluster_delete_paths() {
    local version="$1" name="$2" data="$3" conf_dir="$4" rows other_v other_n rest other_data
    local resolved other_resolved target mounted
    [[ "${version}" =~ ^[0-9]+([.][0-9]+)?$ && "${name}" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_-]*$ ]] || die "небезопасное имя/версия кластера"
    validate_cluster_directory_removal "${conf_dir}" "${name}" "Каталог конфигурации" "/etc/postgresql/${version}/${name}"
    validate_cluster_directory_removal "${data}" "${name}" "Каталог данных"
    rows="$(pg_lsclusters --no-header)" || die "не удалось проверить реестр перед удалением"
    [[ "$(awk -v v="${version}" -v n="${name}" '$1==v && $2==n {print $6}' <<<"${rows}")" == "${data}" ]] || \
        die "регистрация/путь кластера изменились; повторите выбор"
    resolved="$(realpath -m -- "${data}")" || die "не удалось разрешить каталог данных"
    while read -r other_v other_n rest; do
        [[ -n "${other_v}" ]] || continue
        [[ "${other_v}/${other_n}" != "${version}/${name}" ]] || continue
        other_data="$(awk '{print $4}' <<<"${rest}")"
        other_resolved="$(realpath -m -- "${other_data}")" || die "не удалось проверить каталог соседнего кластера"
        [[ "${resolved}" != "${other_resolved}" && "${resolved}" != "${other_resolved}/"* && "${other_resolved}" != "${resolved}/"* ]] || \
            die "каталог данных пересекается с кластером ${other_v}/${other_n}; удаление запрещено"
    done <<<"${rows}"
    # A nested bind mount can share the same filesystem; --one-file-system alone
    # is not sufficient. Refuse mounted cluster trees, preserving all their files.
    mounted="$(findmnt -rn -o TARGET)" || die "не удалось проверить точки монтирования"
    for target in "${data}" "${conf_dir}"; do
        [[ ! -L "${target}" ]] || continue
        resolved="$(realpath -m -- "${target}")" || die "не удалось разрешить ${target}"
        while IFS= read -r other_resolved; do
            [[ "${other_resolved}" != "${resolved}" && "${other_resolved}" != "${resolved}/"* ]] || \
                die "в каталоге кластера есть точка монтирования ${other_resolved}; сначала отключите её"
        done <<<"${mounted}"
    done
}

delete_cluster_checked() {
    local version="$1" name="$2" owner="$3" data="$4" log="$5" home="$6"
    local conf_dir="/etc/postgresql/$1/$2" service="postgresql@$1-$2.service" state rc=0 path
    validate_cluster_delete_paths "${version}" "${name}" "${data}" "${conf_dir}"
    [[ -f "${data}/PG_VERSION" ]] || die "нет PG_VERSION в ${data}; автоматическое удаление повреждённого/постороннего каталога запрещено"
    [[ -x "${home}/bin/pg_ctl" ]] || die "не найден pg_ctl для проверки остановки кластера"
    stop_cluster_checked "${version}" "${name}"
    # pg_ctl status returns 3 only for a stopped server. All other failures,
    # including timeout/permission errors, must preserve both data and config.
    run_parsec_aware timeout -k 5s 15s runuser -u "${owner}" -- "${home}/bin/pg_ctl" -D "${data}" status || rc=$?
    [[ "${rc}" == 3 ]] || die "не подтверждена остановка ${version}/${name} (pg_ctl status=${rc}); файлы сохранены"
    state="$(timeout -k 5s 15s systemctl show "${service}" -p ActiveState -p MainPID)" || die "не удалось проверить службу ${service}"
    grep -qx 'MainPID=0' <<<"${state}" && grep -Eq '^ActiveState=(inactive|failed)$' <<<"${state}" || \
        die "служба ${service} ещё работает или меняет состояние; файлы сохранены"
    validate_cluster_delete_paths "${version}" "${name}" "${data}" "${conf_dir}"
    for path in "${data}/pg_wal" "${data}/pg_xlog" "${data}/pg_tblspc/"*; do
        [[ ! -L "${path}" ]] || warn "внешние данные по ссылке ${path} сохраняются; при необходимости удалите их отдельно"
    done
    remove_cluster_directory_exact "${data}" "${name}" "Каталог данных"
    remove_cluster_directory_exact "${conf_dir}" "${name}" "Каталог конфигурации" "${conf_dir}"
    remove_cluster_directory_exact "/etc/systemd/system/${service}.d" "${service}.d" "Дополнения службы" "/etc/systemd/system/${service}.d"
    path="/etc/syslog-ng/conf.d/mod-astra-postgres-${version}-${name}.conf"
    if [[ -e "${path}" || -L "${path}" ]]; then
        rm -f -- "${path}" || die "не удалось удалить ${path}"
        warn "конфиг syslog-ng выбранного кластера удалён; reload не вызывается во избежание зависания Astra. Изменение применится при следующей штатной перезагрузке конфигурации syslog-ng"
    fi
    # A nonstandard setup may share one log across registered clusters.
    local rows
    rows="$(pg_lsclusters --no-header)" || die "не удалось проверить соседние журналы; журнал ${log} сохранён"
    if awk -v p="${log}" -v v="${version}" -v n="${name}" '$7==p && !($1==v && $2==n) {found=1} END {exit !found}' <<<"${rows}"; then
        warn "журнал ${log} используется другим кластером и сохранён"
    else
    case "${log}" in
        /var/log/postgresql/*-"${version}"-"${name}".log) rm -f -- "${log}" || die "не удалось удалить журнал ${log}" ;;
        *) warn "нестандартный журнал ${log} сохранён; проверьте его отдельно" ;;
    esac
    fi
    remove_cluster_service_files "${version}" "${name}" yes
    printf 'Удаление выполнено без pg_dropcluster.\n'
}

delete_cluster_menu() {
    local row version name port status owner data log home
    header
    step "Удаление: Выбор кластера"
    select_cluster "Выберите кластер" || return 0
    row="${SELECTED_CLUSTER_ROW}"
    read -r version name port status owner data log <<<"${row}"
    printf '\nВыбран кластер %s/%s, данные: %s\n' "${version}" "${name}" "${data}"
    if ((NON_INTERACTIVE)) && [[ "${BACKUP_BEFORE_DELETE}" == yes ]]; then
        make_cold_backup "${version}" "${name}" "${port}" "${status}" "${owner}" "${data}" "${log}" no
    elif ((NON_INTERACTIVE)); then
        printf 'Удаление выполняется без резервной копии по заданным параметрам.\n'
    elif confirm "Будет остановлен кластер. Сделать холодный бэкап перед удалением?" Y; then
        make_cold_backup "${version}" "${name}" "${port}" "${status}" "${owner}" "${data}" "${log}" no
    elif ! confirm "Будет остановлен кластер. Удалить кластер БЕЗ резервной копии?" N; then
        warn "удаление отменено"
        pause
        return 0
    fi
    printf 'Удаляется только журнал выбранного кластера: %s\n' "${log}"
    printf 'Каталог /var/log/postgresql и журналы других кластеров сохраняются.\n'
    home="$(cluster_pg_home "${version}" "${data}")" || die "не удалось определить сервер кластера"
    delete_cluster_checked "${version}" "${name}" "${owner}" "${data}" "${log}" "${home}"
    printf 'Кластер %s/%s удалён.\n' "${version}" "${name}"
    pause
}

drop_database_checked() {
    local version="$1" cluster="$2" port="$3" status="$4" data="$5" database="$6"
    local home socket_dir
    [[ "${status}" == online* ]] || die \
        "для удаления БД кластер ${version}/${cluster} должен быть запущен"
    validate_database_name "${database}" || die "недопустимое имя базы данных: ${database}"
    [[ "${database}" != postgres ]] || die "удаление служебной базы postgres запрещено"
    home="$(cluster_pg_home "${version}" "${data}")"
    [[ -x "${home}/bin/dropdb" ]] || die "не найден ${home}/bin/dropdb"
    socket_dir="$(cluster_socket_directory "${port}")" || die \
        "не найден Unix-сокет кластера ${version}/${cluster} на порту ${port}"
    runuser -u postgres -- "${home}/bin/dropdb" --force \
        --host="${socket_dir}" --port="${port}" --username=postgres -- "${database}" || die \
        "не удалось удалить базу данных ${database} из кластера ${version}/${cluster}"
}

delete_database_menu() {
    local row version name port status owner data log home socket_dir database default_database
    header
    step "Удаление: Выбор базы данных"
    select_cluster "Выберите кластер" || return 0
    row="${SELECTED_CLUSTER_ROW}"
    read -r version name port status owner data log <<<"${row}"
    printf '\nВыбран кластер %s/%s, данные: %s\n' "${version}" "${name}" "${data}"
    if [[ "${status}" != online* ]]; then
        warn "для удаления БД кластер ${version}/${name} должен быть запущен"
        pause
        return 0
    fi
    home="$(cluster_pg_home "${version}" "${data}")"
    socket_dir="$(cluster_socket_directory "${port}")" || {
        warn "не найден Unix-сокет кластера ${version}/${name} на порту ${port}"
        pause
        return 0
    }
    if ! print_cluster_databases "${home}" "${socket_dir}" "${port}" "${version}" "${name}"; then
        warn "не удалось получить список БД кластера ${version}/${name}"
        pause
        return 0
    fi
    ((${#CLUSTER_DATABASES[@]})) || {
        warn "в кластере нет доступных баз данных"
        pause
        return 0
    }
    printf 'Служебная база postgres отображается в списке, но её удаление запрещено.\n'
    default_database=1
    if ! default_database="$(database_number_in_loaded_list "${name}")"; then
        default_database=1
    fi
    select_existing_database "Выберите удаляемую БД (номер из списка или точное имя)" \
        "${default_database}" || return 0
    database="${SELECTED_DATABASE}"
    if [[ "${database}" == postgres ]]; then
        warn "удаление служебной базы postgres запрещено"
        pause
        return 0
    fi
    if confirm "Сделать горячий бэкап базы ${database} перед удалением?" Y; then
        make_hot_backup "${version}" "${name}" "${port}" "${status}" "${data}" \
            "${database}" yes
    elif ! confirm "Удалить базу ${database} БЕЗ резервной копии?" N; then
        warn "удаление базы данных отменено"
        pause
        return 0
    fi
    confirm "Удалить базу ${database} из кластера ${version}/${name}? Все данные БД будут потеряны" N || {
        warn "удаление базы данных отменено"
        pause
        return 0
    }
    drop_database_checked "${version}" "${name}" "${port}" "${status}" "${data}" "${database}"
    printf 'База данных %s удалена из кластера %s/%s.\n' \
        "${database}" "${version}" "${name}"
    pause
}

delete_menu() {
    local choice
    if ((NON_INTERACTIVE)); then
        delete_cluster_menu
        return 0
    fi
    header
    step "Удаление: Выбор режима"
    printf '%s\n' \
        '1 - Кластер: Удалить' \
        '2 - База данных: Удалить' \
        '0 - Вернуться назад'
    read -r -p "Что удалить: " choice || return 0
    case "${choice}" in
        1) delete_cluster_menu ;;
        2) delete_database_menu ;;
        0) return 0 ;;
        *) warn "неверный режим удаления"; pause ;;
    esac
}

restore_hot_backup() {
    local archive="$1" filename source_version source_database timestamp dump_name
    local row version name port status owner data log home socket_dir target_database stage metadata_file=""
    local create_target_database=no target_database_owner=""
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
        case "${target_database}" in
            postgres|template0|template1)
                if ((NON_INTERACTIVE)); then
                    die "служебную базу ${target_database} нельзя заменить при горячем restore"
                fi
                warn "служебную базу ${target_database} нельзя заменить при горячем restore"
                pause
                return 0
                ;;
        esac
        target_database_owner="$(database_owner \
            "${home}" "${socket_dir}" "${port}" "${target_database}")"
        printf 'Владелец существующей базы: %s\n' "${target_database_owner}"
    fi
    if ((NON_INTERACTIVE)) && [[ "${create_target_database}" == no ]]; then
        [[ "${OVERWRITE_EXISTING}" == yes ]] || die \
            "для горячего restore поверх существующей БД задайте --overwrite yes или PGCC_OVERWRITE=yes"
    elif ((NON_INTERACTIVE)); then
        :
    elif [[ "${create_target_database}" == yes ]]; then
        confirm "Создать базу ${target_database} и восстановить горячий бэкап?" Y || return 0
    else
        confirm "Удалить существующую БД, создать её заново и восстановить горячий бэкап?" N || return 0
    fi

    validate_hot_backup_archive_contents "${archive}" "${dump_name}"
    CLEANUP_DIR="$(mktemp -d /tmp/create-claster.hot-restore.XXXXXX)"
    stage="${CLEANUP_DIR}"
    if tar -tzf "${archive}" | grep -Fxq 'backup-info.env'; then
        tar -xzf "${archive}" -C "${stage}" -- "${dump_name}" backup-info.env || die \
            "не удалось извлечь горячий дамп и его метаданные"
        [[ -f "${stage}/backup-info.env" && ! -L "${stage}/backup-info.env" ]] || die \
            "извлечённый метафайл не является обычным файлом"
        metadata_file="${stage}/backup-info.env"
    else
        tar -xzf "${archive}" -C "${stage}" -- "${dump_name}" || die \
            "не удалось извлечь горячий дамп"
    fi
    [[ -f "${stage}/${dump_name}" && ! -L "${stage}/${dump_name}" ]] || die \
        "извлечённый дамп не является обычным файлом"
    chown -R postgres:postgres "${stage}"
    "${home}/bin/pg_restore" --list "${stage}/${dump_name}" >/dev/null || die \
        "не удалось прочитать оглавление горячего дампа"
    ensure_restore_roles "${home}" "${socket_dir}" "${port}" "${stage}/${dump_name}" "${metadata_file}"
    if [[ "${create_target_database}" == yes ]]; then
        printf 'Создание базы данных %s в кластере %s/%s...\n' \
            "${target_database}" "${version}" "${name}"
        create_database "${home}" "${socket_dir}" "${port}" "${target_database}" \
            "${RESTORE_ADMIN_ROLE:-postgres}"
    else
        replace_database_for_restore "${home}" "${socket_dir}" "${port}" \
            "${target_database}" "${target_database_owner}"
    fi
    printf 'Восстановление базы %s в кластере %s/%s...\n' \
        "${target_database}" "${version}" "${name}"
    runuser -u postgres -- "${home}/bin/pg_restore" --verbose --exit-on-error \
        --host="${socket_dir}" --port="${port}" --dbname="${target_database}" \
        "${stage}/${dump_name}" || die \
        "не удалось восстановить горячий бэкап в базу ${target_database}"
    rm -rf -- "${stage}"
    CLEANUP_DIR=""
    printf 'Горячий бэкап восстановлен в %s/%s, база %s.\n' \
        "${version}" "${name}" "${target_database}"
    pause
}

restore_log_directory_permissions() {
    # Restore Astra postgresql-common defaults on the shared directory only.
    # Never recurse into existing logs or follow an archive-supplied final symlink.
    local log_dir=/var/log/postgresql
    [[ ! -L "${log_dir}" ]] || die "каталог журналов ${log_dir} является символьной ссылкой; права не изменены"
    mkdir -p -- "${log_dir}" || die "не удалось создать каталог журналов ${log_dir}"
    chown root:postgres -- "${log_dir}" || die "не удалось установить владельца root:postgres для ${log_dir}"
    chmod 1775 -- "${log_dir}" || die "не удалось установить права 1775 для ${log_dir}"
}

restore_menu() {
    local choice archive stage info service_file version name package entry unit_dir candidate
    local cluster_name cluster_port pg_version data_dir log_file
    local original_name original_port original_data_dir original_conf_dir
    local restore_name restore_port restore_data_dir restore_conf_dir restore_service_file file conflict
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
    local registered_pg_version=""
    source "${stage}/backup-info.env"
    version="${pg_version:?}"
    original_name="${cluster_name:?}"
    original_port="${cluster_port:?}"
    original_data_dir="${data_dir:?}"
    package="${package:?}"
    registered_pg_version="${registered_pg_version:-${version}}"
    [[ "${registered_pg_version}" =~ ^[0-9]+$ ]] || die "недопустимая версия регистрации в бэкапе"
    original_conf_dir="/etc/postgresql/${registered_pg_version}/${original_name}"
    validate_identifier "${original_name}" || die "в метаданных бэкапа недопустимое имя кластера"
    [[ "${original_data_dir}" == */"${original_name}" ]] || die "каталог данных в бэкапе не соответствует имени кластера"

    printf 'Бэкап: PostgreSQL %s, кластер %s, порт %s, пакет %s\n' \
        "${version}" "${original_name}" "${original_port}" "${package}"
    if ((NON_INTERACTIVE)); then
        if ((TARGET_NAME_SET)); then restore_name="${cls_nm}"; else restore_name="${original_name}"; fi
        if ((TARGET_PORT_SET)); then restore_port="${cls_pt}"; else restore_port="${original_port}"; fi
        validate_identifier "${restore_name}" || die "недопустимое имя кластера: ${restore_name}"
        restore_data_dir="$(cold_restore_data_path "${package}" "${original_data_dir}" "${original_name}" "${restore_name}")" || die "не удалось определить каталог данных для рестори"
        if conflict="$(restore_target_conflict "${version}" "${restore_name}" "${restore_data_dir}")"; then
            die "${conflict}. Холодный рестори поверх существующего кластера запрещён"
        fi
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
            restore_data_dir="$(cold_restore_data_path "${package}" "${original_data_dir}" "${original_name}" "${restore_name}")" || die "не удалось определить каталог данных для рестори"
            if conflict="$(restore_target_conflict "${version}" "${restore_name}" "${restore_data_dir}")"; then
                warn "АЛАРМ: ${conflict}; введите другое имя кластера"
                continue
            fi
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
    restore_conf_dir="/etc/postgresql/${version}/${restore_name}"
    printf 'Цель: PostgreSQL %s, кластер %s, порт %s\n' "${version}" "${restore_name}" "${restore_port}"
    printf 'Каталог данных: %s\n' "${restore_data_dir}"

    if ((!NON_INTERACTIVE)); then
        confirm "Восстановить кластер с указанными именем и портом?" Y || return 0
    fi
    server_package_installed "${package}" || install_package "${package}"
    SELECTED_PACKAGE="${package}"
    configure_selected_package
    stop_disable_vendor_service "${SELECTED_PACKAGE}"
    prepare_postgres_root
    if conflict="$(restore_target_conflict "${version}" "${restore_name}" "${restore_data_dir}")"; then
        die "${conflict}. Рестори остановлен до распаковки архива"
    fi
    while IFS= read -r entry; do
        [[ "${entry}" == root/* ]] || die "недопустимый путь в архиве: ${entry}"
        [[ "${entry}" != *'/../'* && "${entry}" != *'/..' && "${entry}" != root/.. ]] || \
            die "выход за корень в пути архива: ${entry}"
    done < <(tar -tzf "${archive}")
    # Only standard roots are changed here (strictly limited alphabet above).
    # Custom roots are retained, so no user-supplied path is used as a regexp.
    if [[ "${original_data_dir%/*}" != "${restore_data_dir%/*}" ]]; then
        transform_args+=(--transform "s#^root${original_data_dir%/*}/#root${restore_data_dir%/*}/#")
    fi
    if [[ "${restore_name}" != "${original_name}" ]]; then
        transform_args+=(--transform "s#/${original_name}/#/${restore_name}/#g")
        transform_args+=(--transform "s#/${original_name}\$#/${restore_name}#")
        transform_args+=(--transform "s#-${original_name}\\.service\$#-${restore_name}.service#")
        transform_args+=(--transform "s#-${original_name}\\.log\$#-${restore_name}.log#")
    fi
    transform_args+=(--transform "s#^root/etc/postgresql/${registered_pg_version}/#root/etc/postgresql/${version}/#")
    transform_args+=(--transform "s#postgresql@${registered_pg_version}-#postgresql@${version}-#g")
    tar "${transform_args[@]}" --keep-directory-symlink -xzf "${archive}" -C / --strip-components=1 \
        --exclude='root/backup-info.env' --exclude='root/.postgres/systemd/save'

    restore_log_directory_permissions

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

    restore_service_file=""
    unit_dir="$(systemd_unit_dir)"
    # A saved unit may be used only from this backup, never from the host cache.
    if [[ "${service_file:-}" == /.postgres/systemd/save/* ]]; then
        if tar -xOzf "${archive}" -- "root${service_file}" >"${stage}/archived-unit.service" 2>/dev/null && [[ -s "${stage}/archived-unit.service" ]]; then
            restore_service_file="${unit_dir}/postgresql@${version}-${restore_name}.service"
            cp -- "${stage}/archived-unit.service" "${restore_service_file}"
        fi
    fi
    if [[ -n "${service_file:-}" && "${service_file}" != /.postgres/systemd/save/* ]]; then
        candidate="$(dirname -- "${service_file}")/postgresql@${version}-${restore_name}.service"
        [[ -f "${candidate}" ]] && restore_service_file="${candidate}"
    fi
    if [[ -z "${restore_service_file}" ]]; then
        restore_service_file="$(cluster_service_file "${version}" "${restore_name}" no || true)"
    fi
    unit_dir="$(systemd_unit_dir)"
    if [[ -z "${restore_service_file}" ]]; then
        restore_service_file="${unit_dir}/postgresql@${version}-${restore_name}.service"
        write_cluster_unit_file "${restore_service_file}" "${version}" "${restore_name}" "${restore_data_dir}"
        printf 'В старом бэкапе отсутствует systemd unit; создан новый %s.\n' \
            "${restore_service_file}"
    fi
    replace_literal_in_file "${original_data_dir}" "${restore_data_dir}" "${restore_service_file}"
    replace_literal_in_file "${original_conf_dir}" "${restore_conf_dir}" "${restore_service_file}"
    replace_literal_in_file "${registered_pg_version}-${original_name}" "${version}-${restore_name}" "${restore_service_file}"
    # Replace the cache entry itself, never follow an old cache symlink.
    cp --remove-destination -- "${restore_service_file}" "/.postgres/systemd/save/$(basename -- "${restore_service_file}")"
    ensure_symlink "${restore_service_file}" "/.postgres/systemd/$(basename -- "${restore_service_file}")"
    systemctl daemon-reload
    systemctl enable "$(basename -- "${restore_service_file}")"
    start_cluster_checked "${version}" "${restore_name}"
    repair_wsl_registered_syslog
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
    local choice row version name port status owner data log home socket_dir i
    local cluster_size_bytes cluster_size
    local -a rows=()
    if ((NON_INTERACTIVE)); then
        header
        step "Информация: о развернутых кластерах"
        pg_lsclusters || true
        return 0
    fi
    while true; do
        header
        step "Информация: о развернутых кластерах"
        mapfile -t rows < <(cluster_rows)
        if ((${#rows[@]} == 0)); then
            printf 'Развёрнутых кластеров нет.\n\n0 - Вернуться назад\n'
            read -r -p "Выбор: " _ || true
            return 0
        fi
        for i in "${!rows[@]}"; do
            print_cluster_row "$(printf '%3d - ' "$((i + 1))")" "${rows[i]}"
        done
        printf '  0 - Вернуться назад\n'
        read -r -p "Выберите кластер: " choice || return 0
        if [[ ! "${choice}" =~ ^[0-9]+$ ]] || \
           ((choice < 0 || choice > ${#rows[@]})); then
            clear_screen
            return 0
        fi
        ((choice == 0)) && return 0

        row="${rows[choice - 1]}"
        read -r version name port status owner data log <<<"${row}"
        header
        step "Информация: базы данных кластера ${version}/${name}"
        print_cluster_row 'Кластер: ' "${row}"
        if [[ -d "${data}" ]] && \
           cluster_size_bytes="$(du -s --block-size=1 -- "${data}" 2>/dev/null)"; then
            cluster_size_bytes="${cluster_size_bytes%%[[:space:]]*}"
            if cluster_size="$(human_size_label "${cluster_size_bytes}")"; then
                printf '\nРазмер каталога данных кластера:\n  %9s  %s\n' \
                    "${cluster_size}" "${data}"
            else
                warn "не удалось преобразовать размер каталога данных ${data}"
            fi
        else
            warn "не удалось определить размер каталога данных ${data}"
        fi
        if [[ "${status}" != online* ]]; then
            warn "кластер ${version}/${name} не запущен; получить список БД невозможно"
            printf '\n0 - Вернуться к выбору кластера\n'
        else
            home="$(cluster_pg_home "${version}" "${data}")"
            socket_dir="$(cluster_socket_directory "${port}" || true)"
            if [[ ! -x "${home}/bin/psql" ]]; then
                warn "не найден psql для кластера ${version}/${name}: ${home}/bin/psql"
                printf '\n0 - Вернуться к выбору кластера\n'
            elif [[ -z "${socket_dir}" ]]; then
                warn "не найден локальный сокет кластера ${version}/${name} на порту ${port}"
                printf '\n0 - Вернуться к выбору кластера\n'
            elif ! print_cluster_databases "${home}" "${socket_dir}" "${port}" "${version}" "${name}" all; then
                warn "не удалось получить список БД кластера ${version}/${name}"
                printf '\n0 - Вернуться к выбору кластера\n'
            elif ((${#CLUSTER_DATABASES[@]} == 0)); then
                printf '  0 - Вернуться к выбору кластера\n'
            fi
        fi
        read -r -p "Выбор: " _ || return 0
        clear_screen
    done
}

select_sql_file() {
    local file choice resolved i
    local -a files=()
    SELECTED_SQL_FILE=""
    if [[ -d "${backup_dir}" ]]; then
        while IFS= read -r -d '' file; do
            [[ -r "${file}" ]] && files+=("${file}")
        done < <(find -L "${backup_dir}" -maxdepth 1 -type f -name '*.sql' -print0 2>/dev/null | sort -z)
    fi
    printf 'SQL-файлы в %s:\n' "${backup_dir}"
    for i in "${!files[@]}"; do
        printf '%3d - %s\n' "$((i + 1))" "${files[i]##*/}"
    done
    printf '  0 - Вернуться назад\nМожно ввести относительный или полный путь к .sql, также при пустом списке.\n'
    read -r -p 'Выберите номер SQL-файла или введите путь: ' choice || return 2
    [[ -n "${choice}" && "${choice}" != 0 ]] || return 1
    file=""
    if [[ "${choice}" =~ ^[0-9]+$ ]]; then
        for i in "${!files[@]}"; do
            [[ "${choice}" != "$((i + 1))" ]] || file="${files[i]}"
        done
    elif [[ "${choice}" == /* || -f "${choice}" ]]; then
        file="${choice}"
    else
        file="${backup_dir%/}/${choice}"
    fi
    if [[ "${file}" == *.sql ]] && resolved="$(realpath -e -- "${file}" 2>/dev/null)" &&
        [[ -f "${resolved}" && -r "${resolved}" && "${resolved}" == *.sql ]]; then
        SELECTED_SQL_FILE="${resolved}"
        return 0
    fi
    warn 'требуется доступный для чтения обычный файл .sql'
    pause
    return 1
}

execute_sql_checked() {
    local version="$1" name="$2" port="$3" data="$4" database="$5" file="$6"
    local listing row home socket_dir
    # Recheck the confirmed target; never silently switch to another port/data-dir.
    listing="$(pg_lsclusters --no-header)" || { warn 'не удалось перепроверить кластер'; return 1; }
    row="$(printf '%s\n' "${listing}" | awk -v v="${version}" -v n="${name}" '$1==v && $2==n {print}')"
    local current_version current_name current_port current_status current_owner current_data current_log
    read -r current_version current_name current_port current_status current_owner current_data current_log <<<"${row}"
    [[ "${current_port}" == "${port}" && "${current_data}" == "${data}" && "${current_status}" == online* ]] || {
        warn 'кластер остановлен или его параметры изменились; выберите цель заново'; return 1;
    }
    [[ -f "${file}" && -r "${file}" && ! -L "${file}" ]] || { warn 'SQL-файл больше недоступен'; return 1; }
    home="$(cluster_pg_home "${version}" "${data}")" || return 1
    socket_dir="$(cluster_socket_directory "${port}")" || { warn 'Unix-сокет кластера не найден'; return 1; }
    database_exists "${home}" "${socket_dir}" "${port}" "${database}" || {
        warn 'база данных больше недоступна'; return 1;
    }
    # Root opens the selected file; only the postgres child interprets trusted SQL.
    runuser -u postgres -- "${home}/bin/psql" -X --no-password \
        -h "${socket_dir}" -p "${port}" -d "${database}" \
        --set=ON_ERROR_STOP=1 --file=- <"${file}"
}

execute_sql_menu() {
    local page=cluster result row version name port status owner data log home socket_dir database file answer
    while true; do
        header
        step 'Кластер: Выполнить SQL'
        case "${page}" in
            cluster)
                select_cluster 'Выберите кластер' name-or-number || return 0
                row="${SELECTED_CLUSTER_ROW}"
                read -r version name port status owner data log <<<"${row}"
                [[ "${status}" == online* ]] || { warn 'кластер должен быть запущен'; pause; continue; }
                home="$(cluster_pg_home "${version}" "${data}")" || { warn 'не найден сервер кластера'; pause; continue; }
                socket_dir="$(cluster_socket_directory "${port}")" || { warn 'Unix-сокет кластера не найден'; pause; continue; }
                page=database
                ;;
            database)
                print_cluster_databases "${home}" "${socket_dir}" "${port}" "${version}" "${name}" || {
                    warn 'не удалось получить список БД'; pause; page=cluster; continue;
                }
                select_existing_database 'Выберите БД (номер или точное имя; 0 — назад)' 0 || {
                    page=cluster; continue;
                }
                database="${SELECTED_DATABASE}"
                page=file
                ;;
            file)
                printf 'Цель: %s/%s/%s\n' "${version}" "${name}" "${database}"
                if select_sql_file; then
                    file="${SELECTED_SQL_FILE}"
                    page=confirm
                else
                    result=$?
                    ((result != 2)) || return 0
                    page=database
                fi
                ;;
            confirm)
                printf 'Файл: %s\nИспользуйте только доверенный SQL. Он выполняется от postgres; ошибка может оставить частичные изменения.\n0 - Вернуться назад\n' "${file}"
                read -r -p "${version}/${name}/${database}: выполнить сценарий ${file##*/} ? [N/y] : " answer || return 0
                if [[ "${answer}" == 0 ]]; then page=file; continue; fi
                [[ "${answer}" =~ ^[Yy]$ ]] || { printf 'Выполнение SQL отменено.\n'; return 0; }
                if execute_sql_checked "${version}" "${name}" "${port}" "${data}" "${database}" "${file}"; then
                    printf 'SQL-сценарий успешно выполнен: %s/%s/%s.\n' "${version}" "${name}" "${database}"
                else
                    result=$?
                    printf 'ОШИБКА: SQL-сценарий не выполнен успешно (код %s); возможны частичные изменения.\n' "${result}" >&2
                fi
                pause
                return 0
                ;;
        esac
    done
}

change_cluster_menu() {
    local choice
    while true; do
        header
        step "Кластер: Изменить"
        printf '%s\n' \
            '0 - Вернуться назад' \
            '1 - Кластер: Переименовать' \
            '2 - Кластер: Переключить порт' \
            '3 - Кластер: Переместить данные' \
            '4 - Кластер: Выполнить SQL'
        read -r -p "Выбор: " choice || return 0
        case "${choice}" in
            1) rename_cluster_menu ;;
            2) change_port_menu ;;
            3) move_cluster_data_menu ;;
            4) execute_sql_menu ;;
            *) return 0 ;;
        esac
    done
}

main_menu() {
    local choice skip_first_header="${1:-0}"
    while true; do
        if ((skip_first_header)); then
            skip_first_header=0
        else
            header
        fi
        step "Выбор действия: <${SELECTED_PACKAGE:-сервер не выбран}>"
        printf '%s\n' \
            '0 - Выход' \
            '1 - Информация: о развернутых кластерах' \
            '2 - Кластер: Установить' \
            '3 - Кластер: Остановить/Запустить' \
            '4 - Кластер: Изменить' \
            '5 - Кластер: Бэкап' \
            '6 - Кластер: Рестори' \
            '7 - Кластер: Удалить'
        read -r -p "Выбор: " choice || exit 0
        case "${choice}" in
            0) exit 0 ;;
            1) info_menu ;;
            2) install_menu ;;
            3) cluster_power_menu ;;
            4) change_cluster_menu ;;
            5) backup_menu ;;
            6) restore_menu ;;
            7) delete_menu ;;
            *) clear_screen; exit 0 ;;
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
    select_config
    require_root "$@"
    load_config
    apply_runtime_options
    if ((!NON_INTERACTIVE)); then
        header
        step "Подготовка пакетов"
    fi
    STARTUP_PREPARATION=1
    command -v apt-get >/dev/null 2>&1 || die "поддерживается система пакетов APT"
    ensure_postgresql_common
    if [[ "${ACTION}" == info && "${NON_INTERACTIVE}" == 1 ]]; then
        STARTUP_PREPARATION=0
        command -v pg_lsclusters >/dev/null 2>&1 || die "не найдена команда pg_lsclusters"
        info_menu
        return 0
    fi
    # Backups resolve the existing cluster's binaries; do not select/install a
    # different edition from global defaults when invoked by the cron wrapper.
    if [[ "${NON_INTERACTIVE}" == 0 || ("${ACTION}" != restore && "${ACTION}" != backup) ]]; then
        select_or_install_server
        prepare_postgres_root
    fi
    STARTUP_PREPARATION=0
    repair_wsl_registered_syslog
    if ((NON_INTERACTIVE)); then
        case "${ACTION}" in
            info) info_menu ;;
            install) install_menu ;;
            port) change_port_menu ;;
            move-data) move_cluster_data_menu ;;
            backup) backup_menu ;;
            restore) restore_menu ;;
            delete) delete_menu ;;
        esac
    else
        main_menu 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
