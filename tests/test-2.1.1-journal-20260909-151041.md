# Повторное тестирование pg_claster_creator 2.1.1

Дата: 2026-09-09, MSK. Идентификатор: 151041. Основной прогон: 15:11–15:12; независимая финальная проверка: 15:12:56–15:13:02.

Итог: **FAIL**. Суффикс `-passed` не присвоен: восстановление пользовательского архива завершилось ошибкой на шести WSL. На Astra 1.6 все выполненные автоматические фазы получили OK; это не означает полного покрытия всех вариантов TEST.md.

## Условия и безопасность

- Коммит: `47be778931a7efcadd52a151cc108af5e0bb6603`, плюс существующие незакоммиченные исправления сценариев, включая поддержку ссылок на архивы.
- По прямому указанию пользователя удалены все существующие кластеры до тестов и все созданные кластеры после тестов. Предписание TEST.md сохранять исходный кластер заменено этим указанием.
- Перед тестом обнаружен один кластер: `16/sybsys` на ALSE-1.8.6, online, `/var/lib/postgresql/16/sybsys`. Он удалён. На остальных шести списки были пустыми.
- Снимки предыдущего прогона сохранены в `D:/Ai/pgcc-test-snapshots-20260909-125004/`. Новый снимок и пробный импорт в этом прогоне не выполнялись; восстановимость текущего состояния не подтверждена. Удалённый sybsys можно восстановить только при наличии подходящего бэкапа/снимка; совпадение со старым снимком не гарантируется.
- Проверялся заново собранный пакет `tmp/rerun-151041/claster-creator-2.1.1.deb`, а не прежний dist-пакет.
- Использован именно `/mnt/d/Ai/pg_claster_creator/tmp/16-asvd-20260906-190608-dmp.tar.gz` (534313 байт). Это горячий архив, поэтому сначала создавался пустой QA-кластер, затем выполнялось восстановление asvd.
- Семейства серверов не заменялись ради успешного результата. Архив, расширения и данные не упрощались.
- Исправления продукта в этом прогоне не вносились. Существующие task-specific helper’ы из tmp/save переиспользованы; в повторный запуск добавлена проверка ссылок, preflight принимает идентификатор прогона.

## SHA-256

| Файл | SHA-256 |
|---|---|
| create-claster.sh | `6c170d18611bd77d2d4bea18442c3bb10c19947fe3ab7c6829014cc60e61ac66` |
| create-claster-backup.sh | `9eb7ac2586a062085d158587b87f480a098125009e710c9ead486263e8d6ab54` |
| create-claster-deb.sh | `30890a0014902b10ac37edc3402089b525039168671dce40995116a919cfca6d` |
| tmp/rerun-151041/claster-creator-2.1.1.deb | `ea8c6c3b7ea93e0d4e625b456fe8cd970ac3fce840859949344c4754d48d5dba` |
| tmp/16-asvd-20260906-190608-dmp.tar.gz | `15b74b79e5cf1921655e2dcaeed1c120ca6bc720fb7bb1747e1371e6c8e17c55` |

## Результаты по WSL

| WSL | Сервер | Очистка до | Создание | Ссылки | Рестори asvd | Очистка после / оставшиеся кластеры |
|---|---|---|---|---|---|---|
| smolensk-1.6.14-mg12.4.0 | postgrespro-ent 16 | OK | OK | OK | OK | OK / 0 |
| ALSE-1.7.9-UU1 | postgrespro-ent 17 | OK | OK | OK | FAIL | OK / 0 |
| alse-1.8.2.uu1-mg15.7.0 | tantor-free 16 | OK | OK | OK | FAIL | OK / 0 |
| ALSE-1.8.6 | postgrespro-ent 16 | OK | OK | OK | FAIL | OK / 0 |
| alse-1.8.5-mg16.3.0 | postgrespro-ent 17 | OK | OK | OK | FAIL | OK / 0 |
| alse-1.8.3.uu1-mg15.8.4 | postgrespro-ent 16 | OK | OK | OK | FAIL | OK / 0 |
| alse-1.8.4-mg16.3.0 | tantor-free 16 | OK | OK | OK | FAIL | OK / 0 |

