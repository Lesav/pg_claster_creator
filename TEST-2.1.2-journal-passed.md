# Тестирование pg_claster_creator 2.1.2 — OK

Дата: 2026-09-09, MSK. Идентификатор: 163900.
Итог: **105/105 автоматических фаз OK** (15 на каждом из 7 стендов).
Сохранение прежних бэкапов, настройка ссылки и независимая финальная проверка также успешны.
После проверки результатов журнал переименован в test-2.1.2-journal-20260909-163900-passed.md.

## Область проверки

Выполнен сценарий последнего запроса: сохранить содержимое /.postgres/backup, заменить каталог ссылкой на общий каталог Windows, удалить все кластеры и /DATA, /BACKUP до теста, создать чистый кластер через create-claster.sh, создать asvd, применить scheme_asvd.r586.sql, создать горячий/холодный бэкапы, проверить смену TCP-порта и перенос в /DATA, удалить все кластеры и оба каталога после завершения.

Это не весь расширенный план TEST.md: установка DEB, полный рестори новых архивов и fault-injection не входили в данный сценарий. Горячий архив проверен через tar/метаданные и pg_restore --list; холодный через tar/метаданные и успешный повторный запуск исходного кластера.

Для развёртывания не использовался старый 16-asvd-20260906-190608-dmp.tar.gz. Этот файл только скопирован/сравнен при выполнении отдельного требования сохранить старые бэкапы; SQL-тест его не открывал. База создана исключительно из /mnt/d/Ai/pg_claster_creator/tmp/scheme_asvd.r586.sql с psql -X --set=ON_ERROR_STOP=1.

## Сохранение прежних бэкапов

До любого удаления содержимое /.postgres/backup сохранено в /mnt/d/Ai/pg_claster_creator.backup.
В smolensk был один архив, в ALSE-1.7.9-UU1 три, включая его идентичную копию; на остальных WSL каталог был пуст или отсутствовал.
Получено три уникальных файла. Копии проверялись побайтно (diff/cmp); идентичный файл не перезаписывался. Конфликтов разных файлов с одинаковым именем не обнаружено.

| Сохранённый файл | SHA-256 |
|---|---|
| 16-asvd-20260906-190608-dmp.tar.gz | `15b74b79e5cf1921655e2dcaeed1c120ca6bc720fb7bb1747e1371e6c8e17c55` |
| 17-asvd-20260909-154933-dmp.tar.gz | `d47d3275dabc42cea74fac8cd7792240c6ce05396c4d5e265df1f07c74560db9` |
| 17-sybsys-20260909-154530.tar.gz | `39e4840c7b12aa2889ba2109c3b46494c8f718bfb12a5e0f0d88859620bc0f6c` |

На всех семи WSL создана и после теста сохранена ссылка:

```text
/.postgres/backup -> /mnt/d/Ai/pg_claster_creator.backup
```

Сначала проверялась копия; только затем удалялся прежний каталог /.postgres/backup.
Общий каталог Windows не удалялся. Все новые архивы писались через ссылку в отдельные подпапки:
`/.postgres/backup/test-2.1.2-163900/WSL/`.
Это исключило конфликты имён asvd при параллельном создании архивов одной версии PostgreSQL.

## Исходники

Коммит: `7affaa67ebb5292f45f852b34f82de4f52ad34bc`. Проверялся основной сценарий версии 2.1.2 из рабочей директории, не прежняя установленная копия.

| Файл | SHA-256 |
|---|---|
| .new-claster.config | `7b4f2e911abcba0c290a5e97fe3e3751985433c9fb18b20c7982b776b873b3ab` |
| create-claster.sh | `2ef76425fbfc72873295581268cbcaee405d53a4c6831649c62ef4c6b1bc7cbf` |
| create-claster-backup.sh | `755a4c2264dea83aba3ef25bb7552c06f71e09442fbf645235346305217fbfa3` |
| create-claster-deb.sh | `296431cff08c9afd78629c9829d21b75e05a6c67b39118b406f4b656c55292f0` |
| tmp/scheme_asvd.r586.sql | `d3f426a85b0ac6c00432c38f416ad1dfd9609d579458af955b66512ee92cb61a` |

Хеш общего .new-claster.config до и после одинаков: 7b4f2e911abcba0c290a5e97fe3e3751985433c9fb18b20c7982b776b873b3ab.
Во всех WSL выбран отдельный /usr/local/shared/pg_claster_creator/.new-claster.config; конфиг проекта не изменялся.
Пакет явно задавался при install; последующие операции использовали локальный конфиг без дополнительного PGCC_PACKAGE.

## Матрица результатов

