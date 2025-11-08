#!/bin/bash

#################################################
# TPC-DS Parallel Query Execution Script
# Runs TPC-DS queries in parallel for performance testing
#################################################

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Error: config.sh not found. Please create it from 00-set.sh"
    exit 1
fi

# Default values
OUTPUT_DIR="$RESULTS_DIR/parallel"
ITERATIONS=${QUERY_ITERATIONS:-3}
QUERY_PATTERN="*"
WARMUP=false
PARALLEL=${PARALLEL_JOBS:-4}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run TPC-DS queries in parallel for performance testing.

OPTIONS:
    --queries PATTERN      Run specific queries (e.g., "query01,query05" or "query*")
                          Default: all queries
    --iterations N        Run each query N times (default: $ITERATIONS)
    --parallel N          Number of parallel query executions (default: $PARALLEL)
    --output DIR         Output directory for results (default: $OUTPUT_DIR)
    --warmup             Run queries once before measuring (cache warmup)
    --power-test         Run power test (each query once, sequential)
    --throughput-test    Run throughput test (queries in parallel streams)
    -h, --help          Show this help message

EXAMPLES:
    # Run queries with 4 parallel streams
    $0 --parallel 4

    # Run specific queries in parallel 10 times each
    $0 --queries "query01,query05,query10" --parallel 8 --iterations 10

    # Run power test (standard TPC-DS)
    $0 --power-test

    # Run throughput test (standard TPC-DS)
    $0 --throughput-test --parallel 4

NOTES:
    - Power test: Runs all queries sequentially once to measure single-stream performance
    - Throughput test: Runs queries in parallel streams to measure multi-stream performance
    - Default mode: Runs all queries in parallel with specified iterations

EOF
    exit 1
}

# Parse arguments
POWER_TEST=false
THROUGHPUT_TEST=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --queries)
            QUERY_PATTERN="$2"
            shift 2
            ;;
        --iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --warmup)
            WARMUP=true
            shift
            ;;
        --power-test)
            POWER_TEST=true
            shift
            ;;
        --throughput-test)
            THROUGHPUT_TEST=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Initialize
ensure_directory "$OUTPUT_DIR"
log "INFO" "Starting parallel query execution"

# Test connection
log "INFO" "Testing ClickHouse connection..."
if ! test_connection; then
    log "ERROR" "Failed to connect to ClickHouse"
    exit 1
fi

# Check if database exists
DB_EXISTS=$(execute_query "EXISTS DATABASE $CLICKHOUSE_DATABASE" "default" || echo "0")
if [ "$DB_EXISTS" = "0" ]; then
    log "ERROR" "Database $CLICKHOUSE_DATABASE does not exist. Run setup scripts first."
    exit 1
fi

# Get list of queries
if [ ! -d "$QUERIES_DIR" ]; then
    log "ERROR" "Queries directory not found: $QUERIES_DIR"
    ensure_directory "$QUERIES_DIR"
    exit 1
fi

# Build query list
QUERY_FILES=()
if [[ "$QUERY_PATTERN" == *","* ]]; then
    IFS=',' read -ra PATTERNS <<< "$QUERY_PATTERN"
    for pattern in "${PATTERNS[@]}"; do
        pattern=$(echo "$pattern" | xargs)
        if [ -f "$QUERIES_DIR/${pattern}.sql" ]; then
            QUERY_FILES+=("$QUERIES_DIR/${pattern}.sql")
        fi
    done
else
    for file in "$QUERIES_DIR"/$QUERY_PATTERN.sql; do
        if [ -f "$file" ]; then
            QUERY_FILES+=("$file")
        fi
    done
fi

