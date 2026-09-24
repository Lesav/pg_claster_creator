# Changelog

All significant project changes are recorded in this file.

[Русский оригинал](CHANGELOG_ru.md). This is a technical translation of the Russian changelog. Entries describe the respective historical releases, not necessarily current behavior. Historical artifact names and test results are retained; some referenced reports are no longer present in the current tree.

## 2.5.7 — 2026-09-24

- Added DEB mode 6: SQL on an existing cluster/database; missing targets warn and succeed without creating anything. Modes 4/5 offer explicit create/replace policy (CLI/ENV), with `re-<cluster>-<database>` package names for replacement. Added main-script SQL CLI/ENV, updated manuals and test plan; failed SQL is not automatically replayed.

- Release attachments now use `claster-creator-X.Y.Z.sha256` on GitHub and GitFlic. The CI build retains `SHA256SUMS` only as an artifact compatibility copy. GitFlic sends checksum files as `text/plain`; GitFlic 4.5.0 additionally needs the separate server-side checksum-name validation patch.

- The full eight-WSL run produced 4472 PASS results and 120 successful expected-return-code checks with no product failures; cleanup and exact server-minor restoration succeeded on every stand. The passed journal retains 26 explicitly untested variants and does not claim full coverage.

## 2.5.6 — 2026-09-14

- Updated create-claster-deb.sh: the package includes the latest passed test journal and the CHANGELOG and README documents.
- Added GitHub Actions for non-destructive DEB verification and tag-triggered release uploads with the automatic job token. Pinned actions, read-only PR builds, SHA-256 download verification, and refusal to overwrite conflicting assets. Existing releases/tags and PostgreSQL behavior are unchanged.
- Updated script version constants, README package examples and all six manual headers. Functional command-line options and environment interfaces are unchanged; builder help documents the new packaging rule.
- The preceding CI setup commit (`08c77ab`) passed a GitHub-hosted build and artifact checksum verification. After separate authorization, 2.5.6 was built locally and tested on eight WSL distributions; 31 offline publisher tests also passed. The journal records 35 fully confirmed IDs and 24 IDs with untested variants, no observed product failures, and successful cleanup. Its `passed` suffix was explicitly requested despite the documented skips; live 2.5.6 CI/tag publication remains untested.

## 2.5.5 — 2026-09-14

- The GitFlic release publisher now requires a separate secret `GITFLIC_RELEASE_TOKEN` (user API token). It neither uses nor changes `CI_JOB_TOKEN` and fails before API requests when the release token is missing or invalid. Added offline authentication-isolation tests and CI setup instructions; PostgreSQL scripts and their interfaces are unchanged.
- Confirmed CI publication and SHA-256 download verification of the original 2.5.4 DEB and SHA256SUMS in the temporary GitFlic project (pipeline 18, publication job 27). The server MIME restriction was fixed in a separate custom GitFlic image, not in this package; stock GitFlic 4.5.0 still requires that server-side support.
- Documented masked release credentials, retry behavior, manual tag-pipeline start when tag push does not trigger CI, and migration without temporary diagnostic branches. Existing v2.5.4 is unchanged.
- Aligned script versions, README examples and man headers. No cluster-management or CLI/ENV behavior changed; the 2.5.3 test journal retains only its original coverage. No new full cluster run is claimed.

## 2.5.4 — 2026-09-13

- Adopted the MIT License, copyright 2026 Andrei Lesnykh; added license notices to the three main scripts and both READMEs.
- All DEB modes now require and include LICENSE beside the installed scripts and as `/usr/share/doc/claster-creator/copyright`. The release-build helper stages and verifies both copies. Cluster-management logic is unchanged.
- Reorganized README in English with a Russian technical translation; retained the Russian changelog in CHANGELOG_ru.md and translated the release history into English.
- Added GitFlic 4.5 CI for Bash syntax, scripts-only DEB builds and package-content verification on a Shell runner tagged `pgcc-deb`. Generated packages are job artifacts, never Git content; matching `vX.Y.Z` tags publish DEB and SHA-256 release attachments.
- Set executable permissions explicitly on staged scripts so fakeroot re-execution works from clean Linux Git checkouts, not only Windows mounts.
- Runtime CLI/environment interfaces and cluster behavior are unchanged. The 2.5.3 journal remains evidence for its recorded scope; this packaging/documentation release does not claim a new full cluster test.

## 2.5.3 — 2026-09-13

- The syslog-ng fix is specifically intended for testing project functionality on WSL without PARSEC. It is inactive on physical servers and ordinary virtual machines outside WSL and does not change their syslog-ng or Astra audit settings.
- Added a targeted fix in create-claster.sh for stock Astra syslog-ng configurations on WSL without PARSEC: when pgN_kv_parser/pgN_audit_parser are missing, it uses the registered log file and a separate raw log without emulating structured Astra auditing. The original is preserved; syntax validation has a timeout and failures trigger rollback. Working/custom configurations and ordinary Linux systems are unchanged. No automatic reload/restart or CapabilitiesParsec change is performed. The English header documents symptoms and diagnostic steps.
- No new CLI/ENV arguments; usage and the Command-line options / Environment interface retain the existing contract. Versions of all three scripts and MAN pages are aligned; README and the test program have been clarified.
- Preserved the actual TEST-2.5.2-journal.md report: 32 IDs fully confirmed, with untested variants and reasons remaining for 27. Omissions are neither FAIL nor proof of PASS; an incomplete run without errors retains a filename without a status suffix. This is not a full passed result for 2.5.3.
- Retained reusable helpers for parallel WSL checks, package restoration, and cleanup verification. Package 2.5.3 includes all regular root-level Markdown files, excludes tests/, and retains the previous distribution configuration and gzip compression for older Astra versions.

## 2.5.2 — 2026-09-13

- A notification is written to stderr before stopping a cluster or its stock service. Interactive confirmations warn about the stop in advance; CLI/cleanup/postinst calls receive no additional input prompts.
- Updated the full plan: 59 mandatory IDs, ENV/configuration/major-name/notification coverage, per-WSL duration, and total duration. The release receives targeted checks on Mint and Astra 1.8.6, without claiming a full passed run or installing the package on the test systems.

