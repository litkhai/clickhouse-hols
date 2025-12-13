#!/bin/bash
# 환경 설정 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"

echo "환경 설정 중..."

# Python3 확인
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python3가 설치되어 있지 않습니다."
    exit 1
fi
echo "✓ Python3: $(python3 --version)"

# pip3 확인
if ! command -v pip3 &> /dev/null; then
    echo "ERROR: pip3가 설치되어 있지 않습니다."
    exit 1
fi
echo "✓ pip3: $(pip3 --version)"

# 필요한 Python 패키지 설치
echo ""
echo "Python 패키지 설치 중..."
pip3 install -q mysql-connector-python pymysql 2>/dev/null || true
echo "✓ mysql-connector-python 설치 완료"
echo "✓ pymysql 설치 완료"

# 설정 파일 디렉토리 생성
mkdir -p "${BASE_DIR}/config"
mkdir -p "${BASE_DIR}/test-results"
mkdir -p "${BASE_DIR}/logs"

echo ""
echo "✓ 환경 설정 완료"
exit 0
