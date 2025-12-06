#!/bin/bash
# ============================================================================
# CostKeeper: ClickHouse Cloud Cost Monitoring Setup Script
# ============================================================================
# Description: Interactive setup script for CostKeeper (CHC Exclusive)
# Version: 1.0
# Date: 2025-12-06
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Secret files
CREDENTIALS_FILE="${SCRIPT_DIR}/.credentials"
CONFIG_FILE="${SCRIPT_DIR}/costkeeper.conf"

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${CYAN}$1${NC}"
}

# Function to prompt for input with default value
prompt_input() {
    local prompt_text=$1
    local default_value=$2
    local var_name=$3

    if [ -n "$default_value" ]; then
        read -p "$(echo -e ${BLUE}${prompt_text}${NC} [${default_value}]: )" input_value
        input_value=${input_value:-$default_value}
    else
        read -p "$(echo -e ${BLUE}${prompt_text}${NC}: )" input_value
    fi

    eval "$var_name='$input_value'"
}

# Function to prompt for password (hidden input)
prompt_password() {
    local prompt_text=$1
    local var_name=$2

    read -s -p "$(echo -e ${BLUE}${prompt_text}${NC}: )" input_value
    echo
    eval "$var_name='$input_value'"
}

# Banner
echo -e "${GREEN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                      CostKeeper                              ║
║     ClickHouse Cloud Cost Monitoring & Alerting              ║
║                    Version 1.0                               ║
║                  (CHC Exclusive)                             ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

print_info "CostKeeper는 ClickHouse Cloud 전용 비용 모니터링 시스템입니다."
print_info "RMV와 TTL 등 CHC의 네이티브 기능만을 사용합니다."
echo ""

# ============================================================================
# Step 1: Check for existing credentials
# ============================================================================
if [ -f "$CREDENTIALS_FILE" ]; then
    print_warning "기존 인증 정보가 발견되었습니다."
    prompt_input "기존 인증 정보를 사용하시겠습니까? (yes/no)" "yes" USE_EXISTING_CREDS

    if [ "$USE_EXISTING_CREDS" = "yes" ] || [ "$USE_EXISTING_CREDS" = "y" ]; then
        source "$CREDENTIALS_FILE"
        print_success "기존 인증 정보를 불러왔습니다."
        SKIP_CREDENTIALS=true
    else
        SKIP_CREDENTIALS=false
    fi
    echo ""
else
    SKIP_CREDENTIALS=false
fi

# ============================================================================
# Step 2: ClickHouse Cloud Connection Configuration
# ============================================================================
if [ "$SKIP_CREDENTIALS" = false ]; then
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Step 1: ClickHouse Cloud Connection"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    prompt_input "CHC 호스트 (예: abc123.us-east-1.aws.clickhouse.cloud)" "" CH_HOST
    prompt_input "CHC 포트" "8443" CH_PORT
    prompt_input "CHC 사용자" "default" CH_USER
    prompt_password "CHC 비밀번호" CH_PASSWORD

    echo ""

    # ============================================================================
    # Step 3: CHC API Configuration
    # ============================================================================
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Step 2: ClickHouse Cloud API Configuration"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_info "CHC API Key는 Billing 데이터를 수집하는데 필요합니다."
    print_info "API Key는 ClickHouse Cloud Console에서 발급받을 수 있습니다."
    echo ""

    prompt_input "CHC Organization ID" "" CHC_ORG_ID
    prompt_password "CHC API Key" CHC_API_KEY

    echo ""

    # Save credentials to hidden file
    print_info "인증 정보를 안전하게 저장 중..."

    cat > "$CREDENTIALS_FILE" << EOF
# ============================================================================
# CostKeeper Credentials (DO NOT COMMIT TO VERSION CONTROL)
# Generated: $(date)
# ============================================================================

# ClickHouse Cloud Connection
CH_HOST=${CH_HOST}
CH_PORT=${CH_PORT}
CH_USER=${CH_USER}
CH_PASSWORD=${CH_PASSWORD}

# CHC API Configuration
CHC_ORG_ID=${CHC_ORG_ID}
CHC_API_KEY=${CHC_API_KEY}
EOF

    chmod 600 "$CREDENTIALS_FILE"
    print_success "인증 정보가 안전하게 저장되었습니다: $CREDENTIALS_FILE"

    # Add to .gitignore
    if [ ! -f "${SCRIPT_DIR}/.gitignore" ]; then
        echo ".credentials" > "${SCRIPT_DIR}/.gitignore"
        echo "costkeeper.conf" >> "${SCRIPT_DIR}/.gitignore"
        echo "costkeeper-setup.sql" >> "${SCRIPT_DIR}/.gitignore"
        print_success ".gitignore 파일이 생성되었습니다."
    fi

    echo ""
fi

# ============================================================================
# Step 4: Service Configuration
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 3: Service Configuration"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

prompt_input "Database 이름" "costkeeper" DATABASE_NAME
prompt_input "서비스 이름" "production" SERVICE_NAME
prompt_input "할당된 CPU 코어 수" "2.0" ALLOCATED_CPU
prompt_input "할당된 메모리 (GB)" "8.0" ALLOCATED_MEMORY

