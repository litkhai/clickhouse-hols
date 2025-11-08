#!/bin/bash

# ClickHouse OSS environment initial setup script
# Usage: ./setup.sh [VERSION]
# Example: ./setup.sh 25.10
#          ./setup.sh latest
#          ./setup.sh (defaults to latest)

set -e

# Version parameter (default to latest if not specified)
CLICKHOUSE_VERSION="${1:-latest}"
BASE_DIR="/Users/kenlee/clickhouse/oss"
SCRIPT_NAME="ClickHouse OSS Setup"

echo "🚀 $SCRIPT_NAME"
echo "=================================="
echo "📍 Installation directory: $BASE_DIR"
echo "📦 ClickHouse version: $CLICKHOUSE_VERSION"
echo ""

# Check Docker environment
echo "🐳 Checking Docker environment..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed!"
    echo "   Install from https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Docker is not running!"
    echo "   Please start Docker Desktop."
    exit 1
fi

echo "✅ Docker environment check complete"

# Create directory
echo "📁 Creating directory..."
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

# Create docker-compose.yml (using Named Volume)
echo "📝 Creating Docker Compose configuration..."
cat > docker-compose.yml << EOF
services:
  clickhouse:
    image: clickhouse/clickhouse-server:${CLICKHOUSE_VERSION}
    container_name: clickhouse-oss
    hostname: clickhouse
    ports:
      - "8123:8123"  # HTTP Interface
      - "9000:9000"  # TCP Interface
    volumes:
      # Using Named volume (resolves macOS permission issues)
      - clickhouse_data:/var/lib/clickhouse
      - clickhouse_logs:/var/log/clickhouse-server
    environment:
      CLICKHOUSE_DB: default
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: ""
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8123/ping"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 30s
    ulimits:
      nofile:
        soft: 262144
        hard: 262144

volumes:
  clickhouse_data:
    driver: local
  clickhouse_logs:
    driver: local

networks:
  default:
    name: clickhouse-network
    driver: bridge
EOF

# Create .env file
echo "📝 Creating environment variables file..."
cat > .env << 'EOF'
# ClickHouse configuration
CLICKHOUSE_DB=default
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=

# Docker Compose configuration
COMPOSE_PROJECT_NAME=clickhouse-oss
EOF

# Create start.sh script
echo "📝 Creating start script..."
cat > start.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting ClickHouse..."
echo "========================"

# Clean up existing container if present
if docker ps -a --format '{{.Names}}' | grep -q '^clickhouse-oss$'; then
    echo "🔄 Cleaning up existing container..."
    docker-compose down
fi

# Start ClickHouse
echo "▶️  Starting ClickHouse container..."
docker-compose up -d

# Wait for initialization
echo "⏳ Waiting for ClickHouse initialization..."
echo "   (up to 45 seconds)"

# Check status (wait up to 45 seconds)
for i in {1..45}; do
    if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
        echo ""
        echo "✅ ClickHouse started successfully!"
        break
    fi

    if [ $i -eq 45 ]; then
        echo ""
        echo "⚠️  Startup is taking longer than expected. Check logs:"
        echo "   docker-compose logs clickhouse"
        exit 1
    fi

    echo -ne "\r   Waiting... ${i}s"
    sleep 1
done

echo ""
echo "🎯 Connection Information:"
echo "   📍 Web UI: http://localhost:8123/play"
echo "   📍 HTTP API: http://localhost:8123"
echo "   📍 TCP: localhost:9000"
echo "   👤 User: default (no password)"
echo ""
echo "🔧 Management Commands:"
echo "   ./stop.sh      - Stop ClickHouse"
echo "   ./status.sh    - Check status"
echo "   ./client.sh    - Connect to CLI client"
echo ""
echo "✨ ClickHouse is ready!"
EOF

# Create stop.sh script
echo "📝 Creating stop script..."
cat > stop.sh << 'EOF'
#!/bin/bash

echo "🛑 Stopping ClickHouse..."
echo "======================="

# Stop with Docker Compose
if [ -f "docker-compose.yml" ]; then
    echo "▶️  Stopping with Docker Compose..."
    docker-compose down
else
    echo "▶️  Stopping container directly..."
    docker stop clickhouse-oss 2>/dev/null || true
    docker rm clickhouse-oss 2>/dev/null || true
fi

# Check status
if docker ps --format '{{.Names}}' | grep -q '^clickhouse-oss$'; then
    echo "⚠️  Container is still running."
    echo "   Force stop: docker kill clickhouse-oss"
