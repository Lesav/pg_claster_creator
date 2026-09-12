# Точечная проверка рабочих исправлений после 2.4.2

Дата: 2026-09-12, 20:12–20:22 MSK. **Точечная регрессия успешна; это не полный passed-журнал S01–S10.**

По согласованию проверены исправления пунктов 1, 2, 3 и доработка тестов по пункту 5. Пункт 4 (дополнительные тайм-ауты) не реализован и не проверялся. Полный прогон с удалением всех кластеров/пакетов отложен по ответу пользователя.

## Проверенные исходники

Рабочий create-claster.sh сохраняет номер 2.4.2, но отличается от выпущенного DEB.
SHA-256: `1ae5ae04e7ddb72b4e92ef0290d3ad29b8bb96f0f46c016876e65406a95c1a1b`.
Старый dist/claster-creator-2.4.2.deb не пересобирался и эти исправления не содержит.
Установленные сценарии WSL не заменялись. Старый TEST-2.4.2-journal-fail.md не изменён.

## Изменения

- Единая clear_screen: stdout должен быть TTY, TERM — непустым и не dumb/unknown. Все прежние прямые clear маршрутизированы через неё; сохранено поведение PRESERVE_NEXT_CLEAR.
- После распаковки cold-архива вызывается restore_log_directory_permissions, до запуска кластера. Только /var/log/postgresql получает root:postgres и 1775; рекурсивного chown/chmod нет. Ошибки mkdir/chown/chmod и финальная символьная ссылка дают понятный отказ.
- Никакой общей фильтрации произвольных архивных путей или исправления прав остальных родителей не добавлено. PGDATA сохраняет архивные права.
- В tools/prx-test-live-edges.sh закреплены проверки состава/метаданных legacy-архива, отказ от известных ошибочных parent-tree архивов, замер родителей даже после неуспешного restore. Исправление прав log-parent проверяется отдельно от неизменности остальных родителей.
- tools/prx-test-full-contracts.sh повторно использован из tmp/save и расширен с 44 до 79 проверок: все семь действий CLI/ENV, позиционные backup/delete, смешанные/недостающие/лишние аргументы и пропущенные значения ключей. Source внутри функций не оставляет некорректный продуктовый EXIT trap.
- В prx-test-edit-menu.sh, prx-test-cluster-power.sh и prx-test-cluster-delete.sh восстановлен собственный EXIT trap после source продукта. Ранее он мог быть заменён продуктовым и не удалять fixture.
- README, usage, английский header, две man-страницы и TEST.md согласованы. CHANGELOG содержит раздел «Не выпущено», без переписывания истории опубликованного релиза.

## Результаты по WSL

| WSL | Экран/права/архив | Contracts | Общая fixture-регрессия | Очистка |
|---|---|---|---|---|
| alse-1.6.14-mg12.4.0 | [16 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.6.14-mg12.4.0/fixes-201225-r2/results.tsv) | [79 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.6.14-mg12.4.0/contracts-201225-r2/results.tsv) | [PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/recheck/alse-1.6.14-mg12.4.0/fixtures/check.log) | [cleanup](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.6.14-mg12.4.0/fixture-cleanup/run.log) |
| alse-1.7.9-uu1 | [16 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.7.9-uu1/fixes-201225-r2/results.tsv) | [79 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.7.9-uu1/contracts-201225-r2/results.tsv) | [PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/recheck/alse-1.7.9-uu1/fixtures/check.log) | [cleanup](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.7.9-uu1/fixture-cleanup/run.log) |
| alse-1.8.2.uu1-mg15.7.0 | [16 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.2.uu1-mg15.7.0/fixes-201225-r2/results.tsv) | [79 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.2.uu1-mg15.7.0/contracts-201225-r2/results.tsv) | [PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/recheck/alse-1.8.2.uu1-mg15.7.0/fixtures/check.log) | [cleanup](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.2.uu1-mg15.7.0/fixture-cleanup/run.log) |
| alse-1.8.3.uu1-mg15.8.4 | [16 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.3.uu1-mg15.8.4/fixes-201225-r2/results.tsv) | [79 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.3.uu1-mg15.8.4/contracts-201225-r2/results.tsv) | [PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/recheck/alse-1.8.3.uu1-mg15.8.4/fixtures/check.log) | [cleanup](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.3.uu1-mg15.8.4/fixture-cleanup/run.log) |
| alse-1.8.4-mg16.3.0 | [16 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.4-mg16.3.0/fixes-201225-r2/results.tsv) | [79 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.4-mg16.3.0/contracts-201225-r2/results.tsv) | [PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/recheck/alse-1.8.4-mg16.3.0/fixtures/check.log) | [cleanup](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.4-mg16.3.0/fixture-cleanup/run.log) |
| alse-1.8.5-mg16.3.0 | [16 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.5-mg16.3.0/fixes-201225-r2/results.tsv) | [79 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.5-mg16.3.0/contracts-201225-r2/results.tsv) | [PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/recheck/alse-1.8.5-mg16.3.0/fixtures/check.log) | [cleanup](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.5-mg16.3.0/fixture-cleanup/run.log) |
| alse-1.8.6 | [16 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.6/fixes-201225-r2/results.tsv) | [79 PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.6/contracts-201225-r2/results.tsv) | [PASS](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/recheck/alse-1.8.6/fixtures/check.log) | [cleanup](D:/Ai/pg_claster_creator.backup/TEST-2.4.2/alse-1.8.6/fixture-cleanup/run.log) |

