#!/usr/bin/env bash
# Purpose: populate a disposable cluster database with control objects, ACL and checksums.
# Usage: bash tools/prx-prepare-postgres-test-data.sh VERSION CLUSTER PORT
# Args: VERSION/CLUSTER -- disposable cluster and database of the same name; PORT -- TCP port.
# Output: SQL control dataset and diagnostic log; replaces only its pgcc_owner schema.
# Example: bash tools/prx-prepare-postgres-test-data.sh 16 qa 55432
set -Eeuo pipefail

pg_version="$1"
cluster_name="$2"
cluster_port="$3"
log_dir=/var/log/pgcc-tests
mkdir -p "${log_dir}"
exec > >(tee "${log_dir}/pt-data-cc07-${cluster_name}.log") 2>&1

psql_as_postgres() {
    runuser -u postgres -- psql --cluster "${pg_version}/${cluster_name}" \
        --set=ON_ERROR_STOP=1 --dbname "${cluster_name}" "$@"
}

printf 'started=%s\n' "$(date --iso-8601=seconds)"
psql_as_postgres <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgcc_acl_login') THEN
        CREATE ROLE pgcc_acl_login LOGIN PASSWORD 'Pgcc-ACL-2.1.1!';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgcc_acl_nologin') THEN
        CREATE ROLE pgcc_acl_nologin NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgcc_alt_owner') THEN
        CREATE ROLE pgcc_alt_owner NOLOGIN;
    END IF;
END
\$\$;

DROP SCHEMA IF EXISTS pgcc_owner CASCADE;
CREATE SCHEMA pgcc_owner AUTHORIZATION pgcc_owner;
SET search_path = pgcc_owner, public;

CREATE SEQUENCE control_seq START 1000;
CREATE TABLE parent_control (
    id bigint PRIMARY KEY DEFAULT nextval('control_seq'),
    payload text NOT NULL,
    qty integer NOT NULL CHECK (qty > 0),
    touched_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE child_control (
    id bigint PRIMARY KEY,
    parent_id bigint NOT NULL REFERENCES parent_control(id),
    note text
);
CREATE TABLE inherited_base (
    id integer,
    value integer CONSTRAINT inherited_positive CHECK (value > 0)
);
CREATE TABLE inherited_child (extra text) INHERITS (inherited_base);
CREATE FUNCTION touch_parent() RETURNS trigger LANGUAGE plpgsql AS \$fn\$
BEGIN
    NEW.touched_at := clock_timestamp();
    RETURN NEW;
END
\$fn\$;
CREATE TRIGGER parent_touch BEFORE UPDATE ON parent_control
    FOR EACH ROW EXECUTE FUNCTION touch_parent();
INSERT INTO parent_control(payload, qty)
SELECT 'row-' || i, i FROM generate_series(1, 100) AS g(i);
INSERT INTO child_control
SELECT i, 999 + i, 'child-' || i FROM generate_series(1, 100) AS g(i);
INSERT INTO inherited_base VALUES (1, 10);
INSERT INTO inherited_child VALUES (2, 20, 'inherited');
CREATE VIEW control_view AS SELECT id, payload, qty FROM parent_control WHERE qty <= 10;
CREATE MATERIALIZED VIEW control_matview AS SELECT count(*) AS row_count, sum(qty) AS qty_sum FROM parent_control;
CREATE TABLE alt_owned(id integer PRIMARY KEY, note text);
ALTER TABLE alt_owned OWNER TO pgcc_alt_owner;
INSERT INTO alt_owned VALUES (1, 'owned by another role');
GRANT USAGE ON SCHEMA pgcc_owner TO pgcc_user, pgcc_acl_login, pgcc_acl_nologin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA pgcc_owner TO pgcc_user;
GRANT SELECT ON ALL TABLES IN SCHEMA pgcc_owner TO pgcc_acl_login, pgcc_acl_nologin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA pgcc_owner TO pgcc_user, pgcc_acl_login;
ALTER DATABASE "${cluster_name}" SET search_path = pgcc_owner, public;
SQL

if psql_as_postgres -Atqc "SELECT name FROM pg_available_extensions WHERE name='pgcrypto'" | grep -qx pgcrypto; then
    psql_as_postgres -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto'
    printf 'extension=pgcrypto\n'
else
    printf 'extension=BLOCKED:pgcrypto-unavailable\n'
fi

psql_as_postgres -x -c "SELECT datname, pg_get_userbyid(datdba) AS owner FROM pg_database WHERE datname='${cluster_name}'"
psql_as_postgres -x -c "SELECT nspname, pg_get_userbyid(nspowner) AS owner FROM pg_namespace WHERE nspname='pgcc_owner'"
psql_as_postgres -P pager=off -c "SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls FROM pg_roles WHERE rolname LIKE 'pgcc_%' ORDER BY rolname"
psql_as_postgres -Atqc "SELECT count(*), md5(string_agg(id::text || ':' || payload || ':' || qty::text, ',' ORDER BY id)) FROM ONLY pgcc_owner.parent_control"
psql_as_postgres -Atqc "SELECT last_value, is_called FROM pgcc_owner.control_seq"
psql_as_postgres -Atqc "SHOW password_encryption"
psql_as_postgres -Atqc "SHOW shared_preload_libraries"
psql_as_postgres -Atqc "SHOW lc_messages"
psql_as_postgres -Atqc "SELECT extname FROM pg_extension ORDER BY extname"
grep -Ev '^[[:space:]]*(#|$)' "/etc/postgresql/${pg_version}/${cluster_name}/pg_hba.conf" || true

PGPASSWORD='Pgcc-QA-2.1.1!' psql --cluster "${pg_version}/${cluster_name}" \
    -h 127.0.0.1 -p "${cluster_port}" -U pgcc_user -d "${cluster_name}" \
    -Atqc 'SHOW search_path; SELECT count(*) FROM pgcc_owner.parent_control;'
printf 'password_login_rc=%s\n' "$?"
printf 'finished=%s\n' "$(date --iso-8601=seconds)"
