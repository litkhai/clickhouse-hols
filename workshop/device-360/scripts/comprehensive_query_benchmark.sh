#!/bin/bash

# Comprehensive Query Benchmark with Concurrency Testing
# Tests query performance across different vCPU scales and concurrency levels

source /Users/kenlee/Documents/GitHub/clickhouse-hols/chc/tool/costkeeper/.credentials

RESULTS_DIR="/Users/kenlee/Documents/GitHub/clickhouse-hols/workshop/device-360/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${RESULTS_DIR}/comprehensive_benchmark_${TIMESTAMP}.md"

# Test configuration
DEVICE_IDS=(
    "37591b99-08a0-4bc1-9cc8-ceb6a7cbd693"
    "c940762f-0802-4bda-877e-3a18149e37fd"
    "166d4b90-cb45-4981-bdea-2be0bba44c90"
    "f2cda408-37d6-497e-92d4-58e706b2ef87"
    "eb21052a-aaf4-4910-a16f-6c7a0bfabeac"
)

# Get current vCPU scale
get_vcpu_scale() {
    clickhouse client --host=${CH_HOST} --user=${CH_USER} --password=${CH_PASSWORD} --secure \
        --query="SELECT value FROM system.settings WHERE name = 'max_threads'" 2>/dev/null
}

CURRENT_VCPU=$(get_vcpu_scale)

echo "# Comprehensive Query Benchmark Results" > $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "**Test Date**: $(date)" >> $RESULTS_FILE
echo "**vCPU Scale**: $CURRENT_VCPU" >> $RESULTS_FILE
echo "**Total Rows**: 448,000,000" >> $RESULTS_FILE
echo "**Index**: Bloom filter on device_id + ORDER BY (device_id, event_date, event_ts)" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "---" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Function to run query and measure time
run_query_timed() {
    local query="$1"
    local run_name="$2"

    START=$(date +%s.%N)
    clickhouse client --host=${CH_HOST} --user=${CH_USER} --password=${CH_PASSWORD} --secure \
        --query="$query" > /dev/null 2>&1
    END=$(date +%s.%N)

    ELAPSED=$(echo "$END - $START" | bc)
    echo "$ELAPSED"
}

# Clear caches
clear_caches() {
    clickhouse client --host=${CH_HOST} --user=${CH_USER} --password=${CH_PASSWORD} --secure \
        --query="SYSTEM DROP QUERY CACHE" 2>/dev/null || true
    clickhouse client --host=${CH_HOST} --user=${CH_USER} --password=${CH_PASSWORD} --secure \
        --query="SYSTEM DROP MARK CACHE" 2>/dev/null || true
    sleep 2
}

echo "## Part 1: Single Query Performance (Cold vs Warm Cache)" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Test Q1: Point Lookup
echo "### Q1: Single Device Point Lookup" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "\`\`\`sql" >> $RESULTS_FILE
echo "SELECT * FROM device360.ad_requests" >> $RESULTS_FILE
echo "WHERE device_id = '${DEVICE_IDS[0]}'" >> $RESULTS_FILE
echo "ORDER BY event_ts DESC LIMIT 1000" >> $RESULTS_FILE
echo "\`\`\`" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

clear_caches
echo "| Run | Cache State | Elapsed (sec) | Rows Returned |" >> $RESULTS_FILE
echo "|-----|-------------|---------------|---------------|" >> $RESULTS_FILE

Q1="SELECT * FROM device360.ad_requests WHERE device_id = '${DEVICE_IDS[0]}' ORDER BY event_ts DESC LIMIT 1000"

COLD_TIME=$(run_query_timed "$Q1" "cold")
echo "| 1 | Cold | $COLD_TIME | 1,000 |" >> $RESULTS_FILE

WARM1_TIME=$(run_query_timed "$Q1" "warm1")
echo "| 2 | Warm | $WARM1_TIME | 1,000 |" >> $RESULTS_FILE

