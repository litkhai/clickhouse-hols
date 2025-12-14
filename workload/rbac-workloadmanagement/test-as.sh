#!/bin/bash

# ============================================
# ClickHouse RBAC Lab - Permission Test Script
# 각 사용자의 권한을 테스트하는 스크립트
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
CH_SECURE="${CH_SECURE:---secure}"

# 사용자 정보
declare -A USERS=(
    ["demo_bi_user"]="SecurePass123!"
    ["demo_analyst"]="AnalystPass456!"
    ["demo_engineer"]="EngineerPass789!"
    ["demo_partner"]="PartnerPass000!"
)

# 테스트 실행 함수
run_test() {
    local username=$1
    local password=$2
    local test_name=$3
    local query=$4
    local expect_success=$5

    echo -ne "  ${CYAN}${test_name}...${NC} "

    output=$(clickhouse-client \
        --host="${CH_HOST}" \
        --port="${CH_PORT}" \
        --user="${username}" \
        --password="${password}" \
        ${CH_SECURE} \
        --query="${query}" 2>&1)

    exit_code=$?

    if [ $expect_success -eq 1 ]; then
        if [ $exit_code -eq 0 ]; then
            echo -e "${GREEN}✓ PASS${NC}"
            return 0
        else
            echo -e "${RED}✗ FAIL (expected success)${NC}"
            echo "    Error: $output"
            return 1
        fi
    else
        if [ $exit_code -ne 0 ]; then
            echo -e "${GREEN}✓ PASS (correctly denied)${NC}"
            return 0
        else
            echo -e "${RED}✗ FAIL (should be denied)${NC}"
            echo "    Output: $output"
            return 1
        fi
    fi
}

# 사용자별 테스트 실행
test_user() {
    local username=$1
    local password=$2

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Testing: ${username}${NC}"
    echo -e "${BLUE}========================================${NC}"

    case $username in
        demo_bi_user)
            run_test "$username" "$password" "Read sales table" \
                "SELECT count() FROM rbac_demo.sales" 1
            run_test "$username" "$password" "Read customers (limited columns)" \
                "SELECT id, name, region FROM rbac_demo.customers" 1
            run_test "$username" "$password" "Read customers (all columns)" \
                "SELECT * FROM rbac_demo.customers" 0
            run_test "$username" "$password" "Insert into sales" \
                "INSERT INTO rbac_demo.sales VALUES (999, 'TEST', 'Test', 0, today(), 0)" 0
            ;;

        demo_analyst)
            run_test "$username" "$password" "Read sales table" \
                "SELECT count() FROM rbac_demo.sales" 1
            run_test "$username" "$password" "Read customers (limited columns)" \
                "SELECT id, name, region FROM rbac_demo.customers" 1
            run_test "$username" "$password" "Read customers (all columns)" \
                "SELECT * FROM rbac_demo.customers" 0
            run_test "$username" "$password" "Create temporary table" \
                "CREATE TEMPORARY TABLE temp_test (id UInt64)" 1
            run_test "$username" "$password" "Insert into sales" \
                "INSERT INTO rbac_demo.sales VALUES (999, 'TEST', 'Test', 0, today(), 0)" 0
            run_test "$username" "$password" "Check settings profile" \
                "SELECT getSetting('max_memory_usage')" 1
            ;;

        demo_engineer)
            run_test "$username" "$password" "Read sales table" \
                "SELECT count() FROM rbac_demo.sales" 1
            run_test "$username" "$password" "Read customers (all columns)" \
                "SELECT * FROM rbac_demo.customers" 1
            run_test "$username" "$password" "Insert into sales" \
                "INSERT INTO rbac_demo.sales VALUES (999, 'TEST', 'Test', 0, today(), 0)" 1
            run_test "$username" "$password" "Delete test data" \
                "DELETE FROM rbac_demo.sales WHERE id = 999" 1
            ;;

        demo_partner)
            run_test "$username" "$password" "Read sales (APAC only)" \
                "SELECT count() FROM rbac_demo.sales WHERE region = 'APAC'" 1
            run_test "$username" "$password" "Count all sales (should only see APAC)" \
                "SELECT count() FROM rbac_demo.sales" 1
            run_test "$username" "$password" "Read customers table" \
                "SELECT count() FROM rbac_demo.customers" 0
            run_test "$username" "$password" "Read customer_id from sales" \
                "SELECT customer_id FROM rbac_demo.sales LIMIT 1" 0
            run_test "$username" "$password" "Read allowed columns only" \
                "SELECT id, region, product FROM rbac_demo.sales LIMIT 1" 1
            ;;
    esac
}

# 메인 실행
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}ClickHouse RBAC Permission Tests${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "Host: ${CH_HOST}:${CH_PORT}"

# 모든 사용자 테스트
for username in "${!USERS[@]}"; do
    test_user "$username" "${USERS[$username]}"
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Complete${NC}"
echo -e "${BLUE}========================================${NC}"
