# Тестирование pg_claster_creator 2.5.7

Дата: 24.09.2026, MSK (UTC+03:00). Идентификатор:
`run-20260924-152642`.

Программа: [TEST.md](TEST.md), разделы «Начало тестирования» и S01–S10;
61 обязательный ID. Запрошенная параллельность — 8 потоков, не более одной
активной цепочки на WSL. Пропуски не считаются ошибками.

## Итог

В выполненных проверках ошибок продукта не выявлено. Все восемь WSL завершили
основную цепочку, дополнительную config/ENV-цепочку, изолированную регрессию
mode 6/create-replace и обязательную очистку с кодом 0.

На `alse-1.8.3.uu1-mg15.8.4` после прежнего сбоя WSL отсутствовал весь
PostgreSQL-стек. Перед read-only gate восстановлен исторически зафиксированный
baseline `tantor-free-server-16` 16.8, оба common-пакета и локальный
`claster-creator 2.5.7`. Затем стенд наравне с остальными прошёл удаление,
установку через продукт, проверку той же minor и финальное восстановление.

В `results.tsv` восьми стендов — **4592 записи: 4472 PASS и 120 успешных
сверок ожидаемого/фактического rc**. Строк FAIL нет. На каждом стенде успешны
10 фаз, 8 fixture-наборов и 5 итоговых сообщений новой регрессии mode 6 /
create-replace. Offline publisher: GitFlic 20/20, GitHub 14/14.

По явному правилу пользователя пропуски не считаются ошибками и при отсутствии
FAIL не препятствуют суффиксу `passed`. Перечисленные ниже непроверенные варианты
остаются «Не тестировалось» и не объявляются PASS.

## Время

Общее календарное время — **10 мин 23 с, 15:27:11–15:37:34 MSK**: от первого
read-only gate до окончания offline publisher/checksum. Пересекающиеся интервалы
не складывались. Ошибочный первый вызов offline publisher без обязательного
аргумента завершился до запуска тестов; исправленный вызов выполнен 20/20.

| WSL | Основная цепочка и очистка | Время | config/ENV и очистка |
|---|---:|---:|---:|
| alse-1.6.14-mg12.4.0 | 15:29:05–15:33:32 | 4 мин 27 с | 15:35:09–15:35:59, 50 с |
| alse-1.7.9-uu1 | 15:28:55–15:33:48 | 4 мин 53 с | 15:35:09–15:35:59, 50 с |
| alse-1.8.2.uu1-mg15.7.0 | 15:28:56–15:34:08 | 5 мин 12 с | 15:35:09–15:36:03, 54 с |
| alse-1.8.3.uu1-mg15.8.4 | 15:28:56–15:34:07 | 5 мин 11 с | 15:35:10–15:36:03, 53 с |
| alse-1.8.4-mg16.3.0 | 15:28:56–15:34:50 | 5 мин 54 с | 15:35:10–15:36:09, 59 с |
| alse-1.8.5-mg16.3.0 | 15:28:56–15:34:08 | 5 мин 12 с | 15:35:10–15:36:03, 53 с |
| alse-1.8.6-mg16.5.0 | 15:28:57–15:34:12 | 5 мин 15 с | 15:35:10–15:36:06, 56 с |
| mint22-3 | 15:28:57–15:34:54 | 5 мин 57 с | 15:35:11–15:36:08, 57 с |

## Стенды и серверы

Read-only minor gate подтвердил доступность исходной версии в APT на всех восьми
стендах. Оба common-пакета удалялись и устанавливались именно через
`create-claster.sh`. Единственная предварительная установка APT выполнялась для
восстановления утраченного исходного baseline `alse-1.8.3` до начала gate.

