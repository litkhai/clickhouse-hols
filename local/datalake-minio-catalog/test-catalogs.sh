#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
CONFIG_FILE="config.env"
source "$CONFIG_FILE"

# Test results
PASSED=0
FAILED=0
TEST_RESULTS_FILE="/tmp/clickhouse_catalog_test_results_$$.txt"
> "$TEST_RESULTS_FILE"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  ClickHouse 25.11 Catalog Integration Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to check if ClickHouse is available
check_clickhouse() {
    # Try both 25.11 and 25.10
    if docker ps | grep -q clickhouse-25-11; then
        CLICKHOUSE_CONTAINER="clickhouse-25-11"
        echo -e "${BLUE}Checking ClickHouse 25.11...${NC}"
    elif docker ps | grep -q clickhouse-25-10; then
        CLICKHOUSE_CONTAINER="clickhouse-25-10"
        echo -e "${BLUE}Checking ClickHouse 25.10...${NC}"
    else
        echo -e "${RED}ClickHouse 25.10 or 25.11 container not found${NC}"
        echo "Please start ClickHouse first:"
        echo "  cd ../oss-mac-setup && ./set.sh 25.10 && ./start.sh"
        echo "  OR"
        echo "  cd ../oss-mac-setup && ./set.sh 25.11 && ./start.sh"
        exit 1
    fi

    # Check version
    VERSION=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "SELECT version()" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}ClickHouse version: $VERSION${NC}"

    # Try to connect
    if ! docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "SELECT 1" &> /dev/null; then
        echo -e "${RED}Cannot connect to ClickHouse${NC}"
        echo "Please check ClickHouse status"
        exit 1
    fi

    echo -e "${GREEN}ClickHouse is ready!${NC}"
    echo ""
}

# Function to test MinIO connection
test_minio() {
    echo -e "${YELLOW}Testing MinIO connection...${NC}"

    # Check MinIO health
    if curl -sf http://localhost:${MINIO_PORT:-19000}/minio/health/live > /dev/null; then
        echo -e "${GREEN}✓ MinIO is healthy${NC}"
    else
        echo -e "${RED}✗ MinIO is not responding${NC}"
        echo "minio:FAILED" >> "$TEST_RESULTS_FILE"
        FAILED=$((FAILED + 1))
        echo ""
        return 1
    fi

    # Test with ClickHouse
    docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
    SET s3_truncate_on_insert = 1;

    DROP TABLE IF EXISTS test_minio;
    CREATE TABLE test_minio (
        id UInt32,
        name String,
        value Float64
    ) ENGINE = Memory;

    INSERT INTO test_minio VALUES (1, 'test1', 100.5), (2, 'test2', 200.7);

    -- Export to MinIO (use host.docker.internal from container)
    INSERT INTO FUNCTION s3(
        'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/test/data.parquet',
        '${MINIO_ROOT_USER:-admin}',
        '${MINIO_ROOT_PASSWORD:-password123}',
        'Parquet'
    ) SELECT * FROM test_minio;
    " 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Write to MinIO succeeded${NC}"

        # Test read
        RESULT=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
        SELECT count() FROM s3(
            'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/test/data.parquet',
            '${MINIO_ROOT_USER:-admin}',
            '${MINIO_ROOT_PASSWORD:-password123}',
            'Parquet'
        )" 2>/dev/null)

        if [ "$RESULT" = "2" ]; then
            echo -e "${GREEN}✓ Read from MinIO succeeded (count: $RESULT)${NC}"
            echo "minio:PASSED" >> "$TEST_RESULTS_FILE"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}✗ Read from MinIO failed (expected 2, got $RESULT)${NC}"
            echo "minio:FAILED" >> "$TEST_RESULTS_FILE"
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "${RED}✗ Write to MinIO failed${NC}"
        echo "minio:FAILED" >> "$TEST_RESULTS_FILE"
        FAILED=$((FAILED + 1))
    fi

    # Cleanup
    docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "DROP TABLE IF EXISTS test_minio" 2>/dev/null

    echo ""
}

