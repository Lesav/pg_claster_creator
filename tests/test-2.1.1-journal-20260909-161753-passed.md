# Тестирование pg_claster_creator 2.1.1 — OK

Дата: 2026-09-09, MSK. Идентификатор: 161753.
Все 13 фаз на каждом из 7 стендов имеют флаг **OK** (91/91).
Независимая финальная проверка также OK на всех семи.
Журнал после проверки переименован в test-2.1.1-journal-20260909-161753-passed.md.

## Область проверки

Пройден сценарий последнего запроса пользователя: очистка всех кластеров до теста, создание чистого кластера через create-claster.sh, создание БД asvd, применение scheme_asvd.r586.sql, горячий/холодный бэкапы, смена TCP-порта, перенос данных в /DATA, очистка после.

Это результат указанного сценария, а не декларация прохождения всего расширенного плана TEST.md. Установка DEB, восстановление из созданных архивов и fault-injection в этот прогон не входили.

Исходный архив /mnt/d/Ai/pg_claster_creator/tmp/16-asvd-20260906-190608-dmp.tar.gz не использовался и не читался. Применялся неизменённый SQL /mnt/d/Ai/pg_claster_creator/tmp/scheme_asvd.r586.sql с psql -X --set=ON_ERROR_STOP=1.

## Изоляция конфигурации

Перед запуском /usr/local/shared/pg_claster_creator/.new-claster.config отсутствовал на всех семи WSL. В каждой машине он создан копированием её собственного установленного /usr/local/share/pg_claster_creator/.new-claster.config с правами 0600. Исходные установленные конфиги не заменялись.

Во всех запусках подтверждён selected_config=/usr/local/shared/pg_claster_creator/.new-claster.config. Сценарии запускались из общего проекта, но сохраняли значения в отдельные локальные файлы WSL. Общий конфиг проекта остался побайтно неизменным.

Точный серверный пакет задавался ключом --package при создании кластера. Последующие backup/port/move-data запускались без дополнительного PGCC_PACKAGE, используя локальную конфигурацию. Прежний сбой Tantor с запуском бинарника другой редакции не воспроизвёлся.

## Исходники

Коммит: `47be778931a7efcadd52a151cc108af5e0bb6603` плюс существующие изменения рабочей копии, включая новый приоритет конфигурации. Код продукта и SQL во время прогона не исправлялись.

| Файл | SHA-256 |
|---|---|
| .new-claster.config | `7b4f2e911abcba0c290a5e97fe3e3751985433c9fb18b20c7982b776b873b3ab` |
| create-claster.sh | `d4b372ad2cbf16151b49a79329f9a4492caec64e3ce8b8a57ba0d41be24015ad` |
| create-claster-backup.sh | `026a86c553e63579b617fdb1d80553bcb95d5ab0ead85565684f884e029958d1` |
| create-claster-deb.sh | `cfa1d4f27210abb330ec32b7bcfd5c6f493d2c67cadfedea7656cb797bb06d66` |
| tmp/scheme_asvd.r586.sql | `d3f426a85b0ac6c00432c38f416ad1dfd9609d579458af955b66512ee92cb61a` |

Хеш .new-claster.config в таблице одинаков до и после теста.

## Матрица стендов

