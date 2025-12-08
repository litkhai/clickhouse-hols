#!/bin/bash

# Color codes
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Stopping LibreChat services...${NC}"
docker compose down

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Services stopped successfully${NC}"
else
    echo -e "${RED}✗ Failed to stop services${NC}"
    exit 1
fi
