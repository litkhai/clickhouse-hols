# LibreChat with Local LLM and ClickHouse MCP Server

로컬 LLM (Ollama)과 ClickHouse MCP 서버를 통합한 LibreChat 환경입니다.

## 개요

이 설정은 다음을 제공합니다:

- **LibreChat**: 오픈소스 ChatGPT 대안 웹 인터페이스
- **Ollama**: 로컬 LLM 모델 실행 (Mac 최적화)
- **ClickHouse MCP Server**: ClickHouse 데이터베이스에 대한 MCP (Model Context Protocol) 접근
- **MongoDB**: LibreChat 데이터 저장소

## 추천 경량 모델

Mac에서 원활하게 작동하는 경량 모델들:

### MCP Tool Calling 지원 모델 (필수)
MCP 서버와 함께 사용하려면 **반드시 tool calling을 지원하는 모델**을 사용해야 합니다:

1. **llama3.1:8b** (8B) ✅ - **최고의 function calling 성능 (91% 성공률, 권장)**
2. **mistral-nemo** (12B) ✅ - Mistral 7B보다 우수한 대안
3. **qwen2.5:7b-instruct** (7B) ✅ - 빠르고 안정적

### Tool Calling 지원 제한적/불안정 모델
다음 모델들은 MCP와 함께 사용 시 문제가 있을 수 있습니다:

1. **mistral:7b-instruct** (7B) ⚠️ - v0.3 필요, 불안정 (86% 성공률)
2. **qwen2.5-coder:3b** (3B) ⚠️ - JSON 문자열 반환 문제
3. **phi-3.5:3.8b** (3.8B) ❌ - Tool calling 미지원
4. **gemma2:2b** (2B) ❌ - Tool calling 미지원
5. **tinyllama:1.1b** (1.1B) ❌ - Tool calling 미지원

## 사전 요구사항