## Ошибки и ограничения

1. ALSE-1.7.9-UU1, ALSE-1.8.6, alse-1.8.5-mg16.3.0 и alse-1.8.3.uu1-mg15.8.4: `pg_restore` rc=1, `relation "schedule.at" does not exist` при COPY. Перед этим создавалось расширение pgpro_scheduler. Совместимость расширения источника/назначения требует отдельного исследования; причина не считается окончательно установленной.
2. alse-1.8.2.uu1-mg15.7.0 и alse-1.8.4-mg16.3.0: `pg_restore` rc=1, `extension "pg_variables" is not available`. На Tantor отсутствует необходимое расширение.
3. ALSE-1.8.6: `dpkg --audit` до/после сообщает о частично настроенном `man-db`. Все шесть man-страниц при этом открылись с rc=0. Пакетный дефект среды не исправлялся.
4. Первый вызов теста alse-1.8.4-mg16.3.0 завершился ошибкой WSL `0x80370107` до появления тестового журнала. Повторный вызов выполнил тест и очистку. На части WSL также выводилось предупреждение о невозможности запуска systemd user session root.
5. Прежнее зависание dpkg на Astra 1.6 в этом прогоне не воспроизвелось: mode 1, установка modes 2–4 и повтор mode 4 завершились rc=0.

На шести WSL зависимые проверки бэкапов, холодного восстановления и DEB остановлены после ошибки исходного восстановления, а не выполнены с подменённой базой. На Astra 1.6 контрольная БД qa55416 дополняла восстановленную asvd: горячие проверки используют qa55416; холодный архив включает asvd.

## Команды и воспроизведение

Корень REPO: `/mnt/d/Ai/pg_claster_creator`. Каждая строка ниже запускалась через `wsl -d WSL -u root --exec bash`:

```bash
$REPO/create-claster-deb.sh --mode 1 --non-interactive --output-dir $REPO/tmp/rerun-151041
$REPO/tmp/save/rerun-2.1.1.sh "$REPO" 151041 "$WSL" "$VERSION" "$PACKAGE" "$FAMILY" "$PORT"
$REPO/tmp/save/rerun-preflight.sh "$REPO" "$WSL" 151041
```

| WSL | VERSION | PACKAGE | FAMILY | PORT / QA_CLUSTER |
|---|---|---|---|---|
| smolensk-1.6.14-mg12.4.0 | 16 | postgrespro-ent-16-server | postgrespro-ent | 55416 / qa55416 |
| ALSE-1.7.9-UU1 | 17 | postgrespro-ent-17-server | postgrespro-ent | 55417 / qa55417 |
| alse-1.8.2.uu1-mg15.7.0 | 16 | tantor-free-server-16 | tantor-free | 55418 / qa55418 |
| ALSE-1.8.6 | 16 | postgrespro-ent-16-server | postgrespro-ent | 55419 / qa55419 |
| alse-1.8.5-mg16.3.0 | 17 | postgrespro-ent-17-server | postgrespro-ent | 55420 / qa55420 |
| alse-1.8.3.uu1-mg15.8.4 | 16 | postgrespro-ent-16-server | postgrespro-ent | 55421 / qa55421 |
| alse-1.8.4-mg16.3.0 | 16 | tantor-free-server-16 | tantor-free | 55422 / qa55422 |

В USER-ARCHIVE команда: `create-claster.sh --action restore --backup-file "$REPO/tmp/16-asvd-20260906-190608-dmp.tar.gz" --pg-version "$VERSION" --cluster-name "qa$PORT" --database asvd --backup-dir /BACKUP/pgcc-test`.

Полные команды остальных фаз находятся в переиспользованных helper’ах tmp/save, названных в rerun-2.1.1.sh. Фазы фиксируют время начала/окончания, rc и pg_lsclusters в full.log.

## Подтверждённые результаты Astra 1.6