- Added ENV equivalents for all functional builder and backup-wrapper arguments: CLI > nonempty ENV > configuration/default, including PGCC_SQL_FILE, PGCC_MODE, PGCC_DEPENDS, PGCC_OUTPUT_DIR, PGCC_INTERACTIVE/PGCC_FORCE, and wrapper target/retention parameters. Existing main-script ENV inputs and new wrapper inputs survive the scripts' own sudo re-execution. PGCC_CRON selects the existing interactive cron dialog. No new CLI actions for SQL/rename/start/stop were added.

- Fixed the shared cold restore/rename check: conflicts are identified by the major/name pair. Identical names across different majors are allowed unless actual path, service, or port conflicts exist.
- Added PGCC_CFG and --config FILE/--config=FILE to all three scripts: CLI > ENV > system > local configuration. An explicitly selected file is required, with no fallback on error; relative paths start at the invocation directory. Selection survives sudo, wrapper cron jobs, and the builder's last.sh. The selected configuration is embedded in the DEB without carrying the build-host path into postinst. Updated usage, English headers, README, man pages, and the test plan. Built dist/claster-creator-2.5.2.deb with the previous distribution configuration from Git.

- Kept the latest full journal, 2.5.1 (fail), and the 2.5.2 release report in the root. Older journals were moved to the local ignored tests directory and removed from the Git index. Commit history and previously released DEBs are not rewritten.
- In all five modes, create-claster-deb.sh includes every regular root-level .md file with mode 0644, without recursing into tests or following links. Removed the mandatory dependency on the 2.1.2 passed journal; updated help, man pages, and package-content checks.

## 2.5.1 — 2026-09-12

- Patch to the prepared 2.5.0 release: clarified usage, Command-line options, and Environment interface for all three scripts before building. The main script executes SQL interactively only; the builder accepts --sql-file in mode 5, but not SQL_FILE/PGCC_SQL_FILE from the environment. The wrapper neither executes SQL nor provides its own ENV equivalents for arguments.
- Clarified the scope of CLASTER_FORCE_INSTALL/CLASTER_FORCE_DB_INSTALL (postinst, not build time) and the main script's CLI/ENV/configuration precedence. This patch adds no CLI/ENV actions and does not change executable operation logic compared with the prepared 2.5.0 version.
- Aligned versions, README, TEST, and man pages. Package dist/claster-creator-2.5.1.deb uses gzip and the previous configuration from Git; the user's local configuration edit is excluded. The new release does not claim a full passed test run.

## 2.5.0 — 2026-09-12 (prepared minor release)

- Vanilla PostgreSQL: Debian/Ubuntu/Mint `postgresql-N` servers are recognized alongside `postgresql-N-server`; client/contrib/meta/dev/extension packages are excluded from server lists. Priority: SE/Enterprise → BE → Free/PostgreSQL; vanilla and Tantor Free have equal priority, and explicit package selection takes precedence. Backup metadata uses the package owning postgres, not a fabricated name ending in -server; DEBs select the actual naming format and pin the major. On Mint, the server provides versioned contrib, so the postgresql-contrib metapackage is not added. Checked real APT behavior and a trial DEB without installing the server.
- Main script: “Edit → 4 — Execute SQL” for a selected existing database, .sql selection by number/path, step-by-step return with 0, rejection by default, and target revalidation after confirmation. psql output remains visible until Enter; ON_ERROR_STOP stops execution on error. Added mandatory check PT-CC-26.
- Builder: mode 5 creates a cluster and database and applies an embedded `.sql` file; interactive selection by number from backup-dir or by relative/absolute path, CLI `--sql-file`, a reproducible last.sh, and a distinct `*-sql.deb` name.
- Mode 3 now lists cold archives only; mode 4 lists hot dumps only. Menu item labels begin with “Install scripts”.
- At installation, SQL runs as postgres with ON_ERROR_STOP and is not replayed automatically after failure. Markers and CLASTER_FORCE_INSTALL cover mode 5; CLASTER_FORCE_DB_INSTALL is forbidden for this mode. Added mandatory check PT-DEB-17 to the full test plan.
- This minor release combines menu-based SQL, SQL deployment DEBs, and vanilla support. Aligned the three script versions, usage, and man pages; `dist/claster-creator-2.5.0.deb` retains gzip control/data archives and the mandatory historical 2.1.2 journal. Targeted checks do not replace the full plan: no new full passed journal exists.

## 2.4.3 — 2026-09-12

- Fixed screen clearing in create-claster.sh: only when stdout is a TTY and TERM is nonempty and neither dumb nor unknown. Redirected output contains no clear commands; warnings are preserved.
- After extracting a cold archive and before starting the cluster, /var/log/postgresql is set to root:postgres and 1775 without recursively changing files. A mkdir/chown/chmod failure or a symlink in place of the directory aborts restore with diagnostics. This is not general permission filtering for every parent directory in an archive.
- Retained tests for legacy archive contents/metadata and rejection of an incorrectly repacked tree containing shared parent directories. Preserved the EXIT trap check and expanded CLI/ENV/positional negative tests. These checks do not replace the full live S01–S10 run.
- Aligned the three script versions, usage, and six man pages; `dist/claster-creator-2.4.3.deb` retains gzip for Astra 1.6/1.7 compatibility and the historical 2.1.2 journal. Targeted checks are documented in `TEST-2.4.2-fixes-regression.md`; there is no full passed run for the new functionality.

## 2.4.2 — 2026-09-12

Patch release publishing the 2.4.1 fixes. Compared with the tested working version 2.4.1, executable logic in all three scripts is unchanged: only the version number, documentation, and DEB were updated.

- Preserved rename fixes, effective-path validation, log/autostart link relocation, and partial-failure diagnostics. The targeted regression in `TEST-2.4.1-rename-regression.md` applies to the unchanged 2.4.2 functionality, but does not replace the full S01–S10 plan or close BLOCKED items in the 2.4.0 journal.
- Aligned the three script versions and six man pages; usage displays the current version. The full test plan retains expanded PT-CC-25 checks: prefix/reverse, a native-like fixture, effective paths, log handling, states/autostart, and failures.
- Distribution package `dist/claster-creator-2.4.2.deb` uses gzip for control/data and includes the mandatory historical 2.1.2 passed journal. No new full passed journal exists.

