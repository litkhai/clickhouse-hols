#!/bin/bash

# ============================================
# ClickHouse RBAC Lab - User Connection Helper
# 다른 사용자로 ClickHouse에 접속하는 스크립트
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ClickHouse 연결 정보 (환경변수 또는 기본값)
CH_HOST="${CH_HOST:-localhost}"
CH_PORT="${CH_PORT:-9000}"
CH_SECURE="${CH_SECURE:---secure}"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 사용자 정보 맵
declare -A USERS=(
    ["bi"]="demo_bi_user:SecurePass123!"
    ["analyst"]="demo_analyst:AnalystPass456!"
    ["engineer"]="demo_engineer:EngineerPass789!"
    ["partner"]="demo_partner:PartnerPass000!"
)

# 사용법 출력
usage() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}ClickHouse RBAC Lab - User Connection${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Usage: $0 <user_type> [query]"
    echo ""
    echo "Available user types:"
    echo "  bi        - BI User (읽기 전용, 제한적)"
    echo "  analyst   - Analyst (분석가, 중간 제한)"
    echo "  engineer  - Engineer (데이터 엔지니어, 관대함)"
    echo "  partner   - Partner (외부 파트너, 매우 제한적)"
    echo ""
    echo "Examples:"
    echo "  $0 analyst                              # analyst로 대화형 접속"
    echo "  $0 bi 'SELECT count() FROM rbac_demo.sales'   # 쿼리 직접 실행"
    echo ""
    exit 1
}

# 파라미터 체크
if [ $# -lt 1 ]; then
    usage
fi

USER_TYPE=$1
QUERY=$2

# 사용자 정보 조회
if [ -z "${USERS[$USER_TYPE]}" ]; then
    echo -e "${RED}Error: Unknown user type '$USER_TYPE'${NC}"
    usage
fi

IFS=':' read -r USERNAME PASSWORD <<< "${USERS[$USER_TYPE]}"

echo -e "${GREEN}Connecting as: ${USERNAME}${NC}"
echo -e "${YELLOW}Host: ${CH_HOST}:${CH_PORT}${NC}"
echo ""

# ClickHouse 클라이언트 실행
if [ -z "$QUERY" ]; then
    # 대화형 모드
    echo -e "${BLUE}=== Interactive Mode ===${NC}"
    echo "You are now connected as ${USERNAME}"
    echo "Type 'exit' or Ctrl+D to quit"
    echo ""

    clickhouse-client \
        --host="${CH_HOST}" \
        --port="${CH_PORT}" \
        --user="${USERNAME}" \
        --password="${PASSWORD}" \
        ${CH_SECURE} \
        --prompt="[${USERNAME}]> "
else
    # 쿼리 실행 모드
    echo -e "${BLUE}=== Query Mode ===${NC}"
    echo "Query: ${QUERY}"
    echo ""

    clickhouse-client \
        --host="${CH_HOST}" \
        --port="${CH_PORT}" \
        --user="${USERNAME}" \
        --password="${PASSWORD}" \
        ${CH_SECURE} \
        --query="${QUERY}"
fi
