#!/bin/bash

#################################################
# TPC-DS Environment Setup Script
# Enhanced parameter-by-parameter configuration
#################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

# Default values
DEFAULT_HOST="localhost"
DEFAULT_PORT="9000"
DEFAULT_HTTP_PORT="8123"
DEFAULT_USER="default"
DEFAULT_PASSWORD=""
DEFAULT_DATABASE="tpcds"
DEFAULT_SCALE_FACTOR="1"
DEFAULT_PARALLEL_JOBS="4"
DEFAULT_S3_BUCKET=""

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Generate config.sh with ClickHouse connection parameters.
Enhanced interactive mode with options and examples for each parameter.

OPTIONS:
    -h, --host HOST           ClickHouse host (default: $DEFAULT_HOST)
    -p, --port PORT           ClickHouse native port (default: $DEFAULT_PORT)
    --http-port PORT          ClickHouse HTTP port (default: $DEFAULT_HTTP_PORT)
    -u, --user USER           ClickHouse user (default: $DEFAULT_USER)
    -P, --password PASSWORD   ClickHouse password (prompted interactively)
    -d, --database DATABASE   Database name (default: $DEFAULT_DATABASE)
    -s, --scale-factor N      Data scale factor (default: $DEFAULT_SCALE_FACTOR)
    -j, --parallel N          Parallel jobs (default: $DEFAULT_PARALLEL_JOBS)
    --s3-bucket URL          S3 bucket URL (default: Tokyo bucket)
    --interactive            Interactive mode - prompt for each parameter
    --docker                 Use Docker container settings
    --non-interactive        Non-interactive mode - use CLI args only
    --help                   Show this help message

INTERACTIVE MODE (Default):
    Enhanced interactive mode with:
    - Current value display
    - Available options and examples
    - Value validation and suggestions
    - Confirmation for each change
    - Secure password handling (never stored)

EXAMPLES:
    # Interactive mode (default - enhanced with options/examples)
    $0

    # Non-interactive mode with CLI arguments
    $0 --non-interactive --host 10.0.1.100 --port 9000 --user admin

    # Docker mode
    $0 --docker

EOF
    exit 1
}

# Function to read existing config values
read_existing_config() {
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${GREEN}✓ Found existing config.sh${NC}"
        echo ""

        # Extract existing values
        EXISTING_HOST=$(grep '^export CLICKHOUSE_HOST=' "$CONFIG_FILE" | cut -d'"' -f2)
        EXISTING_PORT=$(grep '^export CLICKHOUSE_PORT=' "$CONFIG_FILE" | cut -d'"' -f2)
        EXISTING_HTTP_PORT=$(grep '^export CLICKHOUSE_HTTP_PORT=' "$CONFIG_FILE" | cut -d'"' -f2)
        EXISTING_USER=$(grep '^export CLICKHOUSE_USER=' "$CONFIG_FILE" | cut -d'"' -f2)
        EXISTING_DATABASE=$(grep '^export CLICKHOUSE_DATABASE=' "$CONFIG_FILE" | cut -d'"' -f2)
        EXISTING_SCALE_FACTOR=$(grep '^export SCALE_FACTOR=' "$CONFIG_FILE" | cut -d'"' -f2)
        EXISTING_PARALLEL_JOBS=$(grep '^export PARALLEL_JOBS=' "$CONFIG_FILE" | cut -d'"' -f2)
        EXISTING_S3_BUCKET=$(grep '^export S3_BUCKET=' "$CONFIG_FILE" | cut -d'"' -f2)

        # Set defaults from existing config
        DEFAULT_HOST=${EXISTING_HOST:-$DEFAULT_HOST}
        DEFAULT_PORT=${EXISTING_PORT:-$DEFAULT_PORT}
        DEFAULT_HTTP_PORT=${EXISTING_HTTP_PORT:-$DEFAULT_HTTP_PORT}
        DEFAULT_USER=${EXISTING_USER:-$DEFAULT_USER}
        DEFAULT_DATABASE=${EXISTING_DATABASE:-$DEFAULT_DATABASE}
        DEFAULT_SCALE_FACTOR=${EXISTING_SCALE_FACTOR:-$DEFAULT_SCALE_FACTOR}
        DEFAULT_PARALLEL_JOBS=${EXISTING_PARALLEL_JOBS:-$DEFAULT_PARALLEL_JOBS}
        DEFAULT_S3_BUCKET=${EXISTING_S3_BUCKET:-$DEFAULT_S3_BUCKET}

        return 0
    else
        echo -e "${YELLOW}No existing config.sh found. Creating new configuration.${NC}"
        echo ""
        return 1
    fi
}

