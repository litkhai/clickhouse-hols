#!/bin/bash
# CHC 접속 정보 확인 및 연결 테스트 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${BASE_DIR}/config/chc-config.sh"
CONFIG_TEMPLATE="${BASE_DIR}/config/chc-config.template"

echo "ClickHouse Cloud 접속 정보 확인 중..."
echo ""

# 설정 파일 확인
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "설정 파일이 없습니다: ${CONFIG_FILE}"
    echo ""
    echo "템플릿 파일을 복사하여 설정 파일을 생성합니다..."

    if [ -f "${CONFIG_TEMPLATE}" ]; then
        cp "${CONFIG_TEMPLATE}" "${CONFIG_FILE}"
        echo "✓ 설정 파일 생성: ${CONFIG_FILE}"
        echo ""
        echo "다음 단계:"
        echo "1. ${CONFIG_FILE} 파일을 편집하여 실제 접속 정보를 입력하세요."
        echo "2. 다시 이 스크립트를 실행하세요."
        echo ""
        echo "필요한 정보:"
        echo "  - CHC_HOST: ClickHouse Cloud 호스트명"
        echo "  - CHC_MYSQL_PORT: MySQL Interface 포트 (기본 9004)"
        echo "  - CHC_USER: 사용자명"
        echo "  - CHC_PASSWORD: 비밀번호"
        echo "  - CHC_DATABASE: 데이터베이스명"
        exit 1
    else
        echo "ERROR: 템플릿 파일도 없습니다: ${CONFIG_TEMPLATE}"
        exit 1
    fi
fi

# 설정 파일 로드
source "${CONFIG_FILE}"

# 필수 변수 확인
if [ -z "${CHC_HOST}" ] || [ "${CHC_HOST}" = "your-instance.clickhouse.cloud" ]; then
    echo "ERROR: CHC_HOST가 설정되지 않았습니다."
    echo "설정 파일을 확인하세요: ${CONFIG_FILE}"
    exit 1
fi

if [ -z "${CHC_PASSWORD}" ] || [ "${CHC_PASSWORD}" = "your-password" ]; then
    echo "ERROR: CHC_PASSWORD가 설정되지 않았습니다."
    echo "설정 파일을 확인하세요: ${CONFIG_FILE}"
    exit 1
fi

echo "설정 정보:"
echo "  호스트: ${CHC_HOST}"
echo "  포트: ${CHC_MYSQL_PORT}"
echo "  사용자: ${CHC_USER}"
echo "  데이터베이스: ${CHC_DATABASE}"
echo "  SSL 모드: ${CHC_SSL_MODE}"
echo ""

# Python으로 연결 테스트
echo "연결 테스트 중..."
python3 << EOF
import sys
import mysql.connector
from mysql.connector import Error

try:
    connection = mysql.connector.connect(
        host='${CHC_HOST}',
        port=${CHC_MYSQL_PORT},
        user='${CHC_USER}',
        password='${CHC_PASSWORD}',
        database='default',
        ssl_disabled=False
    )

    if connection.is_connected():
        cursor = connection.cursor()

        # 버전 확인
        cursor.execute("SELECT version()")
        version = cursor.fetchone()
        print(f"✓ 연결 성공!")
        print(f"  ClickHouse 버전: {version[0]}")

        # 현재 데이터베이스 확인
        cursor.execute("SELECT currentDatabase()")
        current_db = cursor.fetchone()
        print(f"  현재 데이터베이스: {current_db[0]}")

        # MySQL interface 설정 확인
        cursor.execute("SELECT name, value FROM system.settings WHERE name LIKE '%mysql%' LIMIT 5")
        settings = cursor.fetchall()
        if settings:
            print(f"  MySQL 관련 설정:")
            for setting in settings:
                print(f"    {setting[0]}: {setting[1]}")

        cursor.close()
        connection.close()
        sys.exit(0)
    else:
        print("ERROR: 연결 실패")
        sys.exit(1)

except Error as e:
    print(f"ERROR: 연결 중 오류 발생")
    print(f"  {e}")
    sys.exit(1)
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ 접속 정보 확인 완료"
    exit 0
else
    echo ""
    echo "ERROR: 접속 확인 실패"
    exit 1
fi
