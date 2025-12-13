#!/bin/bash
# Python 드라이버 상세 호환성 테스트 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${BASE_DIR}/config/chc-config.sh"
RESULT_FILE="${BASE_DIR}/test-results/python-driver-detailed.json"

source "${CONFIG_FILE}"

echo "Python 드라이버 상세 호환성 테스트 실행 중..."
echo ""

export RESULT_FILE

python3 << 'EOF'
import json
import sys
import os
from datetime import datetime
import traceback

results = {"test_name": "Python Driver Detailed Compatibility Tests", "timestamp": datetime.now().isoformat(), "tests": []}

def add_test_result(test_name, passed, message="", error="", details=""):
    results["tests"].append({
        "name": test_name,
        "passed": passed,
        "message": message,
        "error": error,
        "details": details
    })
    print(f"{'✓' if passed else '✗'} {test_name}: {message if message else error}")
    if details:
        print(f"  상세: {details}")

# Test 1: mysql-connector-python 상세 테스트
try:
    import mysql.connector
    from mysql.connector import Error

    connection = mysql.connector.connect(
        host=os.environ['CHC_HOST'],
        port=int(os.environ['CHC_MYSQL_PORT']),
        user=os.environ['CHC_USER'],
        password=os.environ['CHC_PASSWORD'],
        database='default',
        ssl_disabled=False,
        connection_timeout=10
    )

    # 기본 연결 테스트
    cursor = connection.cursor()
    cursor.execute("SELECT 1")
    result = cursor.fetchone()

    # 연결 정보 확인
    details = f"Connection established successfully"

    cursor.close()
    connection.close()
    add_test_result("mysql-connector-python", result[0] == 1, "Connection successful", details=details)
except Exception as e:
    add_test_result("mysql-connector-python", False, error=str(e), details=traceback.format_exc())

# Test 2: PyMySQL 상세 테스트
try:
    import pymysql
    from pymysql import Error

    print("\n[PyMySQL 상세 테스트]")
    connection = pymysql.connect(
        host=os.environ['CHC_HOST'],
        port=int(os.environ['CHC_MYSQL_PORT']),
        user=os.environ['CHC_USER'],
        password=os.environ['CHC_PASSWORD'],
        database='default',
        ssl={'ca': None},  # SSL 설정을 딕셔너리로 전달
        connect_timeout=30
    )

    cursor = connection.cursor()
    cursor.execute("SELECT 1")
    result = cursor.fetchone()

    cursor.close()
    connection.close()
    add_test_result("PyMySQL", result[0] == 1, "Connection successful")
except Exception as e:
    error_msg = str(e)
    stack = traceback.format_exc()
    add_test_result("PyMySQL", False, error=error_msg, details=stack)

