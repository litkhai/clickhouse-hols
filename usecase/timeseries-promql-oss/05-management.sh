#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docker exec -i clickhouse-26-8 clickhouse-client --multiline --multiquery < "$SCRIPT_DIR/05-management.sql"
