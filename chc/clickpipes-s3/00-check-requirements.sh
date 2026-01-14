#!/bin/bash

echo "=================================================="
echo "ClickPipes S3 Test - Requirements Check"
echo "=================================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check function
check_command() {
    local cmd=$1
    local name=$2
    local install_hint=$3

    if command -v "$cmd" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $name is installed"
        if [ "$cmd" = "clickhouse-client" ]; then
            VERSION=$($cmd --version 2>&1 | head -n 1)
            echo "  Version: $VERSION"
        elif [ "$cmd" = "aws" ]; then
            VERSION=$($cmd --version 2>&1)
            echo "  Version: $VERSION"
        elif [ "$cmd" = "jq" ]; then
            VERSION=$($cmd --version 2>&1)
            echo "  Version: $VERSION"
        fi
        return 0
    else
        echo -e "${RED}✗${NC} $name is NOT installed"
        echo -e "  ${YELLOW}Install:${NC} $install_hint"
        return 1
    fi
}

MISSING=0

echo ""
echo "Checking required tools..."
echo ""

# Check AWS CLI
check_command "aws" "AWS CLI" "curl 'https://awscli.amazonaws.com/AWSCLIV2.pkg' -o 'AWSCLIV2.pkg' && sudo installer -pkg AWSCLIV2.pkg -target /"
[ $? -ne 0 ] && MISSING=$((MISSING + 1))

# Check ClickHouse Client
check_command "clickhouse-client" "ClickHouse Client" "brew install clickhouse (macOS) or curl https://clickhouse.com/ | sh (Linux)"
[ $? -ne 0 ] && MISSING=$((MISSING + 1))

# Check jq
check_command "jq" "jq (JSON processor)" "brew install jq (macOS) or apt-get install jq (Linux)"
[ $? -ne 0 ] && MISSING=$((MISSING + 1))

# Check curl
check_command "curl" "curl" "Should be pre-installed"
[ $? -ne 0 ] && MISSING=$((MISSING + 1))

echo ""
echo "Checking configuration..."
echo ""

# Check .env file
if [ -f .env ]; then
    echo -e "${GREEN}✓${NC} .env file exists"

    # Load and check required variables
    export $(grep -v '^#' .env | xargs)

    REQUIRED_VARS=(
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
        "AWS_REGION"
        "AWS_S3_BUCKET"
        "CHC_ORGANIZATION_ID"
        "CHC_SERVICE_ID"
        "CHC_API_KEY"
        "CHC_HOST"
        "CHC_USER"
        "CHC_PASSWORD"
    )

    echo ""
    echo "Checking required environment variables..."
    for VAR in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!VAR}" ]; then
            echo -e "  ${RED}✗${NC} $VAR is not set"
            MISSING=$((MISSING + 1))
        else
            # Mask sensitive values
            if [[ "$VAR" == *"KEY"* ]] || [[ "$VAR" == *"PASSWORD"* ]] || [[ "$VAR" == *"TOKEN"* ]]; then
                echo -e "  ${GREEN}✓${NC} $VAR = ****"
            else
                echo -e "  ${GREEN}✓${NC} $VAR = ${!VAR}"
            fi
        fi
    done
else
    echo -e "${RED}✗${NC} .env file NOT found"
    echo -e "  ${YELLOW}Create it:${NC} cp .env.template .env"
    echo -e "  ${YELLOW}Then edit:${NC} nano .env"
    MISSING=$((MISSING + 1))
fi

echo ""
echo "Testing connectivity..."
echo ""

# Test AWS credentials
if [ -n "$AWS_ACCESS_KEY_ID" ]; then
    echo -n "Testing AWS credentials... "
    if aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
        echo -e "${GREEN}✓${NC} AWS credentials valid"

        # Check S3 bucket access
        echo -n "Testing S3 bucket access... "
        if aws s3 ls "s3://${AWS_S3_BUCKET}" --region "$AWS_REGION" &> /dev/null; then
            echo -e "${GREEN}✓${NC} S3 bucket accessible"
        else
            echo -e "${RED}✗${NC} Cannot access S3 bucket"
            echo "  Check bucket name and permissions"
            MISSING=$((MISSING + 1))
        fi
    else
        echo -e "${RED}✗${NC} AWS credentials invalid"
        MISSING=$((MISSING + 1))
    fi
else
    echo -e "${YELLOW}⊘${NC} Skipping AWS test (credentials not set)"
fi

# Test ClickHouse connection
if [ -n "$CHC_HOST" ] && [ -n "$CHC_USER" ] && [ -n "$CHC_PASSWORD" ]; then
    echo -n "Testing ClickHouse connection... "
    if clickhouse-client \
        --host="$CHC_HOST" \
        --user="$CHC_USER" \
        --password="$CHC_PASSWORD" \
        --secure \
        --query="SELECT 1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} ClickHouse connection successful"
    else
        echo -e "${RED}✗${NC} ClickHouse connection failed"
        echo "  Check host, user, and password"
        MISSING=$((MISSING + 1))
    fi
else
    echo -e "${YELLOW}⊘${NC} Skipping ClickHouse test (credentials not set)"
fi

# Test ClickPipes API
if [ -n "$CHC_ORGANIZATION_ID" ] && [ -n "$CHC_SERVICE_ID" ] && [ -n "$CHC_API_KEY" ]; then
    echo -n "Testing ClickPipes API access... "
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "https://api.clickhouse.cloud/v1/organizations/${CHC_ORGANIZATION_ID}/services/${CHC_SERVICE_ID}/clickpipes" \
        -H "Authorization: Bearer ${CHC_API_KEY}")

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then
        echo -e "${GREEN}✓${NC} ClickPipes API accessible (HTTP $HTTP_CODE)"
    else
        echo -e "${RED}✗${NC} ClickPipes API failed (HTTP $HTTP_CODE)"
        echo "  Check Organization ID, Service ID, and API Key"
        MISSING=$((MISSING + 1))
    fi
else
    echo -e "${YELLOW}⊘${NC} Skipping ClickPipes API test (credentials not set)"
fi

echo ""
echo "=================================================="

if [ $MISSING -eq 0 ]; then
    echo -e "${GREEN}✅ All requirements satisfied!${NC}"
    echo ""
    echo "You're ready to run the test:"
    echo "  ./run-full-test.sh"
    exit 0
else
    echo -e "${RED}❌ $MISSING requirement(s) missing or failed${NC}"
    echo ""
    echo "Please fix the issues above before running the test."
    echo ""
    echo "Quick fixes:"
    echo "  1. Install missing tools"
    echo "  2. Create and configure .env file: cp .env.template .env"
    echo "  3. Verify AWS and ClickHouse credentials"
    exit 1
fi