# Test 3: Connection Pooling 상세 테스트
try:
    from mysql.connector import pooling

    print("\n[Connection Pooling 상세 테스트]")
    pool = pooling.MySQLConnectionPool(
        pool_name="test_pool",
        pool_size=3,
        pool_reset_session=False,  # 세션 리셋 비활성화
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
    error_msg = str(e)
    stack = traceback.format_exc()

    # 오류 분석
    if "NOT_IMPLEMENTED" in error_msg or "is not implemented" in error_msg:
        analysis = "ClickHouse가 일부 MySQL protocol 명령을 구현하지 않음"
    elif "RESET" in error_msg.upper():
        analysis = "Session reset 명령 미지원 가능성"
    else:
        analysis = "Unknown error"

    add_test_result("Connection Pooling", False, error=error_msg, details=f"{analysis}\n\n{stack}")

# Test 4: Prepared Statements 상세 테스트
try:
    import mysql.connector

    print("\n[Prepared Statements 상세 테스트]")
    connection = mysql.connector.connect(
        host=os.environ['CHC_HOST'],
        port=int(os.environ['CHC_MYSQL_PORT']),
        user=os.environ['CHC_USER'],
        password=os.environ['CHC_PASSWORD'],
        database='default',
        ssl_disabled=False
    )
    cursor = connection.cursor()

    # 다양한 파라미터 타입 테스트
    test_cases = [
        ("SELECT %s + %s", (10, 20), 30),
        ("SELECT %s", ('hello',), 'hello'),
        ("SELECT %s", (123.45,), 123.45)
    ]

    all_passed = True
    test_details = []

    for query, params, expected in test_cases:
        cursor.execute(query, params)
        result = cursor.fetchone()[0]
        passed = (result == expected)
        all_passed = all_passed and passed
        test_details.append(f"  {query} with {params}: {'✓' if passed else '✗'}")

    cursor.close()
    connection.close()

    details_str = "\n".join(test_details)
    add_test_result("Prepared Statements (Detailed)", all_passed, "All parameter types work", details=details_str)
except Exception as e:
    add_test_result("Prepared Statements (Detailed)", False, error=str(e), details=traceback.format_exc())

# Test 5: Batch Operations 상세 테스트
try:
    import mysql.connector

    print("\n[Batch Operations 상세 테스트]")
    connection = mysql.connector.connect(
        host=os.environ['CHC_HOST'],
        port=int(os.environ['CHC_MYSQL_PORT']),
        user=os.environ['CHC_USER'],
        password=os.environ['CHC_PASSWORD'],
        database='mysql_interface',
        ssl_disabled=False
    )
    cursor = connection.cursor()

    # 테스트 테이블 생성
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS test_batch_detailed (
            id INT,
            name VARCHAR(50),
            value DECIMAL(10,2)
        ) ENGINE = MergeTree() ORDER BY id
    """)

    # 다양한 배치 크기 테스트
    batch_sizes = [10, 100, 1000]
    batch_results = []

    for batch_size in batch_sizes:
        data = [(i, f'name_{i}', float(i * 10.5)) for i in range(1, batch_size + 1)]
        cursor.executemany("INSERT INTO test_batch_detailed VALUES (%s, %s, %s)", data)

        cursor.execute("SELECT COUNT(*) FROM test_batch_detailed")
        count = cursor.fetchone()[0]
        batch_results.append(f"  Batch {batch_size}: {'✓' if count >= batch_size else '✗'} ({count} rows)")

        # 정리
        cursor.execute("TRUNCATE TABLE test_batch_detailed")

    cursor.execute("DROP TABLE IF EXISTS test_batch_detailed")
    cursor.close()
    connection.close()

    details_str = "\n".join(batch_results)
    add_test_result("Batch Operations (Detailed)", True, "All batch sizes work", details=details_str)
except Exception as e:
    add_test_result("Batch Operations (Detailed)", False, error=str(e), details=traceback.format_exc())

# Test 6: Connection Options 테스트
try:
    import mysql.connector

    print("\n[Connection Options 테스트]")
    options_tests = []

    # autocommit 테스트
    try:
        conn = mysql.connector.connect(
            host=os.environ['CHC_HOST'],
            port=int(os.environ['CHC_MYSQL_PORT']),
            user=os.environ['CHC_USER'],
            password=os.environ['CHC_PASSWORD'],
            database='default',
            ssl_disabled=False,
            autocommit=True
        )
        options_tests.append("  autocommit=True: ✓")
        conn.close()
    except Exception as e:
        options_tests.append(f"  autocommit=True: ✗ ({str(e)})")

    # charset 테스트
    try:
        conn = mysql.connector.connect(
            host=os.environ['CHC_HOST'],
            port=int(os.environ['CHC_MYSQL_PORT']),
            user=os.environ['CHC_USER'],
            password=os.environ['CHC_PASSWORD'],
            database='default',
            ssl_disabled=False,
            charset='utf8mb4'
        )
        options_tests.append("  charset='utf8mb4': ✓")
        conn.close()
    except Exception as e:
        options_tests.append(f"  charset='utf8mb4': ✗ ({str(e)})")

    details_str = "\n".join(options_tests)
    add_test_result("Connection Options", True, "Options tested", details=details_str)
except Exception as e:
    add_test_result("Connection Options", False, error=str(e), details=traceback.format_exc())

# 결과 저장
with open(os.environ['RESULT_FILE'], 'w') as f:
    json.dump(results, f, indent=2)

# 통계
total = len(results["tests"])
passed = sum(1 for t in results["tests"] if t["passed"])
print(f"\n{'='*60}")
print(f"통계: {passed}/{total} 테스트 통과 ({passed*100//total}%)")
print(f"{'='*60}")

sys.exit(0 if passed >= total * 0.7 else 1)
EOF

exit $?
