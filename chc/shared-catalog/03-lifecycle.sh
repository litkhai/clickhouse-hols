#!/usr/bin/env bash
# 03 — Object lifecycle as the replicas log it: stages and versions of one table
# from CREATE to final removal, UNDROP, retention, DROP DATABASE.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
set -e
uuid_of() { ch -q "SELECT uuid FROM system.tables WHERE database = '$1' AND name = '$2'" 2>/dev/null | grep -v '^Unknown'; }
# stages LIKE-UUID: every stage change each replica applied for that object
stages() {
  flush_logs
  show "SELECT hostName() AS replica, formatDateTime(event_time_microseconds, '%H:%i:%S.%f') AS at, replaceRegexpOne(message, '^Applying changes for object [0-9a-f-]+ ', '') AS change FROM clusterAllReplicas('default', system.text_log) WHERE event_date = today() AND logger_name = 'SharedDatabaseCatalog' AND message LIKE 'Applying changes for object $1 %' ORDER BY event_time_microseconds, replica"
}
dropped() { show "SELECT hostName() AS replica, database, table, uuid, engine, table_dropped_time FROM clusterAllReplicas('default', system.dropped_tables) WHERE database LIKE 'sc_lab%' ORDER BY table, replica"; }

expect_ok mk "CREATE TABLE sc_lab.life (n UInt64) ENGINE = MergeTree ORDER BY n"
expect_ok fill "INSERT INTO sc_lab.life SELECT number FROM numbers(1000)"
U="$(uuid_of sc_lab life)"; echo "uuid = $U"
expect_ok alter "ALTER TABLE sc_lab.life ADD COLUMN c UInt8 DEFAULT 1"
expect_ok rename "RENAME TABLE sc_lab.life TO sc_lab.life2"
echo "## DROP keeps the object, UNDROP brings it back"
expect_ok drop "DROP TABLE sc_lab.life2"
show "SELECT now() AS dropped_at"
dropped
expect_ok undrop "UNDROP TABLE sc_lab.life2"
show "SELECT hostName() AS replica, uuid, total_rows FROM clusterAllReplicas('default', system.tables) WHERE database = 'sc_lab' AND name = 'life2' ORDER BY replica"
echo "## the object JSON the catalog stores (create_query cut)"
flush_logs
show "SELECT hostName() AS replica, toUInt32OrZero(extract(message, 'new version ([0-9]+)')) AS obj_version, replaceRegexpOne(extract(message, ': (\\\\{.*)$'), '\"create_query\":\"[^\"]{0,40}[^\"]*\"', '\"create_query\":\"…\"') AS object FROM clusterAllReplicas('default', system.text_log) WHERE event_date = today() AND logger_name = 'SharedDatabaseCatalog' AND message LIKE 'Looking at the new version % of the object $U:%' ORDER BY event_time_microseconds LIMIT 1 BY replica, obj_version"

echo "## retention 0: query SETTINGS vs session setting"
expect_ok drop_q "DROP TABLE sc_lab.life2 SETTINGS database_shared_drop_table_delay_seconds = 0"
dropped
expect_ok undrop_q "UNDROP TABLE sc_lab.life2"
try drop_s "DROP TABLE sc_lab.life2" --database_shared_drop_table_delay_seconds=0
dropped
sleep 20
try undrop_s_20s "UNDROP TABLE sc_lab.life2"
stages "$U"
echo "## the drop thread waits for every active replica, skips idle ones"
show "SELECT hostName() AS replica, formatDateTime(event_time_microseconds, '%H:%i:%S.%f') AS at, substring(message, 1, 200) AS message FROM clusterAllReplicas('default', system.text_log) WHERE event_date = today() AND logger_name = 'SharedDatabaseCatalog' AND message LIKE '%$U%' AND message NOT LIKE 'Applying changes%' AND message NOT LIKE 'Looking at%' ORDER BY event_time_microseconds LIMIT 20"
show "SELECT substring(message, 1, 260) AS message FROM system.text_log WHERE event_time > now() - INTERVAL 10 MINUTE AND logger_name = 'SharedDatabaseCatalog' AND message LIKE '%Discarded inactive replicas%' ORDER BY event_time_microseconds DESC LIMIT 1"

echo "## DROP ... SYNC"
expect_ok mk_sync "CREATE TABLE sc_lab.life_sync (n UInt64) ENGINE = MergeTree ORDER BY n"
expect_ok drop_sync "DROP TABLE sc_lab.life_sync SYNC"
try undrop_sync "UNDROP TABLE sc_lab.life_sync"

echo "## DROP DATABASE without SYNC"
expect_ok mkdb "CREATE DATABASE sc_lab_dropdb"
expect_ok mkdb_t "CREATE TABLE sc_lab_dropdb.t (n UInt64) ENGINE = MergeTree ORDER BY n"
expect_ok mkdb_fill "INSERT INTO sc_lab_dropdb.t SELECT number FROM numbers(10)"
DBU="$(ch -q "SELECT uuid FROM system.databases WHERE name = 'sc_lab_dropdb'" 2>/dev/null | grep -v '^Unknown')"
TU="$(uuid_of sc_lab_dropdb t)"
expect_ok dropdb "DROP DATABASE sc_lab_dropdb"
dropped
try undrop_db "UNDROP DATABASE sc_lab_dropdb"
try undrop_db_table "UNDROP TABLE sc_lab_dropdb.t"
stages "$DBU"
stages "$TU"
