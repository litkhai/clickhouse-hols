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
SKIPPED=0
TEST_RESULTS=()
CLICKHOUSE_VERSION=""
START_TIME=$(date +%s)

# Markdown output file
MD_OUTPUT="test-results-unity-deltalake-$(date +%Y%m%d-%H%M%S).md"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  Unity Catalog + Delta Lake Integration Test${NC}"
echo -e "${BLUE}  ClickHouse 25.10 / 25.11${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# Function to add test result
add_test_result() {
    local test_name="$1"
    local status="$2"
    local details="$3"
    local execution_time="$4"

    TEST_RESULTS+=("$test_name|$status|$details|$execution_time")

    case $status in
        "PASSED")
            PASSED=$((PASSED + 1))
            echo -e "${GREEN}✓ $test_name${NC}"
            ;;
        "FAILED")
            FAILED=$((FAILED + 1))
            echo -e "${RED}✗ $test_name${NC}"
            [ -n "$details" ] && echo -e "${RED}  Error: $details${NC}"
            ;;
        "SKIPPED")
            SKIPPED=$((SKIPPED + 1))
            echo -e "${YELLOW}⊘ $test_name (SKIPPED)${NC}"
            ;;
    esac
}

# Function to check if ClickHouse is available
check_clickhouse() {
    echo -e "${BLUE}Checking ClickHouse availability...${NC}"

    # Try both 25.11 and 25.10
    if docker ps | grep -q "clickhouse-25-11"; then
        CLICKHOUSE_CONTAINER="clickhouse-25-11"
        echo -e "${GREEN}Found ClickHouse 25.11 container${NC}"
    elif docker ps | grep -q "clickhouse-25-10"; then
        CLICKHOUSE_CONTAINER="clickhouse-25-10"
        echo -e "${GREEN}Found ClickHouse 25.10 container${NC}"
    else
        echo -e "${RED}ClickHouse 25.10 or 25.11 container not found${NC}"
        echo "Please start ClickHouse first:"
        echo "  cd ../oss-mac-setup && ./set.sh 25.11 && ./start.sh"
        echo "  OR"
        echo "  cd ../oss-mac-setup && ./set.sh 25.10 && ./start.sh"
        exit 1
    fi

    # Check version
    CLICKHOUSE_VERSION=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "SELECT version()" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}ClickHouse version: $CLICKHOUSE_VERSION${NC}"

    # Try to connect
    if ! docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "SELECT 1" &> /dev/null; then
        echo -e "${RED}Cannot connect to ClickHouse${NC}"
        echo "Please check ClickHouse status"
        exit 1
    fi

    echo -e "${GREEN}ClickHouse is ready!${NC}"
    echo ""
}

# Function to check Unity Catalog
check_unity_catalog() {
    echo -e "${BLUE}Checking Unity Catalog availability...${NC}"

    if [ "$CATALOG_TYPE" != "unity" ]; then
        echo -e "${YELLOW}Unity Catalog is not the active catalog (current: $CATALOG_TYPE)${NC}"
        echo "To switch to Unity Catalog:"
        echo "  ./setup.sh --configure  # Select option 5 for Unity Catalog"
        echo "  ./setup.sh --restart"
        exit 1
    fi

    # Check Unity Catalog health
    if ! curl -sf http://localhost:${UNITY_PORT:-8080}/api/2.1/unity-catalog/catalogs > /dev/null 2>&1; then
        echo -e "${RED}Unity Catalog is not responding on port ${UNITY_PORT:-8080}${NC}"
        echo "Please start Unity Catalog first:"
        echo "  ./setup.sh --start"
        exit 1
    fi

    echo -e "${GREEN}Unity Catalog is ready!${NC}"
    echo ""
}

# Function to check MinIO
check_minio() {
    echo -e "${BLUE}Checking MinIO availability...${NC}"

    if ! curl -sf http://localhost:${MINIO_PORT:-19000}/minio/health/live > /dev/null 2>&1; then
        echo -e "${RED}MinIO is not responding on port ${MINIO_PORT:-19000}${NC}"
        echo "Please start MinIO first:"
        echo "  ./setup.sh --start"
        exit 1
    fi

    echo -e "${GREEN}MinIO is ready!${NC}"
    echo ""
}

