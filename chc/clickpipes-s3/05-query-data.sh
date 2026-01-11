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
echo "Query Ingested Data"
echo "=================================================="

QUERY_TYPE=${1:-"summary"}

case $QUERY_TYPE in
  "summary")
    echo "Query: Data Summary"
    clickhouse-client \
      --host="$CHC_HOST" \
      --user="$CHC_USER" \
      --password="$CHC_PASSWORD" \
      --secure \
      --query="
      SELECT
          _path,
          _file,
          min(_time) AS first_inserted,
          max(_time) AS last_inserted,
          count() AS row_count
      FROM $TEST_TABLE_NAME
      GROUP BY _path, _file
      ORDER BY first_inserted
      FORMAT PrettyCompact;
      "
    ;;

  "duplicates")
    echo "Query: Check for Duplicates"
    clickhouse-client \
      --host="$CHC_HOST" \
      --user="$CHC_USER" \
      --password="$CHC_PASSWORD" \
      --secure \
      --query="
      SELECT
          _path,
          count() AS insert_count,
          groupArray(_time) AS insert_times
      FROM $TEST_TABLE_NAME
      GROUP BY _path
      HAVING insert_count > 3  -- Each file has 3 rows
      ORDER BY insert_count DESC
      FORMAT PrettyCompact;
      "
    ;;

  "timeline")
    echo "Query: Ingestion Timeline"
    clickhouse-client \
      --host="$CHC_HOST" \
      --user="$CHC_USER" \
      --password="$CHC_PASSWORD" \
      --secure \
      --query="
      SELECT
          toStartOfMinute(_time) AS minute,
          count() AS rows_inserted,
          groupUniqArray(_file) AS files
      FROM $TEST_TABLE_NAME
      GROUP BY minute
      ORDER BY minute
      FORMAT PrettyCompact;
      "
    ;;

  "count")
    echo "Query: Total Count"
    clickhouse-client \
      --host="$CHC_HOST" \
      --user="$CHC_USER" \
      --password="$CHC_PASSWORD" \
      --secure \
      --query="
      SELECT
          count() AS total_rows,
          countDistinct(_path) AS unique_files,
          min(_time) AS first_insert,
          max(_time) AS last_insert
      FROM $TEST_TABLE_NAME
      FORMAT Vertical;
      "
    ;;

  "all")
    echo "Query: All Data"
    clickhouse-client \
      --host="$CHC_HOST" \
      --user="$CHC_USER" \
      --password="$CHC_PASSWORD" \
      --secure \
      --query="
      SELECT *
      FROM $TEST_TABLE_NAME
      ORDER BY _time, _path
      FORMAT PrettyCompact;
      "
    ;;

  *)
    echo "Unknown query type: $QUERY_TYPE"
    echo ""
    echo "Usage: $0 [summary|duplicates|timeline|count|all]"
    echo ""
    echo "  summary    - Show files and ingestion times (default)"
    echo "  duplicates - Check for duplicate ingestions"
    echo "  timeline   - Show ingestion timeline by minute"
    echo "  count      - Show total counts"
    echo "  all        - Show all data"
    exit 1
    ;;
esac

echo ""
echo "Query complete!"
echo ""
echo "Tip: You can also run with different query types:"
echo "  ./05-query-data.sh summary"
echo "  ./05-query-data.sh duplicates"
echo "  ./05-query-data.sh timeline"
echo "  ./05-query-data.sh count"
echo "  ./05-query-data.sh all"
