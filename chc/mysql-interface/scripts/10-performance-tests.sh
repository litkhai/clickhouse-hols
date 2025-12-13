#!/bin/bash
# 성능 테스트 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${BASE_DIR}/config/chc-config.sh"
RESULT_FILE="${BASE_DIR}/test-results/performance.json"

source "${CONFIG_FILE}"

echo "성능 테스트 실행 중..."
echo ""

export RESULT_FILE

python3 << 'EOF'
import json
import sys
import mysql.connector
from datetime import datetime
import time
import os

results = {"test_name": "Performance Tests", "timestamp": datetime.now().isoformat(), "tests": []}

def add_test_result(test_name, passed, message="", duration=0, throughput=0):
    results["tests"].append({
        "name": test_name,
        "passed": passed,
        "message": message,
        "duration_ms": duration,
        "throughput": throughput
    })
    print(f"{'✓' if passed else '✗'} {test_name}: {message} (Duration: {duration:.2f}ms, Throughput: {throughput:.2f} ops/sec)")

try:
    connection = mysql.connector.connect(
        host=os.environ['CHC_HOST'],
        port=int(os.environ['CHC_MYSQL_PORT']),
        user=os.environ['CHC_USER'],
        password=os.environ['CHC_PASSWORD'],
        database='mysql_interface',
        ssl_disabled=False
    )
    cursor = connection.cursor()

    # Test 1: Simple Query Performance
    iterations = 100
    start_time = time.time()
    for i in range(iterations):
        cursor.execute("SELECT 1")
        cursor.fetchone()
    duration = (time.time() - start_time) * 1000
    throughput = iterations / (duration / 1000)
    add_test_result("Simple Query", True, f"{iterations} iterations", duration=duration, throughput=throughput)

    # Test 2: Aggregation Performance
    start_time = time.time()
    cursor.execute("""
        SELECT
            COUNT(*) as cnt,
            SUM(number) as total,
            AVG(number) as avg
        FROM system.numbers
        LIMIT 10000
    """)
    result = cursor.fetchall()
    duration = (time.time() - start_time) * 1000
    add_test_result("Aggregation Query", len(result) > 0, "10K rows", duration=duration, throughput=10000/(duration/1000))

    # Test 3: Batch Insert Performance
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS test_perf (
            id INT,
            value INT,
            text VARCHAR(100)
        ) ENGINE = MergeTree() ORDER BY id
    """)

    batch_size = 1000
    data = [(i, i*10, f'text_{i}') for i in range(batch_size)]

    start_time = time.time()
    cursor.executemany("INSERT INTO test_perf VALUES (%s, %s, %s)", data)
    duration = (time.time() - start_time) * 1000
    throughput = batch_size / (duration / 1000)
    add_test_result("Batch Insert", True, f"{batch_size} rows", duration=duration, throughput=throughput)

    # Test 4: Scan Performance
    start_time = time.time()
    cursor.execute("SELECT COUNT(*) FROM test_perf")
    count = cursor.fetchone()[0]
    duration = (time.time() - start_time) * 1000
    add_test_result("Table Scan", count == batch_size, f"Scanned {count} rows", duration=duration, throughput=count/(duration/1000))

    # Cleanup
    cursor.execute("DROP TABLE IF EXISTS test_perf")

    cursor.close()
    connection.close()

    with open(os.environ['RESULT_FILE'], 'w') as f:
        json.dump(results, f, indent=2)

    total = len(results["tests"])
    passed = sum(1 for t in results["tests"] if t["passed"])
    avg_throughput = sum(t["throughput"] for t in results["tests"]) / total if total > 0 else 0

    print(f"\n통계: {passed}/{total} 테스트 통과")
    print(f"평균 처리량: {avg_throughput:.2f} ops/sec")

    sys.exit(0 if passed == total else 1)

except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
EOF

exit $?
