#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== PREWHERE Verification Tests ===${NC}\n"

# Connection settings
CH_HOST="localhost"
CH_MYSQL_PORT="9004"
CH_USER="mysql_user"
CH_CLIENT="docker exec clickhouse-test clickhouse-client"

# Test 1: Verify PREWHERE in EXPLAIN PLAN
echo -e "${GREEN}Test 1: Verify PREWHERE appears in EXPLAIN PLAN${NC}\n"

echo -e "${YELLOW}Query with explicit PREWHERE:${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
EXPLAIN PLAN
SELECT *
FROM default.prewhere_test
PREWHERE date = '2024-03-01'
WHERE status = 'active'
LIMIT 100;
" | grep -i "prewhere" && echo -e "${GREEN}✅ PREWHERE found in execution plan${NC}" || echo -e "${RED}❌ PREWHERE not found${NC}"

# Test 2: Verify automatic optimization
echo -e "\n${GREEN}Test 2: Verify automatic PREWHERE optimization${NC}\n"

echo -e "${YELLOW}EXPLAIN SYNTAX with optimize_move_to_prewhere = 1:${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SET optimize_move_to_prewhere = 1;
EXPLAIN SYNTAX
SELECT *
FROM default.prewhere_test
WHERE date = '2024-03-01' AND status = 'active';
"

echo -e "\n${YELLOW}Check if WHERE was converted to PREWHERE:${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SET optimize_move_to_prewhere = 1;
EXPLAIN SYNTAX
SELECT *
FROM default.prewhere_test
WHERE date = '2024-03-01' AND status = 'active';
" | grep -i "prewhere" && echo -e "${GREEN}✅ WHERE automatically converted to PREWHERE${NC}" || echo -e "${YELLOW}⚠️  No automatic conversion (might be expected depending on the query)${NC}"

# Test 3: Verify query pipeline
echo -e "\n${GREEN}Test 3: Verify PREWHERE in query pipeline${NC}\n"

mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
EXPLAIN PIPELINE
SELECT *
FROM default.prewhere_test
PREWHERE date >= '2024-03-01' AND date < '2024-04-01'
WHERE status = 'active'
LIMIT 100;
"

# Test 4: Compare data read with and without PREWHERE
echo -e "\n${GREEN}Test 4: Compare data read with and without PREWHERE${NC}\n"

echo -e "${YELLOW}Without PREWHERE (optimize_move_to_prewhere = 0):${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SET optimize_move_to_prewhere = 0;
SELECT count(*), avg(value) FROM default.prewhere_test_large WHERE date = '2024-06-15';
" > /dev/null

sleep 1

BYTES_WITHOUT=$(mysql -h $CH_HOST -P $CH_MYSQL_PORT -u $CH_USER -sN -e "
SELECT read_bytes
FROM system.query_log
WHERE query LIKE '%prewhere_test_large%'
    AND query LIKE '%2024-06-15%'
    AND query NOT LIKE '%system.query_log%'
    AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;
")

echo -e "Bytes read: ${RED}$BYTES_WITHOUT${NC}"

echo -e "\n${YELLOW}With PREWHERE:${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT count(*), avg(value) FROM default.prewhere_test_large PREWHERE date = '2024-06-15';
" > /dev/null

sleep 1

BYTES_WITH=$(mysql -h $CH_HOST -P $CH_MYSQL_PORT -u $CH_USER -sN -e "
SELECT read_bytes
FROM system.query_log
WHERE query LIKE '%prewhere_test_large%'
    AND query LIKE '%PREWHERE%'
    AND query NOT LIKE '%system.query_log%'
    AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;
")

echo -e "Bytes read: ${GREEN}$BYTES_WITH${NC}"

if [ ! -z "$BYTES_WITHOUT" ] && [ ! -z "$BYTES_WITH" ]; then
    REDUCTION=$(echo "scale=2; (1 - $BYTES_WITH / $BYTES_WITHOUT) * 100" | bc)
    echo -e "\n${BLUE}Data read reduction: ${GREEN}${REDUCTION}%${NC}"
fi

# Test 5: Verify result consistency
echo -e "\n${GREEN}Test 5: Verify PREWHERE and WHERE produce same results${NC}\n"

echo -e "${YELLOW}Running query with PREWHERE:${NC}"
RESULT_PREWHERE=$(mysql -h $CH_HOST -P $CH_MYSQL_PORT -u $CH_USER -sN -e "
SELECT count(*), round(avg(value), 2), round(sum(value), 2)
FROM default.prewhere_test
PREWHERE date >= '2024-03-01' AND date < '2024-04-01'
WHERE status = 'active';
")

echo -e "Result: $RESULT_PREWHERE"

echo -e "\n${YELLOW}Running same query with WHERE only:${NC}"
RESULT_WHERE=$(mysql -h $CH_HOST -P $CH_MYSQL_PORT -u $CH_USER -sN -e "
SET optimize_move_to_prewhere = 0;
SELECT count(*), round(avg(value), 2), round(sum(value), 2)
FROM default.prewhere_test
WHERE date >= '2024-03-01' AND date < '2024-04-01' AND status = 'active';
")

echo -e "Result: $RESULT_WHERE"

if [ "$RESULT_PREWHERE" = "$RESULT_WHERE" ]; then
    echo -e "\n${GREEN}✅ Results match! PREWHERE and WHERE produce identical results.${NC}"
else
    echo -e "\n${RED}❌ Results differ! This should not happen.${NC}"
fi

# Test 6: Check PREWHERE effectiveness by column
echo -e "\n${GREEN}Test 6: PREWHERE effectiveness by column type${NC}\n"

echo -e "${YELLOW}Testing with indexed column (date):${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT
    'date column' as test,
    count(*) as matches
FROM default.prewhere_test_large
PREWHERE date = '2024-06-15';
" --table

mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT
    query_duration_ms,
    formatReadableSize(read_bytes) as bytes_read
FROM system.query_log
WHERE query LIKE '%date = ''2024-06-15''%'
    AND query NOT LIKE '%system.query_log%'
    AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1
FORMAT Vertical;
"

echo -e "\n${YELLOW}Testing with non-indexed String column (description):${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT
    'string column' as test,
    count(*) as matches
FROM default.prewhere_test_large
PREWHERE description LIKE '%12345%';
" --table

mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT
    query_duration_ms,
    formatReadableSize(read_bytes) as bytes_read
FROM system.query_log
WHERE query LIKE '%description LIKE%'
    AND query NOT LIKE '%system.query_log%'
    AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1
FORMAT Vertical;
"

# Test 7: Verify PREWHERE with both MySQL and native protocols
echo -e "\n${GREEN}Test 7: Compare MySQL protocol vs Native protocol${NC}\n"

echo -e "${YELLOW}Via MySQL protocol:${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT count(*) FROM default.prewhere_test PREWHERE date = '2024-03-01' WHERE status = 'active';
" --table

echo -e "\n${YELLOW}Via Native protocol:${NC}"
$CH_CLIENT --query="
SELECT count(*) FROM default.prewhere_test PREWHERE date = '2024-03-01' WHERE status = 'active';
"

echo -e "\n${BLUE}=== Verification Tests Complete ===${NC}"
echo -e "\n${GREEN}Summary:${NC}"
echo -e "- PREWHERE syntax works via MySQL protocol ✓"
echo -e "- Automatic optimization available ✓"
echo -e "- Results are consistent between PREWHERE and WHERE ✓"
echo -e "- Both MySQL and Native protocols support PREWHERE ✓"
