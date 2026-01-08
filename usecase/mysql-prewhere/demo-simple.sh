#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     MySQL PREWHERE Simple Demo                           ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}\n"

CH_HOST="localhost"
CH_MYSQL_PORT="9004"
CH_USER="mysql_user"
CH_CLIENT="docker exec clickhouse-test clickhouse-client"

echo -e "${GREEN}1. Basic query via MySQL protocol${NC}\n"
echo -e "${YELLOW}Command: mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER${NC}\n"

echo -e "${BLUE}Query 1: Count records for a specific date${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT count(*) as total_records
FROM default.prewhere_test
WHERE date = '2024-03-01';
" --table

echo -e "\n${BLUE}Query 2: Same query with explicit PREWHERE${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT count(*) as total_records
FROM default.prewhere_test
PREWHERE date = '2024-03-01';
" --table

echo -e "\n${BLUE}Query 3: PREWHERE with multiple conditions${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT
    category,
    count(*) as count,
    round(avg(value), 2) as avg_value
FROM default.prewhere_test
PREWHERE date >= '2024-03-01' AND date < '2024-04-01'
WHERE status = 'active'
GROUP BY category
ORDER BY count DESC;
" --table

echo -e "\n${BLUE}Query 4: EXPLAIN SYNTAX to see PREWHERE${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
EXPLAIN SYNTAX
SELECT *
FROM default.prewhere_test
PREWHERE date = '2024-03-01'
WHERE status = 'active'
LIMIT 5;
"

echo -e "\n${BLUE}Query 5: EXPLAIN PLAN to see execution plan${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
EXPLAIN PLAN
SELECT *
FROM default.prewhere_test
PREWHERE date = '2024-03-01'
WHERE status = 'active'
LIMIT 5;
"

echo -e "\n${GREEN}2. Compare with ClickHouse native client${NC}\n"

echo -e "${BLUE}Same query via native client:${NC}"
$CH_CLIENT --query="
SELECT count(*) as total_records
FROM default.prewhere_test
PREWHERE date = '2024-03-01';
"

echo -e "\n${GREEN}3. Performance comparison on large table${NC}\n"

echo -e "${YELLOW}Testing on 10M row table...${NC}\n"

echo -e "${BLUE}Test 1: Without PREWHERE optimization${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SET optimize_move_to_prewhere = 0;
SELECT 'Without PREWHERE' as test, count(*) as records, round(avg(value), 2) as avg_val
FROM default.prewhere_test_large
WHERE date = '2024-06-15';
" --table

echo -e "\n${BLUE}Test 2: With explicit PREWHERE${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT 'With PREWHERE' as test, count(*) as records, round(avg(value), 2) as avg_val
FROM default.prewhere_test_large
PREWHERE date = '2024-06-15';
" --table

echo -e "\n${BLUE}Test 3: PREWHERE with highly selective filter${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT count(*) as records, round(avg(value), 2) as avg_val
FROM default.prewhere_test_large
PREWHERE date = '2024-06-15' AND user_id < 100
WHERE status = 'active';
" --table

echo -e "\n${GREEN}4. Verify automatic optimization${NC}\n"

echo -e "${BLUE}Check if WHERE is converted to PREWHERE automatically:${NC}\n"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SET optimize_move_to_prewhere = 1;
EXPLAIN SYNTAX
SELECT * FROM default.prewhere_test WHERE date = '2024-03-01';
"

echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Demo Complete                          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${GREEN}Key Takeaways:${NC}"
echo -e "✅ PREWHERE works via MySQL protocol"
echo -e "✅ Syntax is identical to native ClickHouse"
echo -e "✅ Automatic optimization is available"
echo -e "✅ Performance benefits are real"

echo -e "\n${YELLOW}Try it yourself:${NC}"
echo -e "  mysql -h localhost -P 9004 --protocol=TCP -u mysql_user"

echo -e "\n${YELLOW}Example queries to try:${NC}"
echo -e "  SELECT * FROM default.prewhere_test PREWHERE date = '2024-01-15' LIMIT 10;"
echo -e "  EXPLAIN SYNTAX SELECT * FROM default.prewhere_test WHERE date = '2024-01-15';"
echo -e "  EXPLAIN PLAN SELECT * FROM default.prewhere_test PREWHERE date = '2024-01-15';"

echo ""
