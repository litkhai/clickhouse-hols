#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration file
CONFIG_FILE="config.env"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}   Data Lake Setup with MinIO and Catalog${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Function to prompt for configuration
configure_setup() {
    echo -e "${YELLOW}Configuration Setup${NC}"
    echo ""

    # MinIO Storage Size
    read -p "Enter MinIO storage size (default: 20G): " storage_size
    storage_size=${storage_size:-20G}
    sed -i.bak "s/MINIO_STORAGE_SIZE=.*/MINIO_STORAGE_SIZE=$storage_size/" "$CONFIG_FILE"

    # MinIO Port Configuration
    echo ""
    echo -e "${YELLOW}MinIO Port Configuration:${NC}"
    echo "Default ports: 19000 (API), 19001 (Console)"
    echo "Note: These ports are compatible with ClickHouse 25.8 lab"
    read -p "Enter MinIO API port (default: 19000): " minio_port
    minio_port=${minio_port:-19000}
    sed -i.bak "s/MINIO_PORT=.*/MINIO_PORT=$minio_port/" "$CONFIG_FILE"

    read -p "Enter MinIO Console port (default: 19001): " minio_console_port
    minio_console_port=${minio_console_port:-19001}
    sed -i.bak "s/MINIO_CONSOLE_PORT=.*/MINIO_CONSOLE_PORT=$minio_console_port/" "$CONFIG_FILE"

    # Catalog Type Selection
    echo ""
    echo "Select Data Catalog Type:"
    echo "1) Nessie (Default - Modern, Git-like catalog)"
    echo "2) Hive Metastore (Traditional, widely supported)"
    echo "3) Iceberg REST Catalog (Standard REST API)"
    echo "4) Polaris (Apache Polaris - Open source catalog for Apache Iceberg)"
    echo "5) Unity Catalog (Databricks Unity Catalog)"
    read -p "Enter selection (1-5, default: 1): " catalog_choice
    catalog_choice=${catalog_choice:-1}

    case $catalog_choice in
        1)
            catalog_type="nessie"
            # Configure Nessie port
            read -p "Enter Nessie port (default: 19120): " nessie_port
            nessie_port=${nessie_port:-19120}
            sed -i.bak "s/NESSIE_PORT=.*/NESSIE_PORT=$nessie_port/" "$CONFIG_FILE"
            ;;
        2)
            catalog_type="hive"
            # Configure Hive ports
            read -p "Enter Hive Metastore port (default: 9083): " hive_port
            hive_port=${hive_port:-9083}
            sed -i.bak "s/HIVE_METASTORE_PORT=.*/HIVE_METASTORE_PORT=$hive_port/" "$CONFIG_FILE"

            read -p "Enter PostgreSQL port (default: 5432): " postgres_port
            postgres_port=${postgres_port:-5432}
            sed -i.bak "s/POSTGRES_PORT=.*/POSTGRES_PORT=$postgres_port/" "$CONFIG_FILE"
            ;;
        3)
            catalog_type="iceberg-rest"
            # Configure Iceberg REST port
            read -p "Enter Iceberg REST port (default: 8181): " iceberg_port
            iceberg_port=${iceberg_port:-8181}
            sed -i.bak "s/ICEBERG_REST_PORT=.*/ICEBERG_REST_PORT=$iceberg_port/" "$CONFIG_FILE"
            ;;
        4)
            catalog_type="polaris"
            # Configure Polaris ports
            read -p "Enter Polaris API port (default: 8182): " polaris_port
            polaris_port=${polaris_port:-8182}
            sed -i.bak "s/POLARIS_PORT=.*/POLARIS_PORT=$polaris_port/" "$CONFIG_FILE"

            read -p "Enter Polaris Management port (default: 8183): " polaris_mgmt_port
            polaris_mgmt_port=${polaris_mgmt_port:-8183}
            sed -i.bak "s/POLARIS_MGMT_PORT=.*/POLARIS_MGMT_PORT=$polaris_mgmt_port/" "$CONFIG_FILE"
            ;;
        5)
            catalog_type="unity"
            # Configure Unity Catalog ports
            read -p "Enter Unity Catalog port (default: 8080): " unity_port
            unity_port=${unity_port:-8080}
            sed -i.bak "s/UNITY_PORT=.*/UNITY_PORT=$unity_port/" "$CONFIG_FILE"
            ;;
        *)
            echo -e "${YELLOW}Invalid selection, using Nessie as default${NC}"
            catalog_type="nessie"
            sed -i.bak "s/NESSIE_PORT=.*/NESSIE_PORT=19120/" "$CONFIG_FILE"
            ;;
    esac

    sed -i.bak "s/CATALOG_TYPE=.*/CATALOG_TYPE=$catalog_type/" "$CONFIG_FILE"

    # Clean up backup files
    rm -f "${CONFIG_FILE}.bak"

    echo ""
    echo -e "${GREEN}Configuration saved!${NC}"
    echo ""
    echo -e "${BLUE}Configuration Summary:${NC}"
    echo "  Storage Size: $storage_size"
    echo "  MinIO API Port: $minio_port"
    echo "  MinIO Console Port: $minio_console_port"
    echo "  Catalog Type: $catalog_type"

    case $catalog_type in
        nessie)
            echo "  Nessie Port: ${nessie_port:-19120}"
            ;;
        hive)
            echo "  Hive Metastore Port: ${hive_port:-9083}"
            echo "  PostgreSQL Port: ${postgres_port:-5432}"
            ;;
        iceberg-rest)
            echo "  Iceberg REST Port: ${iceberg_port:-8181}"
            ;;
        polaris)
            echo "  Polaris API Port: ${polaris_port:-8182}"
            echo "  Polaris Management Port: ${polaris_mgmt_port:-8183}"
            ;;
        unity)
            echo "  Unity Catalog Port: ${unity_port:-8080}"
            ;;
    esac
    echo ""
}

