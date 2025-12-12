#!/bin/bash
# Quick Test Script - Small scale test for validation
# Generates 1GB of data for quick testing

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "======================================================================"
echo "Device360 Quick Test (Small Scale)"
echo "======================================================================"
echo "This will:"
echo "  - Generate 1GB of test data (~1.7M records)"
echo "  - Upload to S3"
echo "  - Ingest into ClickHouse"
echo "  - Run sample queries"
echo ""
echo "Estimated time: 10-15 minutes"
echo "======================================================================"

if [ ! -f .env ]; then
    echo "ERROR: .env file not found"
    echo "Please copy .env.template to .env and configure it"
    exit 1
fi

export $(cat .env | grep -v '^#' | xargs)

# Override with small scale settings
export TARGET_SIZE_GB=1
export NUM_DEVICES=100000
export NUM_RECORDS=1700000
export DATA_OUTPUT_DIR=./data

echo ""
echo -e "${YELLOW}[1/4] Generating 1GB test data...${NC}"
python3 scripts/generate_data.py

echo ""
echo -e "${YELLOW}[2/4] Uploading to S3...${NC}"
python3 scripts/upload_to_s3.py

echo ""
echo -e "${YELLOW}[3/4] Ingesting into ClickHouse...${NC}"
python3 scripts/ingest_from_s3.py

echo ""
echo -e "${YELLOW}[4/4] Running sample queries...${NC}"
python3 scripts/run_benchmarks.py

echo ""
echo "======================================================================"
echo -e "${GREEN}Quick test completed successfully!${NC}"
echo "======================================================================"
echo "Check ./results/ for benchmark results"
echo "Check ./logs/ for detailed logs"
echo ""
echo "To run full 300GB test:"
echo "  export TARGET_SIZE_GB=300"
echo "  ./setup.sh"
