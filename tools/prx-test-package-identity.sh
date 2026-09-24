#!/usr/bin/env bash
# Usage: bash tools/prx-test-package-identity.sh REPO
# Isolated package matching checks; dpkg-query is mocked, no package changes.
set -Eeuo pipefail
source "$1/tools/prx-package-identity.sh"
fixture_inventory=$'libs\tamd64\tinstalled\nother\tamd64\tinstalled'
dpkg-query() { printf '%s\n' "$fixture_inventory"; }
approved_removal libs:amd64 libs:amd64
approved_removal libs libs:amd64
approved_removal libs:amd64 libs
if approved_removal libs libs:i386; then exit 1; fi
if approved_removal other libs:amd64; then exit 1; fi
fixture_inventory+=$'\nlibs\ti386\tinstalled'
if approved_removal libs libs:amd64 libs:i386; then exit 1; fi
if approved_removal libs:i386 libs; then exit 1; fi
approved_removal libs:i386 libs:i386
fixture_inventory=$'libs\tamd64\tconfig-files'
if approved_removal libs libs:amd64; then exit 1; fi
dpkg-query() { return 1; }
if approved_removal libs libs:amd64; then exit 1; fi
approved_removal libs:amd64 libs:amd64
printf 'PASS exact names, architecture aliases, wrong architecture, unknown/ambiguous/removed packages and query failure\n'