# Enhanced prompt function with options and examples
prompt_parameter() {
    local param_num="$1"
    local param_name="$2"
    local param_description="$3"
    local current_value="$4"
    local options="$5"
    local examples="$6"
    local is_secret="$7"
    local validation_hint="$8"

    # Display parameter header (to stderr so it's not captured)
    echo "" >&2
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${BLUE}║${NC} ${BOLD}Parameter ${param_num}: ${YELLOW}${param_description}${NC}" >&2
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}" >&2
    echo "" >&2

    if [ "$is_secret" = "true" ]; then
        # Password handling
        echo -e "${RED}⚠  SECURITY: Password will NOT be stored in config.sh${NC}" >&2
        echo -e "${YELLOW}   Passwords must be set via environment variable at runtime:${NC}" >&2
        echo -e "${CYAN}   export CLICKHOUSE_PASSWORD='your-password'${NC}" >&2
        echo "" >&2
        echo -e "${YELLOW}For connection testing only:${NC}" >&2
        echo "" >&2

        read -s -p "Enter password (or press Enter to skip): " new_value
        echo "" >&2

        if [ -n "$new_value" ]; then
            read -s -p "Confirm password: " confirm_value
            echo "" >&2

            if [ "$new_value" != "$confirm_value" ]; then
                echo -e "${RED}✗ Passwords don't match. Skipping.${NC}" >&2
                new_value=""
            else
                echo -e "${GREEN}✓ Password confirmed (for testing only)${NC}" >&2
            fi
        else
            echo -e "${YELLOW}⊘ Skipped (will need to set at runtime)${NC}" >&2
        fi
    else
        # Regular parameter handling
        echo -e "${CYAN}Current value:${NC} ${GREEN}${current_value}${NC}" >&2
        echo "" >&2

        if [ -n "$options" ]; then
            echo -e "${CYAN}Available options:${NC}" >&2
            echo -e "${options}" >&2
            echo "" >&2
        fi

        if [ -n "$examples" ]; then
            echo -e "${CYAN}Examples:${NC}" >&2
            echo -e "${examples}" >&2
            echo "" >&2
        fi

        if [ -n "$validation_hint" ]; then
            echo -e "${YELLOW}Note:${NC} ${validation_hint}" >&2
            echo "" >&2
        fi

        echo -e "${BOLD}Options:${NC}" >&2
        echo -e "  ${GREEN}[Enter]${NC}  Keep current value: ${GREEN}${current_value}${NC}" >&2
        echo -e "  ${YELLOW}[New value]${NC}  Enter new value to replace current" >&2
        echo "" >&2

        # Read user input
        read -p "Your choice: " user_input

        if [ -z "$user_input" ]; then
            # Keep current
            echo "" >&2
            echo -e "  ${GREEN}✓ Keeping current value: ${BOLD}${current_value}${NC}" >&2
            echo "" >&2
            new_value=""
        else
            # New value entered
            echo "" >&2
            echo -e "${YELLOW}New value entered:${NC} ${BOLD}${user_input}${NC}" >&2
            read -p "Confirm this value? (Y/n): " confirm

            if [[ "$confirm" =~ ^[Nn]$ ]]; then
                echo -e "  ${YELLOW}⊘ Cancelled, keeping: ${BOLD}${current_value}${NC}" >&2
                echo "" >&2
                new_value=""
            else
                echo -e "  ${GREEN}✓ Confirmed new value: ${BOLD}${user_input}${NC}" >&2
                echo "" >&2
                new_value="$user_input"
            fi
        fi
    fi

    # Only output the result value to stdout
    echo "$new_value"
}

