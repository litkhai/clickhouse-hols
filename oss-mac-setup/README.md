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