- Горячий и холодный архивы созданы и прочитаны; pg_restore --list успешен.
- Новая БД восстановлена. Отказ без overwrite: rc=1, unchanged_after_refusal=yes. Разрешённое overwrite: rc=0.
- Контрольный набор: 100 строк, checksum `57a63c0d2d3517bf733aaae36ed8387e`; тот же результат до и после обоих перемещений данных.
- Ротация count: 2 архива, sentinel сохранён; лимит 1B: сохранён 1 самый новый архив, sentinel сохранён.
- DEB modes 1–4 собраны с rc=0; modes 2–4 установлены с rc=0 и online целевыми кластерами. Mode 4 повторно установлен с rc=0.
- Старый TCP-порт после переключения: pg_isready rc=2; новый: rc=0. Возврат порта и перемещение туда/обратно: rc=0.
- Удаление qa55416m2 через create-claster.sh: rc=0. Оставшиеся QA-кластеры удалены финальной очисткой.

## Полнота плана TEST.md

OK в results.tsv означает успешную выполненную фазу, а не автоматически весь пункт плана. Ниже полный реестр обязательных идентификаторов (пример шаблона PT-CC-08 не является отдельной проверкой).
BLOCKED означает, что полная ожидаемая совокупность вариантов не подтверждена. Основания:
A — на шести WSL не восстановился исходный архив; зависимые проверки заблокированы.
B — переиспользованный автоматический прогон покрывает только часть пункта; оставшиеся интерактивные, fault-injection или clean-snapshot варианты в этом запуске не выполнены. Их риск не принят и полный успех не заявляется.

