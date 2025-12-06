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
CREDENTIALS_FILE=".credentials"

echo -e "${CYAN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║              LibreChat with Local LLM Setup                  ║
║         ClickHouse MCP Server + Ollama Integration           ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""

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

# Function to prompt for input with default value
prompt_input() {
    local prompt_text=$1
    local default_value=$2
    local var_name=$3

    if [ -n "$default_value" ]; then
        read -p "$(echo -e ${BLUE}${prompt_text}${NC} [${default_value}]: )" input_value
        input_value=${input_value:-$default_value}
    else
        read -p "$(echo -e ${BLUE}${prompt_text}${NC}: )" input_value
    fi

    eval "$var_name='$input_value'"
}

# Function to prompt for password (hidden input)
prompt_password() {
    local prompt_text=$1
    local var_name=$2

    read -s -p "$(echo -e ${BLUE}${prompt_text}${NC}: )" input_value
    echo
    eval "$var_name='$input_value'"
}

# Function to check prerequisites
check_prerequisites() {
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Checking Prerequisites"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        print_info "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
    print_success "Docker is installed"

    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed."
        exit 1
    fi
    print_success "Docker Compose is installed"

    # Check Ollama
    if ! command -v ollama &> /dev/null; then
        print_warning "Ollama is not installed."
        print_info "Ollama is required for local LLM models."
        print_info "Visit: https://ollama.ai"
        echo ""
        prompt_input "Do you want to continue without Ollama? (yes/no)" "no" CONTINUE_WITHOUT_OLLAMA
        if [ "$CONTINUE_WITHOUT_OLLAMA" != "yes" ] && [ "$CONTINUE_WITHOUT_OLLAMA" != "y" ]; then
            exit 1
        fi
    else
        print_success "Ollama is installed"

        # Check if Ollama is running
        if ! ollama list &> /dev/null; then
            print_warning "Ollama is not running. Please start Ollama."
            print_info "Run: ollama serve"
        fi
    fi

    echo ""
}

# Function to configure ClickHouse connection
configure_clickhouse() {
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "ClickHouse Connection Configuration"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_info "Configure ClickHouse connection for MCP server"
    echo ""

    # ClickHouse Host
    prompt_input "ClickHouse Host" "localhost" CH_HOST

    # ClickHouse Port
    prompt_input "ClickHouse Port" "8123" CH_PORT

    # ClickHouse User
    prompt_input "ClickHouse User" "default" CH_USER

    # ClickHouse Password
    prompt_password "ClickHouse Password (leave empty if none)" CH_PASSWORD

    # ClickHouse Database
    prompt_input "ClickHouse Database (optional)" "default" CH_DATABASE

    echo ""
    print_success "ClickHouse configuration completed"
    echo ""

    # Save credentials
    cat > "$CREDENTIALS_FILE" << EOF
# ClickHouse MCP Server Configuration
# Generated: $(date)
# DO NOT COMMIT THIS FILE TO VERSION CONTROL

CH_HOST=${CH_HOST}
CH_PORT=${CH_PORT}
CH_USER=${CH_USER}
CH_PASSWORD=${CH_PASSWORD}
CH_DATABASE=${CH_DATABASE}
EOF

    chmod 600 "$CREDENTIALS_FILE"
    print_success "Credentials saved to: $CREDENTIALS_FILE"

    # Add to .gitignore
    if [ ! -f "${SCRIPT_DIR}/.gitignore" ]; then
        echo ".credentials" > "${SCRIPT_DIR}/.gitignore"
        echo "config.env" >> "${SCRIPT_DIR}/.gitignore"
        echo ".env" >> "${SCRIPT_DIR}/.gitignore"
        print_success ".gitignore created"
    fi

    echo ""
}

# Function to configure LLM models
configure_models() {
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Local LLM Model Configuration"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_info "Recommended lightweight models for Mac:"
    echo "  1. qwen2.5-coder:3b (3B) - Best for coding tasks"
    echo "  2. phi-3.5:3.8b (3.8B) - Microsoft's efficient model"
    echo "  3. gemma2:2b (2B) - Lightweight Google model"
    echo "  4. tinyllama:1.1b (1.1B) - Ultra lightweight"
    echo "  5. Custom model name"
    echo ""

    # Primary model selection
    prompt_input "Select primary model (1-5)" "1" MODEL_CHOICE

    case $MODEL_CHOICE in
        1) PRIMARY_MODEL="qwen2.5-coder:3b" ;;
        2) PRIMARY_MODEL="phi-3.5:3.8b" ;;
        3) PRIMARY_MODEL="gemma2:2b" ;;
        4) PRIMARY_MODEL="tinyllama:1.1b" ;;
        5)
            prompt_input "Enter custom model name" "" PRIMARY_MODEL
            ;;
        *)
            print_warning "Invalid selection, using qwen2.5-coder:3b as default"
            PRIMARY_MODEL="qwen2.5-coder:3b"
            ;;
    esac

    print_success "Primary model: ${PRIMARY_MODEL}"
    echo ""

    # Optional secondary model
    prompt_input "Add a secondary model? (yes/no)" "no" ADD_SECONDARY
    if [ "$ADD_SECONDARY" = "yes" ] || [ "$ADD_SECONDARY" = "y" ]; then
        echo ""
        prompt_input "Select secondary model (1-5)" "2" SECONDARY_CHOICE

        case $SECONDARY_CHOICE in
            1) SECONDARY_MODEL="qwen2.5-coder:3b" ;;
            2) SECONDARY_MODEL="phi-3.5:3.8b" ;;
            3) SECONDARY_MODEL="gemma2:2b" ;;
            4) SECONDARY_MODEL="tinyllama:1.1b" ;;
            5)
                prompt_input "Enter custom model name" "" SECONDARY_MODEL
                ;;
            *)
                SECONDARY_MODEL="phi-3.5:3.8b"
                ;;
        esac
        print_success "Secondary model: ${SECONDARY_MODEL}"
    else
        SECONDARY_MODEL=""
    fi

    echo ""

    # Pull models if Ollama is available
    if command -v ollama &> /dev/null; then
        prompt_input "Pull models now? (yes/no)" "yes" PULL_MODELS
        if [ "$PULL_MODELS" = "yes" ] || [ "$PULL_MODELS" = "y" ]; then
            echo ""
            print_info "Pulling ${PRIMARY_MODEL}..."
            ollama pull "$PRIMARY_MODEL" || print_warning "Failed to pull ${PRIMARY_MODEL}"

            if [ -n "$SECONDARY_MODEL" ]; then
                print_info "Pulling ${SECONDARY_MODEL}..."
                ollama pull "$SECONDARY_MODEL" || print_warning "Failed to pull ${SECONDARY_MODEL}"
            fi
            print_success "Model pulling completed"
        fi
    fi

    echo ""
}

