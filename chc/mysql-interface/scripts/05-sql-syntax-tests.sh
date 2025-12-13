#!/bin/bash
# SQL 구문 호환성 테스트 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${BASE_DIR}/config/chc-config.sh"
RESULT_FILE="${BASE_DIR}/test-results/sql-syntax.json"

# 설정 로드
source "${CONFIG_FILE}"

echo "SQL 구문 호환성 테스트 실행 중..."
echo ""

python3 << EOF
import json
import sys
import mysql.connector
from mysql.connector import Error
from datetime import datetime

results = {
    "test_name": "SQL Syntax Compatibility Tests",
    "timestamp": datetime.now().isoformat(),
    "tests": []
}

def add_test_result(test_name, passed, message="", error=""):
    results["tests"].append({
        "name": test_name,
        "passed": passed,
        "message": message,
        "error": error
    })
    status = "✓" if passed else "✗"
    print(f"{status} {test_name}: {message if message else error}")

try:
    connection = mysql.connector.connect(
        host='${CHC_HOST}',
        port=${CHC_MYSQL_PORT},
        user='${CHC_USER}',
        password='${CHC_PASSWORD}',
        database='mysql_interface',
        ssl_disabled=False
    )
    cursor = connection.cursor()

    # 테스트 테이블 생성
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS test_sql_syntax (
            id INT,
            name VARCHAR(100),
            email VARCHAR(100),
            age INT,
            salary DECIMAL(10,2),
            created_at TIMESTAMP
        ) ENGINE = MergeTree()
        ORDER BY id
    """)

    # Test 1: INSERT 단일
    try:
        cursor.execute("INSERT INTO test_sql_syntax VALUES (1, 'John', 'john@example.com', 30, 50000.00, now())")
        add_test_result("Single INSERT", True, "Single row inserted")
    except Exception as e:
        add_test_result("Single INSERT", False, error=str(e))

    # Test 2: INSERT 다중
    try:
        cursor.execute("""
            INSERT INTO test_sql_syntax VALUES
            (2, 'Jane', 'jane@example.com', 25, 60000.00, now()),
            (3, 'Bob', 'bob@example.com', 35, 55000.00, now())
        """)
        add_test_result("Multiple INSERT", True, "Multiple rows inserted")
    except Exception as e:
        add_test_result("Multiple INSERT", False, error=str(e))

    # Test 3: SELECT with WHERE
    try:
        cursor.execute("SELECT * FROM test_sql_syntax WHERE id = 1")
        result = cursor.fetchone()
        add_test_result("SELECT WHERE", result is not None, f"Found: {result[1] if result else None}")
    except Exception as e:
        add_test_result("SELECT WHERE", False, error=str(e))

    # Test 4: SELECT with ORDER BY
    try:
        cursor.execute("SELECT name FROM test_sql_syntax ORDER BY age DESC")
        results_list = cursor.fetchall()
        add_test_result("SELECT ORDER BY", len(results_list) > 0, f"Ordered {len(results_list)} rows")
    except Exception as e:
        add_test_result("SELECT ORDER BY", False, error=str(e))

    # Test 5: SELECT with LIMIT
    try:
        cursor.execute("SELECT * FROM test_sql_syntax LIMIT 2")
        results_list = cursor.fetchall()
        add_test_result("SELECT LIMIT", len(results_list) == 2, f"Limited to {len(results_list)} rows")
    except Exception as e:
        add_test_result("SELECT LIMIT", False, error=str(e))

    # Test 6: GROUP BY
    try:
        cursor.execute("""
            SELECT age, COUNT(*) as cnt
            FROM test_sql_syntax
            GROUP BY age
        """)
        results_list = cursor.fetchall()
        add_test_result("GROUP BY", len(results_list) > 0, f"Grouped into {len(results_list)} groups")
    except Exception as e:
        add_test_result("GROUP BY", False, error=str(e))

    # Test 7: HAVING
    try:
        cursor.execute("""
            SELECT age, AVG(salary) as avg_salary
            FROM test_sql_syntax
            GROUP BY age
            HAVING AVG(salary) > 50000
        """)
        results_list = cursor.fetchall()
        add_test_result("HAVING", True, f"Filtered to {len(results_list)} groups")
    except Exception as e:
        add_test_result("HAVING", False, error=str(e))

    # Test 8: DISTINCT
    try:
        cursor.execute("SELECT DISTINCT age FROM test_sql_syntax")
        results_list = cursor.fetchall()
        add_test_result("DISTINCT", len(results_list) > 0, f"Found {len(results_list)} distinct values")
    except Exception as e:
        add_test_result("DISTINCT", False, error=str(e))

    # Test 9: IN clause
    try:
        cursor.execute("SELECT * FROM test_sql_syntax WHERE id IN (1, 2)")
        results_list = cursor.fetchall()
        add_test_result("IN Clause", len(results_list) == 2, f"Found {len(results_list)} rows")
    except Exception as e:
        add_test_result("IN Clause", False, error=str(e))

    # Test 10: BETWEEN
    try:
        cursor.execute("SELECT * FROM test_sql_syntax WHERE age BETWEEN 25 AND 35")
        results_list = cursor.fetchall()
        add_test_result("BETWEEN", len(results_list) > 0, f"Found {len(results_list)} rows")
    except Exception as e:
        add_test_result("BETWEEN", False, error=str(e))

    # Test 11: LIKE
    try:
        cursor.execute("SELECT * FROM test_sql_syntax WHERE name LIKE 'J%'")
        results_list = cursor.fetchall()
        add_test_result("LIKE Pattern", len(results_list) > 0, f"Found {len(results_list)} matches")
    except Exception as e:
        add_test_result("LIKE Pattern", False, error=str(e))

    # Test 12: CASE WHEN
    try:
        cursor.execute("""
            SELECT name,
                   CASE
                       WHEN age < 30 THEN 'Young'
                       WHEN age >= 30 THEN 'Senior'
                   END as age_group
            FROM test_sql_syntax
        """)
        results_list = cursor.fetchall()
        add_test_result("CASE WHEN", len(results_list) > 0, f"Processed {len(results_list)} rows")
    except Exception as e:
        add_test_result("CASE WHEN", False, error=str(e))

    # 정리
    cursor.execute("DROP TABLE IF EXISTS test_sql_syntax")

    cursor.close()
    connection.close()

    # 결과 저장
    with open('${RESULT_FILE}', 'w') as f:
        json.dump(results, f, indent=2)

    # 통계
    total = len(results["tests"])
    passed = sum(1 for t in results["tests"] if t["passed"])
    print(f"\n통계: {passed}/{total} 테스트 통과 ({passed*100//total}%)")

    sys.exit(0 if passed >= total * 0.8 else 1)

except Error as e:
    print(f"ERROR: {e}")
    with open('${RESULT_FILE}', 'w') as f:
        json.dump(results, f, indent=2)
    sys.exit(1)
EOF

exit $?
