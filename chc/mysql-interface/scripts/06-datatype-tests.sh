#!/bin/bash
# 데이터 타입 호환성 테스트 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${BASE_DIR}/config/chc-config.sh"
RESULT_FILE="${BASE_DIR}/test-results/datatype.json"

source "${CONFIG_FILE}"

echo "데이터 타입 호환성 테스트 실행 중..."
echo ""

export RESULT_FILE

python3 << 'EOF'
import json
import sys
import mysql.connector
from datetime import datetime
from decimal import Decimal

results = {"test_name": "Data Type Compatibility Tests", "timestamp": datetime.now().isoformat(), "tests": []}

def add_test_result(test_name, passed, message="", error=""):
    results["tests"].append({"name": test_name, "passed": passed, "message": message, "error": error})
    print(f"{'✓' if passed else '✗'} {test_name}: {message if message else error}")

try:
    import os
    connection = mysql.connector.connect(
        host=os.environ['CHC_HOST'],
        port=int(os.environ['CHC_MYSQL_PORT']),
        user=os.environ['CHC_USER'],
        password=os.environ['CHC_PASSWORD'],
        database='mysql_interface',
        ssl_disabled=False
    )
    cursor = connection.cursor()

    # 테이블 생성
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS test_datatypes (
            tiny_int TINYINT,
            small_int SMALLINT,
            int_col INT,
            big_int BIGINT,
            float_col FLOAT,
            double_col DOUBLE,
            decimal_col DECIMAL(10,2),
            char_col CHAR(10),
            varchar_col VARCHAR(255),
            text_col TEXT,
            date_col DATE,
            datetime_col DATETIME,
            timestamp_col TIMESTAMP
        ) ENGINE = MergeTree() ORDER BY int_col
    """)

    # Test: 데이터 삽입 및 검증
    try:
        cursor.execute("""
            INSERT INTO test_datatypes VALUES (
                127, 32767, 2147483647, 9223372036854775807,
                3.14, 3.14159265359, 123.45,
                'test', 'varchar test', 'text content',
                '2025-01-01', '2025-01-01 12:00:00', '2025-01-01 12:00:00'
            )
        """)
        add_test_result("Data Type INSERT", True, "All data types inserted")
    except Exception as e:
        add_test_result("Data Type INSERT", False, error=str(e))

    # Test: 각 데이터 타입 조회
    try:
        cursor.execute("SELECT * FROM test_datatypes LIMIT 1")
        row = cursor.fetchone()
        if row:
            add_test_result("Integer Types", row[0] == 127 and row[2] == 2147483647, f"TINYINT={row[0]}, INT={row[2]}")
            add_test_result("Float Types", abs(float(row[4]) - 3.14) < 0.01, f"FLOAT={row[4]}")
            add_test_result("Decimal Type", abs(float(row[6]) - 123.45) < 0.01, f"DECIMAL={row[6]}")
            add_test_result("String Types", row[7] is not None and row[8] is not None, f"CHAR='{row[7]}', VARCHAR='{row[8]}'")
            add_test_result("Date Types", row[10] is not None, f"DATE={row[10]}")
    except Exception as e:
        add_test_result("Data Type SELECT", False, error=str(e))

    cursor.execute("DROP TABLE IF EXISTS test_datatypes")
    cursor.close()
    connection.close()

    with open(os.environ['RESULT_FILE'], 'w') as f:
        json.dump(results, f, indent=2)

    total = len(results["tests"])
    passed = sum(1 for t in results["tests"] if t["passed"])
    print(f"\n통계: {passed}/{total} 테스트 통과")

    sys.exit(0 if passed >= total * 0.8 else 1)

except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
EOF

exit $?
