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
echo "Validate Checkpoint Behavior"
echo "=================================================="

# Check if pause/resume times exist
if [ -f .pause_time ] && [ -f .resume_time ]; then
    PAUSE_TIME=$(cat .pause_time)
    RESUME_TIME=$(cat .resume_time)
    echo "Pause Time:  $PAUSE_TIME UTC"
    echo "Resume Time: $RESUME_TIME UTC"
    HAVE_TIMES=true
else
    echo "⚠️  Warning: Pause/resume times not found"
    HAVE_TIMES=false
fi

echo ""
echo "=================================================="
echo "Test 1: Check for Duplicate Ingestions"
echo "=================================================="

DUPLICATES=$(clickhouse-client \
  --host="$CHC_HOST" \
  --user="$CHC_USER" \
  --password="$CHC_PASSWORD" \
  --secure \
  --query="
  SELECT
      _path,
      count() AS insert_count
  FROM $TEST_TABLE_NAME
  GROUP BY _path
  HAVING insert_count > 3
  FORMAT JSONCompact;" | jq -r '.rows | length')

echo ""
if [ "$DUPLICATES" -eq 0 ]; then
    echo "✅ PASS: No duplicate files detected!"
    echo "   Each file appears to be ingested exactly once (3 rows per file)"
    CHECKPOINT_WORKS=true
else
    echo "❌ FAIL: Found $DUPLICATES files with duplicate ingestions!"
    echo ""
    echo "Details:"
    clickhouse-client \
      --host="$CHC_HOST" \
      --user="$CHC_USER" \
      --password="$CHC_PASSWORD" \
      --secure \
      --query="
      SELECT
          _path,
          count() AS insert_count,
          groupArray(toString(_time)) AS insert_times
      FROM $TEST_TABLE_NAME
      GROUP BY _path
      HAVING insert_count > 3
      ORDER BY insert_count DESC
      FORMAT PrettyCompact;"
    CHECKPOINT_WORKS=false
fi

echo ""
echo "=================================================="
echo "Test 2: Verify All Files Were Ingested"
echo "=================================================="

EXPECTED_FILES=12
EXPECTED_ROWS=36  # 12 files × 3 rows each

ACTUAL=$(clickhouse-client \
  --host="$CHC_HOST" \
  --user="$CHC_USER" \
  --password="$CHC_PASSWORD" \
  --secure \
  --query="
  SELECT
      countDistinct(_path) AS unique_files,
      count() AS total_rows
  FROM $TEST_TABLE_NAME
  FORMAT JSONCompact;" | jq -r '.data[0]')

ACTUAL_FILES=$(echo "$ACTUAL" | jq -r '.[0]')
ACTUAL_ROWS=$(echo "$ACTUAL" | jq -r '.[1]')

echo ""
echo "Expected: $EXPECTED_FILES files, $EXPECTED_ROWS rows"
echo "Actual:   $ACTUAL_FILES files, $ACTUAL_ROWS rows"

if [ "$ACTUAL_FILES" -eq "$EXPECTED_FILES" ] && [ "$ACTUAL_ROWS" -eq "$EXPECTED_ROWS" ]; then
    echo "✅ PASS: All files ingested correctly!"
    ALL_FILES_INGESTED=true
elif [ "$ACTUAL_FILES" -eq "$EXPECTED_FILES" ] && [ "$ACTUAL_ROWS" -gt "$EXPECTED_ROWS" ]; then
    echo "⚠️  WARNING: All files present but row count is higher (possible duplicates)"
    ALL_FILES_INGESTED=false
else
    echo "❌ FAIL: File or row count mismatch!"
    ALL_FILES_INGESTED=false
fi

if [ "$HAVE_TIMES" = true ]; then
    echo ""
    echo "=================================================="
    echo "Test 3: Analyze Pause/Resume Timeline"
    echo "=================================================="

    echo ""
    echo "Before Pause:"
    clickhouse-client \
      --host="$CHC_HOST" \
      --user="$CHC_USER" \
      --password="$CHC_PASSWORD" \
      --secure \
      --query="
      SELECT
          count() AS row_count,
          countDistinct(_path) AS unique_files,
          groupUniqArray(substring(_path, position(_path, 'ym=') + 3, 6)) AS months
      FROM $TEST_TABLE_NAME
      WHERE _time < toDateTime('$PAUSE_TIME')
      FORMAT Vertical;"

    echo ""
    echo "After Resume:"
    clickhouse-client \
      --host="$CHC_HOST" \
      --user="$CHC_USER" \
      --password="$CHC_PASSWORD" \
      --secure \
      --query="
      SELECT
          count() AS row_count,
          countDistinct(_path) AS unique_files,
          groupUniqArray(substring(_path, position(_path, 'ym=') + 3, 6)) AS months
      FROM $TEST_TABLE_NAME
      WHERE _time >= toDateTime('$RESUME_TIME')
      FORMAT Vertical;"

    echo ""
    echo "Ingestion Timeline:"
    clickhouse-client \
      --host="$CHC_HOST" \
      --user="$CHC_USER" \
      --password="$CHC_PASSWORD" \
      --secure \
      --query="
      SELECT
          toStartOfMinute(_time) AS minute,
          count() AS rows_inserted,
          length(groupUniqArray(_file)) AS unique_files,
          if(minute < toDateTime('$PAUSE_TIME'), 'before_pause',
             if(minute >= toDateTime('$RESUME_TIME'), 'after_resume', 'during_pause')) AS phase
      FROM $TEST_TABLE_NAME
      GROUP BY minute
      ORDER BY minute
      FORMAT PrettyCompact;"
fi

echo ""
echo "=================================================="
echo "Test Summary"
echo "=================================================="

if [ "$CHECKPOINT_WORKS" = true ] && [ "$ALL_FILES_INGESTED" = true ]; then
    echo ""
    echo "🎉 ✅ ALL TESTS PASSED!"
    echo ""
    echo "Conclusion:"
    echo "  - ClickPipes S3 successfully maintains checkpoints"
    echo "  - Pause/Resume works without data duplication"
    echo "  - All files were ingested exactly once"
    echo ""
    echo "Customer Guidance:"
    echo "  ✅ Safe to pause and resume S3 ClickPipes"
    echo "  ✅ No deduplication logic needed in the table"
    echo "  ✅ Checkpoint mechanism is reliable"
else
    echo ""
    echo "⚠️  TESTS FAILED - Issues Detected"
    echo ""
    if [ "$CHECKPOINT_WORKS" = false ]; then
        echo "  ❌ Checkpointing does not work - duplicates found"
        echo "     Customer must implement deduplication logic"
        echo "     Consider using ReplacingMergeTree or similar"
    fi
    if [ "$ALL_FILES_INGESTED" = false ]; then
        echo "  ❌ Not all files were ingested correctly"
        echo "     Check pipe logs for errors"
    fi
fi

echo ""
echo "Full data summary:"
./05-query-data.sh summary

echo ""
echo "=================================================="
echo "Validation Complete!"
echo "=================================================="
