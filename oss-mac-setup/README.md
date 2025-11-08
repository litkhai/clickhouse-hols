# ClickHouse OSS Environment

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
