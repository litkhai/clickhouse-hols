#!/bin/bash

#################################################
# TPC-DS Environment Setup Script
# Generates config.sh from parameters
#################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default values
DEFAULT_HOST="localhost"
DEFAULT_PORT="9000"
DEFAULT_HTTP_PORT="8123"
DEFAULT_USER="default"
DEFAULT_PASSWORD=""
DEFAULT_DATABASE="tpcds"
DEFAULT_SCALE_FACTOR="1"
DEFAULT_PARALLEL_JOBS="4"
DEFAULT_S3_BUCKET="https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Generate config.sh with ClickHouse connection parameters.

OPTIONS:
    -h, --host HOST           ClickHouse host (default: $DEFAULT_HOST)
    -p, --port PORT           ClickHouse native port (default: $DEFAULT_PORT)
    --http-port PORT          ClickHouse HTTP port (default: $DEFAULT_HTTP_PORT)
    -u, --user USER           ClickHouse user (default: $DEFAULT_USER)
    -P, --password PASSWORD   ClickHouse password (default: empty)
    -d, --database DATABASE   Database name (default: $DEFAULT_DATABASE)
    -s, --scale-factor N      Data scale factor (default: $DEFAULT_SCALE_FACTOR)
    -j, --parallel N          Parallel jobs (default: $DEFAULT_PARALLEL_JOBS)
    --s3-bucket URL          S3 bucket URL (default: Tokyo bucket)
    --interactive            Interactive mode - prompt for all values
    --docker                 Use Docker container settings
    --help                   Show this help message

EXAMPLES:
    # Generate config with defaults
    $0

    # Generate config for remote server
    $0 --host 10.0.1.100 --port 9000 --user admin --password secret

    # Interactive mode
    $0 --interactive

    # Docker mode
    $0 --docker

    # Custom scale factor and parallelism
    $0 --scale-factor 10 --parallel 8

    # Complete custom setup
    $0 -h myserver.com -p 9000 -u myuser -P mypass -d tpcds_prod -s 100 -j 16

EOF
    exit 1
}

# Parse arguments
INTERACTIVE=false
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

# Interactive mode
if [ "$INTERACTIVE" = true ]; then
    echo "========================================"
    echo "TPC-DS Interactive Configuration"
    echo "========================================"
    echo ""

    read -p "ClickHouse host [$DEFAULT_HOST]: " HOST
    HOST=${HOST:-$DEFAULT_HOST}

    read -p "ClickHouse native port [$DEFAULT_PORT]: " PORT
    PORT=${PORT:-$DEFAULT_PORT}

    read -p "ClickHouse HTTP port [$DEFAULT_HTTP_PORT]: " HTTP_PORT
    HTTP_PORT=${HTTP_PORT:-$DEFAULT_HTTP_PORT}

    read -p "ClickHouse user [$DEFAULT_USER]: " USER
    USER=${USER:-$DEFAULT_USER}

    read -s -p "ClickHouse password [empty]: " PASSWORD
    echo ""

    read -p "Database name [$DEFAULT_DATABASE]: " DATABASE
    DATABASE=${DATABASE:-$DEFAULT_DATABASE}

    read -p "Scale factor (1=1GB, 10=10GB, 100=100GB) [$DEFAULT_SCALE_FACTOR]: " SCALE_FACTOR
    SCALE_FACTOR=${SCALE_FACTOR:-$DEFAULT_SCALE_FACTOR}

    read -p "Parallel jobs [$DEFAULT_PARALLEL_JOBS]: " PARALLEL_JOBS
    PARALLEL_JOBS=${PARALLEL_JOBS:-$DEFAULT_PARALLEL_JOBS}

    read -p "S3 bucket URL [$DEFAULT_S3_BUCKET]: " S3_BUCKET
    S3_BUCKET=${S3_BUCKET:-$DEFAULT_S3_BUCKET}
fi

# Docker mode - use Docker container settings
if [ "$DOCKER" = true ]; then
    echo "Using Docker container settings..."
    HOST=${HOST:-"clickhouse-server"}
    PORT=${PORT:-"9000"}
    HTTP_PORT=${HTTP_PORT:-"8123"}
    USER=${USER:-"default"}
    PASSWORD=${PASSWORD:-""}
    DATABASE=${DATABASE:-"tpcds"}
    SCALE_FACTOR=${SCALE_FACTOR:-"1"}
    PARALLEL_JOBS=${PARALLEL_JOBS:-"4"}
    S3_BUCKET=${S3_BUCKET:-"$DEFAULT_S3_BUCKET"}