| Пункт и полное имя | Итог по всем 7 WSL | Фактическое покрытие / причина |
|---|---|---|
| PT-ENV-01 — Паспорт стенда и исходников | BLOCKED | Паспорта, хеши и место есть в full.log; полный паспорт и проверка восстановления снимка не завершены (B). |
| PT-ENV-02 — Репозитории и семейства серверов | BLOCKED | apt-cache policy и доступные пакеты сохранены; проверено одно установленное семейство на стенд, не все семейства на чистых снимках (B). |
| PT-ENV-03 — Синтаксис, версия, справка и man | BLOCKED | Все 3 bash -n, --help, --version, неизвестный ключ, 6 man: ожидаемые rc. Короткие формы и полное соответствие документации отдельно не проверялись (B). |
| PT-ENV-04 — Права root и поиск конфигурации | BLOCKED | Справка nobody rc=0, административные вызовы rc=1; конфиг через установленную ссылку работает. Все варианты поиска не проверялись (B). |
| PT-ENV-05 — Сохранность `.new-claster.config` | BLOCKED | Хеш конфига до/после создания записан; отменённые и ошибочные интерактивные ветки не покрыты (B). |
| PT-CC-01 — Установка обязательного пакета | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-CC-02 — Выбор и установка серверного комплекта | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-CC-03 — Служебная структура `/.postgres` | BLOCKED | Структура /.postgres записана; ссылки на архив и backup-каталог проверены. Все опасные цели не проверялись (B). |
| PT-CC-04 — Главное меню и навигация | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-CC-05 — Информация о кластерах и БД | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-CC-06 — Интерактивная установка кластера | BLOCKED | CLI-создание на всех семи: OK; интерактивная матрица не выполнена (B). |
| PT-CC-07 — Роли, настройки и расширения нового кластера | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-CC-08 — Конфликты имени, каталога и порта при установке | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-CC-09 — Переключение порта | BLOCKED | Astra 1.6: перенос порта туда/обратно и pg_isready OK; остальные варианты B, остальные WSL A. |
| PT-CC-10 — Перемещение данных | BLOCKED | Astra 1.6: перенос туда/обратно с неизменной checksum OK; остальные варианты B, остальные WSL A. |
| PT-CC-11 — Интерактивный выбор горячего бэкапа | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-CC-12 — Горячий бэкап существующей БД | BLOCKED | Astra 1.6: горячий архив, метаданные, права, pg_restore --list OK; вариант через каталог-ссылку отдельно не выполнен (A/B). |
| PT-CC-13 — Холодный бэкап кластера | BLOCKED | Astra 1.6: online cold без очистки WAL OK; down и очистка WAL не выполнены (A/B). |
| PT-CC-14 — Отказ бэкапа | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-CC-15 — Фильтрация и путь к архиву | BLOCKED | Все семь: обычный файл, относительная ссылка, ссылка на каталог бэкапов, исключение битой ссылки/каталога, оба меню OK. Полная матрица повреждённых архивов не выполнена (B). |
| PT-CC-16 — Горячий рестори в новую БД | FAIL | FAIL на шести: USER-ARCHIVE rc=1 (schedule.at или pg_variables). Astra 1.6: USER-ARCHIVE и контрольный рестори rc=0. |
| PT-CC-17 — Горячий рестори поверх существующей БД | BLOCKED | Astra 1.6: отказ без overwrite и разрешённая перезапись OK; полный набор служебных БД не покрыт (A/B). |
| PT-CC-18 — Холодный рестори | BLOCKED | Astra 1.6: холодный рестори mode 3 под новым именем/портом OK; старый архив без unit и все пути не покрыты (A/B). |
| PT-CC-19 — Конфликты холодного рестори | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-CC-20 — Удаление БД | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-CC-21 — Удаление кластера | BLOCKED | Astra 1.6: delete без бэкапа OK; независимая очистка всех WSL OK. Полная интерактивная матрица не выполнена (B). |
| PT-CC-22 — CLI, ENV и позиционные аргументы | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-CC-23 — WSL, PARSEC и тайм-ауты | BLOCKED | Операции прогона ограничены timeout, конечные состояния проверены. Имитация зависшего systemctl в этом прогоне не запускалась (B). |
| PT-BK-01 — Аргументы и валидация | BLOCKED | Astra 1.6: 5 некорректных наборов аргументов и штатные вызовы проверены; все единицы и перестановки не покрыты (A/B). |
| PT-BK-02 — Одиночный плановый горячий бэкап | BLOCKED | Astra 1.6: custom каталог OK; дефолтный вариант отдельно не выполнен (A/B). |
| PT-BK-03 — Ротация по количеству | BLOCKED | Astra 1.6: count=2 и sentinel сохранён; полная матрица разных кластеров не выполнена (A/B). |
| PT-BK-04 — Ротация по размеру | BLOCKED | Astra 1.6: лимит 1B, самый новый и sentinel сохранены; остальные WSL A. |
| PT-BK-05 — Ошибка бэкапа и блокировка | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-BK-06 — Создание cron-задачи | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-DEB-01 — Интерактивный выбор режимов | BLOCKED | Все семь: выбор архивной ссылки в меню сборщика OK; Astra 1.6: CLI modes 1–4 OK. Полный интерактив не выполнен (B). |
| PT-DEB-02 — Неинтерактивная валидация | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-DEB-03 — Режим 1 и содержимое пакета | BLOCKED | Свежий mode 1 установлен на всех семи; повторная установка mode 1 и полный аудит содержимого в этом прогоне не выполнены (B). |
| PT-DEB-04 — Имена пакетов и скелет | BLOCKED | Astra 1.6: modes 1–4 и output-dir OK; все отказные варианты не проверялись (A/B). |
| PT-DEB-05 — Зависимости PostgreSQL Pro | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-DEB-06 — Дополнительные зависимости | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-DEB-07 — `create-claster-deb-last.sh` | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-DEB-08 — Установка mode 2 | BLOCKED | Astra 1.6: apt reinstall mode 2 OK; отсутствующие зависимости/занятый порт отдельно не покрыты (A/B). |
| PT-DEB-09 — Установка mode 3 | BLOCKED | Astra 1.6: mode 3 OK; все повторные/конфликтные варианты не покрыты (A/B). |
| PT-DEB-10 — Установка mode 4 | BLOCKED | Astra 1.6: mode 4 OK с контрольным архивом; остальные WSL A; занятый порт не проверялся (B). |
| PT-DEB-11 — Идемпотентность и маркеры | BLOCKED | Astra 1.6: повтор mode 4 OK; прерывание/устаревшие маркеры не проверялись (A/B). |
| PT-DEB-12 — Существующий кластер без force | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-DEB-13 — `CLASTER_FORCE_INSTALL` | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-DEB-14 — `CLASTER_FORCE_DB_INSTALL` | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-DEB-15 — Создание data-root при установке | BLOCKED | Astra 1.6: custom data-root работает; существовавший корень не удалялся перед установкой (A/B). |
| PT-DEB-16 — Установка зависимостей через APT | BLOCKED | Полный сценарий не выполнен сохранённым автоматическим прогоном (B); при зависимости от исходной БД на шести WSL также A. |
| PT-E2E-01 — Существующий кластер → горячий архив → новая БД | BLOCKED | На шести исходное восстановление FAIL, сквозной сценарий BLOCKED (A); Astra 1.6: контрольная БД восстановлена внутри того же кластера, не другого (B). |
| PT-E2E-02 — Существующий кластер → холодный архив → удаление → рестори | BLOCKED | Astra 1.6: холодный архив и mode 3 OK, но источник перед рестори не удалялся (A/B). |
| PT-E2E-03 — Горячий архив → DEB mode 4 → чистая система | BLOCKED | Astra 1.6: mode 4 с точным пакетом и контрольным архивом OK; повышение версии/занятый порт не проверялись (A/B). |
| PT-E2E-04 — Холодный архив → DEB mode 3 → чистая система | BLOCKED | Astra 1.6: mode 3 OK; чистый снимок и повтор mode 3 не выполнены (A/B). |
| PT-E2E-05 — Плановый бэкап и ротация | BLOCKED | Astra 1.6: ротация OK; cron и рестори оставшегося после ротации архива не выполнены (A/B). |

