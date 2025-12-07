#!/bin/bash

# Color codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}Restarting LibreChat services...${NC}"
docker-compose restart

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Services restarted successfully${NC}"
    echo ""
    echo "LibreChat: http://localhost:$(grep LIBRECHAT_PORT .env | cut -d'=' -f2)"
else
    echo -e "${RED}✗ Failed to restart services${NC}"
    exit 1
fi
