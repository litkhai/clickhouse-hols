# ClickHouse MCP Server

[English](#english) | [한국어](#한국어)

---

## English

Python-based MCP (Model Context Protocol) server for ClickHouse database integration.

## Quick Start

1. Create environment file:
```bash
cp .env.example .env
# Edit .env with your ClickHouse connection details
```

2. Build and start the server:
```bash
docker-compose up -d --build
```

3. Check status:
```bash
docker-compose ps
docker-compose logs -f
```

4. Test health endpoint:
```bash
curl http://localhost:3001/health
```

## Configuration

Environment variables in `.env` file:

- `CLICKHOUSE_HOST`: ClickHouse server host (default: `clickhouse-latest` for local Docker setup)
- `CLICKHOUSE_PORT`: ClickHouse HTTP port (default: 8123)
- `CLICKHOUSE_USER`: Database user (default: default)
- `CLICKHOUSE_PASSWORD`: User password (default: empty)
- `CLICKHOUSE_DATABASE`: Default database (default: default)
- `CLICKHOUSE_SECURE`: Use HTTPS (default: false)

**Note**: The MCP server connects to the local ClickHouse Docker container (`clickhouse-latest`) via the `clickhouse-network`. Make sure the ClickHouse container is running before starting the MCP server.

## Usage with LibreChat

This MCP server can be integrated with LibreChat to provide ClickHouse query capabilities to AI assistants.

1. Ensure this server is running on port 3001
2. Configure LibreChat to connect to `http://mcp-clickhouse-server:3001`
3. LibreChat will be able to query ClickHouse through the MCP protocol

## Tools Available

- **query**: Execute SELECT queries
- **list_databases**: List all databases
- **list_tables**: List tables in a database
- **describe_table**: Get table schema
- **execute**: Run DDL/DML statements (with safety checks)

## Stopping

```bash
docker-compose down
```

## Troubleshooting

### Container keeps restarting
Check logs:
```bash
docker-compose logs mcp-clickhouse
```

### Can't connect to ClickHouse
- Verify ClickHouse is running: `docker ps | grep clickhouse`
- Check ClickHouse port: `curl http://localhost:8123/ping`
- Verify connection settings in `.env`

### Health check failing
Wait 10-15 seconds after startup for the server to initialize.

---

## 한국어

ClickHouse 데이터베이스 통합을 위한 Python 기반 MCP (Model Context Protocol) 서버입니다.

## 빠른 시작

1. 환경 파일 생성:
```bash
cp .env.example .env
# ClickHouse 연결 정보로 .env 편집
```

2. 서버 빌드 및 시작:
```bash
docker-compose up -d --build
```

3. 상태 확인:
```bash
docker-compose ps
docker-compose logs -f
```

4. 헬스 엔드포인트 테스트:
```bash
curl http://localhost:3001/health
```

## 설정

`.env` 파일의 환경 변수:

- `CLICKHOUSE_HOST`: ClickHouse 서버 호스트 (기본값: 로컬 Docker 설정의 경우 `clickhouse-latest`)
- `CLICKHOUSE_PORT`: ClickHouse HTTP 포트 (기본값: 8123)
- `CLICKHOUSE_USER`: 데이터베이스 사용자 (기본값: default)
- `CLICKHOUSE_PASSWORD`: 사용자 비밀번호 (기본값: 비어있음)
- `CLICKHOUSE_DATABASE`: 기본 데이터베이스 (기본값: default)
- `CLICKHOUSE_SECURE`: HTTPS 사용 (기본값: false)

**참고**: MCP 서버는 `clickhouse-network`를 통해 로컬 ClickHouse Docker 컨테이너(`clickhouse-latest`)에 연결됩니다. MCP 서버를 시작하기 전에 ClickHouse 컨테이너가 실행 중인지 확인하세요.

## LibreChat과 함께 사용

이 MCP 서버는 LibreChat과 통합하여 AI 어시스턴트에 ClickHouse 쿼리 기능을 제공할 수 있습니다.

1. 이 서버가 포트 3001에서 실행 중인지 확인
2. `http://mcp-clickhouse-server:3001`에 연결하도록 LibreChat 설정
3. LibreChat이 MCP 프로토콜을 통해 ClickHouse를 쿼리할 수 있게 됨

## 사용 가능한 도구

- **query**: SELECT 쿼리 실행
- **list_databases**: 모든 데이터베이스 목록 조회
- **list_tables**: 데이터베이스의 테이블 목록 조회
- **describe_table**: 테이블 스키마 조회
- **execute**: DDL/DML 문 실행 (안전성 검사 포함)

## 중지

```bash
docker-compose down
```

## 문제 해결

### 컨테이너가 계속 재시작됨
로그 확인:
```bash
docker-compose logs mcp-clickhouse
```

### ClickHouse에 연결할 수 없음
- ClickHouse 실행 확인: `docker ps | grep clickhouse`
- ClickHouse 포트 확인: `curl http://localhost:8123/ping`
- `.env`의 연결 설정 확인

### 헬스 체크 실패
서버 초기화를 위해 시작 후 10-15초 대기하세요.