## Фазы по каждому стенду и артефакты

Для каждого стенда в `tmp/rerun-151041/WSL/`: `full.log` — stdout/stderr теста; `results.tsv` — флаги и rc; `preflight.log` — независимые проверки; `final-state.log` — финальная инвентаризация и SHA-256 сохранённых архивов/DEB (включает прежние артефакты).

### smolensk-1.6.14-mg12.4.0

[Полный лог](../tmp/rerun-151041/smolensk-1.6.14-mg12.4.0/full.log), [preflight](../tmp/rerun-151041/smolensk-1.6.14-mg12.4.0/preflight.log), [финальное состояние](../tmp/rerun-151041/smolensk-1.6.14-mg12.4.0/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
PACKAGE-MODE1	OK	rc=0
EMPTY-CLUSTERS	OK	rc=0
BACKUP-LINKS	OK	rc=0
SYNTAX-create-claster.sh	OK	rc=0
HELP-create-claster.sh	OK	rc=0
VERSION-create-claster.sh	OK	rc=0
SYNTAX-create-claster-backup.sh	OK	rc=0
HELP-create-claster-backup.sh	OK	rc=0
VERSION-create-claster-backup.sh	OK	rc=0
SYNTAX-create-claster-deb.sh	OK	rc=0
HELP-create-claster-deb.sh	OK	rc=0
VERSION-create-claster-deb.sh	OK	rc=0
CREATE	OK	rc=0
USER-ARCHIVE	OK	rc=0
DATA	OK	rc=0
HOT	OK	rc=0
COLD	OK	rc=0
RESTORE-OVERWRITE	OK	rc=0
ROTATION	OK	rc=0
DEB-BUILD	OK	rc=0
DEB-INSTALL-2	OK	rc=0
DEB-INSTALL-3	OK	rc=0
DEB-INSTALL-4	OK	rc=0
PORT-MOVE	OK	rc=0
DEB-REINSTALL	OK	rc=0
DELETE	OK	rc=0
CLEANUP-AFTER	OK	rc=0
```

### ALSE-1.7.9-UU1

[Полный лог](../tmp/rerun-151041/ALSE-1.7.9-UU1/full.log), [preflight](../tmp/rerun-151041/ALSE-1.7.9-UU1/preflight.log), [финальное состояние](../tmp/rerun-151041/ALSE-1.7.9-UU1/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
PACKAGE-MODE1	OK	rc=0
EMPTY-CLUSTERS	OK	rc=0
BACKUP-LINKS	OK	rc=0
SYNTAX-create-claster.sh	OK	rc=0
HELP-create-claster.sh	OK	rc=0
VERSION-create-claster.sh	OK	rc=0
SYNTAX-create-claster-backup.sh	OK	rc=0
HELP-create-claster-backup.sh	OK	rc=0
VERSION-create-claster-backup.sh	OK	rc=0
SYNTAX-create-claster-deb.sh	OK	rc=0
HELP-create-claster-deb.sh	OK	rc=0
VERSION-create-claster-deb.sh	OK	rc=0
CREATE	OK	rc=0
USER-ARCHIVE	FAIL	rc=1
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.2.uu1-mg15.7.0

[Полный лог](../tmp/rerun-151041/alse-1.8.2.uu1-mg15.7.0/full.log), [preflight](../tmp/rerun-151041/alse-1.8.2.uu1-mg15.7.0/preflight.log), [финальное состояние](../tmp/rerun-151041/alse-1.8.2.uu1-mg15.7.0/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
PACKAGE-MODE1	OK	rc=0
EMPTY-CLUSTERS	OK	rc=0
BACKUP-LINKS	OK	rc=0
SYNTAX-create-claster.sh	OK	rc=0
HELP-create-claster.sh	OK	rc=0
VERSION-create-claster.sh	OK	rc=0
SYNTAX-create-claster-backup.sh	OK	rc=0
HELP-create-claster-backup.sh	OK	rc=0
VERSION-create-claster-backup.sh	OK	rc=0
SYNTAX-create-claster-deb.sh	OK	rc=0
HELP-create-claster-deb.sh	OK	rc=0
VERSION-create-claster-deb.sh	OK	rc=0
CREATE	OK	rc=0
USER-ARCHIVE	FAIL	rc=1
CLEANUP-AFTER	OK	rc=0
```

### ALSE-1.8.6

[Полный лог](../tmp/rerun-151041/ALSE-1.8.6/full.log), [preflight](../tmp/rerun-151041/ALSE-1.8.6/preflight.log), [финальное состояние](../tmp/rerun-151041/ALSE-1.8.6/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
PACKAGE-MODE1	OK	rc=0
EMPTY-CLUSTERS	OK	rc=0
BACKUP-LINKS	OK	rc=0
SYNTAX-create-claster.sh	OK	rc=0
HELP-create-claster.sh	OK	rc=0
VERSION-create-claster.sh	OK	rc=0
SYNTAX-create-claster-backup.sh	OK	rc=0
HELP-create-claster-backup.sh	OK	rc=0
VERSION-create-claster-backup.sh	OK	rc=0
SYNTAX-create-claster-deb.sh	OK	rc=0
HELP-create-claster-deb.sh	OK	rc=0
VERSION-create-claster-deb.sh	OK	rc=0
CREATE	OK	rc=0
USER-ARCHIVE	FAIL	rc=1
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.5-mg16.3.0

[Полный лог](../tmp/rerun-151041/alse-1.8.5-mg16.3.0/full.log), [preflight](../tmp/rerun-151041/alse-1.8.5-mg16.3.0/preflight.log), [финальное состояние](../tmp/rerun-151041/alse-1.8.5-mg16.3.0/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
PACKAGE-MODE1	OK	rc=0
EMPTY-CLUSTERS	OK	rc=0
BACKUP-LINKS	OK	rc=0
SYNTAX-create-claster.sh	OK	rc=0
HELP-create-claster.sh	OK	rc=0
VERSION-create-claster.sh	OK	rc=0
SYNTAX-create-claster-backup.sh	OK	rc=0
HELP-create-claster-backup.sh	OK	rc=0
VERSION-create-claster-backup.sh	OK	rc=0
SYNTAX-create-claster-deb.sh	OK	rc=0
HELP-create-claster-deb.sh	OK	rc=0
VERSION-create-claster-deb.sh	OK	rc=0
CREATE	OK	rc=0
USER-ARCHIVE	FAIL	rc=1
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.3.uu1-mg15.8.4

[Полный лог](../tmp/rerun-151041/alse-1.8.3.uu1-mg15.8.4/full.log), [preflight](../tmp/rerun-151041/alse-1.8.3.uu1-mg15.8.4/preflight.log), [финальное состояние](../tmp/rerun-151041/alse-1.8.3.uu1-mg15.8.4/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
PACKAGE-MODE1	OK	rc=0
EMPTY-CLUSTERS	OK	rc=0
BACKUP-LINKS	OK	rc=0
SYNTAX-create-claster.sh	OK	rc=0
HELP-create-claster.sh	OK	rc=0
VERSION-create-claster.sh	OK	rc=0
SYNTAX-create-claster-backup.sh	OK	rc=0
HELP-create-claster-backup.sh	OK	rc=0
VERSION-create-claster-backup.sh	OK	rc=0
SYNTAX-create-claster-deb.sh	OK	rc=0
HELP-create-claster-deb.sh	OK	rc=0
VERSION-create-claster-deb.sh	OK	rc=0
CREATE	OK	rc=0
USER-ARCHIVE	FAIL	rc=1
CLEANUP-AFTER	OK	rc=0
```

### alse-1.8.4-mg16.3.0

[Полный лог](../tmp/rerun-151041/alse-1.8.4-mg16.3.0/full.log), [preflight](../tmp/rerun-151041/alse-1.8.4-mg16.3.0/preflight.log), [финальное состояние](../tmp/rerun-151041/alse-1.8.4-mg16.3.0/final-state.log).

```text
CLEANUP-BEFORE	OK	rc=0
PACKAGE-MODE1	OK	rc=0
EMPTY-CLUSTERS	OK	rc=0
BACKUP-LINKS	OK	rc=0
SYNTAX-create-claster.sh	OK	rc=0
HELP-create-claster.sh	OK	rc=0
VERSION-create-claster.sh	OK	rc=0
SYNTAX-create-claster-backup.sh	OK	rc=0
HELP-create-claster-backup.sh	OK	rc=0
VERSION-create-claster-backup.sh	OK	rc=0
SYNTAX-create-claster-deb.sh	OK	rc=0
HELP-create-claster-deb.sh	OK	rc=0
VERSION-create-claster-deb.sh	OK	rc=0
CREATE	OK	rc=0
USER-ARCHIVE	FAIL	rc=1
CLEANUP-AFTER	OK	rc=0
```

## Очистка и оставленные артефакты

На всех семи CLEANUP-BEFORE=OK и CLEANUP-AFTER=OK. После завершения отдельный вызов подтвердил пустой pg_lsclusters, отсутствие каталогов кластеров второго уровня в /etc/postgresql и процессов postgres. В /DATA/pgcc-test, /DATA/pgcc-deb-test и /var/lib/postgresql файлов PG_VERSION нет.

Удаление выполнено штатным pg_dropcluster с прямой предварительной остановкой. Удалялись только точные unit-файлы выбранных кластеров и нормализованные остаточные конфигурации. Общий каталог логов не удалялся.

Намеренно сохранены исходный архив, старые снимки, свежий mode 1, тестовые архивы и DEB, логи, пакетные маркеры и пустые родительские тестовые каталоги. Это не работающие кластеры. На Astra 1.6 свежие архивы: /BACKUP/pgcc-test/16-qa55416-20260909-151150{,-dmp}.tar.gz; DEB modes 2–4: /var/tmp/pgcc-deb-tests/*qa55416*.deb. Хеши — в final-state.log.

В копиях full.log этого прогона маскированы хеши паролей и известный тестовый пароль. Исходные архивы, DEB и локальные служебные логи внутри WSL могут содержать учётные данные; публиковать их без дополнительной проверки нельзя. tmp игнорируется Git, поэтому для передачи журнала нужно отдельно приложить очищенные логи.

Журнал не переименован в -passed: есть FAIL и неполное покрытие (BLOCKED). Все исходные/тестовые кластеры удалены; никаких дополнительных тестовых процессов не оставлено.
