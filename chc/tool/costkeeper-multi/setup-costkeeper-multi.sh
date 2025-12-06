#!/bin/bash
# ============================================================================
# CostKeeper Multi-Service: ClickHouse Cloud Cost Monitoring Setup Script
# ============================================================================
# Description: Interactive setup script for multi-service CostKeeper (CHC Exclusive)
# Version: 2.0-multi
# Date: 2025-12-07
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
CONFIG_FILE="${SCRIPT_DIR}/costkeeper-multi.conf"

# Detect which clickhouse client command is available
CLICKHOUSE_CLIENT_CMD=""
if command -v clickhouse-client &> /dev/null || which clickhouse-client &> /dev/null; then
    CLICKHOUSE_CLIENT_CMD="clickhouse-client"
elif command -v clickhouse &> /dev/null || which clickhouse &> /dev/null; then
    CLICKHOUSE_CLIENT_CMD="clickhouse client"
fi

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
║              CostKeeper Multi-Service                        ║
║     ClickHouse Cloud Cost Monitoring & Alerting              ║
║                Version 2.0-multi                             ║
║              (CHC Exclusive - remoteSecure)                  ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

print_info "CostKeeper Multi-Service는 같은 Organization 내 여러 CHC 서비스를 모니터링합니다."
print_info "remoteSecure() 함수를 사용하여 각 서비스의 시스템 메트릭을 수집합니다."
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
        echo ""
    else
        SKIP_CREDENTIALS=false
    fi
    echo ""
else
    SKIP_CREDENTIALS=false
fi