# Function to show parameter result
show_param_result() {
    local param_name="$1"
    local param_value="$2"
    echo -e "${BLUE}→ ${param_name}: ${BOLD}${param_value}${NC}"
    echo ""
    sleep 0.3
}

# Parse arguments
INTERACTIVE=true
NON_INTERACTIVE=false
DOCKER=false
HOST=""
PORT=""
HTTP_PORT=""
USER=""
PASSWORD=""
DATABASE=""
SCALE_FACTOR=""
PARALLEL_JOBS=""
S3_BUCKET=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            HOST="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        --http-port)
            HTTP_PORT="$2"
            shift 2
            ;;
        -u|--user)
            USER="$2"
            shift 2
            ;;
        -P|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -d|--database)
            DATABASE="$2"
            shift 2
            ;;
        -s|--scale-factor)
            SCALE_FACTOR="$2"
            shift 2
            ;;
        -j|--parallel)
            PARALLEL_JOBS="$2"
            shift 2
            ;;
        --s3-bucket)
            S3_BUCKET="$2"
            shift 2
            ;;
        --interactive)
            INTERACTIVE=true
            NON_INTERACTIVE=false
            shift
            ;;
        --non-interactive)
            INTERACTIVE=false
            NON_INTERACTIVE=true
            shift
            ;;
        --docker)
            DOCKER=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Read existing config if in interactive mode
if [ "$INTERACTIVE" = true ] && [ "$NON_INTERACTIVE" = false ]; then
    read_existing_config || true
fi

# Header (don't clear screen in interactive mode to preserve context)
if [ "$INTERACTIVE" = false ]; then
    clear
fi
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                                  ║${NC}"
echo -e "${GREEN}║           ${BOLD}TPC-DS Benchmark Configuration Setup${NC}${GREEN}                ║${NC}"
echo -e "${GREEN}║                                                                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Docker mode
if [ "$DOCKER" = true ]; then
    echo -e "${BLUE}🐋 Docker Mode: Using container-optimized settings${NC}"
    HOST=${HOST:-"clickhouse-server"}
    PORT=${PORT:-"9000"}
    HTTP_PORT=${HTTP_PORT:-"8123"}
    USER=${USER:-"default"}
    PASSWORD=${PASSWORD:-""}
    DATABASE=${DATABASE:-"tpcds"}
    SCALE_FACTOR=${SCALE_FACTOR:-"1"}
    PARALLEL_JOBS=${PARALLEL_JOBS:-"4"}
    S3_BUCKET=${S3_BUCKET:-"$DEFAULT_S3_BUCKET"}
    INTERACTIVE=false
fi