| WSL | Серверный пакет | Исходная → итоговая major.minor | Порт | Результат |
|---|---|---:|---:|---|
| alse-1.6.14-mg12.4.0 | postgrespro-ent-16-server | 16.2 → 16.2 | 60100 | PASS |
| alse-1.7.9-uu1 | tantor-se-server-17 | 17.9 → 17.9 | 60200 | PASS |
| alse-1.8.2.uu1-mg15.7.0 | tantor-free-server-16 | 16.6 → 16.6 | 60300 | PASS |
| alse-1.8.3.uu1-mg15.8.4 | tantor-free-server-16 | 16.8 → 16.8 | 60400 | PASS |
| alse-1.8.4-mg16.3.0 | postgrespro-ent-13-server | 13.23 → 13.23 | 60500 | PASS |
| alse-1.8.5-mg16.3.0 | tantor-be-server-18 | 18.1 → 18.1 | 60600 | PASS |
| alse-1.8.6-mg16.5.0 | tantor-se-server-17 | 17.9 → 17.9 | 60700 | PASS |
| mint22-3 | postgresql-16 | 16.15 → 16.15 | 60800 | PASS |

## Проверенные исходники и пакет

Проверялся commit `dc466d8d4026dafb755b9b738f27696a3efdbbd1`. Во время этого
прогона commit, ветки, теги и удалённые репозитории не изменялись.

| Файл | SHA-256 |
|---|---|
| create-claster.sh | `0fd9f33b78c7e2382e0b95b2f2a93feabe223fe66a194e0cbcddc540462c1edf` |
| create-claster-backup.sh | `7044a8b17ba4c7bae9d85dddc46d479ef873131ac67c7a064dea3bbef02fad83` |
| create-claster-deb.sh | `b672dd4a777533304e5555a23fe1418487e09f9b5da5fe186c2a8bf70c9ed0bb` |
| .new-claster.config | `ad11caf6fa1a42276a5f5ddc3fa5856847e43baebcd0194f1bc07314f812dc81` |

DEB имеет `Package: claster-creator`, `Version: 2.5.7`, `Architecture: all`;
локальный `claster-creator-2.5.7.sha256` совпадает. Во всех восьми WSL
проверены gzip-архивы DEB, LICENSE, разрешённые Markdown, конфиг, три сценария,
шесть MAN и исключение development-каталогов.

## Выполненные группы

| Группа | Результат на доступных WSL |
|---|---|
| Minor gate, удаление пакетов, bootstrap common/server | 8/8 PASS |
| Syntax/version/help/MAN и release fixtures | 8/8 PASS |
| Core: данные, hot/cold backup/restore, DEB mode 2–4 | 8/8 PASS |
| Extra, ports, UI, edges и SQL mode 5 | 8/8 PASS |
| APT/dpkg dependency installation | 8/8 PASS |
| Interactive install, power, rename/delete, major/name | 8/8 PASS |
| Config/ENV, wrapper, cron, rotation, mode 1–5, data-root | 8/8 PASS |
| Mode 6 и create/replace fixture/postinst guards | 8/8 PASS |
| Финальная очистка, пакеты, minor, source bytes | 8/8 PASS |
| Offline publisher и локальная checksum | 20/20 + 14/14 PASS |

Новая `tools/prx-test-deb-existing.sh` на каждом из восьми стендов проверила:

- mode 6: отсутствие кластера/БД, фактический порт, registry/connection/SQL
  errors, `.sql-started`, запрет replay, повтор после ручной проверки и отсутствие
  разрушающих действий;
- mode 4/5 replace: порядок delete → install, отсутствие точной цели, сохранность
  одноимённой другой major, повтор, ошибка удаления и проверка payload до удаления;
- CLI/ENV-приоритет SQL основного сценария, strict/skip и ENV-only wizard mode 6.

Это изолированная регрессия с подменёнными внешними командами. Реальная установка
mode 6 и реальная замена кластера mode 4/5 не выполнялись и не объявляются PASS.

## Покрытие 61 обязательного ID

### Полностью выполнены на восьми WSL

`PT-BK-01`, `PT-BK-03`, `PT-BK-04`, `PT-BK-05`, `PT-BK-06`,
`PT-CC-01`, `PT-CC-02`, `PT-CC-04`, `PT-CC-05`, `PT-CC-07`,
`PT-CC-12`, `PT-CC-16`, `PT-CC-17`, `PT-CC-21`, `PT-CC-24`,
`PT-DEB-02`, `PT-DEB-03`, `PT-DEB-04`, `PT-DEB-06`, `PT-DEB-08`,
`PT-DEB-09`, `PT-DEB-10`, `PT-DEB-12`, `PT-DEB-13`, `PT-DEB-14`,
`PT-DEB-15`, `PT-DEB-16`, `PT-DEB-17`, `PT-E2E-01`, `PT-E2E-02`,
`PT-E2E-04`, `PT-E2E-05`, `PT-ENV-01`, `PT-ENV-02`, `PT-ENV-03`.

