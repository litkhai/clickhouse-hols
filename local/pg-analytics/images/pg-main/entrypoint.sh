#!/bin/bash
# Runs PostgreSQL and pgduck_server in one container: the design point of
# path A is that the lake engine shares the OLTP node's CPU and memory.
set -euo pipefail

PGDUCK_DIR=/var/lib/pgduck
mkdir -p "$PGDUCK_DIR/socket" "$PGDUCK_DIR/cache"
chmod 700 "$PGDUCK_DIR/socket"

# pgduck_server reads MinIO through a DuckDB secret created at start-up
cat > "$PGDUCK_DIR/init.sql" <<SQL
CREATE SECRET minio (TYPE s3, KEY_ID '${S3_ACCESS_KEY}', SECRET '${S3_SECRET_KEY}',
  ENDPOINT '${S3_ENDPOINT}', URL_STYLE 'path', USE_SSL false, REGION 'us-east-1');
SQL

pgduck_args=(--unix_socket_directory "$PGDUCK_DIR/socket" --port 5332
             --init_file_path "$PGDUCK_DIR/init.sql"
             --memory_limit "${PGDUCK_MEMORY_LIMIT:-4GB}")
if [ "${PGDUCK_CACHE:-on}" = "on" ]; then
  pgduck_args+=(--cache_dir "$PGDUCK_DIR/cache")
fi
pgduck_server "${pgduck_args[@]}" &

# pg_lake's workers fail (and retry) until the engine answers; wait for it
for _ in $(seq 1 120); do
  psql -h "$PGDUCK_DIR/socket" -p 5332 -Atqc 'SELECT 1' >/dev/null 2>&1 && break
  sleep 0.5
done

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  initdb -D "$PGDATA" -U postgres --locale=C.UTF-8 --auth=trust >/dev/null
  cat >> "$PGDATA/postgresql.conf" <<CONF
listen_addresses = '*'
shared_preload_libraries = 'pg_extension_base'
pg_lake_engine.host = 'host=$PGDUCK_DIR/socket port=5332'
pg_lake_iceberg.default_location_prefix = '${ICEBERG_LOCATION_PREFIX}'
shared_buffers = '${PG_SHARED_BUFFERS:-2GB}'
work_mem = '256MB'
max_parallel_workers_per_gather = 4
autovacuum = off
# snapshots are frozen before measuring; nothing may compact behind the bench
pg_lake_iceberg.autovacuum = off
# PG18 io workers and pg_lake's per-statement attached workers share this pool;
# the default 8 runs out when a second session writes to the lake.
max_worker_processes = 16
CONF
  echo "host all all 0.0.0.0/0 trust" >> "$PGDATA/pg_hba.conf"
fi

exec postgres -D "$PGDATA"