# Interactive mode - prompt for each parameter with enhanced UI
if [ "$INTERACTIVE" = true ] && [ "$DOCKER" = false ]; then
    echo -e "${CYAN}${BOLD}Interactive Configuration Mode${NC}"
    echo -e "${CYAN}Configure each parameter step-by-step with guidance and examples.${NC}"
    echo ""
    echo -e "${YELLOW}For each parameter:${NC}"
    echo -e "  • Current value and available options will be shown"
    echo -e "  • Press ${GREEN}Enter${NC} to keep current value"
    echo -e "  • Type a ${YELLOW}new value${NC} to change it"
    echo ""
    read -p "Press Enter to start..." start_confirm
    echo ""

    # Parameter 1: Host
    if [ -z "$HOST" ]; then
        OPTIONS="  • ${GREEN}localhost${NC}       - Local ClickHouse instance
  • ${GREEN}127.0.0.1${NC}       - Local via IP
  • ${GREEN}clickhouse-server${NC} - Docker container name
  • ${GREEN}10.x.x.x${NC}        - Remote server IP
  • ${GREEN}hostname.domain${NC} - Remote server hostname"

        EXAMPLES="  ${CYAN}localhost${NC}              (development)
  ${CYAN}clickhouse.mycompany.com${NC} (production)
  ${CYAN}10.0.1.100${NC}            (internal network)"

        new_host=$(prompt_parameter "1/8" "CLICKHOUSE_HOST" "ClickHouse Server Host" \
            "$DEFAULT_HOST" "$OPTIONS" "$EXAMPLES" "false" \
            "Use 'localhost' for local development, IP/hostname for remote")
        HOST=${new_host:-$DEFAULT_HOST}
        show_param_result "Host" "$HOST"
    fi

    # Parameter 2: Native Port
    if [ -z "$PORT" ]; then
        OPTIONS="  • ${GREEN}9000${NC}  - Default ClickHouse native protocol port
  • ${GREEN}9440${NC}  - Default secure native protocol port (TLS)"

        EXAMPLES="  ${CYAN}9000${NC}  (standard, most common)
  ${CYAN}9440${NC}  (with TLS encryption)"

        new_port=$(prompt_parameter "2/8" "CLICKHOUSE_PORT" "ClickHouse Native Protocol Port" \
            "$DEFAULT_PORT" "$OPTIONS" "$EXAMPLES" "false" \
            "Port 9000 is standard for non-TLS connections")
        PORT=${new_port:-$DEFAULT_PORT}
        show_param_result "Native Port" "$PORT"
    fi

    # Parameter 3: HTTP Port
    if [ -z "$HTTP_PORT" ]; then
        OPTIONS="  • ${GREEN}8123${NC}  - Default HTTP interface port
  • ${GREEN}8443${NC}  - Default HTTPS interface port (TLS)"

        EXAMPLES="  ${CYAN}8123${NC}  (standard HTTP)
  ${CYAN}8443${NC}  (HTTPS with TLS)"

        new_http_port=$(prompt_parameter "3/8" "CLICKHOUSE_HTTP_PORT" "ClickHouse HTTP Interface Port" \
            "$DEFAULT_HTTP_PORT" "$OPTIONS" "$EXAMPLES" "false" \
            "HTTP port is used for web interface and some tools")
        HTTP_PORT=${new_http_port:-$DEFAULT_HTTP_PORT}
        show_param_result "HTTP Port" "$HTTP_PORT"
    fi

    # Parameter 4: User
    if [ -z "$USER" ]; then
        OPTIONS="  • ${GREEN}default${NC}  - Default ClickHouse user (no password by default)
  • ${GREEN}admin${NC}    - Common admin user
  • ${GREEN}readonly${NC} - Read-only user (if configured)
  • ${GREEN}custom${NC}   - Your custom username"

        EXAMPLES="  ${CYAN}default${NC}       (standard user)
  ${CYAN}benchmark_user${NC} (dedicated benchmark account)
  ${CYAN}readonly${NC}      (for query-only access)"

        new_user=$(prompt_parameter "4/8" "CLICKHOUSE_USER" "ClickHouse Username" \
            "$DEFAULT_USER" "$OPTIONS" "$EXAMPLES" "false" \
            "Use 'default' for standard setup, or your custom user")
        USER=${new_user:-$DEFAULT_USER}
        show_param_result "Username" "$USER"
    fi

    # Parameter 5: Password (always prompt, never store)
    echo ""
    password_result=$(prompt_parameter "5/8" "CLICKHOUSE_PASSWORD" "ClickHouse Password" \
        "" "" "" "true" "")
    PASSWORD="$password_result"
    if [ -n "$PASSWORD" ]; then
        show_param_result "Password" "***provided (for testing)***"
    else
        show_param_result "Password" "***skipped (set at runtime)***"
    fi

    # Parameter 6: Database
    if [ -z "$DATABASE" ]; then
        OPTIONS="  • ${GREEN}tpcds${NC}         - Default TPC-DS database name
  • ${GREEN}tpcds_dev${NC}     - Development environment
  • ${GREEN}tpcds_prod${NC}    - Production environment
  • ${GREEN}tpcds_100gb${NC}   - Database with specific scale
  • ${GREEN}custom_name${NC}   - Your custom database name"

        EXAMPLES="  ${CYAN}tpcds${NC}           (standard)
  ${CYAN}tpcds_test_sf10${NC}  (test with scale factor 10)
  ${CYAN}benchmark_db${NC}     (custom name)"

        new_database=$(prompt_parameter "6/8" "CLICKHOUSE_DATABASE" "Database Name" \
            "$DEFAULT_DATABASE" "$OPTIONS" "$EXAMPLES" "false" \
            "Database will be created if it doesn't exist")
        DATABASE=${new_database:-$DEFAULT_DATABASE}
        show_param_result "Database" "$DATABASE"
    fi

    # Parameter 7: Scale Factor
    if [ -z "$SCALE_FACTOR" ]; then
        OPTIONS="  • ${GREEN}1${NC}     ~1 GB    - Quick testing, CI/CD (minutes)
  • ${GREEN}10${NC}    ~10 GB   - Small benchmark (30min - 1hr)
  • ${GREEN}100${NC}   ~100 GB  - Medium benchmark (hours)
  • ${GREEN}1000${NC}  ~1 TB    - Large benchmark (many hours)
  • ${GREEN}10000${NC} ~10 TB   - Enterprise benchmark (days)"

        EXAMPLES="  ${CYAN}1${NC}     (development and testing)
  ${CYAN}10${NC}    (realistic small-scale benchmark)
  ${CYAN}100${NC}   (production-like benchmark)"

        new_scale=$(prompt_parameter "7/8" "SCALE_FACTOR" "TPC-DS Scale Factor (Data Size)" \
            "$DEFAULT_SCALE_FACTOR" "$OPTIONS" "$EXAMPLES" "false" \
            "Larger scale = more data = longer generation & load time")
        SCALE_FACTOR=${new_scale:-$DEFAULT_SCALE_FACTOR}
        show_param_result "Scale Factor" "$SCALE_FACTOR (~${SCALE_FACTOR}GB)"
    fi

    # Parameter 8: Parallel Jobs
    if [ -z "$PARALLEL_JOBS" ]; then
        OPTIONS="  • ${GREEN}1${NC}   - Sequential (slowest, lowest resource usage)
  • ${GREEN}2${NC}   - Light parallel
  • ${GREEN}4${NC}   - Moderate parallel (recommended for most systems)
  • ${GREEN}8${NC}   - Heavy parallel (8+ core systems)
  • ${GREEN}16${NC}  - Maximum parallel (16+ core systems)
  • ${GREEN}32${NC}  - Extreme parallel (high-end servers)"

        EXAMPLES="  ${CYAN}4${NC}   (laptop/desktop with 4-8 cores)
  ${CYAN}8${NC}   (workstation with 8-16 cores)
  ${CYAN}16${NC}  (server with 16+ cores)"

        CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "unknown")
        HINT="System CPUs detected: ${CPU_CORES}. Recommended: 50-100% of CPU count"

        new_parallel=$(prompt_parameter "8/8" "PARALLEL_JOBS" "Number of Parallel Query Streams" \
            "$DEFAULT_PARALLEL_JOBS" "$OPTIONS" "$EXAMPLES" "false" \
            "$HINT")
        PARALLEL_JOBS=${new_parallel:-$DEFAULT_PARALLEL_JOBS}
        show_param_result "Parallel Jobs" "$PARALLEL_JOBS"
    fi

    # S3 Bucket (advanced, keep current or use default)
    if [ -z "$S3_BUCKET" ]; then
        echo ""
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║${NC} ${BOLD}Advanced: S3 Data Source${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYAN}Current S3 bucket:${NC} ${GREEN}${DEFAULT_S3_BUCKET}${NC}"
        echo ""
        echo -e "${CYAN}This is for loading pre-generated TPC-DS data from S3.${NC}"
        echo -e "${CYAN}Default Tokyo bucket is usually fine for most users.${NC}"
        echo ""
        read -p "Change S3 bucket? (y/N): " change_s3

        if [[ "$change_s3" =~ ^[Yy]$ ]]; then
            read -p "Enter new S3 bucket URL: " new_s3
            if [ -n "$new_s3" ]; then
                S3_BUCKET="$new_s3"
                echo -e "${GREEN}✓ Updated S3 bucket${NC}"
            else
                S3_BUCKET="$DEFAULT_S3_BUCKET"
                echo -e "${YELLOW}⊘ Keeping default${NC}"
            fi
        else
            S3_BUCKET="$DEFAULT_S3_BUCKET"
            echo -e "${GREEN}✓ Using default S3 bucket${NC}"
        fi
    fi
