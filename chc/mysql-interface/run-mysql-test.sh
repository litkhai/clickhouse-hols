#!/bin/bash
# ClickHouse Cloud MySQL Interface 호환성 자동 테스트 스크립트
# 작성일: 2025-12-13

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_RESULTS_DIR="${SCRIPT_DIR}/test-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="${TEST_RESULTS_DIR}/report_${TIMESTAMP}.md"

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 테스트 결과 디렉토리 생성
mkdir -p "${TEST_RESULTS_DIR}"

# 헤더 출력
echo ""
echo "=========================================================================="
echo "  ClickHouse Cloud MySQL Interface 호환성 자동 테스트"
echo "=========================================================================="
echo ""
echo "실행 시간: $(date)"
echo "결과 저장: ${TEST_RESULTS_DIR}"
echo ""

# 1단계: 환경 설정
log_info "1단계: 환경 설정 시작..."
"${SCRIPT_DIR}/scripts/01-setup-environment.sh"
if [ $? -eq 0 ]; then
    log_success "환경 설정 완료"
else
    log_error "환경 설정 실패"
    exit 1
fi
echo ""

# 2단계: MySQL 클라이언트 설치 확인
log_info "2단계: MySQL 클라이언트 설치 확인..."
"${SCRIPT_DIR}/scripts/02-install-mysql-clients.sh"
if [ $? -eq 0 ]; then
    log_success "MySQL 클라이언트 확인 완료"
else
    log_error "MySQL 클라이언트 설치 실패"
    exit 1
fi
echo ""

# 3단계: CHC 접속 정보 확인
log_info "3단계: ClickHouse Cloud 접속 정보 확인..."
"${SCRIPT_DIR}/scripts/03-verify-connection.sh"
if [ $? -eq 0 ]; then
    log_success "접속 정보 확인 완료"
else
    log_error "접속 정보 확인 실패"
    exit 1
fi
echo ""

# 4단계: 기본 호환성 테스트
log_info "4단계: 기본 호환성 테스트 실행..."
"${SCRIPT_DIR}/scripts/04-basic-compatibility-tests.sh"
BASIC_TEST_RESULT=$?
echo ""

# 5단계: SQL 구문 호환성 테스트
log_info "5단계: SQL 구문 호환성 테스트 실행..."
"${SCRIPT_DIR}/scripts/05-sql-syntax-tests.sh"
SQL_TEST_RESULT=$?
echo ""

# 6단계: 데이터 타입 호환성 테스트
log_info "6단계: 데이터 타입 호환성 테스트 실행..."
"${SCRIPT_DIR}/scripts/06-datatype-tests.sh"
DATATYPE_TEST_RESULT=$?
echo ""

# 7단계: 함수 호환성 테스트
log_info "7단계: 함수 호환성 테스트 실행..."
"${SCRIPT_DIR}/scripts/07-function-tests.sh"
FUNCTION_TEST_RESULT=$?
echo ""

# 8단계: TPC-DS 벤치마크 테스트
log_info "8단계: TPC-DS 벤치마크 테스트 실행..."
"${SCRIPT_DIR}/scripts/08-tpcds-tests.sh"
TPCDS_TEST_RESULT=$?
echo ""

# 9단계: Python 드라이버 테스트
log_info "9단계: Python 드라이버 테스트 실행..."
"${SCRIPT_DIR}/scripts/09-python-driver-tests.sh"
PYTHON_TEST_RESULT=$?
echo ""

# 10단계: 성능 테스트
log_info "10단계: 성능 테스트 실행..."
"${SCRIPT_DIR}/scripts/10-performance-tests.sh"
PERFORMANCE_TEST_RESULT=$?
echo ""

# 11단계: 리포트 생성
log_info "11단계: 테스트 리포트 생성..."
"${SCRIPT_DIR}/scripts/11-generate-report.sh" "${TIMESTAMP}"
if [ $? -eq 0 ]; then
    log_success "리포트 생성 완료: ${REPORT_FILE}"
else
    log_error "리포트 생성 실패"
fi
echo ""

# 전체 결과 요약
echo "=========================================================================="
echo "  테스트 결과 요약"
echo "=========================================================================="
echo ""

TOTAL_TESTS=7
PASSED_TESTS=0

[ $BASIC_TEST_RESULT -eq 0 ] && PASSED_TESTS=$((PASSED_TESTS + 1))
[ $SQL_TEST_RESULT -eq 0 ] && PASSED_TESTS=$((PASSED_TESTS + 1))
[ $DATATYPE_TEST_RESULT -eq 0 ] && PASSED_TESTS=$((PASSED_TESTS + 1))
[ $FUNCTION_TEST_RESULT -eq 0 ] && PASSED_TESTS=$((PASSED_TESTS + 1))
[ $TPCDS_TEST_RESULT -eq 0 ] && PASSED_TESTS=$((PASSED_TESTS + 1))
[ $PYTHON_TEST_RESULT -eq 0 ] && PASSED_TESTS=$((PASSED_TESTS + 1))
[ $PERFORMANCE_TEST_RESULT -eq 0 ] && PASSED_TESTS=$((PASSED_TESTS + 1))

echo "전체 테스트: ${TOTAL_TESTS}"
echo "성공: ${PASSED_TESTS}"
echo "실패: $((TOTAL_TESTS - PASSED_TESTS))"
echo ""

PASS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
echo "성공률: ${PASS_RATE}%"
echo ""

if [ $PASS_RATE -ge 80 ]; then
    log_success "전체 테스트 성공!"
    echo ""
    echo "상세 리포트: ${REPORT_FILE}"
    exit 0
else
    log_warning "일부 테스트 실패"
    echo ""
    echo "상세 리포트: ${REPORT_FILE}"
    exit 1
fi
