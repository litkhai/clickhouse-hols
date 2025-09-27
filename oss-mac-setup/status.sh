#!/bin/bash

echo "📊 ClickHouse 상태"
echo "=================="

# 컨테이너 상태
echo "🐳 컨테이너 상태:"
if docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep clickhouse-oss; then
    echo ""
else
    echo "❌ ClickHouse 컨테이너가 실행되지 않고 있습니다."
    echo "   시작하려면: ./start.sh"
    echo ""
    exit 1
fi

# 서비스 헬스체크
echo "💓 서비스 상태:"
if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
    echo "✅ HTTP Interface: 정상 (포트 8123)"
    
    # 버전 정보
    VERSION=$(curl -s http://localhost:8123/ 2>/dev/null | grep -o 'ClickHouse server version [0-9.]*' | head -1)
    if [ -n "$VERSION" ]; then
        echo "✅ $VERSION"
    fi
else
    echo "❌ HTTP Interface: 연결 실패 (포트 8123)"
fi

# TCP 포트 확인
if nc -z localhost 9000 2>/dev/null; then
    echo "✅ TCP Interface: 정상 (포트 9000)"
else
    echo "❌ TCP Interface: 연결 실패 (포트 9000)"
fi

echo ""

# 리소스 사용량
echo "💾 리소스 사용량:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" clickhouse-oss 2>/dev/null

echo ""

# 볼륨 정보
echo "💿 데이터 볼륨:"
docker volume ls | grep clickhouse || echo "볼륨 정보를 찾을 수 없습니다."

echo ""
echo "🔧 관리 명령어:"
echo "   ./start.sh     - ClickHouse 시작"
echo "   ./stop.sh      - ClickHouse 중지"
echo "   ./client.sh    - CLI 클라이언트 접속"
echo "   docker-compose logs -f  - 실시간 로그 확인"
