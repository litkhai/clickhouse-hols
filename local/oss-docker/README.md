# ClickHouse OSS Environment

[English](#english) | [한국어](#한국어)

---

## English

ClickHouse development environment on Docker (macOS, Linux) with a seccomp security profile.

### ✨ Features

- 🔒 **Seccomp Security Profile** - Fixes `get_mempolicy: Operation not permitted` errors
- 📦 **Version Control** - Specify ClickHouse version or use latest
- 🐳 **Docker Named Volumes** - Persistent data storage without host permission issues
- 🧹 **Easy Cleanup** - Built-in cleanup options for data management
- 🌐 **Multiple Interfaces** - Web UI, HTTP API, and TCP access

### 🚀 Quick Start

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

### 📍 Connection Information

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (no password)

### 🛠 Management Scripts

#### Setup
- `./set.sh [VERSION]` - Initial environment setup (first time only)
  - `./set.sh` - Install latest version
  - `./set.sh 25.10` - Install specific version
  - `./set.sh latest` - Explicitly install latest

#### Operations
- `./start.sh` - Start ClickHouse (creates seccomp profile automatically)
- `./stop.sh` - Stop ClickHouse (preserves data)
- `./stop.sh --cleanup` or `./stop.sh -c` - Stop and delete all data
- `./status.sh` - Check container status, health, and resource usage
- `./client.sh` - Connect to CLI client
- `./cleanup.sh` - Complete data deletion (with confirmation prompt)

### 🔧 Advanced Usage

```bash
# View real-time logs
docker compose logs -f

# Execute SQL directly
docker compose exec clickhouse clickhouse-client --query "SHOW DATABASES"

# Access container shell
docker compose exec clickhouse bash
```

### 📂 Data Storage

Data is stored in Docker Named Volumes for persistence:
- `clickhouse-oss_clickhouse_data` - Database files
- `clickhouse-oss_clickhouse_logs` - Log files

### 🔄 Updates

```bash
# Update to new version
docker compose pull
docker compose up -d
```

### 🔧 Troubleshooting

#### get_mempolicy Error
This setup includes a custom seccomp profile that resolves the common `get_mempolicy: Operation not permitted` error. The profile allows necessary NUMA memory policy syscalls (`get_mempolicy`, `set_mempolicy`, `mbind`).

#### Container Won't Start
1. Check Docker is running: `docker info`
2. Check logs: `docker logs clickhouse-oss`
3. Verify seccomp profile exists: `ls -la seccomp-profile.json`

#### Permission issues
This setup uses Docker Named Volumes instead of bind mounts to avoid host permission issues with ClickHouse data directories (macOS and Windows file sharing in particular).

### 📋 System Requirements

- macOS (Apple Silicon or Intel) or Linux. Windows is not tested
- Docker Desktop, or Docker Engine with the Compose plugin on Linux
- `bash`
- 4GB+ RAM recommended
- 10GB+ disk space

### 🔐 Security

- Includes custom seccomp profile for container security
- Default user with no password (suitable for development)
- Network isolation with dedicated Docker network
- Data persistence with named volumes

### License

[MIT](../../LICENSE) — same as the rest of the repository.

---

## 한국어

*영어 원문을 LLM 도움으로 번역했습니다(2026-10-06).*

Docker(macOS, Linux)에서 seccomp 보안 프로파일과 함께 쓰는 ClickHouse 개발 환경입니다.

### ✨ 기능

- 🔒 **Seccomp 보안 프로파일** - `get_mempolicy: Operation not permitted` 오류를 해결합니다
- 📦 **버전 관리** - ClickHouse 버전을 지정하거나 latest를 사용합니다
- 🐳 **Docker Named Volume** - 호스트 권한 문제 없이 데이터를 영구 저장합니다
- 🧹 **간편한 정리** - 데이터 관리를 위한 정리 옵션을 기본 제공합니다
- 🌐 **다양한 인터페이스** - Web UI, HTTP API, TCP 접속

### 🚀 빠른 시작

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

### 📍 접속 정보

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **사용자**: default (비밀번호 없음)

### 🛠 관리 스크립트

#### 설정
- `./set.sh [VERSION]` - 초기 환경 설정 (최초 1회만)
  - `./set.sh` - 최신 버전 설치
  - `./set.sh 25.10` - 특정 버전 설치
  - `./set.sh latest` - 최신 버전을 명시적으로 설치

#### 운영
- `./start.sh` - ClickHouse 시작 (seccomp 프로파일을 자동 생성)
- `./stop.sh` - ClickHouse 중지 (데이터 보존)
- `./stop.sh --cleanup` 또는 `./stop.sh -c` - 중지하고 모든 데이터 삭제
- `./status.sh` - 컨테이너 상태, 헬스, 리소스 사용량 확인
- `./client.sh` - CLI 클라이언트 접속
- `./cleanup.sh` - 데이터 완전 삭제 (확인 프롬프트 포함)

### 🔧 고급 사용법

```bash
# View real-time logs
docker compose logs -f

# Execute SQL directly
docker compose exec clickhouse clickhouse-client --query "SHOW DATABASES"

# Access container shell
docker compose exec clickhouse bash
```

### 📂 데이터 저장

데이터는 영구 보존을 위해 Docker Named Volume에 저장됩니다.
- `clickhouse-oss_clickhouse_data` - 데이터베이스 파일
- `clickhouse-oss_clickhouse_logs` - 로그 파일

### 🔄 업데이트

```bash
# Update to new version
docker compose pull
docker compose up -d
```

### 🔧 트러블슈팅

#### get_mempolicy 오류
이 환경에는 흔히 발생하는 `get_mempolicy: Operation not permitted` 오류를 해결하는 커스텀 seccomp 프로파일이 포함되어 있습니다. 이 프로파일은 NUMA 메모리 정책에 필요한 시스템 콜(`get_mempolicy`, `set_mempolicy`, `mbind`)을 허용합니다.

#### 컨테이너가 시작되지 않을 때
1. Docker가 실행 중인지 확인: `docker info`
2. 로그 확인: `docker logs clickhouse-oss`
3. seccomp 프로파일이 있는지 확인: `ls -la seccomp-profile.json`

#### 권한 문제
이 환경은 ClickHouse 데이터 디렉터리에서 생기는 호스트 권한 문제(특히 macOS와 Windows의 파일 공유)를 피하기 위해 bind mount 대신 Docker Named Volume을 사용합니다.

### 📋 시스템 요구사항

- macOS(Apple Silicon 또는 Intel) 또는 Linux. Windows는 테스트하지 않았습니다
- Docker Desktop, 또는 Linux의 Docker Engine과 Compose 플러그인
- `bash`
- 4GB 이상 RAM 권장
- 10GB 이상 디스크 공간

### 🔐 보안

- 컨테이너 보안을 위한 커스텀 seccomp 프로파일 포함
- 비밀번호 없는 default 사용자 (개발용으로 적합)
- 전용 Docker 네트워크로 네트워크 격리
- Named Volume으로 데이터 영구 보존

### License

[MIT](../../LICENSE) — 저장소 전체와 동일합니다.
