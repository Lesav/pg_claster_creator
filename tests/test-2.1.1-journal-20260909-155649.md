# Тестирование 2.1.1: чистый кластер и scheme_asvd.r586.sql

Дата: 2026-09-09, MSK. Идентификатор: 155649.

Итог основного прогона: **FAIL** на двух Tantor; на пяти Postgres Pro все заданные фазы OK.
Дополнительный прогон двух Tantor с явным PGCC_PACKAGE: **OK**.
Журнал не переименован в -passed: первичные ошибки и ограничение изоляции теста сохранены, не скрыты успешным повтором.

## Область проверки

Выполнен сценарий из последнего запроса пользователя, а не полный набор всех вариантов TEST.md:

1. Удалить все кластеры на семи указанных WSL.
2. Создать новый кластер штатным create-claster.sh в дефолтном каталоге данных.
3. Создать БД asvd и применить неизменённый tmp/scheme_asvd.r586.sql с ON_ERROR_STOP=1.
4. Создать и прочитать горячий и холодный бэкапы.
5. Проверить смену TCP-порта и возврат на исходный порт.
6. Переместить данные в /DATA/pg_VERSION/CLUSTER и проверить online, фактический data_directory и неизменность логического дампа.
7. Удалить все кластеры и независимо проверить отсутствие оставшихся данных кластеров/процессов.

Архив 16-asvd-20260906-190608-dmp.tar.gz **не читался и не использовался**. Новые архивы получены из БД, созданной SQL-сценарием. Восстановление из новых архивов в этом заданном сценарии не выполнялось: горячий проверен через tar и pg_restore --list, холодный — через чтение tar/метаданных и возврат исходного кластера online.

## Исходники и конфигурация

Коммит: `47be778931a7efcadd52a151cc108af5e0bb6603` плюс существующие рабочие изменения. Во всех девяти запусках SHA-256 основного сценария одинаковый. Код продукта и исходный SQL в этом прогоне не исправлялись.

| Файл | SHA-256 |
|---|---|
| create-claster.sh | `6c170d18611bd77d2d4bea18442c3bb10c19947fe3ab7c6829014cc60e61ac66` |
| create-claster-backup.sh | `9eb7ac2586a062085d158587b87f480a098125009e710c9ead486263e8d6ab54` |
| create-claster-deb.sh | `30890a0014902b10ac37edc3402089b525039168671dce40995116a919cfca6d` |
| tmp/scheme_asvd.r586.sql | `d3f426a85b0ac6c00432c38f416ad1dfd9609d579458af955b66512ee92cb61a` |
| .new-claster.config до теста и после возврата | `7b4f2e911abcba0c290a5e97fe3e3751985433c9fb18b20c7982b776b873b3ab` |

До теста конфиг содержал семейство postgrespro-ent, версию 17 и backup_dir=/.postgres/backup. Для install версия и пакет явно задавались ключами на каждом стенде. Тестовые изменения общего конфига отменены; исходный SHA-256 восстановлен. Другие пользовательские изменения, включая TEST.md, не отменялись.

## Стенды и результаты

| WSL | Сервер | SQL asvd | Горячий | Холодный | TCP и /DATA | Логический дамп неизменён | Очистка после |
|---|---|---|---|---|---|---|---|
| smolensk-1.6.14-mg12.4.0 | postgrespro-ent 16 | OK | OK | OK | OK | OK | OK / 0 кластеров |
| ALSE-1.7.9-UU1 | postgrespro-ent 17 | OK | OK | OK | OK | OK | OK / 0 кластеров |
| alse-1.8.2.uu1-mg15.7.0 | tantor-free 16 | OK | OK | FAIL → OK¹ | BLOCKED → OK¹ | BLOCKED → OK¹ | OK / 0 кластеров |
| alse-1.8.3.uu1-mg15.8.4 | postgrespro-ent 16 | OK | OK | OK | OK | OK | OK / 0 кластеров |
| alse-1.8.4-mg16.3.0 | tantor-free 16 | OK | OK | FAIL → OK¹ | BLOCKED → OK¹ | BLOCKED → OK¹ | OK / 0 кластеров |
| alse-1.8.5-mg16.3.0 | postgrespro-ent 17 | OK | OK | OK | OK | OK | OK / 0 кластеров |
| ALSE-1.8.6 | postgrespro-ent 16 | OK | OK | OK | OK | OK | OK / 0 кластеров |

