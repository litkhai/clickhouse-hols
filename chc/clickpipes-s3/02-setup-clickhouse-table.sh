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
echo "ClickPipes S3 Test - ClickHouse Table Setup"
echo "=================================================="

echo ""
echo "Connecting to ClickHouse Cloud..."
echo "Host: $CHC_HOST"
echo "User: $CHC_USER"
echo "Table: $TEST_TABLE_NAME"

# Create the test table
clickhouse-client \
  --host="$CHC_HOST" \
  --user="$CHC_USER" \
  --password="$CHC_PASSWORD" \
  --secure \
  --query="
DROP TABLE IF EXISTS $TEST_TABLE_NAME;

CREATE TABLE $TEST_TABLE_NAME
(
    id UInt32,
    date String,
    value String,
    _file String,
    _path String,
    _time DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (date, id);
"

echo ""
echo "✅ Table created successfully!"

echo ""
echo "Verifying table..."

clickhouse-client \
  --host="$CHC_HOST" \
  --user="$CHC_USER" \
  --password="$CHC_PASSWORD" \
  --secure \
  --query="
DESCRIBE TABLE $TEST_TABLE_NAME FORMAT Vertical;
"

echo ""
echo "=================================================="
echo "✅ ClickHouse Table Setup Complete!"
echo "=================================================="
echo ""
echo "Next step: Run ./03-create-clickpipe.sh"
