#!/usr/bin/env bash
# Purpose: stage a release on Linux FS to avoid DrvFS package ownership/mode issues.
# Usage: bash tools/prx-build-release-local.sh REPO VERSION JOURNAL_VERSION
# Args: REPO -- source directory; VERSION -- release; JOURNAL_VERSION -- evidence version.
# Output: verified gzip-only DEB in REPO/dist; no package installation.
# Example: bash tools/prx-build-release-local.sh /mnt/d/Ai/pg_claster_creator 2.2.0 2.1.2
set -Eeuo pipefail
repo="$1"; version="$2"; journal_version="$3"
stage="$(mktemp -d /tmp/pgcc-release.XXXXXX)"
trap 'rm -rf -- "$stage"' EXIT
for f in create-claster.sh create-claster-backup.sh create-claster-deb.sh .new-claster.config README.md TEST.md CHANGELOG.md "TEST-$journal_version-journal-passed.md"; do
    cp -- "$repo/$f" "$stage/$f"
done
cp -R -- "$repo/man" "$stage/man"
# Refuse an unexpected external config in the build environment.
[[ ! -e /usr/local/shared/pg_claster_creator/.new-claster.config ]]
for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh; do
    bash -n "$stage/$name"
    bash "$stage/$name" --version | grep -F "$version"
    bash "$stage/$name" --help >/dev/null
done
bash "$stage/create-claster-deb.sh" --mode 1 --non-interactive --output-dir "$repo/dist" --force
[[ ! -e "$stage/tmp" ]]
package="$repo/dist/claster-creator-$version.deb"
[[ "$(ar t "$package")" == $'debian-binary\ncontrol.tar.gz\ndata.tar.gz' ]]
[[ "$(dpkg-deb -f "$package" Version)" == "$version" ]]
dpkg-deb --fsys-tarfile "$package" > "$stage/payload.tar"
member="./usr/local/share/pg_claster_creator/TEST-$journal_version-journal-passed.md"
tar -xOf "$stage/payload.tar" "$member" > "$stage/extracted-journal"
cmp "$stage/extracted-journal" "$repo/TEST-$journal_version-journal-passed.md"
tar -tvf "$stage/payload.tar" "$member" | tee "$stage/entry"
grep -q '^-rw-r--r-- root/root ' "$stage/entry"
tar -xOf "$stage/payload.tar" ./usr/local/share/pg_claster_creator/.new-claster.config > "$stage/extracted-config"
cmp "$stage/extracted-config" "$repo/.new-claster.config"
for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh README.md TEST.md CHANGELOG.md; do
    tar -xOf "$stage/payload.tar" "./usr/local/share/pg_claster_creator/$name" > "$stage/extracted-file"
    cmp "$stage/extracted-file" "$repo/$name"
done
sed '/^main "\$@"$/d' "$stage/create-claster-deb.sh" > "$stage/check-builder.sh"
mv "$stage/TEST-$journal_version-journal-passed.md" "$stage/journal-hidden"
for mode in 1 2 3 4; do
    if (source "$stage/check-builder.sh"; MODE="$mode"; build_package) > "$stage/error" 2>&1; then exit 1; fi
    grep -q 'не найден журнал успешного тестирования' "$stage/error"
done
echo 'PASS: tmp cleanup, gzip control/data, version, help, syntax, journal bytes/path/0644, source config/scripts/docs, missing-journal rejection'
