# Журнал тестирования claster-creator 2.4.0 — FAIL

Прогон: **2026-09-12 17:11:07–17:33:13 MSK**. План: `TEST.md`, раздел «План полного тестирования», S01–S10, 57 контрольных точек.

**Итог: FAIL. Полный план не закрыт.** Обнаружены ошибки живого переименования. После них выполнены независимые безопасные проверки и очистка. Незавершённые варианты явно отмечены BLOCKED ниже, а не засчитаны по частичным успешным действиям. Журнал переименован из `TEST-2.4.0-journal.md` в `TEST-2.4.0-journal-fail.md` по указанию пользователя. Суффикс passed недопустим.

Снимки WSL не создавались и не использовались. Общие каталоги /DATA, /BACKUP и /.postgres, исходные кластеры и серверные пакеты массово не удалялись.

## Проверенные байты

Git HEAD на старте: `34e59ae5a5ca73e3687ffdecd621698b7b317a2e`, master / release/2.x / v2.4.0. Рабочее дерево исходно чистое. В ходе тестов менялись только helpers, их индекс, правила LF для журналов и этот журнал. Три продуктовых сценария, исходный конфиг и выпущенный DEB не изменялись. Commit/push в этом прогоне не выполнялись.

| Файл | SHA256 |
|---|---|
| create-claster.sh | 167db668cce08314cce0f79d46ad18b3973cbd9601b26b82271bec2590787913 |
| create-claster-backup.sh | aa77cdfaf949cd689bc3f170480405023d94086a80cf69c23c4bd85383773d46 |
| create-claster-deb.sh | 521f5bd78e5df03893e37f9a7ed08a9a905b0068e3d53d5a4be72615f703c4c9 |
| dist/claster-creator-2.4.0.deb | 49510f17b23da11cc22fa70b40638e4831339e7cae6c4bf88f0ee555569ed62c |

## Матрица стендов

Номера W1–W7 используются в таблице контрольных точек.

| WSL | Имя | Установленный сервер | Базовый QA-порт | Исходный реестр |
|---|---|---|---|---|
| W1 | smolensk-1.6.14-mg12.4.0 | postgrespro-ent-16-server | 57210 | 16/asvd, 5432, online |
| W2 | ALSE-1.7.9-UU1 | tantor-se-server-17 | 57310 | пусто |
| W3 | alse-1.8.2.uu1-mg15.7.0 | tantor-free-server-16 | 57410 | пусто |
| W4 | alse-1.8.5-mg16.3.0 | postgrespro-ent-17-server | 57510 | пусто |
| W5 | alse-1.8.3.uu1-mg15.8.4 | tantor-free-server-16 | 57610 | пусто |
| W6 | alse-1.8.4-mg16.3.0 | postgrespro-ent-13-server | 57710 | пусто |
| W7 | ALSE-1.8.6 | tantor-be-server-18 | 57810 | пусто |

Живые QA-источники: `qa240_PORT`; копии: суффиксы `cold/m2/m3/m4/e/u/t`. Каталоги данных — штатные каталоги выбранного пакета и `/DATA/pgcc240-PORT*`. БД источника названа по QA-кластеру; набор включает 100 строк, дочернюю таблицу/FK, наследование/constraint, sequence, view/materialized view, функцию/триггер, отдельного владельца, LOGIN/NOLOGIN/ACL и доступное pgcrypto. Старый архив asvd не использовался.

## F1 — повторная подстановка имени в уже изменённые пути

**PT-CC-25: FAIL на W1–W6.** Живой вызов завершается rc=1. Пример W2, PostgreSQL/Tantor SE 17:

```text
Кластер: 17/qa240_57310u -> 17/qa240_57310uren
Данные: /var/lib/postgresql/tantor-se-17/qa240_57310u -> /var/lib/postgresql/tantor-se-17/qa240_57310uren
ОШИБКА: неожиданный путь после переименования:
/var/lib/postgresql/tantor-se-17/qa240_57310urenren
```

Воспроизведение: восстановить cold в отдельный QA-кластер `qa240_PORTu`, выбрать меню `4 → 1 → номер QA-кластера → qa240_PORTuren → y`. Это валидное имя; исходное имя является префиксом нового. Отмена перед этим сохраняла online.

Ожидалось: один суффикс, согласованные data/config/unit, сохранённые online и SQL. Фактически: физический каталог переименован один раз, но `data_directory` указывает на несуществующий путь с двойным суффиксом. Кластер остановлен, реестр показывает owner `<unknown>`; новый unit ещё не завершён.

