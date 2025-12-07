#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}[INFO]${NC} Stopping LibreChat services..."

# Check if docker compose or docker-compose
if docker compose version &> /dev/null; then
    docker compose down
else
    docker-compose down
fi

echo -e "${GREEN}[SUCCESS]${NC} All services stopped"