fi

# Apply defaults for any unset values
HOST=${HOST:-$DEFAULT_HOST}
PORT=${PORT:-$DEFAULT_PORT}
HTTP_PORT=${HTTP_PORT:-$DEFAULT_HTTP_PORT}
USER=${USER:-$DEFAULT_USER}
PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}
DATABASE=${DATABASE:-$DEFAULT_DATABASE}
SCALE_FACTOR=${SCALE_FACTOR:-$DEFAULT_SCALE_FACTOR}
PARALLEL_JOBS=${PARALLEL_JOBS:-$DEFAULT_PARALLEL_JOBS}
S3_BUCKET=${S3_BUCKET:-$DEFAULT_S3_BUCKET}

# Display configuration
echo ""
echo "========================================"
echo "Generating TPC-DS Configuration"
echo "========================================"
echo "Host:           $HOST"
echo "Native Port:    $PORT"
echo "HTTP Port:      $HTTP_PORT"
echo "User:           $USER"
echo "Password:       $([ -n "$PASSWORD" ] && echo '***' || echo '(empty)')"
echo "Database:       $DATABASE"
echo "Scale Factor:   $SCALE_FACTOR"
echo "Parallel Jobs:  $PARALLEL_JOBS"
echo "S3 Bucket:      $S3_BUCKET"
echo ""

# Test connection
echo "Testing ClickHouse connection..."
TEST_CMD="clickhouse-client --host=\"$HOST\" --port=\"$PORT\" --user=\"$USER\""
[ -n "$PASSWORD" ] && TEST_CMD="$TEST_CMD --password=\"$PASSWORD\""
TEST_CMD="$TEST_CMD --query=\"SELECT version() AS version\""

if eval "$TEST_CMD" 2>/dev/null; then
    echo "✓ Connection successful!"
    CONNECTION_OK=true
else
    echo "✗ Connection failed!"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    CONNECTION_OK=false
fi

# Generate config.sh
CONFIG_FILE="$SCRIPT_DIR/config.sh"

cat > "$CONFIG_FILE" << EOF
#!/bin/bash

#################################################
# TPC-DS Benchmark Configuration
# Auto-generated by 00-set.sh on $(date '+%Y-%m-%d %H:%M:%S')
#################################################

# ClickHouse Connection Settings
export CLICKHOUSE_HOST="${HOST}"
export CLICKHOUSE_PORT="${PORT}"
export CLICKHOUSE_HTTP_PORT="${HTTP_PORT}"
export CLICKHOUSE_USER="${USER}"
export CLICKHOUSE_PASSWORD="${PASSWORD}"
export CLICKHOUSE_DATABASE="${DATABASE}"

# TPC-DS Data Generation Settings
export SCALE_FACTOR="${SCALE_FACTOR}"
export DSDGEN_PATH="\${DSDGEN_PATH:-./tpcds-kit/tools/dsdgen}"
export DATA_DIR="\${DATA_DIR:-./data}"

# Query Execution Settings
export QUERIES_DIR="\${QUERIES_DIR:-./queries}"
export RESULTS_DIR="\${RESULTS_DIR:-./results}"
export PARALLEL_JOBS="${PARALLEL_JOBS}"
export QUERY_ITERATIONS="\${QUERY_ITERATIONS:-1}"

# S3 Data Source (alternative to local generation)
export S3_BUCKET="${S3_BUCKET}"

# ClickHouse Client Settings
export CLICKHOUSE_CLIENT="\${CLICKHOUSE_CLIENT:-clickhouse-client}"
export CLICKHOUSE_CLIENT_OPTS="\${CLICKHOUSE_CLIENT_OPTS:---send_logs_level=none}"

# Logging
export LOG_DIR="\${LOG_DIR:-./logs}"
export VERBOSE="\${VERBOSE:-false}"

#################################################
# Helper Functions
#################################################

# Function to test ClickHouse connection
test_connection() {
    echo "Testing ClickHouse connection..."
    \$CLICKHOUSE_CLIENT \\
        --host="\$CLICKHOUSE_HOST" \\
        --port="\$CLICKHOUSE_PORT" \\
        --user="\$CLICKHOUSE_USER" \\
        --password="\$CLICKHOUSE_PASSWORD" \\
        --query="SELECT version() AS version, uptime() AS uptime" 2>/dev/null

    if [ \$? -eq 0 ]; then
        echo "Connection successful!"
        return 0
    else
        echo "Connection failed!"
        return 1
    fi
}

