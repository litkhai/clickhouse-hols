#!/bin/bash

# Two refusals worth seeing once: the layout without its setting, and dictGet on
# a dictionary that holds a model. They raise exceptions, so they run here.

CH="docker exec -i clickhouse-26-10 clickhouse-client"

echo "================================"
echo "ClickHouse 26.10: XGBoost dictionary Test"
echo "================================"
echo ""

cat 05-xgboost.sql | $CH --multiline --multiquery

refused() {
    echo "-- $1"
    $CH -q "$2" 2>&1 | grep -o 'Code: [0-9]*\..*' | head -1
    echo ""
}

echo ""
echo "════════ 6. What it refuses ════════"
echo ""

refused "6a. predictXGBoost without enable_xgboost" \
    "SELECT predictXGBoost('xg.late_model', 10., 20., 18.)"

refused "6b. dictGet: there are no rows to look up" \
    "SELECT dictGet('xg.late_model', 'late', (10., 20., 18.)) SETTINGS enable_xgboost = 1"

echo "================================"
echo "Test complete!"
echo "================================"
