#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== PREWHERE vs WHERE Performance Comparison ===${NC}\n"

# Connection settings
CH_HOST="localhost"
CH_MYSQL_PORT="9004"
CH_USER="mysql_user"

# Warm up the cache
echo -e "${YELLOW}Warming up cache...${NC}"
mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "SELECT count(*) FROM default.prewhere_test_large;" > /dev/null 2>&1

# Test 1: WHERE only (no optimization)
echo -e "\n${GREEN}Test 1: WHERE only (optimize_move_to_prewhere = 0)${NC}"
echo -e "${YELLOW}Query: SELECT with date filter in WHERE clause${NC}"

for i in {1..3}; do
    echo -e "\n${BLUE}Run $i:${NC}"
    mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
    SET optimize_move_to_prewhere = 0;

    SELECT count(*), avg(value), sum(value)
    FROM default.prewhere_test_large
    WHERE date BETWEEN '2024-06-01' AND '2024-06-30'
        AND status = 'active'
    SETTINGS max_threads = 4;
    " --table

    # Get execution time from query_log
    mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
    SELECT
        query_duration_ms,
        read_rows,
        formatReadableSize(read_bytes) as read_size,
        formatReadableSize(memory_usage) as memory
    FROM system.query_log
    WHERE query LIKE '%prewhere_test_large%'
        AND query LIKE '%2024-06-01%'
        AND query NOT LIKE '%system.query_log%'
        AND type = 'QueryFinish'
    ORDER BY event_time DESC
    LIMIT 1
    FORMAT Vertical;
    "
done

# Test 2: PREWHERE explicit
echo -e "\n${GREEN}Test 2: Explicit PREWHERE${NC}"
echo -e "${YELLOW}Query: Same query but with explicit PREWHERE${NC}"

for i in {1..3}; do
    echo -e "\n${BLUE}Run $i:${NC}"
    mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
    SELECT count(*), avg(value), sum(value)
    FROM default.prewhere_test_large
    PREWHERE date BETWEEN '2024-06-01' AND '2024-06-30'
    WHERE status = 'active'
    SETTINGS max_threads = 4;
    " --table

    mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
    SELECT
        query_duration_ms,
        read_rows,
        formatReadableSize(read_bytes) as read_size,
        formatReadableSize(memory_usage) as memory
    FROM system.query_log
    WHERE query LIKE '%prewhere_test_large%'
        AND query LIKE '%PREWHERE%'
        AND query NOT LIKE '%system.query_log%'
        AND type = 'QueryFinish'
    ORDER BY event_time DESC
    LIMIT 1
    FORMAT Vertical;
    "
done

# Test 3: Automatic PREWHERE optimization
echo -e "\n${GREEN}Test 3: Automatic PREWHERE optimization (optimize_move_to_prewhere = 1)${NC}"
echo -e "${YELLOW}Query: WHERE clause with automatic optimization${NC}"

for i in {1..3}; do
    echo -e "\n${BLUE}Run $i:${NC}"
    mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
    SET optimize_move_to_prewhere = 1;

    SELECT count(*), avg(value), sum(value)
    FROM default.prewhere_test_large
    WHERE date BETWEEN '2024-06-01' AND '2024-06-30'
        AND status = 'active'
    SETTINGS max_threads = 4;
    " --table

    mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
    SELECT
        query_duration_ms,
        read_rows,
        formatReadableSize(read_bytes) as read_size,
        formatReadableSize(memory_usage) as memory
    FROM system.query_log
    WHERE query LIKE '%prewhere_test_large%'
        AND query LIKE '%2024-06-01%'
        AND query NOT LIKE '%system.query_log%'
        AND type = 'QueryFinish'
    ORDER BY event_time DESC
    LIMIT 1
    FORMAT Vertical;
    "
done

# Test 4: High selectivity PREWHERE
echo -e "\n${GREEN}Test 4: High selectivity PREWHERE (filtering on indexed column)${NC}"

for i in {1..3}; do
    echo -e "\n${BLUE}Run $i:${NC}"
    mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
    SELECT count(*), avg(value)
    FROM default.prewhere_test_large
    PREWHERE date = '2024-06-15' AND user_id < 1000
    WHERE status = 'active' AND length(description) > 20
    SETTINGS max_threads = 4;
    " --table

    mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
    SELECT
        query_duration_ms,
        read_rows,
        formatReadableSize(read_bytes) as read_size
    FROM system.query_log
    WHERE query LIKE '%user_id < 1000%'
        AND query NOT LIKE '%system.query_log%'
        AND type = 'QueryFinish'
    ORDER BY event_time DESC
    LIMIT 1
    FORMAT Vertical;
    "
done

# Summary comparison
echo -e "\n${BLUE}=== Performance Summary ===${NC}"
echo -e "${GREEN}Comparing average execution times:${NC}\n"

mysql -h $CH_HOST -P $CH_MYSQL_PORT --protocol=TCP -u $CH_USER -e "
SELECT
    if(query LIKE '%optimize_move_to_prewhere = 0%', 'WHERE only (no opt)',
       if(query LIKE '%PREWHERE%', 'Explicit PREWHERE', 'Auto PREWHERE')) as query_type,
    count(*) as runs,
    round(avg(query_duration_ms), 2) as avg_duration_ms,
    round(min(query_duration_ms), 2) as min_duration_ms,
    round(max(query_duration_ms), 2) as max_duration_ms,
    round(avg(read_rows)) as avg_rows_read,
    formatReadableSize(round(avg(read_bytes))) as avg_bytes_read
FROM system.query_log
WHERE query LIKE '%prewhere_test_large%'
    AND query LIKE '%2024-06-01%'
    AND query NOT LIKE '%system.query_log%'
    AND type = 'QueryFinish'
    AND event_time >= now() - INTERVAL 5 MINUTE
GROUP BY query_type
ORDER BY avg_duration_ms;
" --table

echo -e "\n${BLUE}=== Performance Comparison Complete ===${NC}"