# Function to execute ClickHouse query
execute_query() {
    local query="\$1"
    local database="\${2:-\$CLICKHOUSE_DATABASE}"

    \$CLICKHOUSE_CLIENT \\
        --host="\$CLICKHOUSE_HOST" \\
        --port="\$CLICKHOUSE_PORT" \\
        --user="\$CLICKHOUSE_USER" \\
        --password="\$CLICKHOUSE_PASSWORD" \\
        --database="\$database" \\
        \$CLICKHOUSE_CLIENT_OPTS \\
        --query="\$query"
}

# Function to execute SQL file
execute_sql_file() {
    local file="\$1"
    local database="\${2:-\$CLICKHOUSE_DATABASE}"

    if [ ! -f "\$file" ]; then
        echo "Error: SQL file not found: \$file"
        return 1
    fi

    \$CLICKHOUSE_CLIENT \\
        --host="\$CLICKHOUSE_HOST" \\
        --port="\$CLICKHOUSE_PORT" \\
        --user="\$CLICKHOUSE_USER" \\
        --password="\$CLICKHOUSE_PASSWORD" \\
        --database="\$database" \\
        \$CLICKHOUSE_CLIENT_OPTS \\
        --queries-file="\$file"
}

# Function to create directory if it doesn't exist
ensure_directory() {
    local dir="\$1"
    if [ ! -d "\$dir" ]; then
        mkdir -p "\$dir"
        echo "Created directory: \$dir"
    fi
}

# Function to log message
log() {
    local level="\$1"
    shift
    local message="\$@"
    local timestamp=\$(date '+%Y-%m-%d %H:%M:%S')

    echo "[\$timestamp] [\$level] \$message"

    if [ "\$VERBOSE" = "true" ] && [ -d "\$LOG_DIR" ]; then
        echo "[\$timestamp] [\$level] \$message" >> "\$LOG_DIR/benchmark.log"
    fi
}

# Initialize directories
initialize_directories() {
    ensure_directory "\$DATA_DIR"
    ensure_directory "\$RESULTS_DIR"
    ensure_directory "\$LOG_DIR"
    ensure_directory "\$QUERIES_DIR"
}

# Export functions for use in other scripts
export -f test_connection
export -f execute_query
export -f execute_sql_file
export -f ensure_directory
export -f log
export -f initialize_directories

# Print configuration if verbose
if [ "\$VERBOSE" = "true" ]; then
    log "INFO" "Configuration loaded:"
    log "INFO" "  CLICKHOUSE_HOST: \$CLICKHOUSE_HOST"
    log "INFO" "  CLICKHOUSE_PORT: \$CLICKHOUSE_PORT"
    log "INFO" "  CLICKHOUSE_DATABASE: \$CLICKHOUSE_DATABASE"
    log "INFO" "  SCALE_FACTOR: \$SCALE_FACTOR"
    log "INFO" "  DATA_DIR: \$DATA_DIR"
    log "INFO" "  QUERIES_DIR: \$QUERIES_DIR"
    log "INFO" "  RESULTS_DIR: \$RESULTS_DIR"
fi
EOF

chmod +x "$CONFIG_FILE"

echo ""
echo "========================================"
echo "Configuration Generated Successfully"
echo "========================================"
echo "Config file: $CONFIG_FILE"
echo ""

if [ "$CONNECTION_OK" = true ]; then
    echo "✓ Ready to run TPC-DS benchmark!"
    echo ""
    echo "Next steps:"
    echo "  1. Create schema:    ./01-create-schema.sh"
    echo "  2. Load data:        ./03-load-data.sh --source s3"
    echo "  3. Run queries:      ./04-run-queries-sequential.sh"
    echo ""
    echo "Or run everything:    ./run-all.sh"
else
    echo "⚠ Warning: Connection test failed"
    echo ""
    echo "Please verify:"
    echo "  - ClickHouse server is running"
    echo "  - Host and port are correct"
    echo "  - User credentials are valid"
    echo ""
    echo "Test connection manually:"
    echo "  clickhouse-client --host $HOST --port $PORT --user $USER"
fi

echo ""

exit 0
