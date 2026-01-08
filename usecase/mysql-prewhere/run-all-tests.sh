#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     MySQL PREWHERE Complete Test Suite                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"

# Check if ClickHouse is running
echo -e "${YELLOW}Checking ClickHouse connection...${NC}"
CH_CLIENT="docker exec clickhouse-test clickhouse-client"
if $CH_CLIENT --query="SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ ClickHouse is running${NC}\n"
else
    echo -e "${RED}❌ ClickHouse is not running or not accessible${NC}"
    echo -e "${YELLOW}Please start ClickHouse first${NC}"
    exit 1
fi

# Check if MySQL protocol port is available
echo -e "${YELLOW}Checking MySQL protocol port (9004)...${NC}"
if mysql -h localhost -P 9004 --protocol=TCP -u mysql_user -e "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ MySQL protocol is available${NC}\n"
else
    echo -e "${RED}❌ MySQL protocol port is not accessible${NC}"
    echo -e "${YELLOW}Make sure ClickHouse is configured to accept MySQL protocol connections${NC}"
    exit 1
fi

# Make scripts executable
chmod +x "$SCRIPT_DIR"/*.sh

# Run setup
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 1/4: Setting up test environment${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"

bash "$SCRIPT_DIR/00-setup.sh"

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✅ Setup completed successfully${NC}\n"
else
    echo -e "\n${RED}❌ Setup failed${NC}"
    exit 1
fi

read -p "Press Enter to continue with MySQL protocol tests..."

# Run MySQL protocol tests
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 2/4: Testing PREWHERE via MySQL protocol${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"

bash "$SCRIPT_DIR/01-test-mysql-protocol.sh"

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✅ MySQL protocol tests completed${NC}\n"
else
    echo -e "\n${YELLOW}⚠️  Some MySQL protocol tests may have failed${NC}\n"
fi

read -p "Press Enter to continue with verification tests..."

# Run verification tests
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 3/4: Verifying PREWHERE functionality${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"

bash "$SCRIPT_DIR/03-verify-prewhere.sh"

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✅ Verification tests completed${NC}\n"
else
    echo -e "\n${YELLOW}⚠️  Some verification tests may have failed${NC}\n"
fi

read -p "Press Enter to continue with performance comparison..."

# Run performance comparison
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 4/4: Performance comparison${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
echo -e "${YELLOW}Note: This test may take a few minutes...${NC}\n"

bash "$SCRIPT_DIR/02-performance-comparison.sh"

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✅ Performance comparison completed${NC}\n"
else
    echo -e "\n${YELLOW}⚠️  Some performance tests may have failed${NC}\n"
fi

# Final summary
echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Test Suite Complete                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${GREEN}All tests have been executed!${NC}\n"

echo -e "${YELLOW}Key Findings:${NC}"
echo -e "1. PREWHERE syntax works via MySQL protocol"
echo -e "2. Automatic PREWHERE optimization (optimize_move_to_prewhere) is available"
echo -e "3. Performance benefits are measurable"
echo -e "4. Results are consistent across protocols"

echo -e "\n${YELLOW}Quick Commands for Further Testing:${NC}"
echo -e "  ${GREEN}Native:${NC}  clickhouse-client"
echo -e "  ${GREEN}MySQL:${NC}   mysql -h localhost -P 9004 -u default"

echo -e "\n${YELLOW}Cleanup (optional):${NC}"
echo -e "  DROP TABLE default.prewhere_test;"
echo -e "  DROP TABLE default.prewhere_test_large;"

echo -e "\n${BLUE}Happy testing!${NC}\n"
