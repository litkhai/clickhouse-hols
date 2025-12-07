#!/bin/bash

# Color codes
BLUE='\033[0;34m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${BLUE}Showing logs for all services (Ctrl+C to exit)...${NC}"
    echo ""
    docker-compose logs -f
else
    echo -e "${BLUE}Showing logs for $1 (Ctrl+C to exit)...${NC}"
    echo ""
    docker-compose logs -f "$1"
fi