# Function to create directory structure
create_directories() {
    echo -e "${BLUE}Creating directory structure...${NC}"
    mkdir -p minio-storage
    mkdir -p notebooks
    mkdir -p sample-data
    echo -e "${GREEN}Directories created!${NC}"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"

    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker is not installed${NC}"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo -e "${RED}Error: Docker Compose is not installed${NC}"
        exit 1
    fi

    echo -e "${GREEN}Prerequisites check passed!${NC}"
    echo ""
}

# Function to start services
start_services() {
    echo -e "${BLUE}Starting services...${NC}"

    # Load configuration
    source "$CONFIG_FILE"

    # Determine which profile to use
    local compose_profiles="--profile $CATALOG_TYPE"

    # Check if docker compose (v2) or docker-compose (v1) is available
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        DOCKER_COMPOSE="docker-compose"
    fi

    # Start services
    $DOCKER_COMPOSE --env-file "$CONFIG_FILE" $compose_profiles up -d

    echo ""
    echo -e "${GREEN}Services started!${NC}"
    echo ""
}

# Function to wait for services
wait_for_services() {
    echo -e "${BLUE}Waiting for services to be ready...${NC}"

    # Wait for MinIO
    echo -n "Waiting for MinIO..."
    for i in {1..30}; do
        if curl -s http://localhost:${MINIO_PORT:-9000}/minio/health/live > /dev/null 2>&1; then
            echo -e " ${GREEN}Ready!${NC}"
            break
        fi
        echo -n "."
        sleep 2
    done

    # Wait for catalog service
    source "$CONFIG_FILE"
    case $CATALOG_TYPE in
        nessie)
            echo -n "Waiting for Nessie..."
            for i in {1..30}; do
                if curl -s http://localhost:${NESSIE_PORT:-19120}/api/v2/config > /dev/null 2>&1; then
                    echo -e " ${GREEN}Ready!${NC}"
                    break
                fi
                echo -n "."
                sleep 2
            done
            ;;
        hive)
            echo "Waiting for Hive Metastore (this may take a minute)..."
            sleep 30
            ;;
        iceberg-rest)
            echo -n "Waiting for Iceberg REST..."
            for i in {1..30}; do
                if curl -s http://localhost:${ICEBERG_REST_PORT:-8181}/v1/config > /dev/null 2>&1; then
                    echo -e " ${GREEN}Ready!${NC}"
                    break
                fi
                echo -n "."
                sleep 2
            done
            ;;
        polaris)
            echo -n "Waiting for Polaris..."
            for i in {1..30}; do
                if curl -s http://localhost:${POLARIS_PORT:-8182}/health > /dev/null 2>&1; then
                    echo -e " ${GREEN}Ready!${NC}"
                    break
                fi
                echo -n "."
                sleep 2
            done
            ;;
        unity)
            echo -n "Waiting for Unity Catalog..."
            for i in {1..30}; do
                if curl -s http://localhost:${UNITY_PORT:-8080}/api/2.1/unity-catalog/catalogs > /dev/null 2>&1; then
                    echo -e " ${GREEN}Ready!${NC}"
                    break
                fi
                echo -n "."
                sleep 2
            done
            ;;
    esac

    echo ""
}

