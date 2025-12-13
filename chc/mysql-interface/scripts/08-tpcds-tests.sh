#!/bin/bash
# TPC-DS 벤치마크 테스트 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${BASE_DIR}/config/chc-config.sh"
RESULT_FILE="${BASE_DIR}/test-results/tpcds.json"

source "${CONFIG_FILE}"

echo "TPC-DS 벤치마크 테스트 실행 중..."
echo ""

export RESULT_FILE

python3 << 'EOF'
import json
import sys
import mysql.connector
from datetime import datetime
import time
import os

results = {"test_name": "TPC-DS Benchmark Tests", "timestamp": datetime.now().isoformat(), "tests": []}

def add_test_result(test_name, passed, message="", error="", duration=0):
    results["tests"].append({
        "name": test_name,
        "passed": passed,
        "message": message,
        "error": error,
        "duration_ms": duration
    })
    print(f"{'✓' if passed else '✗'} {test_name}: {message if message else error} ({duration:.2f}ms)")

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

    # 데이터베이스 및 테이블 존재 확인
    cursor.execute("SHOW DATABASES LIKE 'mysql_interface'")
    if not cursor.fetchone():
        cursor.execute("CREATE DATABASE mysql_interface")
        print("✓ Database created: mysql_interface")

    cursor.execute("USE mysql_interface")

    # TPC-DS 쿼리 테스트 (간단한 버전)

    # Q1: Simple Aggregation
    try:
        start_time = time.time()
        cursor.execute("""
            SELECT
                COUNT(*) as total_count,
                COUNT(DISTINCT name) as unique_names
            FROM system.tables
            WHERE database = 'system'
        """)
        result = cursor.fetchall()
        duration = (time.time() - start_time) * 1000
        add_test_result("Q1: Simple Aggregation", len(result) > 0, f"Rows: {len(result)}", duration=duration)
    except Exception as e:
        add_test_result("Q1: Simple Aggregation", False, error=str(e))

    # Q2: GROUP BY with ORDER BY
    try:
        start_time = time.time()
        cursor.execute("""
            SELECT
                database,
                COUNT(*) as table_count,
                SUM(total_rows) as total_rows
            FROM system.tables
            WHERE database != ''
            GROUP BY database
            ORDER BY total_rows DESC
            LIMIT 10
        """)
        result = cursor.fetchall()
        duration = (time.time() - start_time) * 1000
        add_test_result("Q2: GROUP BY", len(result) > 0, f"Groups: {len(result)}", duration=duration)
    except Exception as e:
        add_test_result("Q2: GROUP BY", False, error=str(e))

    # Q3: HAVING Clause
    try:
        start_time = time.time()
        cursor.execute("""
            SELECT
                database,
                COUNT(*) as cnt
            FROM system.tables
            GROUP BY database
            HAVING COUNT(*) > 1
        """)
        result = cursor.fetchall()
        duration = (time.time() - start_time) * 1000
        add_test_result("Q3: HAVING", True, f"Groups: {len(result)}", duration=duration)
    except Exception as e:
        add_test_result("Q3: HAVING", False, error=str(e))

    # Q4: Subquery
    try:
        start_time = time.time()
        cursor.execute("""
            SELECT name, total_rows
            FROM system.tables
            WHERE total_rows > (
                SELECT AVG(total_rows) FROM system.tables WHERE total_rows > 0
            )
            LIMIT 10
        """)
        result = cursor.fetchall()
        duration = (time.time() - start_time) * 1000
        add_test_result("Q4: Subquery", True, f"Rows: {len(result)}", duration=duration)
    except Exception as e:
        add_test_result("Q4: Subquery", False, error=str(e))

    # Q5: CASE WHEN
    try:
        start_time = time.time()
        cursor.execute("""
            SELECT
                name,
                CASE
                    WHEN total_rows = 0 THEN 'Empty'
                    WHEN total_rows < 1000 THEN 'Small'
                    WHEN total_rows < 100000 THEN 'Medium'
                    ELSE 'Large'
                END as size_category
            FROM system.tables
            WHERE database = 'system'
            LIMIT 20
        """)
        result = cursor.fetchall()
        duration = (time.time() - start_time) * 1000
        add_test_result("Q5: CASE WHEN", len(result) > 0, f"Rows: {len(result)}", duration=duration)
    except Exception as e:
        add_test_result("Q5: CASE WHEN", False, error=str(e))

    # Q6: JOIN (using system tables)
    try:
        start_time = time.time()
        cursor.execute("""
            SELECT
                t.database,
                t.name,
                c.name as column_name,
                c.type
            FROM system.tables t
            JOIN system.columns c ON t.database = c.database AND t.name = c.table
            WHERE t.database = 'system' AND t.name = 'tables'
            LIMIT 20
        """)
        result = cursor.fetchall()
        duration = (time.time() - start_time) * 1000
        add_test_result("Q6: JOIN", len(result) > 0, f"Rows: {len(result)}", duration=duration)
    except Exception as e:
        add_test_result("Q6: JOIN", False, error=str(e))

    # Q7: IN Clause
    try:
        start_time = time.time()
        cursor.execute("""
            SELECT name, engine
            FROM system.tables
            WHERE database IN ('system', 'information_schema', 'mysql_interface')
            LIMIT 50
        """)
        result = cursor.fetchall()
        duration = (time.time() - start_time) * 1000
        add_test_result("Q7: IN Clause", len(result) > 0, f"Rows: {len(result)}", duration=duration)
    except Exception as e:
        add_test_result("Q7: IN Clause", False, error=str(e))

    cursor.close()
    connection.close()

    with open(os.environ['RESULT_FILE'], 'w') as f:
        json.dump(results, f, indent=2)

    total = len(results["tests"])
    passed = sum(1 for t in results["tests"] if t["passed"])
    avg_duration = sum(t["duration_ms"] for t in results["tests"]) / total if total > 0 else 0

    print(f"\n통계: {passed}/{total} 테스트 통과 ({passed*100//total}%)")
    print(f"평균 실행 시간: {avg_duration:.2f}ms")

    sys.exit(0 if passed >= total * 0.7 else 1)

except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
EOF

exit $?