else
    # Non-interactive mode - apply defaults
    HOST=${HOST:-$DEFAULT_HOST}
    PORT=${PORT:-$DEFAULT_PORT}
    HTTP_PORT=${HTTP_PORT:-$DEFAULT_HTTP_PORT}
    USER=${USER:-$DEFAULT_USER}
    PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}
    DATABASE=${DATABASE:-$DEFAULT_DATABASE}
    SCALE_FACTOR=${SCALE_FACTOR:-$DEFAULT_SCALE_FACTOR}
    PARALLEL_JOBS=${PARALLEL_JOBS:-$DEFAULT_PARALLEL_JOBS}
    S3_BUCKET=${S3_BUCKET:-$DEFAULT_S3_BUCKET}
fi

# Display final configuration summary
echo ""
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                                  ║${NC}"
echo -e "${GREEN}║                ${BOLD}Configuration Summary${NC}${GREEN}                        ║${NC}"
echo -e "${GREEN}║                                                                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Connection:${NC}"
echo -e "  Host:              ${GREEN}${HOST}${NC}"
echo -e "  Native Port:       ${GREEN}${PORT}${NC}"
echo -e "  HTTP Port:         ${GREEN}${HTTP_PORT}${NC}"
echo -e "  User:              ${GREEN}${USER}${NC}"
echo -e "  Password:          ${RED}***NOT STORED IN CONFIG***${NC}"
echo -e "  Database:          ${GREEN}${DATABASE}${NC}"
echo ""
echo -e "${CYAN}Benchmark Settings:${NC}"
echo -e "  Scale Factor:      ${GREEN}${SCALE_FACTOR}${NC} (~$(echo "$SCALE_FACTOR * 1" | bc 2>/dev/null || echo "$SCALE_FACTOR")GB)"
echo -e "  Parallel Jobs:     ${GREEN}${PARALLEL_JOBS}${NC}"
echo ""
echo -e "${CYAN}Data Source:${NC}"
echo -e "  S3 Bucket:         ${GREEN}${S3_BUCKET:0:60}...${NC}"
echo ""
echo -e "${GREEN}──────────────────────────────────────────────────────────────────${NC}"
echo ""

