#!/bin/bash
# 함수 호환성 테스트 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${BASE_DIR}/config/chc-config.sh"
RESULT_FILE="${BASE_DIR}/test-results/function.json"

source "${CONFIG_FILE}"

echo "함수 호환성 테스트 실행 중..."
echo ""

export RESULT_FILE

python3 << 'EOF'
import json
import sys
import mysql.connector
from datetime import datetime
import os

results = {"test_name": "Function Compatibility Tests", "timestamp": datetime.now().isoformat(), "tests": []}

def add_test_result(test_name, passed, message="", error=""):
    results["tests"].append({"name": test_name, "passed": passed, "message": message, "error": error})
    print(f"{'✓' if passed else '✗'} {test_name}: {message if message else error}")

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

    # 테스트용 테이블 생성
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS test_functions (
            id INT,
            name VARCHAR(100),
            value DECIMAL(10,2),
            created_at DATETIME
        ) ENGINE = MergeTree() ORDER BY id
    """)

    # 테스트 데이터 삽입
    cursor.execute("""
        INSERT INTO test_functions VALUES
        (1, 'Alice', 100.50, '2025-01-01 10:00:00'),
        (2, 'Bob', 200.75, '2025-01-02 11:00:00'),
        (3, 'Charlie', 150.25, '2025-01-03 12:00:00'),
        (4, 'David', 300.00, '2025-01-04 13:00:00'),
        (5, 'Eve', 250.50, '2025-01-05 14:00:00')
    """)

    # 문자열 함수 테스트
    try:
        cursor.execute("SELECT CONCAT('Hello', ' ', 'World') as result")
        result = cursor.fetchone()[0]
        add_test_result("CONCAT", result == "Hello World", f"Result: {result}")
    except Exception as e:
        add_test_result("CONCAT", False, error=str(e))

    try:
        cursor.execute("SELECT UPPER('test') as result")
        result = cursor.fetchone()[0]
        add_test_result("UPPER", result == "TEST", f"Result: {result}")
    except Exception as e:
        add_test_result("UPPER", False, error=str(e))

    try:
        cursor.execute("SELECT LOWER('TEST') as result")
        result = cursor.fetchone()[0]
        add_test_result("LOWER", result == "test", f"Result: {result}")
    except Exception as e:
        add_test_result("LOWER", False, error=str(e))

    try:
        cursor.execute("SELECT LENGTH('hello') as result")
        result = cursor.fetchone()[0]
        add_test_result("LENGTH", result == 5, f"Result: {result}")
    except Exception as e:
        add_test_result("LENGTH", False, error=str(e))

    try:
        cursor.execute("SELECT SUBSTRING('Hello World', 1, 5) as result")
        result = cursor.fetchone()[0]
        add_test_result("SUBSTRING", result == "Hello", f"Result: {result}")
    except Exception as e:
        add_test_result("SUBSTRING", False, error=str(e))

    try:
        cursor.execute("SELECT REPLACE('hello@example.com', '@example.com', '@test.com') as result")
        result = cursor.fetchone()[0]
        add_test_result("REPLACE", result == "hello@test.com", f"Result: {result}")
    except Exception as e:
        add_test_result("REPLACE", False, error=str(e))

    # 날짜 함수 테스트
    try:
        cursor.execute("SELECT NOW() as result")
        result = cursor.fetchone()[0]
        add_test_result("NOW", result is not None, f"Result: {result}")
    except Exception as e:
        add_test_result("NOW", False, error=str(e))

    try:
        cursor.execute("SELECT CURDATE() as result")
        result = cursor.fetchone()[0]
        add_test_result("CURDATE", result is not None, f"Result: {result}")
    except Exception as e:
        add_test_result("CURDATE", False, error=str(e))

    try:
        cursor.execute("SELECT YEAR(NOW()) as result")
        result = cursor.fetchone()[0]
        add_test_result("YEAR", result >= 2025, f"Result: {result}")
    except Exception as e:
        add_test_result("YEAR", False, error=str(e))

    try:
        cursor.execute("SELECT MONTH(NOW()) as result")
        result = cursor.fetchone()[0]
        add_test_result("MONTH", 1 <= result <= 12, f"Result: {result}")
    except Exception as e:
        add_test_result("MONTH", False, error=str(e))

    try:
        cursor.execute("SELECT DAY(created_at) as result FROM test_functions WHERE id = 1")
        result = cursor.fetchone()[0]
        add_test_result("DAY", result == 1, f"Result: {result}")
    except Exception as e:
        add_test_result("DAY", False, error=str(e))

    try:
        cursor.execute("SELECT DATE_FORMAT(created_at, '%Y-%m-%d') as result FROM test_functions WHERE id = 1")
        result = cursor.fetchone()[0]
        add_test_result("DATE_FORMAT", result == "2025-01-01", f"Result: {result}")
    except Exception as e:
        add_test_result("DATE_FORMAT", False, error=str(e))

    # 집계 함수 테스트 (실제 사용자 테이블 사용)
    try:
        cursor.execute("SELECT COUNT(*) as result FROM test_functions")
        result = cursor.fetchone()[0]
        add_test_result("COUNT", result == 5, f"Result: {result}")
    except Exception as e:
        add_test_result("COUNT", False, error=str(e))

    try:
        cursor.execute("SELECT SUM(id) as result FROM test_functions")
        result = cursor.fetchone()[0]
        add_test_result("SUM", result == 15, f"Result: {result}")  # 1+2+3+4+5 = 15
    except Exception as e:
        add_test_result("SUM", False, error=str(e))

    try:
        cursor.execute("SELECT AVG(id) as result FROM test_functions")
        result = cursor.fetchone()[0]
        add_test_result("AVG", abs(float(result) - 3.0) < 0.1, f"Result: {result}")  # (1+2+3+4+5)/5 = 3
    except Exception as e:
        add_test_result("AVG", False, error=str(e))

    try:
        cursor.execute("SELECT MIN(value) as result FROM test_functions")
        result = cursor.fetchone()[0]
        add_test_result("MIN", abs(float(result) - 100.50) < 0.01, f"Result: {result}")
    except Exception as e:
        add_test_result("MIN", False, error=str(e))

    try:
        cursor.execute("SELECT MAX(value) as result FROM test_functions")
        result = cursor.fetchone()[0]
        add_test_result("MAX", abs(float(result) - 300.00) < 0.01, f"Result: {result}")
    except Exception as e:
        add_test_result("MAX", False, error=str(e))

    try:
        cursor.execute("SELECT ROUND(AVG(value), 2) as result FROM test_functions")
        result = cursor.fetchone()[0]
        add_test_result("ROUND", abs(float(result) - 200.40) < 0.1, f"Result: {result}")  # (100.50+200.75+150.25+300+250.50)/5 = 200.40
    except Exception as e:
        add_test_result("ROUND", False, error=str(e))

    # 정리
    cursor.execute("DROP TABLE IF EXISTS test_functions")

    cursor.close()
    connection.close()

    with open(os.environ['RESULT_FILE'], 'w') as f:
        json.dump(results, f, indent=2)

    total = len(results["tests"])
    passed = sum(1 for t in results["tests"] if t["passed"])
    print(f"\n통계: {passed}/{total} 테스트 통과 ({passed*100//total}%)")

    sys.exit(0 if passed >= total * 0.8 else 1)

except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
EOF

exit $?