Причина подтверждена чтением установленного `pg_renamecluster` и `create-claster.sh`: штатная команда уже обновляет пути в конфигурации, затем `rename_cluster_checked()` (около строк 1674–1697) выполняет безусловные `replace_literal_in_file`. Старый путь совпадает с префиксом уже нового пути и заменяется повторно. Это ошибка продукта, не ошибочный ввод helper-а.

Логи каждого из W1–W6: `tmp/full-2.4.0-20260912-1900/<WSL>/live-ui/RENAME-ONLINE.log`, `run.log`, `RENAME-ONLINE-clusters.log`, `results.tsv`. Пример страховочной копии W2: `/var/tmp/pgcc-rename.W7yFQV`.

Нужна идемпотентная корректировка только ещё старых ссылок/значений после pg_renamecluster, без замены префикса уже нового имени. Отдельно необходим regression old-name-prefix-of-new-name для реального pg_renamecluster и online/down. Исправление продуктового кода в этом прогоне не выполнялось.

## F2 — обрыв переименования на Astra 1.8.6

**PT-CC-25 / PT-CC-23: FAIL на W7.** Вызов `18/qa240_57810u → qa240_57810uren` оборвался после сообщения о страховочной копии `/var/tmp/pgcc-rename.j0dd82`; внешний WSL-вызов завершился rc=1, запись END шага и EXIT-очистка не выполнились. Кластер остался зарегистрирован под старым QA-именем и был online при последующей проверке. Двойной суффикс на этом стенде не подтверждён — переименование не дошло до этого этапа.

Системный журнал **17:21:26 MSK**:

```text
PARSEC-UNIT: [/lib/systemd/system/postgresql@.service] pdp_get_pid(1215) return NULL, Success
systemd[1]: Caught <SEGV> from unknown sender process.
kernel: systemd: systemd: potentially unexpected fatal signal 11.
```

Полная выборка: `tmp/full-2.4.0-20260912-1900/ALSE-1.8.6/rename-systemd-journal.log`. Это подтверждённый сбой systemd/WSL во время операции; точный внутренний дефект systemd здесь не установлен. В отличие от нового direct delete, rename вызывает `remove_cluster_service_files` без bounded-режима, где остаётся `systemctl disable`; этот путь требует отдельной проверки совместимости WSL/PARSEC.

В том же системном журнале есть ошибка syslog-ng со ссылкой на **старый, не принадлежащий прогону** `mod-astra-postgres-18-sybsys.conf` и отсутствующий `pg18_kv_parser`. Этот файл не менялся. Он не объявляется доказанной причиной SEGV.

Часть stdout не успела попасть в отдельный STEP.log до обрыва; она была прочитана из защищённого current.log перед очисткой. Последующая cleanup-ui использовала этот рабочий лог, поэтому для F2 сохранены run.log, внешний rc, приведённый фрагмент и системный журнал, а не полный STEP.log. Успешный FINAL после cleanup-ui означает только отдельную очистку, не успешное переименование.

## Что реально выполнено

Для каждого WSL логи расположены в `tmp/full-2.4.0-20260912-1900/<WSL>/`. Суффикс `1900` — идентификатор каталога, **не фактическое время старта**. Команды/ввод, START/END, rc и итог каждого запуска — в run.log/summary.log; stdout/stderr — в отдельных файлах. После live-шагов сохранялись реестр, службы, SHA конфигов и список артефактов. Пароли/хеши аутентификации маскировались; поиск открытых тестовых паролей/SCRAM/md5-хешей в опубликованных .log совпадений не дал.

| Каталог / helper | Проверка | Результат на каждом WSL |
|---|---|---|
| preflight / prx-test-wsl-preflight | ОС, пакеты, версии, три help/CLI, 6 man, конфиги и реестр | 56 PASS |
| fixtures / prx-test-release-fixtures | существующие 7 изолированных helpers: deletion/rename/power/menu/Tantor/tmp/config | PASS; системные команды здесь подменены, не доказательство живого rename |
| live / prx-test-live-regression core | create/data/hot/cold/restore/overwrite/port/move/rotation, DEB2–4 install/repeat/cleanup | 46 PASS |
| live-extra | отказ/ссылки/полный schema+data fingerprint/LOGIN, power UI, повтор без force, force2–4/forceDB | 69 PASS отдельных действий |
| live-ports | занятые TCP-порты, переустановка mode2/4 после удаления с stale markers | 15 PASS |
| guards | ошибка backup, реальный внешний flock, cron/все 5 расписаний | 19 PASS |
| live-ui | отмена, затем живое переименование с расширением имени | F1 или F2; дальнейшие зависимые шаги не зачтены |
| live-tail | независимая новая копия без rename: ENV down-port/move, реальная cron-команда, restore/fingerprint/LOGIN, delete DB, delete→cold restore | 32 PASS |
| package-journal / prx-test-package-journal | mode1 payload/metadata/6 man/байты/журнал 0644, gzip при env zstd, отказ всех modes без журнала | PASS |
| tmp/full-2.4.0-20260912-1900/direct-delete/<WSL>/ | отдельные online/down default/custom QA fixtures; реальный direct delete | PASS, без pg_dropcluster/syslog reload |
| final-audit.log | возврат реестра, двух конфигов, scripts-only 2.4.0; dpkg audit; QA-state cleanup | rc=0 |

