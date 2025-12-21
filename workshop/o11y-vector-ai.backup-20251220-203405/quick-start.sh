#!/bin/bash
set -e

echo "=========================================="
echo "O11y Vector AI - Quick Start"
echo "=========================================="
echo ""

# Check if .env exists
if [ -f .env ]; then
    echo "⚠️  .env 파일이 이미 존재합니다."
    read -p "기존 파일을 덮어쓰시겠습니까? (y/N): " overwrite
    if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
        echo "종료합니다."
        exit 0
    fi
fi

echo "ClickHouse Cloud 연결 정보를 입력해주세요."
echo ""

# Collect ClickHouse info
read -p "ClickHouse Host (예: abc123.us-east-1.aws.clickhouse.cloud): " CH_HOST
read -p "ClickHouse User [default]: " CH_USER
CH_USER=${CH_USER:-default}
read -sp "ClickHouse Password: " CH_PASSWORD
echo ""
read -p "ClickHouse Database [o11y]: " CH_DB
CH_DB=${CH_DB:-o11y}

echo ""
echo "=========================================="
echo "연결 테스트 중..."
echo "=========================================="

# Test connection
if command -v clickhouse &> /dev/null; then
    echo "ClickHouse 연결을 테스트합니다..."
    if clickhouse client \
        --host="$CH_HOST" \
        --port=8443 \
        --user="$CH_USER" \
        --password="$CH_PASSWORD" \
        --secure \
        --query="SELECT 1" &> /dev/null; then
        echo "✅ ClickHouse 연결 성공!"
    else
        echo "❌ ClickHouse 연결 실패!"
        echo "설정을 확인하고 다시 시도해주세요."
        exit 1
    fi
else
    echo "⚠️  clickhouse가 설치되어 있지 않습니다."
    echo "연결 테스트를 건너뜁니다."
fi

echo ""
echo "=========================================="
echo ".env 파일 생성 중..."
echo "=========================================="

# Create .env file
cat > .env << EOF
# ClickHouse Cloud Configuration
CLICKHOUSE_HOST=$CH_HOST
CLICKHOUSE_PORT=8443
CLICKHOUSE_USER=$CH_USER
CLICKHOUSE_PASSWORD=$CH_PASSWORD
CLICKHOUSE_DB=$CH_DB
CLICKHOUSE_SECURE=true

# Service Configuration
SAMPLE_APP_PORT=8000
OTEL_COLLECTOR_GRPC_PORT=4317
OTEL_COLLECTOR_HTTP_PORT=4318
EOF

chmod 600 .env
echo "✅ .env 파일이 생성되었습니다."

echo ""
echo "=========================================="
echo "다음 단계:"
echo "=========================================="
echo ""
echo "1. ClickHouse 스키마 생성:"
echo "   cd scripts && ./setup-clickhouse.sh"
echo ""
echo "2. 서비스 시작:"
echo "   cd .. && docker-compose up -d"
echo ""
echo "3. 로그 확인:"
echo "   docker-compose logs -f"
echo ""
echo "4. 서비스 접속:"
echo "   - Sample App: http://localhost:8000"
echo "   - Sample App Docs: http://localhost:8000/docs"
echo ""
echo "모든 단계를 자동으로 실행하려면 다음을 실행하세요:"
echo "   ./scripts/deploy.sh"
echo ""