| WSL | Семейство / версия | Кластер | Порт исходный → тестовый → возврат | Данные после переноса | Все фазы | Итоговая очистка |
|---|---|---|---|---|---|---|
| smolensk-1.6.14-mg12.4.0 | postgrespro-ent 16 | qa55650 | 55650 → 56050 → 55650 | /DATA/pg_16/qa55650 | OK | 0 кластеров; /DATA и /BACKUP отсутствуют |
| ALSE-1.7.9-UU1 | postgrespro-ent 17 | qa55651 | 55651 → 56051 → 55651 | /DATA/pg_17/qa55651 | OK | 0 кластеров; /DATA и /BACKUP отсутствуют |
| alse-1.8.2.uu1-mg15.7.0 | tantor-free 16 | qa55652 | 55652 → 56052 → 55652 | /DATA/pg_16/qa55652 | OK | 0 кластеров; /DATA и /BACKUP отсутствуют |
| alse-1.8.3.uu1-mg15.8.4 | postgrespro-ent 16 | qa55653 | 55653 → 56053 → 55653 | /DATA/pg_16/qa55653 | OK | 0 кластеров; /DATA и /BACKUP отсутствуют |
| alse-1.8.4-mg16.3.0 | tantor-free 16 | qa55654 | 55654 → 56054 → 55654 | /DATA/pg_16/qa55654 | OK | 0 кластеров; /DATA и /BACKUP отсутствуют |
| alse-1.8.5-mg16.3.0 | postgrespro-ent 17 | qa55655 | 55655 → 56055 → 55655 | /DATA/pg_17/qa55655 | OK | 0 кластеров; /DATA и /BACKUP отсутствуют |
| ALSE-1.8.6 | postgrespro-ent 16 | qa55656 | 55656 → 56056 → 55656 | /DATA/pg_16/qa55656 | OK | 0 кластеров; /DATA и /BACKUP отсутствуют |

До тестов зарегистрированных кластеров не было. Создано и затем удалено семь тестовых кластеров.

## Критерии подтверждения

- Синтаксис основного сценария корректен, создание каждого кластера rc=0.
- createdb asvd и исполнение полного SQL с ON_ERROR_STOP=1 завершились rc=0 на всех семи.
- В каждой схеме asvd 1647 relations в pg_class (не число таблиц), asvd_has_tables=t. Список схем и расширений сохранён в полном логе. SQL самостоятельно обрабатывает отсутствие необязательных расширений; их комплекты могут отличаться между семьями серверов.
- Горячие и холодные архивы созданы через общую ссылку, прочитаны и имеют SHA-256 в final-state.log. Все кластеры после холодного бэкапа вернулись online.
- После смены TCP-порта старый давал pg_isready rc=2, новый rc=0; исходный порт затем возвращён.
- Перенос из дефолтного каталога в /DATA/pg_VERSION/CLUSTER завершён rc=0, SHOW data_directory подтвердил ожидаемый путь.
- Логический дамп всей asvd до бэкапов и после операций совпал по SHA-256 на каждом стенде. Дополнительно совпал хеш каталога relations.
- CLEANUP-BEFORE/AFTER и DIRECTORIES-BEFORE/AFTER — OK на всех семи.
- Независимая проверка 16:43:01–16:43:11: пустой pg_lsclusters, нет процессов postgres, каталогов кластеров второго уровня /etc/postgresql, PG_VERSION в /var/lib/postgresql; /DATA и /BACKUP отсутствуют даже как ссылки; /.postgres/backup остаётся корректной ссылкой.

Fingerprint: pg_dump --dbname asvd --no-comments, удаляются только строки restrict/unrestrict, затем sha256sum. Хеши сравнивались внутри стенда, а не между WSL: SQL содержит зависимые от времени/окружения данные.

| WSL | SHA-256 логического дампа до = после |
|---|---|
| smolensk-1.6.14-mg12.4.0 | `6bd49dba89585defc5e3b22f2bdd67ee27bd0f8a22c7daeec52ae71d5394b228` |
| ALSE-1.7.9-UU1 | `9d1b897a7e991a38e125af76f9b3849d774bfa550f723b74c3c254559b18b7c0` |
| alse-1.8.2.uu1-mg15.7.0 | `d084bc5e7eaaef56791c9ced2a7d9984650aad57d088795f71c0143d30de49d7` |
| alse-1.8.3.uu1-mg15.8.4 | `f33509e4b1461b506348a9694b34f9c5fb6763ef43078fd883070443e363ead2` |
| alse-1.8.4-mg16.3.0 | `6ed48983c3ae84230c18f57e19c970d45d001ee74189ae352605cc612387ab80` |
| alse-1.8.5-mg16.3.0 | `b4a61dcf0f2107679d8703d72bfdef8fc69792cb05acc01436d3cccd8f925473` |
| ALSE-1.8.6 | `89a3bd2d10b7d3d7d6d15d7bd88ab8be842d58158fcce0b314f551577d53c932` |

## Команды и helper’ы