### 필수
- Docker Desktop for Mac
- Ollama ([https://ollama.ai](https://ollama.ai))
- ClickHouse 인스턴스 (로컬 또는 클라우드)

### 권장
- 최소 16GB RAM
- Apple Silicon (M1/M2/M3) 또는 Intel Mac

## 빠른 시작

### 1. Ollama 설치 및 실행

```bash
# Ollama 설치 (Homebrew)
brew install ollama

# Ollama 서비스 시작
ollama serve
```

### 2. 초기 설정

```bash
cd local/llm-mac-librechat
./setup.sh
```

대화형 프롬프트에서 다음을 입력합니다:
- ClickHouse 연결 정보 (host, port, user, password)
- 사용할 LLM 모델 선택
- LibreChat 포트 설정

### 3. 서비스 시작

```bash
./start.sh
```

### 4. 접속

브라우저에서 `http://localhost:3080` 접속 후:
1. 계정 생성
2. 로그인
3. 모델 선택 (드롭다운에서 Ollama 모델 선택)
4. ClickHouse 데이터와 대화 시작!

## 사용법

### 기본 명령어

```bash
# 초기 설정 (최초 1회)
./setup.sh

# 서비스 시작
./start.sh

# 서비스 중지
./stop.sh

# 재시작
./restart.sh

# 상태 확인
./status.sh

# 로그 보기
./logs.sh

# 특정 서비스 로그만 보기
./logs.sh librechat
./logs.sh mcp-server
./logs.sh mongodb
```

### ClickHouse 쿼리 예제

LibreChat에서 다음과 같이 질문할 수 있습니다:

```
"시스템에 있는 모든 테이블을 보여줘"
"users 테이블의 스키마를 설명해줘"
"지난 7일간의 사용자 활동을 분석해줘"
"sales 테이블에서 상위 10개 제품을 조회해줘"
```

MCP 서버가 자동으로 ClickHouse 쿼리를 실행하고 결과를 반환합니다.

## 구조

```
local/llm-mac-librechat/
├── setup.sh                    # 초기 설정 스크립트
├── start.sh                    # 서비스 시작
├── stop.sh                     # 서비스 중지
├── restart.sh                  # 서비스 재시작
├── logs.sh                     # 로그 조회
├── status.sh                   # 상태 확인
├── docker-compose.yml          # Docker 서비스 정의
├── config.env                  # 환경 설정 (자동 생성)
├── .credentials               # ClickHouse 인증 정보 (자동 생성, git 제외)
├── librechat.yaml             # LibreChat 설정
├── mcp-server/
│   └── server.js              # ClickHouse MCP 서버
├── librechat-data/            # LibreChat 데이터 (자동 생성)
└── README.md                  # 이 파일
```

## 서비스 구성

### LibreChat
- **포트**: 3080 (기본값)
- **데이터**: MongoDB에 저장
- **기능**:
  - 다중 모델 지원
  - 대화 기록
  - 파일 업로드
  - MCP 통합

### Ollama (호스트)
- **포트**: 11434
- **위치**: 호스트 머신에서 실행
- **모델**: ~/.ollama/models

### ClickHouse MCP Server
- **포트**: 3001 (기본값)
- **기능**:
  - 쿼리 실행
  - 스키마 조회
  - 테이블 목록
  - DDL/DML 실행

### MongoDB
- **포트**: 27017 (내부)
- **데이터**: Docker 볼륨
- **인증**: admin/admin123

## MCP 서버 API

### Endpoints

#### Health Check
```bash
curl http://localhost:3001/health
```

#### List Tables
```bash
curl -X POST http://localhost:3001/api/tools/execute \
  -H "Content-Type: application/json" \
  -d '{"tool": "list_tables", "parameters": {}}'
```

#### Query
```bash
curl -X POST http://localhost:3001/api/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT * FROM system.tables LIMIT 5"}'
```

#### Describe Table
```bash
curl -X POST http://localhost:3001/api/tools/execute \
  -H "Content-Type: application/json" \
  -d '{"tool": "describe_table", "parameters": {"table": "users"}}'
```

## 모델 관리

### 모델 다운로드

```bash
# MCP Tool Calling 권장 모델
ollama pull llama3.1:8b              # 최고 성능 (91% 성공률)
ollama pull mistral-nemo             # 대안 (12B)
ollama pull qwen2.5:7b-instruct      # 대안 (7B)
```

### 설치된 모델 확인

```bash
ollama list
```

### 모델 삭제

```bash
ollama rm <model-name>
```

## 문제 해결

### 🔧 LibreChat v0.8.x "Ollama" 이름 버그 (해결됨)

**문제**: LibreChat v0.8.x에서 custom endpoint 이름을 "Ollama" (대소문자 무관)로 설정하면 agents controller로 잘못 라우팅되어 "fetch failed" 오류가 발생합니다.

**원인**: LibreChat의 알려진 버그 ([Issue #10327](https://github.com/danny-avila/LibreChat/issues/10327))

**해결책**: `librechat.yaml`에서 엔드포인트 이름을 "Ollama"가 아닌 다른 이름으로 변경:

```yaml
endpoints:
  custom:
    - name: "LocalLLM"  # "Ollama" 대신 다른 이름 사용
      apiKey: "ollama"
      baseURL: "http://host.docker.internal:11434/v1/"
      modelDisplayLabel: "Ollama"  # UI에는 "Ollama"로 표시됨
```

이 설정으로 Ollama가 정상적으로 작동합니다.

### ⚠️ MCP Tool Calling 제한사항 (중요)

**문제**: LibreChat v0.8.x에서 일부 Ollama 모델을 사용한 MCP tool calling이 제대로 작동하지 않습니다.

**원인**:
- 일부 모델(qwen2.5-coder:3b, mistral:7b-instruct v0.2)은 tool call을 `message.content`에 JSON 문자열로 반환
- LibreChat은 `tool_calls` 필드의 구조화된 객체를 기대함
- 이로 인해 tool이 호출되지 않고 JSON만 텍스트로 표시됨
- LiteLLM 프록시 사용 시 응답 변환 문제 발생

**검증된 해결책**:
1. **llama3.1:8b 사용 (✅ 권장)**:
   - 가장 우수한 tool calling 지원 (91% 성공률)
   - 가장 빠른 응답 속도 (4.04초 평균)
   - 현재 설정에서 완벽히 작동 확인됨
   ```bash
   ollama pull llama3.1:8b
   ```

2. **대안 모델**:
   - `mistral-nemo` (12B) - Mistral 7B보다 우수
   - `qwen2.5:7b-instruct` - 빠르고 안정적

3. **capabilities 설정 필수**:
   ```yaml
   capabilities:
     tools: true
     agents: true
   ```

4. **OpenAI/Claude API 사용**: 완벽한 MCP 통합 보장

**참고 자료**:
- [LibreChat Discussion #7639](https://github.com/danny-avila/LibreChat/discussions/7639) - MCP Tools 호출 문제
- [Ollama Tool Support Blog](https://ollama.com/blog/tool-support) - 공식 지원 모델
- [Best Ollama Models 2025 for Function Calling](https://collabnix.com/best-ollama-models-for-function-calling-tools-complete-guide-2025/) - 성능 벤치마크

### Ollama 연결 오류

```bash
# Ollama 서비스 상태 확인
ps aux | grep ollama

# Ollama 재시작
killall ollama
ollama serve
```

### ClickHouse 연결 오류

1. ClickHouse가 실행 중인지 확인
2. `.credentials` 파일의 연결 정보 확인
3. 방화벽/네트워크 설정 확인

```bash
# 연결 테스트
curl "http://localhost:8123/?query=SELECT%20version()"
```

### LibreChat 접속 불가

```bash
# 컨테이너 상태 확인
./status.sh

# 로그 확인
./logs.sh

# 재시작
./restart.sh
```

### MongoDB 오류

```bash
# MongoDB 컨테이너 재시작
docker restart librechat-mongodb

# 컨테이너 로그 확인
./logs.sh mongodb
```

## 보안 고려사항

### 주의사항

1. **`.credentials` 파일**
   - Git에 커밋하지 마세요
   - 권한: 600 (자동 설정)
   - 민감한 정보 포함

2. **기본 비밀번호 변경**
   - MongoDB: admin/admin123
   - 프로덕션 환경에서는 반드시 변경

3. **네트워크 노출**
   - 기본 설정은 localhost만 허용
   - 외부 접근 시 인증/암호화 필수

## 성능 최적화

### Mac 시스템 권장사항

1. **Docker 리소스 할당**
   - Docker Desktop > Settings > Resources
   - CPU: 최소 4 코어
   - Memory: 8GB 이상
   - Swap: 2GB

2. **Ollama 메모리**
   - 모델 크기에 따라 4-8GB RAM 필요
   - 여러 모델 동시 로드 시 더 많은 메모리 필요

3. **디스크 공간**
   - 모델: ~2-4GB per model
   - Docker 이미지: ~2GB
   - 데이터: 필요에 따라

## 업데이트

### 이미지 업데이트

```bash
# 이미지 pull
docker compose pull

# 재시작
./restart.sh
```

### 모델 업데이트

```bash
# 최신 모델 pull
ollama pull <model-name>
```

## 기여

개선 사항이나 버그는 이슈로 제출해주세요.

## 라이선스

이 랩이 담고 있는 파일 — compose 파일, 스크립트, 설정 템플릿, 이 문서 — 는
[MIT](../../LICENSE)로, 저장소 전체와 동일합니다.

실행 시점에 내려받는 소프트웨어는 각자의 라이선스를 따르며, 여기에 복사해 두지
않았습니다:
- LibreChat: MIT License
- Ollama: MIT License
- ClickHouse: Apache License 2.0

## 참고 링크

- [LibreChat Documentation](https://docs.librechat.ai/)
- [Ollama](https://ollama.ai/)
- [ClickHouse Documentation](https://clickhouse.com/docs)
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io/)