WARM2_TIME=$(run_query_timed "$Q1" "warm2")
echo "| 3 | Warm | $WARM2_TIME | 1,000 |" >> $RESULTS_FILE

echo "" >> $RESULTS_FILE
echo "**Analysis**: Cold=$COLD_TIME sec, Warm avg=$(echo "scale=4; ($WARM1_TIME + $WARM2_TIME) / 2" | bc) sec" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Test Q2: Aggregation by device
echo "### Q2: Device Event Count by Date" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "\`\`\`sql" >> $RESULTS_FILE
echo "SELECT event_date, count() FROM device360.ad_requests" >> $RESULTS_FILE
echo "WHERE device_id = '${DEVICE_IDS[0]}' GROUP BY event_date ORDER BY event_date" >> $RESULTS_FILE
echo "\`\`\`" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

clear_caches
echo "| Run | Cache State | Elapsed (sec) |" >> $RESULTS_FILE
echo "|-----|-------------|---------------|" >> $RESULTS_FILE

Q2="SELECT event_date, count() FROM device360.ad_requests WHERE device_id = '${DEVICE_IDS[0]}' GROUP BY event_date ORDER BY event_date"

COLD_TIME=$(run_query_timed "$Q2" "cold")
echo "| 1 | Cold | $COLD_TIME |" >> $RESULTS_FILE

WARM1_TIME=$(run_query_timed "$Q2" "warm1")
echo "| 2 | Warm | $WARM1_TIME |" >> $RESULTS_FILE

WARM2_TIME=$(run_query_timed "$Q2" "warm2")
echo "| 3 | Warm | $WARM2_TIME |" >> $RESULTS_FILE

echo "" >> $RESULTS_FILE

# Test Q3: Full table aggregation
echo "### Q3: Daily Event Aggregation (Full Table Scan)" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "\`\`\`sql" >> $RESULTS_FILE
echo "SELECT event_date, count() as events, uniq(device_id) as unique_devices" >> $RESULTS_FILE
echo "FROM device360.ad_requests GROUP BY event_date ORDER BY event_date" >> $RESULTS_FILE
echo "\`\`\`" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

clear_caches
echo "| Run | Cache State | Elapsed (sec) |" >> $RESULTS_FILE
echo "|-----|-------------|---------------|" >> $RESULTS_FILE

Q3="SELECT event_date, count() as events, uniq(device_id) as unique_devices FROM device360.ad_requests GROUP BY event_date ORDER BY event_date"

COLD_TIME=$(run_query_timed "$Q3" "cold")
echo "| 1 | Cold | $COLD_TIME |" >> $RESULTS_FILE

WARM1_TIME=$(run_query_timed "$Q3" "warm1")
echo "| 2 | Warm | $WARM1_TIME |" >> $RESULTS_FILE

WARM2_TIME=$(run_query_timed "$Q3" "warm2")
echo "| 3 | Warm | $WARM2_TIME |" >> $RESULTS_FILE

echo "" >> $RESULTS_FILE
echo "---" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Part 2: Concurrency Testing
echo "## Part 2: Concurrency Testing" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "Testing query performance under concurrent load." >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Function to run concurrent queries
run_concurrent_queries() {
    local query="$1"
    local concurrency="$2"
    local iterations="$3"

    local total_time=0
    local temp_dir=$(mktemp -d)

    for ((i=1; i<=$iterations; i++)); do
        START=$(date +%s.%N)

        # Run queries in parallel
        for ((j=1; j<=$concurrency; j++)); do
            {
                clickhouse client --host=${CH_HOST} --user=${CH_USER} --password=${CH_PASSWORD} --secure \
                    --query="$query" > /dev/null 2>&1
            } &
        done

        # Wait for all to complete
        wait

        END=$(date +%s.%N)
        ELAPSED=$(echo "$END - $START" | bc)
        total_time=$(echo "$total_time + $ELAPSED" | bc)
    done

    rm -rf "$temp_dir"

    # Calculate average
    AVG=$(echo "scale=4; $total_time / $iterations" | bc)
    echo "$AVG"
}