| WSL | Сервер | Кластер | Исходный → тестовый порт | Данные после переноса | Все фазы | После очистки |
|---|---|---|---|---|---|---|
| smolensk-1.6.14-mg12.4.0 | postgrespro-ent 16 | qa55550 | 55550 → 55950 → 55550 | /DATA/pg_16/qa55550 | OK | 0 кластеров |
| ALSE-1.7.9-UU1 | postgrespro-ent 17 | qa55551 | 55551 → 55951 → 55551 | /DATA/pg_17/qa55551 | OK | 0 кластеров |
| alse-1.8.2.uu1-mg15.7.0 | tantor-free 16 | qa55552 | 55552 → 55952 → 55552 | /DATA/pg_16/qa55552 | OK | 0 кластеров |
| alse-1.8.3.uu1-mg15.8.4 | postgrespro-ent 16 | qa55553 | 55553 → 55953 → 55553 | /DATA/pg_16/qa55553 | OK | 0 кластеров |
| alse-1.8.4-mg16.3.0 | tantor-free 16 | qa55554 | 55554 → 55954 → 55554 | /DATA/pg_16/qa55554 | OK | 0 кластеров |
| alse-1.8.5-mg16.3.0 | postgrespro-ent 17 | qa55555 | 55555 → 55955 → 55555 | /DATA/pg_17/qa55555 | OK | 0 кластеров |
| ALSE-1.8.6 | postgrespro-ent 16 | qa55556 | 55556 → 55956 → 55556 | /DATA/pg_16/qa55556 | OK | 0 кластеров |

## Критерии и фактический результат

- CLEANUP-BEFORE: pg_lsclusters перед тестом пуст на всех семи; выполнена штатная очистка/проверка остаточных конфигураций.
- LOCAL-CONFIG: выбран приоритетный локальный конфиг каждой WSL, доступный для чтения.
- SYNTAX: bash -n основного сценария rc=0.
- CREATE: штатный --action install rc=0; новый кластер online в дефолтном каталоге данных.
- DATABASE: createdb asvd rc=0.
- SQL-SCHEMAS: неизменённый SQL исполнен с ON_ERROR_STOP=1, rc=0.
- SCHEMA-INVENTORY: во всех asvd зарегистрировано 1647 relations в pg_class (не число таблиц); asvd_has_tables=t. Схемы и расширения перечислены в логах. SQL сам обрабатывает недоступность необязательных расширений; комплект расширений может отличаться между серверами.
- LOGICAL-BASELINE: до бэкапов получен SHA-256 полного логического pg_dump базы asvd.
- HOT: архив создан, tar прочитан, метаданные прочитаны, pg_restore --list rc=0.
- COLD: архив создан, tar и метаданные прочитаны, исходный online-кластер снова успешно запущен. --clear-wal no.
- PORT-MOVE: порт изменён и возвращён; старый порт при смене давал pg_isready rc=2, новый rc=0; данные перенесены в /DATA; SHOW data_directory совпал с ожидаемым путём, кластер доступен.
- LOGICAL-UNCHANGED: SHA-256 полного логического дампа до бэкапов и после всех операций совпал. Также совпал контрольный хеш каталога relations.
- CLEANUP-AFTER: тестовые кластеры, их конфигурации и unit-файлы удалены.
- Дополнительно: независимые запросы 16:20:12–16:20:23 подтвердили пустой pg_lsclusters, отсутствие каталогов кластеров второго уровня в /etc/postgresql, процессов postgres и файлов PG_VERSION в /DATA и /var/lib/postgresql.

Логический fingerprint: pg_dump --dbname asvd --no-comments, из вывода удалены только строки restrict/unrestrict, затем sha256sum. Сравнение выполнялось внутри одного стенда; различия хешей между WSL допустимы, поскольку SQL содержит данные времени/окружения.

## Контрольные хеши asvd

| WSL | SHA-256 до = после |
|---|---|
| smolensk-1.6.14-mg12.4.0 | `3d356d61589e9b50beec09cd3aeafaae73b61d57553a2487db077a549c89b690` |
| ALSE-1.7.9-UU1 | `8b979818f801627c84ec90777eccd04f16d81b5c88a29718bd26370408836226` |
| alse-1.8.2.uu1-mg15.7.0 | `290ccac8a1acf963f285cb6582e8583f97a38aebe3dee0d549ac72521aa15b1f` |
| alse-1.8.3.uu1-mg15.8.4 | `2837c1375b57c11e9509109257ad98ae66511d5dcecab3d109733e8733edd0cd` |
| alse-1.8.4-mg16.3.0 | `a2bd6cc8a3723122440ea7dfc91c5f0cfecaf9f01d98bfe10b0e248b8fffb24f` |
| alse-1.8.5-mg16.3.0 | `25bbe53a639769d45cb0fa01bb7095f7a707c65819b1cf0f70cc5fa7dcacdf9f` |
| ALSE-1.8.6 | `0196d873368ff39b39f372be514d0639341d86bb665bc1f617c5aa580cdb9854` |