echo ""

# ============================================================================
# Step 5: Alert Configuration
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 4: Alert Configuration"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

prompt_input "Alert 임계값 (%)" "20.0" ALERT_THRESHOLD_PCT
prompt_input "Warning Severity 임계값 (%)" "30.0" WARNING_THRESHOLD_PCT
prompt_input "Critical Severity 임계값 (%)" "50.0" CRITICAL_THRESHOLD_PCT

echo ""

# ============================================================================
# Step 6: Data Retention Configuration
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 5: Data Retention Configuration"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

prompt_input "분석 데이터 보관 기간 (일)" "365" DATA_RETENTION_DAYS
prompt_input "Alert 데이터 보관 기간 (일)" "90" ALERT_RETENTION_DAYS

echo ""

# ============================================================================
# Step 7: Generate Configuration File
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 6: Generating Configuration"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cat > "$CONFIG_FILE" << EOF
# ============================================================================
# CostKeeper Configuration (Non-Sensitive)
# Generated: $(date)
# ============================================================================

# Database Configuration
DATABASE_NAME=${DATABASE_NAME}

# Service Configuration
SERVICE_NAME=${SERVICE_NAME}
ALLOCATED_CPU=${ALLOCATED_CPU}
ALLOCATED_MEMORY=${ALLOCATED_MEMORY}

# Alert Configuration
ALERT_THRESHOLD_PCT=${ALERT_THRESHOLD_PCT}
WARNING_THRESHOLD_PCT=${WARNING_THRESHOLD_PCT}
CRITICAL_THRESHOLD_PCT=${CRITICAL_THRESHOLD_PCT}

# Data Retention Configuration
DATA_RETENTION_DAYS=${DATA_RETENTION_DAYS}
ALERT_RETENTION_DAYS=${ALERT_RETENTION_DAYS}

# Connection Settings (CHC Exclusive)
CH_SECURE=true
CH_PORT=${CH_PORT}
EOF

chmod 644 "$CONFIG_FILE"
print_success "설정 파일 생성 완료: $CONFIG_FILE"
echo ""

# ============================================================================
# Step 8: Generate SQL Script
# ============================================================================
print_info "SQL 스크립트 생성 중..."

SQL_FILE="${SCRIPT_DIR}/costkeeper-setup.sql"

# Replace variables in SQL template
sed -e "s/\${DATABASE_NAME}/${DATABASE_NAME}/g" \
    -e "s/\${SERVICE_NAME}/${SERVICE_NAME}/g" \
    -e "s/\${ALLOCATED_CPU}/${ALLOCATED_CPU}/g" \
    -e "s/\${ALLOCATED_MEMORY}/${ALLOCATED_MEMORY}/g" \
    -e "s/\${ALERT_THRESHOLD_PCT}/${ALERT_THRESHOLD_PCT}/g" \
    -e "s/\${WARNING_THRESHOLD_PCT}/${WARNING_THRESHOLD_PCT}/g" \
    -e "s/\${CRITICAL_THRESHOLD_PCT}/${CRITICAL_THRESHOLD_PCT}/g" \
    -e "s/\${DATA_RETENTION_DAYS}/${DATA_RETENTION_DAYS}/g" \
    -e "s/\${ALERT_RETENTION_DAYS}/${ALERT_RETENTION_DAYS}/g" \
    "${SCRIPT_DIR}/costkeeper-template.sql" > "$SQL_FILE"

print_success "SQL 스크립트 생성 완료: $SQL_FILE"
echo ""

# ============================================================================
# Step 9: Test Connection
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 7: Connection Test"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Build clickhouse-client command
build_ch_client_cmd() {
    local cmd="clickhouse-client"
    cmd+=" --host=${CH_HOST}"
    cmd+=" --port=${CH_PORT}"
    cmd+=" --user=${CH_USER}"
    cmd+=" --password=${CH_PASSWORD}"
    cmd+=" --secure"
    echo "$cmd"
}

CH_CLIENT_CMD=$(build_ch_client_cmd)

# Test connection
print_info "ClickHouse Cloud 연결 테스트 중..."
if eval "$CH_CLIENT_CMD --query='SELECT version()'" > /dev/null 2>&1; then
    print_success "연결 테스트 성공!"
else
    print_error "연결 테스트 실패. 연결 정보를 확인해주세요."
    exit 1
fi

echo ""

# ============================================================================
# Step 10: Create Database
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 8: Database Creation"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create database
print_info "Database '${DATABASE_NAME}' 생성 중..."
if eval "$CH_CLIENT_CMD --query=\"CREATE DATABASE IF NOT EXISTS ${DATABASE_NAME}\""; then
    print_success "Database 생성 완료"
else
    print_error "Database 생성 실패"
    exit 1
fi

echo ""

# ============================================================================
# Step 11: Execute SQL Script
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 9: SQL Script Execution"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_warning "SQL 스크립트를 실행하시겠습니까?"
print_warning "경고: 기존 CostKeeper 테이블과 뷰가 삭제될 수 있습니다."
echo ""
prompt_input "계속하시겠습니까? (yes/no)" "yes" CONFIRM_EXECUTE

