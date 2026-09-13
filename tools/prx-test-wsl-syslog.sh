#!/usr/bin/env bash
# Purpose: isolated WSL syslog repair regression; never reloads real services.
# Usage: bash tools/prx-test-wsl-syslog.sh REPO
# Args: REPO contains the working create-claster.sh.
# Output: PASS assertions; temporary fixture is removed on exit.
# Example: bash tools/prx-test-wsl-syslog.sh /mnt/d/Ai/pg_claster_creator
# Adjust the example path if the repository is mounted elsewhere.
set -Eeuo pipefail
repo="$1"
source "$repo/create-claster.sh"
trap - ERR
fixture=$(mktemp -d /tmp/pgcc-syslog-test.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
mkdir "$fixture/conf"
conf="$fixture/conf/mod-astra-postgres-17-qa.conf"
stock() { render_stock_cluster_syslog 17 qa /qa/data >"$conf"; cp "$conf" "$fixture/original"; }
wsl_syslog_config_dir() { echo "$fixture/conf"; }
is_wsl_without_parsec() { [[ "$platform" == wsl ]]; }
timeout() { shift 3; "$@"; }
syslog-ng() {
    local expanded=""
    for arg in "$@"; do [[ "$arg" != --preprocess-into=* ]] || expanded="${arg#*=}"; done
    [[ -n "$expanded" ]]
    cp "$conf" "$expanded"
    if [[ "$validation" == valid ]]; then
        printf '\nparser pg17_kv_parser { kv-parser(); };\nparser pg17_audit_parser { kv-parser(); };\n' >>"$expanded"
    fi
    if [[ "$validation" == fail ]] && ! grep -q 'parser(pg17_' "$conf"; then return 1; fi
    return 0
}
platform=native; validation=missing; stock
repair_wsl_cluster_syslog 17 qa /qa/data /qa/server.log
cmp "$conf" "$fixture/original"; echo 'PASS non-WSL unchanged'
platform=wsl; validation=valid
repair_wsl_cluster_syslog 17 qa /qa/data /qa/server.log
cmp "$conf" "$fixture/original"; echo 'PASS valid Astra parsers preserved'
validation=missing
echo '# custom' >>"$conf"; cp "$conf" "$fixture/custom"
repair_wsl_cluster_syslog 17 qa /qa/data /qa/server.log
cmp "$conf" "$fixture/custom"; echo 'PASS custom config preserved'
stock
repair_wsl_cluster_syslog 17 qa /qa/data /qa/server.log
grep -qxF '# PGCC WSL raw PostgreSQL log v1' "$conf"
grep -qF 'file("/qa/server.log"' "$conf"
grep -qF '${MESSAGE}\n' "$conf"
[[ $(find "$fixture/conf" -name '*.bak' | wc -l) == 1 ]]
cmp "$fixture/original" "$(find "$fixture/conf" -name '*.bak')"
echo 'PASS missing parser repaired, raw source and original backup'
repair_wsl_cluster_syslog 17 qa /qa/data /qa/server.log
[[ $(find "$fixture/conf" -name '*.bak' | wc -l) == 1 ]]; echo 'PASS idempotent'
repair_wsl_cluster_syslog 17 qa /qa/data /qa/changed.log
grep -qF 'file("/qa/changed.log"' "$conf"; echo 'PASS owned path refreshed'
echo '# user change' >>"$conf"; cp "$conf" "$fixture/custom-owned"
repair_wsl_cluster_syslog 17 qa /qa/data /qa/new.log
cmp "$conf" "$fixture/custom-owned"; echo 'PASS edited owned file preserved'
stock; validation=fail
if repair_wsl_cluster_syslog 17 qa /qa/data /qa/server.log; then exit 1; fi
cmp "$conf" "$fixture/original"; echo 'PASS validation failure rolled back'
validation=missing
repair_wsl_cluster_syslog 17 qa /qa/data '/qa/bad"path'
cmp "$conf" "$fixture/original"; echo 'PASS unsafe path rejected'
mv "$conf" "$fixture/external"; ln -s "$fixture/external" "$conf"
repair_wsl_cluster_syslog 17 qa /qa/data /qa/server.log
[[ -L "$conf" ]]; cmp "$fixture/external" "$fixture/original"; echo 'PASS config symlink preserved'
rm "$conf"
render_wsl_cluster_syslog 17 old /qa/old.log >"$conf"
sed -i 's/17_old/17_qa/g' "$conf"
repair_wsl_cluster_syslog 17 qa /qa/data /qa/new.log old
grep -qF 'syslog-ng-17-qa.log' "$conf"; grep -qF 'file("/qa/new.log"' "$conf"
echo 'PASS native-like rename refreshed'
# Real parser validation, when installed, uses an isolated top-level config.
if command -v /usr/sbin/syslog-ng >/dev/null; then
    printf '@version: 3.38\n@include "%s"\n' "$conf" >"$fixture/root.conf"
    /usr/sbin/syslog-ng --syntax-only -f "$fixture/root.conf"
    echo 'PASS real syslog-ng syntax'
    syslog-ng() { /usr/sbin/syslog-ng "$@" -f "$fixture/root.conf"; }
    stock
    repair_wsl_cluster_syslog 17 qa /qa/data /qa/server.log
    grep -qxF '# PGCC WSL raw PostgreSQL log v1' "$conf"
    echo 'PASS real missing-parser diagnosis and replacement'
    stock
    render_stock_cluster_syslog 18 other /qa/other >"$fixture/conf/other.conf"
    printf '@version: 3.38\n@include "%s/*.conf"\n' "$fixture/conf" >"$fixture/root.conf"
    if repair_wsl_cluster_syslog 17 qa /qa/data /qa/server.log; then exit 1; fi
    cmp "$conf" "$fixture/original"
    echo 'PASS real unrelated parser error causes rollback'
fi