## Воспроизведение

REPO=/mnt/d/Ai/pg_claster_creator.
Для каждой строки матрицы запускался:

```bash
wsl -d WSL -u root --exec bash "$REPO/tmp/save/rerun-2.1.1.sh" \
  "$REPO" 161753 WSL VERSION PACKAGE FAMILY PORT sql
```

PACKAGE: postgrespro-ent-16-server / postgrespro-ent-17-server для Postgres Pro, tantor-free-server-16 для двух Tantor. VERSION/FAMILY/PORT приведены в матрице.

Переиспользован tmp/save/test-sql-workflow.sh. Проверки бэкапов и переноса используют tools/prx-test-postgres-backups.sh и tools/prx-test-postgres-port-data.sh через совместимые wrappers tmp/save. Команды ограничены timeout; полный вывод, время начала/окончания, rc и pg_lsclusters фиксировались для каждой фазы.

Основные действия:

```bash
bash "$REPO/create-claster.sh" --action install --package "$PACKAGE" \
  --pg-version "$VERSION" --cluster-name "$CLUSTER" --port "$PORT" \
  --schema pgcc_owner --user pgcc_user --password '<TEST_PASSWORD>' \
  --backup-dir /BACKUP/pgcc-sql-161753
runuser -u postgres -- createdb --cluster "$VERSION/$CLUSTER" --owner postgres asvd
runuser -u postgres -- psql -X --cluster "$VERSION/$CLUSTER" --dbname asvd \
  --set=ON_ERROR_STOP=1 --file "$REPO/tmp/scheme_asvd.r586.sql"
bash "$REPO/create-claster.sh" --action backup --pg-version "$VERSION" \
  --cluster-name "$CLUSTER" --backup-type hot --database asvd --backup-dir /BACKUP/pgcc-sql-161753
bash "$REPO/create-claster.sh" --action backup --pg-version "$VERSION" \
  --cluster-name "$CLUSTER" --backup-type cold --clear-wal no --backup-dir /BACKUP/pgcc-sql-161753
bash "$REPO/create-claster.sh" --action port --pg-version "$VERSION" \
  --cluster-name "$CLUSTER" --port "$NEW_PORT"
# После проверки доступности — возврат исходного порта тем же действием.
bash "$REPO/create-claster.sh" --action move-data --pg-version "$VERSION" \
  --cluster-name "$CLUSTER" --data-root /DATA
```

## Флаги и логи

### smolensk-1.6.14-mg12.4.0

