#!/bin/bash

# Colors
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           LibreChat Service Status                           ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

docker ps --filter "name=librechat" --filter "name=mcp-server" --filter "name=mongo" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