¹ Дополнительный запуск с PGCC_PACKAGE=tantor-free-server-16. В первом results.tsv PORT-MOVE записан как FAIL rc=2: helper не смог подключиться к остановленному кластеру ещё до смены порта. Поэтому отдельные операции порта и переноса в первичной попытке фактически BLOCKED, а не доказанный дефект этих операций.

SQL выполнен с rc=0 на всех семи; в схеме asvd зафиксировано 1647 объектов pg_class (таблицы, индексы, последовательности и другие relations; это не число таблиц). Инвентаризация схем и расширений есть в full.log. Необязательные расширения SQL обрабатывает собственными EXCEPTION-блоками: rc=0 не означает, что одинаковый комплект расширений установлен на всех семействах.

## Первичный сбой и влияние тестовой среды

На alse-1.8.2.uu1-mg15.7.0 и alse-1.8.4-mg16.3.0 холодный архив физически создан, но последующий запуск исходного кластера неуспешен:

```text
Кластер баз данных был инициализирован редакцией PostgreSQL,
которая несовместима с текущей редакцией (Postgres Pro Enterprise).
ОШИБКА: не удалось подтвердить запуск ... код=1, systemd=inactive
```

В этой попытке кластер Tantor запускался через /usr/lib/postgresql/16/bin/pg_ctl, указывающий на другую редакцию. COLD rc=1; последующая проверка подключения rc=2.

Важное ограничение: параллельные WSL вызывали один и тот же файл create-claster.sh в /mnt/d, а его save_config() записывает семейство/версию и каталог бэкапа в соседний общий .new-claster.config. main() для backup/port/move-data выполняет выбор сервера и prepare_postgres_root() до действия. При отсутствии явного пакета дальнейший выбор зависел от изменяемого общего конфига.

Поэтому первичные результаты нельзя трактовать как чистое независимое доказательство несовместимости Tantor: есть ошибка изоляции теста и зависимость выбора серверных бинарников от конфигурации. Для последующих межсемейных параллельных тестов нужны отдельные копии сценария/конфига на стенд либо последовательный запуск; пакет следует задавать явно.

В дополнительном прогоне экспортирован штатный PGCC_PACKAGE=tantor-free-server-16. Без исправления кода продукта и без изменения SQL обе WSL прошли все заданные фазы. Общий сценарий не объявлен безусловно прошедшим: исходная попытка с неявным выбором пакета осталась FAIL.

## Команды

REPO=/mnt/d/Ai/pg_claster_creator. Основной запуск для каждого стенда:

```bash
wsl -d WSL -u root --exec bash $REPO/tmp/save/rerun-2.1.1.sh \
  "$REPO" 155649 WSL VERSION PACKAGE FAMILY PORT sql
```

| WSL | VERSION | PACKAGE | FAMILY | PORT | Новый порт | CLUSTER |
|---|---|---|---|---|---|---|
| smolensk-1.6.14-mg12.4.0 | 16 | postgrespro-ent-16-server | postgrespro-ent | 55530 | 55930 | qa55530 |
| ALSE-1.7.9-UU1 | 17 | postgrespro-ent-17-server | postgrespro-ent | 55531 | 55931 | qa55531 |
| alse-1.8.2.uu1-mg15.7.0 | 16 | tantor-free-server-16 | tantor-free | 55532 | 55932 | qa55532 |
| alse-1.8.3.uu1-mg15.8.4 | 16 | postgrespro-ent-16-server | postgrespro-ent | 55533 | 55933 | qa55533 |
| alse-1.8.4-mg16.3.0 | 16 | tantor-free-server-16 | tantor-free | 55534 | 55934 | qa55534 |
| alse-1.8.5-mg16.3.0 | 17 | postgrespro-ent-17-server | postgrespro-ent | 55535 | 55935 | qa55535 |
| ALSE-1.8.6 | 16 | postgrespro-ent-16-server | postgrespro-ent | 55536 | 55936 | qa55536 |

