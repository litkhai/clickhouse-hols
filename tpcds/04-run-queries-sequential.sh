#!/bin/bash

#################################################
# TPC-DS Sequential Query Execution Script
# Runs TPC-DS queries one by one and records results
#################################################

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Error: config.sh not found. Please create it from config.sh.example"
    exit 1
fi

# Default values
OUTPUT_DIR="$RESULTS_DIR/sequential"
ITERATIONS=${QUERY_ITERATIONS:-1}
QUERY_PATTERN="*"
WARMUP=false

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run TPC-DS queries sequentially and record performance metrics.

OPTIONS:
    --queries PATTERN      Run specific queries (e.g., "query01,query05" or "query*")
                          Default: all queries
    --iterations N        Run each query N times (default: $ITERATIONS)
    --output DIR         Output directory for results (default: $OUTPUT_DIR)
    --warmup             Run queries once before measuring (cache warmup)
    -h, --help          Show this help message

EXAMPLES:
    # Run all queries once
    $0

    # Run specific queries 3 times each
    $0 --queries "query01,query05,query10" --iterations 3

    # Run all queries with warmup
    $0 --warmup --iterations 3

    # Run queries matching pattern
    $0 --queries "query0*"

EOF
    exit 1
}

# Parse arguments
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
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --warmup)
            WARMUP=true
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
log "INFO" "Starting sequential query execution"

# Test connection
log "INFO" "Testing ClickHouse connection..."
if ! test_connection; then
    log "ERROR" "Failed to connect to ClickHouse"
    exit 1
fi

# Check if database exists and has data
DB_EXISTS=$(execute_query "EXISTS DATABASE $CLICKHOUSE_DATABASE" "default" || echo "0")
if [ "$DB_EXISTS" = "0" ]; then
    log "ERROR" "Database $CLICKHOUSE_DATABASE does not exist. Run setup scripts first."
    exit 1
fi

# Get list of queries
if [ ! -d "$QUERIES_DIR" ]; then
    log "ERROR" "Queries directory not found: $QUERIES_DIR"
    log "INFO" "Creating queries directory. Please add TPC-DS query files (.sql)"
    ensure_directory "$QUERIES_DIR"
    exit 1
fi

# Build query list based on pattern
QUERY_FILES=()
if [[ "$QUERY_PATTERN" == *","* ]]; then
    # Comma-separated list
    IFS=',' read -ra PATTERNS <<< "$QUERY_PATTERN"
    for pattern in "${PATTERNS[@]}"; do
        pattern=$(echo "$pattern" | xargs)  # trim whitespace
        if [ -f "$QUERIES_DIR/${pattern}.sql" ]; then
            QUERY_FILES+=("$QUERIES_DIR/${pattern}.sql")
        fi
    done
else
    # Glob pattern
    for file in "$QUERIES_DIR"/$QUERY_PATTERN.sql; do
        if [ -f "$file" ]; then
            QUERY_FILES+=("$file")
        fi
    done
fi

