#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG_FILE="config-multi-catalog.env"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   Multi-Catalog Data Lake Setup${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Multi-catalog setup for Data Lake with MinIO and Multiple Catalogs
Run multiple catalogs simultaneously for testing and comparison

OPTIONS:
    --configure           Interactive configuration
    --start [catalogs]    Start services (all catalogs by default)
    --stop                Stop all services
    --clean               Clean all data
    --status              Show service status
    --help                Show this help

EXAMPLES:
    # Configure storage and ports
    $0 --configure

    # Start all services (MinIO + all catalogs)
    $0 --start

    # Start MinIO + specific catalogs
    $0 --start nessie unity

    # Stop all services
    $0 --stop

    # Check status
    $0 --status

AVAILABLE CATALOGS:
    - nessie       : Git-like catalog (port 19120)
    - hive         : Traditional Hive Metastore (port 9083)
    - iceberg      : Iceberg REST API (port 8181)
    - polaris      : Apache Polaris (ports 8182, 8183)
    - unity        : Unity Catalog (port 8080)
    - all          : Start all catalogs (default)

EOF
}

# Create default config if not exists
create_default_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << 'EOF'
# MinIO Configuration
MINIO_STORAGE_SIZE=20G
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=password123
MINIO_PORT=19000
MINIO_CONSOLE_PORT=19001

# Catalog Ports
NESSIE_PORT=19120
HIVE_METASTORE_PORT=9083
POSTGRES_PORT=5432
POSTGRES_PASSWORD=hive
ICEBERG_REST_PORT=8181
POLARIS_PORT=8182
POLARIS_MGMT_PORT=8183
UNITY_PORT=8080

# Sample Data
SAMPLE_DATA_BUCKET=warehouse
EOF
        echo -e "${GREEN}Created default configuration: $CONFIG_FILE${NC}"
    fi
}

configure() {
    echo -e "${YELLOW}Configuration Setup${NC}"
    echo ""

    read -p "Enter MinIO storage size (default: 20G): " storage_size
    storage_size=${storage_size:-20G}

    read -p "Enter MinIO API port (default: 19000): " minio_port
    minio_port=${minio_port:-19000}

    read -p "Enter MinIO Console port (default: 19001): " minio_console_port
    minio_console_port=${minio_console_port:-19001}

    echo ""
    echo -e "${YELLOW}Catalog Ports (press Enter to keep defaults):${NC}"

    read -p "Nessie port (default: 19120): " nessie_port
    nessie_port=${nessie_port:-19120}

    read -p "Hive Metastore port (default: 9083): " hive_port
    hive_port=${hive_port:-9083}

    read -p "Iceberg REST port (default: 8181): " iceberg_port
    iceberg_port=${iceberg_port:-8181}

    read -p "Polaris API port (default: 8182): " polaris_port
    polaris_port=${polaris_port:-8182}

    read -p "Polaris Management port (default: 8183): " polaris_mgmt_port
    polaris_mgmt_port=${polaris_mgmt_port:-8183}

    read -p "Unity Catalog port (default: 8080): " unity_port
    unity_port=${unity_port:-8080}

    # Write config
    cat > "$CONFIG_FILE" << EOF
# MinIO Configuration
MINIO_STORAGE_SIZE=$storage_size
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=password123
MINIO_PORT=$minio_port
MINIO_CONSOLE_PORT=$minio_console_port

# Catalog Ports
NESSIE_PORT=$nessie_port
HIVE_METASTORE_PORT=$hive_port
POSTGRES_PORT=5432
POSTGRES_PASSWORD=hive
ICEBERG_REST_PORT=$iceberg_port
POLARIS_PORT=$polaris_port
POLARIS_MGMT_PORT=$polaris_mgmt_port
UNITY_PORT=$unity_port

# Sample Data
SAMPLE_DATA_BUCKET=warehouse
EOF

    echo ""
    echo -e "${GREEN}Configuration saved to $CONFIG_FILE${NC}"
    echo ""
    echo -e "${BLUE}Configuration Summary:${NC}"
    echo "  MinIO API Port: $minio_port"
    echo "  MinIO Console Port: $minio_console_port"
    echo "  Nessie Port: $nessie_port"
    echo "  Hive Metastore Port: $hive_port"
    echo "  Iceberg REST Port: $iceberg_port"
    echo "  Polaris Ports: $polaris_port (API), $polaris_mgmt_port (Mgmt)"
    echo "  Unity Catalog Port: $unity_port"
    echo ""
}

