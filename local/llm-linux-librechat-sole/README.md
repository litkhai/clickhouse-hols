# LibreChat Standalone (Linux Edition)

**Ollama를 사용한 독립형 LibreChat 배포**

이 프로젝트는 LibreChat과 MongoDB만 포함된 경량 배포 버전입니다. MCP 서버는 사용자가 별도로 구성할 수 있습니다.

## 주요 특징

- ✅ **경량 배포**: LibreChat + MongoDB만 포함
- ✅ **Ollama 통합**: llama3.1:8b 모델 사용 (최고의 tool calling 성능)
- ✅ **MCP 지원**: 사용자가 원하는 MCP 서버 연결 가능
- ✅ **Linux 최적화**: Linux 환경에서 바로 실행 가능
- ✅ **간편한 관리**: 스크립트 기반 관리

## 필수 요구사항

### 1. Docker & Docker Compose
```bash
# Docker 설치 확인
docker --version
docker compose --version

# Docker가 없다면:
# https://docs.docker.com/get-docker/
```

### 2. Ollama (권장)
```bash
# Ollama 설치 (Linux)
curl -fsSL https://ollama.ai/install.sh | sh

# llama3.1:8b 모델 다운로드 (4.9GB)
ollama pull llama3.1:8b

# 설치 확인
ollama list
```

## 빠른 시작

### 1. 초기 설정 및 실행
```bash
# setup.sh 실행 (자동으로 .env 생성 및 서비스 시작)
./setup.sh
```

`setup.sh`는 다음 작업을 자동으로 수행합니다:
- Docker 및 Ollama 설치 확인
- 보안 시크릿 자동 생성
- `.env` 파일 생성
- llama3.1:8b 모델 다운로드 여부 확인
- 서비스 시작

### 2. 서비스 관리
```bash
# 시작
./start.sh

# 중지
./stop.sh

# 재시작
./restart.sh

# 로그 확인
./logs.sh          # 전체 로그
./logs.sh librechat    # LibreChat 로그만
./logs.sh mongodb      # MongoDB 로그만

# 상태 확인
./status.sh
```

### 3. 접속
- **LibreChat**: http://localhost:3080
- 처음 접속 시 계정 등록 필요 (자동 승인)

## MCP 서버 설정

### 방법 1: 자동 설정 (권장)

MCP 서버가 이미 실행 중이라면:

1. `librechat.yaml` 파일 열기
2. `mcpServers` 섹션 주석 해제
3. MCP 서버 정보 입력:

```yaml
mcpServers:
  clickhouse:
    type: streamable-http
    url: http://mcp-clickhouse-server:3001/mcp
    timeout: 30000
```

4. LibreChat 재시작:
```bash
./restart.sh
```

### 방법 2: 수동 설정

다른 MCP 서버를 추가하려면:

```yaml
mcpServers:
  # ClickHouse 예시
  clickhouse:
    type: streamable-http
    url: http://your-mcp-host:3001/mcp
    timeout: 30000

  # PostgreSQL 예시
  postgres:
    type: streamable-http
    url: http://postgres-mcp-host:3002/mcp
    timeout: 30000

  # Custom API 예시
  custom-api:
    type: streamable-http
    url: http://api-host:3003/mcp
    timeout: 30000
```

### MCP 연결 확인

1. LibreChat 로그인
2. 새 대화 시작
3. "LocalLLM" 엔드포인트 선택
4. MCP 도구 사용 가능 여부 확인:
   ```
   내 데이터베이스를 조회해줘
   ```

## 디렉토리 구조

```
llm-linux-librechat-sole/
├── docker compose.yml      # Docker 구성
├── librechat.yaml          # LibreChat 설정 (MCP 포함)
├── .env                    # 환경 변수 (자동 생성)
├── .env.example            # 환경 변수 템플릿
├── setup.sh                # 초기 설정 스크립트
├── start.sh                # 시작 스크립트
├── stop.sh                 # 중지 스크립트
├── restart.sh              # 재시작 스크립트
├── logs.sh                 # 로그 조회 스크립트
├── status.sh               # 상태 확인 스크립트
├── librechat-data/         # LibreChat 데이터 (자동 생성)
└── README.md               # 이 문서
```

## 설정 파일

### docker compose.yml

LibreChat과 MongoDB 서비스 정의:
- **LibreChat**: 포트 3080, Ollama 연결
- **MongoDB**: 내부 전용, 데이터 영구 저장

### librechat.yaml

LibreChat 엔드포인트 및 MCP 설정:
- **LocalLLM 엔드포인트**: Ollama llama3.1:8b 사용
- **Capabilities**: Tools 및 Agents 활성화 (MCP 필수)
- **MCP 서버**: 사용자 정의 가능

### .env

환경 변수 (setup.sh가 자동 생성):
- `SESSION_SECRET`: 세션 암호화 키 (32 bytes)
- `JWT_SECRET`: JWT 토큰 키 (32 bytes)
- `JWT_REFRESH_SECRET`: JWT 리프레시 키 (32 bytes)
- `CREDS_KEY`: 자격증명 암호화 키 (32 bytes)
- `CREDS_IV`: 자격증명 IV (16 bytes)
- `LIBRECHAT_PORT`: LibreChat 포트 (기본 3080)
- `PRIMARY_MODEL`: Ollama 모델 (llama3.1:8b)

