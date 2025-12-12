#!/bin/bash

# Device360 Query Benchmark Script
# Tests query performance with cold and warm cache

source /Users/kenlee/Documents/GitHub/clickhouse-hols/chc/tool/costkeeper/.credentials

DEVICE_ID="37591b99-08a0-4bc1-9cc8-ceb6a7cbd693"
RESULTS_FILE="/Users/kenlee/Documents/GitHub/clickhouse-hols/workshop/device-360/results/query_benchmark_$(date +%Y%m%d_%H%M%S).md"

echo "# Device360 Query Benchmark Results" > $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "**Test Date**: $(date)" >> $RESULTS_FILE
echo "**vCPU Scale**: 32" >> $RESULTS_FILE
echo "**Total Rows**: 448,000,000" >> $RESULTS_FILE
echo "**Test Device ID**: $DEVICE_ID" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "---" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

run_query() {
    local query_name="$1"
    local query="$2"
    local target="$3"

    echo "" >> $RESULTS_FILE
    echo "## $query_name" >> $RESULTS_FILE
    echo "**Target**: < $target" >> $RESULTS_FILE
    echo "" >> $RESULTS_FILE
    echo "\`\`\`sql" >> $RESULTS_FILE
    echo "$query" >> $RESULTS_FILE
    echo "\`\`\`" >> $RESULTS_FILE
    echo "" >> $RESULTS_FILE

    # Clear caches
    echo "Clearing caches..." >> $RESULTS_FILE
    clickhouse client --host=${CH_HOST} --user=${CH_USER} --password=${CH_PASSWORD} --secure --query="SYSTEM DROP QUERY CACHE" 2>/dev/null || true
    clickhouse client --host=${CH_HOST} --user=${CH_USER} --password=${CH_PASSWORD} --secure --query="SYSTEM DROP MARK CACHE" 2>/dev/null || true
    sleep 2

    echo "| Run | Elapsed Time | Rows | Status |" >> $RESULTS_FILE
    echo "|-----|--------------|------|--------|" >> $RESULTS_FILE

    for run in 1 2 3; do
        echo "Running $query_name - Run $run..."

        RESULT=$(clickhouse client --host=${CH_HOST} --user=${CH_USER} --password=${CH_PASSWORD} --secure \
            --query="$query" --time 2>&1)

        ELAPSED=$(echo "$RESULT" | grep "Elapsed:" | awk '{print $2}' | sed 's/s\.//')
        ROWS=$(echo "$RESULT" | grep "rows in set" | awk '{print $1}')

        if [ -z "$ELAPSED" ]; then
            ELAPSED="error"
        fi

        if [ -z "$ROWS" ]; then
            ROWS="N/A"
        fi

        if [ "$run" -eq 1 ]; then
            echo "| $run (cold) | $ELAPSED sec | $ROWS | ✓ |" >> $RESULTS_FILE
        else
            echo "| $run (warm) | $ELAPSED sec | $ROWS | ✓ |" >> $RESULTS_FILE
        fi

        sleep 1
    done

    echo "" >> $RESULTS_FILE
}

# Query 1: Single Device Point Lookup
run_query "Q1: Single Device Point Lookup" \
"SELECT * FROM device360.ad_requests WHERE device_id = '$DEVICE_ID' ORDER BY event_ts DESC LIMIT 1000" \
"100ms"

# Query 2: Device Event Count by Date
run_query "Q2: Device Event Count by Date" \
"SELECT event_date, count() as events FROM device360.ad_requests WHERE device_id = '$DEVICE_ID' GROUP BY event_date ORDER BY event_date" \
"50ms"

# Query 3: Device Timeline with Apps
run_query "Q3: Device Timeline with Apps" \
"SELECT event_ts, app_name, city, country, device_brand, device_model, click FROM device360.ad_requests WHERE device_id = '$DEVICE_ID' ORDER BY event_ts" \
"500ms"

# Query 4: Device First/Last Touch
run_query "Q4: Device First/Last Touch Attribution" \
"SELECT
    device_id,
    argMin(app_name, event_ts) as first_app,
    argMin(country, event_ts) as first_country,
    min(event_ts) as first_seen,
    argMax(app_name, event_ts) as last_app,
    argMax(country, event_ts) as last_country,
    max(event_ts) as last_seen,
    dateDiff('day', min(event_ts), max(event_ts)) as lifetime_days,
    count() as total_events
FROM device360.ad_requests
WHERE device_id = '$DEVICE_ID'
GROUP BY device_id" \
"100ms"

# Query 5: Hourly Activity Pattern
run_query "Q5: Hourly Activity Pattern" \
"SELECT event_hour, count() as requests FROM device360.ad_requests WHERE device_id = '$DEVICE_ID' GROUP BY event_hour ORDER BY event_hour" \
"50ms"

# Query 6: Top Devices by Event Count
run_query "Q6: Top 100 Devices by Event Count" \
"SELECT device_id, count() as event_count, uniq(app_name) as unique_apps, uniq(city) as unique_cities FROM device360.ad_requests GROUP BY device_id ORDER BY event_count DESC LIMIT 100" \
"5 seconds"

# Query 7: Daily Aggregation
run_query "Q7: Daily Event Aggregation" \
"SELECT event_date, count() as events, uniq(device_id) as unique_devices, avg(click) as click_rate FROM device360.ad_requests GROUP BY event_date ORDER BY event_date" \
"2 seconds"

# Query 8: App Performance Analysis
run_query "Q8: App Performance Analysis" \
"SELECT app_name, count() as total_requests, uniq(device_id) as unique_devices, sum(click) as total_clicks, sum(click) / count() * 100 as ctr FROM device360.ad_requests GROUP BY app_name ORDER BY total_requests DESC LIMIT 20" \
"3 seconds"

# Query 9: Geographic Distribution
run_query "Q9: Geographic Distribution" \
"SELECT country, city, count() as requests, uniq(device_id) as unique_devices FROM device360.ad_requests GROUP BY country, city ORDER BY requests DESC LIMIT 50" \
"3 seconds"

# Query 10: Device Brand Analysis
run_query "Q10: Device Brand & Model Analysis" \
"SELECT device_brand, device_model, count() as requests, uniq(device_id) as unique_devices FROM device360.ad_requests GROUP BY device_brand, device_model ORDER BY requests DESC LIMIT 30" \
"2 seconds"

echo "" >> $RESULTS_FILE
echo "---" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "**Benchmark completed at**: $(date)" >> $RESULTS_FILE

echo ""
echo "========================================" echo "Query Benchmark Complete!"
echo "Results saved to: $RESULTS_FILE"
echo "========================================"
