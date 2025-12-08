#!/bin/bash

# Color codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}LibreChat Service Status${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check Docker
if ! docker info &> /dev/null; then
    echo -e "${RED}✗ Docker is not running${NC}"
    exit 1
fi

# Check containers
echo -e "${CYAN}Container Status:${NC}"
docker compose ps

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check if LibreChat is accessible
LIBRECHAT_PORT=$(grep LIBRECHAT_PORT .env | cut -d'=' -f2)
if curl -s http://localhost:${LIBRECHAT_PORT} > /dev/null; then
    echo -e "${GREEN}✓ LibreChat is accessible at http://localhost:${LIBRECHAT_PORT}${NC}"
else
    echo -e "${YELLOW}⚠ LibreChat is not responding yet (may still be initializing)${NC}"
fi

echo ""

# Check Ollama
if command -v ollama &> /dev/null; then
    echo -e "${CYAN}Ollama Models:${NC}"
    ollama list | grep llama3.1:8b || echo -e "${YELLOW}⚠ llama3.1:8b not found${NC}"
else
    echo -e "${YELLOW}⚠ Ollama not installed${NC}"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