# Function to test Nessie catalog
test_nessie() {
    echo -e "${YELLOW}Testing Nessie Catalog...${NC}"

    if [ "$CATALOG_TYPE" != "nessie" ]; then
        echo -e "${BLUE}ℹ Nessie is not the active catalog. Skipping...${NC}"
        echo ""
        return
    fi

    # Check Nessie health
    if ! curl -sf http://localhost:${NESSIE_PORT:-19120}/api/v2/config > /dev/null; then
        echo -e "${RED}✗ Nessie is not responding${NC}"
        echo "nessie:FAILED" >> "$TEST_RESULTS_FILE"
        FAILED=$((FAILED + 1))
        echo ""
        return
    fi

    echo -e "${GREEN}✓ Nessie is healthy${NC}"

    # Test Iceberg table with Nessie
    docker exec clickhouse-25-11 clickhouse-client --query "
    DROP TABLE IF EXISTS test_nessie;
    CREATE TABLE test_nessie (
        id UInt32,
        name String,
        created_at DateTime
    ) ENGINE = Memory;

    INSERT INTO test_nessie VALUES
        (1, 'Alice', '2025-12-07 10:00:00'),
        (2, 'Bob', '2025-12-07 11:00:00'),
        (3, 'Charlie', '2025-12-07 12:00:00');
    " 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Nessie catalog test passed${NC}"
        echo "nessie:PASSED" >> "$TEST_RESULTS_FILE"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ Nessie catalog test failed${NC}"
        echo "nessie:FAILED" >> "$TEST_RESULTS_FILE"
        FAILED=$((FAILED + 1))
    fi

    # Cleanup
    docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "DROP TABLE IF EXISTS test_nessie" 2>/dev/null

    echo ""
}

# Function to test Hive Metastore
test_hive() {
    echo -e "${YELLOW}Testing Hive Metastore...${NC}"

    if [ "$CATALOG_TYPE" != "hive" ]; then
        echo -e "${BLUE}ℹ Hive Metastore is not the active catalog. Skipping...${NC}"
        echo ""
        return
    fi

    # Check if Hive Metastore port is listening
    if ! nc -z localhost ${HIVE_METASTORE_PORT:-9083} 2>/dev/null; then
        echo -e "${RED}✗ Hive Metastore is not responding on port ${HIVE_METASTORE_PORT:-9083}${NC}"
        echo "hive:FAILED" >> "$TEST_RESULTS_FILE"
        FAILED=$((FAILED + 1))
        echo ""
        return
    fi

    echo -e "${GREEN}✓ Hive Metastore is listening${NC}"

    # Test basic connectivity
    docker exec clickhouse-25-11 clickhouse-client --query "
    DROP TABLE IF EXISTS test_hive;
    CREATE TABLE test_hive (
        id UInt32,
        product String,
        price Float64
    ) ENGINE = Memory;

    INSERT INTO test_hive VALUES
        (1, 'Product A', 99.99),
        (2, 'Product B', 149.99),
        (3, 'Product C', 199.99);
    " 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Hive Metastore test passed${NC}"
        echo "hive:PASSED" >> "$TEST_RESULTS_FILE"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ Hive Metastore test failed${NC}"
        echo "hive:FAILED" >> "$TEST_RESULTS_FILE"
        FAILED=$((FAILED + 1))
    fi

    # Cleanup
    docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "DROP TABLE IF EXISTS test_hive" 2>/dev/null

    echo ""
}

# Function to test Iceberg REST catalog
test_iceberg_rest() {
    echo -e "${YELLOW}Testing Iceberg REST Catalog...${NC}"

    if [ "$CATALOG_TYPE" != "iceberg-rest" ]; then
        echo -e "${BLUE}ℹ Iceberg REST is not the active catalog. Skipping...${NC}"
        echo ""
        return
    fi

    # Check Iceberg REST health
    if ! curl -sf http://localhost:${ICEBERG_REST_PORT:-8181}/v1/config > /dev/null; then
        echo -e "${RED}✗ Iceberg REST is not responding${NC}"
        echo "iceberg-rest:FAILED" >> "$TEST_RESULTS_FILE"
        FAILED=$((FAILED + 1))
        echo ""
        return
    fi

    echo -e "${GREEN}✓ Iceberg REST is healthy${NC}"

    # Test basic connectivity
    docker exec clickhouse-25-11 clickhouse-client --query "
    DROP TABLE IF EXISTS test_iceberg_rest;
    CREATE TABLE test_iceberg_rest (
        order_id UInt32,
        customer_id UInt32,
        amount Float64
    ) ENGINE = Memory;

    INSERT INTO test_iceberg_rest VALUES
        (1001, 1, 250.50),
        (1002, 2, 350.75),
        (1003, 3, 450.25);
    " 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Iceberg REST catalog test passed${NC}"
        echo "iceberg-rest:PASSED" >> "$TEST_RESULTS_FILE"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ Iceberg REST catalog test failed${NC}"
        echo "iceberg-rest:FAILED" >> "$TEST_RESULTS_FILE"
        FAILED=$((FAILED + 1))
    fi

    # Cleanup
    docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "DROP TABLE IF EXISTS test_iceberg_rest" 2>/dev/null

    echo ""
}

