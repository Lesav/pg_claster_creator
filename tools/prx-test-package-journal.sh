#!/usr/bin/env bash
# Purpose: verify required release journal inclusion and missing-file failure.
# Usage: bash tools/prx-test-package-journal.sh REPO VERSION JOURNAL_VERSION LOG_DIR
# Args: LOG_DIR -- new private evidence/output directory; versions identify package and journal.
# Output: verified mode-1 package and logs, including missing-journal failures; no installation.
# Example: bash tools/prx-test-package-journal.sh /repo 2.4.0 2.1.2 /repo/tmp/package-qa
set -Eeuo pipefail
repo="$1"
release="$2"; journal="$3"; logs="$4"
[[ ! -e "$logs" ]]
mkdir -p "$logs"
exec >"$logs/check.log" 2>&1
date --iso-8601=seconds
work="$(mktemp -d /tmp/pgcc-journal-check.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
builder="$repo/create-claster-deb.sh"
bash -n "$builder"
DPKG_DEB_COMPRESSOR_TYPE=zstd bash "$builder" --mode 1 --non-interactive --output-dir "$logs/artifacts" </dev/null
package="$logs/artifacts/claster-creator-$release.deb"
member="./usr/local/share/pg_claster_creator/TEST-$journal-journal-passed.md"
[[ "$(ar t "$package")" == $'debian-binary\ncontrol.tar.gz\ndata.tar.gz' ]]
[[ "$(dpkg-deb -f "$package" Version)" == "$release" ]]
dpkg-deb -I "$package"
dpkg-deb -c "$package"
dpkg-deb --fsys-tarfile "$package" > "$work/payload.tar"
tar -xOf "$work/payload.tar" "$member" > "$work/journal.md"
cmp "$repo/TEST-$journal-journal-passed.md" "$work/journal.md"
for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh README.md TEST.md CHANGELOG.md; do
    tar -xOf "$work/payload.tar" "./usr/local/share/pg_claster_creator/$name" >"$work/extracted"
    cmp "$repo/$name" "$work/extracted"
done
[[ "$(tar -tf "$work/payload.tar" | grep -Ec '/man1/create-claster.*\.1\.gz$')" == 6 ]]
sha256sum "$package"
tar -tvf "$work/payload.tar" "$member" | tee "$work/entry"
grep -q '^-rw-r--r-- root/root ' "$work/entry"
printf 'PASS journal: expected path, identical bytes, root/root 0644\n'
# Load the unchanged build function from a directory without a journal.
sed '/^main "\$@"$/d' "$builder" > "$work/builder.sh"
for mode in 1 2 3 4 5; do
    if (source "$work/builder.sh"; MODE="$mode"; build_package) >"$work/error" 2>&1; then
        echo 'FAIL missing journal accepted'; exit 1
    fi
    grep -q "не найден журнал успешного тестирования версии $journal" "$work/error"
    cp "$work/error" "$logs/missing-journal-$mode.log"
    printf 'PASS mode %s: missing required historical journal refused\n' "$mode"
done
date --iso-8601=seconds
printf 'PASS package/journal/gzip checks\n'
