#!/usr/bin/env bash
# Path note: If /mnt/d/Ai/pg_claster_creator in the example does not match
# your filesystem, replace it with the actual project path before running.
# Purpose: stage a release on Linux FS to avoid DrvFS package ownership/mode issues.
# Usage: bash tools/prx-build-release-local.sh REPO VERSION [LEGACY_JOURNAL [BASELINE_VERSION [CONFIG_FILE]]]
# Args: REPO -- source directory; VERSION -- release; LEGACY_JOURNAL -- ignored compatibility slot.
#   BASELINE_VERSION -- optional local DEB whose shell logic must remain unchanged.
#   CONFIG_FILE -- optional distribution config; overrides PGCC_CFG.
# Environment: PGCC_CFG selects a distribution config when CONFIG_FILE is omitted;
#   otherwise use REPO/.new-claster.config. Relative paths use the invocation cwd.
#   The selected file is copied to staging and passed explicitly to the builder,
#   so a system config cannot replace the distribution config.
# Output: verified gzip-only DEB in REPO/dist; no package installation.
#   Verifies only the four README/CHANGELOG files and latest available passed journal.
#   Requires REPO/LICENSE; verifies both installed license copies and mode 0644.
# Example: bash tools/prx-build-release-local.sh /mnt/d/Ai/pg_claster_creator 2.2.0 2.1.2
set -Eeuo pipefail
repo="$1"; version="$2"
baseline_version="${4:-}"
config_source="${5:-${PGCC_CFG:-$repo/.new-claster.config}}"
config_source="$(realpath -e -- "$config_source")"
[[ -f "$config_source" && -r "$config_source" ]]
stage="$(mktemp -d /tmp/pgcc-release.XXXXXX)"
trap 'rm -rf -- "$stage"' EXIT
for f in create-claster.sh create-claster-backup.sh create-claster-deb.sh; do
    # Git checkouts may contain mode 0644; the builder re-executes itself via fakeroot.
    install -m 0755 -- "$repo/$f" "$stage/$f"
done
cp -- "$repo/LICENSE" "$stage/LICENSE"
while IFS= read -r -d '' document; do
    cp -- "$document" "$stage/${document##*/}"
done < <(find "$repo" -maxdepth 1 -type f -name '*.md' -print0)
cp -- "$config_source" "$stage/.new-claster.config"
cp -R -- "$repo/man" "$stage/man"
if [[ -n "$baseline_version" ]]; then
    dpkg-deb -x "$repo/dist/claster-creator-$baseline_version.deb" "$stage/baseline"
    for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh; do
        # Ignore only comments and the release constant, not executable logic.
        sed '/^#/d; /^readonly SCRIPT_VERSION=/d' "$stage/$name" >"$stage/current-code"
        sed '/^#/d; /^readonly SCRIPT_VERSION=/d' "$stage/baseline/usr/local/share/pg_claster_creator/$name" >"$stage/baseline-code"
        cmp "$stage/current-code" "$stage/baseline-code"
        printf 'PASS: unchanged logic against %s: %s\n' "$baseline_version" "$name"
    done
fi
# Always build from the staged distribution config, not the host's defaults.
for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh; do
    bash -n "$stage/$name"
    bash "$stage/$name" --version | grep -F "$version"
    bash "$stage/$name" --help >/dev/null
done
bash "$stage/create-claster-deb.sh" --config "$stage/.new-claster.config" --mode 1 --non-interactive --output-dir "$repo/dist" --force
[[ ! -e "$stage/tmp" ]]
package="$repo/dist/claster-creator-$version.deb"
[[ "$(ar t "$package")" == $'debian-binary\ncontrol.tar.gz\ndata.tar.gz' ]]
[[ "$(dpkg-deb -f "$package" Version)" == "$version" ]]
dpkg-deb --fsys-tarfile "$package" > "$stage/payload.tar"
for member in ./usr/local/share/pg_claster_creator/LICENSE ./usr/share/doc/claster-creator/copyright; do
    tar -xOf "$stage/payload.tar" "$member" | cmp - "$repo/LICENSE"
    tar -tvf "$stage/payload.tar" "$member" | grep -q '^-rw-r--r-- root/root '
done
markdown=(README.md README_ru.md CHANGELOG.md CHANGELOG_ru.md)
latest="$(find "$repo" -maxdepth 1 -type f -name 'TEST-*-journal-passed.md' -printf '%f\n' | grep -E '^TEST-[0-9]+\.[0-9]+\.[0-9]+-journal-passed\.md$' | LC_ALL=C sort -V | tail -n 1 || true)"
[[ -z "$latest" ]] || markdown+=("$latest")
expected_markdown=0
for name in "${markdown[@]}"; do
    document="$repo/$name"
    [[ -f "$document" && ! -L "$document" ]] || continue
    expected_markdown=$((expected_markdown + 1))
    member="./usr/local/share/pg_claster_creator/${document##*/}"
    tar -xOf "$stage/payload.tar" "$member" > "$stage/extracted-markdown"
    cmp "$stage/extracted-markdown" "$document"
    tar -tvf "$stage/payload.tar" "$member" | tee "$stage/entry"
    grep -q '^-rw-r--r-- root/root ' "$stage/entry"
done
tar -tf "$stage/payload.tar" > "$stage/payload.list"
[[ "$(grep -Ec '^\./usr/local/share/pg_claster_creator/[^/]+\.md$' "$stage/payload.list")" == "$expected_markdown" ]]
! grep -q '/tests/' "$stage/payload.list"
tar -xOf "$stage/payload.tar" ./usr/local/share/pg_claster_creator/.new-claster.config > "$stage/extracted-config"
cmp "$stage/extracted-config" "$config_source"
for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh; do
    tar -xOf "$stage/payload.tar" "./usr/local/share/pg_claster_creator/$name" > "$stage/extracted-file"
    cmp "$stage/extracted-file" "$repo/$name"
    tar -tvf "$stage/payload.tar" "./usr/local/share/pg_claster_creator/$name" | grep -q '^-rwxr-xr-x root/root '
done
for language in en ru; do
    for name in create-claster.sh create-claster-backup.sh create-claster-deb.sh; do
        man_prefix=./usr/share/man
        [[ $language != ru ]] || man_prefix+=/ru
        tar -xOf "$stage/payload.tar" "$man_prefix/man1/$name.1.gz" | gzip -dc > "$stage/extracted-man"
        cmp "$stage/extracted-man" "$repo/man/$language/man1/$name.1"
    done
done
! grep -Eq '/(tests|tools|tmp|dist|\.git)/' "$stage/payload.list"
echo 'PASS: tmp cleanup, gzip control/data, version, help, syntax, allowed Markdown bytes/path/0644, source config/scripts/0755, six manuals, development documents excluded'