## 2.4.1 — 2026-09-12

Patch release fixing rename issues identified in `TEST-2.4.0-journal-fail.md`. Historical passed journals do not validate these changes; a separate regression is documented in `TEST-2.4.1-rename-regression.md`.

- Prevented repeated replacement of paths already updated by `pg_renamecluster` for `old → old_suffix`. The shared restore/move-data replacement function is unchanged.
- Before renaming, the stopped state is confirmed by an actual `pg_ctl status`; effective data/HBA/ident paths are checked before startup. The standard `config/log` link is updated when the native helper leaves it pointing to the old name.
- Rename does not call `systemctl enable/disable`; persistent/runtime Wants/Requires links are preserved and relocated. The native helper's systemd reload is disabled only for that child invocation; one bounded reload runs after preparing the configuration and unit. The previous systemd rename failure did not recur on any of the seven WSL systems.
- Failures report the stage, exit code, and recovery manifest; configuration, units, and vendor settings are preserved without copying the database or performing automatic rollback.
- The mock test now reproduces native-helper path updates and checks prefix/reverse renames, repeated application, states, autostart, and six failure cases. Live checks: 28 renames and 14 deletions on seven Astra WSL systems. The full plan, including BLOCKED variants, remains incomplete.
- Aligned the three script versions, usage/man pages, and documentation; CLI and backup formats are unchanged. The DEB retains gzip and the mandatory historical 2.1.2 journal.

## 2.4.0 — 2026-09-12

Minor release changing cluster deletion for all supported families. The historical 2.1.2 passed journal does not validate the new functionality; targeted regression results and coverage limits are documented in TEST.md.

- PostgreSQL/Postgres Pro/Tantor clusters are deleted without `pg_dropcluster`: stop with process and systemd verification, then remove the specific data, configuration, service, and links. Neither `syslog-ng-ctl reload` nor `systemctl disable` is called; service calls have timeouts. The syslog-ng configuration is removed, with the change taking effect at its next normal configuration reload.
- Unsafe paths, a missing PG_VERSION, overlaps with neighboring cluster data, and nested mount points prevent deletion. External symlink targets and shared/nonstandard logs are preserved; DEB force-install uses the same procedure.
- Consolidated the full plan into 10 scenarios: retained the previous 55 IDs and added stop/start and rename separately, for 57 checkpoints. Archives/packages and evidence are reused without reducing the compatibility matrix; test-system preparation requires no snapshots.
- Aligned all three scripts, usage/man pages, and documentation with version 2.4.0. DEBs continue to use gzip for Astra 1.6/1.7 compatibility.

## 2.3.5 — 2026-09-12

Patch release changing only input handling during server-package selection. Edition priorities, configuration, and cluster operations are unchanged. The historical 2.1.2 journal is retained; checks for this fix are documented in TEST.md.

- Server-package selection exits on `0`, empty/invalid input, or EOF without redisplaying the list. Invalid input is not passed to arithmetic expressions; valid selection and priorities are preserved.

## 2.3.4 — 2026-09-12

Patch release clarifying the selected-server display and fixing builder temporary-directory cleanup. Cluster-management operations, server-selection priorities, and CLI are unchanged. The historical 2.1.2 passed journal is retained unchanged and does not validate the new fixes; current checks are documented in TEST.md.

- The builder removes the parent `tmp` directory only if it created it during the current run and it is empty after cleanup. Pre-existing directories and unrelated files are preserved, including on build failure.

- The main menu heading displays only the currently selected server package for cluster creation, not every installed server. Configuration-based selection and priorities are unchanged.

## 2.3.3 — 2026-09-12

Patch release fixing packaging compatibility with older dpkg and extending the menu heading. Cluster-management operations and CLI are unchanged. The historical 2.1.2 journal is retained unchanged; checks for this release are documented in TEST.md.

- The main menu heading displays installed PostgreSQL/Postgres Pro/Tantor server packages and versions. The list refreshes when returning to the menu; client and removed packages are not shown. Server selection and priorities are unchanged.

- Fixed DEB compatibility with Astra 1.6/1.7 `dpkg`: the builder explicitly uses gzip for `control.tar` and `data.tar` in all modes, including fakeroot runs. Modern build-host compression defaults no longer produce unreadable `control.tar.zst` archives. Cluster-management logic is unchanged.

## 2.3.2 — 2026-09-11

Patch release changing only interactive menu organization, versions, and documentation. Cluster-management operations and the non-interactive interface are preserved. The historical 2.1.2 journal does not cover new 2.3.x features; current checks are documented in TEST.md.

- Grouped rename, port switching, and data relocation under submenu “4 — Cluster: Edit”, with items 1–3 and return via 0. Main menu numbering: backup — 5, restore — 6, delete — 7. Operation logic and CLI are unchanged.

## 2.3.1 — 2026-09-11

Patch release fixing rename conflict checks. This changes behavior, not just packaging; the historical 2.1.2 journal does not validate the fix.

- Rename is no longer blocked by a leftover unit file for an unregistered cluster when the service is inactive/failed and MainPID=0. Target unit files and links are backed up, then replaced after confirmation. A running/transitional service, a state-check failure, or existing configuration/data still blocks the operation.

## 2.3.0 — 2026-09-11

Minor release adding cluster state management and renaming, and fixing cold restore and builder navigation. The historical 2.1.2 passed journal does not validate the new features; actual check coverage and limits are documented in TEST.md.

- Added “3 — Cluster: Stop/Start”: select a cluster by name/number, automatically offer stop for online or start for down, and request `y/N` confirmation with rejection by default. State is rechecked after confirmation without substituting a different action. Rename moved to item 4 and delete to item 9.

- Added “4 — Cluster: Rename” to the main menu. Validates new-name syntax, uniqueness across all versions, and path conflicts; after confirmation, stops the cluster, runs `pg_renamecluster`, and reconciles configuration and unit files. Online/offline state and autostart are preserved. Configuration and old unit files are saved separately; database/role names and external cron jobs are unchanged.