# ============================================================================
# Step 2: Primary Service (CostKeeper 설치 위치)
# ============================================================================
if [ "$SKIP_CREDENTIALS" = false ]; then
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Step 1: Primary Service (CostKeeper 설치 위치)"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_info "Primary Service는 CostKeeper 데이터베이스가 설치될 서비스입니다."
    print_info "이 서비스에서 모든 서비스의 메트릭을 수집합니다."
    echo ""

    # Validate CHC Host
    while true; do
        prompt_input "Primary 서비스 호스트 (예: primary.us-east-1.aws.clickhouse.cloud)" "" CH_HOST

        # Remove https:// or http:// prefix if present
        CH_HOST=$(echo "$CH_HOST" | sed -E 's|^https?://||')

        if [ -z "$CH_HOST" ]; then
            print_error "호스트를 입력해주세요."
            continue
        fi

        if [[ ! "$CH_HOST" =~ \.clickhouse\.cloud$ ]]; then
            print_warning "경고: CHC 호스트는 일반적으로 '.clickhouse.cloud'로 끝납니다."
            prompt_input "계속하시겠습니까? (yes/no)" "no" CONFIRM_HOST
            if [ "$CONFIRM_HOST" != "yes" ] && [ "$CONFIRM_HOST" != "y" ]; then
                continue
            fi
        fi

        print_success "호스트: ${CH_HOST}"
        break
    done

    # Validate CHC Password
    while true; do
        prompt_password "Primary 서비스 비밀번호" CH_PASSWORD

        if [ -z "$CH_PASSWORD" ]; then
            print_error "비밀번호를 입력해주세요."
            continue
        fi

        if [ ${#CH_PASSWORD} -lt 8 ]; then
            print_warning "비밀번호가 너무 짧습니다 (최소 8자 권장)."
            prompt_input "계속하시겠습니까? (yes/no)" "no" CONFIRM_PWD
            if [ "$CONFIRM_PWD" != "yes" ] && [ "$CONFIRM_PWD" != "y" ]; then
                continue
            fi
        fi

        print_success "비밀번호가 입력되었습니다."
        break
    done

    # CHC 고정값
    CH_PORT=8443
    CH_USER=default

    echo ""

    # Test connection
    print_info "Primary 서비스 연결을 테스트합니다..."

    VERSION=$(curl -s "https://${CH_HOST}:${CH_PORT}/?query=SELECT%20version()" --user "${CH_USER}:${CH_PASSWORD}" 2>&1)
    CURL_EXIT_CODE=$?

    if [ $CURL_EXIT_CODE -eq 0 ] && [ -n "$VERSION" ] && [[ ! "$VERSION" =~ "Code:" ]]; then
        print_success "Primary 서비스 연결 성공! (ClickHouse version: ${VERSION})"
    else
        print_error "Primary 서비스 연결 실패. 호스트 또는 비밀번호를 확인해주세요."
        if [[ "$VERSION" =~ "Code:" ]]; then
            print_error "오류: ${VERSION}"
        fi
        print_error "다시 시작하려면 스크립트를 재실행하세요."
        exit 1
    fi

    echo ""

    # ============================================================================
    # Step 3: CHC API & Organization
    # ============================================================================
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Step 2: ClickHouse Cloud API Configuration"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_info "CHC API는 Billing 데이터와 서비스 목록을 조회하는데 필요합니다."
    print_info "API Key는 ClickHouse Cloud Console에서 발급받을 수 있습니다."
    echo ""

    # Validate Organization ID
    while true; do
        prompt_input "CHC Organization ID (UUID 형식)" "" CHC_ORG_ID

        if [ -z "$CHC_ORG_ID" ]; then
            print_error "Organization ID를 입력해주세요."
            continue
        fi

        if [[ ! "$CHC_ORG_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
            print_warning "경고: Organization ID는 일반적으로 UUID 형식입니다."
            prompt_input "계속하시겠습니까? (yes/no)" "no" CONFIRM_ORG_ID
            if [ "$CONFIRM_ORG_ID" != "yes" ] && [ "$CONFIRM_ORG_ID" != "y" ]; then
                continue
            fi
        fi

        print_success "Organization ID: ${CHC_ORG_ID}"
        break
    done

    # Validate API Key ID
    while true; do
        prompt_input "CHC API Key ID" "" CHC_API_KEY_ID

        if [ -z "$CHC_API_KEY_ID" ]; then
            print_error "API Key ID를 입력해주세요."
            continue
        fi

        if [ ${#CHC_API_KEY_ID} -lt 10 ]; then
            print_warning "API Key ID가 너무 짧습니다 (최소 10자 권장)."
            prompt_input "계속하시겠습니까? (yes/no)" "no" CONFIRM_KEY_ID
            if [ "$CONFIRM_KEY_ID" != "yes" ] && [ "$CONFIRM_KEY_ID" != "y" ]; then
                continue
            fi
        fi

        print_success "API Key ID: ${CHC_API_KEY_ID}"
        break
    done

    # Validate API Key Secret
    while true; do
        prompt_password "CHC API Key Secret" CHC_API_KEY_SECRET

        if [ -z "$CHC_API_KEY_SECRET" ]; then
            print_error "API Key Secret을 입력해주세요."
            continue
        fi

        if [ ${#CHC_API_KEY_SECRET} -lt 20 ]; then
            print_warning "API Key Secret이 너무 짧습니다 (최소 20자 권장)."
            prompt_input "계속하시겠습니까? (yes/no)" "no" CONFIRM_KEY_SECRET
            if [ "$CONFIRM_KEY_SECRET" != "yes" ] && [ "$CONFIRM_KEY_SECRET" != "y" ]; then
                continue
            fi
        fi

        print_success "API Key Secret이 입력되었습니다."
        break
    done

    echo ""

    # Test CHC API connection
    print_info "CHC API 연결을 테스트합니다..."

    API_TEST_URL="https://api.clickhouse.cloud/v1/organizations/${CHC_ORG_ID}"
    API_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$API_TEST_URL" \
        -u "${CHC_API_KEY_ID}:${CHC_API_KEY_SECRET}" \
        -H "Content-Type: application/json" 2>&1)

    HTTP_CODE=$(echo "$API_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$API_RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        ORG_NAME=$(echo "$RESPONSE_BODY" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | head -n1)
        if [ -n "$ORG_NAME" ]; then
            print_success "CHC API 연결 성공! (Organization: ${ORG_NAME})"
        else
            print_success "CHC API 연결 성공!"
        fi
    elif [ "$HTTP_CODE" = "401" ]; then
        print_error "CHC API 인증 실패. API Key를 확인해주세요."
        print_error "다시 시작하려면 스크립트를 재실행하세요."
        exit 1
    elif [ "$HTTP_CODE" = "404" ]; then
        print_error "CHC API 연결 실패. Organization ID를 확인해주세요."
        print_error "다시 시작하려면 스크립트를 재실행하세요."
        exit 1
    else
        print_warning "CHC API 연결 테스트를 완료할 수 없습니다 (HTTP ${HTTP_CODE})."
        print_warning "계속 진행하지만, API 정보가 정확한지 확인해주세요."
    fi

    echo ""

    # ============================================================================
    # Step 4: Multi-Service Selection
    # ============================================================================
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Step 3: Multi-Service Selection"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_info "Organization 내 사용 가능한 서비스 목록을 조회합니다..."
    echo ""

    SERVICES_URL="https://api.clickhouse.cloud/v1/organizations/${CHC_ORG_ID}/services"
    SERVICES_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$SERVICES_URL" \
        -u "${CHC_API_KEY_ID}:${CHC_API_KEY_SECRET}" \
        -H "Content-Type: application/json" 2>&1)

    SERVICES_HTTP_CODE=$(echo "$SERVICES_RESPONSE" | tail -n1)
    SERVICES_BODY=$(echo "$SERVICES_RESPONSE" | sed '$d')

    # Parse services into arrays
    declare -a SERVICE_IDS
    declare -a SERVICE_NAMES
    declare -a SERVICE_HOSTS
    SERVICE_COUNT=0

    if [ "$SERVICES_HTTP_CODE" = "200" ]; then
        # Use Python to parse JSON
        SERVICE_DATA=$(echo "$SERVICES_BODY" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'result' in data:
        for service in data['result']:
            service_id = service.get('id', '')
            service_name = service.get('name', '')
            # Extract hostname from endpoints
            hostname = ''
            if 'endpoints' in service:
                for endpoint in service['endpoints']:
                    if endpoint.get('protocol') == 'https':
                        hostname = endpoint.get('host', '')
                        break
            print(f'{service_id}|{service_name}|{hostname}')
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)

        if [[ "$SERVICE_DATA" =~ ^ERROR ]]; then
            print_error "서비스 목록 파싱 실패: ${SERVICE_DATA}"
            exit 1
        fi

        # Read into arrays
        while IFS='|' read -r sid sname shost; do
            if [ -n "$sid" ] && [ -n "$sname" ]; then
                SERVICE_IDS+=("$sid")
                SERVICE_NAMES+=("$sname")
                SERVICE_HOSTS+=("$shost")
                ((SERVICE_COUNT++))
            fi
        done <<< "$SERVICE_DATA"

        if [ $SERVICE_COUNT -eq 0 ]; then
            print_error "사용 가능한 서비스를 찾을 수 없습니다."
            exit 1
        fi

        print_success "${SERVICE_COUNT}개의 서비스를 찾았습니다."
        echo ""

        # Display services
        print_info "사용 가능한 서비스 목록:"
        for i in "${!SERVICE_NAMES[@]}"; do
            echo "  [$((i+1))] ${SERVICE_NAMES[$i]} (${SERVICE_HOSTS[$i]})"
        done
        echo ""

        # User selection
        declare -a SELECTED_SERVICES
        MONITORING_SERVICE_COUNT=0

        print_info "모니터링할 서비스를 선택하세요."
        print_warning "⚠️  Performance 고려사항:"
        echo "  • 서비스당 약 1-2초의 메트릭 수집 시간 추가"
        echo "  • 권장 서비스 수: 5-10개"
        echo "  • 최대 서비스 수: ~20개 (RMV timeout 제한)"
        echo ""

        prompt_input "몇 개의 서비스를 모니터링하시겠습니까?" "1" MONITORING_SERVICE_COUNT

        if ! [[ "$MONITORING_SERVICE_COUNT" =~ ^[0-9]+$ ]] || [ "$MONITORING_SERVICE_COUNT" -lt 1 ]; then
            print_error "유효한 숫자를 입력해주세요."
            exit 1
        fi

        if [ "$MONITORING_SERVICE_COUNT" -gt "$SERVICE_COUNT" ]; then
            print_error "사용 가능한 서비스 수($SERVICE_COUNT)를 초과할 수 없습니다."
            exit 1
        fi

        if [ "$MONITORING_SERVICE_COUNT" -gt 20 ]; then
            print_warning "경고: 20개 이상의 서비스는 성능 문제가 발생할 수 있습니다."
            prompt_input "계속하시겠습니까? (yes/no)" "no" CONFIRM_COUNT
            if [ "$CONFIRM_COUNT" != "yes" ] && [ "$CONFIRM_COUNT" != "y" ]; then
                exit 1
            fi
        fi

        echo ""

        # Collect service selections
        for ((n=1; n<=$MONITORING_SERVICE_COUNT; n++)); do
            while true; do
                prompt_input "모니터링할 서비스 #${n} 번호를 입력하세요 (1-${SERVICE_COUNT})" "" SERVICE_NUM

                if ! [[ "$SERVICE_NUM" =~ ^[0-9]+$ ]] || [ "$SERVICE_NUM" -lt 1 ] || [ "$SERVICE_NUM" -gt "$SERVICE_COUNT" ]; then
                    print_error "1에서 ${SERVICE_COUNT} 사이의 번호를 입력해주세요."
                    continue
                fi

                # Check for duplicates
                idx=$((SERVICE_NUM - 1))
                selected_id="${SERVICE_IDS[$idx]}"
                duplicate=false
                for selected in "${SELECTED_SERVICES[@]}"; do
                    if [ "$selected" = "$selected_id" ]; then
                        print_error "이미 선택된 서비스입니다. 다른 서비스를 선택해주세요."
                        duplicate=true
                        break
                    fi
                done

                if [ "$duplicate" = true ]; then
                    continue
                fi

                SELECTED_SERVICES+=("$selected_id")
                print_success "선택됨: ${SERVICE_NAMES[$idx]}"
                break
            done
        done

        echo ""
        print_success "${#SELECTED_SERVICES[@]}개 서비스가 선택되었습니다."
        echo ""

    else
        print_error "서비스 목록 조회 실패 (HTTP ${SERVICES_HTTP_CODE})."
        exit 1
    fi

    # ============================================================================
    # Step 5: Collect Credentials for Each Selected Service
    # ============================================================================
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Step 4: Service Credentials"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_info "각 서비스의 인증 정보를 입력하세요."
    print_warning "⚠️  보안 권장사항:"
    echo "  • read-only user 사용 권장 (system 테이블만 조회)"
    echo "  • Primary 서비스가 침해되면 모든 서비스 접근 가능"
    echo ""

    # Store service credentials
    declare -a MONITORED_SERVICES

    for selected_id in "${SELECTED_SERVICES[@]}"; do
        # Find service index
        for i in "${!SERVICE_IDS[@]}"; do
            if [ "${SERVICE_IDS[$i]}" = "$selected_id" ]; then
                service_name="${SERVICE_NAMES[$i]}"
                service_host="${SERVICE_HOSTS[$i]}"

                echo ""
                print_info "서비스: ${service_name} (${service_host})"

                # Check if this is the primary service
                if [ "$service_host" = "$CH_HOST" ]; then
                    print_info "이 서비스는 Primary 서비스입니다. 동일한 credentials를 사용합니다."
                    MONITORED_SERVICES+=("${service_name}|${service_host}|${CH_USER}|${CH_PASSWORD}")
                else
                    # Collect remote service credentials
                    prompt_input "User [default]" "default" remote_user
                    prompt_password "Password" remote_password

                    # Test remote connection
                    print_info "원격 서비스 연결을 테스트합니다..."
                    REMOTE_VERSION=$(curl -s "https://${service_host}:8443/?query=SELECT%20version()" --user "${remote_user}:${remote_password}" 2>&1)
                    REMOTE_CURL_EXIT=$?

                    if [ $REMOTE_CURL_EXIT -eq 0 ] && [ -n "$REMOTE_VERSION" ] && [[ ! "$REMOTE_VERSION" =~ "Code:" ]]; then
                        print_success "원격 서비스 연결 성공! (${REMOTE_VERSION})"
                        MONITORED_SERVICES+=("${service_name}|${service_host}|${remote_user}|${remote_password}")
                    else
                        print_error "원격 서비스 연결 실패. 인증 정보를 확인해주세요."
                        if [[ "$REMOTE_VERSION" =~ "Code:" ]]; then
                            print_error "오류: ${REMOTE_VERSION}"
                        fi
                        exit 1
                    fi
                fi
                break
            fi
        done
    done

    echo ""
    print_success "모든 서비스의 인증 정보가 입력되었습니다."
    echo ""

fi

# ============================================================================
# Step 6: Save Credentials
# ============================================================================
if [ "$SKIP_CREDENTIALS" = false ]; then
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Step 5: Save Configuration"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_info "인증 정보를 저장합니다..."

    # Create .credentials file
    cat > "$CREDENTIALS_FILE" << EOF
# ============================================================================
# CostKeeper Multi-Service Credentials
# ============================================================================
# ⚠️  WARNING: This file contains sensitive information!
# ⚠️  Keep this file secure and do not commit to version control
# ============================================================================

# Primary Service (CostKeeper 설치 위치)
CH_HOST=${CH_HOST}
CH_PORT=${CH_PORT}
CH_USER=${CH_USER}
CH_PASSWORD=${CH_PASSWORD}

# CHC API Configuration (Organization-wide)
CHC_ORG_ID=${CHC_ORG_ID}
CHC_API_KEY_ID=${CHC_API_KEY_ID}
CHC_API_KEY_SECRET=${CHC_API_KEY_SECRET}

# Monitoring Mode
MONITORING_MODE=multi

# Monitored Services (name|host|user|password)
CH_MONITORED_SERVICES=(
EOF

    # Add each monitored service
    for service_entry in "${MONITORED_SERVICES[@]}"; do
        echo "  \"${service_entry}\"" >> "$CREDENTIALS_FILE"
    done

    cat >> "$CREDENTIALS_FILE" << EOF
)
EOF

    chmod 600 "$CREDENTIALS_FILE"
    print_success "인증 정보가 저장되었습니다: ${CREDENTIALS_FILE}"
    echo ""
fi

# If we skipped credential collection, load the monitored services
if [ "$SKIP_CREDENTIALS" = true ]; then
    # MONITORED_SERVICES already loaded from .credentials file
    :
fi

# ============================================================================
# Step 7: CostKeeper Configuration
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 6: CostKeeper Configuration"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Database Name
prompt_input "Database Name" "costkeeper" DATABASE_NAME

# Data Retention
prompt_input "Data Retention (days)" "90" DATA_RETENTION_DAYS

# Alert Threshold
prompt_input "Alert Threshold (%)" "50" ALERT_THRESHOLD_PCT

echo ""
print_success "Configuration:"
echo "  • Database: ${DATABASE_NAME}"
echo "  • Data Retention: ${DATA_RETENTION_DAYS} days"
echo "  • Alert Threshold: ${ALERT_THRESHOLD_PCT}%"
echo "  • Monitored Services: ${#MONITORED_SERVICES[@]}"
echo ""

# ============================================================================
# Step 8: Generate SQL with Multi-Service CTEs
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 7: Generate SQL"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_info "멀티 서비스 SQL을 생성합니다..."

# Read template
TEMPLATE_FILE="${SCRIPT_DIR}/costkeeper-multi-template.sql"
if [ ! -f "$TEMPLATE_FILE" ]; then
    print_error "Template file not found: ${TEMPLATE_FILE}"
    exit 1
fi

GENERATED_SQL="${SCRIPT_DIR}/costkeeper-multi-generated.sql"

# Start with template content
cp "$TEMPLATE_FILE" "$GENERATED_SQL"

# Replace basic variables
sed -i.bak "s/\${DATABASE_NAME}/${DATABASE_NAME}/g" "$GENERATED_SQL"
sed -i.bak "s/\${CHC_ORG_ID}/${CHC_ORG_ID}/g" "$GENERATED_SQL"
sed -i.bak "s/\${CHC_API_KEY_ID}/${CHC_API_KEY_ID}/g" "$GENERATED_SQL"
sed -i.bak "s/\${CHC_API_KEY_SECRET}/${CHC_API_KEY_SECRET}/g" "$GENERATED_SQL"
sed -i.bak "s/\${DATA_RETENTION_DAYS}/${DATA_RETENTION_DAYS}/g" "$GENERATED_SQL"
sed -i.bak "s/\${ALERT_THRESHOLD_PCT}/${ALERT_THRESHOLD_PCT}/g" "$GENERATED_SQL"

# Generate service-specific CTEs
SERVICE_METRICS_CTES=""
SERVICE_UNION_ALL=""

service_idx=0
for service_entry in "${MONITORED_SERVICES[@]}"; do
    IFS='|' read -r sname shost suser spass <<< "$service_entry"

    # Determine if this is local or remote
    if [ "$shost" = "$CH_HOST" ]; then
        # Local service - no remoteSecure
        SERVICE_METRICS_CTES+="    service_${service_idx}_metrics AS (
        SELECT
            '${sname}' as service_name,
            toStartOfFifteenMinutes(now()) as collected_at,
            avgIf(value, metric = 'CGroupMaxCPU') as allocated_cpu,
            avgIf(value, metric = 'CGroupMemoryTotal') / (1024 * 1024 * 1024) as allocated_memory_gb,
            avgIf(value, metric = 'CGroupUserTimeNormalized') + avgIf(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_avg,
            quantileIf(0.5)(value, metric = 'CGroupUserTimeNormalized') + quantileIf(0.5)(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_p50,
            quantileIf(0.9)(value, metric = 'CGroupUserTimeNormalized') + quantileIf(0.9)(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_p90,
            quantileIf(0.99)(value, metric = 'CGroupUserTimeNormalized') + quantileIf(0.99)(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_p99,
            maxIf(value, metric = 'CGroupUserTimeNormalized') + maxIf(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_max,
            avgIf(value, metric = 'CGroupUserTimeNormalized') as cpu_user_cores,
            avgIf(value, metric = 'CGroupSystemTimeNormalized') as cpu_system_cores,
            avgIf(value, metric = 'CGroupMemoryUsed') / (1024 * 1024 * 1024) as memory_used_avg_gb,
            quantileIf(0.99)(value, metric = 'CGroupMemoryUsed') / (1024 * 1024 * 1024) as memory_used_p99_gb,
            maxIf(value, metric = 'CGroupMemoryUsed') / (1024 * 1024 * 1024) as memory_used_max_gb,
            (avgIf(value, metric = 'CGroupMemoryUsed') / avgIf(value, metric = 'CGroupMemoryTotal')) * 100 as memory_usage_pct_avg,
            (quantileIf(0.99)(value, metric = 'CGroupMemoryUsed') / avgIf(value, metric = 'CGroupMemoryTotal')) * 100 as memory_usage_pct_p99,
            (maxIf(value, metric = 'CGroupMemoryUsed') / avgIf(value, metric = 'CGroupMemoryTotal')) * 100 as memory_usage_pct_max,
            sumIf(value, metric LIKE 'BlockReadBytes%') as disk_read_bytes,
            sumIf(value, metric LIKE 'BlockWriteBytes%') as disk_write_bytes,
            maxIf(value, metric = 'FilesystemMainPathTotalBytes') / (1024 * 1024 * 1024) as disk_total_gb,
            maxIf(value, metric = 'FilesystemMainPathUsedBytes') / (1024 * 1024 * 1024) as disk_used_gb,
            (maxIf(value, metric = 'FilesystemMainPathUsedBytes') / maxIf(value, metric = 'FilesystemMainPathTotalBytes')) * 100 as disk_usage_pct,
            sumIf(value, metric = 'NetworkReceiveBytes_eth0') as network_rx_bytes,
            sumIf(value, metric = 'NetworkSendBytes_eth0') as network_tx_bytes,
            avgIf(value, metric = 'LoadAverage1') as load_avg_1m,
            avgIf(value, metric = 'LoadAverage5') as load_avg_5m,
            avgIf(value, metric = 'OSProcessesRunning') as processes_running_avg
        FROM system.asynchronous_metric_log
        WHERE event_time >= (SELECT start_time FROM target_period)
          AND event_time < now()
    ),
"
    else
        # Remote service - use remoteSecure
        SERVICE_METRICS_CTES+="    service_${service_idx}_metrics AS (
        SELECT
            '${sname}' as service_name,
            toStartOfFifteenMinutes(now()) as collected_at,
            avgIf(value, metric = 'CGroupMaxCPU') as allocated_cpu,
            avgIf(value, metric = 'CGroupMemoryTotal') / (1024 * 1024 * 1024) as allocated_memory_gb,
            avgIf(value, metric = 'CGroupUserTimeNormalized') + avgIf(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_avg,
            quantileIf(0.5)(value, metric = 'CGroupUserTimeNormalized') + quantileIf(0.5)(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_p50,
            quantileIf(0.9)(value, metric = 'CGroupUserTimeNormalized') + quantileIf(0.9)(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_p90,
            quantileIf(0.99)(value, metric = 'CGroupUserTimeNormalized') + quantileIf(0.99)(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_p99,
            maxIf(value, metric = 'CGroupUserTimeNormalized') + maxIf(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_max,
            avgIf(value, metric = 'CGroupUserTimeNormalized') as cpu_user_cores,
            avgIf(value, metric = 'CGroupSystemTimeNormalized') as cpu_system_cores,
            avgIf(value, metric = 'CGroupMemoryUsed') / (1024 * 1024 * 1024) as memory_used_avg_gb,
            quantileIf(0.99)(value, metric = 'CGroupMemoryUsed') / (1024 * 1024 * 1024) as memory_used_p99_gb,
            maxIf(value, metric = 'CGroupMemoryUsed') / (1024 * 1024 * 1024) as memory_used_max_gb,
            (avgIf(value, metric = 'CGroupMemoryUsed') / avgIf(value, metric = 'CGroupMemoryTotal')) * 100 as memory_usage_pct_avg,
            (quantileIf(0.99)(value, metric = 'CGroupMemoryUsed') / avgIf(value, metric = 'CGroupMemoryTotal')) * 100 as memory_usage_pct_p99,
            (maxIf(value, metric = 'CGroupMemoryUsed') / avgIf(value, metric = 'CGroupMemoryTotal')) * 100 as memory_usage_pct_max,
            sumIf(value, metric LIKE 'BlockReadBytes%') as disk_read_bytes,
            sumIf(value, metric LIKE 'BlockWriteBytes%') as disk_write_bytes,
            maxIf(value, metric = 'FilesystemMainPathTotalBytes') / (1024 * 1024 * 1024) as disk_total_gb,
            maxIf(value, metric = 'FilesystemMainPathUsedBytes') / (1024 * 1024 * 1024) as disk_used_gb,
            (maxIf(value, metric = 'FilesystemMainPathUsedBytes') / maxIf(value, metric = 'FilesystemMainPathTotalBytes')) * 100 as disk_usage_pct,
            sumIf(value, metric = 'NetworkReceiveBytes_eth0') as network_rx_bytes,
            sumIf(value, metric = 'NetworkSendBytes_eth0') as network_tx_bytes,
            avgIf(value, metric = 'LoadAverage1') as load_avg_1m,
            avgIf(value, metric = 'LoadAverage5') as load_avg_5m,
            avgIf(value, metric = 'OSProcessesRunning') as processes_running_avg
        FROM remoteSecure(
            '${shost}:8443',
            'system.asynchronous_metric_log',
            '${suser}',
            '${spass}'
        )
        WHERE event_time >= (SELECT start_time FROM target_period)
          AND event_time < now()
    ),
"
    fi

    # Add to UNION ALL
    if [ $service_idx -eq 0 ]; then
        SERVICE_UNION_ALL+="        SELECT * FROM service_${service_idx}_metrics"
    else
        SERVICE_UNION_ALL+="
        UNION ALL
        SELECT * FROM service_${service_idx}_metrics"
    fi

    ((service_idx++))
done

# Write the generated CTEs to a temp file
TEMP_CTE_FILE="${SCRIPT_DIR}/.temp_ctes"
echo "$SERVICE_METRICS_CTES" > "$TEMP_CTE_FILE"

TEMP_UNION_FILE="${SCRIPT_DIR}/.temp_union"
echo "$SERVICE_UNION_ALL" > "$TEMP_UNION_FILE"

# Replace placeholders using awk (more reliable for multi-line)
awk -v ctes="$SERVICE_METRICS_CTES" '{gsub(/\$\{SERVICE_METRICS_CTES\}/, ctes)}1' "$GENERATED_SQL" > "${GENERATED_SQL}.tmp"
mv "${GENERATED_SQL}.tmp" "$GENERATED_SQL"

awk -v unions="$SERVICE_UNION_ALL" '{gsub(/\$\{SERVICE_UNION_ALL\}/, unions)}1' "$GENERATED_SQL" > "${GENERATED_SQL}.tmp"
mv "${GENERATED_SQL}.tmp" "$GENERATED_SQL"

# Cleanup
rm -f "${GENERATED_SQL}.bak" "$TEMP_CTE_FILE" "$TEMP_UNION_FILE"

print_success "SQL 생성 완료: ${GENERATED_SQL}"
echo ""

# ============================================================================
# Step 9: Deploy to ClickHouse
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 8: Deploy to ClickHouse"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

prompt_input "지금 ClickHouse에 배포하시겠습니까? (yes/no)" "yes" DEPLOY_NOW

if [ "$DEPLOY_NOW" = "yes" ] || [ "$DEPLOY_NOW" = "y" ]; then
    print_info "CostKeeper를 배포합니다..."
    echo ""

    if [ -z "$CLICKHOUSE_CLIENT_CMD" ]; then
        print_error "clickhouse-client를 찾을 수 없습니다."
        print_info "수동으로 배포하려면 다음 명령어를 실행하세요:"
        echo ""
        echo "  clickhouse client --host ${CH_HOST} --user ${CH_USER} --password '${CH_PASSWORD}' --secure --multiquery < ${GENERATED_SQL}"
        echo ""
        exit 1
    fi

    # Execute SQL
    $CLICKHOUSE_CLIENT_CMD --host "${CH_HOST}" --port "${CH_PORT}" --user "${CH_USER}" --password "${CH_PASSWORD}" --secure --multiquery < "$GENERATED_SQL"

    if [ $? -eq 0 ]; then
        print_success "CostKeeper Multi-Service가 성공적으로 배포되었습니다!"
        echo ""
        print_info "다음 단계:"
        echo "  1. RMV가 자동으로 데이터 수집 시작 (15분마다)"
        echo "  2. 첫 hourly 분석은 1시간 후 생성됨"
        echo "  3. ${DATABASE_NAME}.hourly_analysis 테이블에서 결과 확인"
        echo ""
        print_info "모니터링 중인 서비스:"
        for service_entry in "${MONITORED_SERVICES[@]}"; do
            IFS='|' read -r sname shost _ _ <<< "$service_entry"
            echo "  • ${sname} (${shost})"
        done
        echo ""
    else
        print_error "배포 중 오류가 발생했습니다."
        exit 1
    fi
else
    print_info "배포를 건너뛰었습니다."
    print_info "수동으로 배포하려면 다음 명령어를 실행하세요:"
    echo ""
    echo "  ${CLICKHOUSE_CLIENT_CMD} --host ${CH_HOST} --port ${CH_PORT} --user ${CH_USER} --password '${CH_PASSWORD}' --secure --multiquery < ${GENERATED_SQL}"
    echo ""
fi

print_success "CostKeeper Multi-Service 설정이 완료되었습니다!"
echo ""
