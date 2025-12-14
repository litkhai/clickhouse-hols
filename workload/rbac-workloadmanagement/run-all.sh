#!/bin/bash

# ============================================
# ClickHouse RBAC Lab - Full Setup Script
# 모든 단계를 순서대로 실행하는 스크립트
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ClickHouse 연결 정보
CH_HOST="${CH_HOST:-localhost}"
CH_PORT="${CH_PORT:-9000}"
CH_USER="${CH_USER:-default}"
CH_PASSWORD="${CH_PASSWORD:-}"
CH_SECURE="${CH_SECURE}"

# 배너 출력
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ClickHouse RBAC & Workload Management${NC}"
echo -e "${BLUE}Full Setup Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Host: ${CH_HOST}:${CH_PORT}"
echo -e "User: ${CH_USER}"
echo ""

# 확인 프롬프트
read -p "This will create all RBAC demo resources. Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# 실행 함수
run_step() {
    local step_num=$1
    local step_name=$2
    local sql_file=$3

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}Step ${step_num}: ${step_name}${NC}"
    echo -e "${CYAN}========================================${NC}"

    if [ ! -f "${SCRIPT_DIR}/${sql_file}" ]; then
        echo -e "${RED}Error: File not found - ${sql_file}${NC}"
        return 1
    fi

    if [ -z "$CH_PASSWORD" ]; then
        clickhouse-client \
            --host="${CH_HOST}" \
            --port="${CH_PORT}" \
            --user="${CH_USER}" \
            ${CH_SECURE} \
            --queries-file="${SCRIPT_DIR}/${sql_file}"
    else
        clickhouse-client \
            --host="${CH_HOST}" \
            --port="${CH_PORT}" \
            --user="${CH_USER}" \
            --password="${CH_PASSWORD}" \
            ${CH_SECURE} \
            --queries-file="${SCRIPT_DIR}/${sql_file}"
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Step ${step_num} completed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ Step ${step_num} failed${NC}"
        return 1
    fi
}

# 단계별 실행
run_step 1 "Setup (Database & Tables)" "01-setup.sql" || exit 1
sleep 1

run_step 2 "Create Roles" "02-create-roles.sql" || exit 1
sleep 1

run_step 3 "Create Users" "03-create-users.sql" || exit 1
sleep 1

run_step 4 "Row Policies" "04-row-policies.sql" || exit 1
sleep 1

run_step 5 "Column Security" "05-column-security.sql" || exit 1
sleep 1

run_step 6 "Settings Profiles" "06-settings-profiles.sql" || exit 1
sleep 1

run_step 7 "Quotas" "07-quotas.sql" || exit 1
sleep 1

echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Optional: Workload Scheduling (v25+)${NC}"
echo -e "${YELLOW}========================================${NC}"
read -p "Setup Workload Scheduling? (requires ClickHouse 25+) (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    run_step 8 "Workload Scheduling" "08-workload-scheduling.sql"
    sleep 1
else
    echo -e "${YELLOW}Skipping Workload Scheduling${NC}"
fi

# 최종 검증
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Final Verification${NC}"
echo -e "${CYAN}========================================${NC}"

run_step 9 "Monitoring & Verification" "09-monitoring.sql"

# 완료
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Test user connections:"
echo "   ./connect-as.sh analyst"
echo "   ./connect-as.sh bi"
echo ""
echo "2. Run permission tests:"
echo "   ./test-as.sh"
echo ""
echo "3. Clean up when done:"
echo "   clickhouse-client < 99-cleanup.sql"
echo ""
