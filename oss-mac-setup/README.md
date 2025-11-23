# ClickHouse OSS Multi-Version Environment

ClickHouse development environment optimized for macOS with multi-version support and seccomp security profile.

## ✨ Features

- 🔒 **Seccomp Security Profile** - Fixes `get_mempolicy: Operation not permitted` errors
- 📦 **Multi-Version Support** - Run multiple ClickHouse versions simultaneously
- 🎯 **Smart Port Mapping** - Automatic port assignment based on version (e.g., 24.10 → port 2410)
- 🐳 **Docker Named Volumes** - Persistent data storage with proper macOS permissions
- 🧹 **Easy Cleanup** - Built-in cleanup options for data management
- 🌐 **Multiple Interfaces** - Web UI, HTTP API, and TCP access for each version

## 🚀 Quick Start

### Single Version Setup
```bash
# 1. Setup (first time only) - defaults to latest version
./set.sh

# Or specify a specific version
./set.sh 25.10

# 2. Start
./start.sh

# 3. Connect (for latest, use port 9999)
./client.sh 9999
```

### Multi-Version Setup
```bash
# 1. Setup multiple versions
./set.sh 24.10 25.6 25.10

# 2. Start all versions
./start.sh

# 3. Connect to specific version
./client.sh 2410  # for version 24.10
./client.sh 2506  # for version 25.6
./client.sh 2510  # for version 25.10
```

## 📍 Port Mapping Convention

Ports are automatically assigned based on version numbers:

| Version | HTTP Port | TCP Port | Web UI |
|---------|-----------|----------|---------|
| 24.10   | 2410      | 24101    | http://localhost:2410/play |
| 25.6    | 2506      | 25061    | http://localhost:2506/play |
| 25.10   | 2510      | 25101    | http://localhost:2510/play |
| latest  | 9999      | 99991    | http://localhost:9999/play |

**Default User**: `default` (no password)

## 🛠 Management Scripts

### Setup
- `./set.sh [VERSION1] [VERSION2] ...` - Initial environment setup (first time only)
  - `./set.sh` - Install latest version only
  - `./set.sh 25.10` - Install specific single version
  - `./set.sh 24.10 25.6 25.10` - Install multiple versions
  - `./set.sh latest` - Explicitly install latest version

### Operations
- `./start.sh` - Start all configured ClickHouse versions
- `./stop.sh` - Stop all versions (preserves data)
- `./stop.sh --cleanup` or `./stop.sh -c` - Stop and delete all data
- `./status.sh` - Check container status, health, and resource usage for all versions
- `./client.sh <PORT>` - Connect to CLI client of specific version
  - Example: `./client.sh 2410` for version 24.10
  - Example: `./client.sh 9999` for latest version
- `./cleanup.sh` - Complete data deletion for all versions (with confirmation prompt)

## 🔧 Advanced Usage

### View Logs
```bash
# View all logs
docker-compose logs -f

# View logs for specific version
docker logs clickhouse-24-10 -f
docker logs clickhouse-25-10 -f
```

### Execute SQL Directly
```bash
# Execute SQL on specific version
docker-compose exec clickhouse-24-10 clickhouse-client --query "SHOW DATABASES"
docker-compose exec clickhouse-25-10 clickhouse-client --query "SELECT version()"

# Access container shell for specific version
docker-compose exec clickhouse-24-10 bash
```

### Working with Multiple Versions
```bash
# Test query across all versions
for container in $(docker ps --filter "name=clickhouse-" --format "{{.Names}}"); do
  echo "=== $container ==="
  docker exec $container clickhouse-client --query "SELECT version()"
done
```

## 📂 Data Storage

Data is stored in separate Docker Named Volumes for each version:
- `clickhouse-oss_clickhouse_data_24_10` - Database files for version 24.10
- `clickhouse-oss_clickhouse_logs_24_10` - Log files for version 24.10
- `clickhouse-oss_clickhouse_data_25_10` - Database files for version 25.10
- `clickhouse-oss_clickhouse_logs_25_10` - Log files for version 25.10
- And so on for each configured version...

## 🔄 Updates

```bash
# Update all versions to latest images
docker-compose pull
docker-compose up -d

# Update specific version
docker pull clickhouse/clickhouse-server:25.10
docker-compose up -d clickhouse-25-10
```

## 🔧 Troubleshooting

### get_mempolicy Error
This setup includes a custom seccomp profile that resolves the common `get_mempolicy: Operation not permitted` error. The profile allows necessary NUMA memory policy syscalls (`get_mempolicy`, `set_mempolicy`, `mbind`).

### Container Won't Start
1. Check Docker is running: `docker info`
2. Check logs for specific version: `docker logs clickhouse-24-10`
3. Verify seccomp profile exists: `ls -la seccomp-profile.json`
4. Check all container status: `./status.sh`

### Port Conflicts
If you get port binding errors, check for conflicts:
```bash
# Check which ports are in use
lsof -i :2410
lsof -i :2510

# Stop conflicting services or change version configuration
```

### Permission Issues on macOS
This setup uses Docker Named Volumes instead of bind mounts to avoid macOS permission issues with ClickHouse data directories.

### Version-Specific Issues
Each version runs independently. If one version fails:
1. Check logs: `docker logs clickhouse-<version>`
2. Try restarting just that version: `docker-compose restart clickhouse-<version>`
3. Check connectivity: `curl http://localhost:<port>/ping`

## 📋 System Requirements

- macOS (optimized for Apple Silicon and Intel)
- Docker Desktop for Mac
- 4GB+ RAM recommended per version
- 10GB+ disk space per version

## 🔐 Security

- Includes custom seccomp profile for container security
- Default user with no password (suitable for development)
- Network isolation with dedicated Docker network
- Data persistence with named volumes
- Each version runs in isolated containers

## 💡 Use Cases

### Testing Version Compatibility
Run your application against multiple ClickHouse versions simultaneously to ensure compatibility:
```bash
# Setup test versions
./set.sh 24.10 25.10

# Run tests against different versions
pytest tests/ --clickhouse-port=2410  # Test against 24.10
pytest tests/ --clickhouse-port=2510  # Test against 25.10
```

### Version Migration Testing
Test data migration between versions:
```bash
# Load data in older version
./client.sh 2410
# ... load your data ...

# Export from old version
docker exec clickhouse-24-10 clickhouse-client --query "SELECT * FROM mydb.mytable FORMAT Native" > data.native

# Import to new version
cat data.native | docker exec -i clickhouse-25-10 clickhouse-client --query "INSERT INTO mydb.mytable FORMAT Native"
```

### Performance Comparison
Compare query performance across versions:
```bash
# Run same query on different versions
time ./client.sh 2410 --query "SELECT count() FROM large_table"
time ./client.sh 2510 --query "SELECT count() FROM large_table"
```
