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

# Detect which clickhouse client command is available
CLICKHOUSE_CLIENT_CMD=""
# Try multiple detection methods for better reliability
if command -v clickhouse-client &> /dev/null || which clickhouse-client &> /dev/null; then
    CLICKHOUSE_CLIENT_CMD="clickhouse-client"
elif command -v clickhouse &> /dev/null || which clickhouse &> /dev/null; then
    # For Homebrew macOS installation, 'clickhouse client' subcommand is used
    # Skip version test to avoid Gatekeeper issues - if binary exists, assume it works
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

        echo ""

        # Test connection with existing credentials
        print_info "기존 인증 정보로 CHC 연결을 테스트합니다..."

        # Remove https:// prefix if present in stored credentials
        CH_HOST_CLEAN=$(echo "$CH_HOST" | sed -E 's|^https?://||')

        VERSION=$(curl -s "https://${CH_HOST_CLEAN}:${CH_PORT}/?query=SELECT%20version()" --user "${CH_USER}:${CH_PASSWORD}" 2>&1)
        CURL_EXIT_CODE=$?

        if [ $CURL_EXIT_CODE -eq 0 ] && [ -n "$VERSION" ] && [[ ! "$VERSION" =~ "Code:" ]]; then
            print_success "CHC 연결 성공! (ClickHouse version: ${VERSION})"
        else
            print_error "CHC 연결 실패. 인증 정보가 만료되었거나 올바르지 않습니다."
            if [[ "$VERSION" =~ "Code:" ]]; then
                print_error "오류: ${VERSION}"
            fi
            print_error "다시 시작하려면 스크립트를 재실행하세요."
            exit 1
        fi

        echo ""

        # Test CHC API connection with existing credentials
        print_info "기존 API 정보로 CHC API 연결을 테스트합니다..."

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
            print_error "CHC API 인증 실패. API Key가 만료되었거나 올바르지 않습니다."
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

    print_info "CHC 연결 정보를 입력하세요."
    echo ""

    # Validate CHC Host
    while true; do
        prompt_input "CHC 호스트 (예: abc123.us-east-1.aws.clickhouse.cloud)" "" CH_HOST

        # Remove https:// or http:// prefix if present
        CH_HOST=$(echo "$CH_HOST" | sed -E 's|^https?://||')

        # Validate host format
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
        prompt_password "CHC 비밀번호" CH_PASSWORD

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

    # Test connection immediately after credential input
    print_info "입력하신 정보로 CHC 연결을 테스트합니다..."

    VERSION=$(curl -s "https://${CH_HOST}:${CH_PORT}/?query=SELECT%20version()" --user "${CH_USER}:${CH_PASSWORD}" 2>&1)
    CURL_EXIT_CODE=$?

    if [ $CURL_EXIT_CODE -eq 0 ] && [ -n "$VERSION" ] && [[ ! "$VERSION" =~ "Code:" ]]; then
        print_success "CHC 연결 성공! (ClickHouse version: ${VERSION})"
    else
        print_error "CHC 연결 실패. 호스트 또는 비밀번호를 확인해주세요."
        if [[ "$VERSION" =~ "Code:" ]]; then
            print_error "오류: ${VERSION}"
        fi
        print_error "다시 시작하려면 스크립트를 재실행하세요."
        exit 1
    fi

    echo ""

    # ============================================================================
    # Step 2: CHC API & Service Selection
    # ============================================================================
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Step 2: ClickHouse Cloud API & Service Selection"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_info "CHC API는 Billing 데이터를 수집하는데 필요합니다."
    print_info "API Key는 ClickHouse Cloud Console에서 발급받을 수 있습니다."
    echo ""

    # Validate Organization ID (UUID format)
    while true; do
        prompt_input "CHC Organization ID (UUID 형식)" "" CHC_ORG_ID

        if [ -z "$CHC_ORG_ID" ]; then
            print_error "Organization ID를 입력해주세요."
            continue
        fi

        # UUID format validation (8-4-4-4-12 hex digits)
        if [[ ! "$CHC_ORG_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
            print_warning "경고: Organization ID는 일반적으로 UUID 형식입니다 (예: 12345678-1234-1234-1234-123456789abc)."
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
    print_info "입력하신 API 정보로 CHC API 연결을 테스트합니다..."

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
        print_error "CHC API 인증 실패. API Key ID 또는 Secret을 확인해주세요."
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

    # Get Service List and let user choose
    print_info "사용 가능한 서비스 목록을 조회합니다..."
    echo ""
    print_warning "⚠️  모니터링 범위 안내:"
    echo "  • Billing 데이터: 모든 서비스 자동 수집 (CHC API 사용)"
    echo "  • Hourly Metrics: 선택한 1개 서비스만 수집 (시스템 메트릭 제한)"
    echo "  • 멀티 서비스 메트릭 모니터링은 향후 지원 예정 (TODO_MULTI_SERVICE_MONITORING.md 참조)"
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
    SERVICE_COUNT=0

    if [ "$SERVICES_HTTP_CODE" = "200" ]; then
        # Extract services from result array
        # API response structure: {"result": [{"id":"UUID","name":"Name",...}, ...]}

        # Use Python to parse JSON properly
        SERVICE_DATA=$(echo "$SERVICES_BODY" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'result' in data:
        for service in data['result']:
            print(f\"{service.get('id', '')}|{service.get('name', '')}\")
except:
    pass
")

        SERVICE_IDS=()
        SERVICE_NAMES=()
        SERVICE_COUNT=0

        # Parse the output
        while IFS='|' read -r id name; do
            if [ -n "$id" ] && [ -n "$name" ]; then
                SERVICE_IDS+=("$id")
                SERVICE_NAMES+=("$name")
                SERVICE_COUNT=$((SERVICE_COUNT + 1))
            fi
        done <<< "$SERVICE_DATA"

        if [ "$SERVICE_COUNT" -eq 0 ]; then
            print_error "사용 가능한 서비스가 없습니다."
            print_error "ClickHouse Cloud Console에서 서비스를 먼저 생성해주세요."
            exit 1
        fi

        echo ""
        print_info "사용 가능한 서비스: (${SERVICE_COUNT}개)"
        for i in "${!SERVICE_IDS[@]}"; do
            echo "  [$((i+1))] ${SERVICE_NAMES[$i]} (ID: ${SERVICE_IDS[$i]})"
        done
        echo ""
    else
        print_warning "서비스 목록을 조회할 수 없습니다 (HTTP ${SERVICES_HTTP_CODE})."
        print_info "Service ID를 직접 입력해야 합니다."
        echo ""
    fi

    # Service selection logic
    while true; do
        if [ "$SERVICE_COUNT" -gt 1 ]; then
            prompt_input "Hourly Metrics를 수집할 서비스를 선택하세요 (번호 또는 UUID)" "1" SERVICE_SELECTION
        elif [ "$SERVICE_COUNT" -eq 1 ]; then
            prompt_input "이 서비스의 Hourly Metrics를 수집하시겠습니까? (yes/번호/UUID)" "yes" SERVICE_SELECTION
            if [ "$SERVICE_SELECTION" = "yes" ] || [ "$SERVICE_SELECTION" = "y" ]; then
                SERVICE_SELECTION="1"
            fi
        else
            prompt_input "Hourly Metrics를 수집할 CHC Service ID (UUID 형식)" "" SERVICE_SELECTION
        fi

        if [ -z "$SERVICE_SELECTION" ]; then
            print_error "서비스를 선택해주세요."
            continue
        fi

        # Check if it's a number (service selection)
        if [[ "$SERVICE_SELECTION" =~ ^[0-9]+$ ]]; then
            SERVICE_INDEX=$((SERVICE_SELECTION - 1))
            if [ "$SERVICE_INDEX" -ge 0 ] && [ "$SERVICE_INDEX" -lt "$SERVICE_COUNT" ]; then
                CHC_SERVICE_ID="${SERVICE_IDS[$SERVICE_INDEX]}"
                SERVICE_NAME_FROM_API="${SERVICE_NAMES[$SERVICE_INDEX]}"
                print_info "선택된 서비스: ${SERVICE_NAME_FROM_API}"
            else
                print_error "잘못된 번호입니다. 1부터 ${SERVICE_COUNT} 사이의 번호를 입력해주세요."
                continue
            fi
        else
            # Treat as UUID
            CHC_SERVICE_ID="$SERVICE_SELECTION"

            # UUID format validation
            if [[ ! "$CHC_SERVICE_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
                print_warning "경고: Service ID는 일반적으로 UUID 형식입니다."
                prompt_input "계속하시겠습니까? (yes/no)" "no" CONFIRM_SERVICE_ID
                if [ "$CONFIRM_SERVICE_ID" != "yes" ] && [ "$CONFIRM_SERVICE_ID" != "y" ]; then
                    continue
                fi
            fi
            SERVICE_NAME_FROM_API=""
        fi

        # Verify service exists and get details
        print_info "Service 정보를 조회합니다..."
        SERVICE_URL="https://api.clickhouse.cloud/v1/organizations/${CHC_ORG_ID}/services/${CHC_SERVICE_ID}"
        SERVICE_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$SERVICE_URL" \
            -u "${CHC_API_KEY_ID}:${CHC_API_KEY_SECRET}" \
            -H "Content-Type: application/json" 2>&1)

        SERVICE_HTTP_CODE=$(echo "$SERVICE_RESPONSE" | tail -n1)
        SERVICE_BODY=$(echo "$SERVICE_RESPONSE" | sed '$d')

        if [ "$SERVICE_HTTP_CODE" = "200" ]; then
            # Get service details from API if not already set
            if [ -z "$SERVICE_NAME_FROM_API" ]; then
                SERVICE_NAME_FROM_API=$(echo "$SERVICE_BODY" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | head -n1)
            fi
            SERVICE_REGION=$(echo "$SERVICE_BODY" | grep -o '"region":"[^"]*"' | cut -d'"' -f4 | head -n1)
            SERVICE_TIER=$(echo "$SERVICE_BODY" | grep -o '"tier":"[^"]*"' | cut -d'"' -f4 | head -n1)

            print_success "Service 확인 완료!"
            if [ -n "$SERVICE_NAME_FROM_API" ]; then
                echo "  - Name: ${SERVICE_NAME_FROM_API}"
            fi
            if [ -n "$SERVICE_REGION" ]; then
                echo "  - Region: ${SERVICE_REGION}"
            fi
            if [ -n "$SERVICE_TIER" ]; then
                echo "  - Tier: ${SERVICE_TIER}"
            fi
            echo "  - ID: ${CHC_SERVICE_ID}"

            # Use API service name as SERVICE_NAME
            SERVICE_NAME="${SERVICE_NAME_FROM_API:-default}"
            print_info "서비스 표시 이름이 자동으로 설정되었습니다: ${SERVICE_NAME}"

            break
        elif [ "$SERVICE_HTTP_CODE" = "404" ]; then
            print_error "Service ID를 찾을 수 없습니다. 다시 입력해주세요."
            continue
        else
            print_error "Service 조회 실패 (HTTP ${SERVICE_HTTP_CODE}). 다시 입력해주세요."
            continue
        fi
    done

    echo ""

    # Save credentials to hidden file
    print_info "인증 정보를 안전하게 저장 중..."

    # Ensure CH_HOST doesn't have https:// prefix before saving
    CH_HOST=$(echo "$CH_HOST" | sed -E 's|^https?://||')

    cat > "$CREDENTIALS_FILE" << EOF
# ============================================================================
# CostKeeper Credentials (DO NOT COMMIT TO VERSION CONTROL)
# Generated: $(date)
# ============================================================================

# ClickHouse Cloud Connection (CHC Exclusive - Fixed Values)
CH_HOST=${CH_HOST}
CH_PORT=8443
CH_USER=default
CH_PASSWORD=${CH_PASSWORD}

# CHC API Configuration
CHC_ORG_ID=${CHC_ORG_ID}
CHC_API_KEY_ID=${CHC_API_KEY_ID}
CHC_API_KEY_SECRET=${CHC_API_KEY_SECRET}
CHC_SERVICE_ID=${CHC_SERVICE_ID}
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
# Step 4: Check for existing configuration
# ============================================================================
SKIP_CONFIG=false
if [ -f "$CONFIG_FILE" ]; then
    print_warning "기존 설정 파일이 발견되었습니다."
    prompt_input "기존 설정을 사용하시겠습니까? (yes/no)" "yes" USE_EXISTING_CONFIG

    if [ "$USE_EXISTING_CONFIG" = "yes" ] || [ "$USE_EXISTING_CONFIG" = "y" ]; then
        source "$CONFIG_FILE"
        print_success "기존 설정을 불러왔습니다."
        echo ""
        print_info "현재 설정:"
        echo "  • Database: ${DATABASE_NAME}"
        echo "  • 서비스: ${SERVICE_NAME}"
        echo "  • Alert 임계값: ${ALERT_THRESHOLD_PCT}%, Warning: ${WARNING_THRESHOLD_PCT}%, Critical: ${CRITICAL_THRESHOLD_PCT}%"
        echo "  • 데이터 보관: ${DATA_RETENTION_DAYS}일, Alert: ${ALERT_RETENTION_DAYS}일"
        echo ""
        SKIP_CONFIG=true
    fi
    echo ""
fi

# ============================================================================
# Step 3: Database Configuration
# ============================================================================
if [ "$SKIP_CONFIG" = false ]; then
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Step 3: Database Configuration"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Validate Database Name
    while true; do
        prompt_input "Database 이름" "costkeeper" DATABASE_NAME

        if [ -z "$DATABASE_NAME" ]; then
            print_error "Database 이름을 입력해주세요."
            continue
        fi

        # Check valid database name (alphanumeric and underscore only)
        if [[ ! "$DATABASE_NAME" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
            print_error "Database 이름은 영문자로 시작하고 영문자, 숫자, 밑줄(_)만 사용할 수 있습니다."
            continue
        fi

        print_success "Database: ${DATABASE_NAME}"
        break
    done

    print_info "💡 CPU/메모리 할당 정보는 CHC API에서 자동으로 조회됩니다."
    echo ""

    # ============================================================================
    # Step 6: Alert Configuration
    # ============================================================================
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Step 4: Alert Configuration"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Validate Alert Threshold
    while true; do
        prompt_input "Alert 임계값 (%)" "20.0" ALERT_THRESHOLD_PCT

        if [ -z "$ALERT_THRESHOLD_PCT" ]; then
            print_error "Alert 임계값을 입력해주세요."
            continue
        fi

        # Check if it's a valid number
        if ! [[ "$ALERT_THRESHOLD_PCT" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            print_error "임계값은 숫자여야 합니다 (예: 20 또는 20.0)."
            continue
        fi

        # Check if in valid range (0-100)
        if (( $(echo "$ALERT_THRESHOLD_PCT < 0 || $ALERT_THRESHOLD_PCT > 100" | bc -l) )); then
            print_error "임계값은 0에서 100 사이여야 합니다."
            continue
        fi

        print_success "Alert 임계값: ${ALERT_THRESHOLD_PCT}%"
        break
    done

    # Validate Warning Threshold
    while true; do
        prompt_input "Warning Severity 임계값 (%)" "30.0" WARNING_THRESHOLD_PCT

        if [ -z "$WARNING_THRESHOLD_PCT" ]; then
            print_error "Warning 임계값을 입력해주세요."
            continue
        fi

        # Check if it's a valid number
        if ! [[ "$WARNING_THRESHOLD_PCT" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            print_error "임계값은 숫자여야 합니다 (예: 30 또는 30.0)."
            continue
        fi

        # Check if in valid range (0-100)
        if (( $(echo "$WARNING_THRESHOLD_PCT < 0 || $WARNING_THRESHOLD_PCT > 100" | bc -l) )); then
            print_error "임계값은 0에서 100 사이여야 합니다."
            continue
        fi

        # Check if greater than alert threshold
        if (( $(echo "$WARNING_THRESHOLD_PCT < $ALERT_THRESHOLD_PCT" | bc -l) )); then
            print_warning "경고: Warning 임계값(${WARNING_THRESHOLD_PCT}%)이 Alert 임계값(${ALERT_THRESHOLD_PCT}%)보다 낮습니다."
            prompt_input "계속하시겠습니까? (yes/no)" "no" CONFIRM_WARNING
            if [ "$CONFIRM_WARNING" != "yes" ] && [ "$CONFIRM_WARNING" != "y" ]; then
                continue
            fi
        fi

        print_success "Warning 임계값: ${WARNING_THRESHOLD_PCT}%"
        break
    done

    # Validate Critical Threshold
    while true; do
        prompt_input "Critical Severity 임계값 (%)" "50.0" CRITICAL_THRESHOLD_PCT

        if [ -z "$CRITICAL_THRESHOLD_PCT" ]; then
            print_error "Critical 임계값을 입력해주세요."
            continue
        fi

        # Check if it's a valid number
        if ! [[ "$CRITICAL_THRESHOLD_PCT" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            print_error "임계값은 숫자여야 합니다 (예: 50 또는 50.0)."
            continue
        fi

        # Check if in valid range (0-100)
        if (( $(echo "$CRITICAL_THRESHOLD_PCT < 0 || $CRITICAL_THRESHOLD_PCT > 100" | bc -l) )); then
            print_error "임계값은 0에서 100 사이여야 합니다."
            continue
        fi

        # Check if greater than warning threshold
        if (( $(echo "$CRITICAL_THRESHOLD_PCT < $WARNING_THRESHOLD_PCT" | bc -l) )); then
            print_warning "경고: Critical 임계값(${CRITICAL_THRESHOLD_PCT}%)이 Warning 임계값(${WARNING_THRESHOLD_PCT}%)보다 낮습니다."
            prompt_input "계속하시겠습니까? (yes/no)" "no" CONFIRM_CRITICAL
            if [ "$CONFIRM_CRITICAL" != "yes" ] && [ "$CONFIRM_CRITICAL" != "y" ]; then
                continue
            fi
        fi

        print_success "Critical 임계값: ${CRITICAL_THRESHOLD_PCT}%"
        break
    done

    echo ""

    # ============================================================================
    # Step 7: Data Retention Configuration
    # ============================================================================
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Step 5: Data Retention Configuration"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Validate Data Retention Days
    while true; do
        prompt_input "분석 데이터 보관 기간 (일)" "365" DATA_RETENTION_DAYS

        if [ -z "$DATA_RETENTION_DAYS" ]; then
            print_error "데이터 보관 기간을 입력해주세요."
            continue
        fi

        # Check if it's a valid integer
        if ! [[ "$DATA_RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
            print_error "보관 기간은 정수여야 합니다 (예: 365)."
            continue
        fi

        # Check if positive
        if [ "$DATA_RETENTION_DAYS" -le 0 ]; then
            print_error "보관 기간은 0보다 커야 합니다."
            continue
        fi

        # Warning for very short retention
        if [ "$DATA_RETENTION_DAYS" -lt 30 ]; then
            print_warning "경고: 보관 기간이 30일 미만입니다. 데이터 분석에 충분하지 않을 수 있습니다."
            prompt_input "계속하시겠습니까? (yes/no)" "no" CONFIRM_DATA_RETENTION
            if [ "$CONFIRM_DATA_RETENTION" != "yes" ] && [ "$CONFIRM_DATA_RETENTION" != "y" ]; then
                continue
            fi
        fi

        print_success "데이터 보관 기간: ${DATA_RETENTION_DAYS}일"
        break
    done

    # Validate Alert Retention Days
    while true; do
        prompt_input "Alert 데이터 보관 기간 (일)" "90" ALERT_RETENTION_DAYS

        if [ -z "$ALERT_RETENTION_DAYS" ]; then
            print_error "Alert 보관 기간을 입력해주세요."
            continue
        fi

        # Check if it's a valid integer
        if ! [[ "$ALERT_RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
            print_error "보관 기간은 정수여야 합니다 (예: 90)."
            continue
        fi

        # Check if positive
        if [ "$ALERT_RETENTION_DAYS" -le 0 ]; then
            print_error "보관 기간은 0보다 커야 합니다."
            continue
        fi

        # Warning for very short retention
        if [ "$ALERT_RETENTION_DAYS" -lt 7 ]; then
            print_warning "경고: Alert 보관 기간이 7일 미만입니다. Alert 이력 추적이 어려울 수 있습니다."
            prompt_input "계속하시겠습니까? (yes/no)" "no" CONFIRM_ALERT_RETENTION
            if [ "$CONFIRM_ALERT_RETENTION" != "yes" ] && [ "$CONFIRM_ALERT_RETENTION" != "y" ]; then
                continue
            fi
        fi

        print_success "Alert 보관 기간: ${ALERT_RETENTION_DAYS}일"
        break
    done

    echo ""
fi

# ============================================================================
# Step 8: Generate Configuration File
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
# Step 9: Generate SQL Script
# ============================================================================
print_info "SQL 스크립트 생성 중..."

SQL_FILE="${SCRIPT_DIR}/costkeeper-setup.sql"

# Load credentials for API access in SQL
source "$CREDENTIALS_FILE"

# Replace variables in SQL template
sed -e "s/\${DATABASE_NAME}/${DATABASE_NAME}/g" \
    -e "s/\${SERVICE_NAME}/${SERVICE_NAME}/g" \
    -e "s/\${CHC_ORG_ID}/${CHC_ORG_ID}/g" \
    -e "s/\${CHC_SERVICE_ID}/${CHC_SERVICE_ID}/g" \
    -e "s|\${CHC_API_KEY_ID}|${CHC_API_KEY_ID}|g" \
    -e "s|\${CHC_API_KEY_SECRET}|${CHC_API_KEY_SECRET}|g" \
    -e "s/\${ALERT_THRESHOLD_PCT}/${ALERT_THRESHOLD_PCT}/g" \
    -e "s/\${WARNING_THRESHOLD_PCT}/${WARNING_THRESHOLD_PCT}/g" \
    -e "s/\${CRITICAL_THRESHOLD_PCT}/${CRITICAL_THRESHOLD_PCT}/g" \
    -e "s/\${DATA_RETENTION_DAYS}/${DATA_RETENTION_DAYS}/g" \
    -e "s/\${ALERT_RETENTION_DAYS}/${ALERT_RETENTION_DAYS}/g" \
    "${SCRIPT_DIR}/costkeeper-template.sql" > "$SQL_FILE"

print_success "SQL 스크립트 생성 완료: $SQL_FILE"
echo ""

# ============================================================================
# Step 10: Test Connection
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 7: Connection Test"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Load credentials for connection test (in case they were loaded at the beginning)
if [ -f "$CREDENTIALS_FILE" ]; then
    source "$CREDENTIALS_FILE"
fi

# Check if clickhouse client is available
if [ -z "$CLICKHOUSE_CLIENT_CMD" ]; then
    print_warning "clickhouse client가 설치되어 있지 않습니다."
    echo ""
    print_info "clickhouse client는 CostKeeper 설치에 필요합니다."
    print_info "설치 방법: https://clickhouse.com/docs/en/install"
    echo ""
    prompt_input "지금 설치하시겠습니까? (yes/no)" "yes" INSTALL_CLIENT

    if [ "$INSTALL_CLIENT" = "yes" ] || [ "$INSTALL_CLIENT" = "y" ]; then
        print_info "clickhouse client 설치 중..."

        # Detect OS and install
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS - Check if already installed via Homebrew
            if brew list clickhouse &> /dev/null; then
                print_info "clickhouse는 이미 Homebrew로 설치되어 있습니다."
                ALREADY_INSTALLED=true
            else
                if command -v brew &> /dev/null; then
                    brew install clickhouse
                    ALREADY_INSTALLED=false
                else
                    print_error "Homebrew가 설치되어 있지 않습니다."
                    print_error "다음 명령어로 설치하세요: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                    exit 1
                fi
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            # Linux
            curl https://clickhouse.com/ | sh
            ALREADY_INSTALLED=false
        else
            print_error "지원되지 않는 운영체제입니다."
            print_error "https://clickhouse.com/docs/en/install 에서 직접 설치해주세요."
            exit 1
        fi

        # Re-detect clickhouse client command after installation
        # Clear command hash to detect newly installed binaries
        hash -r 2>/dev/null || true

        # Try multiple detection methods for better reliability
        if command -v clickhouse-client &> /dev/null || which clickhouse-client &> /dev/null; then
            CLICKHOUSE_CLIENT_CMD="clickhouse-client"
            print_success "clickhouse client 준비 완료! (명령어: clickhouse-client)"
        elif command -v clickhouse &> /dev/null || which clickhouse &> /dev/null; then
            # For macOS Homebrew installation, 'clickhouse client' subcommand is used
            # Skip version test to avoid Gatekeeper issues - if binary exists, assume it works
            CLICKHOUSE_CLIENT_CMD="clickhouse client"
            print_success "clickhouse client 준비 완료! (명령어: clickhouse client)"
        else
            print_error "clickhouse client를 찾을 수 없습니다."
            if [ "$ALREADY_INSTALLED" = true ]; then
                print_error "Homebrew로 설치되어 있지만 PATH에서 찾을 수 없습니다."
                print_error "터미널을 재시작하거나 다음 명령어를 실행해보세요:"
                print_error "  hash -r"
            fi
            exit 1
        fi
    else
        print_error "clickhouse client가 없으면 CostKeeper를 설치할 수 없습니다."
        print_error "설치 후 다시 실행해주세요."
        exit 1
    fi

    echo ""
fi

# Build clickhouse client command with proper quoting
build_ch_client_cmd() {
    local cmd="${CLICKHOUSE_CLIENT_CMD}"
    cmd+=" --host=${CH_HOST}"
    # Note: --port is NOT specified when using --secure
    # The --secure flag automatically uses the correct HTTPS port (9440)
    cmd+=" --user=${CH_USER}"
    cmd+=" --password=${CH_PASSWORD}"
    cmd+=" --secure"
    echo "$cmd"
}

CH_CLIENT_FULL_CMD=$(build_ch_client_cmd)

# Test connection
print_info "ClickHouse Cloud 연결 테스트 중..."
print_info "사용 명령어: ${CLICKHOUSE_CLIENT_CMD}"
if eval "$CH_CLIENT_FULL_CMD --query='SELECT version()'" > /dev/null 2>&1; then
    print_success "연결 테스트 성공!"
else
    print_error "연결 테스트 실패. 연결 정보를 확인해주세요."
    print_error "디버깅 정보:"
    echo "  - Host: ${CH_HOST}"
    echo "  - Port: ${CH_PORT}"
    echo "  - User: ${CH_USER}"
    echo "  - Command: ${CLICKHOUSE_CLIENT_CMD}"
    exit 1
fi

echo ""

# ============================================================================
# Step 11: Create Database
# ============================================================================
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Step 8: Database Creation"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create database
print_info "Database '${DATABASE_NAME}' 생성 중..."
if eval "$CH_CLIENT_FULL_CMD --query=\"CREATE DATABASE IF NOT EXISTS ${DATABASE_NAME}\""; then
    print_success "Database 생성 완료"
else
    print_error "Database 생성 실패"
    exit 1
fi

echo ""

# ============================================================================
# Step 12: Execute SQL Script
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
    if eval "$CH_CLIENT_FULL_CMD --multiquery < ${SQL_FILE}"; then
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
    echo "  ${CLICKHOUSE_CLIENT_CMD} --host=\${CH_HOST} --port=\${CH_PORT} \\"
    echo "    --user=\${CH_USER} --password=\${CH_PASSWORD} --secure \\"
    echo "    --multiquery < ${SQL_FILE}"
    echo ""
    exit 0
fi

echo ""

# ============================================================================
# Step 13: Verification
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
RMV_COUNT=$(eval "$CH_CLIENT_FULL_CMD --query=\"SELECT count() FROM system.view_refreshes WHERE database = '${DATABASE_NAME}'\" 2>/dev/null || echo 0")

if [ "$RMV_COUNT" -gt 0 ]; then
    print_success "RMV 확인: ${RMV_COUNT}개 RMV 발견"

    # Show RMV status
    echo ""
    print_info "RMV 상태:"
    eval "$CH_CLIENT_FULL_CMD --query=\"SELECT view, status, next_refresh_time FROM system.view_refreshes WHERE database = '${DATABASE_NAME}' FORMAT PrettyCompact\""
else
    print_warning "RMV가 발견되지 않았습니다."
fi

echo ""

# ============================================================================
# Step 14: Summary
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
echo "  • ClickHouse 접속: ${CLICKHOUSE_CLIENT_CMD} --host=\${CH_HOST} --port=\${CH_PORT} --user=\${CH_USER} --password=\${CH_PASSWORD} --secure"
echo ""