## LLM 모델 정보

### llama3.1:8b (기본 모델)

- **크기**: 4.9GB
- **Tool Calling 성공률**: 91% ✅
- **평균 응답 속도**: 4.04초
- **추천 이유**: MCP tool calling에서 최고 성능

### 다른 모델 사용하기

다른 Ollama 모델을 사용하려면:

1. 모델 다운로드:
```bash
ollama pull <model-name>
```

2. `librechat.yaml` 수정:
```yaml
models:
  default:
    - "your-model-name"
```

3. `.env` 수정:
```bash
PRIMARY_MODEL=your-model-name
```

4. 재시작:
```bash
./restart.sh
```

**⚠️ 주의**: Tool calling 지원 모델만 MCP와 함께 사용 가능합니다.

### MCP 지원 모델

✅ **권장**:
- llama3.1:8b (91% 성공률)
- mistral-nemo (12B)
- qwen2.5:7b-instruct

❌ **지원하지 않음**:
- tinyllama:1.1b
- phi-3.5:3.8b
- gemma2:2b

## 문제 해결

### LibreChat이 시작되지 않음

```bash
# 로그 확인
./logs.sh librechat

# 포트 충돌 확인
lsof -i :3080

# 컨테이너 재시작
./restart.sh
```

### MongoDB 연결 오류

```bash
# MongoDB 상태 확인
docker compose ps mongodb

# MongoDB 로그 확인
./logs.sh mongodb

# MongoDB 재시작
docker compose restart mongodb
```

### Ollama 연결 오류

```bash
# Ollama 상태 확인
curl http://localhost:11434/api/tags

# Ollama 재시작 (Linux)
systemctl restart ollama

# 모델 목록 확인
ollama list
```

### MCP 도구가 호출되지 않음

1. **Capabilities 확인** (`librechat.yaml`):
```yaml
capabilities:
  tools: true
  agents: true
```

2. **모델 tool calling 지원 확인**:
```bash
ollama show llama3.1:8b --modelfile | grep -i tool
```

3. **MCP 서버 연결 확인**:
```bash
curl http://your-mcp-server:port/mcp
```

4. **LibreChat 로그 확인**:
```bash
./logs.sh librechat | grep -i mcp
```

### 보안 키 재생성

```bash
# .env 삭제
rm .env

# setup.sh 다시 실행
./setup.sh

# 주의: 기존 세션이 모두 무효화됩니다
```

## 고급 설정

### 포트 변경

`.env` 파일 수정:
```bash
LIBRECHAT_PORT=8080
```

재시작:
```bash
./restart.sh
```

### 외부 접근 허용

`docker compose.yml` 수정:
```yaml
ports:
  - "0.0.0.0:3080:3080"  # 모든 인터페이스에서 접근 가능
```

**⚠️ 보안 경고**: 프로덕션 환경에서는 역방향 프록시(nginx) 사용 권장

### MongoDB 백업

```bash
# 백업
docker exec librechat-mongodb mongodump --out=/tmp/backup
docker cp librechat-mongodb:/tmp/backup ./mongodb-backup

# 복원
docker cp ./mongodb-backup librechat-mongodb:/tmp/backup
docker exec librechat-mongodb mongorestore /tmp/backup
```

### 리소스 제한

`docker compose.yml`에 추가:
```yaml
services:
  librechat:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
```

## 성능 최적화

### 1. Ollama 성능 향상

```bash
# GPU 사용 (NVIDIA)
# Ollama가 자동으로 GPU 감지

# CPU 스레드 수 설정
export OLLAMA_NUM_THREAD=8
```

### 2. MongoDB 성능 향상

`docker compose.yml`에 추가:
```yaml
mongodb:
  command: --wiredTigerCacheSizeGB 2
```

### 3. LibreChat 캐싱

`librechat.yaml`:
```yaml
cache: true  # 이미 활성화됨
```

## 관련 프로젝트

- **llm-mac-librechat-with-clickhouse**: macOS용 버전 (ClickHouse MCP 포함)
- **mcp-server-clickhouse**: ClickHouse MCP 서버

## 참고 자료

- [LibreChat 공식 문서](https://docs.librechat.ai/)
- [Ollama 공식 사이트](https://ollama.ai/)
- [MCP 프로토콜](https://modelcontextprotocol.io/)
- [Docker 문서](https://docs.docker.com/)

## 라이선스

이 프로젝트는 MIT 라이선스를 따릅니다.

## 지원

문제가 발생하면:
1. [Issues](https://github.com/danny-avila/LibreChat/issues) 확인
2. `./logs.sh`로 로그 수집
3. 위 문제 해결 섹션 참조

## 업데이트

### LibreChat 업데이트
```bash
docker compose pull
./restart.sh
```

### 모델 업데이트
```bash
ollama pull llama3.1:8b
./restart.sh
```