else
    echo "✅ ClickHouse stopped successfully."
fi

echo ""
echo "🔧 To restart: ./start.sh"
EOF

# Create status.sh script
echo "📝 Creating status check script..."
cat > status.sh << 'EOF'
#!/bin/bash

echo "📊 ClickHouse Status"
echo "=================="

# Container status
echo "🐳 Container Status:"
if docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep clickhouse-oss; then
    echo ""
else
    echo "❌ ClickHouse container is not running."
    echo "   To start: ./start.sh"
    echo ""
    exit 1
fi

# Service health check
echo "💓 Service Status:"
if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
    echo "✅ HTTP Interface: OK (port 8123)"

    # Version information
    VERSION=$(curl -s http://localhost:8123/ 2>/dev/null | grep -o 'ClickHouse server version [0-9.]*' | head -1)
    if [ -n "$VERSION" ]; then
        echo "✅ $VERSION"
    fi
else
    echo "❌ HTTP Interface: Connection failed (port 8123)"
fi

# TCP port check
if nc -z localhost 9000 2>/dev/null; then
    echo "✅ TCP Interface: OK (port 9000)"
else
    echo "❌ TCP Interface: Connection failed (port 9000)"
fi

echo ""

# Resource usage
echo "💾 Resource Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" clickhouse-oss 2>/dev/null

echo ""

# Volume information
echo "💿 Data Volumes:"
docker volume ls | grep clickhouse || echo "Volume information not found."

echo ""
echo "🔧 Management Commands:"
echo "   ./start.sh     - Start ClickHouse"
echo "   ./stop.sh      - Stop ClickHouse"
echo "   ./client.sh    - Connect to CLI client"
echo "   docker-compose logs -f  - View real-time logs"
EOF

# Create client.sh script
echo "📝 Creating client connection script..."
cat > client.sh << 'EOF'
#!/bin/bash

echo "🔌 ClickHouse Client Connection"
echo "============================"

# Check container status
if ! docker ps --format '{{.Names}}' | grep -q '^clickhouse-oss$'; then
    echo "❌ ClickHouse is not running."
    echo "   To start: ./start.sh"
    exit 1
fi

# Check service status
if ! curl -s http://localhost:8123/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse service is not responding."
    echo "   Check status: ./status.sh"
    exit 1
fi

echo "✅ Connecting..."
echo "   To exit: type 'exit' or press Ctrl+D"
echo ""

# Connect to client
docker-compose exec clickhouse clickhouse-client
EOF

# Create cleanup.sh script (for complete data deletion)
echo "📝 Creating cleanup script..."
cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 ClickHouse Complete Cleanup"
echo "======================"
echo ""
echo "⚠️  Warning: This will delete all ClickHouse data!"
echo "   - All databases"
echo "   - All tables"
echo "   - All logs"
echo ""

read -p "Are you sure you want to delete all data? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 1
fi

echo "🛑 Stopping and removing containers..."
docker-compose down -v

echo "🗑️  Removing Docker volumes..."
docker volume rm clickhouse-oss_clickhouse_data 2>/dev/null || true
docker volume rm clickhouse-oss_clickhouse_logs 2>/dev/null || true

echo "🧹 Cleaning up network..."
docker network rm clickhouse-network 2>/dev/null || true

echo "✅ Cleanup complete!"
echo ""
echo "🔄 To restart: ./start.sh"
EOF

# Create README.md
echo "📝 Creating documentation..."
cat > README.md << 'EOF'
# ClickHouse OSS Environment

ClickHouse development environment optimized for macOS.

## 🚀 Quick Start

```bash
# 1. Setup (first time only)
./setup.sh [VERSION]

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

- `./setup.sh [VERSION]` - Initial environment setup (first time only)
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
EOF

# Grant script execution permissions
echo "🔐 Setting execution permissions..."
chmod +x *.sh

# Download Docker image
echo "📥 Downloading ClickHouse image..."
docker pull clickhouse/clickhouse-server:${CLICKHOUSE_VERSION}

echo ""
echo "✅ ClickHouse OSS environment setup complete!"
echo ""
echo "🎯 Next steps:"
echo "   1. Start ClickHouse: ./start.sh"
echo "   2. Access Web UI: http://localhost:8123/play"
echo "   3. Connect CLI: ./client.sh"
echo ""
echo "📖 For more details, see README.md"