В direct-delete fixture кластер создавался через pg_createcluster, autostart-ссылка задавалась helper-ом. Поэтому его результат доказывает **удаление**, а не исправность интерактивного создания или systemctl enable.

Успех отдельных вызовов force/restore/checksum не приравнивается автоматически ко всему соответствующему PT-ID. Все такие недостающие условия перечислены ниже.

## Все 57 контрольных точек

PASS — закрыта точка; FAIL — обнаружена ошибка; BLOCKED — точка не закрыта целиком. BLOCKED с уже успешными подшагами означает частичное покрытие. Не все BLOCKED причинно зависят от rename: часть не выполнялась после остановки полного прогона по дефектам, часть требует отсутствующего одноразового пакетного окружения. Они требуют следующего прогона, а не косметической смены статуса.

| ID и полное имя | W1 | W2 | W3 | W4 | W5 | W6 | W7 | Фактический результат / незакрытое условие |
|---|---|---|---|---|---|---|---|---|
| PT-ENV-01 — Паспорт стенда и исходников | PASS | PASS | PASS | PASS | PASS | PASS | PASS | preflight: паспорт/место/реестр/версии/SHA; около 28 GiB свободно на D: при малом SQL-наборе. |
| PT-ENV-02 — Репозитории и семейства серверов | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Доступные/установленные пакеты сохранены; нет отдельного vanilla-стенда и полной матрицы major/семейств. |
| PT-ENV-03 — Синтаксис, версия, справка и man | PASS | PASS | PASS | PASS | PASS | PASS | PASS | preflight: 56 проверок/WSL, три сценария, help/version/неизвестный ключ, шесть man; версии и байты совпали. |
| PT-ENV-04 — Права root и поиск конфигурации | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Приоритет/fallback/ссылки проверены fixtures; nonroot help/version всех и admin main проверены; весь административный nonroot-набор wrapper/builder не завершён. |
| PT-ENV-05 — Сохранность `.new-claster.config` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | live*: защищённые defaults сравнивались как значения после операций; разрешённые изменения отделены от defaults; финально оба конфига восстановлены. |
| PT-CC-03 — Служебная структура `/.postgres` | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Работа существующей структуры и собственной backup-ссылки проверена. Варианты отсутствующей общей /.postgres и всех опасных целей не выполнены. |
| PT-CC-02 — Выбор и установка серверного комплекта | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | fixtures проверили приоритет/выход/SE/BE/маски; live использовал явно выбранный установленный пакет. Сценарий установки отсутствующего комплекта не закрыт. |
| PT-CC-04 — Главное меню и навигация | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | fixtures и live-extra/ui/tail проверили навигацию/возврат и реальные действия; полная живая таблица всех экранов/ошибочных вводов не завершена. |
| PT-CC-05 — Информация о кластерах и БД | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | CLI info и реальные списки БД получены. Отдельная живая проверка info на down и полная таблица выравнивания/ANSI не завершены. |
| PT-CC-22 — CLI, ENV и позиционные аргументы | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Реальные CLI/ENV info, port, move-data, backup, restore, delete прошли; полный CLI>ENV>config-набор и ENV install не завершены. |
| PT-CC-06 — Интерактивная установка кластера | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | CREATE и DEB mode2 создали чистые кластеры; полная интерактивная установка default/custom с отменами не завершена. |
| PT-CC-07 — Роли, настройки и расширения нового кластера | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | DATA: роли/настройки/расширение/100 строк/LOGIN проверены; полная независимая сверка каждого свойства нового кластера не закрыта. |
| PT-CC-08 — Конфликты имени, каталога и порта при установке | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | DUPLICATE-INSTALL/INVALID-PORT и занятые TCP порты проверены; интерактивный reprompt, конфликт другого major и непустой data-dir не все выполнены. |
| PT-CC-09 — Переключение порта | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | CLI online port round-trip, ENV down port и состояние/SQL проверены; не вся таблица busy/current/invalid и всех конфигурационных файлов. |
| PT-CC-10 — Перемещение данных | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | CLI online и ENV down move в /DATA с SQL/состоянием прошли; возврат/default и все опасные/symlink/непустые цели не закрыты. |
| PT-CC-24 — Остановить/Запустить по текущему состоянию | PASS | PASS | PASS | PASS | PASS | PASS | PASS | fixtures: отмена/неоднозначность/гонка/ошибка; live-extra: n сохраняет online, y stop→down и start→online, SQL сохранён. |
| PT-CC-25 — Переименование кластера | FAIL | FAIL | FAIL | FAIL | FAIL | FAIL | FAIL | F1: двойная замена пути на W1–W6; F2: обрыв/systemd SEGV на W7. Down-rename и последующие варианты заблокированы. |
| PT-CC-11 — Интерактивный выбор горячего бэкапа | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Список/выбор БД использованы в удалении; полный интерактивный hot-selector и границы размеров не завершены. |
| PT-CC-12 — Горячий бэкап существующей БД | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | HOT, pg_restore list, метаданные и backup-dir symlink прошли. Физическая/регистрационная major проверялась fixture-ом, не отдельным живым mismatch-кластером. |
| PT-CC-15 — Фильтрация и путь к архиву | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Абсолютный путь и живая ссылка на hot прошли; вся таблица относительных/коротких имён, битых/посторонних/corrupt файлов не завершена. |
| PT-CC-16 — Горячий рестори в новую БД | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Новая БД: схема/ACL, все строки/sequence и LOGIN совпали; mode4 создавал другой кластер, но полный эталон на именно пустом по ролям target не сопоставлен. |
| PT-CC-17 — Горячий рестори поверх существующей БД | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | HOT-REFUSE/OVERWRITE: изменения сохранены при отказе, stale удалён, checksum восстановлен. Отдельные защиты всех системных БД не завершены. |
| PT-E2E-01 — Существующий кластер → горячий архив → новая БД | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Hot→новая БД и mode4→другой кластер прошли; полный эталон именно другой БД другого пустого по ролям кластера не закрыт. |
| PT-CC-13 — Холодный бэкап кластера | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Online/down cold, проверка архива и сохранение состояния прошли. Разрешённый reset WAL одноразовой копии не выполнялся. |
| PT-CC-18 — Холодный рестори | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Cold default/custom с правильным family-root и запуском/SQL прошёл; старый архив без unit и весь набор родительских symlink не закрыты. |
| PT-CC-19 — Конфликты холодного рестори | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Реальный duplicate cold отказ и fixtures dangling/save проверены; не все реальные конфликты data/config/live-unit/other-major. |
| PT-E2E-02 — Существующий кластер → холодный архив → удаление → рестори | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | tail: delete→cold restore и checksum прошли; полный конфигурационный/всех БД эталон повторного cold restore не сопоставлен. |
| PT-CC-14 — Отказ бэкапа | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Отказ /proc и ошибка backup без ротации проверены; ENOSPC, все stop/start/pg_dump-инъекции и повреждённые архивы не закрыты. |
| PT-CC-20 — Удаление БД | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Меню: отказ от backup+удаления сохранил БД; hot по умолчанию и удаление прошли, соседняя БД сохранена. Системные БД/все варианты подтверждений не закрыты. |
| PT-CC-21 — Удаление кластера | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Прямое online/down default/custom удаление, core cleanup и postinst force прошли; safety fixtures прошли. Не все живые варианты delete с cold/отменой и внешними объектами выполнены. |
| PT-CC-23 — WSL, PARSEC и тайм-ауты | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | FAIL | На W7 во время rename systemd получил SEGV, выполнение оборвалось. На W1–W6 отказа WSL в этой точке не было; ограниченные stop/start/delete прошли. |
| PT-BK-01 — Аргументы и валидация | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Неверный count/size, два лимита и отсутствие TTY проверены; полный набор единиц/порядка/пропущенных аргументов не закрыт. |
| PT-BK-02 — Одиночный плановый горячий бэкап | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Реальный wrapper→main и cron дали валидные архивы в отдельных каталогах; default backup-dir не использовался. |
| PT-BK-03 — Ротация по количеству | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Count=2 и посторонние файлы сохранены; одноимённая БД другого кластера в отдельном каталоге не проверялась. |
| PT-BK-04 — Ротация по размеру | PASS | PASS | PASS | PASS | PASS | PASS | PASS | live/live-extra: лимит 1B оставляет самый новый архив, даже больше лимита; старые своей маски удалены, чужой sentinel сохранён. |
| PT-BK-05 — Ошибка бэкапа и блокировка | PASS | PASS | PASS | PASS | PASS | PASS | PASS | guards: ошибка backup не ротирует 2 sentinel; реальный внешний flock отклоняет второй wrapper с сообщением. |
| PT-BK-06 — Создание cron-задачи | PASS | PASS | PASS | PASS | PASS | PASS | PASS | guards: все 5 расписаний/PTTY/count/size/запрос лимита/повтор; live-tail: именно сохранённая cron-команда запущена дважды без TTY и получила архив. |
| PT-E2E-05 — Плановый бэкап и ротация | PASS | PASS | PASS | PASS | PASS | PASS | PASS | live-tail: два запуска сохранённой cron-команды, count=1, restore newest, полный pg_dump fingerprint и LOGIN совпали. |
| PT-DEB-01 — Интерактивный выбор режимов | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | fixtures: неверный режим/семейство/EOF/back и заполнение mode2; mode1 без stdin прошёл. Все интерактивные modes и границы KB–GB не завершены. |
| PT-DEB-02 — Неинтерактивная валидация | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Реальные сборки mode2–4 полными аргументами прошли; поочерёдное исключение каждого обязательного аргумента и все неверные типы/пути не закрыты. |
| PT-DEB-03 — Режим 1 и содержимое пакета | PASS | PASS | PASS | PASS | PASS | PASS | PASS | package-journal: mode1 metadata/contents/6 man/байты, исторический журнал 0644, отказ всех modes без него; gzip при env zstd. Старые dpkg читают/устанавливают 2.4.0. |
| PT-DEB-04 — Имена пакетов и скелет | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Имена mode1–4 и tmp ownership/error/symlink fixtures прошли; полная отдельная таблица отказа overwrite и --force не завершена. |
| PT-DEB-05 — Зависимости PostgreSQL Pro | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Точные зависимости реально собранных семейств проверены; minima 14/16 и выбор новых Postgres Pro 16–18 через чистый APT не выполнены. |
| PT-DEB-06 — Дополнительные зависимости | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Полная таблица --depends/dedup/invalid не выполнялась в этом прогоне. |
| PT-DEB-07 — `create-claster-deb-last.sh` | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Живое создание/перезапуск last.sh и fallback в недоступном каталоге не выполнялись. |
| PT-CC-01 — Установка обязательного пакета | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Во всех семи WSL common уже установлен. Реальная установка без common требует отдельного одноразового пакетного окружения; удаление зависимостей не выполнялось. |
| PT-DEB-08 — Установка mode 2 | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Mode2 fresh target и TCP conflict прошли, rc=0; отсутствующие пакетные зависимости не устанавливались. |
| PT-DEB-09 — Установка mode 3 | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Cold mode3 fresh/repeat/checksum прошли; полный независимый SQL/ACL/всех БД эталон на package target не сопоставлен. |
| PT-DEB-10 — Установка mode 4 | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Hot mode4 fresh/repeat/busy-port/query прошли; полный эталон ролей/LOGIN/ACL именно package target не закрыт. |
| PT-DEB-11 — Идемпотентность и маркеры | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Повтор и stale markers после удаления проверены live-ports. Прерывание после .cluster-created и продолжение mode3/4 не выполнялись. |
| PT-DEB-12 — Существующий кластер без force | PASS | PASS | PASS | PASS | PASS | PASS | PASS | live-extra: контрольная qa_keep сохранена при повторной установке без force modes2/3/4; rc=0. |
| PT-DEB-13 — `CLASTER_FORCE_INSTALL` | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | FORCE-CLUSTER modes2/3/4 реально выполнен на всех WSL, qa_keep исчезла; весь SQL-эталон после каждого force отдельно не сопоставлен. |
| PT-DEB-14 — `CLASTER_FORCE_DB_INSTALL` | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | FORCE-DB и system_identifier/query прошли; оба флага отклонены. Mode3-only flag, целевая мутация и отдельный соседний DB sentinel проверены не полностью. |
| PT-DEB-15 — Создание data-root при установке | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Отсутствующий собственный root подтверждён для mode2 в extra; отдельного полностью отсутствующего root для mode4 не было. |
| PT-DEB-16 — Установка зависимостей через APT | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Зависимости уже удовлетворены. Реальные apt/dpkg/apt-f сценарии без них не выполнялись; server/common не удалялись. |
| PT-E2E-03 — Горячий архив → DEB mode 4 → чистая система | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Нет чистого пакетного окружения с новой допустимой Postgres Pro; успех busy-port mode4 с уже установленным сервером не заменяет этот ID. |
| PT-E2E-04 — Холодный архив → DEB mode 3 → чистая система | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | BLOCKED | Mode3 exact major/repeat/checksum прошли; полный независимый SQL-эталон и interrupted-marker часть не завершены. |