- The DEB build wizard clears the terminal between steps; submenus include “0 — Back”. Invalid input returns to the previous step or exits at the main menu. Enter accepts the displayed default; EOF cancels the build without looping.

- Cold restore replaces a historical standard data root with the root for the server package family/version recorded in the archive, for example `tantor-free-16/subsys` → `tantor-be-18/smsn`. Custom roots are preserved. Extraction, configuration, and the DEB builder's plan use the new path.

- During cold restore, the name is checked against all registered clusters, regardless of PostgreSQL major version. Failure to obtain the cluster list blocks the operation rather than treating the name as available.

- Cold restore is not blocked by a broken `/.postgres/systemd/postgresql@VERSION-CLUSTER.service` helper symlink or copies in `systemd/save`. The old local cache is not used as a unit-file source; a saved unit is taken only from the selected archive or recreated. The cache is updated after unit restoration without following old symlinks. Active services, configuration, and data are protected against overwriting.

## 2.2.0 — 2026-09-11

Minor release with functional changes; the historical 2.1.2 journal is not full validation of version 2.2.0. Check scope is documented in TEST.md.

- A mismatch between the registered cluster version and `PG_VERSION` no longer blocks backup: the actual version is used in the archive name, package selection, and metadata; the original registration is retained separately. Cluster control uses the original address; retention and cold restore account for the difference.

- Added Tantor SE (Special Edition) and BE (Basic Edition) support to server selection, backup metadata, and DEB builds. Priority: SE/Enterprise, then BE, then Free/PostgreSQL; within a tier, the newer major comes first. Explicit selection is preserved.
- For backups, the Tantor edition is determined from the installed package owning the binary. Cron backup does not select or install a server from the global configuration.
- The historical 2.1.2 journal does not validate new Tantor SE/BE functionality; a separate integration run is required.

## 2.1.3 — 2026-09-09

This patch release does not affect management of PostgreSQL clusters, databases, backups, ports, or data directories. Only journal packaging, version numbers, and documentation changed. The previous version's 2.1.2 test journal remains fully applicable to unchanged functionality within the scenarios it verified and can be trusted. No new full functional run is claimed.

- Included the unchanged `TEST-2.1.2-journal-passed.md` in all DEB modes, installed under `/usr/local/share/pg_claster_creator/` with mode `0644`. Builds are rejected if this journal is missing.
- Package version is 2.1.3; the supporting journal version is explicitly fixed at 2.1.2 without renaming the historical report.

## 2.1.2 — 2026-09-09

- Added the final [2.1.2 test journal](TEST-2.1.2-journal-passed.md): 105 OK phases on seven Astra WSL systems. The journal is stored in the root; local intermediate journals in tests/ are excluded from Git.
- Improved diagnostics for missing clusters and `pg_lsclusters` errors, including before hot restore.
- Bounded vendor-service operation times on Astra/WSL and removed unnecessary stop/disable/unmask calls; privilege escalation uses `sudo -n` without a TTY.
- Cluster creation explicitly sets `peer` for local access and the selected host authentication method: MD5 through version 16, SCRAM for newer versions.

- All three scripts prefer `/usr/local/shared/pg_claster_creator/.new-claster.config`; if absent, they use the configuration beside the resolved script file. Main-script saves target the selected configuration.
- Backup lists in `create-claster.sh` and `create-claster-deb.sh` include symbolic links to archive files. Broken links and links to directories are excluded.

## 2.1.1 — 2026-09-06

Patch release introducing consistent compact size displays and clarifying package construction rules for hot and cold restore.

- Added an aligned archive file size to the interactive backup list in `create-claster-deb.sh`, with two decimal places and a two-letter unit. The size field is limited to nine characters; the value comes from `stat` without opening or extracting the archive.
- Separated DEB dependency construction by backup type: automatic PostgreSQL Pro hot restore uses only an ordered `contrib` chain that pulls in a matching server; cold restore depends only on the exact server package for the physical archive's major version.
- Corrected the mode-3 DEB filename suffix from the misspelled `-fill` to `-full`, indicating a package with a cluster fully populated from a cold backup.
- Unified human-readable database and cluster data-directory sizes in `create-claster.sh`: two decimal places, a two-letter unit, and an aligned field no longer than nine characters. Directory size is also shown on the selected-cluster information screen.

## 2.1.0 — 2026-09-06

Minor release with more reliable DEB deployment, reproducible build commands, safer database restore, and a full regression plan.

- An occupied TCP port no longer interrupts non-interactive cluster installation or `postinst`: the next available port is selected, and the warning reports the actual assignment and the `create-claster.sh --action port` command form for changing it later.
- In mode-2 and mode-4 packages, the occupied-port replacement notification is repeated at the end of `postinst`, after cluster creation or hot restore, so lengthy `pg_restore` output does not hide it.
- After an interactive build is confirmed, `create-claster-deb.sh` creates `create-claster-deb-last.sh` beside itself with mode `0755` and a ready-to-run non-interactive repeat command, including `--force`, absolute paths, and the selected parameters for modes 1–4.
- If the builder directory is not writable, the repeat file is saved in an automatically created `~/tmp`; non-interactive builder runs neither create nor modify the last-command file.
- During automatic PostgreSQL Pro selection, additional `postgrespro-ent-*-server` dependencies already covered by eligible `contrib` alternatives are omitted. The resulting `Depends` contains only `postgresql-common` and the `contrib` chain, which installs the matching server version itself.
- During cluster installation or relocation, a missing custom `--data-root` and `pg_{version}` directory are explicitly created and verified.
- Fixed generated `postinst`: a `.done` marker no longer suppresses deployment when the target cluster is absent from `pg_lsclusters`.
- Stale `.done`, `.cluster-created`, and `.data-moved` markers are removed automatically, after which modes 2–4 rerun the plan. Actual cluster presence is rechecked before writing new markers.
- Reconfiguration after an interrupted mode 3 or 4 continues the recorded intermediate stage rather than incorrectly treating the existing cluster as unrelated and skipping restore.
- Interactive deletion now always offers the appropriate backup: cold before cluster deletion and hot before deleting an individual database.
- Declining a hot database backup requires separate confirmation of deletion without a backup; after a successful backup, final confirmation of database deletion is still required.
- Added a shell-safe command to metadata in new hot and cold backups for repeating the corresponding DEB build non-interactively through `create-claster-deb.sh`.
- The command records mode, family and exact server package, version, cluster, port, absolute backup path, hot-backup database name, and any detected custom `data-root`.
- Hot restore with `--overwrite yes` no longer uses object-by-object `pg_restore --clean`, which failed on inherited table constraints.
- After validating the archive and dump table of contents and restoring missing roles, the existing user database is dropped with `dropdb --force`, recreated with its previous owner, and restored into the clean database.
- Replacement of system databases `postgres`, `template0`, and `template1` is forbidden; destructive-operation confirmation still defaults safely to no.
- Added a mandatory full test plan to `TEST.md` with 55 named checks, expected results, journal format, and end-to-end scenarios for all three scripts.
- Added generated `create-claster-deb-last.sh` to `.gitignore`.

