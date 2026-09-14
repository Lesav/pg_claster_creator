# CI and release builds

## GitHub Actions

For release **2.5.6**, the local build, eight-WSL regression
and 31 offline publisher tests have run after separate approval; see
[the journal](TEST-2.5.6-journal-passed.md) for the documented coverage gaps.
The successful GitHub branch run for commit `08c77ab` verified the preceding
CI setup. Publish reviewed release commits by fast-forwarding the default branch
and `release/2.x`, then creating a new annotated version tag. Keep `release/1.x`
on its latest 1.x release and preserve every existing tag. Branch pushes also
start CI; version tags enable release publication. Publication of 2.5.6 on GitHub
and the internal GitFlic is verified separately from the historical WSL journal.

`.github/workflows/deb-release.yml` runs on GitHub-hosted Ubuntu 24.04:

- Pushes to `master` / `release/**` and pull requests run offline publisher tests,
  Bash syntax checks and the existing scripts-only DEB build/content verification.
- Pushing a new `vX.Y.Z` tag also publishes the DEB and `SHA256SUMS` to GitHub Releases.
  The tag must match the script version and the exact build commit on GitHub.
- **Actions → DEB build and release → Run workflow** builds a selected branch
  without publishing. A dispatch explicitly targeting a tag publishes only when
  that tag already contains this workflow and the publisher helpers.
- Build outputs, `build.log` and `package-contents.txt` are retained as artifacts
  for 30 days. Release attachments have independent retention; `dist/` stays out of Git.

No self-hosted runner or personal token is required. Only the publish job receives
`contents: write`, with the job's automatic `GITHUB_TOKEN` passed as `GH_TOKEN`.
Build/PR jobs have `contents: read`; checkout credentials are not persisted.
Actions are pinned to full commit SHAs. There is no `pull_request_target` or
execution of cluster tests. Sudo only installs packaging dependencies in the
disposable GitHub-hosted VM; the generated DEB is never installed.

The GitHub publisher reuses the existing changelog extractor. It verifies the
manifest, resolves the remote tag commit, preserves existing release descriptions,
refuses existing drafts/prereleases and checks all name collisions before upload.
Equal assets are reused; different assets fail without deletion or `--clobber`.
Every uploaded/reused asset is downloaded and compared by SHA-256. Retrying the
publish job uses the same retained build artifact; rerunning the full build may
produce different archive timestamps and therefore a checksum conflict. Do not
overwrite an existing release to address that conflict.

The manually created GitHub `v2.5.5` release and its `.deb` / `.sha256` attachments
are left unchanged. Old tags do not gain a workflow retroactively. Publish the
next reviewed version with a new tag; never move `v2.5.5` to add CI.

Offline GitHub publisher checks:

```bash
python3 -B tools/prx-test-github-publisher.py
```

## GitFlic CI

The root `gitflic-ci.yaml` targets GitFlic / Runner 4.5.0 and a **Shell** runner
with the `pgcc-deb` tag. Jobs without tags should be disabled for this runner.
Use a dedicated unprivileged build account and Linux filesystem. Do not run the
destructive WSL test plan on the build runner.

## Requirements

Install Bash, Git, Python 3, `fakeroot`, `dpkg-deb`, `ar` (binutils), GNU tar,
gzip, coreutils and findutils. CI does not install dependencies or use sudo.
The runner also needs its vendor-matched Java runtime, `helper.jar` and
`helper.sh`, plus network access to the GitFlic web/API endpoints.

## Pipeline

1. `build-deb` checks every tracked Bash file with `bash -n` and builds mode 1
   using the existing `prx-build-release-local.sh`. It verifies version/help,
   gzip control/data archives, the tracked distribution config, script contents
   and 0755 permissions, allowlisted Markdown (README/CHANGELOG in both languages
   and the latest available passed journal) with 0644 permissions; no CI.md/TEST.md,
   both license copies, and six English/Russian manual pages. Development
   directories must not enter the package. No DEB is installed and no cluster
   operation is executed.
2. `dist/` is uploaded as a job artifact (30-day retention). It contains the DEB,
   `SHA256SUMS`, `package-contents.txt` and `build.log`. These files stay ignored
   by Git. A clean environment prevents host `PGCC_*` values entering packages.