start_services() {
    local catalogs="${1:-all}"

    source "$CONFIG_FILE"

    echo -e "${BLUE}Starting services...${NC}"

    # Determine which profile to use
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        DOCKER_COMPOSE="docker-compose"
    fi

    local profile_args=""

    if [ "$catalogs" = "all" ]; then
        echo -e "${GREEN}Starting MinIO + ALL catalogs${NC}"
        profile_args="--profile nessie --profile hive --profile iceberg-rest --profile polaris --profile unity"
    else
        echo -e "${GREEN}Starting MinIO + selected catalogs: $catalogs${NC}"
        for catalog in $catalogs; do
            case $catalog in
                nessie)
                    profile_args="$profile_args --profile nessie"
                    ;;
                hive)
                    profile_args="$profile_args --profile hive"
                    ;;
                iceberg)
                    profile_args="$profile_args --profile iceberg-rest"
                    ;;
                polaris)
                    profile_args="$profile_args --profile polaris"
                    ;;
                unity)
                    profile_args="$profile_args --profile unity"
                    ;;
                *)
                    echo -e "${RED}Unknown catalog: $catalog${NC}"
                    echo "Available: nessie, hive, iceberg, polaris, unity"
                    exit 1
                    ;;
            esac
        done
    fi

    # Create directories
    mkdir -p minio-storage sample-data notebooks

    # Start services
    $DOCKER_COMPOSE --env-file "$CONFIG_FILE" $profile_args up -d

    echo ""
    echo -e "${GREEN}Services started!${NC}"
    echo ""

    # Wait for services
    echo -e "${BLUE}Waiting for services to be ready...${NC}"

    echo -n "MinIO..."
    for i in {1..30}; do
        if curl -sf http://localhost:${MINIO_PORT:-19000}/minio/health/live > /dev/null 2>&1; then
            echo -e " ${GREEN}Ready!${NC}"
            break
        fi
        echo -n "."
        sleep 2
    done

    echo ""
    show_endpoints "$catalogs"
}

show_endpoints() {
    local catalogs="${1:-all}"
    source "$CONFIG_FILE"

    echo -e "${BLUE}============================================${NC}"
    echo -e "${GREEN}Service Endpoints${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    echo -e "${YELLOW}MinIO Object Storage:${NC}"
    echo "  Console: http://localhost:${MINIO_CONSOLE_PORT:-19001}"
    echo "  API: http://localhost:${MINIO_PORT:-19000}"
    echo "  Credentials: admin / password123"
    echo ""

    if [[ "$catalogs" == "all" ]] || [[ "$catalogs" == *"nessie"* ]]; then
        echo -e "${YELLOW}Nessie Catalog:${NC}"
        echo "  API: http://localhost:${NESSIE_PORT:-19120}/api/v2"
        echo "  UI: http://localhost:${NESSIE_PORT:-19120}"
        echo ""
    fi

    if [[ "$catalogs" == "all" ]] || [[ "$catalogs" == *"hive"* ]]; then
        echo -e "${YELLOW}Hive Metastore:${NC}"
        echo "  Thrift: thrift://localhost:${HIVE_METASTORE_PORT:-9083}"
        echo "  PostgreSQL: localhost:${POSTGRES_PORT:-5432}"
        echo ""
    fi

    if [[ "$catalogs" == "all" ]] || [[ "$catalogs" == *"iceberg"* ]]; then
        echo -e "${YELLOW}Iceberg REST:${NC}"
        echo "  API: http://localhost:${ICEBERG_REST_PORT:-8181}"
        echo ""
    fi

    if [[ "$catalogs" == "all" ]] || [[ "$catalogs" == *"polaris"* ]]; then
        echo -e "${YELLOW}Polaris:${NC}"
        echo "  API: http://localhost:${POLARIS_PORT:-8182}"
        echo "  Management: http://localhost:${POLARIS_MGMT_PORT:-8183}"
        echo ""
    fi

    if [[ "$catalogs" == "all" ]] || [[ "$catalogs" == *"unity"* ]]; then
        echo -e "${YELLOW}Unity Catalog:${NC}"
        echo "  API: http://localhost:${UNITY_PORT:-8080}"
        echo ""
    fi

    echo -e "${BLUE}============================================${NC}"
}

stop_services() {
    echo -e "${BLUE}Stopping all services...${NC}"

    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        DOCKER_COMPOSE="docker-compose"
    fi

    $DOCKER_COMPOSE --profile nessie --profile hive --profile iceberg-rest --profile polaris --profile unity down

    echo -e "${GREEN}All services stopped!${NC}"
}

clean_data() {
    echo -e "${YELLOW}This will remove all data. Are you sure? (y/N)${NC}"
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Cleaning up...${NC}"

        if docker compose version &> /dev/null; then
            DOCKER_COMPOSE="docker compose"
        else
            DOCKER_COMPOSE="docker-compose"
        fi

        $DOCKER_COMPOSE --profile nessie --profile hive --profile iceberg-rest --profile polaris --profile unity down -v
        rm -rf minio-storage/*

        echo -e "${GREEN}Cleanup complete!${NC}"
    else
        echo "Cancelled."
    fi
}

show_status() {
    echo -e "${BLUE}Service Status:${NC}"
    echo ""
    docker ps --filter "name=minio" --filter "name=nessie" --filter "name=hive" --filter "name=iceberg" --filter "name=polaris" --filter "name=unity" --filter "name=jupyter" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Main
case "${1:-}" in
    --configure)
        create_default_config
        configure
        ;;
    --start)
        create_default_config
        shift
        start_services "$*"
        ;;
    --stop)
        stop_services
        ;;
    --clean)
        clean_data
        ;;
    --status)
        show_status
        ;;
    --help|help)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
