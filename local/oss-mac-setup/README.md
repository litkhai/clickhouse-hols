# ClickHouse OSS Environment

[English](#english) | [한국어](#한국어)

---

## English

ClickHouse development environment optimized for macOS with seccomp security profile.

## ✨ Features

- 🔒 **Seccomp Security Profile** - Fixes `get_mempolicy: Operation not permitted` errors
- 📦 **Version Control** - Specify ClickHouse version or use latest
- 🐳 **Docker Named Volumes** - Persistent data storage with proper macOS permissions
- 🧹 **Easy Cleanup** - Built-in cleanup options for data management
- 🌐 **Multiple Interfaces** - Web UI, HTTP API, and TCP access

## 🚀 Quick Start

```bash
# 1. Setup (first time only) - defaults to latest version
./set.sh

# Or specify a version
./set.sh 25.10

# 2. Start
./start.sh

# 3. Connect
./client.sh
```

## 📍 Connection Information

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (no password)

## 🛠 Management Scripts

### Setup
- `./set.sh [VERSION]` - Initial environment setup (first time only)
  - `./set.sh` - Install latest version
  - `./set.sh 25.10` - Install specific version
  - `./set.sh latest` - Explicitly install latest

### Operations
- `./start.sh` - Start ClickHouse (creates seccomp profile automatically)
- `./stop.sh` - Stop ClickHouse (preserves data)
- `./stop.sh --cleanup` or `./stop.sh -c` - Stop and delete all data
- `./status.sh` - Check container status, health, and resource usage
- `./client.sh` - Connect to CLI client
- `./cleanup.sh` - Complete data deletion (with confirmation prompt)

## 🔧 Advanced Usage

```bash
# View real-time logs
docker-compose logs -f

# Execute SQL directly
docker-compose exec clickhouse clickhouse-client --query "SHOW DATABASES"

# Access container shell
docker-compose exec clickhouse bash
```

## 📂 Data Storage

Data is stored in Docker Named Volumes for persistence:
- `clickhouse-oss_clickhouse_data` - Database files
- `clickhouse-oss_clickhouse_logs` - Log files

## 🔄 Updates

```bash
# Update to new version
docker-compose pull
docker-compose up -d
```

## 🔧 Troubleshooting

### get_mempolicy Error
This setup includes a custom seccomp profile that resolves the common `get_mempolicy: Operation not permitted` error. The profile allows necessary NUMA memory policy syscalls (`get_mempolicy`, `set_mempolicy`, `mbind`).

### Container Won't Start
1. Check Docker is running: `docker info`
2. Check logs: `docker logs clickhouse-oss`
3. Verify seccomp profile exists: `ls -la /Users/kenlee/clickhouse/oss/seccomp-profile.json`

### Permission Issues on macOS
This setup uses Docker Named Volumes instead of bind mounts to avoid macOS permission issues with ClickHouse data directories.

## 📋 System Requirements

- macOS (optimized for Apple Silicon and Intel)
- Docker Desktop for Mac
- 4GB+ RAM recommended
- 10GB+ disk space

## 🔐 Security

- Includes custom seccomp profile for container security
- Default user with no password (suitable for development)
- Network isolation with dedicated Docker network
- Data persistence with named volumes

---

## 한국어

seccomp 보안 프로필이 적용된 macOS에 최적화된 ClickHouse 개발 환경입니다.

## ✨ 특징

- 🔒 **Seccomp 보안 프로필** - `get_mempolicy: Operation not permitted` 오류 해결
- 📦 **버전 관리** - ClickHouse 버전 지정 또는 최신 버전 사용
- 🐳 **Docker Named Volumes** - macOS 권한 문제 없는 영구 데이터 저장
- 🧹 **간편한 정리** - 데이터 관리를 위한 내장 정리 옵션
- 🌐 **다중 인터페이스** - Web UI, HTTP API, TCP 접근

## 🚀 빠른 시작

```bash
# 1. 설정 (최초 1회만) - 기본적으로 최신 버전 사용
./set.sh

# 또는 특정 버전 지정
./set.sh 25.10

# 2. 시작
./start.sh

# 3. 연결
./client.sh
```

## 📍 연결 정보

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **사용자**: default (비밀번호 없음)

## 🛠 관리 스크립트

### 설정
- `./set.sh [VERSION]` - 초기 환경 설정 (최초 1회만)
  - `./set.sh` - 최신 버전 설치
  - `./set.sh 25.10` - 특정 버전 설치
  - `./set.sh latest` - 명시적으로 최신 버전 설치

### 운영
- `./start.sh` - ClickHouse 시작 (seccomp 프로필 자동 생성)
- `./stop.sh` - ClickHouse 중지 (데이터 보존)
- `./stop.sh --cleanup` 또는 `./stop.sh -c` - 중지 및 모든 데이터 삭제
- `./status.sh` - 컨테이너 상태, 헬스체크, 리소스 사용량 확인
- `./client.sh` - CLI 클라이언트 연결
- `./cleanup.sh` - 완전한 데이터 삭제 (확인 프롬프트 포함)

## 🔧 고급 사용법

```bash
# 실시간 로그 보기
docker-compose logs -f

# SQL 직접 실행
docker-compose exec clickhouse clickhouse-client --query "SHOW DATABASES"

# 컨테이너 쉘 접근
docker-compose exec clickhouse bash
```

## 📂 데이터 저장소

데이터는 영구성을 위해 Docker Named Volumes에 저장됩니다:
- `clickhouse-oss_clickhouse_data` - 데이터베이스 파일
- `clickhouse-oss_clickhouse_logs` - 로그 파일

## 🔄 업데이트

```bash
# 새 버전으로 업데이트
docker-compose pull
docker-compose up -d
```

## 🔧 문제 해결

### get_mempolicy 오류
이 설정에는 일반적인 `get_mempolicy: Operation not permitted` 오류를 해결하는 사용자 정의 seccomp 프로필이 포함되어 있습니다. 이 프로필은 필요한 NUMA 메모리 정책 시스템 콜(`get_mempolicy`, `set_mempolicy`, `mbind`)을 허용합니다.

### 컨테이너가 시작되지 않음
1. Docker 실행 확인: `docker info`
2. 로그 확인: `docker logs clickhouse-oss`
3. seccomp 프로필 존재 확인: `ls -la /Users/kenlee/clickhouse/oss/seccomp-profile.json`

### macOS 권한 문제
이 설정은 ClickHouse 데이터 디렉토리와의 macOS 권한 문제를 방지하기 위해 바인드 마운트 대신 Docker Named Volumes를 사용합니다.

## 📋 시스템 요구사항

- macOS (Apple Silicon 및 Intel 최적화)
- Docker Desktop for Mac
- 4GB+ RAM 권장
- 10GB+ 디스크 공간

## 🔐 보안

- 컨테이너 보안을 위한 사용자 정의 seccomp 프로필 포함
- 비밀번호 없는 기본 사용자 (개발 환경에 적합)
- 전용 Docker 네트워크를 통한 네트워크 격리
- 명명된 볼륨을 통한 데이터 영속성
