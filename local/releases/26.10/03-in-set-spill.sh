#!/bin/bash

# The two runs that matter most here fail: the in-memory set under a 400 MB cap,
# and the same cap with nothing else set. Errors stop a .sql file, so they run
# here after 03-in-set-spill.sql has built the table.

CH="docker exec -i clickhouse-26-10 clickhouse-client"

echo "================================"
echo "ClickHouse 26.10: IN sets spilling to disk Test"
echo "================================"
echo ""

cat 03-in-set-spill.sql | $CH --multiline --multiquery

refused() {
    echo "-- $1"
    $CH -q "$2" 2>&1 | grep -o 'Code: [0-9]*\..*' | head -1
    echo ""
}

Q="SELECT count() FROM numbers(2000000) WHERE intHash64(number) IN (SELECT k FROM ids)"

echo ""
echo "════════ 4. Under a 400 MB cap ════════"
echo ""

refused "4a. spilling switched off: the set does not fit (this is what 26.9 does)" \
    "$Q SETTINGS max_memory_usage = 400000000, max_bytes_before_external_set = 0, max_bytes_ratio_before_external_set = 0"

refused "4b. the cap alone, defaults otherwise: still fails — the ratio ignores max_memory_usage" \
    "$Q SETTINGS max_memory_usage = 400000000"

echo "-- 4c. the cap plus an absolute threshold below it: succeeds"
$CH -q "$Q SETTINGS max_memory_usage = 400000000, max_bytes_before_external_set = 100000000"
echo ""

echo "================================"
echo "Test complete!"
echo "================================"