[Полный лог](../tmp/rerun-161753/smolensk-1.6.14-mg12.4.0/full.log), [results.tsv](../tmp/rerun-161753/smolensk-1.6.14-mg12.4.0/results.tsv), [финальная проверка и SHA-256 архивов](../tmp/rerun-161753/smolensk-1.6.14-mg12.4.0/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	3d356d61589e9b50beec09cd3aeafaae73b61d57553a2487db077a549c89b690  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### ALSE-1.7.9-UU1

[Полный лог](../tmp/rerun-161753/ALSE-1.7.9-UU1/full.log), [results.tsv](../tmp/rerun-161753/ALSE-1.7.9-UU1/results.tsv), [финальная проверка и SHA-256 архивов](../tmp/rerun-161753/ALSE-1.7.9-UU1/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	8b979818f801627c84ec90777eccd04f16d81b5c88a29718bd26370408836226  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.2.uu1-mg15.7.0

[Полный лог](../tmp/rerun-161753/alse-1.8.2.uu1-mg15.7.0/full.log), [results.tsv](../tmp/rerun-161753/alse-1.8.2.uu1-mg15.7.0/results.tsv), [финальная проверка и SHA-256 архивов](../tmp/rerun-161753/alse-1.8.2.uu1-mg15.7.0/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	290ccac8a1acf963f285cb6582e8583f97a38aebe3dee0d549ac72521aa15b1f  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.3.uu1-mg15.8.4

[Полный лог](../tmp/rerun-161753/alse-1.8.3.uu1-mg15.8.4/full.log), [results.tsv](../tmp/rerun-161753/alse-1.8.3.uu1-mg15.8.4/results.tsv), [финальная проверка и SHA-256 архивов](../tmp/rerun-161753/alse-1.8.3.uu1-mg15.8.4/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	2837c1375b57c11e9509109257ad98ae66511d5dcecab3d109733e8733edd0cd  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.4-mg16.3.0

[Полный лог](../tmp/rerun-161753/alse-1.8.4-mg16.3.0/full.log), [results.tsv](../tmp/rerun-161753/alse-1.8.4-mg16.3.0/results.tsv), [финальная проверка и SHA-256 архивов](../tmp/rerun-161753/alse-1.8.4-mg16.3.0/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	a2bd6cc8a3723122440ea7dfc91c5f0cfecaf9f01d98bfe10b0e248b8fffb24f  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.5-mg16.3.0

[Полный лог](../tmp/rerun-161753/alse-1.8.5-mg16.3.0/full.log), [results.tsv](../tmp/rerun-161753/alse-1.8.5-mg16.3.0/results.tsv), [финальная проверка и SHA-256 архивов](../tmp/rerun-161753/alse-1.8.5-mg16.3.0/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	25bbe53a639769d45cb0fa01bb7095f7a707c65819b1cf0f70cc5fa7dcacdf9f  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### ALSE-1.8.6

[Полный лог](../tmp/rerun-161753/ALSE-1.8.6/full.log), [results.tsv](../tmp/rerun-161753/ALSE-1.8.6/results.tsv), [финальная проверка и SHA-256 архивов](../tmp/rerun-161753/ALSE-1.8.6/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
LOCAL-CONFIG	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	0196d873368ff39b39f372be514d0639341d86bb665bc1f617c5aa580cdb9854  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

## Финальное состояние и сохранённые файлы

Перед тестом существующих кластеров не было. Созданы и затем удалены семь тестовых кластеров. Все семь WSL после завершения очищены от кластеров; общий каталог /var/log/postgresql не удалялся. Удалённые тестовые данные доступны в сохранённых бэкапах, но фактическое восстановление из них в этом прогоне не проверялось.

Намеренно оставлены:
- отдельные локальные конфиги /usr/local/shared/pg_claster_creator/.new-claster.config на каждой WSL; они содержат выбранное семейство/версию и backup_dir=/BACKUP/pgcc-sql-161753;
- 14 новых архивов (горячий asvd и холодный кластер на каждом стенде) в /BACKUP/pgcc-sql-161753;
- журналы и пустые родительские каталоги /DATA/pg_VERSION;
- исходный SQL, прежние архивы и прежние журналы без изменений.

Хеши и точные имена архивов — в final-state.log каждого стенда. В копиях full.log данного прогона замаскированы хеши паролей и известный тестовый пароль. Архивы и исходные служебные логи внутри WSL могут содержать учётные данные: перед публикацией требуется отдельная проверка. tmp игнорируется Git; для передачи доказательств следует приложить очищенные логи отдельно.

На части WSL сохранялось предупреждение о systemd user session root; оно не мешало выполнению фаз, все команды прогона завершились rc=0. Никаких повторных попыток с подменой параметров или данных для получения OK не потребовалось.

Переименование в -passed выполнено после проверки наличия всех 13 фаз на каждом стенде, всех флагов OK, равенства логических хешей, конечного отсутствия кластеров и неизменности общего конфига проекта.