if [ ${#QUERY_FILES[@]} -eq 0 ]; then
    log "ERROR" "No query files found matching pattern: $QUERY_PATTERN"
    log "INFO" "Please add TPC-DS query SQL files to: $QUERIES_DIR"
    exit 1
fi

# Sort query files
IFS=$'\n' QUERY_FILES=($(sort <<<"${QUERY_FILES[*]}"))
unset IFS

log "INFO" "Found ${#QUERY_FILES[@]} query files"
log "INFO" "Iterations per query: $ITERATIONS"
log "INFO" "Warmup: $WARMUP"

# Create results file
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RESULTS_FILE="$OUTPUT_DIR/results_${TIMESTAMP}.csv"
SUMMARY_FILE="$OUTPUT_DIR/summary_${TIMESTAMP}.txt"
DETAILED_FILE="$OUTPUT_DIR/detailed_${TIMESTAMP}.log"

# Write CSV header
echo "timestamp,query,iteration,status,duration_ms,rows_returned,bytes_read,memory_usage" > "$RESULTS_FILE"

echo ""
echo "========================================"
echo "TPC-DS Sequential Query Execution"
echo "========================================"
echo "Database: $CLICKHOUSE_DATABASE"
echo "Queries: ${#QUERY_FILES[@]}"
echo "Iterations: $ITERATIONS"
echo "Output: $OUTPUT_DIR"
echo ""

# Function to execute and time a query
execute_timed_query() {
    local query_file="$1"
    local iteration="$2"
    local query_name=$(basename "$query_file" .sql)

    log "INFO" "Running $query_name (iteration $iteration)..."

    local start_time=$(date +%s%N)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Execute query and capture results
    local output_file="$OUTPUT_DIR/${query_name}_iter${iteration}_${TIMESTAMP}.out"
    local error_file="$OUTPUT_DIR/${query_name}_iter${iteration}_${TIMESTAMP}.err"

    set +e  # Don't exit on error
    local result=$($CLICKHOUSE_CLIENT \
        --host="$CLICKHOUSE_HOST" \
        --port="$CLICKHOUSE_PORT" \
        --user="$CLICKHOUSE_USER" \
        --password="$CLICKHOUSE_PASSWORD" \
        --database="$CLICKHOUSE_DATABASE" \
        --queries-file="$query_file" \
        --time \
        --format=PrettyCompact 2>"$error_file")
    local status=$?
    set -e

    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))

    # Get query statistics
    local rows_returned=$(echo "$result" | wc -l)
    local bytes_read="0"
    local memory_usage="0"

    # Try to get statistics from ClickHouse
    local stats=$(execute_query "SELECT
        formatReadableSize(sum(read_bytes)) as bytes_read,
        formatReadableSize(max(memory_usage)) as memory_usage
    FROM system.query_log
    WHERE type = 'QueryFinish'
        AND query_start_time >= now() - INTERVAL 10 SECOND
        AND query NOT LIKE '%system.query_log%'
    ORDER BY query_start_time DESC
    LIMIT 1" "$CLICKHOUSE_DATABASE" 2>/dev/null || echo "0 B,0 B")

    if [ $status -eq 0 ]; then
        echo "$result" > "$output_file"
        log "INFO" "✓ $query_name completed in ${duration_ms}ms"
        echo "$timestamp,$query_name,$iteration,success,$duration_ms,$rows_returned,$bytes_read,$memory_usage" >> "$RESULTS_FILE"
    else
        local error=$(cat "$error_file")
        log "ERROR" "✗ $query_name failed: $error"
        echo "$timestamp,$query_name,$iteration,failed,$duration_ms,0,0,0" >> "$RESULTS_FILE"
    fi

    # Log detailed output
    {
        echo "========================================"
        echo "Query: $query_name"
        echo "Iteration: $iteration"
        echo "Timestamp: $timestamp"
        echo "Status: $([ $status -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')"
        echo "Duration: ${duration_ms}ms"
        echo "Rows: $rows_returned"
        echo "========================================"
        echo ""
    } >> "$DETAILED_FILE"

    return $status
}

# Warmup phase
if [ "$WARMUP" = true ]; then
    log "INFO" "Starting warmup phase..."
    for query_file in "${QUERY_FILES[@]}"; do
        query_name=$(basename "$query_file" .sql)
        log "INFO" "Warming up $query_name..."
        execute_timed_query "$query_file" "warmup" > /dev/null 2>&1 || true
    done
    log "INFO" "Warmup complete"
    echo ""
fi

# Main execution
START_TIME=$(date +%s)
TOTAL_QUERIES=0
SUCCESSFUL_QUERIES=0
FAILED_QUERIES=0

for iteration in $(seq 1 $ITERATIONS); do
    log "INFO" "Starting iteration $iteration of $ITERATIONS"

    for query_file in "${QUERY_FILES[@]}"; do
        query_name=$(basename "$query_file" .sql)
        TOTAL_QUERIES=$((TOTAL_QUERIES + 1))

        if execute_timed_query "$query_file" "$iteration"; then
            SUCCESSFUL_QUERIES=$((SUCCESSFUL_QUERIES + 1))
        else
            FAILED_QUERIES=$((FAILED_QUERIES + 1))
        fi
    done

    echo ""
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

# Generate summary
{
    echo "========================================"
    echo "TPC-DS Sequential Query Execution Summary"
    echo "========================================"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Database: $CLICKHOUSE_DATABASE"
    echo "Total Duration: ${TOTAL_DURATION}s"
    echo ""
    echo "Query Statistics:"
    echo "  Total Queries: $TOTAL_QUERIES"
    echo "  Successful: $SUCCESSFUL_QUERIES"
    echo "  Failed: $FAILED_QUERIES"
    echo "  Success Rate: $(awk "BEGIN {printf \"%.2f\", ($SUCCESSFUL_QUERIES/$TOTAL_QUERIES)*100}")%"
    echo ""
    echo "Performance Summary (successful queries only):"
    echo ""
} > "$SUMMARY_FILE"

# Calculate statistics from results
awk -F',' '
NR > 1 && $4 == "success" {
    count[$2]++
    sum[$2] += $5
    if (min[$2] == 0 || $5 < min[$2]) min[$2] = $5
    if ($5 > max[$2]) max[$2] = $5
}
END {
    printf "%-20s %10s %10s %10s %10s\n", "Query", "Runs", "Min(ms)", "Max(ms)", "Avg(ms)"
    print "--------------------------------------------------------------------------------"
    for (query in count) {
        avg = sum[query] / count[query]
        printf "%-20s %10d %10d %10d %10.2f\n", query, count[query], min[query], max[query], avg
    }
}
' "$RESULTS_FILE" >> "$SUMMARY_FILE"

# Display summary
cat "$SUMMARY_FILE"

log "INFO" "Results saved to:"
log "INFO" "  Summary: $SUMMARY_FILE"
log "INFO" "  Detailed CSV: $RESULTS_FILE"
log "INFO" "  Detailed Log: $DETAILED_FILE"

echo ""
echo "Sequential query execution complete!"
echo ""

exit 0
