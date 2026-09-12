# Тестирование pg_claster_creator 2.4.2 — FAIL

Дата: 2026-09-12, MSK. Идентификатор: full-2.4.2-20260912-184213.
Основные операции и проверки: 18:42–19:03; последние независимые аудиты завершены в 19:03:27–19:03:37.

Итог полного плана: **19 PASS, 1 FAIL, 37 BLOCKED из 57 ID на каждой из семи доступных ячеек W1–W7**. Это не 57 успешных тестов. Дополнительные отсутствующие комбинации семейств/версий — BLOCKED. S10: удаление QA-объектов и возврат конфигов подтверждены; точное восстановление всех метаданных каталогов после ошибки тестовой обвязки не доказано.

Подтверждён один дефект продукта на всех семи WSL: ANSI-последовательности очистки экрана в перенаправленном выводе интерактивного меню (PT-CC-05). Журнал создан как TEST-2.4.2-journal.md и после сведения результатов переименован в TEST-2.4.2-journal-fail.md. Оснований для passed нет.

## Область проверки

Проверялись установленные create-claster.sh, create-claster-backup.sh, create-claster-deb.sh версии 2.4.2 по разделу «План полного тестирования» TEST.md. Структура журнала следует TEST-2.1.2-journal-passed.md; его старые результаты не перенесены в этот прогон.

Выполнены реальные создание/наполнение QA-кластера, горячие/холодные бэкапы и восстановления, роли/ACL/LOGIN, смена порта и перенос в /DATA, остановка/запуск, переименование, удаление, wrapper/cron/ротация, сборка и установка DEB 1–4, force и повторная установка. Не все варианты обязательных чек-листов закрыты — см. все 57 ID ниже.

Снимки не создавались. Массовая очистка общих /DATA, /BACKUP, /.postgres не выполнялась. Перед началом реестры всех семи WSL были пустыми. Использовались исключительно уникальные QA-имена, отдельные порты/корни/backup-dir. Старый архив 16-asvd-20260906-190608-dmp.tar.gz не использовался. Вместо внешней схемы применён контрольный набор, предусмотренный текущим планом, через tools/prx-prepare-postgres-test-data.sh.

Продуктовые сценарии, версия, DEB и документация в ходе этого задания не исправлялись. Commit/push не выполнялись.

## Исходники

Git HEAD: `033a8552c05eac01566df2ddb9080bc819d5f8c3`, тег `v2.4.2`.
На старте рабочее дерево было чистым. В конце изменены только тестовые helper’ы tools/prx-test-live-regression.sh, tools/prx-test-live-extra.sh, tools/prx-test-live-ui.sh, tools/prx-audit-live-regression.sh и добавлен этот журнал; вспомогательные файлы/логи tmp игнорируются Git.

| Файл | SHA-256 проверенных байтов |
|---|---|
| create-claster.sh | `8396b3d4eedffc9e7cc5960cd1d239ab83707bab2acbe3c29f08418be5bfb38c` |
| create-claster-backup.sh | `f9a787f07ffdaf586163704cdecf7db60efd629e1a66ea8183f1c408e85cc82e` |
| create-claster-deb.sh | `86ba85e397da2666a492c3bfa583e20b4991e2be78f07fc5881c03789214968b` |
| dist/claster-creator-2.4.2.deb | `ee3a5fe6a505bb88f8a6a660ab7adfc1b0b8fda8d4b0a7599c1a3c052e824b65` |
| .new-claster.config проекта | `ad11caf6fa1a42276a5f5ddc3fa5856847e43baebcd0194f1bc07314f812dc81` |
| TEST.md | `da9160556b051774072db98a0c3b65f3b00ffe31390fe2cf5b7c69780220c9af` |

До и после установленные три сценария побайтно совпадают с проектом. Scripts-only DEB имеет размер 167962 байта. Общий конфиг проекта не изменился. Во всех WSL использовался собственный приоритетный конфиг /usr/local/shared/pg_claster_creator/.new-claster.config. Проверки defaults выполнялись после операций, а не только после восстановления конфигов helper’ом.

## Матрица результатов

Имена WSL взяты из последнего запроса, включая переименованные alse-1.6 и alse-1.7; старые обозначения списка в TEST.md не использовались.

| Код | WSL | Astra build | Проверенный установленный сервер | Базовый QA-порт | Результаты |
|---|---|---|---|---|---|
| W1 | alse-1.6.14-mg12.4.0 | 1.6.14.1 | postgrespro-ent-16-server | 60110 | [результаты](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/live-extension-r2/results.tsv), [финальный аудит](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/final-audit-post-extension.log) |
| W2 | alse-1.7.9-uu1 | 1.7.9.46 | tantor-se-server-17 | 60210 | [результаты](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/live-extension-r2/results.tsv), [финальный аудит](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/final-audit-post-extension.log) |
| W3 | alse-1.8.2.uu1-mg15.7.0 | 1.8.2.8 | tantor-free-server-16 | 60310 | [результаты](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/live-extension-r2/results.tsv), [финальный аудит](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/final-audit-post-extension.log) |
| W4 | alse-1.8.3.uu1-mg15.8.4 | 1.8.3.8 | tantor-free-server-16 | 60410 | [результаты](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/live-extension-r2/results.tsv), [финальный аудит](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/final-audit-post-extension.log) |
| W5 | alse-1.8.4-mg16.3.0 | 1.8.4.48 | postgrespro-ent-13-server | 60510 | [результаты](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/live-extension-r2/results.tsv), [финальный аудит](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/final-audit-post-extension.log) |
| W6 | alse-1.8.5-mg16.3.0 | 1.8.5.46 | postgrespro-ent-17-server | 60610 | [результаты](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/live-extension-r2/results.tsv), [финальный аудит](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/final-audit-post-extension.log) |
| W7 | alse-1.8.6 | 1.8.6.39 | tantor-be-server-18 | 60710 | [результаты](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/live-extension-r2/results.tsv), [финальный аудит](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/final-audit-post-extension.log) |