3. Only tags matching `vX.Y.Z` run `publish-release` after the successful build.
   The tag must match the script version. The publisher creates a release from
   that version's English changelog entry, checks its commit, uploads the DEB
   and checksums, then downloads attachments again to verify SHA-256.

Release attachments are independent of expiring job artifacts. The publisher
requires **GITFLIC_RELEASE_TOKEN**, a user API token supplied as a secret project
CI variable. It never uses, changes or falls back to **CI_JOB_TOKEN**, which
remains runner-managed. Missing/invalid release credentials stop publication
before any API request. It sends `Authorization: token ...` to the
same GitFlic origin's `/rest-api` (or `https://api.gitflic.ru` for gitflic.ru).
Do not print the environment or enable shell tracing around secrets. HTTP does
not encrypt tokens or artifacts; use HTTPS for deployments that provide it.

### Configure release credentials

Create a user API token with project read/write scopes. The user must have
`MANAGE_RELEASE` permission for publication and `EXECUTE_CI_CD` for explicit
pipeline starts. Prefer a dedicated service account with access only to the
intended project and an expiring token. In the project's CI variable settings,
add `GITFLIC_RELEASE_TOKEN` as a secret/masked variable; enter its value only
in the GitFlic UI, never in YAML, command arguments, Git or artifacts.
Restrict secret availability to trusted release refs/jobs using the controls
supported by the installation. Masking alone does not prevent untrusted job
code from reading a secret; do not expose it to untrusted branches or forks.
The build and offline publisher tests need no release token. Do not put an
empty placeholder variable in YAML that could override the configured secret.

Existing tags keep their old publisher code: restarting `v2.5.4` does not pick
up this change. Commit and review the update before testing a new release;
do not move an existing release tag just to test authentication.

## Local check

```bash
bash tools/prx-ci-build.sh "$PWD"
```

This command builds but does not publish. Git and the repository config must be
available; `PGCC_CFG` from the host is intentionally not inherited by the build.

## Release procedure

### Current self-hosted verification status (2026-09-14)

CI publication is verified in the temporary project: pipeline **18**, build job
**23**, publication job **27**. The fixed publisher used GITFLIC_RELEASE_TOKEN,
uploaded the DEB built from the original v2.5.4 commit and SHA256SUMS, downloaded
both, and verified their hashes. The user independently downloaded and checked
the files. The temporary recovery branch is not part of the main pipeline.

The production GitFlic server uses a separately patched 4.5.0 image that accepts
DEB and strictly validated SHA256SUMS uploads. This package does not patch GitFlic.
Stock 4.5.0 rejects these uploads (415); its job-token release creation fails
with a null author ID (500). Keep user-token authorization separate from CI_JOB_TOKEN.

Tag-push auto-triggering is **not confirmed** on this installation. If no tag
pipeline appears, use **CI/CD → Create pipeline → Select tag** and choose the
exact release tag. Do not substitute CI_COMMIT_TAG in a branch pipeline.
A successful manual tag start is not proof of automatic triggering on push.

See [runner setup and evidence](tools/gitflic-ci-cd.md#7-теги-и-публикация-известные-ограничения).

### Release steps

1. Update the three script versions, six man-page headers, README examples and
   changelogs. Preserve old journal filenames and their actual test scope.
2. Commit reviewed source changes. Keep `master` and the relevant `release/X.x`
   branch on the intended latest release commit.
3. Create an annotated tag `vX.Y.Z` on that commit and push it explicitly to the
   intended project. Never publish all historical tags as a CI smoke test.
4. Check the build and publication jobs, retained artifact, release attachments
   and checksums. A successful packaging pipeline is not a full cluster test.

On retry, matching release attachments are reused and downloaded for verification.
A mismatched existing commit/file stops publication without deleting or replacing
anything. A failed upload can leave a partial release; retry the same successful
build's publication job, not a newly rebuilt package with different bytes.

For migration, first test in a private temporary GitFlic project. Register a
project-scoped runner for it; do not replace the production repository or move
old release tags as part of CI verification.
