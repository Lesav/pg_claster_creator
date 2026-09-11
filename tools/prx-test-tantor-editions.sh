#!/usr/bin/env bash
# Purpose: regression-test Tantor edition selection without modifying clusters.
# Usage: bash tools/prx-test-tantor-editions.sh REPO
# Args: REPO -- project directory containing the three scripts.
# Output: assertions for package discovery, priorities, metadata and DEB helpers.
# Example: bash tools/prx-test-tantor-editions.sh /mnt/d/Ai/pg_claster_creator
set -Eeuo pipefail
repo="$(realpath "$1")"
fixture="$(mktemp -d /tmp/pgcc-tantor.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
assert() { [[ "$1" == "$2" ]] || { printf 'FAIL: %s != %s\n' "$1" "$2" >&2; exit 1; }; }
(
    source "$repo/create-claster.sh"
    mkdir -p "$fixture/data"
    printf '18\n' >"$fixture/data/PG_VERSION"
    assert "$(cluster_backup_version 16 "$fixture/data")" 18
    assert "$(cluster_backup_version 18 "$fixture/data")" 18
    printf 'invalid\n' >"$fixture/data/PG_VERSION"
    ! cluster_backup_version 16 "$fixture/data"
    assert "$(package_to_fields tantor-se-server-17)" 'tantor-se|17'
    assert "$(package_to_fields tantor-be-server-18)" 'tantor-be|18'
    assert "$(package_to_fields tantor-free-server-16-server)" 'tantor-free|16'
    ! package_to_fields tantor-se-client-17
    ! package_to_fields tantor-be-server-18-dbgsym
    assert "$(vendor_service_name tantor-se-server-17)" tantor-se-server-17
    assert "$(vendor_service_name tantor-be-server-18)" tantor-be-server-18
    choose_from_packages test tantor-free-server-19 tantor-be-server-18 tantor-se-server-17 <<<1 >"$fixture/menu"
    assert "$SELECTED_PACKAGE" tantor-se-server-17
    choose_from_packages test tantor-se-server-16 tantor-se-server-17 <<<1 >/dev/null
    assert "$SELECTED_PACKAGE" tantor-se-server-17
    apt-cache() { printf '%s\n' tantor-se-server-17 tantor-be-server-18 tantor-be-client-18 postgresql-server-dev-18 tantor-free-server-16; }
    assert "$(server_packages | wc -l)" 3
    package_installed() { return 0; }
    dpkg-query() { printf 'tantor-be-server-18:amd64: /opt/tantor/db/18/bin/postgres\n'; }
    assert "$(cluster_server_package 18 /opt/tantor/db/18 /DATA/pg_18/demo)" tantor-be-server-18
    dpkg-query() { printf 'tantor-se-server-18: /opt/tantor/db/18/bin/postgres\n'; }
    assert "$(cluster_server_package 18 /opt/tantor/db/18 /DATA/pg_18/demo)" tantor-se-server-18
    dpkg-query() { return 1; }
    ! cluster_server_package 18 /opt/tantor/db/18 /DATA/pg_18/demo
    printf 'OK: discovery, SE > BE > Free, versions, services, owner metadata\n'
)
sed '/^main "\$@"$/d' "$repo/create-claster-deb.sh" >"$fixture/builder.sh"
(
    source "$fixture/builder.sh"
    for pg in tantor-se tantor-be; do
        pg_ver=18; cls_nm=demo; DATA_ROOT=''
        assert "$(default_server_package)" "$pg-server-18"
        assert "$(infer_family_from_package "$pg-server-18")" "$pg"
        assert "$(target_data_path)" "/var/lib/postgresql/$pg-18/demo"
        SERVER_PACKAGE="$(default_server_package)"; PREFER_NEWEST_SERVER=no
        for MODE in 2 3 4; do
            assert "$(dependency_list)" "postgresql-common, $pg-server-18"
        done
    done
    printf 'OK: DEB package names, edition inference, data paths\n'
)
for script in create-claster.sh create-claster-deb.sh create-claster-backup.sh; do
    bash -n "$repo/$script"
done
printf 'OK: syntax of all three scripts\n'
