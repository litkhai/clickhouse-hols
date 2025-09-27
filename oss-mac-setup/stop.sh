#!/bin/bash

echo "🛑 ClickHouse 중지 중..."
echo "======================="

# Docker Compose로 중지
if [ -f "docker-compose.yml" ]; then
    echo "▶️  Docker Compose로 중지..."
    docker-compose down
else
    echo "▶️  직접 컨테이너 중지..."
    docker stop clickhouse-oss 2>/dev/null || true
    docker rm clickhouse-oss 2>/dev/null || true
fi

# 상태 확인
if docker ps --format '{{.Names}}' | grep -q '^clickhouse-oss$'; then
    echo "⚠️  컨테이너가 여전히 실행 중입니다."
    echo "   강제 중지: docker kill clickhouse-oss"
else
    echo "✅ ClickHouse가 성공적으로 중지되었습니다."
fi

echo ""
echo "🔧 다시 시작하려면: ./start.sh"
