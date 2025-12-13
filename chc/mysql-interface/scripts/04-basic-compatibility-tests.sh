#!/bin/bash
# 기본 호환성 테스트 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${BASE_DIR}/config/chc-config.sh"
RESULT_FILE="${BASE_DIR}/test-results/basic-compatibility.json"

# 설정 로드
source "${CONFIG_FILE}"

echo "기본 호환성 테스트 실행 중..."
echo ""

# Python 테스트 실행
python3 << EOF
import json
import sys
import mysql.connector
from mysql.connector import Error
from datetime import datetime

results = {
    "test_name": "Basic Compatibility Tests",
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
    # 연결 생성
    connection = mysql.connector.connect(
        host='${CHC_HOST}',
        port=${CHC_MYSQL_PORT},
        user='${CHC_USER}',
        password='${CHC_PASSWORD}',
        database='default',
        ssl_disabled=False
    )

    cursor = connection.cursor()

    # Test 1: 기본 SELECT
    try:
        cursor.execute("SELECT 1")
        result = cursor.fetchone()
        add_test_result("Basic SELECT", result[0] == 1, "SELECT 1 returned 1")
    except Exception as e:
        add_test_result("Basic SELECT", False, error=str(e))

    # Test 2: 버전 조회
    try:
        cursor.execute("SELECT version()")
        version = cursor.fetchone()
        add_test_result("Version Query", True, f"Version: {version[0]}")
    except Exception as e:
        add_test_result("Version Query", False, error=str(e))

    # Test 3: 데이터베이스 생성
    try:
        cursor.execute("CREATE DATABASE IF NOT EXISTS mysql_interface")
        add_test_result("Create Database", True, "Database created successfully")
    except Exception as e:
        add_test_result("Create Database", False, error=str(e))

    # Test 4: 데이터베이스 사용
    try:
        cursor.execute("USE mysql_interface")
        add_test_result("Use Database", True, "Database switched successfully")
    except Exception as e:
        add_test_result("Use Database", False, error=str(e))

    # Test 5: 테이블 생성
    try:
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS test_basic (
                id UInt32,
                name String,
                value Float64,
                created DateTime
            ) ENGINE = MergeTree()
            ORDER BY id
        """)
        add_test_result("Create Table", True, "Table created successfully")
    except Exception as e:
        add_test_result("Create Table", False, error=str(e))

    # Test 6: 데이터 삽입
    try:
        cursor.execute("""
            INSERT INTO test_basic VALUES
            (1, 'test1', 100.5, now()),
            (2, 'test2', 200.75, now())
        """)
        add_test_result("Insert Data", True, "Data inserted successfully")
    except Exception as e:
        add_test_result("Insert Data", False, error=str(e))

    # Test 7: 데이터 조회
    try:
        cursor.execute("SELECT * FROM test_basic WHERE id = 1")
        result = cursor.fetchone()
        if result and result[0] == 1:
            add_test_result("Select Data", True, f"Retrieved: {result}")
        else:
            add_test_result("Select Data", False, "Unexpected result")
    except Exception as e:
        add_test_result("Select Data", False, error=str(e))

    # Test 8: COUNT 집계
    try:
        cursor.execute("SELECT COUNT(*) FROM test_basic")
        count = cursor.fetchone()[0]
        add_test_result("Aggregate COUNT", count >= 2, f"Count: {count}")
    except Exception as e:
        add_test_result("Aggregate COUNT", False, error=str(e))

    # Test 9: Prepared Statement
    try:
        query = "SELECT * FROM test_basic WHERE id = %s"
        cursor.execute(query, (2,))
        result = cursor.fetchone()
        add_test_result("Prepared Statement", result[0] == 2, f"Retrieved: {result}")
    except Exception as e:
        add_test_result("Prepared Statement", False, error=str(e))

    # Test 10: 정리
    try:
        cursor.execute("DROP TABLE IF EXISTS test_basic")
        add_test_result("Cleanup", True, "Table dropped successfully")
    except Exception as e:
        add_test_result("Cleanup", False, error=str(e))

    cursor.close()
    connection.close()

    # 결과 저장
    with open('${RESULT_FILE}', 'w') as f:
        json.dump(results, f, indent=2)

    # 통계
    total = len(results["tests"])
    passed = sum(1 for t in results["tests"] if t["passed"])
    print(f"\n통계: {passed}/{total} 테스트 통과")

    sys.exit(0 if passed == total else 1)

except Error as e:
    print(f"ERROR: {e}")
    add_test_result("Connection", False, error=str(e))
    with open('${RESULT_FILE}', 'w') as f:
        json.dump(results, f, indent=2)
    sys.exit(1)
EOF

exit $?