REPO=/mnt/d/Ai/pg_claster_creator.

Подготовка перед тестом:
```bash
wsl -d WSL -u root --exec bash "$REPO/tmp/save/prepare-backup-link.sh" 163900 WSL
```
Во время исполнения этот новый helper находился в tmp/prepare-backup-link.sh; после успешного использования сохранён в tmp/save.

Запуск каждого стенда:
```bash
wsl -d WSL -u root --exec env \
  PGCC_TEST_RESET_DIRS=1 \
  PGCC_TEST_BACKUP_DIR=/.postgres/backup/test-2.1.2-163900/WSL \
  bash "$REPO/tmp/save/rerun-2.1.1.sh" "$REPO" 163900 \
  WSL VERSION PACKAGE FAMILY PORT sql
```

Имя сохранённого runner’а историческое; ветка sql запускает рабочий create-claster.sh 2.1.2 и не использует старый архив или DEB 2.1.1.
PACKAGE: postgrespro-ent-16-server / postgrespro-ent-17-server, для Tantor — tantor-free-server-16.
VERSION/FAMILY/PORT указаны в матрице.

Переиспользованы tmp/save/test-sql-workflow.sh и универсальные tools/prx-test-postgres-backups.sh, tools/prx-test-postgres-port-data.sh через совместимые wrappers.
Runner расширен параметром очистки каталогов, SQL workflow — параметром каталога бэкапов. Код продукта не изменялся.

Ключевые действия:
```bash
bash "$REPO/create-claster.sh" --action install --package "$PACKAGE" \
  --pg-version "$VERSION" --cluster-name "$CLUSTER" --port "$PORT" \
  --schema pgcc_owner --user pgcc_user --password '<TEST_PASSWORD>' --backup-dir "$BACKUP_DIR"
runuser -u postgres -- createdb --cluster "$VERSION/$CLUSTER" --owner postgres asvd
runuser -u postgres -- psql -X --cluster "$VERSION/$CLUSTER" --dbname asvd \
  --set=ON_ERROR_STOP=1 --file "$REPO/tmp/scheme_asvd.r586.sql"
bash "$REPO/create-claster.sh" --action backup --pg-version "$VERSION" \
  --cluster-name "$CLUSTER" --backup-type hot --database asvd --backup-dir "$BACKUP_DIR"
bash "$REPO/create-claster.sh" --action backup --pg-version "$VERSION" \
  --cluster-name "$CLUSTER" --backup-type cold --clear-wal no --backup-dir "$BACKUP_DIR"
bash "$REPO/create-claster.sh" --action port --pg-version "$VERSION" \
  --cluster-name "$CLUSTER" --port "$NEW_PORT"
# Проверка pg_isready и возврат исходного порта.
bash "$REPO/create-claster.sh" --action move-data --pg-version "$VERSION" \
  --cluster-name "$CLUSTER" --data-root /DATA
```

Время начала/окончания фаз, rc и pg_lsclusters сохранены в full.log.
Удаление /DATA и /BACKUP выполнялось только после успешной очистки кластеров,
с проверкой точных путей и отказом для mountpoint. Общий каталог бэкапов вне этих путей.

## Флаги и доказательства

### smolensk-1.6.14-mg12.4.0

