#!/bin/bash

#################################################
# TPC-DS Data Loading Script
# Loads TPC-DS data into ClickHouse
#################################################

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Error: config.sh not found. Please run setup first:"
    echo "  ./00-set.sh"
    exit 1
fi

# Default source
SOURCE="s3"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Load TPC-DS data into ClickHouse from either local files or S3.

OPTIONS:
    --source SOURCE        Data source: 'local' or 's3' (default: s3)
    --data-dir DIR        Directory containing local data files (default: $DATA_DIR)
    --parallel N          Number of parallel insert operations (default: 4)
    --batch-size N        Batch size for inserts (default: 1000000)
    -h, --help           Show this help message

EXAMPLES:
    # Load from S3 (fastest, pre-generated data)
    $0 --source s3

    # Load from locally generated data
    $0 --source local --data-dir ./data

    # Load with custom parallelism
    $0 --source local --parallel 8

EOF
    exit 1
}

# Parse arguments
PARALLEL_INSERTS=4
BATCH_SIZE=1000000

while [[ $# -gt 0 ]]; do
    case $1 in
        --source)
            SOURCE="$2"
            shift 2
            ;;
        --data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL_INSERTS="$2"
            shift 2
            ;;
        --batch-size)
            BATCH_SIZE="$2"
            shift 2
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
initialize_directories
log "INFO" "Starting TPC-DS data loading"
log "INFO" "Source: $SOURCE"

# Test connection
log "INFO" "Testing ClickHouse connection..."
if ! test_connection; then
    log "ERROR" "Failed to connect to ClickHouse"
    exit 1
fi

# Check if database exists
DB_EXISTS=$(execute_query "EXISTS DATABASE $CLICKHOUSE_DATABASE" "default" || echo "0")
if [ "$DB_EXISTS" = "0" ]; then
    log "ERROR" "Database $CLICKHOUSE_DATABASE does not exist. Run 01-create-schema.sh first."
    exit 1
fi

# Function to load from S3
load_from_s3() {
    log "INFO" "Loading data from S3: $S3_BUCKET"

    # Use the existing load script if available
    LOAD_FILE="$SCRIPT_DIR/sql/clickhouse-tpcds-load.sql"
    if [ -f "$LOAD_FILE" ]; then
        log "INFO" "Executing load script: $LOAD_FILE"
        if execute_sql_file "$LOAD_FILE" "$CLICKHOUSE_DATABASE"; then
            log "INFO" "Data loaded successfully from S3"
            return 0
        else
            log "ERROR" "Failed to load data from S3"
            return 1
        fi
    else
        log "ERROR" "Load script not found: $LOAD_FILE"
        return 1
    fi
}

