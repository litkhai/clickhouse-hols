#!/bin/bash

echo "🔌 ClickHouse 클라이언트 접속"
echo "============================"

# 컨테이너 상태 확인
if ! docker ps --format '{{.Names}}' | grep -q '^clickhouse-oss$'; then
    echo "❌ ClickHouse가 실행되지 않고 있습니다."
    echo "   시작하려면: ./start.sh"
    exit 1
fi

# 서비스 상태 확인
if ! curl -s http://localhost:8123/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse 서비스가 응답하지 않습니다."
    echo "   상태 확인: ./status.sh"
    exit 1
fi

echo "✅ 연결 중..."
echo "   종료하려면: exit 입력 또는 Ctrl+D"
echo ""

# 클라이언트 접속
docker-compose exec clickhouse clickhouse-client