Повтор только двух Tantor:

```bash
wsl -d WSL -u root --exec env PGCC_PACKAGE=tantor-free-server-16 \
  bash $REPO/tmp/save/rerun-2.1.1.sh "$REPO" 155649-explicit-package \
  WSL 16 tantor-free-server-16 tantor-free PORT sql
```

Основные команды внутри helper’а:

```bash
bash "$REPO/create-claster.sh" --action install --package "$PACKAGE" \
  --pg-version "$VERSION" --cluster-name "$CLUSTER" --port "$PORT" \
  --schema pgcc_owner --user pgcc_user --password '<TEST_PASSWORD>' \
  --backup-dir "$BACKUP_DIR"
runuser -u postgres -- createdb --cluster "$VERSION/$CLUSTER" --owner postgres asvd
runuser -u postgres -- psql -X --cluster "$VERSION/$CLUSTER" --dbname asvd \
  --set=ON_ERROR_STOP=1 --file "$REPO/tmp/scheme_asvd.r586.sql"
bash "$REPO/create-claster.sh" --action backup --pg-version "$VERSION" \
  --cluster-name "$CLUSTER" --backup-type hot --database asvd --backup-dir "$BACKUP_DIR"
bash "$REPO/create-claster.sh" --action backup --pg-version "$VERSION" \
  --cluster-name "$CLUSTER" --backup-type cold --clear-wal no --backup-dir "$BACKUP_DIR"
bash "$REPO/create-claster.sh" --action port --pg-version "$VERSION" \
  --cluster-name "$CLUSTER" --port "$NEW_PORT"
# Проверки pg_isready; затем возврат исходного порта той же командой.
bash "$REPO/create-claster.sh" --action move-data --pg-version "$VERSION" \
  --cluster-name "$CLUSTER" --data-root /DATA
```

Логический SHA-256: pg_dump всей asvd с --no-comments; из вывода удаляются только строки restrict/unrestrict. Проверено точное равенство хешей до бэкапов и после порта/переноса. Дополнительно сравнивался хеш каталога relations; SHOW data_directory должен совпасть с /DATA/pg_VERSION/CLUSTER. Старый порт после переключения возвращал pg_isready rc=2, новый rc=0.

## Проверка логического содержимого

В таблице приведён хеш успешной попытки. Разные хеши разных стендов допустимы: SQL создаёт зависимые от времени/окружения объекты и данные. Сравнение выполнялось внутри одного стенда/попытки.

| WSL | SHA-256 до и после |
|---|---|
| smolensk-1.6.14-mg12.4.0 | `200c6ec9f5464cd424ec80c9b623e4fbe5f1f779aaa2959146a21cea23dc58be` |
| ALSE-1.7.9-UU1 | `54e693b6f78d390698a3769909e1a5bea03a119b4fa015bea288016078a2f931` |
| alse-1.8.2.uu1-mg15.7.0 | `247f15d175a661203484dd7d67a5b44c7839bae57ef54517bfdc982699c9a510` |
| alse-1.8.3.uu1-mg15.8.4 | `ebff6917e9604983ecb3ab05f8894d4e647f8d13f8494d2278e1edbe607c10dd` |
| alse-1.8.4-mg16.3.0 | `cc2ceeada1ca6390c4dd489f9c634fb067b0d6f718caa12b4a244eeb621629e2` |
| alse-1.8.5-mg16.3.0 | `46100a6a6908c4749bf839b5ac0673de65fc0086d56979418fad5d8472bc84fb` |
| ALSE-1.8.6 | `07ba3088a6abe1ae78d9477760233d631ac4219af8bff74c2e71c15e2023d454` |

## Фазы и полные логи

