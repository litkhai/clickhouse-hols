#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found."
    exit 1
fi

PIPE_ID_FILE=".pipe_id"

if [ ! -f "$PIPE_ID_FILE" ]; then
    echo "Error: Pipe ID file not found. Please run ./03-create-clickpipe.sh first."
    exit 1
fi

PIPE_ID=$(cat "$PIPE_ID_FILE")

echo "=================================================="
echo "ClickPipe Status Check"
echo "=================================================="
echo "Pipe ID: $PIPE_ID"

# Get pipe status from API
RESPONSE=$(curl -s -X GET \
  "https://api.clickhouse.cloud/v1/organizations/${CHC_ORGANIZATION_ID}/services/${CHC_SERVICE_ID}/clickpipes/${PIPE_ID}" \
  -H "Authorization: Bearer ${CHC_API_KEY}")

echo ""
echo "Current Status:"
echo "$RESPONSE" | jq '{
  id: .id,
  name: .name,
  state: .state,
  status: .status,
  files_ingested: .stats.files_processed,
  rows_ingested: .stats.rows_processed,
  last_updated: .updated_at
}'

# Save full response for debugging
echo "$RESPONSE" > .pipe_status_last.json

echo ""
echo "Full response saved to .pipe_status_last.json"
