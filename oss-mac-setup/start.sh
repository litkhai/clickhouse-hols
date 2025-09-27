#!/bin/bash

echo "🚀 ClickHouse 시작 중..."
echo "========================"

# 기존 컨테이너가 있다면 정리
if docker ps -a --format '{{.Names}}' | grep -q '^clickhouse-oss$'; then
    echo "🔄 기존 컨테이너 정리 중..."
    docker-compose down
fi

# ClickHouse 시작
echo "▶️  ClickHouse 컨테이너 시작..."
docker-compose up -d

# 초기화 대기
echo "⏳ ClickHouse 초기화 대기 중..."
echo "   (최대 45초 소요)"

# 상태 확인 (최대 45초 대기)
for i in {1..45}; do
    if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
        echo ""
        echo "✅ ClickHouse 시작 완료!"
        break
    fi
    
    if [ $i -eq 45 ]; then
        echo ""
        echo "⚠️  시작 시간이 오래 걸리고 있습니다. 로그를 확인하세요:"
        echo "   docker-compose logs clickhouse"
        exit 1
    fi
    
    echo -ne "\r   대기 중... ${i}초"
    sleep 1
done

echo ""
echo "🎯 접속 정보:"
echo "   📍 웹 UI: http://localhost:8123/play"
echo "   📍 HTTP API: http://localhost:8123"
echo "   📍 TCP: localhost:9000"
echo "   👤 사용자: default (비밀번호 없음)"
echo ""
echo "🔧 관리 명령어:"
echo "   ./stop.sh      - ClickHouse 중지"
echo "   ./status.sh    - 상태 확인"
echo "   ./client.sh    - CLI 클라이언트 접속"
echo ""
echo "✨ ClickHouse가 준비되었습니다!"