# Final confirmation in interactive mode
if [ "$INTERACTIVE" = true ]; then
    read -p "💾 Save this configuration? (Y/n): " save_confirm
    if [[ "$save_confirm" =~ ^[Nn]$ ]]; then
        echo ""
        echo -e "${YELLOW}⊘ Configuration not saved. Exiting.${NC}"
        echo ""
        exit 0
    fi
fi

# Test connection if password provided
CONNECTION_OK=false
if [ -n "$PASSWORD" ]; then
    echo ""
    echo -e "${BLUE}🔌 Testing ClickHouse connection...${NC}"

    if clickhouse-client --host="$HOST" --port="$PORT" --user="$USER" --password="$PASSWORD" --query="SELECT version() AS version" 2>/dev/null; then
        echo -e "${GREEN}✓ Connection successful!${NC}"
        CONNECTION_OK=true
    else
        echo -e "${RED}✗ Connection failed!${NC}"

        if [ "$INTERACTIVE" = true ]; then
            echo ""
            read -p "Continue saving configuration anyway? (y/N): " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}⊘ Aborted.${NC}"
                exit 1
            fi
        fi
    fi
else
    echo -e "${YELLOW}⚠  Skipping connection test (no password provided)${NC}"
fi

# Generate config.sh
echo ""
echo -e "${BLUE}📝 Generating config.sh...${NC}"

