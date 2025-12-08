#!/bin/bash

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Starting LibreChat services...${NC}"
docker compose up -d

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Services started successfully${NC}"
    echo ""
    echo "LibreChat: http://localhost:$(grep LIBRECHAT_PORT .env | cut -d'=' -f2)"
else
    echo -e "${RED}✗ Failed to start services${NC}"
    exit 1
fi
