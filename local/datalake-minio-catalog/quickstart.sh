#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}   Quick Start - Data Lake Setup${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Check Python
echo -e "${BLUE}Step 1/5: Checking prerequisites...${NC}"
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}Warning: Python 3 not found. Some scripts may not work.${NC}"
else
    echo -e "${GREEN}✓ Python 3 found${NC}"
fi

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found. Please install Docker first.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker found${NC}"
echo ""

# Install Python dependencies
echo -e "${BLUE}Step 2/5: Installing Python dependencies...${NC}"
if command -v python3 &> /dev/null; then
    python3 -m pip install -q -r requirements.txt || echo -e "${YELLOW}Warning: Some packages failed to install${NC}"
    echo -e "${GREEN}✓ Python dependencies installed${NC}"
fi
echo ""

# Generate sample data
echo -e "${BLUE}Step 3/5: Generating sample data...${NC}"
if [ -f "generate_parquet.py" ]; then
    python3 generate_parquet.py
    echo -e "${GREEN}✓ Sample data generated${NC}"
fi
echo ""

# Start services
echo -e "${BLUE}Step 4/5: Starting services (this may take a minute)...${NC}"
./setup.sh --start
echo ""

# Register data
echo -e "${BLUE}Step 5/5: Registering data with catalog...${NC}"
if [ -f "register_data.py" ]; then
    sleep 5  # Give services time to fully initialize
    python3 register_data.py || echo -e "${YELLOW}Warning: Data registration had issues${NC}"
fi
echo ""

# Success message
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   Setup Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Open MinIO Console: http://localhost:9001"
echo "  2. Open Jupyter: http://localhost:8888"
echo "  3. Check README.md for usage examples"
echo ""
echo "Useful commands:"
echo "  ./setup.sh --status     # Check service status"
echo "  ./setup.sh --endpoints  # Show all endpoints"
echo "  ./setup.sh --stop       # Stop all services"
echo ""