## 2.0.2 — 2026-09-06

Patch release with automatic selection of the newest eligible PostgreSQL Pro version for hot-backup restore.

- For mode `4` packages with an implicit `postgrespro-ent` package, `--pg-version` now specifies the minimum target version: dependencies list `contrib` from version 18 down to that minimum so APT prefers the newest available complete set. Each `contrib` requires the server at exactly the same version.
- Generated `postinst` selects the actually installed PostgreSQL Pro version at or above the minimum and uses it for cluster creation and hot restore; an already installed minimum version is retained.
- Explicit `--package` still pins the exact server package and disables selection of a newer version. Mode `3` cold restore remains tied to the physical backup's version.

## 2.0.1 — 2026-09-06

Patch release with expanded cluster information, corrected package layout, and controlled DEB reinstallation.

- Added installation flag `CLASTER_FORCE_INSTALL=1`: the existing cluster is deleted without a backup using the main script's standard action, markers are reset, and the package plan runs again. Applies to modes 2–4, including cold restore.
- Added `CLASTER_FORCE_DB_INSTALL=1` for mode 4 only: the cluster is preserved, while the target database is forcibly restored from the hot dump with cleanup of the existing database.
- Using both force flags together is forbidden; `CLASTER_FORCE_DB_INSTALL` in modes 2 and 3 is rejected before any data changes.
- Mode `2`–`4` package `postinst` now finishes with exit code `0` and a warning if the target cluster is already registered; no redeployment or restore is performed in that case.
- Renamed builder `create-deb.sh` to `create-claster-deb.sh`; its localized man pages were renamed accordingly.
- `create-claster-deb.sh` is now included in every generated package under `/usr/local/share/pg_claster_creator`, without a symlink in `/usr/local/bin`.
- When `create-claster.sh` is launched through the package link in `/usr/local/bin`, configuration is additionally searched for in `../share/pg_claster_creator` relative to the invoked script.
- The interactive “Information: deployed clusters” action now displays a numbered, colored cluster list.
- Selecting a running cluster displays a numbered, aligned list of all its databases, including templates, with sizes; a stopped cluster is not started automatically.
- Non-interactive `--action info` retains the previous full `pg_lsclusters` table output.

## 2.0.0 — 2026-09-05

Major release adding scheduled hot backups, role transfer, and bilingual system documentation.

### Hot backups and roles

- Added application owner roles and ACL grantee roles for the selected database to hot-backup metadata.
- Preserved role attributes `LOGIN`, `SUPERUSER`, `INHERIT`, `CREATEROLE`, `CREATEDB`, `REPLICATION`, and `BYPASSRLS`, connection limits, validity periods, and available SCRAM/MD5 hashes from `pg_authid`; plaintext passwords are not saved.
- All missing roles from the metadata are created before `pg_restore`, allowing `GRANT` entries for roles such as `aida_writer` and `aida_reader` to be restored.
- Existing and system roles are unchanged; compatible owner discovery from the dump table of contents is retained for older archives.
- Hot archives receive mode `0600`, with actual-mode verification and a warning on filesystems that do not support POSIX permissions.

### Scheduled hot backups

- Added `create-claster-backup.sh` version `2.0.0` with detailed `--help`, `--version`, and English header documentation.
- The script accepts `<version> <cluster> <database>` and invokes a non-interactive hot backup through `create-claster.sh`.
- Added `--backup-dir`, retention via `--files-cnt` or `--files-size`, size units up to TiB, and concurrent-run locking with `flock`.
- After a successful backup, retention selects files only by the strict `{version}-{database}-YYYYMMDD-hhmmss-dmp.tar.gz` pattern without opening archives or reading metadata.
- Tasks for identically named databases of the same version on different clusters can be separated using different `--backup-dir` directories.
- `--cron` interactively requests the schedule and any missing limit, then atomically creates a dedicated `/etc/cron.d/pg-claster-backup-*` task with its own log.

### Build and installation

- `create-deb.sh` creates a fresh `tmp/create-deb.XXXXXX/rootFs` skeleton itself; a prebuilt tree is no longer required.
- `create-claster-backup.sh` is installed under `/usr/local/share/pg_claster_creator/` with symlink `/usr/local/bin/create-claster-backup.sh`.
- Bumped the version in all three `.sh` scripts to `2.0.0`.

### Man pages

- Added English man pages for `create-claster.sh`, `create-claster-backup.sh`, and `create-deb.sh`.
- Added Russian localized man pages for all three scripts.
- During builds, pages are compressed deterministically with `gzip -9n` and installed in `/usr/share/man/man1` and `/usr/share/man/ru/man1`.
- Documented actions, options, environment variables, retention, cron, DEB build modes, files, examples, and authorship.

## 1.2.0 — 2026-09-05

Extended the interactive and automatable PostgreSQL cluster-management tool.

### Environment and package preparation

