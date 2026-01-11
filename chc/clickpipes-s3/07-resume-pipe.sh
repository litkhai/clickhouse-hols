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
echo "Resume ClickPipe"
echo "=================================================="
echo "Pipe ID: $PIPE_ID"

# Record resume time
RESUME_TIME=$(date -u +"%Y-%m-%d %H:%M:%S")
echo "$RESUME_TIME" > .resume_time

echo "Resume Time: $RESUME_TIME UTC"

if [ -f .pause_time ]; then
    PAUSE_TIME=$(cat .pause_time)
    echo "Was Paused At: $PAUSE_TIME UTC"
fi

# Resume the pipe via API
echo ""
echo "Sending resume request..."

RESPONSE=$(curl -s -X POST \
  "https://api.clickhouse.cloud/v1/organizations/${CHC_ORGANIZATION_ID}/services/${CHC_SERVICE_ID}/clickpipes/${PIPE_ID}/resume" \
  -H "Authorization: Bearer ${CHC_API_KEY}")

echo ""
echo "API Response:"
echo "$RESPONSE" | jq '.'

echo ""
echo "✅ Resume request sent!"

# Wait a moment and check status
echo ""
echo "Waiting 10 seconds for ingestion to resume..."
sleep 10

echo ""
echo "Checking current status..."
./04-check-pipe-status.sh

echo ""
echo "=================================================="
echo "✅ Pipe Resumed Successfully!"
echo "=================================================="
echo "Resume time saved to .resume_time"
echo ""
echo "Next steps:"
echo "  1. Wait 1-2 minutes for ingestion to complete"
echo "  2. Run validation: ./08-validate-checkpoint.sh"