Ключевой дефицит среды: все семь стендов уже содержат common/выбранный server. Их удаление ради «чистого APT» не выполнялось. Отсутствие vanilla и комбинаций newer Postgres Pro также не выдаётся за SKIPPED/PASS.

## Очистка и сохранённая диагностика

После F1 автоматическая очистка **правильно отказалась** удалять неожиданный data path. Это добавило `originals-preserved FAIL` в live-ui: в реестре оставался QA-кластер, а не был утрачен исходный asvd. Эти неуспешные записи сохранены.

Затем на W1–W6 отдельно проверены: имя отсутствовало в baseline, фактический data-dir строго принадлежит QA, MainPID=0 у old/new служб, реальный pg_ctl status=3. Сохранена повреждённая конфигурация; только у QA-кластера data_directory административно приведён к реально существующему каталогу, затем выполнен обычный delete и удалён старый QA-unit. Логи: recovery-rename-2/recovery.log. Это **административная очистка**, не исправление продукта и не PASS rename.

Первая попытка recovery-rename остановилась до изменения конфигурации: унаследованный ERR trap счёл ожидаемый pg_ctl status=3 ошибкой. Helper исправлен на условный вызов; повтор имеет отдельный лог. Ошибка обвязки не скрыта и не прибавлена к F1.

