#!/bin/bash

#################################################
# TPC-DS Complete Benchmark Runner
# Runs the complete TPC-DS benchmark workflow
#################################################

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Error: config.sh not found. Creating from template..."
    cp "$SCRIPT_DIR/config.sh.example" "$SCRIPT_DIR/config.sh"
    echo "Please edit config.sh with your settings and run again."
    exit 1
fi

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run the complete TPC-DS benchmark workflow.

OPTIONS:
    --skip-schema         Skip schema creation
    --skip-data           Skip data loading
    --skip-sequential     Skip sequential query execution
    --skip-parallel       Skip parallel query execution
    --data-source SOURCE  Data source: 'local' or 's3' (default: s3)
    --scale-factor N      Scale factor for local data generation (default: 1)
    -h, --help           Show this help message

EXAMPLES:
    # Run complete benchmark with S3 data
    $0

    # Run with locally generated data
    $0 --data-source local --scale-factor 1

    # Run only query benchmarks (assuming data already loaded)
    $0 --skip-schema --skip-data

EOF
    exit 1
}

# Parse arguments
SKIP_SCHEMA=false
SKIP_DATA=false
SKIP_SEQUENTIAL=false
SKIP_PARALLEL=false
DATA_SOURCE="s3"
SCALE_FACTOR_ARG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-schema)
            SKIP_SCHEMA=true
            shift
            ;;
        --skip-data)
            SKIP_DATA=true
            shift
            ;;
        --skip-sequential)
            SKIP_SEQUENTIAL=true
            shift
            ;;
        --skip-parallel)
            SKIP_PARALLEL=true
            shift
            ;;
        --data-source)
            DATA_SOURCE="$2"
            shift 2
            ;;
        --scale-factor)
            SCALE_FACTOR_ARG="--scale-factor $2"
            SCALE_FACTOR="$2"
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

echo ""
echo "========================================"
echo "TPC-DS Complete Benchmark"
echo "========================================"
echo "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

OVERALL_START=$(date +%s)

# Step 1: Create Schema
if [ "$SKIP_SCHEMA" = false ]; then
    echo ""
    echo "========================================"
    echo "Step 1: Creating Schema"
    echo "========================================"
    "$SCRIPT_DIR/01-create-schema.sh"
else
    echo "Skipping schema creation..."
fi

# Step 2: Generate/Load Data
if [ "$SKIP_DATA" = false ]; then
    echo ""
    echo "========================================"
    echo "Step 2: Loading Data"
    echo "========================================"

    if [ "$DATA_SOURCE" = "local" ]; then
        echo "Generating data locally..."
        "$SCRIPT_DIR/02-generate-data.sh" $SCALE_FACTOR_ARG
    fi

    echo "Loading data from $DATA_SOURCE..."
    "$SCRIPT_DIR/03-load-data.sh" --source "$DATA_SOURCE"
else
    echo "Skipping data loading..."
fi

# Step 3: Sequential Query Execution
if [ "$SKIP_SEQUENTIAL" = false ]; then
    echo ""
    echo "========================================"
    echo "Step 3: Sequential Query Execution"
    echo "========================================"
    "$SCRIPT_DIR/04-run-queries-sequential.sh" --warmup --iterations 3
else
    echo "Skipping sequential query execution..."
fi

# Step 4: Parallel Query Execution
if [ "$SKIP_PARALLEL" = false ]; then
    echo ""
    echo "========================================"
    echo "Step 4: Parallel Query Execution"
    echo "========================================"
    "$SCRIPT_DIR/05-run-queries-parallel.sh" --warmup --iterations 3 --parallel "$PARALLEL_JOBS"
else
    echo "Skipping parallel query execution..."
fi

OVERALL_END=$(date +%s)
OVERALL_DURATION=$((OVERALL_END - OVERALL_START))

echo ""
echo "========================================"
echo "TPC-DS Benchmark Complete"
echo "========================================"
echo "End Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Total Duration: ${OVERALL_DURATION}s ($(($OVERALL_DURATION / 60))m $(($OVERALL_DURATION % 60))s)"
echo ""
echo "Results are available in: $RESULTS_DIR"
echo ""

exit 0