### Выполнены частично; оставшиеся варианты — «Не тестировалось»

| ID | Выполнено | Не тестировалось |
|---|---|---|
| PT-BK-02 | Реальный wrapper/config и пригодный hot-архив | Собственный sudo-переход wrapper/main |
| PT-CC-03 | Работа существующей `/.postgres` | Полностью отсутствующая начальная структура |
| PT-CC-06 | Интерактивные default/custom и неверный ввод | Полная матрица отмен каждого шага |
| PT-CC-08 | Live conflicts/ports и fixture major/name | Полный real cross-major/path/symlink набор |
| PT-CC-09 | Реальные смены порта | Все комбинации CLI/ENV × online/down |
| PT-CC-10 | Реальные default/custom перемещения | Все symlink/вложенные live-варианты |
| PT-CC-11 | Реальный выбор БД и hot | Полная матрица размеров/имён в PTY |
| PT-CC-13 | Реальные cold online/down | Отдельный подтверждённый reset WAL на одноразовой копии |
| PT-CC-14 | Fixture ошибок/lock | Все живые ошибки дочерних команд |
| PT-CC-15 | Реальные архивы и fixture путей | Вся живая матрица ссылок/битых архивов |
| PT-CC-18 | Реальные cold restore | Все комбинации имён/портов/root |
| PT-CC-19 | Fixture major/name и live occupied | Реальный cross-major и полный unit/save набор |
| PT-CC-20 | Реальное удаление БД с hot | Все ответы и защита каждой служебной БД |
| PT-CC-22 | Контракты и распределённые live CLI/ENV | Обе живые формы каждого действия и собственный sudo |
| PT-CC-23 | Live WSL и fixture timeout/syslog | Все инъекции зависания и применение raw syslog-конфига |
| PT-CC-25 | Live rename default/custom online/down | Реальный cross-major rename |
| PT-CC-26 | Menu SQL, CLI/ENV parser и mocked target | Полная live-матрица `--action sql`, ошибок и смены цели |
| PT-DEB-01 | Mode 5 wizard и фильтры mode 3/4 | Все возвраты мастера mode 1–6 |
| PT-DEB-05 | Dependency fixtures и pinned live server | Live auto-upgrade по альтернативному Depends |
| PT-DEB-07 | Mode 5 last.sh | Полный mode 1/4/fallback/очищенная ENV набор |
| PT-DEB-11 | Repeat/stale marker | Управляемые реальные прерывания mode 3/4 |
| PT-E2E-03 | Hot → mode 4 с точным package | Автовыбор более новой Postgres Pro major |
| PT-ENV-04 | Config fixtures и live propagation | Полная собственная sudo/last.sh цепочка |
| PT-ENV-05 | Defaults/config SHA и восстановление | Полная матрица отмен/ошибок/sudo/last.sh |
| PT-DEB-18 | Изолированные mode 6 postinst/guards | Установка mode 6 на реальную существующую БД |
| PT-DEB-19 | Изолированный replace mode 4/5 | Реальная замена одноразового кластера mode 4/5 |

## Очистка и замечания среды

- На 8/8 протестированных WSL реестр кластеров пуст, процессов postgres нет,
  `dpkg --audit` пуст; исходные server/common-пакеты и точные minor восстановлены.
- `claster-creator 2.5.7` installed/configured; три установленных сценария
  побайтно совпадают с проверенными исходниками.
- QA-data/config/unit, cron, locks, deployment markers, временные DEB/SQL/архивы
  и Linux-копии сборок удалены; системные конфиги восстановлены.
- Предупреждения WSL о systemd user session, локали Mint и активации Astra не
  препятствовали выполненным проверкам и сохранены в логах.
- Каталог доказательств:
  `D:/Ai/pg_claster_creator.backup/TEST-2.5.7/<WSL>/run-20260924-152642/`.
  Предыдущий неполный прогон сохранён отдельно и не входит в новую статистику.