echo "### Test 2.1: Point Lookup Concurrency" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "Query: Single device point lookup (1000 rows)" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

clear_caches
echo "| Concurrency | Iterations | Avg Time (sec) | Queries/sec | Latency per Query (ms) |" >> $RESULTS_FILE
echo "|-------------|------------|----------------|-------------|------------------------|" >> $RESULTS_FILE

Q_POINT="SELECT * FROM device360.ad_requests WHERE device_id = '${DEVICE_IDS[0]}' ORDER BY event_ts DESC LIMIT 1000"

for CONCUR in 1 4 8 16; do
    AVG_TIME=$(run_concurrent_queries "$Q_POINT" $CONCUR 3)
    QPS=$(echo "scale=2; $CONCUR / $AVG_TIME" | bc)
    LATENCY=$(echo "scale=2; $AVG_TIME * 1000 / $CONCUR" | bc)
    echo "| $CONCUR | 3 | $AVG_TIME | $QPS | $LATENCY |" >> $RESULTS_FILE
done

echo "" >> $RESULTS_FILE

echo "### Test 2.2: Aggregation Concurrency" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "Query: Daily event aggregation (full table scan)" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

clear_caches
echo "| Concurrency | Iterations | Avg Time (sec) | Queries/sec |" >> $RESULTS_FILE
echo "|-------------|------------|----------------|-------------|" >> $RESULTS_FILE

Q_AGG="SELECT event_date, count() FROM device360.ad_requests GROUP BY event_date"

for CONCUR in 1 2 4; do
    AVG_TIME=$(run_concurrent_queries "$Q_AGG" $CONCUR 2)
    QPS=$(echo "scale=2; $CONCUR / $AVG_TIME" | bc)
    echo "| $CONCUR | 2 | $AVG_TIME | $QPS |" >> $RESULTS_FILE
done

echo "" >> $RESULTS_FILE
echo "---" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Part 3: Query Variety Performance
echo "## Part 3: Query Variety Performance" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Q4: Top devices
echo "### Q4: Top 100 Devices by Event Count" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
clear_caches
Q4="SELECT device_id, count() as event_count FROM device360.ad_requests GROUP BY device_id ORDER BY event_count DESC LIMIT 100"
TIME=$(run_query_timed "$Q4" "cold")
echo "**Cold cache**: $TIME sec" >> $RESULTS_FILE
TIME=$(run_query_timed "$Q4" "warm")
echo "**Warm cache**: $TIME sec" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Q5: Geographic distribution
echo "### Q5: Geographic Distribution" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
clear_caches
Q5="SELECT country, city, count() as requests FROM device360.ad_requests GROUP BY country, city ORDER BY requests DESC LIMIT 50"
TIME=$(run_query_timed "$Q5" "cold")
echo "**Cold cache**: $TIME sec" >> $RESULTS_FILE
TIME=$(run_query_timed "$Q5" "warm")
echo "**Warm cache**: $TIME sec" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Q6: App performance
echo "### Q6: App Performance Analysis" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
clear_caches
Q6="SELECT app_name, count() as total_requests, uniq(device_id) as unique_devices, sum(click) as total_clicks FROM device360.ad_requests GROUP BY app_name ORDER BY total_requests DESC LIMIT 20"
TIME=$(run_query_timed "$Q6" "cold")
echo "**Cold cache**: $TIME sec" >> $RESULTS_FILE
TIME=$(run_query_timed "$Q6" "warm")
echo "**Warm cache**: $TIME sec" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

echo "---" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "**Benchmark completed at**: $(date)" >> $RESULTS_FILE
echo "**Total runtime**: $(date +%s) seconds" >> $RESULTS_FILE

echo ""
echo "========================================"
echo "Comprehensive Benchmark Complete!"
echo "Results saved to: $RESULTS_FILE"
echo "========================================"
