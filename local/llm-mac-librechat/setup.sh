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

# Function to install Ollama
install_ollama() {
    print_info "Installing Ollama..."
    echo ""

    if command -v ollama &> /dev/null; then
        print_success "Ollama is already installed"
        return 0
    fi

    print_info "Ollama installation options:"
    echo "  1. Install via Homebrew (recommended)"
    echo "  2. Download from ollama.ai manually"
    echo ""

    prompt_input "Select installation method (1-2)" "1" INSTALL_METHOD

    case $INSTALL_METHOD in
        1)
            if command -v brew &> /dev/null; then
                print_info "Installing Ollama via Homebrew..."
                brew install ollama || {
                    print_error "Failed to install Ollama via Homebrew"
                    return 1
                }
                print_success "Ollama installed successfully"

                # Start Ollama service
                print_info "Starting Ollama service..."
                brew services start ollama || print_warning "Failed to start Ollama service"
                sleep 3
            else
                print_error "Homebrew is not installed"
                print_info "Please install Homebrew first: https://brew.sh"
                return 1
            fi
            ;;
        2)
            print_info "Please download and install Ollama from: https://ollama.ai"
            print_info "After installation, run './setup.sh' again"
            exit 0
            ;;
        *)
            print_error "Invalid selection"
            return 1
            ;;
    esac
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
        echo ""
        prompt_input "Do you want to install Ollama now? (yes/no)" "yes" INSTALL_OLLAMA_NOW

        if [ "$INSTALL_OLLAMA_NOW" = "yes" ] || [ "$INSTALL_OLLAMA_NOW" = "y" ]; then
            echo ""
            install_ollama

            # Check if installation was successful
            if command -v ollama &> /dev/null; then
                print_success "Ollama installed successfully"
            else
                print_error "Ollama installation failed"
                prompt_input "Do you want to continue without Ollama? (yes/no)" "no" CONTINUE_WITHOUT_OLLAMA
                if [ "$CONTINUE_WITHOUT_OLLAMA" != "yes" ] && [ "$CONTINUE_WITHOUT_OLLAMA" != "y" ]; then
                    exit 1
                fi
            fi
        else
            print_info "You can install Ollama later from: https://ollama.ai"
            prompt_input "Do you want to continue without Ollama? (yes/no)" "no" CONTINUE_WITHOUT_OLLAMA
            if [ "$CONTINUE_WITHOUT_OLLAMA" != "yes" ] && [ "$CONTINUE_WITHOUT_OLLAMA" != "y" ]; then
                exit 1
            fi
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

# Function to manually configure ClickHouse connection
configure_clickhouse_manual() {
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
}

# Function to deploy ClickHouse with Docker using oss-mac-setup
deploy_clickhouse_docker() {
    print_info "Deploying ClickHouse with Docker..."
    echo ""

    # Check if oss-mac-setup exists
    OSS_MAC_SETUP_PATH="../oss-mac-setup"
    if [ ! -d "$OSS_MAC_SETUP_PATH" ]; then
        print_error "oss-mac-setup directory not found at: $OSS_MAC_SETUP_PATH"
        print_info "Please ensure the oss-mac-setup directory exists in local/"
        return 1
    fi

    # Check if ClickHouse is already running (check for any clickhouse container)
    if docker ps | grep -q "clickhouse"; then
        print_success "ClickHouse container is already running"

        # Try to detect the port from docker ps (using sed instead of grep -P for macOS compatibility)
        CH_HTTP_PORT=$(docker ps --filter "name=clickhouse" --format "{{.Ports}}" | sed -n 's/.*0.0.0.0:\([0-9]*\)->8123.*/\1/p' | head -1)

        if [ -z "$CH_HTTP_PORT" ]; then
            # Try alternative format (without 0.0.0.0)
            CH_HTTP_PORT=$(docker ps --filter "name=clickhouse" --format "{{.Ports}}" | sed -n 's/.*:\([0-9]*\)->8123.*/\1/p' | head -1)
        fi

        if [ -z "$CH_HTTP_PORT" ]; then
            # Default to 8123 if we can't detect the port
            CH_HTTP_PORT="8123"
            print_info "Using default port 8123"
        else
            print_info "Detected ClickHouse HTTP port: $CH_HTTP_PORT"
        fi

        prompt_input "Use existing ClickHouse container? (yes/no)" "yes" USE_EXISTING
        if [ "$USE_EXISTING" = "yes" ] || [ "$USE_EXISTING" = "y" ]; then
            print_info "Using existing ClickHouse container"
            CH_HOST="localhost"
            CH_PORT="$CH_HTTP_PORT"
            CH_USER="default"
            CH_PASSWORD=""
            CH_DATABASE="default"

            # Test connection
            if curl -s "http://${CH_HOST}:${CH_PORT}/ping" > /dev/null 2>&1; then
                print_success "ClickHouse is accessible at http://${CH_HOST}:${CH_PORT}"
                return 0
            else
                print_warning "Cannot connect to ClickHouse at http://${CH_HOST}:${CH_PORT}"
                print_info "Please check the container status with: docker ps"
            fi
        else
            print_info "Stopping existing ClickHouse container..."
            (cd "$OSS_MAC_SETUP_PATH" && ./stop.sh) || print_warning "Failed to stop ClickHouse"
        fi
    fi

    # Instructions for manual setup
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "Please set up ClickHouse manually using oss-mac-setup:"
    echo ""
    echo "  1. Open a new terminal"
    echo "  2. cd ${OSS_MAC_SETUP_PATH}"
    echo "  3. Run: ./set.sh"
    echo "     (Select default options or customize as needed)"
    echo "  4. Run: ./start.sh"
    echo "  5. Come back to this terminal and press Enter to continue"
    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    read -p "Press Enter after you have started ClickHouse..."

    # Wait a bit for container to be ready
    sleep 3

    # Check if ClickHouse is now running
    if docker ps | grep -q "clickhouse"; then
        print_success "ClickHouse container detected"

        # Try to detect the port (macOS compatible)
        CH_HTTP_PORT=$(docker ps --filter "name=clickhouse" --format "{{.Ports}}" | sed -n 's/.*0.0.0.0:\([0-9]*\)->8123.*/\1/p' | head -1)

        if [ -z "$CH_HTTP_PORT" ]; then
            # Try alternative format (without 0.0.0.0)
            CH_HTTP_PORT=$(docker ps --filter "name=clickhouse" --format "{{.Ports}}" | sed -n 's/.*:\([0-9]*\)->8123.*/\1/p' | head -1)
        fi

        if [ -z "$CH_HTTP_PORT" ]; then
            CH_HTTP_PORT="8123"
        fi

        CH_HOST="localhost"
        CH_PORT="$CH_HTTP_PORT"
        CH_USER="default"
        CH_PASSWORD=""
        CH_DATABASE="default"

        # Test connection
        if curl -s "http://${CH_HOST}:${CH_PORT}/ping" > /dev/null 2>&1; then
            print_success "ClickHouse is running and accessible at http://${CH_HOST}:${CH_PORT}"
            return 0
        else
            print_warning "ClickHouse container is running but not responding"
            print_info "It may still be initializing. Please wait a moment."
            return 1
        fi
    else
        print_error "ClickHouse container not found"
        print_info "Please ensure ClickHouse is running before continuing"
        return 1
    fi
}