cat > "$CONFIG_FILE" << 'CONFIGEOF'
#!/bin/bash

#################################################
# TPC-DS Benchmark Configuration
# Auto-generated by 00-set.sh on GENERATION_DATE
#
# IMPORTANT: Password is NOT stored in this file
# Set password via environment variable:
#   export CLICKHOUSE_PASSWORD='your-password'
#################################################

# ClickHouse Connection Settings
export CLICKHOUSE_HOST="PARAM_HOST"
export CLICKHOUSE_PORT="PARAM_PORT"
export CLICKHOUSE_HTTP_PORT="PARAM_HTTP_PORT"
export CLICKHOUSE_USER="PARAM_USER"
export CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-}"  # Set via environment variable
export CLICKHOUSE_DATABASE="PARAM_DATABASE"

# TPC-DS Data Generation Settings
export SCALE_FACTOR="PARAM_SCALE_FACTOR"
export DSDGEN_PATH="${DSDGEN_PATH:-./tpcds-kit/tools/dsdgen}"
export DATA_DIR="${DATA_DIR:-./data}"

# Query Execution Settings
export QUERIES_DIR="${QUERIES_DIR:-./queries}"
export RESULTS_DIR="${RESULTS_DIR:-./results}"
export PARALLEL_JOBS="PARAM_PARALLEL_JOBS"
export QUERY_ITERATIONS="${QUERY_ITERATIONS:-1}"

# S3 Data Source
export S3_BUCKET="PARAM_S3_BUCKET"

# ClickHouse Client Settings
export CLICKHOUSE_CLIENT="${CLICKHOUSE_CLIENT:-clickhouse-client}"
export CLICKHOUSE_CLIENT_OPTS="${CLICKHOUSE_CLIENT_OPTS:---send_logs_level=none}"

# Logging
export LOG_DIR="${LOG_DIR:-./logs}"
export VERBOSE="${VERBOSE:-false}"

#################################################
# Helper Functions
#################################################

test_connection() {
    echo "Testing ClickHouse connection..."
    $CLICKHOUSE_CLIENT \
        --host="$CLICKHOUSE_HOST" \
        --port="$CLICKHOUSE_PORT" \
        --user="$CLICKHOUSE_USER" \
        --password="$CLICKHOUSE_PASSWORD" \
        --query="SELECT version() AS version, uptime() AS uptime" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "Connection successful!"
        return 0
    else
        echo "Connection failed!"
        return 1
    fi
}

execute_query() {
    local query="$1"
    local database="${2:-$CLICKHOUSE_DATABASE}"

    $CLICKHOUSE_CLIENT \
        --host="$CLICKHOUSE_HOST" \
        --port="$CLICKHOUSE_PORT" \
        --user="$CLICKHOUSE_USER" \
        --password="$CLICKHOUSE_PASSWORD" \
        --database="$database" \
        $CLICKHOUSE_CLIENT_OPTS \
        --query="$query"
}

execute_sql_file() {
    local file="$1"
    local database="${2:-$CLICKHOUSE_DATABASE}"

    if [ ! -f "$file" ]; then
        echo "Error: SQL file not found: $file"
        return 1
    fi

    $CLICKHOUSE_CLIENT \
        --host="$CLICKHOUSE_HOST" \
        --port="$CLICKHOUSE_PORT" \
        --user="$CLICKHOUSE_USER" \
        --password="$CLICKHOUSE_PASSWORD" \
        --database="$database" \
        $CLICKHOUSE_CLIENT_OPTS \
        --queries-file="$file"
}