Фазы фиксируют начало/конец, rc и pg_lsclusters. OK — успешная выполненная фаза, FAIL — фактическая ошибка. Итоги не подменены успешной повторной попыткой.

### ALSE-1.7.9-UU1 — rerun-155649

[Полный лог](../tmp/rerun-155649/ALSE-1.7.9-UU1/full.log), [флаги и rc](../tmp/rerun-155649/ALSE-1.7.9-UU1/results.tsv).

```text
CLEANUP-BEFORE	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	54e693b6f78d390698a3769909e1a5bea03a119b4fa015bea288016078a2f931  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.2.uu1-mg15.7.0 — rerun-155649

[Полный лог](../tmp/rerun-155649/alse-1.8.2.uu1-mg15.7.0/full.log), [флаги и rc](../tmp/rerun-155649/alse-1.8.2.uu1-mg15.7.0/results.tsv).

```text
CLEANUP-BEFORE	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	823167f82cf78b73c84f1fd20a005e022d6f5176eed0ecb254073c839e9c570f  -
HOT	OK	rc=0
COLD	FAIL	rc=1
PORT-MOVE	FAIL	rc=2
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.3.uu1-mg15.8.4 — rerun-155649

[Полный лог](../tmp/rerun-155649/alse-1.8.3.uu1-mg15.8.4/full.log), [флаги и rc](../tmp/rerun-155649/alse-1.8.3.uu1-mg15.8.4/results.tsv).

```text
CLEANUP-BEFORE	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	ebff6917e9604983ecb3ab05f8894d4e647f8d13f8494d2278e1edbe607c10dd  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.4-mg16.3.0 — rerun-155649

[Полный лог](../tmp/rerun-155649/alse-1.8.4-mg16.3.0/full.log), [флаги и rc](../tmp/rerun-155649/alse-1.8.4-mg16.3.0/results.tsv).

```text
CLEANUP-BEFORE	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	45ce2c7835daf1de9b15cbf759edd2d73cf51ec64c281ef5814bef9f9fd79fa1  -
HOT	OK	rc=0
COLD	FAIL	rc=1
PORT-MOVE	FAIL	rc=2
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.5-mg16.3.0 — rerun-155649

[Полный лог](../tmp/rerun-155649/alse-1.8.5-mg16.3.0/full.log), [флаги и rc](../tmp/rerun-155649/alse-1.8.5-mg16.3.0/results.tsv).

```text
CLEANUP-BEFORE	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	46100a6a6908c4749bf839b5ac0673de65fc0086d56979418fad5d8472bc84fb  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### ALSE-1.8.6 — rerun-155649

[Полный лог](../tmp/rerun-155649/ALSE-1.8.6/full.log), [флаги и rc](../tmp/rerun-155649/ALSE-1.8.6/results.tsv).

```text
CLEANUP-BEFORE	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	07ba3088a6abe1ae78d9477760233d631ac4219af8bff74c2e71c15e2023d454  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### smolensk-1.6.14-mg12.4.0 — rerun-155649

[Полный лог](../tmp/rerun-155649/smolensk-1.6.14-mg12.4.0/full.log), [флаги и rc](../tmp/rerun-155649/smolensk-1.6.14-mg12.4.0/results.tsv).

```text
CLEANUP-BEFORE	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	200c6ec9f5464cd424ec80c9b623e4fbe5f1f779aaa2959146a21cea23dc58be  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.2.uu1-mg15.7.0 — rerun-155649-explicit-package

[Полный лог](../tmp/rerun-155649-explicit-package/alse-1.8.2.uu1-mg15.7.0/full.log), [флаги и rc](../tmp/rerun-155649-explicit-package/alse-1.8.2.uu1-mg15.7.0/results.tsv).

```text
CLEANUP-BEFORE	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	247f15d175a661203484dd7d67a5b44c7839bae57ef54517bfdc982699c9a510  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.4-mg16.3.0 — rerun-155649-explicit-package

[Полный лог](../tmp/rerun-155649-explicit-package/alse-1.8.4-mg16.3.0/full.log), [флаги и rc](../tmp/rerun-155649-explicit-package/alse-1.8.4-mg16.3.0/results.tsv).