[Сохранение бэкапов](tmp/rerun-163900/smolensk-1.6.14-mg12.4.0/backup-preservation.log), [полный лог](tmp/rerun-163900/smolensk-1.6.14-mg12.4.0/full.log), [results.tsv](tmp/rerun-163900/smolensk-1.6.14-mg12.4.0/results.tsv), [финальное состояние и SHA-256 архивов](tmp/rerun-163900/smolensk-1.6.14-mg12.4.0/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
DIRECTORIES-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	6bd49dba89585defc5e3b22f2bdd67ee27bd0f8a22c7daeec52ae71d5394b228  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
DIRECTORIES-AFTER	OK	rc=0
```

### ALSE-1.7.9-UU1

[Сохранение бэкапов](tmp/rerun-163900/ALSE-1.7.9-UU1/backup-preservation.log), [полный лог](tmp/rerun-163900/ALSE-1.7.9-UU1/full.log), [results.tsv](tmp/rerun-163900/ALSE-1.7.9-UU1/results.tsv), [финальное состояние и SHA-256 архивов](tmp/rerun-163900/ALSE-1.7.9-UU1/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
DIRECTORIES-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	9d1b897a7e991a38e125af76f9b3849d774bfa550f723b74c3c254559b18b7c0  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
DIRECTORIES-AFTER	OK	rc=0
```

### alse-1.8.2.uu1-mg15.7.0

[Сохранение бэкапов](tmp/rerun-163900/alse-1.8.2.uu1-mg15.7.0/backup-preservation.log), [полный лог](tmp/rerun-163900/alse-1.8.2.uu1-mg15.7.0/full.log), [results.tsv](tmp/rerun-163900/alse-1.8.2.uu1-mg15.7.0/results.tsv), [финальное состояние и SHA-256 архивов](tmp/rerun-163900/alse-1.8.2.uu1-mg15.7.0/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
DIRECTORIES-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	d084bc5e7eaaef56791c9ced2a7d9984650aad57d088795f71c0143d30de49d7  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
DIRECTORIES-AFTER	OK	rc=0
```

### alse-1.8.3.uu1-mg15.8.4

[Сохранение бэкапов](tmp/rerun-163900/alse-1.8.3.uu1-mg15.8.4/backup-preservation.log), [полный лог](tmp/rerun-163900/alse-1.8.3.uu1-mg15.8.4/full.log), [results.tsv](tmp/rerun-163900/alse-1.8.3.uu1-mg15.8.4/results.tsv), [финальное состояние и SHA-256 архивов](tmp/rerun-163900/alse-1.8.3.uu1-mg15.8.4/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
DIRECTORIES-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	f33509e4b1461b506348a9694b34f9c5fb6763ef43078fd883070443e363ead2  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
DIRECTORIES-AFTER	OK	rc=0
```

### alse-1.8.4-mg16.3.0

[Сохранение бэкапов](tmp/rerun-163900/alse-1.8.4-mg16.3.0/backup-preservation.log), [полный лог](tmp/rerun-163900/alse-1.8.4-mg16.3.0/full.log), [results.tsv](tmp/rerun-163900/alse-1.8.4-mg16.3.0/results.tsv), [финальное состояние и SHA-256 архивов](tmp/rerun-163900/alse-1.8.4-mg16.3.0/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
DIRECTORIES-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	6ed48983c3ae84230c18f57e19c970d45d001ee74189ae352605cc612387ab80  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
DIRECTORIES-AFTER	OK	rc=0
```

### alse-1.8.5-mg16.3.0

[Сохранение бэкапов](tmp/rerun-163900/alse-1.8.5-mg16.3.0/backup-preservation.log), [полный лог](tmp/rerun-163900/alse-1.8.5-mg16.3.0/full.log), [results.tsv](tmp/rerun-163900/alse-1.8.5-mg16.3.0/results.tsv), [финальное состояние и SHA-256 архивов](tmp/rerun-163900/alse-1.8.5-mg16.3.0/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
DIRECTORIES-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	b4a61dcf0f2107679d8703d72bfdef8fc69792cb05acc01436d3cccd8f925473  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
DIRECTORIES-AFTER	OK	rc=0
```

### ALSE-1.8.6

[Сохранение бэкапов](tmp/rerun-163900/ALSE-1.8.6/backup-preservation.log), [полный лог](tmp/rerun-163900/ALSE-1.8.6/full.log), [results.tsv](tmp/rerun-163900/ALSE-1.8.6/results.tsv), [финальное состояние и SHA-256 архивов](tmp/rerun-163900/ALSE-1.8.6/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
DIRECTORIES-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	89a3bd2d10b7d3d7d6d15d7bd88ab8be842d58158fcce0b314f551577d53c932  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
DIRECTORIES-AFTER	OK	rc=0
```

## Оставленное состояние

- /.postgres/backup — ссылка на общий Windows-каталог на всех семи WSL.
- В D:/Ai/pg_claster_creator.backup/ сохранены 3 уникальных прежних архива.
- В D:/Ai/pg_claster_creator.backup/test-2.1.2-163900/ сохранены 14 новых архивов, по два на WSL.
- Все кластеры, /DATA и /BACKUP удалены на всех семи WSL.
- Прежнее содержимое /DATA и /BACKUP, включая старые тестовые архивы, удалено по запросу. Специальная копия этих каталогов не создавалась; сохранение распространялось на /.postgres/backup. Восстановимость удалённых файлов из иных копий не проверялась.
- Локальные конфиги сохранены; их backup_dir указывает на индивидуальную подпапку теста через /.postgres/backup.
- Общий конфиг проекта, исходный SQL и прежние журналы не изменены. Git commit/push в этом задании не выполнялись.

Предупреждения systemd user session root на части WSL не препятствовали тесту.
Для Windows/DrvFS нельзя полагаться только на Unix chmod для защиты архива: доступ определяется также Windows ACL. Бэкапы содержат данные и метаданные ролей; не публиковать их без проверки.
В копиях full.log замаскированы хеши паролей и известный тестовый пароль; исходные служебные логи внутри WSL могут содержать секреты.
tmp игнорируется Git — очищенные логи передаются отдельно вместе с журналом.

Суффикс -passed присвоен после проверки 105 флагов OK, 14 новых архивов, 3 сохранённых уникальных файлов, неизменности логических дампов, отсутствия кластеров/каталогов и сохранности ссылок.