ensure_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo "Created directory: $dir"
    fi
}

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message"

    if [ "$VERBOSE" = "true" ] && [ -d "$LOG_DIR" ]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_DIR/benchmark.log"
    fi
}

initialize_directories() {
    ensure_directory "$DATA_DIR"
    ensure_directory "$RESULTS_DIR"
    ensure_directory "$LOG_DIR"
    ensure_directory "$QUERIES_DIR"
}

export -f test_connection
export -f execute_query
export -f execute_sql_file
export -f ensure_directory
export -f log
export -f initialize_directories

if [ "$VERBOSE" = "true" ]; then
    log "INFO" "Configuration loaded:"
    log "INFO" "  CLICKHOUSE_HOST: $CLICKHOUSE_HOST"
    log "INFO" "  CLICKHOUSE_PORT: $CLICKHOUSE_PORT"
    log "INFO" "  CLICKHOUSE_DATABASE: $CLICKHOUSE_DATABASE"
    log "INFO" "  SCALE_FACTOR: $SCALE_FACTOR"
fi
CONFIGEOF

# Replace placeholders
sed -i.tmp "s|GENERATION_DATE|$(date '+%Y-%m-%d %H:%M:%S')|g" "$CONFIG_FILE"
sed -i.tmp "s|PARAM_HOST|$HOST|g" "$CONFIG_FILE"
sed -i.tmp "s|PARAM_PORT|$PORT|g" "$CONFIG_FILE"
sed -i.tmp "s|PARAM_HTTP_PORT|$HTTP_PORT|g" "$CONFIG_FILE"
sed -i.tmp "s|PARAM_USER|$USER|g" "$CONFIG_FILE"
sed -i.tmp "s|PARAM_DATABASE|$DATABASE|g" "$CONFIG_FILE"
sed -i.tmp "s|PARAM_SCALE_FACTOR|$SCALE_FACTOR|g" "$CONFIG_FILE"
sed -i.tmp "s|PARAM_PARALLEL_JOBS|$PARALLEL_JOBS|g" "$CONFIG_FILE"
sed -i.tmp "s|PARAM_S3_BUCKET|$S3_BUCKET|g" "$CONFIG_FILE"
rm -f "$CONFIG_FILE.tmp"

chmod +x "$CONFIG_FILE"

echo -e "${GREEN}✓ Configuration saved to: $CONFIG_FILE${NC}"
echo ""

# Success message
if [ "$CONNECTION_OK" = true ]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║                    ${BOLD}✓ Setup Complete!${NC}${GREEN}                        ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}Next Steps:${NC}"
    echo ""
    echo -e "  ${YELLOW}1.${NC} Set password:    ${CYAN}export CLICKHOUSE_PASSWORD='your-password'${NC}"
    echo -e "  ${YELLOW}2.${NC} Create schema:   ${CYAN}./01-create-schema.sh${NC}"
    echo -e "  ${YELLOW}3.${NC} Load data:       ${CYAN}./03-load-data.sh --source s3${NC}"
    echo -e "  ${YELLOW}4.${NC} Run queries:     ${CYAN}./04-run-queries-sequential.sh${NC}"
    echo ""
    echo -e "  ${GREEN}Or run everything:${NC} ${CYAN}./run-all.sh${NC}"
else
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                                                                  ║${NC}"
    echo -e "${YELLOW}║              ${BOLD}⚠  Setup Complete (with warnings)${NC}${YELLOW}              ║${NC}"
    echo -e "${YELLOW}║                                                                  ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}⚠  Connection test failed or was skipped${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}Before running benchmark:${NC}"
    echo ""
    echo -e "  ${YELLOW}1.${NC} Verify ClickHouse is running"
    echo -e "  ${YELLOW}2.${NC} Check host and port: ${CYAN}clickhouse-client --host $HOST --port $PORT${NC}"
    echo -e "  ${YELLOW}3.${NC} Set password: ${CYAN}export CLICKHOUSE_PASSWORD='your-password'${NC}"
fi

echo ""
exit 0