if [ ${#QUERY_FILES[@]} -eq 0 ]; then
    log "ERROR" "No query files found matching pattern: $QUERY_PATTERN"
    exit 1
fi

IFS=$'\n' QUERY_FILES=($(sort <<<"${QUERY_FILES[*]}"))
unset IFS

log "INFO" "Found ${#QUERY_FILES[@]} query files"
log "INFO" "Parallel streams: $PARALLEL"
log "INFO" "Iterations per query: $ITERATIONS"

# Create results file
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RESULTS_FILE="$OUTPUT_DIR/results_${TIMESTAMP}.csv"
SUMMARY_FILE="$OUTPUT_DIR/summary_${TIMESTAMP}.txt"
DETAILED_FILE="$OUTPUT_DIR/detailed_${TIMESTAMP}.log"

echo "timestamp,query,stream,iteration,status,duration_ms,rows_returned" > "$RESULTS_FILE"

echo ""
echo "========================================"
echo "TPC-DS Parallel Query Execution"
echo "========================================"
echo "Database: $CLICKHOUSE_DATABASE"
echo "Queries: ${#QUERY_FILES[@]}"
echo "Parallel Streams: $PARALLEL"
echo "Iterations: $ITERATIONS"
echo "Output: $OUTPUT_DIR"
echo ""

# Function to execute a query in background
execute_query_background() {
    local query_file="$1"
    local stream="$2"
    local iteration="$3"
    local query_name=$(basename "$query_file" .sql)

    local start_time=$(date +%s%N)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local output_file="$OUTPUT_DIR/${query_name}_stream${stream}_iter${iteration}_${TIMESTAMP}.out"
    local error_file="$OUTPUT_DIR/${query_name}_stream${stream}_iter${iteration}_${TIMESTAMP}.err"

    set +e
    $CLICKHOUSE_CLIENT \
        --host="$CLICKHOUSE_HOST" \
        --port="$CLICKHOUSE_PORT" \
        --user="$CLICKHOUSE_USER" \
        --password="$CLICKHOUSE_PASSWORD" \
        --database="$CLICKHOUSE_DATABASE" \
        --queries-file="$query_file" \
        --format=Null \
        > "$output_file" 2>"$error_file"
    local status=$?
    set -e

    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))

    local rows_returned=$(wc -l < "$output_file" 2>/dev/null || echo "0")

    if [ $status -eq 0 ]; then
        echo "$timestamp,$query_name,$stream,$iteration,success,$duration_ms,$rows_returned" >> "$RESULTS_FILE"
        log "INFO" "✓ $query_name (stream $stream, iter $iteration) completed in ${duration_ms}ms"
    else
        echo "$timestamp,$query_name,$stream,$iteration,failed,$duration_ms,0" >> "$RESULTS_FILE"
        log "ERROR" "✗ $query_name (stream $stream, iter $iteration) failed"
    fi

    {
        echo "Query: $query_name | Stream: $stream | Iteration: $iteration | Status: $([ $status -eq 0 ] && echo 'SUCCESS' || echo 'FAILED') | Duration: ${duration_ms}ms"
    } >> "$DETAILED_FILE"
}

# Export function for parallel execution
export -f execute_query_background
export CLICKHOUSE_CLIENT CLICKHOUSE_HOST CLICKHOUSE_PORT CLICKHOUSE_USER CLICKHOUSE_PASSWORD CLICKHOUSE_DATABASE
export OUTPUT_DIR TIMESTAMP RESULTS_FILE DETAILED_FILE
export -f log

# Power test implementation
run_power_test() {
    log "INFO" "Starting TPC-DS Power Test (sequential execution)"
    local start_time=$(date +%s)

    for query_file in "${QUERY_FILES[@]}"; do
        execute_query_background "$query_file" "1" "1"
    done

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log "INFO" "Power test completed in ${duration}s"
    return 0
}

# Throughput test implementation
run_throughput_test() {
    log "INFO" "Starting TPC-DS Throughput Test ($PARALLEL parallel streams)"
    local start_time=$(date +%s)

    # Create job list
    local jobs=()
    for stream in $(seq 1 $PARALLEL); do
        for query_file in "${QUERY_FILES[@]}"; do
            jobs+=("$query_file|$stream|1")
        done
    done

    # Run jobs in parallel
    printf "%s\n" "${jobs[@]}" | xargs -n 1 -P $PARALLEL bash -c '
        IFS="|" read -r query_file stream iteration <<< "$0"
        execute_query_background "$query_file" "$stream" "$iteration"
    '

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log "INFO" "Throughput test completed in ${duration}s"
    return 0
}