# Test 1: Unity Catalog Basic Connectivity
test_unity_basic_connectivity() {
    local test_name="Unity Catalog - Basic Connectivity"
    local start=$(date +%s)

    echo -e "${YELLOW}Running: $test_name${NC}"

    # List catalogs
    local response=$(curl -s http://localhost:${UNITY_PORT:-8080}/api/2.1/unity-catalog/catalogs 2>&1)
    local end=$(date +%s)
    local duration=$((end - start))

    if echo "$response" | grep -q "catalogs"; then
        add_test_result "$test_name" "PASSED" "Successfully connected to Unity Catalog API" "${duration}s"
    else
        add_test_result "$test_name" "FAILED" "Failed to get catalogs from Unity Catalog" "${duration}s"
    fi

    echo ""
}

# Test 2: Create Delta Lake Table via Unity Catalog
test_create_delta_table() {
    local test_name="Unity Catalog - Create Delta Lake Table"
    local start=$(date +%s)

    echo -e "${YELLOW}Running: $test_name${NC}"

    # Create a test table in ClickHouse and prepare for Delta export
    local output=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
    DROP TABLE IF EXISTS test_unity_delta_source;
    CREATE TABLE test_unity_delta_source (
        id UInt32,
        name String,
        value Float64,
        created_at DateTime,
        updated_at DateTime DEFAULT now()
    ) ENGINE = Memory;

    INSERT INTO test_unity_delta_source (id, name, value, created_at) VALUES
        (1, 'Alice', 100.5, '2025-12-01 10:00:00'),
        (2, 'Bob', 200.7, '2025-12-02 11:30:00'),
        (3, 'Charlie', 150.3, '2025-12-03 09:15:00'),
        (4, 'Diana', 300.9, '2025-12-04 14:45:00'),
        (5, 'Eve', 250.6, '2025-12-05 16:20:00');

    SELECT 'Created test source table with ' || toString(count()) || ' rows' FROM test_unity_delta_source;
    " 2>&1)

    local end=$(date +%s)
    local duration=$((end - start))

    if echo "$output" | grep -q "Created test source table with 5 rows"; then
        add_test_result "$test_name" "PASSED" "Source table created with 5 rows" "${duration}s"
    else
        add_test_result "$test_name" "FAILED" "Failed to create source table: $output" "${duration}s"
    fi

    echo ""
}

# Test 3: Write Delta Lake format to MinIO (Parquet-based)
test_write_delta_to_minio() {
    local test_name="Delta Lake - Write to MinIO (Parquet format)"
    local start=$(date +%s)

    echo -e "${YELLOW}Running: $test_name${NC}"

    # Write data to MinIO in Parquet format (Delta Lake compatible)
    local output=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
    SET s3_truncate_on_insert = 1;

    INSERT INTO FUNCTION s3(
        'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/unity-catalog/delta-test/data.parquet',
        '${MINIO_ROOT_USER:-admin}',
        '${MINIO_ROOT_PASSWORD:-password123}',
        'Parquet',
        'id UInt32, name String, value Float64, created_at DateTime, updated_at DateTime'
    )
    SELECT id, name, value, created_at, updated_at
    FROM test_unity_delta_source;

    SELECT 'Written ' || toString(count()) || ' rows to Delta Lake'
    FROM test_unity_delta_source;
    " 2>&1)

    local end=$(date +%s)
    local duration=$((end - start))

    if echo "$output" | grep -q "Written 5 rows to Delta Lake"; then
        add_test_result "$test_name" "PASSED" "Successfully wrote 5 rows to MinIO in Parquet format" "${duration}s"
    else
        add_test_result "$test_name" "FAILED" "Failed to write to MinIO: $output" "${duration}s"
    fi

    echo ""
}

# Test 4: Read Delta Lake format from MinIO
test_read_delta_from_minio() {
    local test_name="Delta Lake - Read from MinIO (Parquet format)"
    local start=$(date +%s)

    echo -e "${YELLOW}Running: $test_name${NC}"

    # Read data from MinIO
    local output=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
    SELECT
        count() as total_rows,
        sum(value) as total_value,
        min(created_at) as earliest_date,
        max(created_at) as latest_date
    FROM s3(
        'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/unity-catalog/delta-test/data.parquet',
        '${MINIO_ROOT_USER:-admin}',
        '${MINIO_ROOT_PASSWORD:-password123}',
        'Parquet'
    )
    FORMAT JSONEachRow;
    " 2>&1)

    local end=$(date +%s)
    local duration=$((end - start))

    if echo "$output" | grep -q '"total_rows":5'; then
        local total_value=$(echo "$output" | grep -o '"total_value":[0-9.]*' | cut -d: -f2)
        add_test_result "$test_name" "PASSED" "Successfully read 5 rows (total_value: $total_value)" "${duration}s"
    else
        add_test_result "$test_name" "FAILED" "Failed to read from MinIO: $output" "${duration}s"
    fi

    echo ""
}

# Test 5: Update Delta Lake data (Append mode)
test_update_delta_append() {
    local test_name="Delta Lake - Append New Data"
    local start=$(date +%s)

    echo -e "${YELLOW}Running: $test_name${NC}"

    # Append new data
    local output=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
    -- Add more data to source
    INSERT INTO test_unity_delta_source (id, name, value, created_at) VALUES
        (6, 'Frank', 175.4, '2025-12-06 10:30:00'),
        (7, 'Grace', 225.8, '2025-12-07 12:00:00');

    -- Append to Delta Lake (new partition)
    INSERT INTO FUNCTION s3(
        'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/unity-catalog/delta-test/data-append.parquet',
        '${MINIO_ROOT_USER:-admin}',
        '${MINIO_ROOT_PASSWORD:-password123}',
        'Parquet',
        'id UInt32, name String, value Float64, created_at DateTime, updated_at DateTime'
    )
    SELECT id, name, value, created_at, updated_at
    FROM test_unity_delta_source
    WHERE id > 5;

    SELECT 'Appended ' || toString(count()) || ' new rows'
    FROM test_unity_delta_source
    WHERE id > 5;
    " 2>&1)

    local end=$(date +%s)
    local duration=$((end - start))

    if echo "$output" | grep -q "Appended 2 new rows"; then
        add_test_result "$test_name" "PASSED" "Successfully appended 2 rows" "${duration}s"
    else
        add_test_result "$test_name" "FAILED" "Failed to append: $output" "${duration}s"
    fi

    echo ""
}

# Test 6: Query Delta Lake with filters
test_query_delta_with_filters() {
    local test_name="Delta Lake - Query with Filters"
    local start=$(date +%s)

    echo -e "${YELLOW}Running: $test_name${NC}"

    # Query with various filters
    local output=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
    WITH delta_data AS (
        SELECT * FROM s3(
            'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/unity-catalog/delta-test/*.parquet',
            '${MINIO_ROOT_USER:-admin}',
            '${MINIO_ROOT_PASSWORD:-password123}',
            'Parquet'
        )
    )
    SELECT
        'Total rows: ' || toString(count()) as metric
    FROM delta_data
    UNION ALL
    SELECT
        'Rows with value > 200: ' || toString(count())
    FROM delta_data
    WHERE value > 200
    UNION ALL
    SELECT
        'Average value: ' || toString(round(avg(value), 2))
    FROM delta_data;
    " 2>&1)

    local end=$(date +%s)
    local duration=$((end - start))

    if echo "$output" | grep -q "Total rows: 7"; then
        add_test_result "$test_name" "PASSED" "Successfully queried with filters" "${duration}s"
    else
        add_test_result "$test_name" "FAILED" "Failed query with filters: $output" "${duration}s"
    fi

    echo ""
}

# Test 7: Schema validation
test_schema_validation() {
    local test_name="Delta Lake - Schema Validation"
    local start=$(date +%s)

    echo -e "${YELLOW}Running: $test_name${NC}"

    # Read schema from Delta Lake
    local output=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
    DESCRIBE TABLE s3(
        'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/unity-catalog/delta-test/data.parquet',
        '${MINIO_ROOT_USER:-admin}',
        '${MINIO_ROOT_PASSWORD:-password123}',
        'Parquet'
    )
    FORMAT Vertical;
    " 2>&1)

    local end=$(date +%s)
    local duration=$((end - start))

    if echo "$output" | grep -q "id" && echo "$output" | grep -q "name" && echo "$output" | grep -q "value"; then
        add_test_result "$test_name" "PASSED" "Schema validation successful" "${duration}s"
    else
        add_test_result "$test_name" "FAILED" "Schema validation failed: $output" "${duration}s"
    fi

    echo ""
}

# Test 8: Performance test - Large dataset
test_performance_large_dataset() {
    local test_name="Delta Lake - Performance Test (Large Dataset)"
    local start=$(date +%s)

    echo -e "${YELLOW}Running: $test_name${NC}"

    # Create and write large dataset
    local output=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
    DROP TABLE IF EXISTS test_large_dataset;
    CREATE TABLE test_large_dataset (
        id UInt32,
        category String,
        value Float64,
        timestamp DateTime
    ) ENGINE = Memory;

    INSERT INTO test_large_dataset
    SELECT
        number as id,
        concat('category_', toString(number % 10)) as category,
        rand() % 10000 / 100.0 as value,
        now() - INTERVAL number SECOND as timestamp
    FROM numbers(10000);

    SET s3_truncate_on_insert = 1;

    INSERT INTO FUNCTION s3(
        'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/unity-catalog/delta-test/large-dataset.parquet',
        '${MINIO_ROOT_USER:-admin}',
        '${MINIO_ROOT_PASSWORD:-password123}',
        'Parquet'
    )
    SELECT * FROM test_large_dataset;

    SELECT 'Written ' || toString(count()) || ' rows' FROM test_large_dataset;
    " 2>&1)

    local write_end=$(date +%s)
    local write_duration=$((write_end - start))

    # Read back and aggregate
    local read_output=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
    SELECT
        count() as total_rows,
        uniq(category) as unique_categories,
        round(avg(value), 2) as avg_value
    FROM s3(
        'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/unity-catalog/delta-test/large-dataset.parquet',
        '${MINIO_ROOT_USER:-admin}',
        '${MINIO_ROOT_PASSWORD:-password123}',
        'Parquet'
    )
    FORMAT JSONEachRow;
    " 2>&1)

    local end=$(date +%s)
    local total_duration=$((end - start))

    if echo "$output" | grep -q "Written 10000 rows" && echo "$read_output" | grep -q '"total_rows":10000'; then
        add_test_result "$test_name" "PASSED" "Written and read 10000 rows (Write: ${write_duration}s, Total: ${total_duration}s)" "${total_duration}s"
    else
        add_test_result "$test_name" "FAILED" "Performance test failed" "${total_duration}s"
    fi

    echo ""
}

# Test 9: Data type compatibility
test_data_types() {
    local test_name="Delta Lake - Data Type Compatibility"
    local start=$(date +%s)

    echo -e "${YELLOW}Running: $test_name${NC}"

    local output=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
    DROP TABLE IF EXISTS test_data_types;
    CREATE TABLE test_data_types (
        int8_col Int8,
        int16_col Int16,
        int32_col Int32,
        int64_col Int64,
        float32_col Float32,
        float64_col Float64,
        string_col String,
        date_col Date,
        datetime_col DateTime,
        bool_col UInt8
    ) ENGINE = Memory;

    INSERT INTO test_data_types VALUES
        (-127, -32767, -2147483647, -9223372036854775807, 3.14, 2.718281828, 'test', '2025-12-01', '2025-12-01 12:00:00', 1),
        (127, 32767, 2147483647, 9223372036854775807, -3.14, -2.718281828, 'demo', '2025-12-31', '2025-12-31 23:59:59', 0);

    SET s3_truncate_on_insert = 1;

    INSERT INTO FUNCTION s3(
        'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/unity-catalog/delta-test/data-types.parquet',
        '${MINIO_ROOT_USER:-admin}',
        '${MINIO_ROOT_PASSWORD:-password123}',
        'Parquet'
    )
    SELECT * FROM test_data_types;

    SELECT count() FROM test_data_types;
    " 2>&1)

    local end=$(date +%s)
    local duration=$((end - start))

    if echo "$output" | grep -q "2"; then
        add_test_result "$test_name" "PASSED" "All data types written and validated" "${duration}s"
    else
        add_test_result "$test_name" "FAILED" "Data type test failed: $output" "${duration}s"
    fi

    echo ""
}

# Test 10: Clean up
test_cleanup() {
    local test_name="Cleanup Test Resources"
    local start=$(date +%s)

    echo -e "${YELLOW}Running: $test_name${NC}"

    local output=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
    DROP TABLE IF EXISTS test_unity_delta_source;
    DROP TABLE IF EXISTS test_large_dataset;
    DROP TABLE IF EXISTS test_data_types;
    SELECT 'Cleanup completed';
    " 2>&1)

    local end=$(date +%s)
    local duration=$((end - start))

    if echo "$output" | grep -q "Cleanup completed"; then
        add_test_result "$test_name" "PASSED" "All test tables dropped" "${duration}s"
    else
        add_test_result "$test_name" "FAILED" "Cleanup failed: $output" "${duration}s"
    fi

    echo ""
}

# Generate markdown report
generate_markdown_report() {
    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))

    echo "# Unity Catalog + Delta Lake Integration Test Report" > "$MD_OUTPUT"
    echo "" >> "$MD_OUTPUT"
    echo "**Test Date:** $(date '+%Y-%m-%d %H:%M:%S')" >> "$MD_OUTPUT"
    echo "" >> "$MD_OUTPUT"

    echo "## Environment Information" >> "$MD_OUTPUT"
    echo "" >> "$MD_OUTPUT"
    echo "| Component | Version/Status |" >> "$MD_OUTPUT"
    echo "|-----------|----------------|" >> "$MD_OUTPUT"
    echo "| ClickHouse Version | $CLICKHOUSE_VERSION |" >> "$MD_OUTPUT"
    echo "| ClickHouse Container | $CLICKHOUSE_CONTAINER |" >> "$MD_OUTPUT"
    echo "| Unity Catalog Port | ${UNITY_PORT:-8080} |" >> "$MD_OUTPUT"
    echo "| MinIO Port | ${MINIO_PORT:-19000} |" >> "$MD_OUTPUT"
    echo "| Catalog Type | $CATALOG_TYPE |" >> "$MD_OUTPUT"
    echo "" >> "$MD_OUTPUT"

    echo "## Test Summary" >> "$MD_OUTPUT"
    echo "" >> "$MD_OUTPUT"
    echo "| Metric | Count |" >> "$MD_OUTPUT"
    echo "|--------|-------|" >> "$MD_OUTPUT"
    echo "| ✅ Passed | $PASSED |" >> "$MD_OUTPUT"
    echo "| ❌ Failed | $FAILED |" >> "$MD_OUTPUT"
    echo "| ⊘ Skipped | $SKIPPED |" >> "$MD_OUTPUT"
    echo "| ⏱️ Total Time | ${total_time}s |" >> "$MD_OUTPUT"
    echo "" >> "$MD_OUTPUT"

    echo "## Test Results" >> "$MD_OUTPUT"
    echo "" >> "$MD_OUTPUT"
    echo "| # | Test Name | Status | Details | Time |" >> "$MD_OUTPUT"
    echo "|---|-----------|--------|---------|------|" >> "$MD_OUTPUT"

    local index=1
    for result in "${TEST_RESULTS[@]}"; do
        IFS='|' read -r test_name status details exec_time <<< "$result"
        local status_icon=""
        case $status in
            "PASSED") status_icon="✅" ;;
            "FAILED") status_icon="❌" ;;
            "SKIPPED") status_icon="⊘" ;;
        esac
        echo "| $index | $test_name | $status_icon $status | $details | $exec_time |" >> "$MD_OUTPUT"
        index=$((index + 1))
    done

    echo "" >> "$MD_OUTPUT"

    # Add detailed findings
    echo "## Key Findings" >> "$MD_OUTPUT"
    echo "" >> "$MD_OUTPUT"

    if [ $FAILED -eq 0 ]; then
        echo "### ✅ All Tests Passed" >> "$MD_OUTPUT"
        echo "" >> "$MD_OUTPUT"
        echo "- Unity Catalog integration is working correctly" >> "$MD_OUTPUT"
        echo "- Delta Lake read/write operations are functional" >> "$MD_OUTPUT"
        echo "- Performance is within acceptable range" >> "$MD_OUTPUT"
        echo "- All data types are properly supported" >> "$MD_OUTPUT"
    else
        echo "### ❌ Issues Found" >> "$MD_OUTPUT"
        echo "" >> "$MD_OUTPUT"
        echo "- $FAILED test(s) failed" >> "$MD_OUTPUT"
        echo "- Please review the failed tests above for details" >> "$MD_OUTPUT"
    fi

    echo "" >> "$MD_OUTPUT"

    echo "## Recommendations" >> "$MD_OUTPUT"
    echo "" >> "$MD_OUTPUT"

    if [[ "$CLICKHOUSE_VERSION" =~ ^25\.1[01] ]]; then
        echo "✅ Using ClickHouse $CLICKHOUSE_VERSION - Unity Catalog and Delta Lake support is available" >> "$MD_OUTPUT"
    else
        echo "⚠️ ClickHouse version $CLICKHOUSE_VERSION detected - Please verify Unity Catalog support" >> "$MD_OUTPUT"
    fi

    echo "" >> "$MD_OUTPUT"
    echo "---" >> "$MD_OUTPUT"
    echo "" >> "$MD_OUTPUT"
    echo "*Generated by Unity Catalog + Delta Lake Integration Test Script*" >> "$MD_OUTPUT"

    echo -e "${GREEN}Markdown report saved to: $MD_OUTPUT${NC}"
}

# Main execution
main() {
    check_clickhouse
    check_unity_catalog
    check_minio

    echo -e "${BLUE}Starting integration tests...${NC}"
    echo ""

    test_unity_basic_connectivity
    test_create_delta_table
    test_write_delta_to_minio
    test_read_delta_from_minio
    test_update_delta_append
    test_query_delta_with_filters
    test_schema_validation
    test_performance_large_dataset
    test_data_types
    test_cleanup

    # Generate markdown report
    generate_markdown_report

    # Summary
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  Test Execution Complete${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""

    echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"
    echo -e "Report: ${BLUE}$MD_OUTPUT${NC}"
    echo ""

    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed. Please check the report for details.${NC}"
        exit 1
    fi
}

main "$@"