- Added a mandatory check for `postgresql-common`.
- Implemented APT installation of missing `postgresql-common`, showing installation progress.
- Added discovery of installed and available server packages.
- Added PostgreSQL Pro Enterprise, PostgreSQL Server, and Tantor Free family support.
- Available packages are grouped by PostgreSQL major version and sorted by name within each group.
- Package priority is assigned by PostgreSQL version, newest to oldest; packages of the same version have equal priority.
- APT metadata is refreshed when package information is unavailable.
- The APT candidate check runs with locale `C`, so it works with English `Candidate:` output even when the system interface uses a Russian locale.
- Server executable `postgres` is checked after installation.
- PostgreSQL Pro installs the `postgrespro-ent-{version}-server` and `postgrespro-ent-{version}-contrib` set; the metapackage conflicting with `postgresql-common` is not used.
- An APT simulation runs before package changes; the operation is cancelled if any installed package would be removed.
- Before a vendor package is installed, any systemd mask is forcibly removed from its stock service.
- After installation, the stock vendor service is stopped and its autostart disabled; `systemctl mask` is not used.
- Normal repeat runs are quiet: messages about already installed prerequisite/server packages, standard `systemctl disable` output, and successful `stop/disable` confirmations are hidden.
- On a `systemctl` failure, command diagnostics are retained, then the script exits with a clear message.
- Warnings and messages about a nonstandard `/.postgres` layout remain visible when entering Menu1; the next heading does not clear the terminal.
- Actual package installation output is not hidden and also remains visible until the main menu appears.

### Configuration

- Moved common settings into `.new-claster.config`.
- Added locale, PostgreSQL family/version, cluster, and backup-directory settings.
- Implemented safe configuration saving through a temporary file.
- The script attempts to set configuration permissions to `0600` during operation.
- Fixed `cls_pt`, `cls_nm`, `cls_ch`, `cls_us`, and `cls_pw` as user defaults; they are no longer overwritten by installation/restore results, arguments, or environment variables.

### The `/.postgres` helper layout

- Implemented creation of `/.postgres`, `/.postgres/systemd/save`, `/.postgres/tmp`, and the backup directory.
- Symlinks `etc`, `data`, `bin`, `lib`, `share`, `man`, and `doc` are created dynamically for the selected server version/family.
- Added required symlinks `include -> {PG_HOME}/include` and `run -> /var/run`.
- Fixed the Tantor Free symlink layout.
- Created a compatible `/usr/lib/postgresql/{version}` path for PostgreSQL Pro and Tantor.
- Existing regular files and directories at expected symlink locations are not overwritten automatically.
- Recognized and preserved the reverse `/var/lib/postgresql/{version} -> /.postgres/data` layout without a false warning or a symlink loop.

### Interactive interface

- Added a script-version heading, separators, and step names.
- Removed the duplicate version heading on the first transition from preparation to the main menu.
- Implemented the main menu: exit, information, installation, port switching, data relocation, backup, restore, and deletion.
- Added a separate “Cluster: Move data” action; renumbered actions: port — `3`, move — `4`, backup — `5`, restore — `6`, delete — `7`.
- Added handling of returns from nested screens and invalid input.
- An invalid number during package selection clears the screen and redisplays the selection menu with a warning.
- Added consistent warnings and errors with line numbers and exit codes.

### Command line and automation

- Added `-v` and `--version` to display the version without checking privileges, configuration, or packages.
- Added `-h` and `--help` with parameter/environment descriptions and invocation examples.
- Added non-interactive mode for `info`, `install`, `port`, `move-data`, `backup`, `restore`, and `delete`.
- Non-interactive mode is enabled automatically by `--action` or `PGCC_ACTION`; stdin reads, menus, confirmations, and pauses are disabled.
- Parameters are accepted through CLI arguments and `PGCC_*` environment variables; arguments take precedence over environment, and environment over `.new-claster.config`.
- Added cluster addressing by version/name without numbered interactive selection.
- For restore, added archive selection by absolute path or by filename relative to `backup_dir`.
- Added configurable `backup-before-delete`, `clear-wal`, and `overwrite` settings with safe defaults; `overwrite` applies only to hot restore into an existing database.
- Non-interactive mode does not clear the terminal using control sequences.
- Successful non-interactive preparation checks are quiet; package installation, warnings, and errors remain visible.
- `--action info` no longer displays a separate preparation stage, checks the server package, changes vendor-service state, or rebuilds `/.postgres` links.
- Added `pg_ctlcluster`-style positional addressing for `backup` and `delete`: `--action backup VERSION CLUSTER` and `--action delete VERSION CLUSTER`.
- Added positional argument count checks and prohibited mixing positional addressing with `--pg-version/--cluster-name`.
- `--backup-file` and `PGCC_BACKUP_FILE` support absolute paths and paths relative to the current directory; for compatibility, a filename not found there is also searched for in `backup_dir`.

### Cluster creation

- Added numbered output of existing clusters.
- Restored the `pg_lsclusters` color scheme in numbered lists: `online*` is green; other states are red.
- Color is used only in terminal display; selection and machine-parsed rows contain no ANSI codes.
- Implemented interactive input of port, cluster name, schema/owner, user, and password.
- Added port-range and registered-cluster conflict checks.
- Added duplicate cluster-name validation.
- Changing a cluster name updates defaults for related parameters.
- Added SQL-identifier name validation.
- Made interactive input transactional: values under validation are held separately and applied only after overall confirmation.
- Fixed invalid input being retained as a new default: after an invalid port, the next prompt again shows the last valid value.
- Cancelling a dialog does not change current-run parameters or `.new-claster.config`.
- Added interactive selection of the system data directory or a custom data root.
- For root `/DATA`, a version-16 cluster directory is `/DATA/pg_16/{cluster name}`.
- Custom-directory validation requires an absolute path with no whitespace; the final cluster directory must be absent or empty.
- Added `--data-root` and `PGCC_DATA_ROOT` for automation; the selected path is not saved to `.new-claster.config`.
- Extended installed-server directory detection to read `postmaster.opts` for clusters with nonstandard data paths.
- Clusters are created with `pg_createcluster` using separate data and log locations.
- Generated additional `conf.d` settings, `pg_hba.conf` network rules, and port, cluster-name, and password-encryption settings.
- Available extensions are automatically added to `shared_preload_libraries`.
- Created a separate systemd unit and a saved copy under `/.postgres/systemd/save`.
- Created the database, schema, application roles, and `cron_user` role.
- Configured `search_path` and `lc_messages` for newly created roles.

### TCP port switching