В каждом WSL: SRC_CLUSTER/SRC_DB = qa242_PORT; дополнительные цели имеют суффиксы e/u/x/x2/cold/m2/m3/m4/ren. QA_ROOT = /DATA/pgcc242-PORT с суффиксом фазы; фактическая структура pg_VERSION/NAME. В прямом rename/delete прогоне отдельные порты 61110–61710 и имена qadel_PORT_online/down. Порт обычного жизненного цикла менялся PORT → PORT+50 → PORT; дополнительные цели использовали отдельные свободные порты.

В рамках каждой доступной ячейки финальные статусы одинаковы: 19 PASS / 1 FAIL / 37 BLOCKED. Это не утверждение о других серверах, одновременно установленных на том же WSL. Живой vanilla PostgreSQL и вся обязательная матрица Postgres Pro 16–18 не покрыты.

## Критерии подтверждения

- PASS означает полный подтверждённый чек-лист конкретного ID в оговорённой ячейке, а не только rc helper’а.
- FAIL — наблюдаемое расхождение с ожиданием.
- BLOCKED — отсутствует необходимый стенд/вариант либо обязательная часть проверки не выполнена. Частичный успешный результат перечислен, но не превращён в PASS.
- Для ожидаемого отказа ненулевой rc считается успешной проверкой только при сохранности состояния. Внешний timeout не засчитывается как корректный отказ продукта.
- Дамп сравнивался целиком через pg_dump --no-comments, с удалением только строк restrict/unrestrict. Сверялись также роли/атрибуты, schema/data, ACL/владельцы, sequence, расширение и вход восстановленной LOGIN-роли. Эталон не менялся при rename/port/move.
- Контрольный набор включает таблицы/данные, наследование и inherited constraint, sequence, view/materialized view, функцию/триггер/FK, разные роли/владельца и доступное расширение.
- Полный fingerprint относится к контрольной БД; сравнение каждой служебной БД cold-кластера не заявляется.

| WSL | Эталон SHA-256 полного логического дампа | Доказательство |
|---|---|---|
| W1 | `8d8da53497e2aab79d70e919ac0db4cc71c5b2e48772b080a65f35f9a26b6d10` | [SOURCE-FULL](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/live/SOURCE-FULL.log) |
| W2 | `0b395ab216e4240a044c3a1c6a4bd2530e7f666025369d70ee826de606263068` | [SOURCE-FULL](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/live/SOURCE-FULL.log) |
| W3 | `02057c2ebd4169e8767c60178e3a75309e36723246ab9a4ca0927f7d2c3e2d41` | [SOURCE-FULL](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/live/SOURCE-FULL.log) |
| W4 | `e3c25c0bf9d883c8a114247fa69710dd7c90785d50a41da8e7e330936fd20e4e` | [SOURCE-FULL](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/live/SOURCE-FULL.log) |
| W5 | `1b783219ccd3eaf8c03b6ec886aa234782fd69ac24f60bffae9cae855ebc7acc` | [SOURCE-FULL](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/live/SOURCE-FULL.log) |
| W6 | `a4c9e5d39d51fef0f805b157a54c0c01b656d7ce56e5695ed0efd76830e295c8` | [SOURCE-FULL](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/live/SOURCE-FULL.log) |
| W7 | `3c607806c416079d0165351da3e27efacce300ee8d477df3c6992b4d7c90d232` | [SOURCE-FULL](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/live/SOURCE-FULL.log) |

Совпадения после hot/overwrite/cold/DEB3/DEB4/force/rename/cron отмечены шагами *-FULL. Отдельно проверены исчезновение stale-объекта, сохранность соседней БД при DB-force, SQL и LOGIN после восстановления ролей в другой кластер.

## Подтверждённый дефект продукта

### F1 — ANSI в перенаправленном интерактивном выводе (PT-CC-05)

Ожидание: если stdout — файл/pipe, в info нет ANSI; down-кластер сам не запускается.