# Regular parallel execution
run_parallel_queries() {
    log "INFO" "Starting parallel query execution"
    local start_time=$(date +%s)

    # Create all job combinations
    local jobs=()
    for iteration in $(seq 1 $ITERATIONS); do
        for query_file in "${QUERY_FILES[@]}"; do
            for stream in $(seq 1 $PARALLEL); do
                jobs+=("$query_file|$stream|$iteration")
            done
        done
    done

    log "INFO" "Total jobs to execute: ${#jobs[@]}"

    # Execute jobs in parallel
    printf "%s\n" "${jobs[@]}" | xargs -n 1 -P $PARALLEL bash -c '
        IFS="|" read -r query_file stream iteration <<< "$0"
        execute_query_background "$query_file" "$stream" "$iteration"
    '

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log "INFO" "Parallel execution completed in ${duration}s"
    return 0
}

# Warmup
if [ "$WARMUP" = true ]; then
    log "INFO" "Starting warmup phase..."
    for query_file in "${QUERY_FILES[@]}"; do
        query_name=$(basename "$query_file" .sql)
        log "INFO" "Warming up $query_name..."
        execute_query_background "$query_file" "warmup" "0" > /dev/null 2>&1 || true
    done
    log "INFO" "Warmup complete"
    echo ""
fi

# Main execution
START_TIME=$(date +%s)

if [ "$POWER_TEST" = true ]; then
    run_power_test
elif [ "$THROUGHPUT_TEST" = true ]; then
    run_throughput_test
else
    run_parallel_queries
fi

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

# Generate summary
TOTAL_QUERIES=$(awk -F',' 'NR > 1 {count++} END {print count}' "$RESULTS_FILE")
SUCCESSFUL_QUERIES=$(awk -F',' 'NR > 1 && $5 == "success" {count++} END {print count}' "$RESULTS_FILE")
FAILED_QUERIES=$(awk -F',' 'NR > 1 && $5 == "failed" {count++} END {print count}' "$RESULTS_FILE")

{
    echo "========================================"
    echo "TPC-DS Parallel Query Execution Summary"
    echo "========================================"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Database: $CLICKHOUSE_DATABASE"
    echo "Total Duration: ${TOTAL_DURATION}s"
    echo "Parallel Streams: $PARALLEL"
    echo ""
    echo "Query Statistics:"
    echo "  Total Executions: $TOTAL_QUERIES"
    echo "  Successful: $SUCCESSFUL_QUERIES"
    echo "  Failed: $FAILED_QUERIES"
    if [ $TOTAL_QUERIES -gt 0 ]; then
        echo "  Success Rate: $(awk "BEGIN {printf \"%.2f\", ($SUCCESSFUL_QUERIES/$TOTAL_QUERIES)*100}")%"
    fi
    echo ""
    echo "Performance Summary (successful queries only):"
    echo ""
} > "$SUMMARY_FILE"

# Calculate statistics
awk -F',' '
NR > 1 && $5 == "success" {
    count[$2]++
    sum[$2] += $6
    if (min[$2] == 0 || $6 < min[$2]) min[$2] = $6
    if ($6 > max[$2]) max[$2] = $6
}
END {
    printf "%-20s %10s %10s %10s %10s %10s\n", "Query", "Runs", "Min(ms)", "Max(ms)", "Avg(ms)", "QPS"
    print "----------------------------------------------------------------------------------------"
    for (query in count) {
        avg = sum[query] / count[query]
        qps = (avg > 0) ? 1000 / avg : 0
        printf "%-20s %10d %10d %10d %10.2f %10.2f\n", query, count[query], min[query], max[query], avg, qps
    }
}
' "$RESULTS_FILE" >> "$SUMMARY_FILE"

{
    echo ""
    echo "Throughput Metrics:"
    echo "  Total Query Time: ${TOTAL_DURATION}s"
    echo "  Total Successful Queries: $SUCCESSFUL_QUERIES"
    if [ $TOTAL_DURATION -gt 0 ]; then
        echo "  Average QPS: $(awk "BEGIN {printf \"%.2f\", $SUCCESSFUL_QUERIES/$TOTAL_DURATION}")"
    fi
} >> "$SUMMARY_FILE"

# Display summary
cat "$SUMMARY_FILE"

log "INFO" "Results saved to:"
log "INFO" "  Summary: $SUMMARY_FILE"
log "INFO" "  Detailed CSV: $RESULTS_FILE"
log "INFO" "  Detailed Log: $DETAILED_FILE"

echo ""
echo "Parallel query execution complete!"
echo ""

exit 0
