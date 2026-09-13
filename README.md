# pg_claster_creator

Manage PostgreSQL clusters on Astra Linux and compatible Debian-based systems using interactive Bash menus or command-line automation. Build Debian packages that install the tools and optionally deploy a cluster, restore a backup, or initialize a database from SQL.

**Version:** 2.5.3 · **Language:** English | [Русский](README_ru.md)

The spelling `claster` is retained in project, command, and package names for compatibility. Interactive messages and `--help` output are currently in Russian; script headers and manual pages include English documentation.

## Contents

- [Features](#features)
- [Requirements and server selection](#requirements-and-server-selection)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Usage and automation](#usage-and-automation)
- [Building Debian packages](#building-debian-packages)
- [Safety and operational limits](#safety-and-operational-limits)
- [WSL notes](#wsl-notes)
- [Documentation and testing](#documentation-and-testing)
- [Contributing and licensing](#contributing-and-licensing)

## Features

| Tool | Purpose |
| --- | --- |
| `create-claster.sh` | Prepare server packages; inspect, create, start/stop, rename, relocate, back up, restore, and delete clusters; change ports and execute SQL. |
| `create-claster-backup.sh` | Run hot database backups, apply retention by count or total size, and configure cron jobs. |
| `create-claster-deb.sh` | Build scripts-only or database-deployment DEB packages. |

Hot backups use PostgreSQL custom-format dumps. Cold backups contain cluster data, configuration, and service information. Both include metadata identifying the source server. Backup directories and readable backup/SQL files may be accessed through symbolic links.

Clusters are identified by **PostgreSQL major version and cluster name**. For example, `17/demo` and `18/demo` are distinct clusters; their paths, services, and ports must still be free of conflicts.

## Requirements and server selection

- Linux with APT, `dpkg-query`, and systemd; Bash 4.4 or later.
- Root privileges, or `sudo`, for cluster management and scheduled backups.
- Configured APT repositories providing `postgresql-common`, its dependencies, and the required server packages. Vendor repository access is the administrator's responsibility.
- GNU command-line utilities, including `tar`, `find`, `sort`, `sed`, and `awk`.
- `flock` for the backup wrapper; an installed and running cron service for scheduled jobs.
- For DEB builds: `dpkg-deb` and `gzip`; `fakeroot` is also required when building on a Windows-mounted filesystem in WSL.
- The locale selected in the configuration must be available on the host.

The project targets Astra Linux 1.6, 1.7, and 1.8 and compatible Debian/Ubuntu systems. Test evidence also includes Linux Mint 22.3; this is not a guarantee for every OS/server combination.

Supported package families, in automatic selection order:

| Priority tier | Family (`--pg-family`) | Server package |
| --- | --- | --- |
| 1 | `postgrespro-ent` | `postgrespro-ent-N-server` |
| 1 | `tantor-se` | `tantor-se-server-N` |
| 2 | `tantor-be` | `tantor-be-server-N` |
| 3 | `tantor-free` | `tantor-free-server-N` |
| 3 | `postgresql` | `postgresql-N` |

`N` is the PostgreSQL major version. Within a tier, newer majors come first, followed by package-name ordering for ties. Tantor Free and vanilla PostgreSQL have equal priority. Legacy names `postgresql-N-server` and `tantor-free-server-N-server` are also accepted.

An explicit `--package` or an applicable installed server selected by the configuration takes precedence over automatic ranking. The main menu heading shows the selected package for **new clusters**, not a list of every installed server. Backup server identity is resolved from the existing cluster and its binaries.

Postgres Pro requires its matching `contrib` package. Client, development, extension, and unversioned `postgresql-contrib` metapackages are not treated as servers. Before installing server packages, the script simulates APT's transaction and refuses a plan that would remove installed packages.

## Quick start

Run these commands from a local checkout on the Linux host or from its WSL-mounted path. No downloaded DEB is required to run the source scripts.

### 1. Prepare a private configuration

Copy the supplied configuration, then review its locale, server family/version, names, and passwords before running a management command:

```bash
sudo install -d -m 0700 /etc/pgcc
sudo install -m 0600 ./.new-claster.config /etc/pgcc/site.config
sudoedit /etc/pgcc/site.config
```

The supplied credentials are examples, not production credentials. Configuration files are executed as Bash code: only use trusted files.

### 2. Open the management menu

```bash
sudo bash ./create-claster.sh --config /etc/pgcc/site.config
```

Choose **Install** (`Кластер: Установить`) to create a cluster, or select another operation. Startup may install missing prerequisites/server packages; starting the program is not a read-only health check.

### 3. Inspect the interfaces

```bash
bash ./create-claster.sh --help
bash ./create-claster-backup.sh --help
bash ./create-claster-deb.sh --help
bash ./create-claster.sh --version
```

Help and version requests do not require root privileges.

## Configuration

All three scripts select one configuration file in this order:

1. `--config FILE` (or `--config=FILE`).
2. Nonempty `PGCC_CFG`.
3. Existing `/usr/local/shared/pg_claster_creator/.new-claster.config`.
4. `.new-claster.config` beside the resolved script file.

Explicit relative paths are resolved from the invocation directory. An explicitly selected missing or unreadable file is an error, with no fallback. Reads and configuration saves use the same selected file.

For supported functional settings, precedence is **CLI > nonempty environment variable > configuration/default**. Help/version have no environment aliases. The complete per-script mapping appears in `--help`, the English headers, and the manual pages.

| Configuration field | Meaning |
| --- | --- |
| `LANG`, `LC_ALL` | Locale for PostgreSQL and supporting utilities. |
| `pg`, `pg_ver` | Default server family and PostgreSQL major version. |
| `cls_pt`, `cls_nm` | Default cluster port and cluster/initial database name. |
| `cls_ch` | Application schema and database owner role. |
| `cls_us`, `cls_pw` | Application login role and password used for application/owner roles. |
| `backup_dir` | Backup storage and backup/SQL search directory. |

The five `cls_*` defaults are preserved when the script saves server selection or backup-directory changes. Protect the configuration as a secret; the script sets its mode to `0600` when saving.

**`share` and `shared` are different paths:** a DEB installs scripts and its packaged configuration under `/usr/local/share/pg_claster_creator/`. The optional per-host override uses `/usr/local/shared/pg_claster_creator/` and is not created automatically.

## Usage and automation

### Interface coverage

| Operation | Interactive | CLI / environment |
| --- | --- | --- |
| Cluster information, creation, port/data changes, backup, restore, deletion | Yes | `--action` / `PGCC_ACTION`: `info`, `install`, `port`, `move-data`, `backup`, `restore`, `delete` |
| Start/stop and rename a cluster; execute SQL on an existing database | Yes | Menu only |
| Delete an individual database | Yes | Menu only; CLI `delete` deletes a cluster |
| Hot backup and retention through the wrapper | Backup runs without prompts | Positional target or environment target, plus options |
| Configure a backup cron job | Yes | `--cron` / `PGCC_CRON=yes` opens the scheduling dialog |
| Build DEB modes 1–5 | Yes | Use `--mode` and `--non-interactive` |

Selecting `--action` or `PGCC_ACTION` disables menus and confirmations. Missing required parameters cause an error; use explicit targets and review destructive options before automation.

### Cluster commands

The following examples assume an existing `16/demo` cluster and `demo` database; adjust the version, names, and paths to your host:

```bash
# List registered clusters (startup preparation still applies).
sudo bash ./create-claster.sh --config /etc/pgcc/site.config --action info

# Back up one database without stopping its cluster.
sudo bash ./create-claster.sh --config /etc/pgcc/site.config \
  --action backup 16 demo --backup-type hot --database demo

# Cold backup: requires a cluster stop during archiving.
sudo bash ./create-claster.sh --config /etc/pgcc/site.config \
  --action backup 16 demo --backup-type cold

# Change the port; this operation can interrupt service.
sudo bash ./create-claster.sh --config /etc/pgcc/site.config \
  --action port --pg-version 16 --cluster-name demo --port 5433
```

`--data-root /DATA` uses `/DATA/pg_N/CLUSTER` for creation or relocation. Non-interactive installation selects the next free port when the requested port is occupied and reports the actual port; do not assume the requested port was retained.

To execute SQL, open **Edit → Execute SQL** (`Изменить → Выполнить SQL`), select a running cluster and database, then choose a numbered `.sql` file or enter its path. Relative paths are searched from the invocation directory, then the backup directory. Only `y/Y` confirms execution. SQL runs as `postgres` with `psql -X` and `ON_ERROR_STOP`; this does not make an arbitrary script transactional. There is no `--action sql` or `PGCC_SQL_FILE` input in `create-claster.sh`.

### Backup retention and scheduling

```bash
# Keep the newest seven matching hot backups after successful backup creation.
sudo bash ./create-claster-backup.sh --config /etc/pgcc/site.config \
  --backup-dir /srv/pg-backups/demo --files-cnt 7 16 demo demo
```

Use `--files-size 10GiB` instead of `--files-cnt` to limit total size; the two options are mutually exclusive. Retention uses the strict major/database/timestamp filename pattern, not archive contents. Use separate directories for different clusters with identical database names. At least the newest matching backup is retained, even if it exceeds the size limit.

The positional `VERSION CLUSTER DATABASE` target can be replaced by `PGCC_PG_VERSION`, `PGCC_CLUSTER_NAME`, and `PGCC_DATABASE` together. `PGCC_FILES_CNT`, `PGCC_FILES_SIZE`, and `PGCC_BACKUP_DIR` mirror the retention/storage options. Add `--cron` to configure a job in `/etc/cron.d`; schedule selection remains interactive. A per-database lock prevents concurrent runs of the same task.

## Building Debian packages

Review the configuration before packaging: the **selected configuration is embedded in the DEB**. Do not accidentally distribute a production password or a private host configuration.

Build a scripts-only package from the checkout:

```bash
bash ./create-claster-deb.sh --config ./.new-claster.config \
  --mode 1 --non-interactive
```

The output is `dist/claster-creator-2.5.3.deb`. Generated `dist/` contents are ignored by Git. GitFlic CI checks and builds the package, retains it as a job artifact, and publishes DEB/checksum attachments for matching `vX.Y.Z` tags. See [CI and release builds](CI.md) for runner requirements and verification scope.

Install this scripts-only package on a host with the required repositories configured:

```bash
sudo apt install ./dist/claster-creator-2.5.3.deb
```

| Mode | Action when the package is installed |
| --- | --- |
| 1 | Install scripts, configuration, Markdown documentation, and manual pages. |
| 2 | Install the tools and create a cluster. |
| 3 | Install the tools and restore an embedded cold cluster backup. |
| 4 | Install the tools, create a cluster, and restore an embedded hot database dump. |
| 5 | Install the tools, create a cluster/database, and execute an embedded SQL file. |

Without a mode, the builder opens its menu. Modes 2–5 prompt by default; use `--non-interactive` for automation. Modes 3/4 require `--backup-file` of the matching type; mode 4 also requires `--database`. Mode 5 requires `--sql-file` / `PGCC_SQL_FILE` and `--database` / `PGCC_DATABASE`. Interactive file lists filter cold/hot backups by mode and offer `.sql` selection for mode 5. SQL must be self-contained: included external files are not packaged.

For automatic Postgres Pro selection in modes 4/5, `--pg-version` is a **minimum major**, with ordered contrib alternatives preferring 18, then 17, down to that minimum. Use `--package` to pin the server package name. Cold mode preserves the server package recorded in backup metadata.

`--output-dir` changes the destination; `--force` permits replacing an existing output DEB. Temporary build trees are cleaned on exit; a `tmp/` parent is removed only if this run created it and it is empty. Both DEB archives use gzip for older Astra `dpkg` compatibility.

Every mode installs all regular root-level `*.md` files, including both READMEs and the current journal, into `/usr/local/share/pg_claster_creator/`. Subdirectories such as `tests/` and symbolic links are excluded. Command links are installed for the main and backup scripts in `/usr/local/bin`; invoke the installed builder by its full path. English and Russian manual pages are installed under `/usr/share/man/`.

Deployment modes use progress/completion markers in `/var/lib/claster-creator`. Review the builder manual before retrying failed deployments. In particular, `CLASTER_FORCE_INSTALL=1` at package installation deletes the target cluster **without a backup** before redeployment; `CLASTER_FORCE_DB_INSTALL=1` overwrites only the target database and is supported in mode 4 only. The flags are mutually exclusive and are not build-time options. Failed mode-5 SQL is not replayed automatically because partial changes may already exist.

## Safety and operational limits

- Cold backups stop the cluster for archiving. An initially running cluster is restarted after success; an initially stopped cluster may be started temporarily to collect database metadata, then stopped again. Inspect state after failures.
- Rename, port/data changes, deletion, and vendor-service preparation can stop services. Stop requests are announced, including in unattended execution; announcements are not additional confirmation prompts.
- Rename preserves the original running state but does not rename databases, roles, or external cron jobs. Partial failure produces a recovery manifest, not an automatic rollback.
- Cluster deletion verifies the stopped state and removes validated cluster-specific configuration, data, and service paths without `pg_dropcluster`. External WAL/tablespace targets and shared or nonstandard files can remain with warnings.
- Hot backups may contain role password hashes. Protect backups, configuration files, embedded deployment data, and generated `create-claster-deb-last.sh` repeat-build commands. Environment passwords avoid command-line arguments but are not a secret store.
- Only restore trusted archives and execute trusted SQL. Cold restore resets `/var/log/postgresql` to `root:postgres` with mode `1775`; it does not reset existing log-file modes. WAL reset options are emergency operations with potential data loss, not routine backup maintenance.
- Allow enough disk space and downtime for physical backups and data relocation. Validate backups by restoring them on an isolated host before relying on them in production.

## WSL notes

Keep PGDATA and critical cluster directories on the Linux filesystem. A Windows mount such as `/mnt/d` may not enforce POSIX ownership or modes: use Windows access controls to protect stored archives. An unsupported mode change is not proof that permission checks passed; archive read/write failures remain errors.

The WSL-only syslog-ng compatibility path is intended for functional testing on WSL without `/dev/parsec`. It replaces only matching stock cluster snippets with unresolved Astra PostgreSQL parser references, preserves originals, and validates the replacement with rollback on failure. The replacement collects **raw log text, not structured Astra audit events**. Valid/custom configurations are preserved.

This path is inactive on ordinary physical or virtual Linux hosts. It does not change global PARSEC settings or reload/restart syslog-ng automatically, and it is not a fix for PID 1 crashes or package service hooks. See **WSL syslog-ng troubleshooting** in the main script header before applying any service changes.

## Documentation and testing

- [Russian README](README_ru.md) — technical translation of this guide.
- [CHANGELOG.md](CHANGELOG.md) — release history in English; [Russian original](CHANGELOG_ru.md).
- [TEST.md](TEST.md) — test preparation, full test plan, cleanup rules, and result criteria (Russian).
- [TEST-2.5.3-journal.md](TEST-2.5.3-journal.md) — latest recorded test run (Russian).
- English manuals: cluster management, backup wrapper, package builder.
- [tools/INDEX.md](tools/INDEX.md) — reusable helper catalog; check each helper's header and environment assumptions before use.

After DEB installation, use `man create-claster.sh`, `man create-claster-backup.sh`, or `man create-claster-deb.sh`. Russian pages can be selected with `LANG=ru_RU.UTF-8 man create-claster.sh` when that locale is available.

The recorded 2.5.3 run covers eight WSL distributions: 35 of 59 required test IDs were fully confirmed, and 24 still have untested mandatory variants. No product failures were found in executed checks; **this is not a full passed result**. See the journal for scope, reasons, and durations.

Full testing is destructive: the plan can delete clusters and remove/reinstall server packages. Use disposable, explicitly authorized environments; follow **Начало тестирования** in `TEST.md`, not a blanket test command. Historical local journals live in ignored `tests/` and are not shipped. A journal included in a package is evidence of its stated scope, not certification of every feature.

## Contributing and licensing

Keep shell files LF-terminated, preserve compatibility with the supported environments, and update both READMEs when user-facing behavior changes. Document CLI/environment changes in script headers, usage, manuals, and the test plan. Reuse helpers from `tools/INDEX.md` before adding new ones, and do not commit generated DEBs or private configurations.

When reporting a problem, include the script version, OS/server package versions, command or menu steps, expected/actual behavior, and sanitized logs. Remove credentials, password hashes, and application data.

Licensed under the MIT License. Copyright (c) 2026 Andrei Lesnykh.

Every DEB includes the license at `/usr/local/share/pg_claster_creator/LICENSE` and `/usr/share/doc/claster-creator/copyright`. Licenses for external PostgreSQL distributions and other dependencies remain their own.
