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
echo "ClickPipes S3 Test - Create ClickPipe"
echo "=================================================="

# Save the pipe ID to a file for later use
PIPE_ID_FILE=".pipe_id"

echo ""
echo "Creating ClickPipe via API..."
echo "Organization: $CHC_ORGANIZATION_ID"
echo "Service: $CHC_SERVICE_ID"
echo "Pipe Name: $TEST_PIPE_NAME"

# Create the ClickPipe using the API
RESPONSE=$(curl -s -X POST \
  "https://api.clickhouse.cloud/v1/organizations/${CHC_ORGANIZATION_ID}/services/${CHC_SERVICE_ID}/clickpipes" \
  -H "Authorization: Bearer ${CHC_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"${TEST_PIPE_NAME}\",
    \"description\": \"Test pipe for checkpoint validation\",
    \"source_type\": \"s3\",
    \"source_config\": {
      \"bucket\": \"${AWS_S3_BUCKET}\",
      \"region\": \"${AWS_REGION}\",
      \"path_prefix\": \"${TEST_PREFIX}/\",
      \"format\": \"JSONEachRow\",
      \"access_key_id\": \"${AWS_ACCESS_KEY_ID}\",
      \"secret_access_key\": \"${AWS_SECRET_ACCESS_KEY}\"
    },
    \"destination_table\": \"${TEST_TABLE_NAME}\",
    \"settings\": {
      \"max_insert_block_size\": \"100000\"
    }
  }")

echo ""
echo "API Response:"
echo "$RESPONSE" | jq '.'

# Extract pipe ID from response
PIPE_ID=$(echo "$RESPONSE" | jq -r '.id // .pipe_id // empty')

if [ -z "$PIPE_ID" ] || [ "$PIPE_ID" = "null" ]; then
    echo ""
    echo "❌ Error: Failed to create ClickPipe or extract pipe ID"
    echo "Response: $RESPONSE"
    exit 1
fi

# Save pipe ID for later use
echo "$PIPE_ID" > "$PIPE_ID_FILE"

echo ""
echo "✅ ClickPipe created successfully!"
echo "Pipe ID: $PIPE_ID"
echo "Pipe ID saved to $PIPE_ID_FILE"

echo ""
echo "Waiting for pipe to start ingesting data..."
sleep 10

echo ""
echo "Checking pipe status..."
./04-check-pipe-status.sh

echo ""
echo "=================================================="
echo "✅ ClickPipe Creation Complete!"
echo "=================================================="
echo ""
echo "The pipe is now running and ingesting data from S3."
echo ""
echo "Next steps:"
echo "  1. Monitor ingestion: ./04-check-pipe-status.sh"
echo "  2. Query data: ./05-query-data.sh"
echo "  3. When ready to test, pause: ./06-pause-pipe.sh"
