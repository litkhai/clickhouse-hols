#!/bin/bash
set -e

echo "=================================================="
echo "ClickPipes S3 Checkpoint - Full Automated Test"
echo "=================================================="

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found"
    echo ""
    echo "Please create .env file with your credentials:"
    echo "  cp .env.template .env"
    echo "  # Edit .env with your AWS and ClickHouse Cloud credentials"
    exit 1
fi

# Make all scripts executable
chmod +x *.sh

echo ""
echo "Step 1: Setting up S3 test data..."
./01-setup-s3-data.sh

echo ""
read -p "Press Enter to continue to create ClickHouse table..."

echo ""
echo "Step 2: Creating ClickHouse table..."
./02-setup-clickhouse-table.sh

echo ""
read -p "Press Enter to continue to create ClickPipe..."

echo ""
echo "Step 3: Creating ClickPipe..."
./03-create-clickpipe.sh

echo ""
echo "Step 4: Monitoring initial ingestion..."
echo "Waiting 30 seconds for some files to be ingested..."
for i in {1..6}; do
    sleep 5
    echo "  ... $((i*5))s elapsed"
done

echo ""
echo "Current data status:"
./05-query-data.sh count

echo ""
echo "Files ingested so far:"
./05-query-data.sh summary

echo ""
read -p "Press Enter to PAUSE the pipe..."

echo ""
echo "Step 5: Pausing ClickPipe..."
./06-pause-pipe.sh

echo ""
echo "⏸️  Pipe is now PAUSED"
echo ""
read -p "Wait 1-2 minutes, then press Enter to RESUME the pipe..."

echo ""
echo "Step 6: Resuming ClickPipe..."
./07-resume-pipe.sh

echo ""
echo "▶️  Pipe is now RESUMED"
echo ""
echo "Waiting 60 seconds for remaining files to be ingested..."
for i in {1..12}; do
    sleep 5
    echo "  ... $((i*5))s elapsed"
done

echo ""
read -p "Press Enter to run validation..."

echo ""
echo "Step 7: Validating checkpoint behavior..."
./08-validate-checkpoint.sh

echo ""
echo "=================================================="
echo "Full Test Complete!"
echo "=================================================="
echo ""
echo "Review the validation results above to determine if:"
echo "  1. Checkpointing works (no duplicates)"
echo "  2. All files were ingested"
echo "  3. Pause/Resume is safe to use"
echo ""
echo "To clean up all resources, run: ./09-cleanup.sh"