if [ "$CONFIRM_EXECUTE" = "yes" ] || [ "$CONFIRM_EXECUTE" = "y" ]; then
    print_info "SQL 스크립트 실행 중..."

    # Execute SQL script
    if eval "$CH_CLIENT_CMD --multiquery < ${SQL_FILE}"; then
        print_success "SQL 스크립트 실행 완료!"
    else
        print_error "SQL 스크립트 실행 실패"
        exit 1
    fi
else
    print_info "SQL 스크립트 실행이 취소되었습니다."
    print_info "다음 명령어로 수동 실행할 수 있습니다:"
    echo ""
    echo "  source ${CREDENTIALS_FILE}"
    echo "  clickhouse-client --host=\${CH_HOST} --port=\${CH_PORT} \\"
    echo "    --user=\${CH_USER} --password=\${CH_PASSWORD} --secure \\"
    echo "    --multiquery < ${SQL_FILE}"
    echo ""
    exit 0
fi

echo ""

# ============================================================================
# Step 12: Verification
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 10: Verification"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_info "설치 확인 중..."

# Check tables
TABLES_COUNT=$(eval "$CH_CLIENT_CMD --query=\"SELECT count() FROM system.tables WHERE database = '${DATABASE_NAME}'\" 2>/dev/null || echo 0")

if [ "$TABLES_COUNT" -gt 0 ]; then
    print_success "테이블 생성 확인: ${TABLES_COUNT}개 테이블 발견"

    # List tables
    echo ""
    print_info "생성된 테이블 목록:"
    eval "$CH_CLIENT_CMD --query=\"SELECT name, engine FROM system.tables WHERE database = '${DATABASE_NAME}' ORDER BY name FORMAT PrettyCompact\""
else
    print_warning "테이블이 생성되지 않았습니다."
fi

echo ""

# Check RMV status
print_info "Refreshable Materialized View 상태 확인 중..."
RMV_COUNT=$(eval "$CH_CLIENT_CMD --query=\"SELECT count() FROM system.view_refreshes WHERE database = '${DATABASE_NAME}'\" 2>/dev/null || echo 0")

if [ "$RMV_COUNT" -gt 0 ]; then
    print_success "RMV 확인: ${RMV_COUNT}개 RMV 발견"

    # Show RMV status
    echo ""
    print_info "RMV 상태:"
    eval "$CH_CLIENT_CMD --query=\"SELECT view, status, next_refresh_time FROM system.view_refreshes WHERE database = '${DATABASE_NAME}' FORMAT PrettyCompact\""
else
    print_warning "RMV가 발견되지 않았습니다."
fi

echo ""

# ============================================================================
# Step 13: Summary
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║              CostKeeper 설치가 완료되었습니다!               ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_info "생성된 파일:"
echo "  • 인증 정보 (보안): ${CREDENTIALS_FILE} (권한: 600)"
echo "  • 설정 파일: ${CONFIG_FILE}"
echo "  • SQL 스크립트: ${SQL_FILE}"
echo ""

print_warning "보안 주의사항:"
echo "  • ${CREDENTIALS_FILE} 파일을 절대 Git에 커밋하지 마세요!"
echo "  • .gitignore에 자동으로 추가되었습니다."
echo ""

print_info "주요 객체:"
echo "  • Database: ${DATABASE_NAME}"
echo "  • Tables: hourly_metrics, hourly_analysis, alerts, daily_billing"
echo "  • RMVs: rmv_hourly_metrics, rmv_hourly_analysis, rmv_daily_billing"
echo "  • Views: v_dashboard, v_alerts"
echo ""

print_info "다음 단계:"
echo ""
echo "  1. Dashboard 확인:"
echo "     SELECT * FROM ${DATABASE_NAME}.v_dashboard LIMIT 10;"
echo ""
echo "  2. Alert 확인:"
echo "     SELECT * FROM ${DATABASE_NAME}.v_alerts WHERE acknowledged = 0;"
echo ""
echo "  3. RMV 상태 확인:"
echo "     SELECT * FROM system.view_refreshes WHERE database = '${DATABASE_NAME}';"
echo ""
echo "  4. Billing 데이터 수집 (CHC API):"
echo "     - RMV가 자동으로 매일 billing 데이터를 수집합니다"
echo "     - 수동 실행: SYSTEM REFRESH VIEW ${DATABASE_NAME}.rmv_daily_billing"
echo ""
echo "  5. 외부 시스템 연동:"
echo "     - ${DATABASE_NAME}.alerts 테이블을 polling하여 Slack, PagerDuty 등에 전송"
echo "     - 예제 스크립트는 README.md 참조"
echo ""

print_success "CostKeeper가 성공적으로 설치되었습니다!"
print_info "자세한 내용은 README.md 파일을 참조하세요."
echo ""

print_info "유용한 명령어:"
echo "  • 인증 정보 로드: source ${CREDENTIALS_FILE}"
echo "  • ClickHouse 접속: clickhouse-client --host=\${CH_HOST} --port=\${CH_PORT} --user=\${CH_USER} --password=\${CH_PASSWORD} --secure"
echo ""