Итого последних серий: 112 + 553 = **665 успешных точечных проверок**, дополнительно 7 успешных запусков общей fixture-регрессии. Это не 665 контрольных точек полного плана. Первые серии fixes-201225 (15 проверок) и contracts-201225 сохранены; повтор r2 добавляет проверку архива и полную запись команд contracts.

## Что действительно проверено

1. Файл, pipe, PTY с xterm, пустой/unset TERM, dumb/unknown; сохранение предупреждения, главное меню и info-menu с подменённым реестром down-кластера. В PTY есть очистка, в остальных соответствующих случаях — нет.
2. Реальные mkdir/chown/chmod/stat на временном Linux-каталоге: исправление root:root 0755 в root:postgres 1775, возможность записи postgres, неизменность владельца/прав существующего файла. Системный /var/log/postgresql не изменялся: в тесте перенаправлена только константа пути проверяемой функции.
3. Инъекции ошибки mkdir/chown/chmod дают rc=1; финальная ссылка отклоняется. Отдельно проверен порядок вызовов в исходнике: extraction → права → start.
4. Миниатюрный tar: unit удаляется без перепаковки дерева, список и метаданные остальных членов совпадают; исходный SHA неизменен; ошибочно упакованный root/ с общими родителями отвергается тестовой обвязкой.
5. Contracts вызывают настоящие функции разбора/валидации с fixture-значениями. Они не выполняют установку пакетов, настоящий postinst или SQL.
6. Общая fixture-регрессия покрывает прежние отрицательные проверки rename/delete/power, Tantor, меню, tmp и конфиги; системные службы/кластерные операции в этих helper’ах подменены.

Полное восстановление холодного кластера с этими новыми байтами, живой postinst, last.sh и все ранее незакрытые варианты полного плана в этой задаче не выполнялись. Их нельзя считать PASS на основании изолированных проверок.

## Подготовка следующего пакетного прогона

Read-only helper tmp/save/check-server-minor.sh сохранил на каждом WSL исходные пакеты и версии:
Postgres Pro 16.2; Tantor SE 17.9; Tantor Free 16.6 и 16.8; Postgres Pro 13.23 и 17.7; Tantor BE 18.1.
По текущим индексам apt-cache madison для всех семи найдены пакеты исходной major.minor.
Это предварительная сверка имён/версий, не доказательство успешного скачивания или установки; перед разрушительным прогоном проверить заново.

Доказательства: D:/Ai/pg_claster_creator.backup/TEST-2.4.2/WSL/minor-gate-201225/.
Список удаления сформирован из согласованного apt list фильтра, исключены только два common-пакета.
Удаление не выполнялось; реестр до/после read-only проверки совпал.

## Артефакты и ограничения

Временные Linux-fixture каталоги и тестовые архивы создавались только из искусственных данных и удалены штатным cleanup. Найденные остатки трёх старых helper’ов из первой серии удалены только при совпадении точного префикса, владельца и временного интервала текущего запуска; адреса записаны в fixture-cleanup/run.log. Старые каталоги вне этого интервала не удалялись. После повторного запуска новых остатков этих helper’ов нет.

В каталоге TEST-2.4.2 оставлены обезличенные результаты и логи. Успешные новые helper’ы сохранены в tmp/save/test-screen-log-permissions.py и tmp/save/check-server-minor.sh; повторно используемые модули перенесены в tools с обновлением INDEX.md.

В некоторых запусках WSL сообщал о невозможности старта systemd user session root; проверяемые команды завершились успешно. Эти сообщения не скрывают тестовые ошибки.

Не выполнялись: удаление реальных кластеров/серверных пакетов, установка исправленных сценариев в WSL, сборка DEB, изменение версии, commit, push.