На W7 старый QA-кластер удалён отдельной штатной cleanup-ui без подмены пути. В финале:

- Реестр совпал с исходным на всех семи WSL. W1: только 16/asvd, 5432, online; W2–W7: пусто.
- Для исходного asvd не выполнялись изменяющие операции; SQL-checksum его пользовательских БД до/после отдельно не снимался.
- Оба системных .new-claster.config совпали с baseline; общий конфиг проекта не изменён.
- Установлены исходные scripts-only пакеты 2.4.0; три сценария байт-в-байт совпали с проверенными исходниками; dpkg --audit пуст.
- Тестовые data/config/unit/cron удалены. Общие /DATA, /BACKUP, /.postgres и чужие syslog-файлы не удалялись.
- Собственные deployment markers выведены из /var/lib/claster-creator в защищённый retained-markers. Это восстановимые диагностические файлы, а не оставленные активные планы.
- После прямого online/down delete в реестре не осталось и qadel-кластеров.

Защищённые артефакты сохранены **внутри соответствующей WSL**:
`/var/tmp/pgcc240-PORT{,-extra,-ports,-ui,-tail}` (root:root, 0700): hot/cold, DEB2–4, копии конфигов, повреждённая rename-конфигурация и retained-markers. Отдельные страховочные каталоги `/var/tmp/pgcc-rename.*` перечислены в RENAME-ONLINE логах. Архивы содержат данные/роли — публично их не публиковать. SHA архивов и DEB перечислены в artifact-sha256.log и final-audit.log каждого WSL. Логи /var/log/pgcc-tests оставлены как диагностика.

Mode1 проверочные DEB находятся в `tmp/full-2.4.0-20260912-1900/<WSL>/package-journal/artifacts/`; выпущенный `dist/claster-creator-2.4.0.deb` не перезаписывался. Упакованный historical passed-журнал относится к 2.1.2, не подтверждает успешность 2.4.0.

Raw-логи/архивы в tmp игнорируются Git. Этот корневой fail-журнал содержит существенные доказательства/ограничения самостоятельно и не игнорируется. Никаких commit/push или изменения тега не выполнялось.

## Следующий прогон

Сначала исправить/проверить F1 и WSL/PARSEC путь F2; затем повторить live rename online/down, включая prefix-имена, и закрыть все BLOCKED варианты. Для сценариев отсутствующих зависимостей требуется отдельное одноразовое пакетное окружение. Исторические passed-журналы не изменять; этот FAIL не переименовывать задним числом в passed.
