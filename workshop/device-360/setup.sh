#!/bin/bash
# Device360 PoC Setup Script
# Complete automation for data generation, upload, and ingestion

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================================================"
echo "Device360 PoC - Complete Setup"
echo "======================================================================"

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${YELLOW}Warning: .env file not found${NC}"
    echo "Copying .env.template to .env..."
    cp .env.template .env
    echo -e "${RED}Please edit .env file with your credentials and run this script again${NC}"
    exit 1
fi

# Load environment variables
export $(cat .env | grep -v '^#' | xargs)

# Validate required environment variables
required_vars=(
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "S3_BUCKET_NAME"
    "CLICKHOUSE_HOST"
    "CLICKHOUSE_PASSWORD"
)

missing_vars=0
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}ERROR: $var is not set in .env${NC}"
        missing_vars=1
    fi
done

if [ $missing_vars -eq 1 ]; then
    echo -e "${RED}Please set all required variables in .env file${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Environment variables loaded${NC}"

# Create necessary directories
mkdir -p data
mkdir -p results
mkdir -p logs

echo -e "${GREEN}✓ Directories created${NC}"

# Check Python dependencies
echo ""
echo "Checking Python dependencies..."
python3 -c "import boto3, clickhouse_connect" 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Installing Python dependencies...${NC}"
    pip3 install boto3 clickhouse-connect
fi
echo -e "${GREEN}✓ Python dependencies ready${NC}"

# Make scripts executable
chmod +x scripts/*.py
echo -e "${GREEN}✓ Scripts made executable${NC}"

echo ""
echo "======================================================================"
echo "Setup Phase Selection"
echo "======================================================================"
echo "1) Generate synthetic data (300GB)"
echo "2) Upload data to S3"
echo "3) Setup S3 integration (IAM role)"
echo "4) Ingest data into ClickHouse"
echo "5) Run benchmark queries"
echo "6) Complete workflow (all steps)"
echo "======================================================================"
read -p "Select phase (1-6): " phase

case $phase in
    1)
        echo ""
        echo "======================================================================"
        echo "Phase 1: Data Generation"
        echo "======================================================================"
        export DATA_OUTPUT_DIR=./data
        python3 scripts/generate_data.py
        ;;
    2)
        echo ""
        echo "======================================================================"
        echo "Phase 2: S3 Upload"
        echo "======================================================================"
        export DATA_OUTPUT_DIR=./data
        python3 scripts/upload_to_s3.py
        ;;
    3)
        echo ""
        echo "======================================================================"
        echo "Phase 3: S3 Integration Setup"
        echo "======================================================================"
        python3 scripts/setup_s3_integration.py
        ;;
    4)
        echo ""
        echo "======================================================================"
        echo "Phase 4: Data Ingestion"
        echo "======================================================================"
        python3 scripts/ingest_from_s3.py
        ;;
    5)
        echo ""
        echo "======================================================================"
        echo "Phase 5: Benchmark Queries"
        echo "======================================================================"
        python3 scripts/run_benchmarks.py
        ;;
    6)
        echo ""
        echo "======================================================================"
        echo "Complete Workflow"
        echo "======================================================================"
        echo "This will run all phases sequentially."
        echo "Estimated time: 2-4 hours depending on data size"
        read -p "Continue? (yes/no): " confirm

        if [ "$confirm" != "yes" ]; then
            echo "Aborted"
            exit 0
        fi

        # Phase 1: Generate data
        echo ""
        echo "======================================================================"
        echo "[1/5] Generating synthetic data..."
        echo "======================================================================"
        export DATA_OUTPUT_DIR=./data
        python3 scripts/generate_data.py 2>&1 | tee logs/01_generate_$(date +%Y%m%d_%H%M%S).log

        # Phase 2: Upload to S3
        echo ""
        echo "======================================================================"
        echo "[2/5] Uploading data to S3..."
        echo "======================================================================"
        python3 scripts/upload_to_s3.py 2>&1 | tee logs/02_upload_$(date +%Y%m%d_%H%M%S).log

        # Phase 3: S3 Integration (optional, may need manual input)
        echo ""
        echo "======================================================================"
        echo "[3/5] Setting up S3 integration..."
        echo "======================================================================"
        echo "Note: This step requires ClickHouse Role ID from your Cloud console"
        python3 scripts/setup_s3_integration.py 2>&1 | tee logs/03_s3_integration_$(date +%Y%m%d_%H%M%S).log

        # Phase 4: Ingest data
        echo ""
        echo "======================================================================"
        echo "[4/5] Ingesting data into ClickHouse..."
        echo "======================================================================"
        python3 scripts/ingest_from_s3.py 2>&1 | tee logs/04_ingest_$(date +%Y%m%d_%H%M%S).log

        # Phase 5: Run benchmarks
        echo ""
        echo "======================================================================"
        echo "[5/5] Running benchmark queries..."
        echo "======================================================================"
        python3 scripts/run_benchmarks.py 2>&1 | tee logs/05_benchmarks_$(date +%Y%m%d_%H%M%S).log

        echo ""
        echo "======================================================================"
        echo -e "${GREEN}Complete workflow finished!${NC}"
        echo "======================================================================"
        echo "Logs saved to: ./logs/"
        echo "Results saved to: ./results/"
        ;;
    *)
        echo -e "${RED}Invalid selection${NC}"
        exit 1
        ;;
esac

echo ""
echo "======================================================================"
echo -e "${GREEN}Setup completed successfully!${NC}"
echo "======================================================================"
