#!/usr/bin/env bash
# Purpose: verify all root Markdown is packaged and archived journals are excluded.
#   Also verify both MIT license copies and reject builds without LICENSE.
# Usage: bash tools/prx-test-package-journal.sh REPO VERSION LEGACY_JOURNAL LOG_DIR
# Args: REPO -- source root; VERSION -- expected version; LEGACY_JOURNAL -- ignored;
#   LOG_DIR -- new evidence/output directory. Run on Linux as root or with fakeroot.
# Output: mode1 real build and modes2-5 documentation-only fixtures, logs and DEBs;
#   no installation or cluster changes. Deployment hooks are stubbed in modes2-5.
# Example: bash tools/prx-test-package-journal.sh /repo 2.5.1 unused /repo/tmp/markdown-qa
set -Eeuo pipefail
repo="$(realpath "$1")"; release="$2"; logs="$4"
[[ ! -e "$logs" ]]; mkdir -p "$logs"; logs="$(realpath "$logs")"
exec >"$logs/check.log" 2>&1
work="$(mktemp -d /tmp/pgcc-journal-check.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
stage="$work/source"; mkdir "$stage"
cp "$repo"/create-claster*.sh "$repo/.new-claster.config" "$repo/LICENSE" "$stage/"
export PGCC_CFG="$stage/.new-claster.config"
cp -R "$repo/man" "$stage/man"
while IFS= read -r -d '' document; do
    cp -- "$document" "$stage/${document##*/}"
done < <(find "$repo" -maxdepth 1 -type f -name '*.md' -print0)
printf 'hidden root document\n' >"$stage/.hidden.md"
printf 'root document with spaces\n' >"$stage/notes with spaces.md"
mkdir "$stage/tests" "$stage/not-a-file.md"
printf 'archived journal must not enter DEB\n' >"$stage/tests/TEST-old-journal-passed.md"
printf 'nested document must not enter DEB\n' >"$stage/not-a-file.md/nested.md"
ln -s tests/TEST-old-journal-passed.md "$stage/archive-link.md"

verify_package() {
    local package="$1" document member expected=0 actual
    [[ "$(ar t "$package")" == $'debian-binary\ncontrol.tar.gz\ndata.tar.gz' ]]
    [[ "$(dpkg-deb -f "$package" Version)" == "$release" ]]
    dpkg-deb --fsys-tarfile "$package" >"$work/payload.tar"
    tar -tf "$work/payload.tar" >"$work/manifest"
    for member in ./usr/local/share/pg_claster_creator/LICENSE ./usr/share/doc/claster-creator/copyright; do
        tar -xOf "$work/payload.tar" "$member" >"$work/extracted"
        cmp "$stage/LICENSE" "$work/extracted"
        tar -tvf "$work/payload.tar" "$member" >"$work/entry"
        grep -q '^-rw-r--r-- root/root ' "$work/entry"
    done
    while IFS= read -r -d '' document; do
        member="./usr/local/share/pg_claster_creator/${document##*/}"
        tar -xOf "$work/payload.tar" "$member" >"$work/extracted"
        cmp "$document" "$work/extracted"
        tar -tvf "$work/payload.tar" "$member" >"$work/entry"
        grep -q '^-rw-r--r-- root/root ' "$work/entry"
        expected=$((expected + 1))
    done < <(find "$stage" -maxdepth 1 -type f -name '*.md' -print0)
    actual="$(grep -Ec '^\./usr/local/share/pg_claster_creator/[^/]+\.md$' "$work/manifest")"
    [[ "$actual" == "$expected" ]]
    ! grep -Eq '/tests/|archive-link\.md|not-a-file\.md|TEST-old-journal' "$work/manifest"
    [[ "$(grep -Ec '/man1/create-claster.*\.1\.gz$' "$work/manifest")" == 6 ]]
    printf 'PASS %s: %s root Markdown files, identical bytes, root/root 0644, gzip; archives/links/nested files excluded\n' "${package##*/}" "$expected"
}

bash -n "$stage/create-claster-deb.sh"
DPKG_DEB_COMPRESSOR_TYPE=zstd bash "$stage/create-claster-deb.sh" --mode 1 --non-interactive --output-dir "$logs/artifacts" </dev/null
verify_package "$logs/artifacts/claster-creator-$release.deb"
[[ ! -e "$stage/tmp" ]]

# Exercise the shared build path in every other mode without restoring a DB.
sed '/^main "\$@"$/d' "$stage/create-claster-deb.sh" >"$stage/builder-fixture.sh"
for mode in 2 3 4 5; do
    (
        source "$stage/builder-fixture.sh"
        load_defaults
        MODE="$mode"; DATABASE_NAME=qa; OUTPUT_DIR="$logs/artifacts"
        mkdir -p "$TMP_DIR"; TMP_DIR_CREATED=1
        package_basename() { printf 'markdown-mode-%s' "$MODE"; }
        dependency_list() { printf 'postgresql-common'; }
        create_install_plan() { :; }
        create_postinst() { printf '#!/bin/sh\nexit 0\n' >"$1"; chmod 0755 "$1"; }
        build_package
    )
    verify_package "$logs/artifacts/markdown-mode-$mode.deb"
    [[ ! -e "$stage/tmp" ]]
done

# A missing source license must prevent packaging, including in scripts-only mode.
mv "$stage/LICENSE" "$work/LICENSE.saved"
if bash "$stage/create-claster-deb.sh" --mode 1 --non-interactive --output-dir "$logs/missing-license" >"$work/missing-license.log" 2>&1; then
    printf 'FAIL: build succeeded without LICENSE\n'; exit 1
fi
grep -Fq 'не найден или недоступен файл лицензии' "$work/missing-license.log"
[[ ! -e "$logs/missing-license/claster-creator-$release.deb" && ! -e "$stage/tmp" ]]
printf 'PASS: missing LICENSE rejected; no package or temporary build tree left\n'
printf 'PASS Markdown packaging modes 1-5; no historical passed journal required\n'
