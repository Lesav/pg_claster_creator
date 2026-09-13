# GitFlic CI and release builds

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
   and 0755 permissions, all regular root Markdown files with 0644 permissions,
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
uses the automatically provided **CI_JOB_TOKEN**, not a runner registration
token or personal access token. It sends `Authorization: token ...` to the
same GitFlic origin's `/rest-api` (or `https://api.gitflic.ru` for gitflic.ru).
Do not print the environment or enable shell tracing around secrets. HTTP does
not encrypt tokens or artifacts; use HTTPS for deployments that provide it.

## Local check

```bash
bash tools/prx-ci-build.sh "$PWD"
```

This command builds but does not publish. Git and the repository config must be
available; `PGCC_CFG` from the host is intentionally not inherited by the build.

## Release procedure

### Current self-hosted verification status (2026-09-13)

The dedicated `a186-ci-cd` runner builds and uploads job artifacts successfully.
End-to-end automatic releases on `gf.icd.nikiet.ru` **are not yet operational**:

- A tag push does not automatically create a tag pipeline on the tested 4.5.0
  installation. Starting from the tag's UI works; REST pipeline start using
  `CI_JOB_TOKEN` returns 403. Do not grant broader token permissions implicitly.
- Release creation using `CI_JOB_TOKEN` returns 500 with
  `org.springframework.dao.InvalidDataAccessApiUsageException.type`; the exact
  server-side cause needs the administrator's logs.
- Release upload rejects the original DEB with 415 and explicitly identifies
  `application/x-debian-package` as unsupported. The administrator must review
  the allowed release file types; disguising the file or changing the client's
  declared Content-Type is not a fix.
- The original job artifact was downloaded and its DEB checksum verified against
  its SHA256SUMS, but **release attachment download verification is blocked**:
  there is no successfully uploaded release DEB yet.

See [runner setup and diagnostic evidence](tools/gitflic-ci-cd.md#7-теги-и-публикация-известные-ограничения).
The offline publisher tests run before CI builds; they do not replace this
integration check.

### Procedure after resolving the server blockers

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
