# ClickHouse OSS Environment

ClickHouse development environment optimized for macOS.

## 🚀 Quick Start

```bash
# 1. Setup (first time only)
./setup.sh

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

- `./setup.sh` - Initial environment setup (first time only)
- `./start.sh` - Start ClickHouse
- `./stop.sh` - Stop ClickHouse
- `./status.sh` - Check status
- `./client.sh` - Connect to CLI client
- `./cleanup.sh` - Complete data deletion

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