# Function to configure LibreChat
configure_librechat() {
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "LibreChat Configuration"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # LibreChat port
    prompt_input "LibreChat Port" "3080" LIBRECHAT_PORT

    # Generate session secret
    SESSION_SECRET=$(openssl rand -hex 32)

    echo ""
    print_success "LibreChat configuration completed"
    echo ""
}

# Function to save configuration
save_configuration() {
    print_info "Saving configuration..."

    # Source credentials if exists
    if [ -f "$CREDENTIALS_FILE" ]; then
        source "$CREDENTIALS_FILE"
    fi

    cat > "$CONFIG_FILE" << EOF
# LibreChat Configuration
# Generated: $(date)

# LibreChat Settings
LIBRECHAT_PORT=${LIBRECHAT_PORT:-3080}
SESSION_SECRET=${SESSION_SECRET}

# Ollama Settings
OLLAMA_BASE_URL=http://host.docker.internal:11434
PRIMARY_MODEL=${PRIMARY_MODEL:-qwen2.5-coder:3b}
SECONDARY_MODEL=${SECONDARY_MODEL}

# ClickHouse MCP Server Settings
CH_HOST=${CH_HOST:-localhost}
CH_PORT=${CH_PORT:-8123}
CH_USER=${CH_USER:-default}
CH_PASSWORD=${CH_PASSWORD}
CH_DATABASE=${CH_DATABASE:-default}

# MCP Server Port
MCP_SERVER_PORT=3001
EOF

    chmod 644 "$CONFIG_FILE"
    print_success "Configuration saved to: $CONFIG_FILE"
    echo ""
}

# Function to create directories
create_directories() {
    print_info "Creating directory structure..."

    mkdir -p librechat-data
    mkdir -p mcp-server
    mkdir -p ollama-models

    print_success "Directories created"
    echo ""
}

# Function to start services
start_services() {
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "Starting Services"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check if docker compose or docker-compose
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        DOCKER_COMPOSE="docker-compose"
    fi

    print_info "Starting services with Docker Compose..."
    $DOCKER_COMPOSE --env-file "$CONFIG_FILE" up -d

    echo ""
    print_success "Services started!"
    echo ""

    # Wait for services
    print_info "Waiting for services to be ready..."
    sleep 10

    echo ""
}

# Function to show endpoints
show_endpoints() {
    source "$CONFIG_FILE"

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
}

# Main execution
main() {
    case "${1:-}" in
        --configure)
            check_prerequisites
            configure_clickhouse
            configure_models
            configure_librechat
            save_configuration
            create_directories
            print_success "Configuration complete! Run './setup.sh --start' to start services."
            ;;
        --start)
            if [ ! -f "$CONFIG_FILE" ]; then
                print_error "Configuration not found. Run './setup.sh --configure' first."
                exit 1
            fi
            start_services
            show_endpoints
            ;;
        --stop)
            if docker compose version &> /dev/null; then
                docker compose down
            else
                docker-compose down
            fi
            print_success "Services stopped"
            ;;
        --restart)
            $0 --stop
            sleep 3
            $0 --start
            ;;
        --status)
            docker ps --filter "name=librechat" --filter "name=mcp-server" --filter "name=mongo"
            ;;
        --logs)
            if docker compose version &> /dev/null; then
                docker compose logs -f
            else
                docker-compose logs -f
            fi
            ;;
        --clean)
            print_warning "This will remove all data including chat history!"
            prompt_input "Continue? (yes/no)" "no" CONFIRM_CLEAN
            if [ "$CONFIRM_CLEAN" = "yes" ] || [ "$CONFIRM_CLEAN" = "y" ]; then
                if docker compose version &> /dev/null; then
                    docker compose down -v
                else
                    docker-compose down -v
                fi
                rm -rf librechat-data/*
                print_success "Cleanup complete"
            fi
            ;;
        --endpoints)
            show_endpoints
            ;;
        *)
            echo "Usage: $0 [OPTION]"
            echo ""
            echo "Options:"
            echo "  --configure    Configure the setup interactively"
            echo "  --start        Start all services"
            echo "  --stop         Stop all services"
            echo "  --restart      Restart all services"
            echo "  --status       Show running services"
            echo "  --logs         Show service logs"
            echo "  --clean        Stop services and remove all data"
            echo "  --endpoints    Show service endpoints"
            echo ""
            echo "Quick Start:"
            echo "  1. ./setup.sh --configure"
            echo "  2. ./setup.sh --start"
            echo ""
            exit 1
            ;;
    esac
}

main "$@"
