#!/usr/bin/env bash
# Build images, start MinIO / Polaris / engines, bootstrap Polaris, stage TPC-H.
# The pg-main image compiles PostgreSQL, pg_lake (with DuckDB) and pg_clickhouse
# from source: expect 30-60 minutes the first time.
source "$(dirname "$0")/_lib.sh"
docker pull -q alpine:3.20 >/dev/null
docker compose build pg-main runner
docker compose up -d --wait minio polaris-db polaris clickhouse pg-duck pg-main
runner init/polaris/bootstrap.py
for sf in $SF_LIST; do runner datagen/gen.py "$sf"; done
echo "setup done. next: ./01-load.sh <sf>"