# Function to configure ClickHouse connection
configure_clickhouse() {
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "ClickHouse Connection Configuration"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_info "Configure ClickHouse connection for MCP server"
    echo ""

    # Ask user for deployment option
    echo "Choose ClickHouse setup option:"
    echo "  1. Auto-deploy with Docker (uses local/oss-mac-setup)"
    echo "  2. Provide existing connection string"
    echo ""

    prompt_input "Select option (1-2)" "1" CH_OPTION

    case $CH_OPTION in
        1)
            print_info "Auto-deploying ClickHouse with Docker..."
            echo ""
            if deploy_clickhouse_docker; then
                print_success "ClickHouse auto-deployment completed"
            else
                print_error "Auto-deployment failed. Please configure manually."
                # Fallback to manual configuration
                configure_clickhouse_manual
            fi
            ;;
        2)
            print_info "Configuring existing ClickHouse connection..."
            echo ""
            configure_clickhouse_manual
            ;;
        *)
            print_warning "Invalid option, using auto-deploy"
            deploy_clickhouse_docker || configure_clickhouse_manual
            ;;
    esac

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

    # Check if Ollama is installed to show appropriate menu
    OLLAMA_INSTALLED=false
    if command -v ollama &> /dev/null; then
        OLLAMA_INSTALLED=true
        print_success "Ollama is already installed"
        echo ""
    fi

    print_info "Recommended lightweight models for Mac:"
    echo "  1. Install/Reinstall Ollama"
    echo "  2. qwen2.5-coder:3b (3B) - Best for coding tasks"
    echo "  3. phi-3.5:3.8b (3.8B) - Microsoft's efficient model"
    echo "  4. gemma2:2b (2B) - Lightweight Google model"
    echo "  5. tinyllama:1.1b (1.1B) - Ultra lightweight"
    echo "  6. Custom model name"
    echo ""

    # Primary model selection (default is always 1)
    prompt_input "Select primary model (1-6)" "1" MODEL_CHOICE

    case $MODEL_CHOICE in
        1)
            install_ollama
            echo ""
            print_success "Ollama installation completed"
            print_info "You can manually pull models later using: ollama pull <model-name>"
            PRIMARY_MODEL=""
            SECONDARY_MODEL=""
            return 0
            ;;
        2) PRIMARY_MODEL="qwen2.5-coder:3b" ;;
        3) PRIMARY_MODEL="phi-3.5:3.8b" ;;
        4) PRIMARY_MODEL="gemma2:2b" ;;
        5) PRIMARY_MODEL="tinyllama:1.1b" ;;
        6)
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
        print_info "Select secondary model:"
        echo "  2. qwen2.5-coder:3b (3B) - Best for coding tasks"
        echo "  3. phi-3.5:3.8b (3.8B) - Microsoft's efficient model"
        echo "  4. gemma2:2b (2B) - Lightweight Google model"
        echo "  5. tinyllama:1.1b (1.1B) - Ultra lightweight"
        echo "  6. Custom model name"
        echo ""
        prompt_input "Select secondary model (2-6)" "3" SECONDARY_CHOICE

        case $SECONDARY_CHOICE in
            2) SECONDARY_MODEL="qwen2.5-coder:3b" ;;
            3) SECONDARY_MODEL="phi-3.5:3.8b" ;;
            4) SECONDARY_MODEL="gemma2:2b" ;;
            5) SECONDARY_MODEL="tinyllama:1.1b" ;;
            6)
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

    # Pull models if Ollama is available and models are configured
    if command -v ollama &> /dev/null && [ -n "$PRIMARY_MODEL" ]; then
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
PRIMARY_MODEL=${PRIMARY_MODEL}
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

# Main setup execution
main() {
    check_prerequisites
    configure_clickhouse
    configure_models
    configure_librechat
    save_configuration
    create_directories

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_success "Setup completed successfully!"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_info "Next step: Run './start.sh' to start all services"
    echo ""
}

main