```text
CLEANUP-BEFORE	OK	rc=0
SYNTAX	OK	rc=0
CREATE	OK	rc=0
DATABASE	OK	rc=0
SQL-SCHEMAS	OK	rc=0
SCHEMA-INVENTORY	OK	rc=0
LOGICAL-BASELINE	OK	cc2ceeada1ca6390c4dd489f9c634fb067b0d6f718caa12b4a244eeb621629e2  -
HOT	OK	rc=0
COLD	OK	rc=0
PORT-MOVE	OK	rc=0
LOGICAL-UNCHANGED	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

## Очистка и артефакты

До основного теста был найден один кластер: 17/ssss на ALSE-1.7.9-UU1, online, /DATA/pg_17/ssss. По прямому указанию пользователя он удалён. На остальных шести перед тестом кластеров не было. Его восстановление возможно только при наличии подходящего бэкапа; наличие точной копии данных ssss в прежних снимках не проверялось.

После каждого из девяти запусков CLEANUP-AFTER=OK. Независимая финальная проверка 16:01:50–16:02:09 показала:
- pg_lsclusters пуст на всех семи WSL;
- нет каталогов кластеров второго уровня /etc/postgresql;
- нет процессов postgres;
- в /DATA и /var/lib/postgresql отсутствуют PG_VERSION.

Удалялись точные зарегистрированные кластеры через pg_dropcluster, их unit-файлы и проверенные нормализованные остаточные конфигурации; общий каталог журналов не удалялся.

Свежие архивы намеренно оставлены в /BACKUP/pgcc-sql-155649 и, на двух Tantor, /BACKUP/pgcc-sql-155649-explicit-package. Архивы первичных неуспешных холодных операций сохранены как диагностические, не объявлены проверенными восстановлением. Пустые родительские каталоги данных и служебные журналы оставлены. Списки архивов и SHA-256, а также подтверждение очистки:

- [smolensk-1.6.14-mg12.4.0: final-state.log](../tmp/rerun-155649/smolensk-1.6.14-mg12.4.0/final-state.log)
- [ALSE-1.7.9-UU1: final-state.log](../tmp/rerun-155649/ALSE-1.7.9-UU1/final-state.log)
- [alse-1.8.2.uu1-mg15.7.0: final-state.log](../tmp/rerun-155649/alse-1.8.2.uu1-mg15.7.0/final-state.log)
- [alse-1.8.3.uu1-mg15.8.4: final-state.log](../tmp/rerun-155649/alse-1.8.3.uu1-mg15.8.4/final-state.log)
- [alse-1.8.4-mg16.3.0: final-state.log](../tmp/rerun-155649/alse-1.8.4-mg16.3.0/final-state.log)
- [alse-1.8.5-mg16.3.0: final-state.log](../tmp/rerun-155649/alse-1.8.5-mg16.3.0/final-state.log)
- [ALSE-1.8.6: final-state.log](../tmp/rerun-155649/ALSE-1.8.6/final-state.log)

В рабочих копиях full.log маскированы хеши паролей и известный тестовый пароль. Архивы содержат данные/метаданные ролей, а исходные локальные логи внутри WSL могут содержать хеши; не публиковать их без проверки. tmp игнорируется Git — очищенные логи нужно передавать вместе с журналом отдельно.

Существующие backup и port/move helper’ы после повторного успешного использования параметризованы и перенесены в tools/prx-test-postgres-backups.sh и tools/prx-test-postgres-port-data.sh; tools/INDEX.md обновлён, старые имена оставлены короткими совместимыми wrappers. Новый SQL-сценарий теста сохранён в tmp/save/test-sql-workflow.sh. Его первоначальное расположение во время этого прогона — tmp/test-sql-workflow.sh.

Окончательное состояние: тестовые кластеры отсутствуют на всех семи WSL, конфиг проекта возвращён побайтно к состоянию перед тестом. Суффикс -passed не присвоен.
