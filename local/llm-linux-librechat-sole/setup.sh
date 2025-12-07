#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Print functions
print_header() {
    echo -e "${CYAN}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Prompt for input with default value
prompt_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    if [ -n "$default" ]; then
        read -p "$(echo -e ${CYAN}${prompt}${NC} [${default}]: )" input
        eval $var_name="\${input:-$default}"
    else
        read -p "$(echo -e ${CYAN}${prompt}${NC}: )" input
        eval $var_name="\$input"
    fi
}

# Generate random secrets
generate_secret() {
    openssl rand -hex "$1"
}

# Check if Docker is installed
check_docker() {
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Checking Docker Installation"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        print_info "Please install Docker from: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        print_info "Please start Docker and try again"
        exit 1
    fi

    print_success "Docker is installed and running"
    echo ""
}

# Check if Ollama is installed
check_ollama() {
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Checking Ollama Installation"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if ! command -v ollama &> /dev/null; then
        print_warning "Ollama is not installed"
        print_info "Please install Ollama from: https://ollama.ai/download"
        echo ""
        prompt_input "Continue without Ollama? (yes/no)" "no" CONTINUE
        if [ "$CONTINUE" != "yes" ] && [ "$CONTINUE" != "y" ]; then
            exit 1
        fi
    else
        print_success "Ollama is installed"

        # Check if llama3.1:8b is available
        if ollama list | grep -q "llama3.1:8b"; then
            print_success "llama3.1:8b model is already available"
        else
            print_warning "llama3.1:8b model is not downloaded"
            prompt_input "Pull llama3.1:8b now? (yes/no)" "yes" PULL_MODEL
            if [ "$PULL_MODEL" = "yes" ] || [ "$PULL_MODEL" = "y" ]; then
                print_info "Pulling llama3.1:8b (4.9GB)..."
                ollama pull llama3.1:8b || print_warning "Failed to pull llama3.1:8b"
            fi
        fi
    fi
    echo ""
}

# Create .env file
create_env_file() {
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Creating Environment Configuration"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ -f .env ]; then
        print_warning ".env file already exists"
        prompt_input "Overwrite? (yes/no)" "no" OVERWRITE
        if [ "$OVERWRITE" != "yes" ] && [ "$OVERWRITE" != "y" ]; then
            print_info "Keeping existing .env file"
            echo ""
            return 0
        fi
    fi

    print_info "Generating security secrets..."

    # Generate secrets
    SESSION_SECRET=$(generate_secret 32)
    JWT_SECRET=$(generate_secret 32)
    JWT_REFRESH_SECRET=$(generate_secret 32)
    CREDS_KEY=$(generate_secret 32)
    CREDS_IV=$(generate_secret 16)

    # Prompt for LibreChat port
    prompt_input "LibreChat port" "3080" LIBRECHAT_PORT

    # Create .env file
    cat > .env << EOF
# LibreChat Configuration
LIBRECHAT_PORT=${LIBRECHAT_PORT}

# Security secrets (auto-generated)
SESSION_SECRET=${SESSION_SECRET}
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}

# Encryption keys for v0.7.6+ (auto-generated)
CREDS_KEY=${CREDS_KEY}
CREDS_IV=${CREDS_IV}

# Ollama Settings
OLLAMA_BASE_URL=http://host.docker.internal:11434
PRIMARY_MODEL=llama3.1:8b
EOF

    print_success ".env file created successfully"
    echo ""
}

# Start services
start_services() {
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Starting LibreChat Services"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_info "Starting containers..."
    docker-compose up -d

    if [ $? -eq 0 ]; then
        print_success "Services started successfully"
        echo ""
        print_info "LibreChat is available at: http://localhost:${LIBRECHAT_PORT}"
        print_info "MongoDB is running (internal only)"
        echo ""
        print_warning "Note: Please wait ~30 seconds for services to fully initialize"
    else
        print_error "Failed to start services"
        exit 1
    fi
    echo ""
}

# Show MCP configuration guide
show_mcp_guide() {
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "MCP Server Configuration Guide"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_info "To enable MCP servers, edit librechat.yaml and uncomment the mcpServers section"
    echo ""
    echo -e "${YELLOW}Example configuration:${NC}"
    echo ""
    cat << 'EOF'
mcpServers:
  clickhouse:
    type: streamable-http
    url: http://mcp-clickhouse-server:3001/mcp
    timeout: 30000
EOF
    echo ""
    print_info "After editing, restart LibreChat with: ./restart.sh"
    echo ""
}

# Main setup
main() {
    clear
    print_header "╔══════════════════════════════════════════════════════════════════╗"
    print_header "║         LibreChat Standalone Setup (Linux Edition)              ║"
    print_header "║                    with Ollama LLM                               ║"
    print_header "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    # Check prerequisites
    check_docker
    check_ollama

    # Create configuration
    create_env_file

    # Start services
    start_services

    # Show MCP guide
    show_mcp_guide

    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Setup Complete!"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_success "LibreChat is running at: http://localhost:${LIBRECHAT_PORT}"
    echo ""
    print_info "Useful commands:"
    echo -e "  ${CYAN}./start.sh${NC}    - Start services"
    echo -e "  ${CYAN}./stop.sh${NC}     - Stop services"
    echo -e "  ${CYAN}./restart.sh${NC}  - Restart services"
    echo -e "  ${CYAN}./logs.sh${NC}     - View logs"
    echo -e "  ${CYAN}./status.sh${NC}   - Check status"
    echo ""
}

main
