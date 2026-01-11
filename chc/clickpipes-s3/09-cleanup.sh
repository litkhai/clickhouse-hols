#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found."
    exit 1
fi

echo "=================================================="
echo "Cleanup Test Environment"
echo "=================================================="

# Confirmation prompt
read -p "This will delete the ClickPipe, table, and S3 data. Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

PIPE_ID_FILE=".pipe_id"

# Delete ClickPipe if it exists
if [ -f "$PIPE_ID_FILE" ]; then
    PIPE_ID=$(cat "$PIPE_ID_FILE")
    echo ""
    echo "Deleting ClickPipe: $PIPE_ID"

    curl -s -X DELETE \
      "https://api.clickhouse.cloud/v1/organizations/${CHC_ORGANIZATION_ID}/services/${CHC_SERVICE_ID}/clickpipes/${PIPE_ID}" \
      -H "Authorization: Bearer ${CHC_API_KEY}"

    echo "✓ ClickPipe deleted"
    rm -f "$PIPE_ID_FILE"
else
    echo "No pipe ID found, skipping pipe deletion"
fi

# Delete ClickHouse table
echo ""
echo "Deleting ClickHouse table: $TEST_TABLE_NAME"

clickhouse-client \
  --host="$CHC_HOST" \
  --user="$CHC_USER" \
  --password="$CHC_PASSWORD" \
  --secure \
  --query="DROP TABLE IF EXISTS $TEST_TABLE_NAME;"

echo "✓ Table deleted"

# Delete S3 data
echo ""
echo "Deleting S3 test data..."

aws s3 rm "s3://${AWS_S3_BUCKET}/${TEST_PREFIX}/" \
  --recursive \
  --region "$AWS_REGION"

echo "✓ S3 data deleted"

# Clean up local files
echo ""
echo "Cleaning up local files..."
rm -f .pause_time .resume_time .pipe_status_last.json
rm -rf /tmp/clickpipe-test

echo "✓ Local files cleaned"

echo ""
echo "=================================================="
echo "✅ Cleanup Complete!"
echo "=================================================="