# Function to display endpoints
show_endpoints() {
    source "$CONFIG_FILE"

    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}Service Endpoints${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""

    echo -e "${YELLOW}MinIO Object Storage:${NC}"
    echo "  Console UI: http://localhost:${MINIO_CONSOLE_PORT:-9001}"
    echo "  API Endpoint: http://localhost:${MINIO_PORT:-9000}"
    echo "  Access Key: ${MINIO_ROOT_USER:-admin}"
    echo "  Secret Key: ${MINIO_ROOT_PASSWORD:-password123}"
    echo ""

    case $CATALOG_TYPE in
        nessie)
            echo -e "${YELLOW}Nessie Catalog:${NC}"
            echo "  API Endpoint: http://localhost:${NESSIE_PORT:-19120}/api/v2"
            echo "  UI: http://localhost:${NESSIE_PORT:-19120}"
            ;;
        hive)
            echo -e "${YELLOW}Hive Metastore:${NC}"
            echo "  Thrift URI: thrift://localhost:${HIVE_METASTORE_PORT:-9083}"
            echo "  PostgreSQL: localhost:${POSTGRES_PORT:-5432}"
            echo "  Database: metastore"
            echo "  User: hive"
            ;;
        iceberg-rest)
            echo -e "${YELLOW}Iceberg REST Catalog:${NC}"
            echo "  API Endpoint: http://localhost:${ICEBERG_REST_PORT:-8181}"
            ;;
        polaris)
            echo -e "${YELLOW}Polaris Catalog:${NC}"
            echo "  API Endpoint: http://localhost:${POLARIS_PORT:-8182}"
            echo "  Management API: http://localhost:${POLARIS_MGMT_PORT:-8183}"
            echo "  Admin Credentials: realm=default-realm, client-id=admin, client-secret=polaris"
            ;;
        unity)
            echo -e "${YELLOW}Unity Catalog:${NC}"
            echo "  API Endpoint: http://localhost:${UNITY_PORT:-8080}"
            echo "  API Version: 2.1"
            ;;
    esac

    echo ""
    echo -e "${YELLOW}Jupyter Notebook:${NC}"
    echo "  URL: http://localhost:8888"
    echo "  (No password required)"
    echo ""

    echo -e "${BLUE}================================================${NC}"
    echo ""
}

# Main execution
main() {
    case "${1:-}" in
        --configure)
            configure_setup
            ;;
        --start)
            check_prerequisites
            create_directories
            start_services
            wait_for_services
            show_endpoints
            ;;
        --stop)
            source "$CONFIG_FILE"
            if docker compose version &> /dev/null; then
                docker compose --profile "$CATALOG_TYPE" down
            else
                docker-compose --profile "$CATALOG_TYPE" down
            fi
            echo -e "${GREEN}Services stopped!${NC}"
            ;;
        --restart)
            $0 --stop
            sleep 5
            $0 --start
            ;;
        --clean)
            source "$CONFIG_FILE"
            if docker compose version &> /dev/null; then
                docker compose --profile "$CATALOG_TYPE" down -v
            else
                docker-compose --profile "$CATALOG_TYPE" down -v
            fi
            echo -e "${YELLOW}Cleaning up data directories...${NC}"
            rm -rf minio-storage/*
            echo -e "${GREEN}Cleanup complete!${NC}"
            ;;
        --status)
            docker ps --filter "name=minio" --filter "name=nessie" --filter "name=hive" --filter "name=iceberg" --filter "name=polaris" --filter "name=unity" --filter "name=jupyter"
            ;;
        --endpoints)
            show_endpoints
            ;;
        *)
            echo "Usage: $0 [OPTION]"
            echo ""
            echo "Options:"
            echo "  --configure    Configure the setup (storage size, catalog type)"
            echo "  --start        Start all services"
            echo "  --stop         Stop all services"
            echo "  --restart      Restart all services"
            echo "  --clean        Stop services and remove all data"
            echo "  --status       Show running services"
            echo "  --endpoints    Show service endpoints"
            echo ""
            echo "Quick Start:"
            echo "  1. $0 --configure"
            echo "  2. $0 --start"
            echo ""
            exit 1
            ;;
    esac
}

main "$@"
