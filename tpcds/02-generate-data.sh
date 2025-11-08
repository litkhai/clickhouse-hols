#!/bin/bash

#################################################
# TPC-DS Data Generation Script
# Generates TPC-DS data using dsdgen tool
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

# Parse command line arguments
SCALE_FACTOR_ARG=""
PARALLEL_ARG=""

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Generate TPC-DS data files using dsdgen tool.

OPTIONS:
    -s, --scale-factor N    Scale factor for data generation (default: $SCALE_FACTOR)
                            1 = ~1GB, 10 = ~10GB, 100 = ~100GB, 1000 = ~1TB
    -p, --parallel N        Number of parallel data generation jobs (default: 1)
    -d, --data-dir DIR      Output directory for data files (default: $DATA_DIR)
    -h, --help             Show this help message

EXAMPLES:
    # Generate 1GB dataset
    $0 --scale-factor 1

    # Generate 10GB dataset with 4 parallel jobs
    $0 --scale-factor 10 --parallel 4

    # Generate data to custom directory
    $0 --scale-factor 1 --data-dir /tmp/tpcds-data

PREREQUISITES:
    1. Install TPC-DS toolkit:
       git clone https://github.com/gregrahn/tpcds-kit.git
       cd tpcds-kit/tools
       make OS=LINUX  # or OS=MACOS

    2. Update DSDGEN_PATH in config.sh to point to dsdgen binary

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--scale-factor)
            SCALE_FACTOR="$2"
            shift 2
            ;;
        -p|--parallel)
            PARALLEL_ARG="$2"
            shift 2
            ;;
        -d|--data-dir)
            DATA_DIR="$2"
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
log "INFO" "Starting TPC-DS data generation"
log "INFO" "Scale factor: $SCALE_FACTOR"
log "INFO" "Output directory: $DATA_DIR"

# Check if dsdgen exists
if [ ! -f "$DSDGEN_PATH" ]; then
    log "ERROR" "dsdgen not found at: $DSDGEN_PATH"
    echo ""
    echo "Please install TPC-DS toolkit:"
    echo "  1. git clone https://github.com/gregrahn/tpcds-kit.git"
    echo "  2. cd tpcds-kit/tools"
    echo "  3. make OS=LINUX  # or OS=MACOS"
    echo "  4. Update DSDGEN_PATH in config.sh"
    echo ""
    exit 1
fi

# Make dsdgen executable
chmod +x "$DSDGEN_PATH"

# Create data directory
ensure_directory "$DATA_DIR"

# Calculate estimated data size
calculate_size() {
    local sf=$1
    # Approximate sizes based on scale factor (in GB)
    local size=$(echo "$sf * 1.0" | bc)
    echo "${size}GB"
}

ESTIMATED_SIZE=$(calculate_size $SCALE_FACTOR)
log "INFO" "Estimated data size: $ESTIMATED_SIZE"

# Check available disk space
AVAILABLE_SPACE=$(df -h "$DATA_DIR" | awk 'NR==2 {print $4}')
log "INFO" "Available disk space: $AVAILABLE_SPACE"

echo ""
echo "========================================"
echo "TPC-DS Data Generation"
echo "========================================"
echo "Scale Factor: $SCALE_FACTOR"
echo "Output Directory: $DATA_DIR"
echo "Estimated Size: $ESTIMATED_SIZE"
echo "Available Space: $AVAILABLE_SPACE"
echo ""
read -p "Continue with data generation? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "INFO" "Data generation cancelled"
    exit 0
fi

# Change to data directory
cd "$DATA_DIR"

# Get the directory where dsdgen is located (for tpcds.idx file)
DSDGEN_DIR=$(dirname "$DSDGEN_PATH")

# Generate data
log "INFO" "Starting data generation..."
START_TIME=$(date +%s)

# List of TPC-DS tables
TABLES=(
    "call_center"
    "catalog_page"
    "catalog_returns"
    "catalog_sales"
    "customer"
    "customer_address"
    "customer_demographics"
    "date_dim"
    "household_demographics"
    "income_band"
    "inventory"
    "item"
    "promotion"
    "reason"
    "ship_mode"
    "store"
    "store_returns"
    "store_sales"
    "time_dim"
    "warehouse"
    "web_page"
    "web_returns"
    "web_sales"
    "web_site"
)

if [ -n "$PARALLEL_ARG" ]; then
    log "INFO" "Generating data with $PARALLEL_ARG parallel jobs..."
    # Generate with parallel option
    "$DSDGEN_PATH" -SCALE "$SCALE_FACTOR" -FORCE Y -PARALLEL "$PARALLEL_ARG" -DIR "$DATA_DIR" -VERBOSE Y
else
    log "INFO" "Generating data (single process)..."
    # Generate without parallel option
    "$DSDGEN_PATH" -SCALE "$SCALE_FACTOR" -FORCE Y -DIR "$DATA_DIR" -VERBOSE Y
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log "INFO" "Data generation completed in $DURATION seconds"

# List generated files
log "INFO" "Generated files:"
echo ""
printf "%-30s %15s\n" "FILE" "SIZE"
echo "--------------------------------------------------------"

TOTAL_SIZE=0
for file in *.dat; do
    if [ -f "$file" ]; then
        size=$(du -h "$file" | awk '{print $1}')
        size_bytes=$(du -b "$file" | awk '{print $1}')
        TOTAL_SIZE=$((TOTAL_SIZE + size_bytes))
        printf "%-30s %15s\n" "$file" "$size"
    fi
done

TOTAL_SIZE_HR=$(echo "$TOTAL_SIZE" | awk '{ split("B KB MB GB TB", v); s=1; while($1>1024 && s<5){$1/=1024; s++} printf "%.2f %s", $1, v[s] }')

echo "--------------------------------------------------------"
printf "%-30s %15s\n" "TOTAL" "$TOTAL_SIZE_HR"
echo ""

log "INFO" "Data generation summary:"
log "INFO" "  Files generated: $(ls -1 *.dat 2>/dev/null | wc -l)"
log "INFO" "  Total size: $TOTAL_SIZE_HR"
log "INFO" "  Duration: $DURATION seconds"

echo ""
echo "========================================"
echo "Data Generation Complete"
echo "========================================"
echo "Next step: Load data into ClickHouse"
echo "  ./03-load-data.sh --source local"
echo ""

exit 0