# Function to load from local files
load_from_local() {
    log "INFO" "Loading data from local directory: $DATA_DIR"

    if [ ! -d "$DATA_DIR" ]; then
        log "ERROR" "Data directory not found: $DATA_DIR"
        log "ERROR" "Please run 02-generate-data.sh first or specify correct --data-dir"
        exit 1
    fi

    # Check if data files exist
    FILE_COUNT=$(ls -1 "$DATA_DIR"/*.dat 2>/dev/null | wc -l)
    if [ "$FILE_COUNT" -eq 0 ]; then
        log "ERROR" "No .dat files found in $DATA_DIR"
        exit 1
    fi

    log "INFO" "Found $FILE_COUNT data files"

    # Define table to file mapping
    declare -A TABLE_FILES=(
        ["call_center"]="call_center.dat"
        ["catalog_page"]="catalog_page.dat"
        ["catalog_returns"]="catalog_returns.dat"
        ["catalog_sales"]="catalog_sales.dat"
        ["customer"]="customer.dat"
        ["customer_address"]="customer_address.dat"
        ["customer_demographics"]="customer_demographics.dat"
        ["date_dim"]="date_dim.dat"
        ["household_demographics"]="household_demographics.dat"
        ["income_band"]="income_band.dat"
        ["inventory"]="inventory.dat"
        ["item"]="item.dat"
        ["promotion"]="promotion.dat"
        ["reason"]="reason.dat"
        ["ship_mode"]="ship_mode.dat"
        ["store"]="store.dat"
        ["store_returns"]="store_returns.dat"
        ["store_sales"]="store_sales.dat"
        ["time_dim"]="time_dim.dat"
        ["warehouse"]="warehouse.dat"
        ["web_page"]="web_page.dat"
        ["web_returns"]="web_returns.dat"
        ["web_sales"]="web_sales.dat"
        ["web_site"]="web_site.dat"
    )

    # Load each table
    for table in "${!TABLE_FILES[@]}"; do
        file="${TABLE_FILES[$table]}"
        filepath="$DATA_DIR/$file"

        if [ ! -f "$filepath" ]; then
            log "WARN" "File not found, skipping: $filepath"
            continue
        fi

        log "INFO" "Loading $table from $file..."
        START=$(date +%s)

        # Use clickhouse-client to load data
        cat "$filepath" | $CLICKHOUSE_CLIENT \
            --host="$CLICKHOUSE_HOST" \
            --port="$CLICKHOUSE_PORT" \
            --user="$CLICKHOUSE_USER" \
            --password="$CLICKHOUSE_PASSWORD" \
            --database="$CLICKHOUSE_DATABASE" \
            --query="INSERT INTO $table FORMAT CSV" \
            --format_csv_delimiter='|' \
            --input_format_allow_errors_ratio=0.01 \
            --input_format_allow_errors_num=1000

        END=$(date +%s)
        DURATION=$((END - START))

        # Get row count
        COUNT=$(execute_query "SELECT count() FROM $table" "$CLICKHOUSE_DATABASE")
        log "INFO" "Loaded $table: $COUNT rows in $DURATION seconds"
    done

    log "INFO" "All data loaded successfully from local files"
}

# Main loading logic
START_TIME=$(date +%s)

echo ""
echo "========================================"
echo "TPC-DS Data Loading"
echo "========================================"
echo "Database: $CLICKHOUSE_DATABASE"
echo "Source: $SOURCE"
echo ""

if [ "$SOURCE" = "s3" ]; then
    load_from_s3
elif [ "$SOURCE" = "local" ]; then
    load_from_local
else
    log "ERROR" "Invalid source: $SOURCE. Must be 'local' or 's3'"
    exit 1
fi

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

# Get table statistics
log "INFO" "Collecting table statistics..."
echo ""
echo "========================================"
echo "Data Loading Complete"
echo "========================================"
echo "Total time: $TOTAL_DURATION seconds"
echo ""
printf "%-30s %15s %15s\n" "TABLE" "ROWS" "SIZE"
echo "----------------------------------------------------------------"

TABLES=$(execute_query "SHOW TABLES FROM $CLICKHOUSE_DATABASE" "default")
TOTAL_ROWS=0
TOTAL_BYTES=0

for table in $TABLES; do
    if [ -n "$table" ]; then
        count=$(execute_query "SELECT count() FROM $CLICKHOUSE_DATABASE.$table" "default" 2>/dev/null || echo "0")
        size=$(execute_query "SELECT formatReadableSize(sum(bytes)) FROM system.parts WHERE database='$CLICKHOUSE_DATABASE' AND table='$table' AND active" "default" 2>/dev/null || echo "0 B")
        size_bytes=$(execute_query "SELECT sum(bytes) FROM system.parts WHERE database='$CLICKHOUSE_DATABASE' AND table='$table' AND active" "default" 2>/dev/null || echo "0")

        printf "%-30s %'15d %15s\n" "$table" "$count" "$size"

        TOTAL_ROWS=$((TOTAL_ROWS + count))
        TOTAL_BYTES=$((TOTAL_BYTES + size_bytes))
    fi
done

TOTAL_SIZE_HR=$(execute_query "SELECT formatReadableSize($TOTAL_BYTES)" "default")

echo "----------------------------------------------------------------"
printf "%-30s %'15d %15s\n" "TOTAL" "$TOTAL_ROWS" "$TOTAL_SIZE_HR"
echo ""

log "INFO" "Data loading completed successfully"
log "INFO" "Total rows loaded: $TOTAL_ROWS"
log "INFO" "Total size: $TOTAL_SIZE_HR"
log "INFO" "Duration: $TOTAL_DURATION seconds"

echo ""
echo "Next step: Run queries"
echo "  ./04-run-queries-sequential.sh"
echo "  ./05-run-queries-parallel.sh"
echo ""

exit 0
