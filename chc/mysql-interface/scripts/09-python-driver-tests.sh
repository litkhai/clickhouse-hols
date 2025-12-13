#!/bin/bash
# Python 드라이버 호환성 테스트 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${BASE_DIR}/config/chc-config.sh"
RESULT_FILE="${BASE_DIR}/test-results/python-driver.json"

source "${CONFIG_FILE}"

echo "Python 드라이버 호환성 테스트 실행 중..."
echo ""

export RESULT_FILE

python3 << 'EOF'
import json
import sys
import os
from datetime import datetime

results = {"test_name": "Python Driver Compatibility Tests", "timestamp": datetime.now().isoformat(), "tests": []}

def add_test_result(test_name, passed, message="", error=""):
    results["tests"].append({"name": test_name, "passed": passed, "message": message, "error": error})
    print(f"{'✓' if passed else '✗'} {test_name}: {message if message else error}")

# Test 1: mysql-connector-python
try:
    import mysql.connector
    connection = mysql.connector.connect(
        host=os.environ['CHC_HOST'],
        port=int(os.environ['CHC_MYSQL_PORT']),
        user=os.environ['CHC_USER'],
        password=os.environ['CHC_PASSWORD'],
        database='default',
        ssl_disabled=False
    )
    cursor = connection.cursor()
    cursor.execute("SELECT 1")
    result = cursor.fetchone()
    cursor.close()
    connection.close()
    add_test_result("mysql-connector-python", result[0] == 1, "Connection successful")
except Exception as e:
    add_test_result("mysql-connector-python", False, error=str(e))

# Test 2: PyMySQL
try:
    import pymysql
    connection = pymysql.connect(
        host=os.environ['CHC_HOST'],
        port=int(os.environ['CHC_MYSQL_PORT']),
        user=os.environ['CHC_USER'],
        password=os.environ['CHC_PASSWORD'],
        database='default',
        ssl=True
    )
    cursor = connection.cursor()
    cursor.execute("SELECT 1")
    result = cursor.fetchone()
    cursor.close()
    connection.close()
    add_test_result("PyMySQL", result[0] == 1, "Connection successful")
except Exception as e:
    add_test_result("PyMySQL", False, error=str(e))

# Test 3: Connection Pooling
try:
    from mysql.connector import pooling
    pool = pooling.MySQLConnectionPool(
        pool_name="test_pool",
        pool_size=3,
        host=os.environ['CHC_HOST'],
        port=int(os.environ['CHC_MYSQL_PORT']),
        user=os.environ['CHC_USER'],
        password=os.environ['CHC_PASSWORD'],
        database='default'
    )
    conn = pool.get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT 1")
    result = cursor.fetchone()
    cursor.close()
    conn.close()
    add_test_result("Connection Pooling", result[0] == 1, "Pool connection successful")
except Exception as e:
    add_test_result("Connection Pooling", False, error=str(e))

# Test 4: Prepared Statements
try:
    import mysql.connector
    connection = mysql.connector.connect(
        host=os.environ['CHC_HOST'],
        port=int(os.environ['CHC_MYSQL_PORT']),
        user=os.environ['CHC_USER'],
        password=os.environ['CHC_PASSWORD'],
        database='default',
        ssl_disabled=False
    )
    cursor = connection.cursor()
    query = "SELECT %s + %s as result"
    cursor.execute(query, (10, 20))
    result = cursor.fetchone()
    cursor.close()
    connection.close()
    add_test_result("Prepared Statements", result[0] == 30, f"Result: {result[0]}")
except Exception as e:
    add_test_result("Prepared Statements", False, error=str(e))

# Test 5: Batch Operations
try:
    import mysql.connector
    connection = mysql.connector.connect(
        host=os.environ['CHC_HOST'],
        port=int(os.environ['CHC_MYSQL_PORT']),
        user=os.environ['CHC_USER'],
        password=os.environ['CHC_PASSWORD'],
        database='mysql_interface',
        ssl_disabled=False
    )
    cursor = connection.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS test_batch (
            id INT,
            value INT
        ) ENGINE = MergeTree() ORDER BY id
    """)

    data = [(i, i*10) for i in range(1, 6)]
    cursor.executemany("INSERT INTO test_batch VALUES (%s, %s)", data)

    cursor.execute("SELECT COUNT(*) FROM test_batch")
    count = cursor.fetchone()[0]

    cursor.execute("DROP TABLE IF EXISTS test_batch")
    cursor.close()
    connection.close()

    add_test_result("Batch Operations", count >= 5, f"Inserted {count} rows")
except Exception as e:
    add_test_result("Batch Operations", False, error=str(e))

with open(os.environ['RESULT_FILE'], 'w') as f:
    json.dump(results, f, indent=2)

total = len(results["tests"])
passed = sum(1 for t in results["tests"] if t["passed"])
print(f"\n통계: {passed}/{total} 테스트 통과 ({passed*100//total}%)")

sys.exit(0 if passed >= total * 0.8 else 1)
EOF

exit $?
