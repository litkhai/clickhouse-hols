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
echo "Pause ClickPipe"
echo "=================================================="
echo "Pipe ID: $PIPE_ID"

# Record pause time
PAUSE_TIME=$(date -u +"%Y-%m-%d %H:%M:%S")
echo "$PAUSE_TIME" > .pause_time

echo "Pause Time: $PAUSE_TIME UTC"

# Pause the pipe via API
echo ""
echo "Sending pause request..."

RESPONSE=$(curl -s -X POST \
  "https://api.clickhouse.cloud/v1/organizations/${CHC_ORGANIZATION_ID}/services/${CHC_SERVICE_ID}/clickpipes/${PIPE_ID}/pause" \
  -H "Authorization: Bearer ${CHC_API_KEY}")

echo ""
echo "API Response:"
echo "$RESPONSE" | jq '.'

echo ""
echo "✅ Pause request sent!"

# Wait a moment and check status
echo ""
echo "Waiting 5 seconds..."
sleep 5

echo ""
echo "Checking current status..."
./04-check-pipe-status.sh

echo ""
echo "Recording state before pause..."
./05-query-data.sh count

echo ""
echo "=================================================="
echo "✅ Pipe Paused Successfully!"
echo "=================================================="
echo "Pause time saved to .pause_time"
echo ""
echo "Next step: Wait 1-2 minutes, then resume with ./07-resume-pipe.sh"
