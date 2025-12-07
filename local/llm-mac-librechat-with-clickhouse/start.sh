#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration file
CONFIG_FILE="config.env"

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${CYAN}$1${NC}"
}

echo -e "${CYAN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║              LibreChat with Local LLM                        ║
║         Starting Services...                                 ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""

# Check if configuration exists
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Configuration file not found: $CONFIG_FILE"
    print_info "Please run './setup.sh' first to configure the system."
    exit 1
fi

# Load configuration
source "$CONFIG_FILE"

# Check if docker compose or docker-compose
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

# Start services
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Starting Services"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_info "Starting Docker Compose services..."
$DOCKER_COMPOSE --env-file "$CONFIG_FILE" up -d

echo ""
print_success "Services started!"
echo ""

# Wait for services to be ready
print_info "Waiting for services to be ready..."
echo ""

# Wait for MongoDB
print_info "Checking MongoDB..."
for i in {1..30}; do
    if docker exec librechat-mongodb mongosh --eval "db.adminCommand('ping')" &> /dev/null; then
        print_success "MongoDB is ready"
        break
    fi
    sleep 2
done

# Wait for MCP Server
print_info "Checking ClickHouse MCP Server..."
for i in {1..30}; do
    if curl -s http://localhost:${MCP_SERVER_PORT:-3001}/health &> /dev/null; then
        print_success "MCP Server is ready"
        break
    fi
    sleep 2
done

# Wait for LibreChat
print_info "Checking LibreChat..."
for i in {1..30}; do
    if curl -s http://localhost:${LIBRECHAT_PORT:-3080}/api/health &> /dev/null; then
        print_success "LibreChat is ready"
        break
    fi
    sleep 2
done

echo ""

# Show endpoints
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_header "Service Endpoints"
print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo -e "${YELLOW}LibreChat:${NC}"
echo "  URL: http://localhost:${LIBRECHAT_PORT:-3080}"
echo "  Create an account on first visit"
echo ""

echo -e "${YELLOW}Local LLM Models (Ollama):${NC}"
echo "  Primary: ${PRIMARY_MODEL:-qwen2.5-coder:3b}"
if [ -n "$SECONDARY_MODEL" ]; then
    echo "  Secondary: ${SECONDARY_MODEL}"
fi
echo "  Ollama API: http://localhost:11434"
echo ""

echo -e "${YELLOW}ClickHouse MCP Server:${NC}"
echo "  Host: ${CH_HOST:-localhost}:${CH_PORT:-8123}"
echo "  Database: ${CH_DATABASE:-default}"
echo "  MCP Port: ${MCP_SERVER_PORT:-3001}"
echo ""

print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_info "Next Steps:"
echo "  1. Open LibreChat: http://localhost:${LIBRECHAT_PORT:-3080}"
echo "  2. Create an account"
echo "  3. Select your local model from the dropdown"
echo "  4. Start chatting with ClickHouse data access via MCP!"
echo ""

print_info "Useful commands:"
echo "  ./stop.sh          - Stop all services"
echo "  ./restart.sh       - Restart all services"
echo "  ./logs.sh          - View logs"
echo "  ./status.sh        - Check service status"
echo ""
