#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found. Please copy .env.template to .env and fill in your credentials."
    exit 1
fi

echo "=================================================="
echo "ClickPipes S3 Test - Data Setup"
echo "=================================================="

# Create temporary directory for test files
mkdir -p /tmp/clickpipe-test

echo ""
echo "Creating test data files..."

# Generate test files with various dates (simulating historical data)
for month in 01 02 03 04 05 06; do
  for day in 01 15; do
    FILE_PATH="/tmp/clickpipe-test/test_${month}_${day}.json"

    # Create JSON file with test data
    cat > "$FILE_PATH" << EOF
{"id": 1, "date": "2025-${month}-${day}", "value": "data_${month}_${day}_row1"}
{"id": 2, "date": "2025-${month}-${day}", "value": "data_${month}_${day}_row2"}
{"id": 3, "date": "2025-${month}-${day}", "value": "data_${month}_${day}_row3"}
EOF

    echo "✓ Created $FILE_PATH"
  done
done

echo ""
echo "Uploading files to S3..."
echo "Bucket: $AWS_S3_BUCKET"
echo "Prefix: $TEST_PREFIX"

# Upload files to S3 with organized structure
for month in 01 02 03 04 05 06; do
  for day in 01 15; do
    LOCAL_FILE="/tmp/clickpipe-test/test_${month}_${day}.json"
    S3_PATH="s3://${AWS_S3_BUCKET}/${TEST_PREFIX}/ym=2025${month}/dt=2025${month}${day}/data.json"

    aws s3 cp "$LOCAL_FILE" "$S3_PATH" \
      --region "$AWS_REGION"

    echo "✓ Uploaded to $S3_PATH"
  done
done

echo ""
echo "=================================================="
echo "Verifying uploaded files..."
echo "=================================================="

aws s3 ls "s3://${AWS_S3_BUCKET}/${TEST_PREFIX}/" \
  --recursive \
  --region "$AWS_REGION" \
  --human-readable

echo ""
echo "=================================================="
echo "✅ S3 Test Data Setup Complete!"
echo "=================================================="
echo "Total files created: 12 (6 months × 2 days)"
echo ""
echo "Next step: Run ./02-setup-clickhouse-table.sh"
