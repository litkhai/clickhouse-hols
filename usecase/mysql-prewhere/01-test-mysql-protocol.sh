#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Testing PREWHERE via MySQL Protocol ===${NC}\n"

# Connection settings
CH_HOST="localhost"
CH_MYSQL_PORT="9004"
CH_USER="mysql_user"
CH_PASSWORD=""
CH_CLIENT="docker exec clickhouse-test clickhouse-client"

# Test 1: Basic PREWHERE syntax via MySQL protocol
echo -e "${GREEN}Test 1: Basic PREWHERE syntax via MySQL protocol${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
USE default;
SELECT count(*) as result_count
FROM prewhere_test
PREWHERE date = '2024-03-01'
WHERE status = 'active';
"

# Test 2: EXPLAIN SYNTAX to verify PREWHERE is recognized
echo -e "\n${GREEN}Test 2: EXPLAIN SYNTAX - verify PREWHERE recognition${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
EXPLAIN SYNTAX
SELECT *
FROM default.prewhere_test
PREWHERE date = '2024-03-01'
WHERE status = 'active'
LIMIT 10;
"

# Test 3: Automatic PREWHERE optimization
echo -e "\n${GREEN}Test 3: Automatic PREWHERE optimization (WHERE converted to PREWHERE)${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SET optimize_move_to_prewhere = 1;
EXPLAIN SYNTAX
SELECT *
FROM default.prewhere_test
WHERE date = '2024-03-01' AND status = 'active'
LIMIT 10;
"

# Test 4: Complex PREWHERE with multiple conditions
echo -e "\n${GREEN}Test 4: Complex PREWHERE with multiple conditions${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT
    category,
    count(*) as cnt,
    avg(value) as avg_value
FROM default.prewhere_test
PREWHERE date >= '2024-03-01' AND date < '2024-04-01'
WHERE status = 'active'
GROUP BY category
ORDER BY cnt DESC;
"

# Test 5: PREWHERE with IN operator
echo -e "\n${GREEN}Test 5: PREWHERE with IN operator${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT count(*) as result_count
FROM default.prewhere_test
PREWHERE category IN ('A', 'B', 'C')
WHERE status = 'active';
"

# Test 6: Verify query execution in system.query_log
echo -e "\n${GREEN}Test 6: Checking query_log for PREWHERE queries (last 5 queries)${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT
    event_time,
    query_duration_ms,
    read_rows,
    read_bytes,
    substring(query, 1, 100) as query_snippet
FROM system.query_log
WHERE query LIKE '%prewhere_test%'
    AND query NOT LIKE '%system.query_log%'
    AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 5
FORMAT Vertical;
"

# Test 7: Compare with native ClickHouse client
echo -e "\n${GREEN}Test 7: Same query via native ClickHouse client${NC}"
$CH_CLIENT --query="
SELECT count(*) as result_count
FROM default.prewhere_test
PREWHERE date = '2024-03-01'
WHERE status = 'active';
"

echo -e "\n${BLUE}=== MySQL Protocol Tests Complete ===${NC}"
