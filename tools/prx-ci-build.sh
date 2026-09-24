#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Purpose: Run non-destructive syntax and scripts-only DEB checks in CI or locally.
# Usage: bash tools/prx-ci-build.sh [REPO]
# Args: REPO defaults to the parent of this helper after installation in tools.
# Output: dist/claster-creator-VERSION.deb, claster-creator-VERSION.sha256,
#   SHA256SUMS (compatibility copy), package-contents.txt, build.log.
# Environment: CI_COMMIT_TAG, when set, must equal vVERSION. No host PGCC_* is used.
# Example: bash tools/prx-ci-build.sh "$PWD"  # never installs the package
set -Eeuo pipefail
repo=$(realpath -e -- "${1:-$(dirname -- "${BASH_SOURCE[0]}")/..}")
cd "$repo"
for command in git bash python3 fakeroot dpkg-deb ar tar gzip sha256sum; do
    command -v "$command" >/dev/null || { echo "Missing build dependency: $command" >&2; exit 1; }
done
[[ -z $(git ls-files -- dist) ]] || { echo 'dist must not be tracked' >&2; exit 1; }
version=$(sed -n 's/^readonly SCRIPT_VERSION="\([0-9]*\.[0-9]*\.[0-9]*\)"$/\1/p' create-claster.sh)
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ -z ${CI_COMMIT_TAG:-} || ${CI_COMMIT_TAG} == "v$version" ]] || {
    echo "Tag ${CI_COMMIT_TAG} does not match script version $version" >&2; exit 1;
}
while IFS= read -r -d '' script; do
    bash -n "$script"
done < <(git ls-files -z -- '*.sh')
echo 'PASS: all tracked Bash files pass syntax checks'
mkdir -p dist
# A clean environment prevents local deployment settings entering release packages.
env -i PATH="$PATH" HOME="$HOME" LANG=C.UTF-8 \
    bash tools/prx-build-release-local.sh "$repo" "$version" '' '' "$repo/.new-claster.config" \
    2>&1 | tee dist/build.log
package="dist/claster-creator-$version.deb"
[[ $(dpkg-deb -f "$package" Package) == claster-creator ]]
dpkg-deb --contents "$package" > dist/package-contents.txt
(cd dist && sha256sum "claster-creator-$version.deb" > "claster-creator-$version.sha256" &&
    cp -- "claster-creator-$version.sha256" SHA256SUMS &&
    sha256sum -c "claster-creator-$version.sha256")
git check-ignore -q "$package"
[[ -z $(git ls-files -- dist) ]]
echo "PASS: $package is verified and remains outside Git"
