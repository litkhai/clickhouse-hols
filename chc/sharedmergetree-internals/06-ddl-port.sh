#!/usr/bin/env bash
# 06 — Porting OSS DDL: which ReplicatedMergeTree / ON CLUSTER forms Cloud accepts, and what it stores.
# Statements marked "must fail" are negative checks: the step fails if they succeed,
# or if they fail with a different error code.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

ok() {        # ok "SQL"
  echo "$1"
  ch -q "$1" < /dev/null
  echo "  → OK"
}
must_fail() { # must_fail CODE "SQL"
  local code="$1" sql="$2" err
  echo "$sql"
  if err="$(ch -q "$sql" < /dev/null 2>&1)"; then
    echo "FAIL: expected error code $code, but the statement succeeded"; exit 1
  fi
  if ! grep -q "Code: $code\." <<< "$err"; then
    echo "FAIL: expected error code $code, got:"; echo "$err"; exit 1
  fi
  echo "  → fails as expected: $(grep -o "Code: $code\. DB::Exception: [^(]*" <<< "$err" | sed -E 's/Code: [0-9]+\. DB::Exception: (Received from [^ ]+ DB::Exception: )?//' | head -1)"
}

for t in p1 p2 p3 p4 p5 p6 p4_dist; do ch -q "DROP TABLE IF EXISTS smt_lab.$t SYNC" < /dev/null; done

echo "-- 1. OSS DDL often names the cluster through a macro. Cloud defines no {cluster} macro."
must_fail 139 "CREATE TABLE smt_lab.p1 ON CLUSTER '{cluster}' (id UInt64) ENGINE = ReplicatedMergeTree ORDER BY id"
echo
echo "-- 2. Explicit Keeper path and replica name, as written for OSS: rejected in the Shared database"
must_fail 36 "CREATE TABLE smt_lab.p2 (id UInt64) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/p2', '{replica}') ORDER BY id"
echo
echo "-- 3. The same with ON CLUSTER default: the cluster name resolves, the engine arguments still do not"
must_fail 36 "CREATE TABLE smt_lab.p3 ON CLUSTER default (id UInt64) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/p3', '{replica}') ORDER BY id"
echo
echo "-- 4. What works: drop the arguments (and ON CLUSTER, or keep it as 'default')"
ok "CREATE TABLE smt_lab.p4 (id UInt64) ENGINE = ReplicatedMergeTree ORDER BY id"
ok "CREATE TABLE smt_lab.p5 ON CLUSTER default (id UInt64, v UInt64) ENGINE = ReplicatedReplacingMergeTree(v) ORDER BY id"
ok "CREATE TABLE smt_lab.p6 (id UInt64, v UInt64) ENGINE = AggregatingMergeTree ORDER BY id"
echo
show "
SELECT name, engine, engine_full FROM system.tables
WHERE database = 'smt_lab' AND name IN ('p4', 'p5', 'p6')
ORDER BY name"
echo
echo "-- 5. A Distributed table over 'default' still works: one shard, so each row is read once"
ok "CREATE TABLE smt_lab.p4_dist AS smt_lab.p4 ENGINE = Distributed(default, smt_lab, p4, rand())"
ok "INSERT INTO smt_lab.p4 SELECT number FROM numbers(1000)"
show "
SELECT (SELECT count() FROM smt_lab.p4) AS local_count,
       (SELECT count() FROM smt_lab.p4_dist) AS distributed_count,
       (SELECT count() FROM system.clusters WHERE cluster = 'default') AS replicas,
       (SELECT uniqExact(shard_num) FROM system.clusters WHERE cluster = 'default') AS shards"
