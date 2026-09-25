#!/usr/bin/env bash
# Stop everything and delete all volumes (MinIO data, Polaris DB, PG data).
source "$(dirname "$0")/_lib.sh"
docker compose --profile tools down -v --remove-orphans
rm -rf .state
