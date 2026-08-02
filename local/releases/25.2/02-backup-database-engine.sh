#!/bin/bash

echo "================================"
echo "ClickHouse 25.2: Backup Database Engine Test"
echo "================================"
echo ""

# BACKUP will not overwrite an existing destination, so clear the one this lab
# writes to. Nothing else lives under that name.
docker exec clickhouse-25-2 rm -rf /var/lib/clickhouse/backups/snapshot_v1 2>/dev/null
docker exec clickhouse-25-2 clickhouse-client -q "DROP DATABASE IF EXISTS snapshot" 2>/dev/null

cat 02-backup-database-engine.sql | docker exec -i clickhouse-25-2 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