- Added colored numbered cluster selection and a prompt for the new TCP port.
- Checked range `1–65535`, equality with the current port, conflicts with another cluster, and actual TCP-port use by an unrelated process.
- Changed port settings through `pg_conftool`; reconciled active settings in `conf.d` and `postgresql.auto.conf`.
- A running cluster is stopped before the change and restarted afterward with result verification; a stopped cluster retains its state.
- Added non-interactive `--action port`, option `--port`, and equivalent variables `PGCC_ACTION=port` and `PGCC_CLUSTER_PORT`.
- Fixed the warning function: when startup-screen preservation is disabled, warnings always return a successful internal status and no longer trigger the fatal-error handler.

### Cluster data relocation

- Added colored numbered cluster selection and a choice of default or custom data placement.
- For root `/DATA`, the target path is `/DATA/pg_{version}/{cluster}`.
- The default path is determined by the server distribution: the standard PostgreSQL/PostgreSQL Pro directory or a separate Tantor Free directory.
- Checked target occupancy, physical-path equality, attempts to move inside the source directory, a symlink at the destination, and safety of the final path component.
- A running cluster is stopped before `mv` and restarted after the new path is verified; a stopped cluster remains `down`.
- After relocation, data-directory references are updated in configuration, `postgresql.auto.conf`, `postmaster.opts`, and active/saved systemd units.
- Verified the result against the actual data directory reported by `pg_lsclusters`.
- Added `--action move-data` for automation; `--data-root` and `PGCC_DATA_ROOT` select a custom root, while omitting them selects the default placement.

### Cold backups and deletion

- Added cold backup without deletion: a cluster that was running before the operation restarts automatically after successful archiving.
- Added an interactive deletion mode choice: delete a cluster or an individual database.
- Database deletion uses sequential numbered cluster selection and database selection by number or exact name from a list with sizes.
- The database is deleted using the version-specific `dropdb --force` after separate confirmation that safely defaults to no.
- Deleting `postgres` is forbidden; `template0/template1` are not offered, and application roles are retained after database deletion.
- Non-interactive `delete` remains compatible with the previous cluster-deletion behavior.
- Added interactive selection of a cluster to delete.
- Fixed deletion-target output: the numbered list is displayed in the terminal rather than captured by an internal command substitution.
- A cold backup is offered before deletion by default.
- Archive names follow `{version}-{cluster}-YYYYMMDD-hhmmss.tar.gz`.
- Deletion without a backup requires separate confirmation.
- The cluster is stopped normally before archiving.
- Added optional WAL reset using the version-specific `pg_resetwal` or `pg_resetxlog` utility.
- Backups include the selected cluster's configuration, data directory, log, and systemd unit.
- Symlinks are dereferenced when archiving.
- Added source hostname, date, backup type, package, family and full PostgreSQL version, source cluster parameters, and names/sizes of every database to `root/backup-info.env`, including template databases and databases that prohibit connections.
- For every database in a cold backup, saved the exact byte size and human-readable `pg_size_pretty` size at the start of the operation.
- Displayed `du -sh` for the data directory before packaging; saved the human-readable size, allocated size in bytes, and original `du -sh` line in metadata.
- A stopped cluster is started temporarily to collect mandatory database metadata, then stopped again before archiving.
- `backup_dir`, including the default `/.postgres/backup`, may be a symlink to a directory; the link is not replaced and is used both for writing backups and for finding restore archives.
- Added explicit diagnostics for broken links, links to non-directories, and missing access permissions.
- Removed generated systemd files and service symlinks after deletion.
- The shared `/var/log/postgresql` directory is not deleted with a cluster; `pg_dropcluster` removes only the log file belonging to the selected cluster.
- After `pg_dropcluster`, explicitly cleaned and verified the selected cluster's configuration/data directories if the native utility left them on disk.
- Recursive deletion is protected by absolute normalized-path validation and an exact match between the final component and cluster name; parent directories are not removed.
- Cleanup supports the system path, the `/.postgres/data` layout, and custom `/DATA/pg_{version}/{cluster}` paths.
- The selected cluster's systemd unit and links are removed from all supported directories, not just one assumed location.

### Hot backups

- Added backup menu choices “1 — hot” and “2 — cold”, with cold as the default.
- After selecting hot backup, added interactive selection of an existing database by number or name.
- Fixed numbered-list handling: input `2` now selects the second database rather than being validated as the literal database name `2`.
- Made number-based selection the primary interactive method while retaining exact-name input.
- Added an aligned database-size column, calculated through `pg_database_size` and formatted with `pg_size_pretty`.
- The default is the number of the database matching the cluster name, or the first database in the returned list if no match exists.
- Hot dumps use the selected version's native `pg_dump` without stopping the cluster.
- The outer archive is named `{version}-{database}-YYYYMMDD-hhmmss-dmp.tar.gz`.
- The archive contains custom-format dump `{version}-{database}-YYYYMMDD-hhmmss-dmp.backup` and a separate `backup-info.env`.
- Hot-backup metadata includes source hostname, date, PostgreSQL version, source cluster name/port, database name, and its exact byte size and human-readable `pg_size_pretty` size at dump completion.
- Added `--backup-type`, `--database`, `PGCC_BACKUP_TYPE`, and `PGCC_DATABASE` for automation.

### Restore

