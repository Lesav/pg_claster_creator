#!/usr/bin/env bash
# Purpose: regression-test PostgreSQL package names and Tantor editions without modifying clusters.
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
    assert "$(cold_restore_data_path tantor-be-server-18 /var/lib/postgresql/tantor-free-16/subsys subsys smsn)" /var/lib/postgresql/tantor-be-18/smsn
    assert "$(cold_restore_data_path tantor-se-server-17 /var/lib/postgresql/16/subsys subsys smsn)" /var/lib/postgresql/tantor-se-17/smsn
    assert "$(cold_restore_data_path postgrespro-ent-18-server /var/lib/postgresql/tantor-free-16/subsys subsys smsn)" /var/lib/postgresql/18/smsn
    assert "$(cold_restore_data_path tantor-be-server-18 /DATA/pg_16/subsys subsys smsn)" /DATA/pg_16/smsn
    (
        original_data_dir=/var/lib/postgresql/tantor-free-16/subsys
        original_name=subsys; restore_name=smsn; registered_pg_version=16; version=18
        restore_data_dir="$(cold_restore_data_path tantor-be-server-18 "$original_data_dir" "$original_name" "$restore_name")"
        transform_args=()
        # Exercise the real extraction transforms against a miniature archive.
        eval "$(declare -f restore_menu | sed -n '/if .*original_data_dir%/,/tar .*transform_args/p' | sed '$d')"
        mkdir -p "$fixture/archive/root$original_data_dir"
        printf '18\n' >"$fixture/archive/root$original_data_dir/PG_VERSION"
        tar -czf "$fixture/data.tar.gz" -C "$fixture/archive" "root$original_data_dir"
        mkdir "$fixture/extracted"
        tar "${transform_args[@]}" -xzf "$fixture/data.tar.gz" -C "$fixture/extracted" --strip-components=1
        assert "$(<"$fixture/extracted$restore_data_dir/PG_VERSION")" 18
        [[ ! -e "$fixture/extracted$original_data_dir" ]]
    )
    (
        # Redirect all conflict paths into a fixture, never touch real clusters.
        eval "$(declare -f restore_target_conflict | sed "s#/.postgres/#$fixture/.postgres/#g; s#/etc/#$fixture/etc/#g; s#/usr/lib/#$fixture/usr/lib/#g; s#\"/lib/#\"$fixture/lib/#g")"
        cluster_exists() { return 1; }
        pg_lsclusters() { printf '16 demo 5432 down postgres /unused /unused\n'; }
        conflict="$(restore_target_conflict 18 demo "$fixture/absent-data")"
        [[ "$conflict" == *'уже зарегистрировано'* && "$conflict" == *'16'* ]]
        pg_lsclusters() { return 1; }
        conflict="$(restore_target_conflict 18 demo "$fixture/absent-data")"
        [[ "$conflict" == *'не удалось проверить'* ]]
        pg_lsclusters() { return 0; }
        mkdir -p "$fixture/.postgres/systemd/save"
        link="$fixture/.postgres/systemd/postgresql@18-demo.service"
        ln -s "$fixture/missing-unit" "$link"
        ! restore_target_conflict 18 demo "$fixture/absent-data"
        # Saved units are a cache, not a conflict or a restore fallback.
        touch "$fixture/.postgres/systemd/save/postgresql@18-demo.service"
        ! restore_target_conflict 18 demo "$fixture/absent-data"
        eval "$(declare -f cluster_service_file | sed "s#/.postgres/#$fixture/.postgres/#g; s#/etc/#$fixture/etc/#g; s#/usr/lib/#$fixture/usr/lib/#g; s#\"/lib/#\"$fixture/lib/#g")"
        assert "$(cluster_service_file 18 demo)" "$fixture/.postgres/systemd/save/postgresql@18-demo.service"
        ! cluster_service_file 18 demo no
        # A live convenience link must also block.
        touch "$fixture/missing-unit"
        conflict="$(restore_target_conflict 18 demo "$fixture/absent-data")"
        [[ "$conflict" == *'/systemd/postgresql@18-demo.service' ]]
        printf 'OK: dangling link and saved cache ignored; live link protected\n'
    )
    mkdir -p "$fixture/data"
    printf '18\n' >"$fixture/data/PG_VERSION"
    assert "$(cluster_backup_version 16 "$fixture/data")" 18
    assert "$(cluster_backup_version 18 "$fixture/data")" 18
    printf 'invalid\n' >"$fixture/data/PG_VERSION"
    ! cluster_backup_version 16 "$fixture/data"
    assert "$(package_to_fields tantor-se-server-17)" 'tantor-se|17'
    assert "$(package_to_fields tantor-be-server-18)" 'tantor-be|18'
    assert "$(package_to_fields tantor-free-server-16-server)" 'tantor-free|16'
    assert "$(package_to_fields postgresql-16)" 'postgresql|16'
    assert "$(package_to_fields postgresql-16-server)" 'postgresql|16'
    assert "$(server_family_priority tantor-free)" 3
    assert "$(server_family_priority postgresql)" 3
    choose_from_packages shared-tier postgresql-18 tantor-free-server-16 <<<1 >/dev/null
    assert "$SELECTED_PACKAGE" postgresql-18
    choose_from_packages shared-tier-reverse postgresql-16 tantor-free-server-18 <<<1 >/dev/null
    assert "$SELECTED_PACKAGE" tantor-free-server-18
    choose_from_packages shared-tier-tie postgresql-16 tantor-free-server-16 <<<1 >/dev/null
    assert "$SELECTED_PACKAGE" postgresql-16
    for bad in postgresql postgresql-contrib postgresql-contrib-16 postgresql-client-16 postgresql-16-pgaudit postgresql-16-server-dbgsym; do
        ! package_to_fields "$bad"
    done
    (
        package_installed() { [[ "$1" == postgresql-16-server ]]; }
        package_available() { return 0; }
        assert "$(vanilla_server_package 16)" postgresql-16-server
        package_installed() { return 1; }
        assert "$(vanilla_server_package 16)" postgresql-16
        package_available() { [[ "$1" == postgresql-16-server ]]; }
        assert "$(vanilla_server_package 16)" postgresql-16-server
    )
    ! package_to_fields tantor-se-client-17
    ! package_to_fields tantor-be-server-18-dbgsym
    assert "$(vendor_service_name tantor-se-server-17)" tantor-se-server-17
    assert "$(vendor_service_name tantor-be-server-18)" tantor-be-server-18
    choose_from_packages test tantor-free-server-19 tantor-be-server-18 tantor-se-server-17 <<<1 >"$fixture/menu"
    assert "$SELECTED_PACKAGE" tantor-se-server-17
    choose_from_packages test tantor-se-server-16 tantor-se-server-17 <<<1 >/dev/null
    assert "$SELECTED_PACKAGE" tantor-se-server-17
    choose_from_packages test tantor-se-server-17 tantor-be-server-18 <<<2 >/dev/null
    assert "$SELECTED_PACKAGE" tantor-be-server-18
    for input in 0 '' invalid 9 -1 1.5 08 01 18446744073709551617; do
        (
            choose_from_packages cancel-test tantor-se-server-17 tantor-be-server-18
            printf 'UNEXPECTED_CONTINUATION\n'
        ) <<<"${input}"$'\n1' >"$fixture/package-cancel" 2>&1
        assert "$(grep -c '^cancel-test$' "$fixture/package-cancel")" 1
        ! grep -Eq 'UNEXPECTED_CONTINUATION|неверный номер|error' "$fixture/package-cancel"
    done
    (
        choose_from_packages cancel-test tantor-se-server-17
        printf 'UNEXPECTED_CONTINUATION\n'
    ) </dev/null >"$fixture/package-eof"
    ! grep -q UNEXPECTED_CONTINUATION "$fixture/package-eof"
    printf 'OK: package choice exits on zero/invalid/empty/EOF without retrying\n'
    apt-cache() { printf '%s\n' tantor-se-server-17 tantor-be-server-18 tantor-be-client-18 postgresql-server-dev-18 tantor-free-server-16 postgresql-16 postgresql-16-server postgresql-client-16 postgresql-contrib postgresql-16-pgaudit; }
    assert "$(server_packages | wc -l)" 5
    package_installed() { return 0; }
    dpkg-query() { printf 'tantor-be-server-18:amd64: /opt/tantor/db/18/bin/postgres\n'; }
    assert "$(cluster_server_package 18 /opt/tantor/db/18 /DATA/pg_18/demo)" tantor-be-server-18
    dpkg-query() { printf 'tantor-se-server-18: /opt/tantor/db/18/bin/postgres\n'; }
    assert "$(cluster_server_package 18 /opt/tantor/db/18 /DATA/pg_18/demo)" tantor-se-server-18
    dpkg-query() { printf 'postgresql-16: /usr/lib/postgresql/16/bin/postgres\n'; }
    assert "$(cluster_server_package 16 /usr/lib/postgresql/16 /fixture/data)" postgresql-16
    dpkg-query() { printf 'postgresql-16-server:amd64: /usr/lib/postgresql/16/bin/postgres\n'; }
    assert "$(cluster_server_package 16 /usr/lib/postgresql/16 /fixture/data)" postgresql-16-server
    dpkg-query() { return 1; }
    ! cluster_server_package 18 /opt/tantor/db/18 /DATA/pg_18/demo
    ! cluster_server_package 16 /usr/lib/postgresql/16 /fixture/data
    printf 'OK: discovery, SE/Enterprise > BE > Free/PostgreSQL, versions, services, owner metadata\n'
)
sed '/^main "\$@"$/d' "$repo/create-claster-deb.sh" >"$fixture/builder.sh"
(
    source "$fixture/builder.sh"
    (
        pg=postgresql; pg_ver=16
        dpkg-query() { return 1; }
        apt-cache() { printf '  Candidate: 16.15\n'; }
        assert "$(default_server_package)" postgresql-16
        dpkg-query() { [[ "${*: -1}" == postgresql-16-server ]] && printf 'ii '; }
        assert "$(default_server_package)" postgresql-16-server
        MODE=5; SERVER_PACKAGE=postgresql-16; PREFER_NEWEST_SERVER=no
        assert "$(dependency_list)" 'postgresql-common, postgresql-16'
        assert "$(infer_family_from_package postgresql-16)" postgresql
    )
    (
        MODE=""; pg=tantor-be; pg_ver=18; cls_nm=demo; cls_ch=demo
        cls_us=demo; cls_pw=demo; cls_pt=5432; SERVER_PACKAGE=""; DATA_ROOT=""
        ! interactive_configuration >"$fixture/main-invalid" <<<9
        assert "$(grep -c 'Выбор режима' "$fixture/main-invalid")" 1
        ! interactive_configuration >"$fixture/family-back" <<<$'2\n0\n0'
        assert "$(grep -c 'Выбор режима' "$fixture/family-back")" 2
        ! interactive_configuration >"$fixture/family-invalid" <<<$'2\n9\n0'
        assert "$(grep -c 'Выбор режима' "$fixture/family-invalid")" 2
        ! interactive_configuration >"$fixture/version-back" <<<$'2\n5\nbad\n0\n0'
        assert "$(grep -c 'Семейство PostgreSQL:' "$fixture/version-back")" 2
        MODE=""
        ! interactive_configuration >"$fixture/eof" </dev/null
        # Complete the actual empty-cluster wizard, but do not build/install.
        MODE=""; pg_ver=18
        interactive_configuration >"$fixture/complete" <<<$'2\n5\n18\n\n\n\n\n\n\n\n1\ny'
        assert "$MODE" 2
        printf 'OK: menu invalid/zero/EOF navigation, previous step, complete wizard\n'
    )
    for pg in tantor-se tantor-be; do
        pg_ver=18; cls_nm=demo; DATA_ROOT=''
        assert "$(default_server_package)" "$pg-server-18"
        assert "$(infer_family_from_package "$pg-server-18")" "$pg"
        assert "$(target_data_path)" "/var/lib/postgresql/$pg-18/demo"
        META_DATA_DIR=/var/lib/postgresql/tantor-free-16/subsys; META_CLUSTER_NAME=subsys
        MODE=3; MOVE_AFTER_RESTORE=no
        assert "$(target_data_path)" "/var/lib/postgresql/$pg-18/demo"
        META_DATA_DIR=/DATA/pg_16/subsys
        assert "$(target_data_path)" /DATA/pg_16/demo
        MODE=2
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