Факт на W1–W7: команда меню завершилась rc=0, down сохранился, но вывод содержит байты ESC[H, ESC[2J, ESC[3J. Проверка INFO-DOWN-NO-ANSI дала rc=1 на всех семи.

Пример воспроизведения на существующем одноразовом down QA-кластере:

```bash
# INDEX — номер QA-кластера в pg_lsclusters; не выбирать чужой кластер.
printf '1\n%s\n\n0\n' "$INDEX" |
  env PGCC_BACKUP_DIR="$QA_BACKUP" /usr/local/bin/create-claster.sh >info.log 2>&1
LC_ALL=C grep -n $'\x1b' info.log
```

Сохранённое фактическое имя для W7: 18/qa242_60710x2, порт 60710. После проверки оно удалено; воспроизведение требует заново подготовленной QA-цели.

Доказательства W7: [вывод меню](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/live-extension-r2/INFO-DOWN-MENU.log), [rc/флаги](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/live-extension-r2/results.tsv), [команда/время](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/live-extension-r2/run.log). Аналогичные файлы есть у W1–W6.

Причина по исходнику: header() вызывает clear при интерактивном режиме, не проверяя stdout TTY; есть прямые clear в info/menu. Проверка -t уже защищает цвет строки кластера, но не очистку экрана. Рекомендуемое исправление: единая функция очистки с проверкой -t 1 (и пригодного TERM), использовать её вместо всех прямых clear. Затем повторить redirected info/menu и реальный PTY. В этом прогоне исправление не применялось.

После этого FAIL завершающие шаги FINAL-START/FINAL-FULL/INPUTS-UNCHANGED модуля R2 не выполнялись; cleanup отработал. Ранее выполненные независимые проверки сохранены.

## Ошибки тестовой обвязки и WSL — отдельно от F1

### H1 — локальная переменная trap в contracts

Первая серия contracts: 43 PASS + 1 FAIL на WSL. При source сценария внутри функции переменная CLEANUP_DIR была локальной, а EXIT trap выполнялся после выхода из функции. Ошибка возникла в fixture MAIN-PRECEDENCE, не в обычном запуске продукта.

Fixture исправлен отключением его EXIT trap после source; повтор contracts-r2: 44/44 PASS на каждом WSL. Первые results/log не перезаписаны. Успешный helper сохранён в tmp/save/test-full-contracts.sh.

### H2 — ошибочная перепаковка legacy cold-архива и изменение прав каталогов

Первая live-extension: 16 PASS + 1 FAIL на WSL, включая cleanup. При удалении unit из извлечённого дерева helper повторно упаковал весь root/. Так в архив попали дополнительные родительские directory entries с root:root 0755. При реальном restore они изменили метаданные общих каталогов; запуск восстановленного QA-кластера отказал: «Could not create log file /var/log/postgresql/postgresql-V-NAME.log».

Это ошибка подготовки тестового архива, не подтверждение поломки restore штатного cold-бэкапа. Диагностика original-members/legacy-members/added-members и stat сохранена в metadata-diagnostic каждого WSL. Некорректные архивы сохранены отдельно для анализа и **не должны использоваться для восстановления**.

Исправление fixture: распакован только gzip-поток в tar; через tar --delete удалены существующие *.service entries, остальные члены/метаданные не перепаковывались. Список членов нового архива сравнен с исходным минус unit. Для Astra 1.6 учитывается /lib/systemd/system.

В ходе устранения собственных последствий теста выполнены только нерекурсивные изменения по явным defaults установленного postgresql-common.postinst:

```text
/etc/postgresql       owner postgres:postgres
/var/lib/postgresql   owner postgres:postgres
/var/log/postgresql   owner root:postgres, mode 1775
```

Логи до/после и проверка записи postgres: metadata-diagnostic/repair.log. Другие добавленные родительские entries перечислены в added-members.txt; текущие /etc, /var, /usr либо /lib и промежуточные каталоги имеют root:root 0755. Их точные исходные метаданные до ошибочного fixture не снимались. Поэтому **полное побайтное/метаданные-в-метаданные восстановление исходного состояния всех общих родителей не доказано**; S10 нельзя объявить безусловным PASS. Содержимое общих каталогов массово не удалялось.

Повтор live-extension-r2: COLD-WITHOUT-UNIT, LEGACY-FULL, LEGACY-UNIT, PARENTS-UNCHANGED и DELETE-WITH-COLD PASS на W1–W7. Сравнение parents-before/after подтверждает отсутствие нового изменения родителей на этом повторе. Повтор завершился уже отдельным F1 (ANSI), а не ошибкой cold restore.

### I1 — инфраструктурные сообщения WSL

При первом запуске extra на W5 (alse-1.8.4-mg16.3.0) WSL вернул Wsl/Service/0x80370107: виртуальная машина/контейнер принудительно завершены. Перед повтором подтверждено, что helper не начал фазу, её каталогов/логов ещё нет и реестр пуст; повтор extra завершился rc=0.

Позднее часть запусков WSL печатала предупреждение о невозможности старта systemd user session root. Это не считалось подтверждением ошибки PostgreSQL; системные операции/очистка проверены отдельно. На Astra 1.6 /usr/lib/systemd/system отсутствует, штатный путь /lib/systemd/system; отдельный read-only find поэтому дал rc=1 без найденных QA-остатков.

## Сводка выполненных фаз

Числа ниже — строки results.tsv, включая проверки отказов и cleanup, **не число закрытых ID полного плана**. Все семь WSL имеют одинаковые количества.

| Фаза | На одном WSL | На семи | Итог |
|---|---:|---:|---|
| preflight (P) | 56 PASS | 392 PASS | OK |
| live core (L) | 52 PASS | 364 PASS | OK |
| live extra (X) | 76 PASS | 532 PASS | OK |
| live ui (U) | 40 PASS | 280 PASS | OK |
| live ports (V) | 15 PASS | 105 PASS | OK |
| backup guards (G) | 19 PASS | 133 PASS | OK |
| contracts-r2 (C) | 44 PASS | 308 PASS | OK |
| live-extension-r2 (R2) | 23 PASS + 1 FAIL | 161 PASS + 7 FAIL | F1 |
| Итого перечисленных окончательных серий | 325 PASS + 1 FAIL | 2275 PASS + 7 FAIL | Не полный PASS |

Дополнительно: release fixtures, package/journal/gzip и финальные аудиты завершились rc=0 на 7/7 WSL. Прямой live regression: 28 переименований и 14 удалений (online/down, standard/custom), успешно.

Ранние неуспешные серии не включены в итог окончательных серий: contracts — 301 PASS/7 FAIL; live-extension — 112 PASS/7 FAIL. Их логи сохранены, причины H1/H2 указаны выше. Повтор не стирает факт сбоя тестовой обвязки.

## Все 57 контрольных точек

Колонка «W1–W7» задаёт один и тот же статус **для каждой** из семи строк матрицы, а не агрегированный PASS по большинству. Полные ожидаемые чек-листы находятся в неизменённом TEST.md; здесь приведено проверяемое ожидание и фактическое покрытие. BLOCKED при частичном успехе означает, что хотя бы один обязательный вариант остался незакрытым. SKIPPED не присваивался.

Обозначения доказательств: P=preflight, F=fixtures, L=live, X=live-extra, U=live-ui, V=live-ports, R2=live-extension-r2, C=contracts-r2, G=guards, J=package-journal, D=direct, A=final-audit-post-extension.log. Ссылки для каждой ячейки приведены сразу после таблицы.

| ID и полное имя | W1–W7 | Ожидаемый результат | Фактический результат / доказательства / незакрытое |
|---|---|---|---|
| PT-ENV-01 — Паспорт стенда и исходников | PASS | Полный паспорт и baseline; достаточно места | P: паспорт, пустой исходный реестр; SHA/HEAD ниже. |
| PT-ENV-02 — Репозитории и семейства серверов | BLOCKED | Полная матрица семейств/major и кандидатов | P: policy/available/packages сохранены. Нет живого vanilla PostgreSQL и всех обязательных Postgres Pro 16–18; состав W1–W7 ниже. |
| PT-ENV-03 — Синтаксис, версия, справка и man | PASS | Синтаксис, все формы help/version, unknown, шесть man | P/F: корректные rc=0, unknown rc=1; установленные байты совпали. |
| PT-ENV-04 — Права root и поиск конфигурации | PASS | Root guard, приоритет/fallback/ссылки конфигов | F/config-priority и X/NONROOT-ADMIN; приоритет, cwd, битая ссылка, fallback проверены fixture; реальные конфиги изолированы. |
| PT-ENV-05 — Сохранность `.new-claster.config` | PASS | Не менять защищённые defaults внутри операций | L/X/U/R2: покомандные SHA/значения defaults без расхождений; A: оба системных и общий конфиги равны baseline. |
| PT-CC-03 — Служебная структура `/.postgres` | BLOCKED | Создание отсутствующей структуры и безопасный повтор | Повторное использование /.postgres и backup-ссылок проверено L/U. Отсутствующий общий /.postgres не моделировался; существующий не удалялся. |
| PT-CC-02 — Выбор и установка серверного комплекта | BLOCKED | Выбор/приоритет и реальная установка комплекта | F/tantor: выбор, неверный/0/EOF, SE > BE > Free проверены. Установку отсутствующих server+contrib и штатную службу в чистом окружении не проверяли. |
| PT-CC-04 — Главное меню и навигация | PASS | Главное/Изменить, возврат, invalid/EOF, один пакет | F/edit-menu и tantor wizard — маршрутизация с подменой действий; U/X/R2 — реальные переходы. ANSI-дефект учитывается отдельно CC-05. |
| PT-CC-05 — Информация о кластерах и БД | FAIL | Online/down info; down не запускается; вывод без ANSI | L/INFO и U/ENV-INFO успешны. R2/INFO-DOWN-STATE PASS, INFO-DOWN-NO-ANSI FAIL rc=1: реальные ESC[H/2J/3J в файле на W1–W7. |
| PT-CC-22 — CLI, ENV и позиционные аргументы | BLOCKED | Обе формы каждого действия; CLI > ENV > config; invalid | C/MAIN-PRECEDENCE — fixture; L/X/U/R2 — реальные CLI/ENV и позиционные backup/delete. Полная таблица всех ключей и обе формы каждого действия не закрыта. |
| PT-CC-06 — Интерактивная установка кластера | BLOCKED | Две реальные интерактивные установки default/custom, invalid/cancel | L/CREATE — CLI default, R2/ENV-INSTALL — ENV custom. Они не заменяют два интерактивных install. |
| PT-CC-07 — Роли, настройки и расширения нового кластера | BLOCKED | Весь набор настроек/ролей/расширений нового сервера | L/DATA,SOURCE-FULL: объекты, ACL, роли и LOGIN проверены. Нет полного отдельного протокола проверок encryption/preload/HBA/search_path/lc_messages для всех major. |
| PT-CC-08 — Конфликты имени, каталога и порта при установке | BLOCKED | Все конфликты install, interactive/non-interactive порт | X/DUPLICATE-INSTALL и V/занятый listener PASS; не закрыты другой major, непустой data-dir и повторный запрос порта именно interactive install. |
| PT-CC-09 — Переключение порта | BLOCKED | Online/down, current/invalid/busy/free, все конфиги порта | L/PORT-DATA и U/ENV-PORT-DOWN PASS. Не закрыты все конфликты и перекрытия conf.d/auto.conf. |
| PT-CC-10 — Перемещение данных | BLOCKED | Online/down, туда/обратно, пустая/занятая/symlink/вложенная цель | L/PORT-DATA и U/ENV-MOVE-DOWN PASS, данные целы. Полная таблица опасных целей и возврат в default не выполнены. |
| PT-CC-24 — Остановить/Запустить по текущему состоянию | PASS | Выбор по состоянию/имени/номеру, y/N, гонки и отказы | F/power — выбор/отказ/гонка с подменой служб; X/POWER-* — реальные cancel/stop/start и состояние/SQL. |
| PT-CC-25 — Переименование кластера | BLOCKED | Полная матрица rename, пути, автозапуск и safe failures | F/rename + U/RENAME-* + D: prefix/reverse, online/down, standard/fixed custom, SQL и enabled/disabled PASS. Не засчитываем непроверенные отдельно runtime Requires и все коллизии имени другой major. |
| PT-CC-11 — Интерактивный выбор горячего бэкапа | BLOCKED | Горячее меню: номер и точное имя БД, формат размеров | Горячий backup через CLI/wrapper и hot-before-delete выполнен. Оба способа выбора именно в backup-меню с таблицей длин/размеров не проверены. |
| PT-CC-12 — Горячий бэкап существующей БД | BLOCKED | Hot, метаданные и фактическая major при несовпадении | L/HOT, U/ENV-HOT-DIRLINK, F/tantor PASS. Несовпадение 16/18 проверено fixture, а не живым кластером; полный чек-лист всех полей архива отдельно не закрыт. |
| PT-CC-15 — Фильтрация и путь к архиву | BLOCKED | Обе маски/все формы путей, фильтр, исправные/битые ссылки | X/SYMLINK-HOT и R2/HOT-SHORT-NAME,BROKEN-LINK,CORRUPT-ARCHIVE PASS. Относительный путь к архиву при реальном restore и вся таблица меню не закрыты. |
| PT-CC-16 — Горячий рестори в новую БД | PASS | Hot в другую БД другого кластера с отсутствующими ролями | R2/ROLES-ABSENT,HOT-SHORT-NAME,HOT-CROSS-FULL: роли созданы, полный dump/role fingerprint и LOGIN совпали. |
| PT-CC-17 — Горячий рестори поверх существующей БД | BLOCKED | Отказ/overwrite/stale/ACL/inheritance и три защищённые БД | L/HOT-REFUSE*,HOT-OVERWRITE* и R2/PROTECTED-RESTORE PASS; postgres сохранён. template0/template1 отдельно не проверялись. |
| PT-E2E-01 — Существующий кластер → горячий архив → новая БД | PASS | SRC → hot → другой кластер/БД, полный эталон | L/HOT + X/полное сравнение + R2/HOT-CROSS-FULL; те же архивы и исходный эталон, доступ восстановленной LOGIN-роли. |
| PT-CC-13 — Холодный бэкап кластера | BLOCKED | Cold online/down и отдельный подтверждённый reset WAL | L/COLD и X/DOWN-COLD PASS, исходное состояние сохранено. Разрушающий вариант reset WAL отдельной копии не выполнялся. |
| PT-CC-18 — Холодный рестори | BLOCKED | Cold варианты путей/имён/unit и сверка всех БД | L/COLD-FULL и R2/COLD-WITHOUT-UNIT,LEGACY-FULL,PARENTS-UNCHANGED PASS. Полный fingerprint есть для контрольной БД, не для каждой служебной БД; все варианты родительской ссылки не закрыты. |
| PT-CC-19 — Конфликты холодного рестори | BLOCKED | Все коллизии restore и разрешённые save/битые unit-ссылки | L/COLD-CONFLICT и F/tantor PASS. Полная живая таблица active unit/config/data/порта/другой major не выполнена. |
| PT-E2E-02 — Существующий кластер → холодный архив → удаление → рестори | BLOCKED | Cold → delete → restore, все БД/config/служба | U/COLD-AFTER-DELETE* PASS, контрольный dump совпал. Не закрыта полная сверка всех БД/общих логов для каждого варианта. |
| PT-CC-14 — Отказ бэкапа | BLOCKED | Набор отказов backup: права/ENOSPC/dump/stop/start/архив | X/BACKUP-UNWRITABLE и R2/CORRUPT-ARCHIVE PASS. Инъекции ENOSPC/pg_dump/stop/start основного backup не выполнены. |
| PT-CC-20 — Удаление БД | BLOCKED | Все варианты удаления БД и защита трёх служебных БД | U/DB-DELETE-CANCEL,DB-DELETE-HOT,DB-ABSENT,NEIGHBOR-DB-PRESERVED PASS. Не закрыты отказ от backup и postgres/template0/template1 именно в delete. |
| PT-CC-21 — Удаление кластера | BLOCKED | Полный direct-delete checklist и отсутствие ложного успеха | D: online/down standard/custom; R2/DELETE-WITH-COLD PASS; F/delete: stop/status/active/mount/shared/WAL/log guards PASS. Нет отдельного подтверждения всех вариантов отмены/внешних tablespaces/ошибки daemon-reload. |
| PT-CC-23 — WSL, PARSEC и тайм-ауты | BLOCKED | Реальные состояния и ограниченные служебные ожидания | L/X/U/D/R2: операции завершались; F: bounded rename/delete fault guards. Тайм-аут внешнего runner не доказывает bounded restore в продукте; все зависания не инъецированы. |
| PT-BK-01 — Аргументы и валидация | BLOCKED | Полная таблица wrapper, перестановки/пропуски/лимиты | G и C/BK-SIZES: некорректные/оба лимита, B–TiB/overflow PASS. Полная таблица перестановок и каждого пропущенного аргумента не закрыта. |
| PT-BK-02 — Одиночный плановый горячий бэкап | BLOCKED | Реальный wrapper hot в default и custom | L/ROTATION-* и U/cron: wrapper → main успешно, custom архив реально восстановлен. Wrapper с непереопределённым default backup-dir отдельно не запускался. |
| PT-BK-03 — Ротация по количеству | PASS | Ротация count, новые свои архивы, чужие сохранены | L/ROTATION-COUNT и X/COUNT-*,SENTINEL,OTHER-FILE PASS; отдельный backup-dir на задачу. |
| PT-BK-04 — Ротация по размеру | PASS | Ротация size, минимум один, чужие сохранены | L/ROTATION-SIZE,ROTATION-MINIMUM и X/SIZE-* PASS. |
| PT-BK-05 — Ошибка бэкапа и блокировка | PASS | Ошибка не ротирует; реальное внешнее владение flock | G: подменён worker с ошибкой, архивы не удалены; второй процесс реально держит flock, конкурирующий worker не запущен. |
| PT-BK-06 — Создание cron-задачи | PASS | Все cron-расписания через PTY и запуск сохранённой команды | G: PTY/5 расписаний/лимиты/повтор, worker подменён; U/CRON-CREATE,CRON-EXECUTE-* — именно сохранённая команда с настоящим main/PostgreSQL. |
| PT-E2E-05 — Плановый бэкап и ротация | PASS | Cron → ротация → restore последнего архива → эталон | U/CRON-ROTATION,ENV-RESTORE,CRON-RESTORE-FULL,CRON-LOGIN PASS. |
| PT-DEB-01 — Интерактивный выбор режимов | BLOCKED | Реальный wizard mode1–4, возврат/EOF и список архивов | F/tantor — wizard fixture; C/DEB-DISPLAY-SIZES — sparse files. Реальная интерактивная сборка всех четырёх режимов не выполнена. |
| PT-DEB-02 — Неинтерактивная валидация | BLOCKED | Полные наборы ключей/каждый пропуск/тип/major/пути | C/DEB-* — validate fixture; L/X — реальные сборки 2–4 PASS. Полная таблица ошибок архива/major через реальный builder не закрыта. |
| PT-DEB-03 — Режим 1 и содержимое пакета | PASS | Mode1 payload, версии/права/ссылки/man/journal/gzip | J/check.log: journal byte-for-byte root:root 0644, все режимы отказали без него; L/X restore-mode1 и A: установлен 2.4.2, включая старый dpkg W1/W2. |
| PT-DEB-04 — Имена пакетов и скелет | BLOCKED | Все имена/output/force и lifecycle tmp/rootFs | F/tmp-cleanup — 7 вариантов PASS; L/X/J — реальные артефакты. Полная матрица overwrite/--force для одних и тех же выходных пакетов не зафиксирована. |
| PT-DEB-05 — Зависимости PostgreSQL Pro | BLOCKED | Postgres Pro alternatives/minimum и реальное разрешение APT | C/DEB-DEPS проверяет строки зависимости 14/16/17/18 и cold exact. Нет live upgrade 16→новейшая допустимая на отдельном чистом стенде. |
| PT-DEB-06 — Дополнительные зависимости | PASS | Дополнительные Depends: нормализация, дубли, запреты | C/DEB-DEPS,DEB-DEP-BAD-*,DEB-DEP-MODE1 PASS; fixture реальных parser/dependency функций, без APT. |
| PT-DEB-07 — `create-claster-deb-last.sh` | BLOCKED | last.sh mode1/4, writable/fallback, права, повтор | Не выполнялось; ни CLI-build, ни tmp-cleanup fixture не заменяют этот интерактивный сценарий. |
| PT-CC-01 — Установка обязательного пакета | BLOCKED | Первоначальная установка отсутствующего common | На W1–W7 common уже установлен; отдельного одноразового стенда без зависимости нет. Пакеты не удалялись ради проверки. |
| PT-DEB-08 — Установка mode 2 | PASS | Mode2 на чистой QA-цели и с занятым портом | L/DEB-INSTALL-2,DEB-ONLINE-2 и V: apt/postinst, реальный listener, свободный порт; установленное семейство из матрицы, Depends уже удовлетворены. |
| PT-DEB-09 — Установка mode 3 | BLOCKED | Cold mode3, все БД, защищённый план и идемпотентность | L/DEB-COLD-FULL,DEB-REINSTALL-3 и X/REINSTALL-PRESERVED-3 PASS. Полная сверка всех служебных БД и каждого условия прав плана отдельно не закрыта. |
| PT-DEB-10 — Установка mode 4 | PASS | Hot mode4 на чистой QA-цели/занятом порту и полный restore | L/DEB-HOT-FULL, V/DEB4 busy-port; фактические установленные серверы W1–W7, роли/ACL/LOGIN и dump совпали. Не зачёт чистого пакетного окружения. |
| PT-DEB-11 — Идемпотентность и маркеры | BLOCKED | Повтор/stale markers и прерывание после cluster-created | L/DEB-REINSTALL-* и V/stale .done PASS. Прерывание mode3/4 после .cluster-created не инъецировалось. |
| PT-DEB-12 — Существующий кластер без force | PASS | Mode2–4 без force сохраняют контрольное изменение | X/MUTATE-*,REINSTALL-*,REINSTALL-PRESERVED-* PASS на всех режимах; dpkg audit после возврата mode1 чист. |
| PT-DEB-13 — `CLASTER_FORCE_INSTALL` | PASS | Force cluster повторяет весь план mode2–4 | X/FORCE-CLUSTER-*,FORCE-RESET-*,FORCE-FULL-3/4 PASS; реальный postinst → main/delete, не только unit fixture. |
| PT-DEB-14 — `CLASTER_FORCE_DB_INSTALL` | BLOCKED | DB-only force, сосед/identifier и запрещённые флаги | X/FORCE-DB-* и BOTH-FORCE-REJECT PASS: stale исчез, сосед/кластер сохранены. Одиночный DB-force для mode3 отдельно не проверен. |
| PT-DEB-15 — Создание data-root при установке | BLOCKED | Root отсутствует отдельно перед mode2 и mode4 | Mode2 создал QA_ROOT. Перед mode4 тот же root уже существовал; этот запуск не закрывает его отсутствующий root. |
| PT-DEB-16 — Установка зависимостей через APT | BLOCKED | APT отсутствующих Depends и dpkg → apt -f | Реальные apt install выполнены с уже удовлетворёнными серверными Depends; чистого пакетного стенда нет. |
| PT-E2E-03 — Горячий архив → DEB mode 4 → чистая система | BLOCKED | Hot → mode4 → чистая система, новая PP major через APT | Нет одноразового чистого окружения и реального выбора более новой Postgres Pro; обычный mode4 не подменяет этот тест. |
| PT-E2E-04 — Холодный архив → DEB mode 3 → чистая система | BLOCKED | Cold → mode3 → чистая цель, все БД и маркеры | L/X mode3 успешно; общий зачёт блокируют неполные DEB-09/11 (все БД и interrupted markers). |

## Команды, ввод, время и ссылки на доказательства

Корень Windows: `D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213`.
Тот же каталог из WSL: `/mnt/d/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213`.

Для P/L/X/U/V/R2 результат каждого шага хранится в results.tsv; stdout/stderr — ID.log. Для live-фаз состояние после шагов записано в ID-clusters.log, ID-services.log, ID-files.log, ID-config-sha.log; для P паспорт/конфиги/реестр находятся в отдельных одноимённых логах. run.log (для P — preflight.log) содержит START/END, дату/время, shell-quoted команду/ввод и фактический rc. Внутренний SQL и команды функций определены в названных helper’ах. Для fixture и J/D общая команда/сценарий и начало/конец находятся в check.log/live.log; это не живые APT/БД, если явно указана подмена. Защищённые значения в публикуемых логах маскируются.

| WSL | Паспорт | Fixtures | Основные live-фазы | Дополнение | Contracts / guards / пакет / direct |
|---|---|---|---|---|---|
| W1 | [P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/preflight/preflight.log) / [результаты P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/preflight/results.tsv) | [F](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/fixtures/check.log) | [L](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/live/run.log) / [X](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/live-extra/run.log) / [U](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/live-ui/run.log) / [V](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/live-ports/run.log) | [R2](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/live-extension-r2/run.log) | [C](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/contracts-r2/results.tsv) / [G](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/guards/results.tsv) / [J](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.6.14-mg12.4.0/package-journal/check.log) / [D](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/direct/alse-1.6.14-mg12.4.0/live.log) |
| W2 | [P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/preflight/preflight.log) / [результаты P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/preflight/results.tsv) | [F](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/fixtures/check.log) | [L](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/live/run.log) / [X](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/live-extra/run.log) / [U](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/live-ui/run.log) / [V](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/live-ports/run.log) | [R2](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/live-extension-r2/run.log) | [C](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/contracts-r2/results.tsv) / [G](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/guards/results.tsv) / [J](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.7.9-uu1/package-journal/check.log) / [D](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/direct/alse-1.7.9-uu1/live.log) |
| W3 | [P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/preflight/preflight.log) / [результаты P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/preflight/results.tsv) | [F](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/fixtures/check.log) | [L](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/live/run.log) / [X](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/live-extra/run.log) / [U](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/live-ui/run.log) / [V](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/live-ports/run.log) | [R2](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/live-extension-r2/run.log) | [C](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/contracts-r2/results.tsv) / [G](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/guards/results.tsv) / [J](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.2.uu1-mg15.7.0/package-journal/check.log) / [D](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/direct/alse-1.8.2.uu1-mg15.7.0/live.log) |
| W4 | [P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/preflight/preflight.log) / [результаты P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/preflight/results.tsv) | [F](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/fixtures/check.log) | [L](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/live/run.log) / [X](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/live-extra/run.log) / [U](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/live-ui/run.log) / [V](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/live-ports/run.log) | [R2](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/live-extension-r2/run.log) | [C](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/contracts-r2/results.tsv) / [G](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/guards/results.tsv) / [J](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.3.uu1-mg15.8.4/package-journal/check.log) / [D](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/direct/alse-1.8.3.uu1-mg15.8.4/live.log) |
| W5 | [P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/preflight/preflight.log) / [результаты P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/preflight/results.tsv) | [F](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/fixtures/check.log) | [L](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/live/run.log) / [X](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/live-extra/run.log) / [U](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/live-ui/run.log) / [V](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/live-ports/run.log) | [R2](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/live-extension-r2/run.log) | [C](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/contracts-r2/results.tsv) / [G](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/guards/results.tsv) / [J](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.4-mg16.3.0/package-journal/check.log) / [D](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/direct/alse-1.8.4-mg16.3.0/live.log) |
| W6 | [P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/preflight/preflight.log) / [результаты P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/preflight/results.tsv) | [F](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/fixtures/check.log) | [L](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/live/run.log) / [X](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/live-extra/run.log) / [U](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/live-ui/run.log) / [V](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/live-ports/run.log) | [R2](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/live-extension-r2/run.log) | [C](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/contracts-r2/results.tsv) / [G](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/guards/results.tsv) / [J](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.5-mg16.3.0/package-journal/check.log) / [D](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/direct/alse-1.8.5-mg16.3.0/live.log) |
| W7 | [P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/preflight/preflight.log) / [результаты P](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/preflight/results.tsv) | [F](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/fixtures/check.log) | [L](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/live/run.log) / [X](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/live-extra/run.log) / [U](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/live-ui/run.log) / [V](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/live-ports/run.log) | [R2](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/live-extension-r2/run.log) | [C](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/contracts-r2/results.tsv) / [G](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/guards/results.tsv) / [J](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/alse-1.8.6/package-journal/check.log) / [D](D:/Ai/pg_claster_creator/tmp/full-2.4.2-20260912-184213/direct/alse-1.8.6/live.log) |

Основные воспроизводимые вызовы (ROOT — корень evidence, значения WSL/V/PACKAGE/FAMILY/PORT — из матрицы):

```bash
REPO=/mnt/d/Ai/pg_claster_creator
ROOT="$REPO/tmp/full-2.4.2-20260912-184213"
bash "$REPO/tools/prx-test-wsl-preflight.sh" "$REPO" "$ROOT/$WSL/preflight" 2.4.2
bash "$REPO/tools/prx-test-release-fixtures.sh" "$REPO" "$WSL" 2.4.2 "$ROOT"
bash "$REPO/tools/prx-test-live-regression.sh" "$REPO" "$WSL" "$V" "$PACKAGE" "$FAMILY" "$PORT" 2.4.2 "$ROOT" core
# Затем те же аргументы с phase extra, ui, ports.
bash "$REPO/tools/prx-test-backup-guards.sh" "$REPO" "$WSL" "$ROOT" "r242_$PORT"
bash "$REPO/tools/prx-test-package-journal.sh" "$REPO" 2.4.2 2.1.2 "$ROOT/$WSL/package-journal"
# Contracts в момент запуска находился в tmp; после успешного использования сохранён в tmp/save.
bash "$REPO/tmp/save/test-full-contracts.sh" "$REPO" "$ROOT/$WSL/contracts-r2"
PGCC_TEST_RENAME=yes PGCC_DELETE_LOG_ROOT="$ROOT/direct" bash "$REPO/tools/prx-test-cluster-delete-live.sh" "$REPO" "$WSL" "$V" "$((PORT+1000))" "/DATA/pgcc-delete-$((PORT+1000))"
PGCC_LIVE_EXTENSION="$REPO/tmp/test-full-live-edges.sh" bash "$REPO/tools/prx-test-live-regression.sh" "$REPO" "$WSL" "$V" "$PACKAGE" "$FAMILY" "$PORT" 2.4.2 "$ROOT" extension-r2
bash "$REPO/tools/prx-audit-live-regression.sh" "$REPO" "$WSL" "$PORT" 2.4.2 "$ROOT" post-extension
```

Это запись выполненного запуска, не команда для повторного запуска поверх существующих evidence/work. Helper’ы отказываются перезаписывать существующие фазовые каталоги. Для нового прогона нужны новые принадлежащие ему пути/имена/порты и baseline.

В tools добавлены полные fingerprint-проверки существующих live-фаз и подключение ограниченного тестового модуля; audit получил необязательную метку повторной проверки. Логика продукта не подменялась в live фазах. Новая обвязка H2 находится в tmp, исправленный повтор не скрывает её первую ошибку.

## Оставленное состояние и S10

На W1–W7 независимый final-audit-post-extension.log завершился rc=0:

- Реестры кластеров совпадают с исходными пустыми реестрами.
- Собственные QA data/config/unit/служебные ссылки и cron удалены; в относящихся к прогону областях дополнительных QA-остатков не найдено. Обычные данные QA-кластеров удалены; контрольные архивы оставлены для повторного восстановления.
- Конфиги /usr/local/shared и /usr/local/share побайтно возвращены к baseline; конфиг проекта неизменен. Конкурирующие изменения конфигов не обнаружены.
- На каждом WSL установлен scripts-only claster-creator 2.4.2, три .sh равны проверенным исходникам, dpkg --audit пуст.
- В финальном списке процессов нет postgres/pg_dropcluster/syslog-ng-ctl. Сообщения WSL root user-session и ps о размере терминала отмечены отдельно и не приняты за QA-процессы.
- Общие /.postgres и backup-ссылка оставлены. Массового удаления общих родителей не было.
- Права трёх каталогов PostgreSQL возвращены к defaults пакета после H2; точное исходное состояние всех затронутых метаданных не доказано. Это явное ограничение S10, несмотря на успешный функциональный аудит.

Намеренно оставлены для диагностики/повтора:

| Расположение в каждом WSL | Содержимое / доступ |
|---|---|
| /var/tmp/pgcc242-PORT и суффиксы -extra/-ui/-ports/-extension/-extension-r2 | Контрольные hot/cold, построенные DEB, SQL-эталоны и копии конфигов; корни root:root 0700, SHA артефактов в финальном аудите |
| /var/tmp/pgcc242-PORT/retained-markers | Собственные deployment-маркеры перенесены из /var/lib/claster-creator; root:root 0700, восстановимы |
| /var/tmp/pgcc-rename.* | Recovery manifest/конфиги переименования; не подменяют резервную копию data |
| tmp/full-2.4.2-20260912-184213 проекта | Маскированные логи/результаты/диагностика/пакетные fixture-артефакты; каталог игнорируется Git |
| /var/tmp/pgcc242-PORT-extension/legacy | **Некорректный архив H2. Только диагностика, не восстанавливать** |

Новый успешный passed-журнал и новый дистрибутив не создавались. Исторический TEST-2.1.2-journal-passed.md, уже находящийся в пакете, не изменялся и не подтверждает полный прогон 2.4.2.

## Что необходимо перед повторным полным прогоном

1. Исправить F1 (TTY-aware clear), отдельно проверить redirect и PTY.
2. Использовать только исправленную подготовку legacy-архива; до любых архивных вариаций фиксировать метаданные всех потенциально затрагиваемых родителей.
3. Предоставить отдельные одноразовые чистые пакетные окружения и недостающие семейства/версии для PT-CC-01, PT-DEB-05/16, PT-E2E-03; не удалять установленные зависимости на текущих стендах ради имитации чистой системы.
4. Завершить перечисленные BLOCKED варианты интерактива, опасных целей, fault injection, всех БД cold, last.sh, прерывания postinst и отдельного отсутствующего data-root mode4.
5. Повторить по новым уникальным QA-именам/логам и сверить S10. Только после всех обязательных PASS допустим суффикс passed.
