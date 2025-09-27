#!/bin/bash

# ClickHouse OSS 환경 초기 설정 스크립트
# 사용법: ./setup.sh

set -e

BASE_DIR="/Users/kenlee/clickhouse/oss"
SCRIPT_NAME="ClickHouse OSS Setup"

echo "🚀 $SCRIPT_NAME"
echo "=================================="
echo "📍 Installation directory: $BASE_DIR"
echo ""

# Docker 환경 확인
echo "🐳 Docker 환경 확인..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker가 설치되지 않았습니다!"
    echo "   https://docs.docker.com/get-docker/ 에서 설치하세요."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Docker가 실행되지 않고 있습니다!"
    echo "   Docker Desktop을 시작하세요."
    exit 1
fi

echo "✅ Docker 환경 확인 완료"

# 디렉토리 생성
echo "📁 디렉토리 생성..."
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

# docker-compose.yml 생성 (Named Volume 사용)
echo "📝 Docker Compose 설정 생성..."
cat > docker-compose.yml << 'EOF'
services:
  clickhouse:
    image: clickhouse/clickhouse-server:24.8
    container_name: clickhouse-oss
    hostname: clickhouse
    ports:
      - "8123:8123"  # HTTP Interface
      - "9000:9000"  # TCP Interface
    volumes:
      # Named volume 사용 (macOS 권한 문제 해결)
      - clickhouse_data:/var/lib/clickhouse
      - clickhouse_logs:/var/log/clickhouse-server
    environment:
      CLICKHOUSE_DB: default
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: ""
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8123/ping"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 30s
    ulimits:
      nofile:
        soft: 262144
        hard: 262144

volumes:
  clickhouse_data:
    driver: local
  clickhouse_logs:
    driver: local

networks:
  default:
    name: clickhouse-network
    driver: bridge
EOF

# .env 파일 생성
echo "📝 환경 변수 파일 생성..."
cat > .env << 'EOF'
# ClickHouse 설정
CLICKHOUSE_DB=default
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=

# Docker Compose 설정
COMPOSE_PROJECT_NAME=clickhouse-oss
EOF

# start.sh 스크립트 생성
echo "📝 시작 스크립트 생성..."
cat > start.sh << 'EOF'
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
EOF

# stop.sh 스크립트 생성
echo "📝 중지 스크립트 생성..."
cat > stop.sh << 'EOF'
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
EOF

# status.sh 스크립트 생성
echo "📝 상태 확인 스크립트 생성..."
cat > status.sh << 'EOF'
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
EOF

# client.sh 스크립트 생성
echo "📝 클라이언트 접속 스크립트 생성..."
cat > client.sh << 'EOF'
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
EOF

# cleanup.sh 스크립트 생성 (데이터 완전 삭제용)
echo "📝 정리 스크립트 생성..."
cat > cleanup.sh << 'EOF'
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
EOF

# README.md 생성
echo "📝 문서 생성..."
cat > README.md << 'EOF'
# ClickHouse OSS Environment

macOS에 최적화된 ClickHouse 개발 환경입니다.

## 🚀 빠른 시작

```bash
# 1. 설정 (최초 1회만)
./setup.sh

# 2. 시작
./start.sh

# 3. 접속
./client.sh
```

## 📍 접속 정보

- **웹 UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **사용자**: default (비밀번호 없음)

## 🛠 관리 스크립트

- `./setup.sh` - 초기 환경 설정 (최초 1회)
- `./start.sh` - ClickHouse 시작
- `./stop.sh` - ClickHouse 중지  
- `./status.sh` - 상태 확인
- `./client.sh` - CLI 클라이언트 접속
- `./cleanup.sh` - 완전 데이터 삭제

## 🔧 고급 사용법

```bash
# 실시간 로그 확인
docker-compose logs -f

# 직접 SQL 실행
docker-compose exec clickhouse clickhouse-client --query "SHOW DATABASES"

# 컨테이너 내부 접속
docker-compose exec clickhouse bash
```

## 📂 데이터 저장

데이터는 Docker Named Volume에 저장되어 영구 보존됩니다:
- `clickhouse-oss_clickhouse_data` - 데이터베이스 파일
- `clickhouse-oss_clickhouse_logs` - 로그 파일

## 🔄 업데이트

```bash
# 새 버전으로 업데이트
docker-compose pull
docker-compose up -d
```
EOF

# 스크립트 실행 권한 부여
echo "🔐 실행 권한 설정..."
chmod +x *.sh

# Docker 이미지 다운로드
echo "📥 ClickHouse 이미지 다운로드..."
docker pull clickhouse/clickhouse-server:24.8

echo ""
echo "✅ ClickHouse OSS 환경 설정 완료!"
echo ""
echo "🎯 다음 단계:"
echo "   1. ClickHouse 시작: ./start.sh"
echo "   2. 웹 UI 접속: http://localhost:8123/play"
echo "   3. CLI 접속: ./client.sh"
echo ""
echo "📖 자세한 사용법은 README.md를 참고하세요."
