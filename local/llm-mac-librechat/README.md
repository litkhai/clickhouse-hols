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

1. **qwen2.5-coder:3b** (3B) - 코딩 작업에 최적화, 우수한 성능
2. **phi-3.5:3.8b** (3.8B) - Microsoft의 효율적인 모델
3. **gemma2:2b** (2B) - Google의 경량 모델
4. **tinyllama:1.1b** (1.1B) - 초경량 모델, 기본 작업용

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

### 2. 설정 구성

```bash
cd local/llm-mac-librechat
./setup.sh --configure
```

대화형 프롬프트에서 다음을 입력합니다:
- ClickHouse 연결 정보 (host, port, user, password)
- 사용할 LLM 모델 선택
- LibreChat 포트 설정

### 3. 서비스 시작

```bash
./setup.sh --start
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
# 설정 (최초 1회)
./setup.sh --configure

# 서비스 시작
./setup.sh --start

# 서비스 중지
./setup.sh --stop

# 재시작
./setup.sh --restart

# 상태 확인
./setup.sh --status

# 로그 보기
./setup.sh --logs

# 엔드포인트 정보
./setup.sh --endpoints

# 완전 삭제 (데이터 포함)
./setup.sh --clean
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
├── setup.sh                    # 메인 설정 스크립트
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
# 추천 모델들
ollama pull qwen2.5-coder:3b
ollama pull phi-3.5:3.8b
ollama pull gemma2:2b
ollama pull tinyllama:1.1b

# 다른 모델들
ollama pull llama3.2:3b
ollama pull mistral:7b-instruct-q4_0
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
docker ps

# 로그 확인
./setup.sh --logs

# 재시작
./setup.sh --restart
```

### MongoDB 오류

```bash
# MongoDB 컨테이너 재시작
docker restart librechat-mongodb

# 볼륨 초기화 (주의: 데이터 삭제됨)
./setup.sh --clean
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
./setup.sh --restart
```

### 모델 업데이트

```bash
# 최신 모델 pull
ollama pull <model-name>
```

## 기여

개선 사항이나 버그는 이슈로 제출해주세요.

## 라이선스

이 프로젝트는 각 구성 요소의 라이선스를 따릅니다:
- LibreChat: MIT License
- Ollama: MIT License
- ClickHouse: Apache License 2.0

## 참고 링크

- [LibreChat Documentation](https://docs.librechat.ai/)
- [Ollama](https://ollama.ai/)
- [ClickHouse Documentation](https://clickhouse.com/docs)
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io/)