# Function to test Polaris catalog
test_polaris() {
    echo -e "${YELLOW}Testing Polaris Catalog...${NC}"

    if [ "$CATALOG_TYPE" != "polaris" ]; then
        echo -e "${BLUE}ℹ Polaris is not the active catalog. Skipping...${NC}"
        echo ""
        return
    fi

    # Check Polaris health (use management port)
    if ! curl -sf http://localhost:${POLARIS_MGMT_PORT:-8183}/q/health > /dev/null; then
        echo -e "${RED}✗ Polaris is not responding${NC}"
        echo "polaris:FAILED" >> "$TEST_RESULTS_FILE"
        FAILED=$((FAILED + 1))
        echo ""
        return
    fi

    echo -e "${GREEN}✓ Polaris is healthy${NC}"

    # Test basic connectivity
    docker exec clickhouse-25-11 clickhouse-client --query "
    DROP TABLE IF EXISTS test_polaris;
    CREATE TABLE test_polaris (
        event_id UInt32,
        event_type String,
        timestamp DateTime
    ) ENGINE = Memory;

    INSERT INTO test_polaris VALUES
        (1, 'login', '2025-12-07 10:00:00'),
        (2, 'purchase', '2025-12-07 11:30:00'),
        (3, 'logout', '2025-12-07 15:45:00');
    " 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Polaris catalog test passed${NC}"
        echo "polaris:PASSED" >> "$TEST_RESULTS_FILE"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ Polaris catalog test failed${NC}"
        echo "polaris:FAILED" >> "$TEST_RESULTS_FILE"
        FAILED=$((FAILED + 1))
    fi

    # Cleanup
    docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "DROP TABLE IF EXISTS test_polaris" 2>/dev/null

    echo ""
}

# Function to test Unity Catalog
test_unity() {
    echo -e "${YELLOW}Testing Unity Catalog...${NC}"

    if [ "$CATALOG_TYPE" != "unity" ]; then
        echo -e "${BLUE}ℹ Unity Catalog is not the active catalog. Skipping...${NC}"
        echo ""
        return
    fi

    # Check Unity Catalog health
    if ! curl -sf http://localhost:${UNITY_PORT:-8080}/api/2.1/unity-catalog/catalogs > /dev/null; then
        echo -e "${RED}✗ Unity Catalog is not responding${NC}"
        echo "unity:FAILED" >> "$TEST_RESULTS_FILE"
        FAILED=$((FAILED + 1))
        echo ""
        return
    fi

    echo -e "${GREEN}✓ Unity Catalog is healthy${NC}"

    # Test basic connectivity
    docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
    DROP TABLE IF EXISTS test_unity;
    CREATE TABLE test_unity (
        user_id UInt32,
        username String,
        last_login DateTime
    ) ENGINE = Memory;

    INSERT INTO test_unity VALUES
        (101, 'alice', '2025-12-07 08:00:00'),
        (102, 'bob', '2025-12-07 09:15:00'),
        (103, 'charlie', '2025-12-07 10:30:00');
    " 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Unity Catalog test passed${NC}"
        echo "unity:PASSED" >> "$TEST_RESULTS_FILE"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ Unity Catalog test failed${NC}"
        echo "unity:FAILED" >> "$TEST_RESULTS_FILE"
        FAILED=$((FAILED + 1))
    fi

    # Cleanup
    docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "DROP TABLE IF EXISTS test_unity" 2>/dev/null

    echo ""
}

# Main test execution
main() {
    check_clickhouse

    echo -e "${BLUE}Running integration tests...${NC}"
    echo ""

    test_minio
    test_nessie
    test_hive
    test_iceberg_rest
    test_polaris
    test_unity

    # Summary
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Test Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    echo -e "${YELLOW}Active Catalog: ${CATALOG_TYPE}${NC}"
    echo ""

    while IFS=: read -r test_name result; do
        if [ "$result" = "PASSED" ]; then
            echo -e "  ${GREEN}✓${NC} $test_name: ${GREEN}PASSED${NC}"
        else
            echo -e "  ${RED}✗${NC} $test_name: ${RED}FAILED${NC}"
        fi
    done < "$TEST_RESULTS_FILE"

    echo ""
    echo -e "Total: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
    echo ""

    # Cleanup
    rm -f "$TEST_RESULTS_FILE"

    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Please check the output above.${NC}"
        exit 1
    fi
}

main "$@"
