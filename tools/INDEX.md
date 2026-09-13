prx-test-postgres-backups.sh — create and inspect hot/cold PostgreSQL backups
prx-test-postgres-port-data.sh — test PostgreSQL port switching and data relocation
prx-test-tantor-editions.sh — test Tantor edition and physical backup version selection
prx-build-release-local.sh — build and verify a release DEB on a Linux filesystem
prx-ci-build.sh — run non-destructive CI syntax, DEB content and artifact checks
prx-publish-gitflic-release.py — publish tag releases with verified attachments using GITFLIC_RELEASE_TOKEN
prx-test-gitflic-publisher.py — test release publishing guards and sanitized HTTP diagnostics offline
prx-install-release-wsl.sh — install a scripts-only release and verify cluster/config preservation
prx-test-deb-tmp-cleanup.sh — test builder temporary directory ownership and cleanup
prx-test-wsl-preflight.sh — collect WSL baseline and test informational CLI and man
prx-check-server-minor.sh — record installed servers, check repository minor versions and simulate package removal
prx-remove-wsl-postgres-packages.sh — remove a reviewed package set on empty WSL with offline service handling and evidence
prx-test-config-priority.sh — test config priority and save isolation with fixtures
prx-test-cluster-identity.sh — test major/name cluster identity and registry failure guards
prx-prepare-postgres-test-data.sh — populate a disposable PostgreSQL database with control objects
prx-test-cluster-power.sh — test state-based interactive cluster start/stop
prx-test-cluster-rename.sh — test native-like rename, prefix paths, autostart and failure guards
prx-test-cluster-delete.sh — test direct cluster deletion and safe refusal boundaries
prx-test-edit-menu.sh — test main/edit menu navigation and dispatch
prx-test-live-regression.sh — run isolated live backup/restore and DEB regression phases
prx-test-live-extra.sh — extend live regression with refusals, rotation and force installs
prx-test-live-ports.sh — test deployment port conflicts and stale markers
prx-test-release-fixtures.sh — run isolated release regression helpers with separate evidence
prx-test-backup-guards.sh — test backup errors, external flock and all cron schedule choices
prx-audit-live-regression.sh — archive owned test markers and verify final WSL baseline
prx-test-package-journal.sh — verify root Markdown inclusion and archived journal exclusion in DEB modes 1–5
prx-test-cluster-delete-live.sh — test live deletion with optional prefix/reverse rename regression
prx-test-live-ui.sh — test real rename, ENV, generated cron commands and database deletion
prx-test-full-contracts.sh — test argument, dependency and size contracts without changing services
prx-test-live-edges.sh — test restore edge cases with archive and parent metadata checks
prx-test-screen-log-permissions.py — test TTY output, cold log permissions and legacy archive metadata
prx-test-deb-sql.sh — test mode-5 selection, payload, deployment guards and optional real SQL
prx-test-menu-sql.sh — test interactive SQL navigation, confirmation and target guards
prx-run-wsl-phases.sh — run sequential regression phases in an isolated per-WSL run
prx-clean-wsl-regression.sh — clean validated run artifacts and verify the WSL baseline
prx-test-live-install.sh — test real interactive default/custom cluster creation
prx-bootstrap-wsl-postgres.sh — remove reviewed server packages and test workspace bootstrap
prx-test-wsl-fixtures.sh — run isolated full-plan fixture suites per WSL
prx-test-wsl-dependencies.sh — test real APT and dpkg dependency installation
prx-test-live-sql.sh — exercise live SQL menu and mode-5 package deployment
prx-test-wsl-stand.sh — run one WSL test chain with final cleanup and timing
prx-test-wsl-syslog.sh — test guarded WSL syslog repair, parser checks and rollback in isolation
prx-verify-wsl-test-cleanup.sh — verify final registry, processes and removal of run artifacts
prx-test-live-config-env.sh — verify live config propagation, cron and fresh DEB data roots
prx-run-live-config-env.sh — run isolated live config checks with timing and cleanup