- Filtered the restore list by strict cold/hot archive naming formats; unrelated `.tar.gz` files are not displayed.
- Added automatic hot-archive detection through the `-dmp.tar.gz` suffix.
- Restore accepts new hot archives with metadata and remains compatible with older dump-only archives.
- Added numbered target-cluster selection and interactive target-database selection for hot restore.
- Before hot backup and restore, displayed a numbered list of connectable user databases in the selected cluster; an existing database is selected by number or name.
- During restore, an absent database name may be entered instead of a list item; that database is created before restoration.
- If the hot backup's source database already exists in the target cluster, its number is offered by default; otherwise, the source name is offered for creating a new database.
- Removed a redundant database-catalog recheck during hot backup after selecting a database from an already loaded list.
- Database names support Latin letters, digits, periods, hyphens, and underscores, including names such as `asvd-old`.
- If the hot-restore target database is absent, the version-specific `createdb` creates it after confirmation. Its owner is the application role found in the dump, or `postgres` if no such role exists.
- For a new database, `pg_restore` runs without cleanup; `overwrite=yes` is required only for an existing database.
- Before hot restore, object-owner roles are determined from the dump table of contents.
- Missing owner roles are created with administrative attributes and a password equal to the role name; existing roles are unchanged.
- The new target database is owned by the application administrator role found in the dump, or `postgres` if the dump contains no application owner.
- The dump is restored into a running cluster with the version-specific `pg_restore --exit-on-error`; existing databases additionally use `--clean --if-exists`.
- Interactive deletion of existing objects requires confirmation defaulting to no; non-interactive hot restore requires `--overwrite yes`.
- Added backup selection from the configured directory.
- Added target cluster-name and port prompts defaulting to values from the backup.
- Implemented checks for new-name and port conflicts with existing clusters.
- Restoring under a new name renames configuration, data, log, and systemd unit paths and updates `cluster_name` and the port.
- Updated `external_pid_file` for the new name so the systemd unit does not remain `activating` after PostgreSQL has actually started.
- Startup waiting is limited to 60 seconds; native Astra checks `online` and `active`, while WSL checks actual `online` state after direct startup.
- For repeated restore, added a bounded direct cluster stop and synchronization of stuck systemd state.
- WSL cluster startup uses `pg_ctlcluster --skip-systemctl-redirect`: the command no longer hangs when redirected to an unready systemd; success is confirmed by actual `online` state.
- Implemented archive metadata reading and validation.
- Installs the server package recorded in the backup when needed.
- Cold restore over an existing cluster is forbidden: interactive mode displays `АЛАРМ` (ALARM) and repeats the name prompt; non-interactive mode exits with an error before extraction.
- Checks cover not only `pg_lsclusters` entries but also leftover configuration/data directories and active/saved systemd units.
- Target-name availability is rechecked immediately before archive extraction.
- Fixed actual systemd-unit discovery under `/etc`, `/usr/lib`, or `/lib/systemd/system`; new cold archives include the discovered file.
- Added compatibility with old cold archives lacking a unit file: restore creates a new unit with the target name and data directory.
- Restored original absolute paths, systemd unit, and cluster settings.
- Existing directory symlinks are preserved during restore; archive contents are written to the link target directory.
- Before extraction, all archive paths are checked to remain beneath the `root/` prefix and contain no `..` traversal.
- After restore, runs `daemon-reload`, enables the service, and starts the cluster.

### Compatibility

- The script targets Bash 4.4 and GNU utilities available in Astra Linux SE 1.6.
- Added safe inclusion through `source` for functional tests without automatically calling `main`.
- Added WSL detection when the PARSEC device is absent and targeted filtering of the nonfatal warning `Не удается открыть файл управления PARSEC.` (“Cannot open the PARSEC control file”); other errors and command exit codes are preserved.

### DEB package builds

- Added `create-deb.sh` version `1.2.0`, with `--help` and version output through `--version`.
- Builds use a user-provided `tmp/rootFs` skeleton, a temporary directory inside `tmp`, and output directory `dist`.
- Packages include the configuration, main script, and Markdown documentation, and create symlink `/usr/local/bin/create-claster.sh`.
- Implemented four modes: scripts installation, empty-cluster creation, cold cluster restore, and cluster creation with hot database restore.
- Modes 3 and 4 require archive type/version validation and embed the backup in the package.
- Added package naming based on mode, PostgreSQL family, version, cluster, and database.
- Every package declares a dependency on `postgresql-common`; modes 2–4 additionally depend on the selected server package and, for PostgreSQL Pro, matching `contrib`.
- Automatic deployment runs through a non-interactive `postinst` after dependency installation; state markers prevent operations from being reapplied.
- `.new-claster.config` is registered as a `conffile` and installed with mode `0600`.
- For older Astra Linux `dpkg-deb` and Windows directories, added automatic execution of the build stage through `fakeroot`, ensuring `root:root` ownership and correct permissions.
- Build modes 2–4 are interactive by default; added explicit `--non-interactive` for automation.
- For modes 3–4, added a shared numbered backup list from `backup_dir`/`--backup-dir`, displaying the automatically detected cold/hot type.
- Added safe reading and aligned display of backup metadata without executing its contents.
- Depending on the mode, interactive prompts refine server family/package, version, cluster name/port, schema, user, password, target database, and data placement.
- Cold backups retain their source version and server package; target name, port, and placement can be changed.
- Cold restore can use source, default, or custom placement; when needed, `postinst` performs resumable relocation through `create-claster.sh --action move-data`.
- Split `postinst` markers into cluster creation/restore and data-relocation stages so reconfiguration continues unfinished work.
- Added detailed English header comments to `create-claster.sh` and `create-deb.sh`, documenting author, purpose, options, arguments, and environment variables.
- Added author `Andrei Lesnykh (AO NIKIET) <lesnyx@ya.ru>` to the generated DEB's `Maintainer` and `Description/Author` fields.
- Changed argument-free `create-deb.sh` startup to interactive numbered mode selection 1–4; direct building of the previous scripts-only package now uses explicit `--mode 1`.
- For modes 2–4, added repeatable `--depends` with comma-separated additional DEB dependencies, deduplication, and a separate interactive prompt.

## 1.1.0 — 2026-09-05

First minor extension of the cluster-management script, preserved by tag `v1.1.0`.

- Added separate TCP port-switching and data-directory relocation actions.
- Implemented individual database deletion through interactive cluster/database selection.
- Expanded hot/cold backups, metadata, and database/data-directory size reporting.
- Strengthened safety of cold restore, cluster renaming, and systemd-unit handling.
- Added custom data paths, colored cluster lists, and quiet preparation.
- Fixed PostgreSQL startup and PARSEC warning filtering in WSL.

## 1.0.0 — 2026-09-05

First recorded script version.

- Implemented APT package preparation, server-distribution selection, and creation of the `/.postgres` layout.
- Added PostgreSQL cluster installation, inspection, cold/hot backup, restore, and deletion.
- Moved common settings into `.new-claster.config`; parameters are also supported through arguments and environment variables.
- Added backup metadata, symlink handling, systemd units, and compatibility with Astra Linux in WSL.
- Preserved the original release state with tag `v1.0.0` and branch `release/1.0.0`.
