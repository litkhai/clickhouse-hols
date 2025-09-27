#!/bin/bash

echo "🧹 ClickHouse 완전 정리"
echo "======================"
echo ""
echo "⚠️  경고: 이 작업은 모든 ClickHouse 데이터를 삭제합니다!"
echo "   - 모든 데이터베이스"
echo "   - 모든 테이블"
echo "   - 모든 로그"
echo ""

read -p "정말로 모든 데이터를 삭제하시겠습니까? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ 정리 작업이 취소되었습니다."
    exit 1
fi

echo "🛑 컨테이너 중지 및 제거..."
docker-compose down -v

echo "🗑️  Docker 볼륨 제거..."
docker volume rm clickhouse-oss_clickhouse_data 2>/dev/null || true
docker volume rm clickhouse-oss_clickhouse_logs 2>/dev/null || true

echo "🧹 네트워크 정리..."
docker network rm clickhouse-network 2>/dev/null || true

echo "✅ 정리 완료!"
echo ""
echo "🔄 다시 시작하려면: ./start.sh"
